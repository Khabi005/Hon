package com.hon.reader.hon.shosetsu

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.luaj.vm2.*
import org.luaj.vm2.lib.OneArgFunction
import org.luaj.vm2.lib.TwoArgFunction
import org.luaj.vm2.lib.VarArgFunction
import org.luaj.vm2.lib.jse.JsePlatform
import java.util.concurrent.TimeUnit

class ShosetsuKotlinEngine {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(35, TimeUnit.SECONDS)
        .build()

    suspend fun search(luaScript: String, query: String, page: Int): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val globals = createSandboxedGlobals()
        globals.load(luaScript).call()

        val searchFn = globals.get("Search")
        if (searchFn.isnil()) {
            throw IllegalArgumentException("Script does not export Search function")
        }

        val result = searchFn.call(LuaValue.valueOf(query), LuaValue.valueOf(page))
        return@withContext parseNovelList(result)
    }

    suspend fun parseNovel(luaScript: String, novelUrl: String, loadChapters: Boolean): Map<String, Any?> = withContext(Dispatchers.IO) {
        val globals = createSandboxedGlobals()
        globals.load(luaScript).call()

        val parseFn = globals.get("Parse")
        if (parseFn.isnil()) {
            throw IllegalArgumentException("Script does not export Parse function")
        }

        val result = parseFn.call(LuaValue.valueOf(novelUrl), LuaValue.valueOf(loadChapters))
        return@withContext parseNovelDetails(result)
    }

    suspend fun getPassage(luaScript: String, chapterUrl: String): String = withContext(Dispatchers.IO) {
        val globals = createSandboxedGlobals()
        globals.load(luaScript).call()

        val passageFn = globals.get("Passage")
        if (passageFn.isnil()) {
            throw IllegalArgumentException("Script does not export Passage function")
        }

        val result = passageFn.call(LuaValue.valueOf(chapterUrl))
        return@withContext result.tojstring()
    }

    private fun createSandboxedGlobals(): Globals {
        val globals = JsePlatform.standardGlobals()

        // Strip dangerous libraries
        globals.set("os", LuaValue.NIL)
        globals.set("io", LuaValue.NIL)
        globals.set("luajava", LuaValue.NIL)
        globals.set("debug", LuaValue.NIL)

        // Shosetsu standard global functions
        globals.set("Require", object : OneArgFunction() {
            override fun call(arg: LuaValue): LuaValue {
                val mod = arg.tojstring()
                return when (mod) {
                    "FilterOptions" -> createFilterOptionsModule()
                    "url" -> createUrlModule()
                    else -> LuaTable()
                }
            }
        })

        globals.set("GET", object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val url = args.arg(1).tojstring()
                return executeHttpRequest(url, "GET", null)
            }
        })

        globals.set("POST", object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val url = args.arg(1).tojstring()
                return executeHttpRequest(url, "POST", null)
            }
        })

        return globals
    }

    private fun executeHttpRequest(url: String, method: String, headers: LuaTable?): Varargs {
        val requestBuilder = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile; Hon/1.0)")
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")

        val response = httpClient.newCall(requestBuilder.build()).execute()
        val htmlContent = response.body?.string() ?: ""

        val responseTable = LuaTable()
        responseTable.set("code", LuaValue.valueOf(response.code))
        responseTable.set("body", LuaValue.valueOf(htmlContent))

        // Wrap Jsoup DOM query functions directly on the response table
        val doc = Jsoup.parse(htmlContent, url)
        wrapElementMethods(responseTable, doc)

        return responseTable
    }

    private fun wrapElementMethods(table: LuaTable, element: Element) {
        table.set("select", object : TwoArgFunction() {
            override fun call(self: LuaValue, cssSelector: LuaValue): LuaValue {
                val query = cssSelector.tojstring()
                val elements = element.select(query)
                val listTable = LuaTable()
                for (i in 0 until elements.size) {
                    val el = elements[i]
                    val elTable = LuaTable()
                    wrapElementMethods(elTable, el)
                    listTable.set(i + 1, elTable)
                }
                return listTable
            }
        })

        table.set("text", object : OneArgFunction() {
            override fun call(self: LuaValue): LuaValue {
                return LuaValue.valueOf(element.text())
            }
        })

        table.set("attr", object : TwoArgFunction() {
            override fun call(self: LuaValue, attrName: LuaValue): LuaValue {
                return LuaValue.valueOf(element.attr(attrName.tojstring()))
            }
        })

        table.set("first", object : OneArgFunction() {
            override fun call(self: LuaValue): LuaValue {
                val firstChild = element.children().firstOrNull() ?: return LuaValue.NIL
                val elTable = LuaTable()
                wrapElementMethods(elTable, firstChild)
                return elTable
            }
        })

        table.set("last", object : OneArgFunction() {
            override fun call(self: LuaValue): LuaValue {
                val lastChild = element.children().lastOrNull() ?: return LuaValue.NIL
                val elTable = LuaTable()
                wrapElementMethods(elTable, lastChild)
                return elTable
            }
        })

        table.set("html", object : OneArgFunction() {
            override fun call(self: LuaValue): LuaValue {
                return LuaValue.valueOf(element.html())
            }
        })
    }

    private fun createFilterOptionsModule(): LuaTable {
        val module = LuaTable()
        module.set("new", object : OneArgFunction() {
            override fun call(arg: LuaValue): LuaValue {
                return LuaTable()
            }
        })
        return module
    }

    private fun createUrlModule(): LuaTable {
        val module = LuaTable()
        val qs = LuaTable()
        qs.set("stringify", object : OneArgFunction() {
            override fun call(arg: LuaValue): LuaValue {
                if (!arg.istable()) return LuaValue.valueOf("")
                val table = arg.checktable()
                val sb = StringBuilder()
                var first = true
                var k = LuaValue.NIL
                while (true) {
                    val next = table.next(k)
                    k = next.arg1()
                    if (k.isnil()) break
                    val v = next.arg(2)
                    if (!first) sb.append("&")
                    sb.append(k.tojstring()).append("=").append(v.tojstring())
                    first = false
                }
                return LuaValue.valueOf(sb.toString())
            }
        })
        module.set("querystring", qs)
        return module
    }

    private fun parseNovelList(result: LuaValue): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        if (!result.istable()) return list

        val table = result.checktable()
        val len = table.length()
        for (i in 1..len) {
            val item = table.get(i)
            if (item.istable()) {
                val novelMap = mutableMapOf<String, Any?>()
                novelMap["id"] = item.get("id").takeIf { !it.isnil() }?.tojstring() ?: ""
                novelMap["title"] = item.get("title").takeIf { !it.isnil() }?.tojstring() ?: ""
                novelMap["cover"] = item.get("image").takeIf { !it.isnil() }?.tojstring()
                    ?: item.get("cover").takeIf { !it.isnil() }?.tojstring()
                novelMap["author"] = item.get("author").takeIf { !it.isnil() }?.tojstring() ?: ""
                list.add(novelMap)
            }
        }
        return list
    }

    private fun parseNovelDetails(result: LuaValue): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        if (!result.istable()) return map

        map["title"] = result.get("title").takeIf { !it.isnil() }?.tojstring() ?: ""
        map["author"] = result.get("author").takeIf { !it.isnil() }?.tojstring()
            ?: result.get("authors").takeIf { !it.isnil() }?.tojstring() ?: ""
        map["synopsis"] = result.get("description").takeIf { !it.isnil() }?.tojstring()
            ?: result.get("synopsis").takeIf { !it.isnil() }?.tojstring() ?: ""
        map["cover"] = result.get("image").takeIf { !it.isnil() }?.tojstring()
            ?: result.get("cover").takeIf { !it.isnil() }?.tojstring()

        val chaptersList = mutableListOf<Map<String, Any?>>()
        val chaptersVal = result.get("chapters")
        if (chaptersVal.istable()) {
            val chTable = chaptersVal.checktable()
            for (i in 1..chTable.length()) {
                val chItem = chTable.get(i)
                if (chItem.istable()) {
                    chaptersList.add(mapOf(
                        "id" to (chItem.get("id").takeIf { !it.isnil() }?.tojstring() ?: ""),
                        "title" to (chItem.get("title").takeIf { !it.isnil() }?.tojstring() ?: "Chapter $i"),
                        "url" to (chItem.get("url").takeIf { !it.isnil() }?.tojstring()
                            ?: chItem.get("id").takeIf { !it.isnil() }?.tojstring() ?: "")
                    ))
                }
            }
        }
        map["chapters"] = chaptersList
        return map
    }
}
