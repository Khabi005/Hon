package com.hon.reader.hon

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

class HonDownloadWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    private val shosetsuEngine = ShosetsuKotlinEngine(httpClient)

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val jobId = inputData.getString("jobId")
        val url = inputData.getString("url")
        val targetPath = inputData.getString("targetPath")
        val bookId = inputData.getString("bookId")
        val chapterId = inputData.getString("chapterId")
        val sourceId = inputData.getString("sourceId") ?: "gutenberg"

        if (jobId == "RECOVER_ALL") {
            return@withContext recoverAllDownloads()
        }

        if (jobId.isNullOrBlank() || url.isNullOrBlank() || targetPath.isNullOrBlank()) {
            return@withContext Result.failure()
        }

        return@withContext executeDownload(jobId, url, targetPath, bookId, chapterId, sourceId)
    }

    private suspend fun executeDownload(
        jobId: String,
        url: String,
        targetPath: String,
        bookId: String?,
        chapterId: String?,
        sourceId: String
    ): Result {
        updateJobStatusInDb(jobId, "running", 0.1)
        HonDownloadManagerBridge.notifyStateChanged(bookId, jobId, "running", 0.1)

        val targetFile = File(targetPath)
        val parentDir = targetFile.parentFile
        if (parentDir != null && !parentDir.exists()) {
            parentDir.mkdirs()
        }

        val tempFile = File("$targetPath.tmp_${System.currentTimeMillis()}")

        return try {
            // 1. Passage Extraction via Extension Runtime (or direct HTTP fallback)
            val luaScript = getSourceScript(sourceId)
            val passageContent: String = if (luaScript != null) {
                shosetsuEngine.getPassage(luaScript, url)
            } else {
                fetchDirectHttp(url)
            }

            if (passageContent.isBlank()) {
                throw IllegalStateException("Extracted chapter passage was empty for $url")
            }

            // Write atomically to temp file
            FileOutputStream(tempFile).use { output ->
                output.write(passageContent.toByteArray(Charsets.UTF_8))
            }

            if (!tempFile.exists() || tempFile.length() == 0L) {
                tempFile.delete()
                throw IllegalStateException("Temporary chapter file was empty after write")
            }

            // 2. Commit file with verified rename/copy
            val renameSucceeded = if (targetFile.exists()) {
                targetFile.delete()
                tempFile.renameTo(targetFile)
            } else {
                tempFile.renameTo(targetFile)
            }

            if (!renameSucceeded) {
                try {
                    tempFile.copyTo(targetFile, overwrite = true)
                    tempFile.delete()
                } catch (e: Exception) {
                    tempFile.delete()
                    throw IllegalStateException("Failed to commit chapter file to target: ${targetFile.absolutePath}", e)
                }
            }

            if (!targetFile.exists() || targetFile.length() == 0L) {
                throw IllegalStateException("Target chapter file missing or empty after commit: ${targetFile.absolutePath}")
            }

            // 3. Update SQLite database (throws on failure)
            updateJobStatusInDb(jobId, "completed", 1.0)
            if (!bookId.isNullOrBlank() && !chapterId.isNullOrBlank()) {
                updateChapterDownloadedInDb(chapterId, targetPath)
            }

            // Notify Flutter runtime
            HonDownloadManagerBridge.notifyStateChanged(bookId, jobId, "completed", 1.0)
            Result.success()
        } catch (e: Exception) {
            if (tempFile.exists()) {
                tempFile.delete()
            }

            val errorMsg = e.message ?: e.toString()
            if (runAttemptCount < 3) {
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
        }
    }

    private suspend fun recoverAllDownloads(): Result {
        val db = openDatabase() ?: return Result.failure()
        val pendingJobs = mutableListOf<PendingJobData>()
        try {
            // Join download_jobs_table with chapters_table according to real Drift schema
            val cursor = db.rawQuery(
                """
                SELECT d.id, c.url, c.local_file_path, d.book_id, d.chapter_id, d.source_id 
                FROM download_jobs_table d 
                JOIN chapters_table c ON d.chapter_id = c.id 
                WHERE d.status IN ('queued', 'running', 'retryWaiting')
                """.trimIndent(),
                null
            )
            while (cursor.moveToNext()) {
                val jId = cursor.getString(0)
                val u = cursor.getString(1)
                val path = cursor.getString(2)
                val bId = cursor.getString(3)
                val chId = cursor.getString(4)
                val sId = cursor.getString(5) ?: "gutenberg"
                if (!u.isNullOrBlank() && !path.isNullOrBlank()) {
                    pendingJobs.add(PendingJobData(jId, u, path, bId, chId, sId))
                }
            }
            cursor.close()
        } finally {
            db.close()
        }

        var hasRetry = false
        var hasFailure = false

        for (job in pendingJobs) {
            val res = executeDownload(job.jobId, job.url, job.targetPath, job.bookId, job.chapterId, job.sourceId)
            if (res is Result.Retry) {
                hasRetry = true
            } else if (res is Result.Failure) {
                hasFailure = true
            }
        }

        return when {
            hasRetry -> Result.retry()
            hasFailure -> Result.failure()
            else -> Result.success()
        }
    }

    private data class PendingJobData(
        val jobId: String,
        val url: String,
        val targetPath: String,
        val bookId: String,
        val chapterId: String,
        val sourceId: String
    )

    private fun getSourceScript(sourceId: String): String? {
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

    private fun fetchDirectHttp(url: String): String {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile; Hon/1.0)")
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            .build()

        val response = httpClient.newCall(request).execute()
        if (!response.isSuccessful) {
            throw IllegalStateException("HTTP GET failed with code ${response.code} for $url")
        }
        return response.body?.string() ?: throw IllegalStateException("Empty HTTP body for $url")
    }

    private fun openDatabase(): SQLiteDatabase? {
        val candidates = listOf(
            File(context.filesDir, "hon.sqlite"),
            File(context.filesDir.parentFile, "app_flutter/hon.sqlite"),
            File(context.filesDir.parentFile, "databases/hon.sqlite")
        )
        for (f in candidates) {
            if (f.exists()) {
                try {
                    return SQLiteDatabase.openDatabase(f.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
                } catch (_: Exception) {}
            }
        }
        return null
    }

    private fun updateJobStatusInDb(jobId: String, status: String, progress: Double, error: String? = null) {
        val db = openDatabase() ?: throw IllegalStateException("Failed to open SQLite database for job $jobId")
        try {
            val values = ContentValues().apply {
                put("status", status)
                put("progress", progress)
                put("updated_at", System.currentTimeMillis() / 1000)
                if (error != null) {
                    put("error_message", error)
                }
            }
            val rows = db.update("download_jobs_table", values, "id = ?", arrayOf(jobId))
            if (rows == 0) {
                throw IllegalStateException("No download_jobs_table row found for id: $jobId")
            }
        } finally {
            db.close()
        }
    }

    private fun updateChapterDownloadedInDb(chapterId: String, localPath: String) {
        val db = openDatabase() ?: throw IllegalStateException("Failed to open SQLite database for chapter $chapterId")
        try {
            val values = ContentValues().apply {
                put("local_file_path", localPath)
                put("download_state", "downloaded")
                put("updated_at", System.currentTimeMillis() / 1000)
            }
            val rows = db.update("chapters_table", values, "id = ?", arrayOf(chapterId))
            if (rows == 0) {
                throw IllegalStateException("No chapters_table row found for id: $chapterId")
            }
        } finally {
            db.close()
        }
    }
}
