package com.hon.reader.hon

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DownloadNotificationReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_PAUSE = "com.hon.reader.ACTION_PAUSE_DOWNLOAD"
        const val ACTION_CANCEL = "com.hon.reader.ACTION_CANCEL_DOWNLOAD"
        const val EXTRA_JOB_ID = "job_id"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val jobId = intent?.getStringExtra(EXTRA_JOB_ID) ?: return
        when (intent.action) {
            ACTION_PAUSE -> {
                HonDownloadManagerBridge.requestJobStopped(context, jobId, "paused")
            }
            ACTION_CANCEL -> {
                HonDownloadManagerBridge.requestJobStopped(context, jobId, "cancelled")
            }
        }
    }
}
