package com.hon.reader.hon

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.*
import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import com.hon.reader.hon.shosetsu.SourceHttpClient
import com.hon.reader.hon.shosetsu.SourcePreferenceStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

data class ChapterData(
    val id: String,
    val title: String,
    val link: String?,
    val order: Double
)

data class ExistingChapter(
    val id: String,
    val sourceChapterId: String,
    val title: String,
    val chapterIndex: Double,
    val url: String?,
    val localFilePath: String? = null,
    val downloadState: String = "notDownloaded",
    val releaseDate: Long? = null
)

data class UpdateCheckResult(
    val booksChecked: Int,
    val newChaptersFound: Int,
    val booksWithUpdates: Int,
    val failureCount: Int,
    val lastError: String? = null,
    val isNetworkFailure: Boolean = false
)

class HonUpdateCheckWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    companion object {
        const val WORK_NAME = "hon_background_update_check"
        const val ONE_TIME_WORK_NAME = "hon_manual_update_check"
        const val CHANNEL_ID = "hon_updates"
        const val NOTIFICATION_ID = 4099
        const val FOREGROUND_NOTIFICATION_ID = 4100
        const val MAX_BOOKS_PER_RUN = 40
        const val MIN_DELAY_PER_SOURCE_MS = 500L

        fun buildConstraints(unmeteredOnly: Boolean, batteryNotLow: Boolean): Constraints {
            return Constraints.Builder()
                .setRequiredNetworkType(if (unmeteredOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(batteryNotLow)
                .build()
        }

        fun buildPeriodicWorkRequest(
            intervalHours: Long,
            unmeteredOnly: Boolean,
            batteryNotLow: Boolean
        ): PeriodicWorkRequest {
            val clampedInterval = intervalHours.coerceAtLeast(1)
            return PeriodicWorkRequestBuilder<HonUpdateCheckWorker>(clampedInterval, TimeUnit.HOURS)
                .setConstraints(buildConstraints(unmeteredOnly, batteryNotLow))
                .addTag("hon_update_check")
                .build()
        }

        fun schedule(
            context: Context,
            enabled: Boolean,
            intervalHours: Long = 24,
            unmeteredOnly: Boolean = true,
            batteryNotLow: Boolean = true
        ) {
            val manager = WorkManager.getInstance(context)
            if (!enabled) {
                manager.cancelUniqueWork(WORK_NAME)
                return
            }
            val request = buildPeriodicWorkRequest(intervalHours, unmeteredOnly, batteryNotLow)
            manager.enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }

        fun triggerOneTime(context: Context, unmeteredOnly: Boolean = false) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(if (unmeteredOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
                .build()
            val request = OneTimeWorkRequestBuilder<HonUpdateCheckWorker>()
                .setConstraints(constraints)
                .addTag("hon_update_check")
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                ONE_TIME_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request
            )
        }

        internal fun sha256(input: String): String {
            val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
            return bytes.joinToString("") { "%02x".format(it) }
        }

        internal fun normalizeTitle(s: String): String {
            var lower = s.lowercase(Locale.ROOT).trim()
            lower = lower.replace(Regex("""\b(?:chapter|chap|ch)\.?\s*(\d+)""", RegexOption.IGNORE_CASE), "c$1")
            return lower.replace(Regex("""[\s\p{P}\p{S}]+"""), "")
        }

        internal suspend fun performUpdateCheck(
            database: UpdateCheckDatabase?,
            enabledSourceIds: Set<String>,
            networkFetcher: suspend (sourceId: String, novelUrl: String) -> List<ChapterData>?,
            notifier: (newChapters: Int, booksCount: Int) -> Unit,
            isStoppedCheck: () -> Boolean = { false },
            delayProvider: suspend (ms: Long) -> Unit = { delay(it) },
            // Chapters added since the last check (never on a book's first check).
            onNewChapters: (bookId: String, sourceId: String, chapters: List<ExistingChapter>) -> Unit = { _, _, _ -> }
        ): UpdateCheckResult {
            if (database == null) {
                return UpdateCheckResult(0, 0, 0, 1, "Database not available")
            }

            val candidates = database.queryOngoingCandidates(enabledSourceIds, limit = MAX_BOOKS_PER_RUN)
            if (candidates.isEmpty()) {
                return UpdateCheckResult(0, 0, 0, 0)
            }

            var totalNewChapters = 0
            var booksWithUpdates = 0
            var failures = 0
            var networkFailures = 0
            var lastError: String? = null
            val lastRequestTimeBySource = mutableMapOf<String, Long>()

            for ((bookId, sourceId, novelUrl) in candidates) {
                if (isStoppedCheck()) {
                    break
                }

                // Minimum delay between consecutive requests to the same source
                val lastTime = lastRequestTimeBySource[sourceId]
                if (lastTime != null) {
                    val elapsed = System.currentTimeMillis() - lastTime
                    if (elapsed < MIN_DELAY_PER_SOURCE_MS) {
                        delayProvider(MIN_DELAY_PER_SOURCE_MS - elapsed)
                    }
                }
                lastRequestTimeBySource[sourceId] = System.currentTimeMillis()

                try {
                    val incomingList = networkFetcher(sourceId, novelUrl)
                    database.touchBookUpdatedAt(bookId)
                    if (incomingList == null || incomingList.isEmpty()) {
                        continue
                    }

                    val existingChapters = database.queryExistingChapters(bookId)
                    val isInitialCheck = existingChapters.isEmpty()
                    val remainingOld = existingChapters.toMutableList()

                    // Count normalized title occurrences across incoming chapters
                    val incomingTitleCounts = mutableMapOf<String, Int>()
                    for (ch in incomingList) {
                        val norm = normalizeTitle(ch.title)
                        if (norm.isNotEmpty()) {
                            incomingTitleCounts[norm] = (incomingTitleCounts[norm] ?: 0) + 1
                        }
                    }

                    // Count normalized title occurrences across remaining old chapters
                    val oldTitleCounts = mutableMapOf<String, Int>()
                    for (ch in remainingOld) {
                        val norm = normalizeTitle(ch.title)
                        if (norm.isNotEmpty()) {
                            oldTitleCounts[norm] = (oldTitleCounts[norm] ?: 0) + 1
                        }
                    }

                    // Pass 1: exact sourceChapterId match
                    val matchedOldByIncoming = mutableMapOf<Int, ExistingChapter>()
                    for (i in incomingList.indices) {
                        val incoming = incomingList[i]
                        val idx = remainingOld.indexOfFirst { it.sourceChapterId == incoming.id }
                        if (idx >= 0) {
                            matchedOldByIncoming[i] = remainingOld.removeAt(idx)
                        }
                    }

                    // Pass 2: unique normalized title match on both sides (no index matching)
                    for (i in incomingList.indices) {
                        if (matchedOldByIncoming.containsKey(i)) continue
                        val incoming = incomingList[i]
                        val normIncoming = normalizeTitle(incoming.title)
                        if (normIncoming.isNotEmpty() &&
                            incomingTitleCounts[normIncoming] == 1 &&
                            oldTitleCounts[normIncoming] == 1) {
                            val matches = remainingOld.filter { normalizeTitle(it.title) == normIncoming }
                            if (matches.size == 1) {
                                val old = matches.first()
                                remainingOld.remove(old)
                                matchedOldByIncoming[i] = old
                            }
                        }
                    }

                    // Reconcile chapters into newChapters and updatedChapters
                    val newChapters = mutableListOf<ExistingChapter>()
                    val updatedChapters = mutableListOf<ExistingChapter>()
                    var newlyAddedCount = 0

                    for (i in incomingList.indices) {
                        val incoming = incomingList[i]
                        val matchedOld = matchedOldByIncoming[i]
                        if (matchedOld != null) {
                            val incomingUrl = incoming.link ?: incoming.id
                            val newIndex = i.toDouble()
                            val changed = (matchedOld.sourceChapterId != incoming.id) ||
                                          (matchedOld.title != incoming.title) ||
                                          (matchedOld.url != incomingUrl) ||
                                          (matchedOld.chapterIndex != newIndex)
                            if (changed) {
                                updatedChapters.add(
                                    matchedOld.copy(
                                        sourceChapterId = incoming.id,
                                        title = incoming.title,
                                        url = incomingUrl,
                                        chapterIndex = newIndex
                                    )
                                )
                            }
                        } else {
                            val newCh = ExistingChapter(
                                id = "$bookId:${incoming.id}",
                                sourceChapterId = incoming.id,
                                title = incoming.title,
                                chapterIndex = i.toDouble(),
                                url = incoming.link ?: incoming.id,
                                downloadState = "notDownloaded",
                                releaseDate = null
                            )
                            newChapters.add(newCh)
                            if (!isInitialCheck) {
                                newlyAddedCount++
                            }
                        }
                    }

                    // Retain remaining unmatched old chapters at the end
                    for (j in remainingOld.indices) {
                        val retained = remainingOld[j]
                        val newIndex = (incomingList.size + j).toDouble()
                        if (retained.chapterIndex != newIndex) {
                            updatedChapters.add(retained.copy(chapterIndex = newIndex))
                        }
                    }

                    val finalTotalChapters = incomingList.size + remainingOld.size
                    database.saveReconciledChapters(
                        bookId = bookId,
                        newChapters = newChapters,
                        updatedChapters = updatedChapters,
                        totalChapters = finalTotalChapters
                    )

                    if (newlyAddedCount > 0) {
                        totalNewChapters += newlyAddedCount
                        booksWithUpdates++
                        try {
                            onNewChapters(bookId, sourceId, newChapters)
                        } catch (_: Exception) {
                            // Saving the chapter list matters more than queueing them.
                        }
                    }
                } catch (e: Exception) {
                    failures++
                    if (e is java.io.IOException) {
                        networkFailures++
                    }
                    lastError = e.message ?: e.toString()
                }
            }

            // Only notify when real new chapters were inserted (not initial check)
            if (totalNewChapters > 0) {
                notifier(totalNewChapters, booksWithUpdates)
            }

            return UpdateCheckResult(
                booksChecked = candidates.size,
                newChaptersFound = totalNewChapters,
                booksWithUpdates = booksWithUpdates,
                failureCount = failures,
                lastError = lastError,
                isNetworkFailure = (failures > 0 && failures == networkFailures)
            )
        }
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val db = openDatabase()
        val adapter = db?.let { SQLiteUpdateCheckDatabase(it) }
        val enabledSources = getEnabledSourceIds()

        val candidates = adapter?.queryOngoingCandidates(enabledSources, limit = MAX_BOOKS_PER_RUN) ?: emptyList()
        if (candidates.size > 15) {
            try {
                setForeground(createForegroundInfo(candidates.size))
            } catch (_: Exception) {}
        }

        val result = performUpdateCheck(
            database = adapter,
            enabledSourceIds = enabledSources,
            networkFetcher = { sourceId, novelUrl -> fetchChaptersFromSource(sourceId, novelUrl) },
            notifier = { newChapters, booksCount -> postUpdateNotification(newChapters, booksCount) },
            isStoppedCheck = { isStopped },
            onNewChapters = { bookId, sourceId, chapters ->
                if (db != null && AutoDownloadQueue.isEnabled(context)) {
                    val jobs = AutoDownloadQueue.persist(
                        db, bookId, sourceId, chapters, AutoDownloadQueue.chaptersDir(context)
                    )
                    AutoDownloadQueue.schedule(context, jobs)
                }
            }
        )

        db?.close()
        recordCheckTimestampAndStatus(result)

        if (result.failureCount > 0 && result.booksChecked == result.failureCount && result.isNetworkFailure) {
            // Entire check failed due to network drop -> honor retry
            Result.retry()
        } else {
            Result.success()
        }
    }

    private fun createForegroundInfo(count: Int): ForegroundInfo {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Chapter Updates",
                NotificationManager.IMPORTANCE_LOW
            )
            nm?.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Checking for updates")
            .setContentText("Checking $count ongoing novels for new chapters…")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                FOREGROUND_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            ForegroundInfo(FOREGROUND_NOTIFICATION_ID, notification)
        }
    }

    private fun openDatabase(): SQLiteDatabase? {
        val file = File(context.filesDir.parentFile, "app_flutter/hon.sqlite")
        if (!file.exists()) return null
        return try {
            SQLiteDatabase.openDatabase(
                file.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING
            ).apply {
                rawQuery("PRAGMA busy_timeout = 5000", null).use { it.moveToFirst() }
                setForeignKeyConstraintsEnabled(true)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun getEnabledSourceIds(): Set<String> {
        val set = mutableSetOf("gutenberg")
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.hon_installed_repository_extensions_v1", null)
            if (raw != null) {
                val array = JSONArray(raw)
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val id = obj.optString("sourceId")
                    val enabled = obj.optBoolean("enabled", true)
                    if (id.isNotEmpty() && enabled) {
                        set.add(id)
                    }
                }
            }
        } catch (_: Exception) {}
        return set
    }

    private suspend fun fetchChaptersFromSource(sourceId: String, novelUrl: String): List<ChapterData>? {
        if (sourceId == "gutenberg") return null
        val extDir = File(context.filesDir.parentFile, "app_flutter/extensions")
        val scriptFile = File(extDir, "$sourceId.lua")
        if (!scriptFile.exists()) return null

        val script = scriptFile.readText()
        val client = SourceHttpClient.create(context, sourceId)
        val engine = ShosetsuKotlinEngine(client)
        val hosts = getAllowedHosts(sourceId)
        val settings = getSourceSettings(sourceId)

        val novelDetails = engine.parseNovel(
            luaScript = script,
            novelUrl = novelUrl,
            loadChapters = true,
            userSettings = settings,
            allowedHosts = hosts
        )

        val chaptersRaw = novelDetails["chapters"] as? List<*> ?: return emptyList()
        val list = mutableListOf<ChapterData>()
        for (item in chaptersRaw) {
            if (item is Map<*, *>) {
                val id = item["id"]?.toString() ?: continue
                val title = item["title"]?.toString() ?: id
                val link = item["link"]?.toString()
                val order = (item["order"] as? Number)?.toDouble() ?: 0.0
                list.add(ChapterData(id, title, link, order))
            }
        }
        return list
    }

    private fun getAllowedHosts(sourceId: String): Set<String> {
        try {
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = flutterPrefs.getString("flutter.hon_installed_repository_extensions_v1", null)
            if (raw != null) {
                val array = JSONArray(raw)
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    if (obj.optString("sourceId") == sourceId) {
                        val hostsArray = obj.optJSONArray("allowedHosts") ?: continue
                        val set = mutableSetOf<String>()
                        for (j in 0 until hostsArray.length()) {
                            val host = hostsArray.getString(j).trim()
                            if (host.isNotEmpty()) set.add(host)
                        }
                        return set
                    }
                }
            }
        } catch (_: Exception) {}
        return emptySet()
    }

    private fun getSourceSettings(sourceId: String): Map<String, Any?> {
        val json = SourcePreferenceStore.read(context, sourceId)
        return json.keys().asSequence().associateWith { json.get(it) }
    }

    private fun postUpdateNotification(newChapters: Int, booksCount: Int) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Chapter Updates",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications when new chapters are available for library books"
            }
            nm.createNotificationChannel(channel)
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("destination", "library")
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(context, 0, intent, flags)

        val text = "$newChapters new ${if (newChapters == 1) "chapter" else "chapters"} in $booksCount ${if (booksCount == 1) "book" else "books"}"
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("New chapters available")
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        nm.notify(NOTIFICATION_ID, notification)
    }

    private fun recordCheckTimestampAndStatus(result: UpdateCheckResult) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val status = when {
                result.failureCount > 0 && result.booksChecked == result.failureCount ->
                    "Check failed: ${result.lastError ?: "Network error"}"
                result.newChaptersFound > 0 ->
                    "Found ${result.newChaptersFound} new chapters in ${result.booksWithUpdates} books"
                result.booksChecked == 0 ->
                    "Up to date (no ongoing books to check)"
                else ->
                    "Up to date (${result.booksChecked} books checked)"
            }
            prefs.edit()
                .putLong("flutter.hon_last_update_check_time", now)
                .putString("flutter.hon_last_update_check_status", status)
                .apply()
        } catch (_: Exception) {}
    }
}

