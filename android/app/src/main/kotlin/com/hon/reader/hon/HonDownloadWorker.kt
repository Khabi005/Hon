package com.hon.reader.hon

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
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

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val jobId = inputData.getString("jobId")
        val url = inputData.getString("url")
        val targetPath = inputData.getString("targetPath")
        val bookId = inputData.getString("bookId")
        val chapterId = inputData.getString("chapterId")

        if (jobId == "RECOVER_ALL") {
            return@withContext recoverAllDownloads()
        }

        if (jobId.isNullOrBlank() || url.isNullOrBlank() || targetPath.isNullOrBlank()) {
            return@withContext Result.failure()
        }

        return@withContext executeDownload(jobId, url, targetPath, bookId, chapterId)
    }

    private fun executeDownload(
        jobId: String,
        url: String,
        targetPath: String,
        bookId: String?,
        chapterId: String?
    ): Result {
        updateJobStatusInDb(jobId, "running", 0.1)

        val targetFile = File(targetPath)
        val parentDir = targetFile.parentFile
        if (parentDir != null && !parentDir.exists()) {
            parentDir.mkdirs()
        }

        val tempFile = File("$targetPath.tmp_${System.currentTimeMillis()}")

        return try {
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile; Hon/1.0)")
                .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                .build()

            val response = httpClient.newCall(request).execute()
            if (!response.isSuccessful) {
                if (runAttemptCount < 3) {
                    updateJobStatusInDb(jobId, "retryWaiting", 0.0, "HTTP error: ${response.code}")
                    return Result.retry()
                } else {
                    updateJobStatusInDb(jobId, "failed", 0.0, "HTTP error: ${response.code}")
                    return Result.failure()
                }
            }

            val body = response.body ?: throw IllegalStateException("Empty response body")
            FileOutputStream(tempFile).use { output ->
                body.byteStream().use { input ->
                    input.copyTo(output)
                }
            }

            if (tempFile.exists() && tempFile.length() > 0) {
                if (targetFile.exists()) {
                    targetFile.delete()
                }
                tempFile.renameTo(targetFile)

                // Update SQLite database: mark job completed and chapter downloaded
                updateJobStatusInDb(jobId, "completed", 1.0)
                if (!bookId.isNullOrBlank() && !chapterId.isNullOrBlank()) {
                    updateChapterDownloadedInDb(chapterId, targetPath)
                }
                Result.success()
            } else {
                tempFile.delete()
                if (runAttemptCount < 3) {
                    updateJobStatusInDb(jobId, "retryWaiting", 0.0, "Downloaded file was empty")
                    Result.retry()
                } else {
                    updateJobStatusInDb(jobId, "failed", 0.0, "Downloaded file was empty")
                    Result.failure()
                }
            }
        } catch (e: Exception) {
            tempFile.delete()
            if (runAttemptCount < 3) {
                updateJobStatusInDb(jobId, "retryWaiting", 0.0, e.message)
                Result.retry()
            } else {
                updateJobStatusInDb(jobId, "failed", 0.0, e.message)
                Result.failure()
            }
        }
    }

    private fun recoverAllDownloads(): Result {
        val db = openDatabase() ?: return Result.failure()
        try {
            // Find any jobs that were interrupted or queued
            val cursor = db.rawQuery(
                "SELECT id, url, target_path, book_id, chapter_id FROM download_jobs_table WHERE status IN ('queued', 'running', 'retryWaiting')",
                null
            )
            val pendingJobs = mutableListOf<PendingJobData>()
            while (cursor.moveToNext()) {
                val jId = cursor.getString(0)
                val u = cursor.getString(1)
                val path = cursor.getString(2)
                val bId = cursor.getString(3)
                val chId = cursor.getString(4)
                pendingJobs.add(PendingJobData(jId, u, path, bId, chId))
            }
            cursor.close()

            for (job in pendingJobs) {
                executeDownload(job.jobId, job.url, job.targetPath, job.bookId, job.chapterId)
            }
            return Result.success()
        } catch (e: Exception) {
            return Result.failure()
        } finally {
            db.close()
        }
    }

    private data class PendingJobData(
        val jobId: String,
        val url: String,
        val targetPath: String,
        val bookId: String,
        val chapterId: String
    )

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
        val db = openDatabase() ?: return
        try {
            val values = ContentValues().apply {
                put("status", status)
                put("progress", progress)
                put("updated_at", System.currentTimeMillis() / 1000)
                if (error != null) {
                    put("error_message", error)
                }
            }
            db.update("download_jobs_table", values, "id = ?", arrayOf(jobId))
        } catch (_: Exception) {
        } finally {
            db.close()
        }
    }

    private fun updateChapterDownloadedInDb(chapterId: String, localPath: String) {
        val db = openDatabase() ?: return
        try {
            val values = ContentValues().apply {
                put("local_file_path", localPath)
                put("download_state", "downloaded")
                put("updated_at", System.currentTimeMillis() / 1000)
            }
            db.update("chapters_table", values, "id = ?", arrayOf(chapterId))
        } catch (_: Exception) {
        } finally {
            db.close()
        }
    }
}
