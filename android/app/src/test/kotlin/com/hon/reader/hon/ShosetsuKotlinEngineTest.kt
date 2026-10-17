package com.hon.reader.hon

import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import kotlinx.coroutines.runBlocking
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class ShosetsuKotlinEngineTest {

    private val sampleGutenbergSearchHtml = """
        <!DOCTYPE html>
        <html>
        <body>
            <li class="booklink">
                <span class="title">Pride and Prejudice</span>
                <a class="link" href="/ebooks/1342">Link</a>
                <img class="cover-thumb" src="/cache/epub/1342/pg1342.cover.small.jpg" />
            </li>
            <li class="booklink">
                <span class="title">Frankenstein; Or, The Modern Prometheus</span>
                <a class="link" href="/ebooks/84">Link</a>
                <img class="cover-thumb" src="/cache/epub/84/pg84.cover.small.jpg" />
            </li>
        </body>
        </html>
    """.trimIndent()

    private val sampleGutenbergNovelHtml = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta property="og:url" content="https://www.gutenberg.org/ebooks/1342" />
        </head>
        <body>
            <h1 itemprop="headline">Pride and Prejudice</h1>
            <img class="cover-art" src="https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg" />
            <div class="readmore-container">
                A classic story of love and manners.
                <span class="toggle-content"> Exploring Elizabeth Bennet's journey.</span>
            </div>
            <div itemprop="creator">Jane Austen</div>
            <div property="dcterms:subject">Courtship -- Fiction</div>
            <div property="dcterms:subject">Sisters -- Fiction</div>
            <meta itemprop="inLanguage" content="en" />
            <a class="read-online-button" href="/ebooks/1342.html.images">Read Online</a>
            <div itemprop="datePublished">1998-06-01</div>
        </body>
        </html>
    """.trimIndent()

    private val sampleGutenbergPassageHtml = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Pride and Prejudice</title>
        </head>
        <body>
            <div class="chapter">
                <h2>CHAPTER I.</h2>
                <p>It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.</p>
            </div>
        </body>
        </html>
    """.trimIndent()

    private fun createMockClient(): OkHttpClient {
        return OkHttpClient.Builder()
            .addInterceptor { chain ->
                val url = chain.request().url.toString()
                val (content, code) = when {
                    url.contains("ebooks/search") -> Pair(sampleGutenbergSearchHtml, 200)
                    url.contains("/ebooks/1342.html") -> Pair(sampleGutenbergPassageHtml, 200)
                    url.contains("/ebooks/1342") -> Pair(sampleGutenbergNovelHtml, 200)
                    else -> Pair("<html><body>Not Found</body></html>", 404)
                }

                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(code)
                    .message("OK")
                    .body(content.toResponseBody("text/html; charset=utf-8".toMediaType()))
                    .build()
            }
            .build()
    }

    private fun loadBundledGutenbergScript(): String {
        // Resolve assets/sources/gutenberg.lua relative to project root
        val possiblePaths = listOf(
            File("assets/sources/gutenberg.lua"),
            File("../../assets/sources/gutenberg.lua"),
            File("../../../assets/sources/gutenberg.lua"),
            File("/home/khabi005/Flutter Prjoct/Hon/assets/sources/gutenberg.lua")
        )
        for (f in possiblePaths) {
            if (f.exists()) return f.readText()
        }
        throw IllegalStateException("assets/sources/gutenberg.lua not found in search paths")
    }

    @Test
    fun testKotlinEngineConsumesBundledGutenbergScriptAndSearches() = runBlocking {
        val script = loadBundledGutenbergScript()
        val engine = ShosetsuKotlinEngine(createMockClient())

        val results = engine.search(script, "pride", 0)
        assertNotNull(results)
        assertEquals(2, results.size)

        val first = results[0]
        assertEquals("Pride and Prejudice", first["title"])
        assertEquals("/ebooks/1342", first["id"])
        assertTrue((first["cover"] as String).contains("pg1342.cover.small.jpg"))
    }

    @Test
    fun testKotlinEngineParsesNovelDetailsAndChapters() = runBlocking {
        val script = loadBundledGutenbergScript()
        val engine = ShosetsuKotlinEngine(createMockClient())

        val details = engine.parseNovel(script, "/ebooks/1342", true)
        assertNotNull(details)
        assertEquals("Pride and Prejudice", details["title"])
        assertEquals("Jane Austen", details["author"])
        assertTrue((details["synopsis"] as String).contains("Elizabeth Bennet"))

        @Suppress("UNCHECKED_CAST")
        val chapters = details["chapters"] as List<Map<String, Any?>>
        assertNotNull(chapters)
        assertEquals(1, chapters.size)
        assertEquals("/ebooks/1342.html.images", chapters[0]["url"])
    }

    @Test
    fun testKotlinEngineRetrievesPassage() = runBlocking {
        val script = loadBundledGutenbergScript()
        val engine = ShosetsuKotlinEngine(createMockClient())

        val passage = engine.getPassage(script, "/ebooks/1342.html.images")
        assertNotNull(passage)
        assertTrue(passage.contains("truth universally acknowledged"))
        assertTrue(passage.contains("CHAPTER I."))
    }

    @Test
    fun testKotlinEngineHostSandboxingNeutralizesDangerousGlobals() {
        val engine = ShosetsuKotlinEngine(createMockClient())
        val globals = engine.createSandboxedGlobals()

        assertTrue(globals.get("os").isnil())
        assertTrue(globals.get("io").isnil())
        assertTrue(globals.get("luajava").isnil())
        assertTrue(globals.get("debug").isnil())
    }
}
