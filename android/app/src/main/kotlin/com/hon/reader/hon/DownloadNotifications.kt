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
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

internal object DownloadNotifications {
    private const val TAG = "DownloadNotifications"
    private const val CHANNEL_ID = "hon_downloads"
    const val NOTIFICATION_ID = 4001

    data class ActiveJob(
        val attemptToken: String,
        val display: String
    )

    data class QueueStatus(
        val queued: Int,
        val running: Int,
        val retryWaiting: Int
    ) {
        val totalPending: Int get() = queued + running + retryWaiting
    }

    // Tracks currently executing jobs: jobId -> ActiveJob(attemptToken, "$title · $phase")
    private val activeJobs = ConcurrentHashMap<String, ActiveJob>()

    // Promotion listeners registered by secondary concurrent workers:
    // jobId -> suspend () -> Boolean (returns true if setForeground succeeded)
    private val workerPromoters = ConcurrentHashMap<String, suspend () -> Boolean>()

    // Atomic reference to the designated primary foreground worker (jobId)
    // Only non-null if that worker has SUCCEEDED in foreground elevation!
    private val primaryWorkerJobId = AtomicReference<String?>(null)

    // Lock for coordinating foreground ownership and promotion state
    private val foregroundLock = Any()

    /**
     * Atomically claims foreground candidacy for [jobId] with [attemptToken] if no primary worker currently
     * holds foreground execution, or registers [promoter] if another worker is already primary.
     *
     * @return true if this worker is granted permission to attempt primary foreground elevation
     * and must call [HonDownloadWorker.setForeground]. Note: primary status is NOT confirmed until
     * [confirmPrimaryElevation] is called upon elevation success.
     * @return false if this worker is designated as secondary; its [promoter] will be invoked
     * if foreground ownership transfers to it upon completion, retry or cancellation of previous workers.
     */
    fun claimOrRegisterForeground(
        jobId: String,
        attemptToken: String,
        title: String,
        phase: String = "Downloading",
        promoter: suspend () -> Boolean
    ): Boolean = synchronized(foregroundLock) {
        activeJobs[jobId] = ActiveJob(attemptToken, "$title · $phase")
        val currentPrimary = primaryWorkerJobId.get()
        if (currentPrimary == null) {
            true
        } else if (currentPrimary == jobId) {
            true
        } else {
            workerPromoters[jobId] = promoter
            false
        }
    }

    /**
     * Confirms that [jobId] with [attemptToken] has successfully elevated to foreground service.
     */
    fun confirmPrimaryElevation(jobId: String, attemptToken: String) = synchronized(foregroundLock) {
        val current = activeJobs[jobId]
        if (current != null && current.attemptToken == attemptToken) {
            primaryWorkerJobId.set(jobId)
            workerPromoters.remove(jobId)
            Log.i(TAG, "Worker $jobId (attempt $attemptToken) confirmed as primary foreground owner")
        }
    }

    /**
     * Called if elevation to foreground service fails (e.g., due to background execution
     * restrictions on Android 12+). Ensures the failed worker is not recorded as primary,
     * attempts promotion of the next candidate worker, and falls back to standard notification.
     */
    fun onForegroundElevationFailed(context: Context, jobId: String, attemptToken: String) {
        var needPromotion = false
        synchronized(foregroundLock) {
            val current = activeJobs[jobId]
            if (current != null && current.attemptToken == attemptToken) {
                workerPromoters.remove(jobId)
                if (primaryWorkerJobId.get() == jobId) {
                    primaryWorkerJobId.set(null)
                    needPromotion = true
                }
            }
        }
        if (needPromotion) {
            runBlocking {
                promoteNextWorkerLocked(context)
            }
        }
        updateQueueNotification(context)
    }

    fun onJobStarted(context: Context, jobId: String, attemptToken: String, title: String, phase: String = "Downloading") {
        synchronized(foregroundLock) {
            activeJobs[jobId] = ActiveJob(attemptToken, "$title · $phase")
        }
        updateQueueNotification(context)
    }

    fun onJobPhase(context: Context, jobId: String, attemptToken: String, title: String, phase: String) {
        val current = activeJobs[jobId]
        if (current == null || current.attemptToken == attemptToken) {
            activeJobs[jobId] = ActiveJob(attemptToken, "$title · $phase")
            updateQueueNotification(context)
        }
    }

    fun removeActiveJob(jobId: String, attemptToken: String?) = synchronized(foregroundLock) {
        val current = activeJobs[jobId]
        if (attemptToken == null || current?.attemptToken == attemptToken) {
            activeJobs.remove(jobId)
            workerPromoters.remove(jobId)
            if (primaryWorkerJobId.get() == jobId) {
                primaryWorkerJobId.set(null)
            }
        }
    }

    /**
     * Acknowledged foreground handoff: outgoing worker unregisters, transfers foreground
     * ownership to the next candidate worker, and waits for the promoted worker's
     * setForeground elevation to succeed before returning.
     */
    suspend fun handoffForegroundAndFinish(context: Context, jobId: String, attemptToken: String) {
        var needPromotion = false
        synchronized(foregroundLock) {
            val current = activeJobs[jobId]
            if (current != null && current.attemptToken == attemptToken) {
                activeJobs.remove(jobId)
            }
            workerPromoters.remove(jobId)
            if (primaryWorkerJobId.get() == jobId) {
                primaryWorkerJobId.set(null)
                needPromotion = true
            }
        }
        if (needPromotion) {
            promoteNextWorkerLocked(context)
        }
        updateQueueNotification(context)
    }

    private suspend fun promoteNextWorkerLocked(context: Context): Boolean {
        val candidates = activeJobs.entries.toList()
        for (entry in candidates) {
            val candJobId = entry.key
            val candAttemptToken = entry.value.attemptToken
            if (primaryWorkerJobId.get() == candJobId) continue

            val promoter = synchronized(foregroundLock) {
                workerPromoters.remove(candJobId)
            } ?: continue

            val elevated = try {
                withTimeoutOrNull(3000) {
                    promoter.invoke()
                } == true
            } catch (e: Exception) {
                Log.w(TAG, "Promoter invocation threw for job $candJobId: ${e.message}")
                false
            }
            if (elevated) {
                synchronized(foregroundLock) {
                    if (activeJobs[candJobId]?.attemptToken == candAttemptToken) {
                        primaryWorkerJobId.set(candJobId)
                        Log.i(TAG, "Acknowledged foreground handoff to $candJobId (attempt $candAttemptToken)")
                        return true
                    }
                }
            } else {
                Log.w(TAG, "Promotion failed or timed out for $candJobId (attempt $candAttemptToken)")
            }
        }
        primaryWorkerJobId.set(null)
        return false
    }

    fun reconcileSurvivingJobs(context: Context) {
        var needPromotion = false
        synchronized(foregroundLock) {
            if (primaryWorkerJobId.get() == null && activeJobs.isNotEmpty()) {
                needPromotion = true
            }
        }
        if (needPromotion) {
            runBlocking {
                promoteNextWorkerLocked(context)
            }
        }
        updateQueueNotification(context)
    }

    fun getPrimaryWorkerJobId(): String? = primaryWorkerJobId.get()
    fun getActiveJobCount(): Int = activeJobs.size

    fun cancelAll(context: Context) = synchronized(foregroundLock) {
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

    fun foreground(
        context: Context,
        job: String,
        attemptToken: String,
        title: String,
        phase: String = "Downloading"
    ): ForegroundInfo {
        synchronized(foregroundLock) {
            activeJobs[job] = ActiveJob(attemptToken, "$title · $phase")
        }
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

        val activeList = activeJobs.values.map { it.display }
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