interface UpdateCheckDatabase {
    fun queryOngoingCandidates(enabledSourceIds: Set<String>, limit: Int = 40): List<Triple<String, String, String>> // (bookId, sourceId, sourceNovelId)
    fun queryExistingChapters(bookId: String): List<ExistingChapter>
    fun saveReconciledChapters(
        bookId: String,
        newChapters: List<ExistingChapter>,
        updatedChapters: List<ExistingChapter>,
        totalChapters: Int
    )
    fun touchBookUpdatedAt(bookId: String)
}

class SQLiteUpdateCheckDatabase(private val db: SQLiteDatabase) : UpdateCheckDatabase {
    override fun queryOngoingCandidates(enabledSourceIds: Set<String>, limit: Int): List<Triple<String, String, String>> {
        val query = """
            SELECT b.id, b.title, b.source_id, b.source_novel_id
            FROM books_table b
            INNER JOIN library_entries_table l ON b.id = l.book_id
            WHERE l.is_in_library = 1 AND l.is_finished = 0 
              AND b.source_id IS NOT NULL AND b.source_novel_id IS NOT NULL
            ORDER BY b.updated_at ASC
            LIMIT ?
        """.trimIndent()
        val candidates = mutableListOf<Triple<String, String, String>>()
        db.rawQuery(query, arrayOf(limit.toString())).use { cursor ->
            while (cursor.moveToNext()) {
                val bookId = cursor.getString(0)
                val sourceId = cursor.getString(2)
                val novelUrl = cursor.getString(3)
                if (sourceId in enabledSourceIds && !novelUrl.isNullOrBlank()) {
                    candidates.add(Triple(bookId, sourceId, novelUrl))
                }
            }
        }
        return candidates
    }

