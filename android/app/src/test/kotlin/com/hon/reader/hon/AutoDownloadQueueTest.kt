package com.hon.reader.hon

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AutoDownloadQueueTest {
    private lateinit var db: SQLiteDatabase
    private val dir = File("/data/user/0/com.hon.reader/app_flutter/chapters")

    @Before
    fun setUp() {
        db = SQLiteDatabase.create(null)
        db.execSQL("""
            CREATE TABLE chapters_table (
                id TEXT PRIMARY KEY, book_id TEXT NOT NULL, source_chapter_id TEXT NOT NULL,
                title TEXT NOT NULL, chapter_index REAL NOT NULL DEFAULT 0.0, url TEXT,
                local_file_path TEXT, download_state TEXT NOT NULL DEFAULT 'notDownloaded',
                release_date INTEGER, updated_at INTEGER NOT NULL
            );
        """.trimIndent())
        db.execSQL("""
            CREATE TABLE download_jobs_table (
                id TEXT PRIMARY KEY, book_id TEXT NOT NULL, chapter_id TEXT NOT NULL,
                chapter_title TEXT NOT NULL, source_id TEXT NOT NULL, status TEXT NOT NULL,
                progress REAL NOT NULL DEFAULT 0.0, retry_count INTEGER NOT NULL DEFAULT 0,
                error_message TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
            );
        """.trimIndent())
        for (i in 1..3) {
            db.insert("chapters_table", null, ContentValues().apply {
                put("id", "b:c$i"); put("book_id", "b"); put("source_chapter_id", "c$i")
                put("title", "Chapter $i"); put("chapter_index", i.toDouble())
                put("url", "https://example.com/c$i"); put("updated_at", 1L)
            })
        }
    }

    @After
    fun tearDown() = db.close()

    private fun chapter(i: Int, state: String = "notDownloaded") = ExistingChapter(
        id = "b:c$i", sourceChapterId = "c$i", title = "Chapter $i",
        chapterIndex = i.toDouble(), url = "https://example.com/c$i", downloadState = state
    )

    @Test
    fun usesTheSameJobIdsAndPathsAsTheDartQueue() {
        // Dart: 'dl_' + sha256('$bookId:$sourceChapterId'), chapters/<sha(book)>_<sha(chapter)>.html
        val jobs = AutoDownloadQueue.persist(db, "b", "src", listOf(chapter(1)), dir, nowSec = 10)
        assertEquals(1, jobs.size)
        assertEquals("dl_" + HonUpdateCheckWorker.sha256("b:c1"), jobs[0].jobId)
        assertEquals(
            "${dir.path}/${HonUpdateCheckWorker.sha256("b")}_${HonUpdateCheckWorker.sha256("c1")}.html",
            jobs[0].targetPath
        )
        db.rawQuery("SELECT status, chapter_id, source_id FROM download_jobs_table", null).use {
            assertTrue(it.moveToFirst())
            assertEquals("queued", it.getString(0))
            assertEquals("b:c1", it.getString(1))
            assertEquals("src", it.getString(2))
        }
        db.rawQuery("SELECT download_state, local_file_path FROM chapters_table WHERE id = 'b:c1'", null).use {
            assertTrue(it.moveToFirst())
            assertEquals("queued", it.getString(0))
            assertEquals(jobs[0].targetPath, it.getString(1))
        }
    }

    @Test
    fun skipsDownloadedChaptersAndJobsAlreadyInFlight() {
        db.insert("download_jobs_table", null, ContentValues().apply {
            put("id", AutoDownloadQueue.jobId("b", "c2")); put("book_id", "b"); put("chapter_id", "b:c2")
            put("chapter_title", "Chapter 2"); put("source_id", "src"); put("status", "paused")
            put("created_at", 1L); put("updated_at", 1L)
        })
        val jobs = AutoDownloadQueue.persist(
            db, "b", "src", listOf(chapter(1, "downloaded"), chapter(2), chapter(3)), dir
        )
        assertEquals(listOf("b:c3"), jobs.map { it.chapterId })
        db.rawQuery("SELECT status FROM download_jobs_table WHERE chapter_id = 'b:c2'", null).use {
            assertTrue(it.moveToFirst())
            assertEquals("paused", it.getString(0))
        }
    }

    @Test
    fun updateCheckReportsOnlyChaptersAddedSinceTheLastCheck() = kotlinx.coroutines.runBlocking {
        val reported = mutableListOf<String>()
        val database = object : UpdateCheckDatabase {
            var existing = listOf(chapter(1))
            override fun queryOngoingCandidates(enabledSourceIds: Set<String>, limit: Int) =
                listOf(Triple("b", "src", "novel"))
            override fun queryExistingChapters(bookId: String) = existing
            override fun saveReconciledChapters(
                bookId: String, newChapters: List<ExistingChapter>,
                updatedChapters: List<ExistingChapter>, totalChapters: Int
            ) {}
            override fun touchBookUpdatedAt(bookId: String) {}
        }
        HonUpdateCheckWorker.performUpdateCheck(
            database = database,
            enabledSourceIds = setOf("src"),
            networkFetcher = { _, _ ->
                listOf(ChapterData("c1", "Chapter 1", "u1", 0.0), ChapterData("c2", "Chapter 2", "u2", 1.0))
            },
            notifier = { _, _ -> },
            delayProvider = {},
            onNewChapters = { _, _, chapters -> reported += chapters.map { it.id } }
        )
        assertEquals(listOf("b:c2"), reported)

        // A book's first check saves its whole list without queueing it.
        reported.clear()
        database.existing = emptyList()
        HonUpdateCheckWorker.performUpdateCheck(
            database = database,
            enabledSourceIds = setOf("src"),
            networkFetcher = { _, _ -> listOf(ChapterData("c1", "Chapter 1", "u1", 0.0)) },
            notifier = { _, _ -> },
            delayProvider = {},
            onNewChapters = { _, _, chapters -> reported += chapters.map { it.id } }
        )
        assertTrue(reported.isEmpty())
    }
}
