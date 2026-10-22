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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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

    data class PendingReservation(
        val jobId: String,
        val attemptToken: String,
        val generation: Long
    )

    sealed class ClaimResult {
        data class PrimaryCandidate(val generation: Long) : ClaimResult()
        object Secondary : ClaimResult()
    }

    // Tracks currently executing jobs: jobId -> ActiveJob(attemptToken, "$title · $phase")
    private val activeJobs = ConcurrentHashMap<String, ActiveJob>()

    // Promotion listeners registered by secondary concurrent workers:
    // jobId -> suspend (Long) -> Boolean (returns true if setForeground succeeded and confirmed)
    private val workerPromoters = ConcurrentHashMap<String, suspend (Long) -> Boolean>()

    // Confirmed primary foreground worker jobId (only non-null if elevation was confirmed!)
    private var confirmedPrimaryJobId: String? = null

    // Pending reservation for foreground elevation candidacy
    private var pendingReservation: PendingReservation? = null

    // Monotonically increasing generation to invalidate timed-out or late confirmations
    private var currentGeneration: Long = 0L

    // Lock for coordinating foreground ownership and pending reservation state
    private val foregroundLock = Any()

    // Mutex to serialize async handoff and promotion loops
    private val promotionMutex = Mutex()

    // Background scope for non-blocking scheduled reconciliation
    private val reconciliationScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /**
     * Checks if the pending reservation for [jobId] with [attemptToken] at [generation]
     * is still valid before calling setForeground.
     */
    fun isReservationValid(jobId: String, attemptToken: String, generation: Long): Boolean = synchronized(foregroundLock) {
        pendingReservation?.generation == generation &&
        pendingReservation?.jobId == jobId &&
        pendingReservation?.attemptToken == attemptToken
    }

    /**
     * Atomically claims foreground candidacy for [jobId] with [attemptToken] if no primary worker currently
     * holds confirmed foreground execution and no other worker holds a pending reservation.
     * Otherwise, registers [promoter] as a secondary worker.
     *
     * @return [ClaimResult.PrimaryCandidate] if this worker is granted permission to attempt primary foreground elevation
     * and must call [HonDownloadWorker.setForeground]. Note: primary status is NOT confirmed until
     * [confirmPrimaryElevation] is called upon elevation success.
     * @return [ClaimResult.Secondary] if another worker is primary or currently pending elevation; its [promoter]
     * will be invoked if foreground ownership transfers to it upon completion, retry or cancellation of previous workers.
     */
    fun claimOrRegisterForeground(
        jobId: String,
        attemptToken: String,
        title: String,
        phase: String = "Downloading",
        promoter: suspend (Long) -> Boolean
    ): ClaimResult = synchronized(foregroundLock) {
        activeJobs[jobId] = ActiveJob(attemptToken, "$title · $phase")
        if (confirmedPrimaryJobId == jobId) {
            ClaimResult.PrimaryCandidate(currentGeneration)
        } else if (confirmedPrimaryJobId == null && pendingReservation == null) {
            currentGeneration++
            val gen = currentGeneration
            pendingReservation = PendingReservation(jobId, attemptToken, gen)
            Log.i(TAG, "Worker $jobId (attempt $attemptToken) reserved initial primary candidate at gen $gen")
            ClaimResult.PrimaryCandidate(gen)
        } else {
            workerPromoters[jobId] = promoter
            Log.i(TAG, "Worker $jobId (attempt $attemptToken) registered as secondary (primary: $confirmedPrimaryJobId, pending: ${pendingReservation?.jobId})")
            ClaimResult.Secondary
        }
    }

    /**
     * Confirms that [jobId] with [attemptToken] has successfully elevated to foreground service.
     * Rejects late confirmations if the reservation was timed out or invalidated.
     */
    fun confirmPrimaryElevation(jobId: String, attemptToken: String, generation: Long): Boolean = synchronized(foregroundLock) {
        val current = activeJobs[jobId]
        if (current != null &&
            current.attemptToken == attemptToken &&
            pendingReservation?.generation == generation &&
            pendingReservation?.jobId == jobId &&
            pendingReservation?.attemptToken == attemptToken
        ) {
            confirmedPrimaryJobId = jobId
            pendingReservation = null
            workerPromoters.remove(jobId)
            Log.i(TAG, "Worker $jobId (attempt $attemptToken, gen $generation) confirmed as primary foreground owner")
            true
        } else {
            Log.w(TAG, "Rejecting late or mismatched elevation confirmation for $jobId (gen $generation, pending: $pendingReservation)")
            false
        }
    }

    /**
     * Called if elevation to foreground service fails (e.g., due to background execution
     * restrictions on Android 12+). Ensures the failed worker is not recorded as primary,
     * attempts promotion of the next candidate worker, and falls back to standard notification.
     */
    suspend fun onForegroundElevationFailed(
        context: Context,
        jobId: String,
        attemptToken: String,
        generation: Long
    ) {
        var needPromotion = false
        synchronized(foregroundLock) {
            val current = activeJobs[jobId]
            if (current != null && current.attemptToken == attemptToken) {
                workerPromoters.remove(jobId)
                if (pendingReservation?.generation == generation &&
                    pendingReservation?.jobId == jobId &&
                    pendingReservation?.attemptToken == attemptToken
                ) {
                    pendingReservation = null
                    needPromotion = true
                }
                if (confirmedPrimaryJobId == jobId) {
                    confirmedPrimaryJobId = null
                    needPromotion = true
                }
            }
        }
        if (needPromotion) {
            promoteNextWorker(context)
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
            if (pendingReservation?.jobId == jobId && (attemptToken == null || pendingReservation?.attemptToken == attemptToken)) {
                pendingReservation = null
            }
            if (confirmedPrimaryJobId == jobId) {
                confirmedPrimaryJobId = null
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
            if (pendingReservation?.jobId == jobId && pendingReservation?.attemptToken == attemptToken) {
                pendingReservation = null
                needPromotion = true
            }
            if (confirmedPrimaryJobId == jobId) {
                confirmedPrimaryJobId = null
                needPromotion = true
            }
        }
        if (needPromotion) {
            promoteNextWorker(context)
        }
        updateQueueNotification(context)
    }

    private suspend fun promoteNextWorker(context: Context): Boolean = promotionMutex.withLock {
        while (true) {
            val nextCandidate: Pair<String, suspend (Long) -> Boolean>? = synchronized(foregroundLock) {
                if (confirmedPrimaryJobId != null) {
                    return@withLock true
                }
                if (pendingReservation != null) {
                    return@withLock false
                }
                val entry = activeJobs.entries.firstOrNull { workerPromoters.containsKey(it.key) }
                if (entry == null) {
                    null
                } else {
                    val candJobId = entry.key
                    val candAttemptToken = entry.value.attemptToken
                    val promoter = workerPromoters.remove(candJobId)
                    if (promoter != null) {
                        currentGeneration++
                        val gen = currentGeneration
                        pendingReservation = PendingReservation(candJobId, candAttemptToken, gen)
                        Pair(candJobId, promoter)
                    } else {
                        null
                    }
                }
            }

            if (nextCandidate == null) {
                return@withLock false
            }

            val (candJobId, promoter) = nextCandidate
            val gen = synchronized(foregroundLock) { pendingReservation?.generation } ?: 0L

            Log.i(TAG, "Promoting next worker candidate $candJobId at generation $gen")

            val elevated = try {
                withTimeoutOrNull(3000) {
                    promoter.invoke(gen)
                } == true
            } catch (e: Exception) {
                Log.w(TAG, "Promoter invocation threw for job $candJobId: ${e.message}")
                false
            }

            if (elevated) {
                val confirmed = synchronized(foregroundLock) { confirmedPrimaryJobId == candJobId }
                if (confirmed) {
                    Log.i(TAG, "Acknowledged foreground handoff to $candJobId at generation $gen")
                    return@withLock true
                }
            }

            synchronized(foregroundLock) {
                if (pendingReservation?.generation == gen) {
                    Log.w(TAG, "Promotion timed out or failed for $candJobId (gen $gen); invalidating reservation")
                    pendingReservation = null
                }
            }
        }
        @Suppress("UNREACHABLE_CODE")
        false
    }

    fun reconcileSurvivingJobs(context: Context) {
        var needPromotion = false
        synchronized(foregroundLock) {
            if (confirmedPrimaryJobId == null && pendingReservation == null && activeJobs.isNotEmpty()) {
                needPromotion = true
            }
        }
        if (needPromotion) {
            runBlocking {
                promoteNextWorker(context)
            }
        }
        updateQueueNotification(context)
    }

    /**
     * Non-blocking reconciliation scheduled on an independent background scope.
     * Prevents timeout fallbacks from blocking execution outside their bounded deadline.
     */
    fun scheduleReconciliation(context: Context) {
        reconciliationScope.launch {
            try {
                var needPromotion = false
                synchronized(foregroundLock) {
                    if (confirmedPrimaryJobId == null && pendingReservation == null && activeJobs.isNotEmpty()) {
                        needPromotion = true
                    }
                }
                if (needPromotion) {
                    promoteNextWorker(context)
                }
                updateQueueNotification(context)
            } catch (e: Exception) {
                Log.w(TAG, "Asynchronous scheduled reconciliation failed: ${e.message}")
            }
        }
    }

    fun getPrimaryWorkerJobId(): String? = synchronized(foregroundLock) { confirmedPrimaryJobId }
    fun getPendingReservation(): PendingReservation? = synchronized(foregroundLock) { pendingReservation }
    fun getActiveJobCount(): Int = activeJobs.size

    fun cancelAll(context: Context) = synchronized(foregroundLock) {
        activeJobs.clear()
        workerPromoters.clear()
        pendingReservation = null
        confirmedPrimaryJobId = null
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
                synchronized(foregroundLock) {
                    confirmedPrimaryJobId = null
                    pendingReservation = null
                }
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