    override fun queryExistingChapters(bookId: String): List<ExistingChapter> {
        val list = mutableListOf<ExistingChapter>()
        val query = """
            SELECT id, source_chapter_id, title, chapter_index, url, local_file_path, download_state, release_date
            FROM chapters_table
            WHERE book_id = ?
            ORDER BY chapter_index ASC
        """.trimIndent()
        db.rawQuery(query, arrayOf(bookId)).use { cursor ->
            while (cursor.moveToNext()) {
                val releaseDate = if (!cursor.isNull(7)) cursor.getLong(7) else null
                list.add(
                    ExistingChapter(
                        id = cursor.getString(0),
                        sourceChapterId = cursor.getString(1) ?: "",
                        title = cursor.getString(2) ?: "",
                        chapterIndex = cursor.getDouble(3),
                        url = cursor.getString(4),
                        localFilePath = cursor.getString(5),
                        downloadState = cursor.getString(6) ?: "notDownloaded",
                        releaseDate = releaseDate
                    )
                )
            }
        }
        return list
    }

    override fun touchBookUpdatedAt(bookId: String) {
        val nowSec = System.currentTimeMillis() / 1000
        val values = ContentValues().apply {
            put("updated_at", nowSec)
        }
        db.update("books_table", values, "id = ?", arrayOf(bookId))
    }

