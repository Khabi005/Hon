package com.hon.reader.hon

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import java.io.File
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import java.util.concurrent.ConcurrentHashMap

class HonDownloadManagerBridge(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.hon.reader/download_worker")

    companion object {
        private val schedulingExecutor = java.util.concurrent.Executors.newFixedThreadPool(2)
        private val cancellationExecutor = java.util.concurrent.Executors.newFixedThreadPool(2)
        private val schedulingLocks = ConcurrentHashMap<String, Any>()
        @Volatile
        private var instance: HonDownloadManagerBridge? = null

        fun notifyStateChanged(bookId: String?, jobId: String, status: String, progress: Double) {
            val bridge = instance ?: return
            Handler(Looper.getMainLooper()).post {
                try {
                    bridge.channel.invokeMethod(
                        "onDownloadStateChanged",
                        mapOf(
                            "bookId" to bookId,
                            "jobId" to jobId,
                            "status" to status,
                            "progress" to progress
                        )
                    )
                } catch (_: Exception) {}
            }
        }

        fun requestJobStopped(context: Context, jobId: String, status: String) {
            cancellationExecutor.execute {
                synchronized(schedulingLocks.getOrPut(jobId) { Any() }) {
                    try {
                        val file = File(context.filesDir.parentFile, "app_flutter/hon.sqlite")
                        if (file.exists()) {
                            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING).use { db ->
                                val values = ContentValues().apply {
                                    put("status", status)
                                    put("updated_at", System.currentTimeMillis() / 1000)
                                }
                                db.update("download_jobs_table", values, "id = ? AND status != 'completed'", arrayOf(jobId))
                                val chState = if (status == "paused") "paused" else "notDownloaded"
                                db.rawQuery("SELECT chapter_id, book_id FROM download_jobs_table WHERE id = ?", arrayOf(jobId)).use { cursor ->
                                    if (cursor.moveToFirst()) {
                                        val chId = cursor.getString(0)
                                        val bookId = cursor.getString(1)
                                        val chVals = ContentValues().apply {
                                            put("download_state", chState)
                                            put("updated_at", System.currentTimeMillis() / 1000)
                                        }
                                        db.update("chapters_table", chVals, "id = ? AND download_state != 'downloaded'", arrayOf(chId))
                                        notifyStateChanged(bookId, jobId, status, 0.0)
                                    }
                                }
                            }
                        }
                        context.getSharedPreferences("hon_download_tokens", Context.MODE_PRIVATE).edit().remove(jobId).apply()
                        WorkManager.getInstance(context).cancelUniqueWork(jobId)
                        HonDownloadWorker.stopAndAwait(jobId)
                    } catch (_: Exception) {}
                }
            }
        }
    }

    init {
        instance = this
        channel.setMethodCallHandler(this)
    }

    fun cleanup() {
        if (instance == this) {
            instance = null
        }
        channel.setMethodCallHandler(null)
    }

    private fun database(): SQLiteDatabase {
        val file=File(context.filesDir.parentFile,"app_flutter/hon.sqlite")
        return SQLiteDatabase.openDatabase(file.path,null,SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING).apply {
            rawQuery("PRAGMA busy_timeout = 5000", null).use { it.moveToFirst() }
            setForeignKeyConstraintsEnabled(true)
        }
    }
    private fun maySchedule(jobId:String):Boolean = database().use { db ->
        db.rawQuery("SELECT status FROM download_jobs_table WHERE id=?",arrayOf(jobId)).use { rows ->
            rows.moveToFirst() && rows.getString(0) in setOf("queued","running","retryWaiting")
        }
    }
    private fun requestStopped(jobId:String,status:String) {
        database().use { db ->
            val values=ContentValues().apply { put("status",status);put("updated_at",System.currentTimeMillis()/1000) }
            db.update("download_jobs_table",values,"id=? AND status != 'completed'",arrayOf(jobId))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isWorkManagerSupported" -> {
                result.success(true)
            }
            "enqueueDownload" -> {
                val jobId = call.argument<String>("jobId")
                val url = call.argument<String>("url")
                val targetPath = call.argument<String>("targetPath")
                val bookId = call.argument<String>("bookId")
                val chapterId = call.argument<String>("chapterId")
                val sourceId = call.argument<String>("sourceId") ?: "gutenberg"
                val wifiOnly = call.argument<Boolean>("wifiOnly") ?: false

                if (jobId.isNullOrBlank() || url.isNullOrBlank() || targetPath.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "jobId, url, and targetPath are required", null)
                    return
                }

                if (android.os.Build.VERSION.SDK_INT >= 33 && context is android.app.Activity &&
                    context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    val preferences = context.getSharedPreferences("hon_notification_prompt", Context.MODE_PRIVATE)
                    if (!preferences.getBoolean("asked", false)) {
                        preferences.edit().putBoolean("asked", true).apply()
                        context.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4097)
                    }
                }

                val constraints = Constraints.Builder()
                    .setRequiredNetworkType(if (wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
                    .build()

                val data = workDataOf(
                    "jobId" to jobId,
                    "url" to url,
                    "targetPath" to targetPath,
                    "bookId" to bookId,
                    "chapterId" to chapterId,
                    "sourceId" to sourceId
                )

                val workRequest = OneTimeWorkRequestBuilder<HonDownloadWorker>()
                    .setConstraints(constraints)
                    .setInputData(data)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
                    .addTag("hon_download")
                    .addTag("job_$jobId")
                    .build()

                val manager = WorkManager.getInstance(context)
                // Recovery with KEEP must retain the token of an already running
                // request. Explicit resume/retry installs a new generation.
                val replace = call.argument<Boolean>("replace") ?: false
                schedulingExecutor.execute {
                  synchronized(schedulingLocks.getOrPut(jobId) { Any() }) {
                    try {
                        if (!maySchedule(jobId)) {
                            Handler(Looper.getMainLooper()).post { result.success(mapOf("enqueued" to false,"jobId" to jobId)) }
                            return@execute
                        }
                        val existing = manager.getWorkInfosForUniqueWork(jobId).get()
                        val running = existing.firstOrNull { !it.state.isFinished }
                        if (!replace && running != null) {
                            val tokens = context.getSharedPreferences("hon_download_tokens", Context.MODE_PRIVATE)
                            if (!tokens.contains(jobId)) tokens.edit().putString(jobId, running.id.toString()).commit()
                            Handler(Looper.getMainLooper()).post { result.success(mapOf("enqueued" to true, "jobId" to jobId)) }
                            return@execute
                        }
                        context.getSharedPreferences("hon_download_tokens", Context.MODE_PRIVATE).edit().putString(jobId, workRequest.id.toString()).commit()
                        manager.enqueueUniqueWork(jobId, if (replace) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, workRequest).result.get()
                        Handler(Looper.getMainLooper()).post { result.success(mapOf("enqueued" to true, "jobId" to jobId)) }
                    } catch (error: Exception) {
                        Handler(Looper.getMainLooper()).post { result.error("SCHEDULE_FAILED", error.message, null) }
                    }
                  }
                }
                return

            }
            "cancelLegacyRecovery" -> {
                WorkManager.getInstance(context).cancelUniqueWork("hon_download_recovery")
                result.success(true)
            }
            "cancelDownload" -> {
                val jobId = call.argument<String>("jobId")
                if (jobId != null) {
                    val status = call.argument<String>("status").takeIf { it == "paused" || it == "cancelled" } ?: "cancelled"
                    try {
                        requestJobStopped(context, jobId, status)
                        result.success(mapOf("cancelled" to true, "jobId" to jobId))
                    } catch (error: Exception) {
                        result.error("CANCEL_FAILED", error.message, null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "jobId is required", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }
}
