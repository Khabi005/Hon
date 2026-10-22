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
        val jobId = intent?.getStringExtra(EXTRA_JOB_ID)
        when (intent?.action) {
            ACTION_PAUSE -> {
                if (jobId == null || jobId == "ALL") {
                    HonDownloadManagerBridge.requestAllJobsStopped(context, "paused")
                } else {
                    HonDownloadManagerBridge.requestJobStopped(context, jobId, "paused")
                }
            }
            ACTION_CANCEL -> {
                if (jobId == null || jobId == "ALL") {
                    HonDownloadManagerBridge.requestAllJobsStopped(context, "cancelled")
                } else {
                    HonDownloadManagerBridge.requestJobStopped(context, jobId, "cancelled")
                }
            }
        }
    }
}
