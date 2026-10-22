package com.hon.reader.hon

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import java.io.File
import java.util.concurrent.ConcurrentHashMap

internal object DownloadNotifications {
    private const val channel = "hon_downloads"
    const val NOTIFICATION_ID = 4001

    private val activeJobs = ConcurrentHashMap<String, String>()

    fun onJobStarted(context: Context, jobId: String, title: String, phase: String = "Downloading") {
        activeJobs[jobId] = "$title · $phase"
        updateQueueNotification(context)
    }

    fun onJobPhase(context: Context, jobId: String, title: String, phase: String) {
        activeJobs[jobId] = "$title · $phase"
        updateQueueNotification(context)
    }

    fun removeActiveJob(jobId: String) {
        activeJobs.remove(jobId)
    }

    fun onJobFinished(context: Context, jobId: String) {
        activeJobs.remove(jobId)
        updateQueueNotification(context)
    }

    @Synchronized
    fun updateQueueNotification(context: Context) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val dbFile = File(context.filesDir.parentFile, "app_flutter/hon.sqlite")
            var remainingCount = activeJobs.size
            if (dbFile.exists()) {
                try {
                    SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                        db.rawQuery("SELECT COUNT(*) FROM download_jobs_table WHERE status IN ('queued', 'running', 'retryWaiting')", null).use { cursor ->
                            if (cursor.moveToFirst()) {
                                remainingCount = cursor.getInt(0)
                            }
                        }
                    }
                } catch (_: Exception) {}
            }

            if (remainingCount <= 0 && activeJobs.isEmpty()) {
                manager.cancel(NOTIFICATION_ID)
                return
            }

            val info = buildForegroundInfo(context, remainingCount)
            manager.notify(NOTIFICATION_ID, info.notification)
        } catch (_: Exception) {}
    }

    fun foreground(context: Context, job: String, title: String, phase: String = "Downloading"): ForegroundInfo {
        activeJobs[job] = "$title · $phase"
        val dbFile = File(context.filesDir.parentFile, "app_flutter/hon.sqlite")
        var remainingCount = activeJobs.size
        if (dbFile.exists()) {
            try {
                SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                    db.rawQuery("SELECT COUNT(*) FROM download_jobs_table WHERE status IN ('queued', 'running', 'retryWaiting')", null).use { cursor ->
                        if (cursor.moveToFirst()) {
                            remainingCount = cursor.getInt(0)
                        }
                    }
                }
            } catch (_: Exception) {}
        }
        return buildForegroundInfo(context, remainingCount)
    }

    private fun buildForegroundInfo(context: Context, remainingCount: Int): ForegroundInfo {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channel, "Downloads", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val pauseIntent = PendingIntent.getBroadcast(
            context,
            2001,
            Intent(context, DownloadNotificationReceiver::class.java).apply {
                action = DownloadNotificationReceiver.ACTION_PAUSE
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val cancelIntent = PendingIntent.getBroadcast(
            context,
            3001,
            Intent(context, DownloadNotificationReceiver::class.java).apply {
                action = DownloadNotificationReceiver.ACTION_CANCEL
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val activeList = activeJobs.values.toList()
        val contentText = when {
            activeList.size == 1 -> activeList.first()
            activeList.size > 1 -> "${activeList.size} downloading simultaneously"
            remainingCount > 0 -> "$remainingCount in queue"
            else -> "Processing downloads"
        }

        val queueSummary = if (remainingCount > 1) "$remainingCount in queue" else null

        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Hon · Downloading chapters")
            .setContentText(contentText)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, true)
            .addAction(android.R.drawable.ic_media_pause, "Pause", pauseIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelIntent)

        if (!queueSummary.isNullOrBlank()) {
            builder.setSubText(queueSummary)
        }

        val notification = builder.build()
        return if (Build.VERSION.SDK_INT >= 29) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    fun dismissIfEmpty(context: Context) {
        updateQueueNotification(context)
    }
}
