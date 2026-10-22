package com.hon.reader.hon

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference

internal object DownloadNotifications {
    private const val TAG = "DownloadNotifications"
    private const val CHANNEL_ID = "hon_downloads"
    const val NOTIFICATION_ID = 4001

    // Tracks currently executing jobs and their sub-phases
    private val activeJobs = ConcurrentHashMap<String, String>()

    // Promotion listeners registered by secondary concurrent workers
    private val workerPromoters = ConcurrentHashMap<String, () -> Unit>()

    // Atomic reference to the designated primary foreground worker
    private val primaryWorkerJobId = AtomicReference<String?>(null)

    data class QueueStatus(
        val queued: Int,
        val running: Int,
        val retryWaiting: Int
    ) {
        val totalPending: Int get() = queued + running + retryWaiting
    }

    /**
     * Atomically claims foreground ownership for [jobId] if no primary worker currently
     * holds foreground execution, or registers [promoter] if another worker is already primary.
     *
     * @return true if this worker is designated as the primary foreground worker and must
     * call [HonDownloadWorker.setForeground].
     * @return false if this worker is designated as secondary; its [promoter] will be invoked
     * if foreground ownership transfers to it upon completion, retry or cancellation of previous workers.
     */
    @Synchronized
    fun claimOrRegisterForeground(
        jobId: String,
        title: String,
        phase: String = "Downloading",
        promoter: () -> Unit
    ): Boolean {
        activeJobs[jobId] = "$title · $phase"
        val currentPrimary = primaryWorkerJobId.get()
        return if (currentPrimary == null || currentPrimary == jobId) {
            primaryWorkerJobId.set(jobId)
            true
        } else {
            workerPromoters[jobId] = promoter
            false
        }
    }

    /**
     * Called if elevation to foreground service fails (e.g., due to background execution
     * restrictions on Android 12+). Falls back to standard notification updates.
     */
    @Synchronized
    fun onForegroundElevationFailed(context: Context, jobId: String) {
        updateQueueNotification(context)
    }

    @Synchronized
    fun onJobStarted(context: Context, jobId: String, title: String, phase: String = "Downloading") {
        activeJobs[jobId] = "$title · $phase"
        if (primaryWorkerJobId.get() == null) {
            primaryWorkerJobId.set(jobId)
        }
        updateQueueNotification(context)
    }

    @Synchronized
    fun onJobPhase(context: Context, jobId: String, title: String, phase: String) {
        activeJobs[jobId] = "$title · $phase"
        updateQueueNotification(context)
    }

    @Synchronized
    fun removeActiveJob(jobId: String) {
        activeJobs.remove(jobId)
        workerPromoters.remove(jobId)
        if (primaryWorkerJobId.get() == jobId) {
            promoteNextWorker()
        }
    }

    @Synchronized
    fun onJobFinished(context: Context, jobId: String) {
        activeJobs.remove(jobId)
        workerPromoters.remove(jobId)
        if (primaryWorkerJobId.get() == jobId) {
            promoteNextWorker()
        }
        updateQueueNotification(context)
    }

    private fun promoteNextWorker() {
        val nextJobId = activeJobs.keys.firstOrNull()
        primaryWorkerJobId.set(nextJobId)
        if (nextJobId != null) {
            val promoter = workerPromoters.remove(nextJobId)
            try {
                promoter?.invoke()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to invoke promotion callback for job $nextJobId: ${e.message}")
            }
        }
    }

    @Synchronized
    fun reconcileAfterBatchStop(context: Context, stoppedJobIds: Collection<String>) {
        for (jobId in stoppedJobIds) {
            activeJobs.remove(jobId)
            workerPromoters.remove(jobId)
        }
        val currentPrimary = primaryWorkerJobId.get()
        if (currentPrimary != null && stoppedJobIds.contains(currentPrimary)) {
            promoteNextWorker()
        }
        updateQueueNotification(context)
    }

    fun getPrimaryWorkerJobId(): String? = primaryWorkerJobId.get()
    fun getActiveJobCount(): Int = activeJobs.size

