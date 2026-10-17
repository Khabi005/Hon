package com.hon.reader.hon

import android.content.Context
import androidx.work.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class HonDownloadManagerBridge(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.hon.reader/download_worker")

    init {
        channel.setMethodCallHandler(this)
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
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
                val wifiOnly = call.argument<Boolean>("wifiOnly") ?: false

                if (jobId.isNullOrBlank() || url.isNullOrBlank() || targetPath.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "jobId, url, and targetPath are required", null)
                    return
                }

                val constraints = Constraints.Builder()
                    .setRequiredNetworkType(if (wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
                    .build()

                val data = workDataOf(
                    "jobId" to jobId,
                    "url" to url,
                    "targetPath" to targetPath,
                    "bookId" to bookId,
                    "chapterId" to chapterId
                )

                val workRequest = OneTimeWorkRequestBuilder<HonDownloadWorker>()
                    .setConstraints(constraints)
                    .setInputData(data)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
                    .addTag("hon_download")
                    .addTag("job_$jobId")
                    .build()

                WorkManager.getInstance(context)
                    .enqueueUniqueWork(jobId, ExistingWorkPolicy.REPLACE, workRequest)

                result.success(mapOf("enqueued" to true, "jobId" to jobId))
            }
            "scheduleDownloadRecovery" -> {
                val constraints = Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()

                val data = workDataOf(
                    "jobId" to "RECOVER_ALL"
                )

                val workRequest = OneTimeWorkRequestBuilder<HonDownloadWorker>()
                    .setConstraints(constraints)
                    .setInputData(data)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
                    .addTag("hon_download_recovery")
                    .build()

                WorkManager.getInstance(context)
                    .enqueueUniqueWork("hon_download_recovery", ExistingWorkPolicy.KEEP, workRequest)

                result.success(mapOf("scheduled" to true))
            }
            "cancelDownload" -> {
                val jobId = call.argument<String>("jobId")
                if (jobId != null) {
                    WorkManager.getInstance(context).cancelUniqueWork(jobId)
                    result.success(mapOf("cancelled" to true, "jobId" to jobId))
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
