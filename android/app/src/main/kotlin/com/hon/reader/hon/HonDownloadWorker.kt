package com.hon.reader.hon

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import com.hon.reader.hon.shosetsu.SourceHttpClient
import com.hon.reader.hon.shosetsu.SourceHttpException
import kotlinx.coroutines.CancellationException
import com.hon.reader.hon.shosetsu.SourcePreferenceStore
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.runBlocking
import okhttp3.Call
import okhttp3.EventListener
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

class HonDownloadWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    companion object {
        private val locks = ConcurrentHashMap<String, Mutex>()
        private val activeCalls = ConcurrentHashMap<String, MutableSet<Call>>()
        fun stopAndAwait(jobId:String) {
            activeCalls[jobId]?.toList()?.forEach { it.cancel() }
            // File replacement and rollback finish before pause/export is acknowledged.
            runBlocking { locks[jobId]?.withLock { } }
        }
    }
    private val trackedCalls = ConcurrentHashMap.newKeySet<Call>()
    private fun isCurrentAttempt(jobId: String): Boolean = !isStopped &&
        context.getSharedPreferences("hon_download_tokens", Context.MODE_PRIVATE).getString(jobId, null) == id.toString()

    private val httpClient = SourceHttpClient.create(context, inputData.getString("sourceId") ?: "gutenberg").newBuilder()
        .eventListener(object : EventListener() {
            override fun callStart(call:Call) {
                trackedCalls.add(call)
                if (!isCurrentAttempt(inputData.getString("jobId") ?: "")) call.cancel()
            }
            override fun callEnd(call:Call) { trackedCalls.remove(call) }
            override fun callFailed(call:Call, error:IOException) { trackedCalls.remove(call) }
        })
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS)
        .build()



    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val jobId = inputData.getString("jobId")
        val url = inputData.getString("url")
        val targetPath = inputData.getString("targetPath")
        val bookId = inputData.getString("bookId")
        val chapterId = inputData.getString("chapterId")
        val sourceId = inputData.getString("sourceId") ?: "gutenberg"

        if (jobId == "RECOVER_ALL") return@withContext Result.success()

        if (jobId.isNullOrBlank() || url.isNullOrBlank() || targetPath.isNullOrBlank()) {
            return@withContext Result.failure()
        }

        val wifiOnly = inputData.getBoolean("wifiOnly", false)
        if (wifiOnly) {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
            val active = cm?.activeNetwork
            val caps = cm?.getNetworkCapabilities(active)
            val isUnmetered = caps?.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == true
            if (!isUnmetered) {
                updateJobStatusInDb(jobId, "retryWaiting", 0.0, "Waiting for Wi-Fi network")
                HonDownloadManagerBridge.notifyStateChanged(bookId, jobId, "retryWaiting", 0.0)
                return@withContext Result.retry()
            }
        }

        return@withContext locks.getOrPut(jobId) { Mutex() }.withLock {
            if (!isCurrentAttempt(jobId)) Result.failure()
            else DownloadRequestGate.run(sourceId) {
                if (!isCurrentAttempt(jobId)) Result.failure()
                else executeDownload(jobId, url, targetPath, bookId, chapterId, sourceId)
            }
        }
    }

    private suspend fun executeDownload(
        jobId: String,
        url: String,
        targetPath: String,
        bookId: String?,
        chapterId: String?,
        sourceId: String
    ): Result {
        val targetFile = File(targetPath)
        var tempFile: File? = null
        var backupFile: File? = null
        var replacingTarget = false

        activeCalls[jobId] = trackedCalls
        return try {
            val retryPrefs = context.getSharedPreferences("hon_download_retry_after", Context.MODE_PRIVATE)
            val retryAt = retryPrefs.getLong(sourceId, 0)
            if (retryAt > System.currentTimeMillis()) {
                val waitSeconds = ((retryAt - System.currentTimeMillis()) / 1000).coerceAtLeast(1)
                updateJobStatusInDb(jobId, "retryWaiting", 0.0, "Source is rate-limited. Waiting ${waitSeconds}s to retry.")
                HonDownloadManagerBridge.notifyStateChanged(bookId, jobId, "retryWaiting", 0.0)
                return Result.retry()
            }
            retryPrefs.edit().remove(sourceId).apply()
            val chTitle = inputData.getString("chapterTitle") ?: "Downloading chapter"
            try {
                setForeground(DownloadNotifications.foreground(context, jobId, chTitle, "Downloading passage"))
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                android.util.Log.w(
                    "HonDownloadWorker",
                    "Could not elevate worker $jobId to foreground service (${error.javaClass.simpleName}: ${error.message}). " +
                    "Continuing execution under standard WorkManager background constraints; posting informational notification only."
                )
                DownloadNotifications.onJobStarted(context, jobId, chTitle, "Downloading passage")
            }
            updateJobStatusInDb(jobId, "running", 0.1)
            HonDownloadManagerBridge.notifyStateChanged(bookId, jobId, "running", 0.1)
            val managedRoot = File(context.filesDir.parentFile, "app_flutter/chapters").canonicalFile
            val parentDir = targetFile.parentFile?.canonicalFile
                ?: throw IllegalStateException("Download destination has no parent")
            if (parentDir != managedRoot && !parentDir.path.startsWith(managedRoot.path + File.separator)) {
                throw IllegalStateException("Download destination is outside managed chapter storage")
            }
            if (targetFile.exists() && targetFile.canonicalFile.parentFile != parentDir) {
                throw IllegalStateException("Download destination resolves outside managed chapter storage")
            }
            if (!parentDir.exists() && !parentDir.mkdirs()) {
                throw IllegalStateException("Cannot create managed chapter storage")
            }
            // Recover a file replacement interrupted before its database commit.
            val interruptedBackup = File(parentDir, "${targetFile.name}.backup")
            if (interruptedBackup.exists()) {
                if (targetFile.exists() && !targetFile.delete()) error("Cannot recover interrupted chapter replacement")
                if (!interruptedBackup.renameTo(targetFile)) error("Cannot restore interrupted chapter replacement")
            }
            tempFile = File.createTempFile(targetFile.name, ".tmp", parentDir)
            // Unsupported sources must fail visibly; raw HTML is not a passage.
            val luaScript = getSourceScript(sourceId)
                ?: throw IllegalStateException("No installed extension script for source $sourceId")
            val client = httpClient.newBuilder().cookieJar(SourceHttpClient.cookies(context, sourceId)).build()
            val settingsJson = SourcePreferenceStore.read(context, sourceId)
            val settings = settingsJson.keys().asSequence().associateWith { settingsJson.get(it) }
            val passage = try {
                ShosetsuKotlinEngine(client).getPassage(luaScript, url, settings, getAllowedHosts(sourceId))
            } catch (error: LinkageError) {
                throw IllegalStateException("The source engine could not load. Please update Hon. ${error.message}", error)
            }
            val imagesDir = File(context.filesDir.parentFile, "app_flutter/images")
            DownloadNotifications.onJobPhase(context, jobId, chTitle, "Extracting illustrations")
            val passageContent = OfflineChapterImages.embed(passage, url, client, imagesDir) { isStopped }

            if (passageContent.isBlank()) {
                throw IllegalStateException("Extracted chapter passage was empty for $url")
            }

            if (!isCurrentAttempt(jobId)) throw IllegalStateException("Download was paused, cancelled or replaced")

            // Write atomically to temp file
            FileOutputStream(tempFile).use { output ->
                output.write(passageContent.toByteArray(Charsets.UTF_8))
                output.fd.sync()
            }

            if (!tempFile.exists() || tempFile.length() == 0L) {
                throw IllegalStateException("Temporary chapter file was empty after write")
            }

            // Retain any prior valid chapter until both file and DB commit succeed.
            if (targetFile.exists()) {
                backupFile = File(parentDir, "${targetFile.name}.backup")
                if (!targetFile.renameTo(backupFile)) {
                    throw IllegalStateException("Could not preserve previous chapter file")
                }
            }
            replacingTarget = true
            if (!tempFile.renameTo(targetFile)) {
                throw IllegalStateException("Could not atomically commit downloaded chapter")
            }

            if (isStopped || !targetFile.exists() || targetFile.length() == 0L) {
                throw IllegalStateException("Target chapter file missing or empty after commit: ${targetFile.absolutePath}")
            }

            // The job and chapter are one durable state transition.
            markCompletedInDb(jobId, chapterId, targetPath)
            backupFile?.delete()

            // Notify Flutter runtime
            HonDownloadManagerBridge.notifyStateChanged(bookId, jobId, "completed", 1.0)
            Result.success()
        } catch (e: Exception) {
            tempFile?.delete()
            if (replacingTarget) targetFile.delete()
            if (backupFile?.exists() == true) {
                if (!backupFile!!.renameTo(targetFile)) {
                    try {
                        updateJobStatusInDb(jobId, "failed", 0.0,
                            "Could not restore the previous chapter file after download failure: ${backupFile!!.absolutePath}")
                    } catch (_: Exception) {}
                    return Result.failure()
                }
            }

            if (!isCurrentAttempt(jobId)) return Result.failure()
            val errorMsg = e.message ?: e.toString()
            if (e is CancellationException) throw e
            val causes = generateSequence(e as Throwable) { it.cause }.take(12).toList()
            val httpError = causes.filterIsInstance<SourceHttpException>().firstOrNull()
            val retryable = httpError?.transient ?: causes.any { it is IOException && it !is java.io.FileNotFoundException }
            if (httpError != null && httpError.retryAfterMillis > 0) {
                context.getSharedPreferences("hon_download_retry_after", Context.MODE_PRIVATE).edit()
                    .putLong(sourceId, System.currentTimeMillis() + httpError.retryAfterMillis).apply()
            }
            val failures = openDatabase()?.use { database ->
                database.execSQL("UPDATE download_jobs_table SET retry_count=retry_count+1 WHERE id=?", arrayOf(jobId))
                database.rawQuery("SELECT retry_count FROM download_jobs_table WHERE id=?", arrayOf(jobId)).use { rows -> if (rows.moveToFirst()) rows.getInt(0) else 4 }
            } ?: 4
            if (retryable && failures <= 3) {
                try {
                    updateJobStatusInDb(jobId, "retryWaiting", 0.0, errorMsg)
                    HonDownloadManagerBridge.notifyStateChanged(bookId, jobId, "retryWaiting", 0.0)
                } catch (_: Exception) {}
                Result.retry()
            } else {
                try {
                    updateJobStatusInDb(jobId, "failed", 0.0, errorMsg)
                    HonDownloadManagerBridge.notifyStateChanged(bookId, jobId, "failed", 0.0)
                } catch (_: Exception) {}
                Result.failure()
            }
        } finally {
            activeCalls.remove(jobId, trackedCalls)
            DownloadNotifications.onJobFinished(context, jobId)
        }
    }

    private fun getSourceScript(sourceId: String): String? {
        if (Regex("^ext_[0-9a-f]{64}$").matches(sourceId)) {
            val root = File(context.filesDir.parentFile, "app_flutter/extensions").canonicalFile
            val script = File(root, "$sourceId.lua")
            if (script.canonicalFile.parentFile != root || !script.isFile || script.length() > 2 * 1024 * 1024) return null
            return script.readText(Charsets.UTF_8)
        }
        if (sourceId != "gutenberg") return null
        val candidatePaths = listOf(
            "flutter_assets/assets/sources/$sourceId.lua",
            "assets/sources/$sourceId.lua"
        )
        for (path in candidatePaths) {
            try {
                context.assets.open(path).use { input ->
                    return input.bufferedReader().readText()
                }
            } catch (_: Exception) {}
        }
        return null
    }

    private fun getAllowedHosts(sourceId: String): Set<String> {
        try {
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = flutterPrefs.getString("flutter.hon_installed_repository_extensions_v1", null)
            if (raw != null) {
                val array = org.json.JSONArray(raw)
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    if (obj.optString("sourceId") == sourceId) {
                        val hostsArray = obj.optJSONArray("allowedHosts") ?: continue
                        val set = mutableSetOf<String>()
                        for (j in 0 until hostsArray.length()) {
                            val host = hostsArray.getString(j).trim()
                            if (host.isNotEmpty()) set.add(host)
                        }
                        return set
                    }
                }
            }
        } catch (_: Exception) {}
        return emptySet()
    }

    private fun openDatabase(): SQLiteDatabase? {
        // path_provider's Android documents directory is app_flutter, which
        // is also the sole Drift SQLite location in AppDatabase.
        val file = File(context.filesDir.parentFile, "app_flutter/hon.sqlite")
        if (!file.exists()) return null
        return SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING).apply {
            rawQuery("PRAGMA busy_timeout = 5000", null).use { it.moveToFirst() }
            setForeignKeyConstraintsEnabled(true)
        }
    }

    private fun updateJobStatusInDb(jobId: String, status: String, progress: Double, error: String? = null) {
        if (!isCurrentAttempt(jobId)) return
        val db = openDatabase() ?: return
        try {
            val values = ContentValues().apply {
                put("status", status)
                put("progress", progress)
                put("updated_at", System.currentTimeMillis() / 1000)
                if (error != null) {
                    put("error_message", error)
                }
            }
            val allowedStatuses = when (status) {
                "running" -> "status IN ('queued', 'retryWaiting', 'running', 'paused')"
                "retryWaiting" -> "status IN ('queued', 'running', 'retryWaiting')"
                "failed" -> "status IN ('queued', 'running', 'retryWaiting', 'paused')"
                "paused" -> "status IN ('queued', 'running', 'retryWaiting', 'paused')"
                "queued" -> "status IN ('queued', 'retryWaiting', 'paused', 'failed')"
                else -> "status != 'completed'"
            }
            val rows = db.update("download_jobs_table", values,
                "id = ? AND $allowedStatuses", arrayOf(jobId))
            if (rows > 0) {
                val chapterState = when (status) {
                    "running" -> "downloading"
                    "retryWaiting", "queued" -> "queued"
                    "paused" -> "paused"
                    "failed" -> "failed"
                    "completed" -> "downloaded"
                    else -> null
                }
                if (chapterState != null) {
                    val chapterId = inputData.getString("chapterId")
                    if (!chapterId.isNullOrBlank()) {
                        val chVals = ContentValues().apply {
                            put("download_state", chapterState)
                            put("updated_at", System.currentTimeMillis() / 1000)
                        }
                        db.update("chapters_table", chVals, "id = ?", arrayOf(chapterId))
                    }
                }
            }
        } finally {
            db.close()
        }
    }

    private fun markCompletedInDb(jobId: String, chapterId: String?, localPath: String) {
        if (chapterId.isNullOrBlank()) throw IllegalStateException("Missing chapter ID for job $jobId")
        if (!isCurrentAttempt(jobId)) throw IllegalStateException("Stale download attempt")
        val db = openDatabase() ?: throw IllegalStateException("Failed to open SQLite database for job $jobId")
        try {
            db.beginTransaction()
            val chapterValues = ContentValues().apply {
                put("local_file_path", localPath)
                put("download_state", "downloaded")
                put("updated_at", System.currentTimeMillis() / 1000)
            }
            val chapterRows = db.update("chapters_table", chapterValues, "id = ?", arrayOf(chapterId))
            if (chapterRows != 1) {
                throw IllegalStateException("No chapters_table row found for id: $chapterId")
            }
            val jobValues = ContentValues().apply {
                put("status", "completed")
                put("progress", 1.0)
                put("error_message", null as String?)
                put("updated_at", System.currentTimeMillis() / 1000)
            }
            val jobRows = db.update("download_jobs_table", jobValues,
                "id = ? AND status = 'running'", arrayOf(jobId))
            if (jobRows != 1 || isStopped) {
                throw IllegalStateException("Job $jobId was cancelled or removed before completion")
            }
            db.setTransactionSuccessful()
        } finally {
            if (db.inTransaction()) db.endTransaction()
            db.close()
        }
    }
}
