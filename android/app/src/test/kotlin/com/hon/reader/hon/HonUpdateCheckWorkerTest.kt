package com.hon.reader.hon

import androidx.work.NetworkType
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class HonUpdateCheckWorkerTest {

    @Test
    fun constraintsAndWorkRequestRespectConfiguredValues() {
        val unmeteredBatteryConstraint = HonUpdateCheckWorker.buildConstraints(
            unmeteredOnly = true,
            batteryNotLow = true
        )
        assertEquals(NetworkType.UNMETERED, unmeteredBatteryConstraint.requiredNetworkType)
        assertTrue(unmeteredBatteryConstraint.requiresBatteryNotLow())

        val anyNetworkConstraint = HonUpdateCheckWorker.buildConstraints(
            unmeteredOnly = false,
            batteryNotLow = false
        )
        assertEquals(NetworkType.CONNECTED, anyNetworkConstraint.requiredNetworkType)
        assertFalse(anyNetworkConstraint.requiresBatteryNotLow())

        val request = HonUpdateCheckWorker.buildPeriodicWorkRequest(
            intervalHours = 12,
            unmeteredOnly = true,
            batteryNotLow = true
        )
        assertNotNull(request)
        assertTrue(request.tags.contains("hon_update_check"))
        assertEquals(NetworkType.UNMETERED, request.workSpec.constraints.requiredNetworkType)
        assertTrue(request.workSpec.constraints.requiresBatteryNotLow())
        assertFalse(request.workSpec.constraints.requiresCharging())

        val chargingRequest = HonUpdateCheckWorker.buildPeriodicWorkRequest(
            intervalHours = 12,
            unmeteredOnly = false,
            batteryNotLow = false,
            charging = true
        )
        assertTrue(chargingRequest.workSpec.constraints.requiresCharging())
    }

    class InMemoryUpdateCheckDatabase : UpdateCheckDatabase {
        data class Candidate(val bookId: String, val sourceId: String, val sourceNovelId: String)
        val candidates = mutableListOf<Candidate>()
        val chaptersByBook = mutableMapOf<String, MutableList<ExistingChapter>>()
        val totalChaptersByBook = mutableMapOf<String, Int>()
        val touchedBooks = mutableSetOf<String>()

        override fun queryOngoingCandidates(enabledSourceIds: Set<String>, limit: Int): List<Triple<String, String, String>> {
            return candidates
                .filter { it.sourceId in enabledSourceIds && it.sourceNovelId.isNotBlank() }
                .take(limit)
                .map { Triple(it.bookId, it.sourceId, it.sourceNovelId) }
        }

        override fun queryExistingChapters(bookId: String): List<ExistingChapter> {
            return chaptersByBook[bookId]?.toList() ?: emptyList()
        }

        override fun touchBookUpdatedAt(bookId: String) {
            touchedBooks.add(bookId)
        }

        val lastNewChapters = mutableListOf<ExistingChapter>()
        val lastUpdatedChapters = mutableListOf<ExistingChapter>()

        override fun saveReconciledChapters(
            bookId: String,
            newChapters: List<ExistingChapter>,
            updatedChapters: List<ExistingChapter>,
            totalChapters: Int
        ) {
            lastNewChapters.clear()
            lastNewChapters.addAll(newChapters)
            lastUpdatedChapters.clear()
            lastUpdatedChapters.addAll(updatedChapters)

            val current = chaptersByBook.getOrPut(bookId) { mutableListOf() }
            for (up in updatedChapters) {
                val idx = current.indexOfFirst { it.id == up.id }
                if (idx >= 0) {
                    current[idx] = up
                }
            }
            current.addAll(newChapters)
            current.sortBy { it.chapterIndex }
            totalChaptersByBook[bookId] = totalChapters
        }
    }

    @Test
    fun titleNormalizationMatchesChapterVariations() {
        assertEquals("c1thebeginning", HonUpdateCheckWorker.normalizeTitle("Chapter 1: The Beginning!"))
        assertEquals("c1thebeginning", HonUpdateCheckWorker.normalizeTitle("Chap. 1 - The Beginning"))
        assertEquals("c1thebeginning", HonUpdateCheckWorker.normalizeTitle("Ch 1 The Beginning"))
        assertEquals("c10thebigclimax", HonUpdateCheckWorker.normalizeTitle("Chapter 10: The Big Climax"))
        assertEquals("epilogueaftermath", HonUpdateCheckWorker.normalizeTitle("Epilogue - Aftermath"))
    }

    @Test
    fun whenZeroBooksNeedUpdatesNoNetworkIsMade() = runBlocking {
        val db = InMemoryUpdateCheckDatabase()
        var networkCalls = 0
        var notificationCalls = 0

        val result = HonUpdateCheckWorker.performUpdateCheck(
            database = db,
            enabledSourceIds = setOf("test_source"),
            networkFetcher = { _, _ ->
                networkCalls++
                null
            },
            notifier = { _, _ ->
                notificationCalls++
            }
        )

        assertEquals(0, result.booksChecked)
        assertEquals(0, result.newChaptersFound)
        assertEquals(0, networkCalls)
        assertEquals(0, notificationCalls)
    }

    @Test
    fun initialCheckSavesChaptersWithoutNotification() = runBlocking {
        val db = InMemoryUpdateCheckDatabase()
        val bookId = "book_initial"
        val sourceId = "test_source"

        db.candidates.add(InMemoryUpdateCheckDatabase.Candidate(bookId, sourceId, "https://example.com/novel/initial"))
        // Initial state: 0 existing chapters in DB
        assertEquals(0, db.queryExistingChapters(bookId).size)

        var notificationCount = 0

        val result = HonUpdateCheckWorker.performUpdateCheck(
            database = db,
            enabledSourceIds = setOf(sourceId),
            networkFetcher = { _, _ ->
                listOf(
                    ChapterData("ch_1", "Chapter 1", "https://example.com/ch1", 0.0),
                    ChapterData("ch_2", "Chapter 2", "https://example.com/ch2", 1.0),
                    ChapterData("ch_3", "Chapter 3", "https://example.com/ch3", 2.0)
                )
            },
            notifier = { _, _ ->
                notificationCount++
            }
        )

        // Must NOT notify or claim new chapters on initial check
        assertEquals(1, result.booksChecked)
        assertEquals(0, result.newChaptersFound)
        assertEquals(0, result.booksWithUpdates)
        assertEquals(0, notificationCount)

        // But chapters MUST be saved to database in Dart-compatible format
        val saved = db.queryExistingChapters(bookId)
        assertEquals(3, saved.size)
        assertEquals("$bookId:ch_1", saved[0].id)
        assertEquals("ch_1", saved[0].sourceChapterId)
        assertEquals("Chapter 1", saved[0].title)
        assertEquals(0.0, saved[0].chapterIndex, 0.001)

        assertEquals("$bookId:ch_2", saved[1].id)
        assertEquals("ch_2", saved[1].sourceChapterId)
        assertEquals(1.0, saved[1].chapterIndex, 0.001)

        assertEquals("$bookId:ch_3", saved[2].id)
        assertEquals("ch_3", saved[2].sourceChapterId)
        assertEquals(2.0, saved[2].chapterIndex, 0.001)
        assertEquals(3, db.totalChaptersByBook[bookId])
    }

    @Test
    fun urlPatternChangeDoesNotDuplicateAndPreservesOfflineDownloads() = runBlocking {
        val db = InMemoryUpdateCheckDatabase()
        val bookId = "book_url_change"
        val sourceId = "test_source"

        db.candidates.add(InMemoryUpdateCheckDatabase.Candidate(bookId, sourceId, "https://example.com/novel/1"))
        // Existing chapter that was already downloaded offline
        db.chaptersByBook[bookId] = mutableListOf(
            ExistingChapter(
                id = "$bookId:ch_1",
                sourceChapterId = "ch_1",
                title = "Chapter 1",
                chapterIndex = 0.0,
                url = "https://old-domain.com/ch1",
                localFilePath = "/data/user/0/com.hon.reader/app_flutter/chapters/c1.html",
                downloadState = "downloaded"
            )
        )

        var notificationCount = 0

        val result = HonUpdateCheckWorker.performUpdateCheck(
            database = db,
            enabledSourceIds = setOf(sourceId),
            networkFetcher = { _, _ ->
                // Upstream changed domain / URL pattern and slight title variation
                listOf(
                    ChapterData("ch_1", "Chapter 1: The Awakening", "https://new-cdn.com/novel/ch1", 0.0)
                )
            },
            notifier = { _, _ ->
                notificationCount++
            }
        )

        // Existing chapter updated -> no new chapters, no notification
        assertEquals(0, result.newChaptersFound)
        assertEquals(0, notificationCount)

        val updated = db.queryExistingChapters(bookId)
        assertEquals(1, updated.size)
        val ch = updated[0]
        assertEquals("$bookId:ch_1", ch.id)
        assertEquals("ch_1", ch.sourceChapterId)
        assertEquals("Chapter 1: The Awakening", ch.title)
        assertEquals("https://new-cdn.com/novel/ch1", ch.url)
        // Crucial: local file and downloaded state must NOT be wiped
        assertEquals("/data/user/0/com.hon.reader/app_flutter/chapters/c1.html", ch.localFilePath)
        assertEquals("downloaded", ch.downloadState)
    }

    @Test
    fun titleHealingPreservesOfflineDownloadWhenSlugChanges() = runBlocking {
        val db = InMemoryUpdateCheckDatabase()
        val bookId = "book_title_heal"
        val sourceId = "test_source"

        db.candidates.add(InMemoryUpdateCheckDatabase.Candidate(bookId, sourceId, "https://example.com/novel/1"))
        // Existing chapter with old slug
        db.chaptersByBook[bookId] = mutableListOf(
            ExistingChapter(
                id = "$bookId:old_slug_1",
                sourceChapterId = "old_slug_1",
                title = "Chapter 1 - First Contact",
                chapterIndex = 0.0,
                url = "https://example.com/old_slug_1",
                localFilePath = "/data/user/0/com.hon.reader/app_flutter/chapters/c1.html",
                downloadState = "downloaded"
            )
        )

        val result = HonUpdateCheckWorker.performUpdateCheck(
            database = db,
            enabledSourceIds = setOf(sourceId),
            networkFetcher = { _, _ ->
                // Upstream changed slug to new_slug_1, but normalized title matches
                listOf(
                    ChapterData("new_slug_1", "Chapter 1: First Contact", "https://example.com/new_slug_1", 0.0),
                    ChapterData("new_slug_2", "Chapter 2: Second Contact", "https://example.com/new_slug_2", 1.0)
                )
            },
            notifier = { _, _ -> }
        )

        // Chapter 1 healed via title matching, Chapter 2 is brand new
        assertEquals(1, result.newChaptersFound)
        assertEquals(1, result.booksWithUpdates)

        val chapters = db.queryExistingChapters(bookId)
        assertEquals(2, chapters.size)
        val healed = chapters[0]
        assertEquals("new_slug_1", healed.sourceChapterId)
        assertEquals("downloaded", healed.downloadState)
        assertEquals("/data/user/0/com.hon.reader/app_flutter/chapters/c1.html", healed.localFilePath)

        val brandNew = chapters[1]
        assertEquals("$bookId:new_slug_2", brandNew.id)
        assertEquals("notDownloaded", brandNew.downloadState)
    }

    @Test
    fun workCapAndCancellationAreHonored() = runBlocking {
        val db = InMemoryUpdateCheckDatabase()
        val sourceId = "test_source"

        // Add 50 candidate books
        for (i in 1..50) {
            db.candidates.add(InMemoryUpdateCheckDatabase.Candidate("book_$i", sourceId, "https://example.com/novel/$i"))
        }

        // 1. Verify capping at 40
        var fetchedCount = 0
        val resultCap = HonUpdateCheckWorker.performUpdateCheck(
            database = db,
            enabledSourceIds = setOf(sourceId),
            networkFetcher = { _, _ ->
                fetchedCount++
                emptyList()
            },
            notifier = { _, _ -> },
            delayProvider = { /* skip delay in test */ }
        )
        assertEquals(40, resultCap.booksChecked)
        assertEquals(40, fetchedCount)

        // 2. Verify cancellation via isStoppedCheck
        var stoppedCalls = 0
        val resultStopped = HonUpdateCheckWorker.performUpdateCheck(
            database = db,
            enabledSourceIds = setOf(sourceId),
            networkFetcher = { _, _ ->
                stoppedCalls++
                emptyList()
            },
            notifier = { _, _ -> },
            isStoppedCheck = { stoppedCalls >= 5 },
            delayProvider = { /* skip delay */ }
        )
        assertEquals(5, stoppedCalls)
    }

    @Test
    fun networkFailureTriggersNetworkFailureFlag() = runBlocking {
        val db = InMemoryUpdateCheckDatabase()
        db.candidates.add(InMemoryUpdateCheckDatabase.Candidate("b1", "s1", "https://example.com/1"))

        val result = HonUpdateCheckWorker.performUpdateCheck(
            database = db,
            enabledSourceIds = setOf("s1"),
            networkFetcher = { _, _ ->
                throw java.io.IOException("Connection timed out")
            },
            notifier = { _, _ -> },
            delayProvider = { }
        )

        assertEquals(1, result.failureCount)
        assertTrue(result.isNetworkFailure)
    }
}
