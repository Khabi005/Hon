package com.hon.reader.hon

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SQLiteUpdateCheckDatabaseTest {

    private lateinit var db: SQLiteDatabase
    private lateinit var updateCheckDb: SQLiteUpdateCheckDatabase

    private fun getTotalChanges(): Int {
        db.rawQuery("SELECT total_changes()", null).use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getInt(0)
            }
        }
        return -1
    }

    @Before
    fun setUp() {
        // Create an in-memory SQLite database
        db = SQLiteDatabase.create(null)
        updateCheckDb = SQLiteUpdateCheckDatabase(db)

        // Create books_table
        db.execSQL("""
            CREATE TABLE books_table (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                author TEXT NOT NULL DEFAULT 'Unknown Author',
                description TEXT NOT NULL DEFAULT '',
                cover_path TEXT,
                format TEXT NOT NULL,
                source_id TEXT,
                source_novel_id TEXT,
                file_path TEXT,
                content_hash TEXT,
                total_chapters INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
        """.trimIndent())

        // Create library_entries_table
        db.execSQL("""
            CREATE TABLE library_entries_table (
                book_id TEXT PRIMARY KEY,
                is_in_library INTEGER NOT NULL DEFAULT 0,
                date_added INTEGER NOT NULL,
                last_read_at INTEGER,
                is_finished INTEGER NOT NULL DEFAULT 0,
                collection_ids TEXT NOT NULL DEFAULT '',
                custom_sort_order INTEGER NOT NULL DEFAULT 0
            );
        """.trimIndent())

        // Create chapters_table
        db.execSQL("""
            CREATE TABLE chapters_table (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL,
                source_chapter_id TEXT NOT NULL,
                title TEXT NOT NULL,
                chapter_index REAL NOT NULL DEFAULT 0.0,
                url TEXT,
                local_file_path TEXT,
                download_state TEXT NOT NULL DEFAULT 'notDownloaded',
                release_date INTEGER,
                updated_at INTEGER NOT NULL
            );
        """.trimIndent())

        // Seed initial book and library entry
        val now = 1700000000L
        val bookVals = ContentValues().apply {
            put("id", "book_1")
            put("title", "The Legendary Mechanic")
            put("format", "webnovel")
            put("source_id", "source_webnovel")
            put("source_novel_id", "https://example.com/novel/1")
            put("total_chapters", 2)
            put("created_at", now)
            put("updated_at", now)
        }
        db.insert("books_table", null, bookVals)

        val libVals = ContentValues().apply {
            put("book_id", "book_1")
            put("is_in_library", 1)
            put("is_finished", 0)
            put("date_added", now)
        }
        db.insert("library_entries_table", null, libVals)

        // Seed 2 chapters with specific release_dates, local_file_paths, and download_state = "downloaded"
        val ch1Vals = ContentValues().apply {
            put("id", "book_1:ch_1")
            put("book_id", "book_1")
            put("source_chapter_id", "ch_1")
            put("title", "Chapter 1: The Transmigration")
            put("chapter_index", 0.0)
            put("url", "https://example.com/ch1")
            put("local_file_path", "/data/user/0/com.hon.reader/app_flutter/chapters/c1.html")
            put("download_state", "downloaded")
            put("release_date", 1700000000000L)
            put("updated_at", now)
        }
        db.insert("chapters_table", null, ch1Vals)

        val ch2Vals = ContentValues().apply {
            put("id", "book_1:ch_2")
            put("book_id", "book_1")
            put("source_chapter_id", "ch_2")
            put("title", "Chapter 2: The Airship")
            put("chapter_index", 1.0)
            put("url", "https://example.com/ch2")
            put("local_file_path", "/data/user/0/com.hon.reader/app_flutter/chapters/c2.html")
            put("download_state", "downloaded")
            put("release_date", 1700000500000L)
            put("updated_at", now)
        }
        db.insert("chapters_table", null, ch2Vals)
    }

    @After
    fun tearDown() {
        if (::db.isInitialized && db.isOpen) {
            db.close()
        }
    }

    @Test
    fun queryOngoingCandidatesReturnsEligibleLibraryNovels() {
        val candidates = updateCheckDb.queryOngoingCandidates(setOf("source_webnovel"), limit = 10)
        assertEquals(1, candidates.size)
        assertEquals("book_1", candidates[0].first)
        assertEquals("source_webnovel", candidates[0].second)
        assertEquals("https://example.com/novel/1", candidates[0].third)
    }

    @Test
    fun unchangedCatalogPreservesReleaseDateAndWritesZeroRows() = runBlocking {
        val initialChapters = updateCheckDb.queryExistingChapters("book_1")
        assertEquals(2, initialChapters.size)
        assertEquals(1700000000000L, initialChapters[0].releaseDate)
        assertEquals(1700000500000L, initialChapters[1].releaseDate)

        val changesBefore = getTotalChanges()

        // 1. Direct call with empty diffs
        updateCheckDb.saveReconciledChapters(
            bookId = "book_1",
            newChapters = emptyList(),
            updatedChapters = emptyList(),
            totalChapters = 2
        )
        val changesAfterDirect = getTotalChanges()
        assertEquals("Direct save with no changes must write 0 SQLite rows", changesBefore, changesAfterDirect)

        // 2. Perform check via HonUpdateCheckWorker with matching upstream catalog
        var notifications = 0
        val result = HonUpdateCheckWorker.performUpdateCheck(
            database = updateCheckDb,
            enabledSourceIds = setOf("source_webnovel"),
            networkFetcher = { _, _ ->
                listOf(
                    ChapterData("ch_1", "Chapter 1: The Transmigration", "https://example.com/ch1", 0.0),
                    ChapterData("ch_2", "Chapter 2: The Airship", "https://example.com/ch2", 1.0)
                )
            },
            notifier = { _, _ -> notifications++ }
        )

        assertEquals(0, result.newChaptersFound)
        assertEquals(0, result.booksWithUpdates)
        assertEquals(0, notifications)

        val chaptersAfterCheck = updateCheckDb.queryExistingChapters("book_1")
        assertEquals(2, chaptersAfterCheck.size)

        // Verify release_date, download_state, and local_file_path remain 100% intact
        val ch1 = chaptersAfterCheck[0]
        assertEquals("book_1:ch_1", ch1.id)
        assertEquals("ch_1", ch1.sourceChapterId)
        assertEquals(1700000000000L, ch1.releaseDate)
        assertEquals("downloaded", ch1.downloadState)
        assertEquals("/data/user/0/com.hon.reader/app_flutter/chapters/c1.html", ch1.localFilePath)

        val ch2 = chaptersAfterCheck[1]
        assertEquals("book_1:ch_2", ch2.id)
        assertEquals("ch_2", ch2.sourceChapterId)
        assertEquals(1700000500000L, ch2.releaseDate)
        assertEquals("downloaded", ch2.downloadState)
        assertEquals("/data/user/0/com.hon.reader/app_flutter/chapters/c2.html", ch2.localFilePath)
    }

    @Test
    fun newChapterInsertsOnlyNewRowAndPreservesExistingChapters() = runBlocking {
        var notifications = 0
        val result = HonUpdateCheckWorker.performUpdateCheck(
            database = updateCheckDb,
            enabledSourceIds = setOf("source_webnovel"),
            networkFetcher = { _, _ ->
                listOf(
                    ChapterData("ch_1", "Chapter 1: The Transmigration", "https://example.com/ch1", 0.0),
                    ChapterData("ch_2", "Chapter 2: The Airship", "https://example.com/ch2", 1.0),
                    ChapterData("ch_3", "Chapter 3: The Secret Lab", "https://example.com/ch3", 2.0)
                )
            },
            notifier = { _, _ -> notifications++ }
        )

        assertEquals(1, result.newChaptersFound)
        assertEquals(1, result.booksWithUpdates)
        assertEquals(1, notifications)

        val chapters = updateCheckDb.queryExistingChapters("book_1")
        assertEquals(3, chapters.size)

        // Existing chapters 1 & 2 must NOT have their release_date, localFilePath, or downloadState overwritten
        assertEquals(1700000000000L, chapters[0].releaseDate)
        assertEquals("downloaded", chapters[0].downloadState)
        assertEquals("/data/user/0/com.hon.reader/app_flutter/chapters/c1.html", chapters[0].localFilePath)

        assertEquals(1700000500000L, chapters[1].releaseDate)
        assertEquals("downloaded", chapters[1].downloadState)
        assertEquals("/data/user/0/com.hon.reader/app_flutter/chapters/c2.html", chapters[1].localFilePath)

        // New chapter 3
        assertEquals("book_1:ch_3", chapters[2].id)
        assertEquals("ch_3", chapters[2].sourceChapterId)
        assertEquals("Chapter 3: The Secret Lab", chapters[2].title)
        assertEquals(2.0, chapters[2].chapterIndex, 0.001)
        assertEquals("notDownloaded", chapters[2].downloadState)
        assertNull(chapters[2].localFilePath)
        assertNull(chapters[2].releaseDate)

        // Check books_table total_chapters updated
        db.rawQuery("SELECT total_chapters FROM books_table WHERE id = 'book_1'", null).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(3, cursor.getInt(0))
        }
    }

    @Test
    fun updatedTitleAndUrlPreservesReleaseDateAndDownloadState() = runBlocking {
        var notifications = 0
        val result = HonUpdateCheckWorker.performUpdateCheck(
            database = updateCheckDb,
            enabledSourceIds = setOf("source_webnovel"),
            networkFetcher = { _, _ ->
                listOf(
                    // Chapter 1 has updated title and URL
                    ChapterData("ch_1", "Chapter 1: The Transmigration (Edited)", "https://example.com/ch1_updated", 0.0),
                    ChapterData("ch_2", "Chapter 2: The Airship", "https://example.com/ch2", 1.0)
                )
            },
            notifier = { _, _ -> notifications++ }
        )

        assertEquals(0, result.newChaptersFound)
        assertEquals(0, notifications)

        val chapters = updateCheckDb.queryExistingChapters("book_1")
        assertEquals(2, chapters.size)

        val ch1 = chapters[0]
        assertEquals("book_1:ch_1", ch1.id)
        assertEquals("Chapter 1: The Transmigration (Edited)", ch1.title)
        assertEquals("https://example.com/ch1_updated", ch1.url)
        // Crucial assertions: release_date, download_state, and local_file_path must NOT be lost!
        assertEquals(1700000000000L, ch1.releaseDate)
        assertEquals("downloaded", ch1.downloadState)
        assertEquals("/data/user/0/com.hon.reader/app_flutter/chapters/c1.html", ch1.localFilePath)

        val ch2 = chapters[1]
        assertEquals(1700000500000L, ch2.releaseDate)
        assertEquals("downloaded", ch2.downloadState)
    }
}