    override fun saveReconciledChapters(
        bookId: String,
        newChapters: List<ExistingChapter>,
        updatedChapters: List<ExistingChapter>,
        totalChapters: Int
    ) {
        // Skip transaction entirely when nothing changed! Zero rows written!
        if (newChapters.isEmpty() && updatedChapters.isEmpty()) {
            return
        }

        db.beginTransaction()
        try {
            val nowSec = System.currentTimeMillis() / 1000

            // 1. INSERT only new chapters
            for (ch in newChapters) {
                val values = ContentValues().apply {
                    put("id", ch.id)
                    put("book_id", bookId)
                    put("source_chapter_id", ch.sourceChapterId)
                    put("title", ch.title)
                    put("chapter_index", ch.chapterIndex)
                    put("url", ch.url)
                    put("download_state", ch.downloadState)
                    if (ch.releaseDate != null) {
                        put("release_date", ch.releaseDate)
                    }
                    put("updated_at", nowSec)
                }
                db.insertWithOnConflict("chapters_table", null, values, SQLiteDatabase.CONFLICT_IGNORE)
            }

            // 2. UPDATE only changed columns for matched ones, NEVER touching release_date, local_file_path or download_state
            for (ch in updatedChapters) {
                val values = ContentValues().apply {
                    put("source_chapter_id", ch.sourceChapterId)
                    put("title", ch.title)
                    put("chapter_index", ch.chapterIndex)
                    put("url", ch.url)
                    put("updated_at", nowSec)
                }
                db.update("chapters_table", values, "id = ?", arrayOf(ch.id))
            }

            // 3. Update total_chapters on books_table
            val countValues = ContentValues().apply {
                put("total_chapters", totalChapters)
                put("updated_at", nowSec)
            }
            db.update("books_table", countValues, "id = ?", arrayOf(bookId))

            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }
}
