package com.hon.reader.hon

import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import kotlinx.coroutines.runBlocking
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.luaj.vm2.LuaError

class ShosetsuCompatibilityTest {
    private fun resource(path: String) = javaClass.classLoader!!.getResourceAsStream("shosetsu/$path")!!.bufferedReader().use { it.readText() }
    private fun bundle(name: String): String = buildString {
        append("local modules, cache = {}, {}\nlocal builtin = Require\nlocal function Require(name) if cache[name] then return cache[name] end; if not modules[name] then return builtin(name) end; local value = modules[name](); cache[name] = value; return value end\n")
        for (library in listOf("url", "WPCommon", "Bixbox", "Madara")) {
            append("modules['$library'] = function()\n${resource("lib/$library.lua")}\nend\n")
        }
        append("return (function()\n${resource("src/$name.lua")}\nend)()")
    }
    private fun client(body: (Request) -> String) = OkHttpClient.Builder().addInterceptor { chain ->
        Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
            .body(body(chain.request()).toResponseBody("text/html; charset=utf-8".toMediaType())).build()
    }.build()

    @Test fun loadsRealWordpressBixboxAndMadaraExtensions() = runBlocking {
        val engine = ShosetsuKotlinEngine(client { error("Structural validation must not fetch a website") })
        for (source in listOf("Bakapervert", "KnoxT", "ZetroTranslation")) assertTrue("Could not load $source", engine.validateExtension(bundle(source)))
    }

    @Test fun madaraSearchUsesOneBasedPagesAndPreservesInlineChapterContent() = runBlocking {
        val engine = ShosetsuKotlinEngine(client { request ->
            if (request.url.encodedPath.startsWith("/page/")) {
                assertEquals("/page/1/", request.url.encodedPath)
                assertEquals("a double story", request.url.queryParameter("s"))
                "<div class='c-tabs-item__content'><a href='https://zetrotranslation.com/novel/story/'><h3>Story</h3><img src='/cover.png'></a></div>"
            } else {
                "<div class='c-blog-post'><ol class='breadcrumb'><li class='active'>Chapter One</li></ol><div class='text-left'><p>A <em>Unicode 日本語</em> passage.</p><div class='ezoic-ad'>Advert</div><img src='/map.png'></div></div>"
            }
        })
        val script = bundle("ZetroTranslation")
        assertEquals("Story", engine.search(script, "a double story", 0).single()["title"])
        val passage = engine.getPassage(script, "story/chapter-1/")
        assertTrue(passage.contains("<em>Unicode 日本語</em>"))
        assertTrue(passage.contains("https://zetrotranslation.com/map.png"))
        assertFalse(passage.contains("Advert"))
    }

    @Test fun bixboxSearchAndPassageUseCollectionsAndSharedLibraryCallbacks() = runBlocking {
        val engine = ShosetsuKotlinEngine(client { request ->
            if (request.url.encodedPath.startsWith("/page/")) {
                assertEquals("/page/1/", request.url.encodedPath)
                "<div class='listupd'><article><div><a href='https://knoxt.space/series/a/'><span class='ntitle'>A Novel</span><img src='/cover.png'></a></div></article></div>"
            } else {
                "<div class='epwrapper'><h1 class='entry-title'>Chapter One</h1><div class='epcontent'><p>Selected <strong>passage</strong> 🌙.</p><div class='code-block'>Advert</div></div></div>"
            }
        })
        val script = bundle("KnoxT")
        assertEquals("A Novel", engine.search(script, "novel", 0).single()["title"])
        val passage = engine.getPassage(script, "chapter-one/")
        assertTrue(passage.contains("<strong>passage</strong>"))
        assertFalse(passage.contains("Advert"))
    }

    @Test fun madaraAjaxPassesFormBodyAndMapsChapterOrder() = runBlocking {
        var posts = 0
        val engine = ShosetsuKotlinEngine(client { request ->
            if (request.method == "POST") {
                posts++
                val body = request.body as FormBody
                assertEquals("manga_get_chapters", body.value(0))
                assertEquals("42", body.value(1))
                "<li class='wp-manga-chapter free-chap'><a href='https://zetrotranslation.com/novel/story/2/'>Second</a><span class='chapter-release-date'>Today</span></li><li class='wp-manga-chapter free-chap'><a href='https://zetrotranslation.com/novel/story/1/'>First</a><span class='chapter-release-date'>Today</span></li>"
            } else {
                "<div class='post-title'><h1>Story <span>HOT</span></h1></div><div class='post-content'><div class='author-content'><a>A Writer</a></div></div><div class='post-status'><div class='post-content_item'><div class='summary-content'>Completed</div></div></div><div class='summary__content'><p>Summary.</p></div><a class='wp-manga-action-button' data-post='42'></a>"
            }
        })
        val details = engine.parseNovel(bundle("ZetroTranslation"), "story/", true)
        assertEquals("Story", details["title"])
        assertEquals("A Writer", details["author"])
        assertEquals(1, posts)
        val chapters = details["chapters"] as List<*>
        assertEquals("First", (chapters.first() as Map<*, *>)["title"])
    }

    @Test fun hostObjectsCannotExposeJavaReflectionOrFileAndProcessApis() {
        val engine = ShosetsuKotlinEngine()
        val globals = engine.createSandboxedGlobals()
        val result = globals.load("local d = Document('<p>text</p>'); return d.getClass == nil and d.class == nil and d.javaClass == nil and d:body().getClass == nil and HeadersBuilder().getClass == nil").call()
        assertTrue(result.toboolean())
        for (name in listOf("os", "io", "luajava", "load", "loadfile", "dofile", "require", "debug")) assertTrue(globals.get(name).isnil())
    }
    @Test fun royalRoadUsesRealDomTextNodesAndSiblingCapabilities() = runBlocking {
        val script = java.io.File(System.getProperty("hon.bundledSources"), "ext_934c81536620b80bcb8750e8e3170dbacc8e3defb15fa28e56a9c9fd65666ebe.lua").readText()
        val engine = ShosetsuKotlinEngine(client {
            "<html><head></head><body><div class='chapter-page'><div class='fic-header'><h1>Chapter One</h1></div><div class='author-note-portlet'><div class='portlet-title'>Author note</div><p>A note before.</p></div><div class='chapter-content'><p>  A <em>real</em> passage.</p><p>Another paragraph.</p></div><div class='author-note-portlet'><div class='portlet-title'>Afterword</div><p>A note after.</p></div></div></body></html>"
        })
        val passage = engine.getPassage(script, "123/chapter-one")
        assertTrue(passage.contains("<em>real</em>"))
        assertTrue(passage.contains("Another paragraph."))
        assertTrue(passage.contains("A note before."))
        assertTrue(passage.contains("A note after."))
    }

}