    @Synchronized
    fun cancelAll(context: Context) {
        activeJobs.clear()
        workerPromoters.clear()
        primaryWorkerJobId.set(null)
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.cancel(NOTIFICATION_ID)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to cancel queue notification: ${e.message}")
        }
    }

    fun dismissIfEmpty(context: Context) {
        updateQueueNotification(context)
    }

    private fun queryQueueStatus(context: Context): QueueStatus {
        val dbFile = File(context.filesDir.parentFile, "app_flutter/hon.sqlite")
        var queued = 0
        var running = 0
        var retryWaiting = 0
        if (dbFile.exists()) {
            try {
                SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                    db.rawQuery("PRAGMA busy_timeout = 3000", null).use { it.moveToFirst() }
                    db.rawQuery(
                        "SELECT status, COUNT(*) FROM download_jobs_table WHERE status IN ('queued', 'running', 'retryWaiting') GROUP BY status",
                        null
                    ).use { cursor ->
                        while (cursor.moveToNext()) {
                            val st = cursor.getString(0)
                            val cnt = cursor.getInt(1)
                            when (st) {
                                "queued" -> queued = cnt
                                "running" -> running = cnt
                                "retryWaiting" -> retryWaiting = cnt
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not query queue status: ${e.message}")
            }
        }
        return QueueStatus(queued, running, retryWaiting)
    }

    @Synchronized
    fun updateQueueNotification(context: Context) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val status = queryQueueStatus(context)

            // State A: Queue is empty and no workers are active -> cancel notification
            if (status.totalPending <= 0 && activeJobs.isEmpty()) {
                primaryWorkerJobId.set(null)
                manager.cancel(NOTIFICATION_ID)
                return
            }

            val notification = buildNotification(context, status)
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w(TAG, "Error updating queue notification: ${e.message}")
        }
    }

    @Synchronized
    fun foreground(context: Context, job: String, title: String, phase: String = "Downloading"): ForegroundInfo {
        activeJobs[job] = "$title · $phase"
        primaryWorkerJobId.set(job)
        workerPromoters.remove(job)
        val status = queryQueueStatus(context)
        val notification = buildNotification(context, status)
        return if (Build.VERSION.SDK_INT >= 29) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(context: Context, status: QueueStatus): android.app.Notification {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Download queue progress and status"
                }
            )
        }

        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val pauseIntent = PendingIntent.getBroadcast(
            context, 2001,
            Intent(context, DownloadNotificationReceiver::class.java).apply {
                action = DownloadNotificationReceiver.ACTION_PAUSE
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val cancelIntent = PendingIntent.getBroadcast(
            context, 3001,
            Intent(context, DownloadNotificationReceiver::class.java).apply {
                action = DownloadNotificationReceiver.ACTION_CANCEL
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val activeList = activeJobs.values.toList()
        val isActivelyExecuting = activeList.isNotEmpty()
        val isWaitingRetryOnly = !isActivelyExecuting && status.retryWaiting > 0 && status.queued == 0 && status.running == 0

        val title: String
        val contentText: String
        val isOngoing: Boolean
        val showProgress: Boolean

        if (isWaitingRetryOnly) {
            // State C: Waiting for backoff / rate limit; dismissable, no indeterminate spinner
            title = "Hon · Downloads waiting to retry"
            contentText = "Waiting for source cooldown (${status.retryWaiting} chapters remaining)"
            isOngoing = false
            showProgress = false
        } else if (isActivelyExecuting) {
            // State B: Actively downloading
            title = "Hon · Downloading chapters"
            contentText = if (activeList.size == 1) {
                activeList.first()
            } else {
                "${activeList.size} downloading simultaneously"
            }
            isOngoing = true
            showProgress = true
        } else {
            // State D: Inter-worker transition
            title = "Hon · Downloading chapters"
            contentText = "${status.totalPending} in queue"
            isOngoing = true
            showProgress = true
        }

        val queueSummary = if (status.totalPending > 1 && !isWaitingRetryOnly) "${status.totalPending} in queue" else null

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(contentText)
            .setContentIntent(open)
            .setOngoing(isOngoing)
            .setOnlyAlertOnce(true)

        if (showProgress) {
            builder.setProgress(0, 0, true)
        }

        if (isOngoing) {
            builder.addAction(android.R.drawable.ic_media_pause, "Pause", pauseIntent)
        }
        builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelIntent)

        if (!queueSummary.isNullOrBlank()) {
            builder.setSubText(queueSummary)
        }

        return builder.build()
    }
}

