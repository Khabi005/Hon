package com.hon.reader.hon

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Queues chapters the background update check just found, so they are saved
 * offline without opening Hon. It mirrors HonDownloadManager.queueChapters in
 * Dart: the same job id and managed file path, a durable job row, the chapter
 * marked queued, then one unique WorkManager request per job.
 */
object AutoDownloadQueue {
    const val PREF_ENABLED = "flutter.hon_auto_download_new"
    const val PREF_WIFI_ONLY = "flutter.hon_download_wifi_only"

    data class Job(
        val jobId: String,
        val bookId: String,
        val chapterId: String,
        val title: String,
        val url: String,
        val sourceId: String,
        val targetPath: String,
    )

    fun jobId(bookId: String, sourceChapterId: String): String =
        "dl_" + HonUpdateCheckWorker.sha256("$bookId:$sourceChapterId")

    fun targetPath(chaptersDir: File, bookId: String, sourceChapterId: String): String =
        File(
            chaptersDir,
            "${HonUpdateCheckWorker.sha256(bookId)}_${HonUpdateCheckWorker.sha256(sourceChapterId)}.html"
        ).path

    fun chaptersDir(context: Context): File = File(context.filesDir.parentFile, "app_flutter/chapters")

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean(PREF_ENABLED, false)

    /**
     * Writes the job rows and marks the chapters queued in one transaction.
     * Chapters with a job that is still queued, running or paused, or that are
     * already downloaded, are left alone. Returns the jobs to schedule.
     */
    fun persist(
        db: SQLiteDatabase,
        bookId: String,
        sourceId: String,
        chapters: List<ExistingChapter>,
        chaptersDir: File,
        nowSec: Long = System.currentTimeMillis() / 1000,
    ): List<Job> {
        val jobs = mutableListOf<Job>()
        db.beginTransaction()
        try {
            for (ch in chapters) {
                val url = ch.url
                if (url.isNullOrBlank() || ch.downloadState == "downloaded") continue
                val id = jobId(bookId, ch.sourceChapterId)
                val busy = db.rawQuery(
                    "SELECT status FROM download_jobs_table WHERE id = ?",
                    arrayOf(id)
                ).use { c -> c.moveToFirst() && c.getString(0) in setOf("queued", "running", "retryWaiting", "paused") }
                if (busy) continue
                val path = ch.localFilePath ?: targetPath(chaptersDir, bookId, ch.sourceChapterId)
                db.insertWithOnConflict(
                    "download_jobs_table", null,
                    ContentValues().apply {
                        put("id", id)
                        put("book_id", bookId)
                        put("chapter_id", ch.id)
                        put("chapter_title", ch.title)
                        put("source_id", sourceId)
                        put("status", "queued")
                        put("progress", 0.0)
                        put("retry_count", 0)
                        putNull("error_message")
                        put("created_at", nowSec)
                        put("updated_at", nowSec)
                    },
                    SQLiteDatabase.CONFLICT_REPLACE
                )
                db.update(
                    "chapters_table",
                    ContentValues().apply {
                        put("local_file_path", path)
                        put("download_state", "queued")
                        put("updated_at", nowSec)
                    },
                    "id = ? AND download_state != 'downloaded'",
                    arrayOf(ch.id)
                )
                jobs.add(Job(id, bookId, ch.id, ch.title, url, sourceId, path))
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return jobs
    }

    /** Hands each job to HonDownloadWorker, keeping any request already running. */
    fun schedule(context: Context, jobs: List<Job>) {
        if (jobs.isEmpty()) return
        val wifiOnly = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean(PREF_WIFI_ONLY, false)
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(if (wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
            .build()
        val manager = WorkManager.getInstance(context)
        val tokens = context.getSharedPreferences("hon_download_tokens", Context.MODE_PRIVATE)
        for (job in jobs) {
            val request = OneTimeWorkRequestBuilder<HonDownloadWorker>()
                .setConstraints(constraints)
                .setInputData(
                    workDataOf(
                        "jobId" to job.jobId,
                        "url" to job.url,
                        "targetPath" to job.targetPath,
                        "bookId" to job.bookId,
                        "chapterId" to job.chapterId,
                        "chapterTitle" to job.title,
                        "sourceId" to job.sourceId,
                        "wifiOnly" to wifiOnly
                    )
                )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
                .addTag("hon_download")
                .addTag("job_${job.jobId}")
                .build()
            try {
                val running = manager.getWorkInfosForUniqueWork(job.jobId).get().firstOrNull { !it.state.isFinished }
                if (running != null) {
                    if (!tokens.contains(job.jobId)) tokens.edit().putString(job.jobId, running.id.toString()).commit()
                    continue
                }
                tokens.edit().putString(job.jobId, request.id.toString()).commit()
                manager.enqueueUniqueWork(job.jobId, ExistingWorkPolicy.KEEP, request).result.get()
            } catch (_: Exception) {
                // The job row stays queued; Hon's recovery on next launch schedules it.
            }
        }
        HonDownloadManagerBridge.notifyStateChanged(jobs.first().bookId, null, "queued", 0.0)
    }
}
