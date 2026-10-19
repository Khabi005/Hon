package com.hon.reader.hon

import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import kotlinx.coroutines.runBlocking
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.luaj.vm2.LuaError
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
    fun testGutenbergSearchWithSpacesBuildsValidQuery() = runBlocking {
        var receivedQuery: String? = null
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            receivedQuery = chain.request().url.queryParameter("query")
            Response.Builder()
                .request(chain.request())
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body(sampleGutenbergSearchHtml.toResponseBody("text/html".toMediaType()))
                .build()
        }.build()
        val results = ShosetsuKotlinEngine(client).search(loadBundledGutenbergScript(), "a double story", 0)
        assertEquals("a double story", receivedQuery)
        assertEquals(2, results.size)
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
        assertTrue(globals.get("package").isnil())
        assertTrue(globals.get("require").isnil())
        assertTrue(globals.get("loadfile").isnil())
        assertTrue(globals.get("dofile").isnil())
    }

    @Test(timeout = 10000)
    fun testInfiniteLuaLoopStopsAtInstructionBudget() = runBlocking {
        val engine = ShosetsuKotlinEngine(createMockClient())
        val script = "return { search = function(_) while true do end end }"
        try {
            engine.search(script, "anything", 0)
            fail("The extension should have been stopped")
        } catch (error: LuaError) {
            assertTrue(error.message.orEmpty().contains("execution budget"))
        }
    }

    @Test
    fun testInstalledExtensionValidationChecksRequiredMethods() = runBlocking {
        val engine = ShosetsuKotlinEngine(createMockClient())
        val valid = "return { search = function(_) return {} end, parseNovel = function(_) return {} end, getPassage = function(_) return 'chapter' end }"
        assertTrue(engine.validateExtension(valid))
        try {
            engine.validateExtension("return { search = function(_) return {} end }")
            fail("Incomplete extension should fail validation")
        } catch (error: IllegalArgumentException) {
            assertTrue(error.message.orEmpty().contains("parseNovel"))
        }
    }
    @Test fun listingOnlyExtensionIsSupportedAndUnknownModulesFail() = runBlocking {
        val engine = ShosetsuKotlinEngine(createMockClient())
        val script = """
            return {
              parseNovel = function() return {} end,
              getPassage = function() return "<p>text</p>" end,
              listings = { Listing("All", false, function() return { Novel { title = "A title", link = "/1" } } end) }
            }
        """.trimIndent()
        assertTrue(engine.validateExtension(script))
        assertEquals("A title", engine.search(script, "", 0).single()["title"])
        try {
            engine.validateExtension("local x = Require('missing'); return {}")
            fail("Unknown dependencies must not be replaced by empty tables")
        } catch (expected: LuaError) {
            assertTrue(expected.message!!.contains("Unsupported extension module"))
        }
    }

    @Test fun cachedBytecodeDoesNotShareSourceGlobalsBetweenRequests() = runBlocking {
        val engine = ShosetsuKotlinEngine(createMockClient())
        val script = """
            local count = 0
            return {
              search = function() count = count + 1; return {Novel {title = tostring(count), link = "/book"}} end,
              parseNovel = function() return {} end,
              getPassage = function() return "<p>text</p>" end
            }
        """.trimIndent()
        assertEquals("1", engine.search(script, "a", 0).single()["title"])
        assertEquals("1", engine.search(script, "b", 0).single()["title"])
    }

    @Test fun searchAndSettingsReceiveTypedDefaultsIncludingNestedGroups() = runBlocking {
        val engine = ShosetsuKotlinEngine(createMockClient())
        val script = """
            local settings = {}
            return {
              searchFilters = {FilterGroup("Options", {TextFilter(5, "Text"), DropdownFilter(6, "Sort", {"A", "B"}), CheckboxFilter(7, "Check")})},
              settings = {SwitchFilter(3, "Show notes")},
              updateSetting = function(id, value) settings[id] = value end,
              search = function(data)
                assert(data[5] == "" and data[6] == 0 and data[7] == false)
                assert(settings[3] == false)
                return {Novel {title="Defaults", link="/book"}}
              end,
              parseNovel = function() return {} end,
              getPassage = function() assert(settings[3] == false); return "<p>text</p>" end
            }
        """.trimIndent()
        assertEquals("Defaults", engine.search(script, "query", 0).single()["title"])
        assertTrue(engine.getPassage(script, "/chapter").contains("text"))
    }

    @Test fun emptyBrowseUsesSelectedListingAndMetadataPaginationContract() = runBlocking {
        val engine = ShosetsuKotlinEngine(createMockClient())
        val script = """
            return {
              search = function() return {Novel {title="Search",link="search"}} end,
              parseNovel = function() return {} end,
              getPassage = function() return "text" end,
              listings = {
                Listing("Latest", true, function(data) return {Novel {title=tostring(data[PAGE]),link="latest"}} end),
                Listing("All", false, function(data) return {Novel {title="All",link="all"}} end)
              }
            }
        """.trimIndent()
        assertEquals("1", engine.search(script, "", 0).single()["title"])
        assertEquals("2", engine.search(script, "", 1).single()["title"])
        assertEquals("All", engine.search(script, "", 0, 1).single()["title"])
        val listings = engine.describeExtension(script)["listings"] as List<*>
        assertEquals(true, (listings[0] as Map<*, *>)["incrementing"])
        assertEquals(false, (listings[1] as Map<*, *>)["incrementing"])
    }

}
