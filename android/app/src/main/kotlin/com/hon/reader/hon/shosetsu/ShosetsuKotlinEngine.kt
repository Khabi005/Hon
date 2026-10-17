package com.hon.reader.hon.shosetsu

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import org.luaj.vm2.*
import org.luaj.vm2.lib.OneArgFunction
import org.luaj.vm2.lib.ThreeArgFunction
import org.luaj.vm2.lib.TwoArgFunction
import org.luaj.vm2.lib.VarArgFunction
import org.luaj.vm2.lib.jse.JsePlatform
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class ShosetsuKotlinEngine(
    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(35, TimeUnit.SECONDS)
        .build()
) {

    suspend fun search(luaScript: String, query: String, page: Int): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val (globals, extensionTable) = loadExtension(luaScript)
        val searchFn = extensionTable.get("search")
        if (searchFn.isnil() || !searchFn.isfunction()) {
            throw IllegalArgumentException("Script does not export 'search' function in returned extension table")
        }

        val data = LuaTable()
        data.set(globals.get("QUERY"), LuaValue.valueOf(query))
        data.set(globals.get("PAGE"), LuaValue.valueOf(page))
        data.set(LuaValue.valueOf("query"), LuaValue.valueOf(query))
        data.set(LuaValue.valueOf("page"), LuaValue.valueOf(page))

        val result = searchFn.call(data)
        return@withContext parseNovelList(result)
    }

    suspend fun parseNovel(luaScript: String, novelUrl: String, loadChapters: Boolean): Map<String, Any?> = withContext(Dispatchers.IO) {
        val (_, extensionTable) = loadExtension(luaScript)
        val parseFn = extensionTable.get("parseNovel")
        if (parseFn.isnil() || !parseFn.isfunction()) {
            throw IllegalArgumentException("Script does not export 'parseNovel' function in returned extension table")
        }

        val result = parseFn.call(LuaValue.valueOf(novelUrl), LuaValue.valueOf(loadChapters))
        return@withContext parseNovelDetails(result)
    }

    suspend fun getPassage(luaScript: String, chapterUrl: String): String = withContext(Dispatchers.IO) {
        val (_, extensionTable) = loadExtension(luaScript)
        val passageFn = extensionTable.get("getPassage")
        if (passageFn.isnil() || !passageFn.isfunction()) {
            throw IllegalArgumentException("Script does not export 'getPassage' function in returned extension table")
        }

        val result = passageFn.call(LuaValue.valueOf(chapterUrl))
        return@withContext result.tojstring()
    }

    private fun loadExtension(luaScript: String): Pair<Globals, LuaTable> {
        val globals = createSandboxedGlobals()
        val chunk = globals.load(luaScript)
        val extensionTable = chunk.call()
        if (!extensionTable.istable()) {
            throw IllegalArgumentException("Upstream Shosetsu extension script must return an extension table")
        }
        return Pair(globals, extensionTable.checktable())
    }

    fun createSandboxedGlobals(): Globals {
        val globals = JsePlatform.standardGlobals()

        // Strip dangerous host libraries for security
        globals.set("os", LuaValue.NIL)
        globals.set("io", LuaValue.NIL)
        globals.set("luajava", LuaValue.NIL)
        globals.set("debug", LuaValue.NIL)
        val packageTable = globals.get("package")
        if (packageTable.istable()) {
            packageTable.set("loadlib", LuaValue.NIL)
        }

        // Shosetsu standard constants
        globals.set("QUERY", LuaValue.valueOf(0))
        globals.set("PAGE", LuaValue.valueOf(1))

        val novelStatus = LuaTable()
        novelStatus.set("UNKNOWN", LuaValue.valueOf(0))
        novelStatus.set("PUBLISHING", LuaValue.valueOf(1))
        novelStatus.set("COMPLETED", LuaValue.valueOf(2))
        novelStatus.set("PAUSED", LuaValue.valueOf(3))
        novelStatus.set("DROPPED", LuaValue.valueOf(4))
        globals.set("NovelStatus", novelStatus)

        val chapterType = LuaTable()
        chapterType.set("HTML", LuaValue.valueOf(1))
        chapterType.set("TEXT", LuaValue.valueOf(2))
        globals.set("ChapterType", chapterType)

        // Shosetsu standard types / constructors
        globals.set("Novel", object : OneArgFunction() {
            override fun call(arg: LuaValue): LuaValue = if (arg.istable()) arg else LuaTable()
        })

        globals.set("NovelInfo", object : OneArgFunction() {
            override fun call(arg: LuaValue): LuaValue {
                val table = if (arg.istable()) arg.checktable() else LuaTable()
                table.set("setChapters", object : TwoArgFunction() {
                    override fun call(self: LuaValue, chapters: LuaValue): LuaValue {
                        self.set("chapters", chapters)
                        return self
                    }
                })
                return table
            }
        })

        globals.set("NovelChapter", object : OneArgFunction() {
            override fun call(arg: LuaValue): LuaValue = if (arg.istable()) arg else LuaTable()
        })

        globals.set("AsList", object : OneArgFunction() {
            override fun call(arg: LuaValue): LuaValue = arg
        })

        globals.set("List", object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs = LuaTable()
        })

        globals.set("Listing", object : ThreeArgFunction() {
            override fun call(name: LuaValue, inc: LuaValue, fn: LuaValue): LuaValue {
                val t = LuaTable()
                t.set("name", name)
                t.set("increments", inc)
                t.set("fn", fn)
                return t
            }
        })

        globals.set("DropdownFilter", object : ThreeArgFunction() {
            override fun call(id: LuaValue, name: LuaValue, options: LuaValue): LuaValue {
                val t = LuaTable()
                t.set("id", id)
                t.set("name", name)
                t.set("options", options)
                return t
            }
        })

        globals.set("SwitchFilter", object : TwoArgFunction() {
            override fun call(id: LuaValue, name: LuaValue): LuaValue {
                val t = LuaTable()
                t.set("id", id)
                t.set("name", name)
                return t
            }
        })

        // Standard Shosetsu collection helper: map(list, fn)
        globals.set("map", object : TwoArgFunction() {
            override fun call(list: LuaValue, fn: LuaValue): LuaValue {
                val res = LuaTable()
                var outIdx = 1
                if (list.istable()) {
                    val tbl = list.checktable()
                    val sizeFn = tbl.get("size")
                    if (sizeFn.isfunction()) {
                        val size = sizeFn.call(tbl).toint()
                        val getFn = tbl.get("get")
                        for (i in 0 until size) {
                            val item = getFn.call(tbl, LuaValue.valueOf(i))
                            val mapped = fn.call(item, LuaValue.valueOf(i))
                            if (!mapped.isnil()) {
                                res.set(outIdx++, mapped)
                            }
                        }
                    } else {
                        val len = tbl.length()
                        for (i in 1..len) {
                            val item = tbl.get(i)
                            val mapped = fn.call(item, LuaValue.valueOf(i - 1))
                            if (!mapped.isnil()) {
                                res.set(outIdx++, mapped)
                            }
                        }
                    }
                }
                return res
            }
        })

        // Shosetsu standard: pageOfElem(doc, removeStyles)
        globals.set("pageOfElem", object : TwoArgFunction() {
            override fun call(docOrElem: LuaValue, removeStyles: LuaValue): LuaValue {
                if (docOrElem.istable()) {
                    val bodyFn = docOrElem.get("body")
                    if (bodyFn.isfunction()) {
                        val body = bodyFn.call(docOrElem)
                        val htmlFn = body.get("html")
                        if (htmlFn.isfunction()) {
                            return htmlFn.call(body)
                        }
                    }
                    val htmlFn = docOrElem.get("html")
                    if (htmlFn.isfunction()) {
                        return htmlFn.call(docOrElem)
                    }
                }
                return LuaValue.valueOf(docOrElem.tojstring())
            }
        })

        // Shosetsu Require("FilterOptions") and Require("url")
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

        // Shosetsu GETDocument(url)
        globals.set("GETDocument", object : OneArgFunction() {
            override fun call(arg: LuaValue): LuaValue {
                val url = arg.tojstring()
                return executeHttpDocument(url)
            }
        })

        // Shosetsu raw GET(url)
        globals.set("GET", object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val url = args.arg(1).tojstring()
                return executeHttpRequest(url, "GET")
            }
        })

        // Shosetsu raw POST(url)
        globals.set("POST", object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val url = args.arg(1).tojstring()
                return executeHttpRequest(url, "POST")
            }
        })

        return globals
    }

    private fun executeHttpDocument(url: String): LuaValue {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile; Hon/1.0)")
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            .build()

        val response = httpClient.newCall(request).execute()
        if (!response.isSuccessful) {
            throw IllegalStateException("HTTP GET failed with code ${response.code} for $url")
        }
        val html = response.body?.string() ?: ""
        val doc = Jsoup.parse(html, url)
        val docTable = LuaTable()
        wrapDocumentMethods(docTable, doc)
        return docTable
    }

    private fun executeHttpRequest(url: String, method: String): Varargs {
        val requestBuilder = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile; Hon/1.0)")
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")

        val response = httpClient.newCall(requestBuilder.build()).execute()
        val htmlContent = response.body?.string() ?: ""

        val responseTable = LuaTable()
        responseTable.set("code", LuaValue.valueOf(response.code))
        responseTable.set("body", LuaValue.valueOf(htmlContent))

        val doc = Jsoup.parse(htmlContent, url)
        wrapDocumentMethods(responseTable, doc)

        return responseTable
    }

    private fun wrapDocumentMethods(table: LuaTable, doc: Document) {
        wrapElementMethods(table, doc)

        table.set("head", object : OneArgFunction() {
            override fun call(self: LuaValue): LuaValue {
                val headEl = doc.head() ?: doc
                val elTable = LuaTable()
                wrapElementMethods(elTable, headEl)
                return elTable
            }
        })

        table.set("body", object : OneArgFunction() {
            override fun call(self: LuaValue): LuaValue {
                val bodyEl = doc.body() ?: doc
                val elTable = LuaTable()
                wrapElementMethods(elTable, bodyEl)
                return elTable
            }
        })
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
                listTable.set("size", object : OneArgFunction() {
                    override fun call(s: LuaValue): LuaValue = LuaValue.valueOf(elements.size)
                })
                listTable.set("get", object : TwoArgFunction() {
                    override fun call(s: LuaValue, idx: LuaValue): LuaValue {
                        val i = idx.toint()
                        if (i in 0 until elements.size) {
                            return listTable.get(i + 1)
                        }
                        return LuaValue.NIL
                    }
                })
                listTable.set("text", object : OneArgFunction() {
                    override fun call(s: LuaValue): LuaValue = LuaValue.valueOf(elements.text().trim())
                })
                listTable.set("attr", object : TwoArgFunction() {
                    override fun call(s: LuaValue, attrName: LuaValue): LuaValue =
                        LuaValue.valueOf(elements.attr(attrName.tojstring()))
                })
                return listTable
            }
        })

        table.set("selectFirst", object : TwoArgFunction() {
            override fun call(self: LuaValue, cssSelector: LuaValue): LuaValue {
                val query = cssSelector.tojstring()
                val el = element.selectFirst(query) ?: return LuaValue.NIL
                val elTable = LuaTable()
                wrapElementMethods(elTable, el)
                return elTable
            }
        })

        table.set("text", object : OneArgFunction() {
            override fun call(self: LuaValue): LuaValue = LuaValue.valueOf(element.text().trim())
        })

        table.set("ownText", object : OneArgFunction() {
            override fun call(self: LuaValue): LuaValue = LuaValue.valueOf(element.ownText().trim())
        })

        table.set("attr", object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val self = args.arg(1)
                val attrName = args.arg(2).tojstring()
                val attrVal = args.arg(3)
                return if (!attrVal.isnil()) {
                    element.attr(attrName, attrVal.tojstring())
                    self
                } else {
                    LuaValue.valueOf(element.attr(attrName))
                }
            }
        })

        table.set("prependElement", object : TwoArgFunction() {
            override fun call(self: LuaValue, tag: LuaValue): LuaValue {
                val created = element.prependElement(tag.tojstring())
                val elTable = LuaTable()
                wrapElementMethods(elTable, created)
                return elTable
            }
        })

        table.set("html", object : OneArgFunction() {
            override fun call(self: LuaValue): LuaValue = LuaValue.valueOf(element.html())
        })
    }

    private fun createFilterOptionsModule(): LuaValue {
        // Require("FilterOptions") returns a callable factory function: FilterOptions(options, default)
        return object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val options = args.arg(1)
                val defaultVal = args.arg(2)

                val fo = LuaTable()
                fo.set("valueOfOrFirst", object : TwoArgFunction() {
                    override fun call(self: LuaValue, v: LuaValue): LuaValue {
                        if (!v.isnil()) return v
                        return if (!defaultVal.isnil()) defaultVal else LuaValue.NIL
                    }
                })
                fo.set("labels", object : OneArgFunction() {
                    override fun call(self: LuaValue): LuaValue = LuaTable()
                })
                return fo
            }
        }
    }

    private fun createUrlModule(): LuaTable {
        val module = LuaTable()
        // Require("url").querystring(params, base)
        module.set("querystring", object : TwoArgFunction() {
            override fun call(params: LuaValue, base: LuaValue): LuaValue {
                val basePath = if (base.isnil()) "" else base.tojstring()
                val sb = StringBuilder()
                if (params.istable()) {
                    val tbl = params.checktable()
                    var k = LuaValue.NIL
                    while (true) {
                        val next = tbl.next(k)
                        k = next.arg1()
                        if (k.isnil()) break
                        val v = next.arg(2)
                        if (sb.isNotEmpty()) sb.append("&")
                        try {
                            sb.append(URLEncoder.encode(k.tojstring(), "UTF-8"))
                                .append("=")
                                .append(URLEncoder.encode(v.tojstring(), "UTF-8"))
                        } catch (_: Exception) {
                            sb.append(k.tojstring()).append("=").append(v.tojstring())
                        }
                    }
                }
                val query = sb.toString()
                return when {
                    query.isEmpty() -> LuaValue.valueOf(basePath)
                    basePath.contains("?") -> LuaValue.valueOf("$basePath&$query")
                    else -> LuaValue.valueOf("$basePath?$query")
                }
            }
        })
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
                val link = item.get("link").takeIf { !it.isnil() }?.tojstring()
                    ?: item.get("id").takeIf { !it.isnil() }?.tojstring() ?: ""
                val title = item.get("title").takeIf { !it.isnil() }?.tojstring() ?: ""
                val cover = item.get("imageURL").takeIf { !it.isnil() }?.tojstring()
                    ?: item.get("image").takeIf { !it.isnil() }?.tojstring()
                    ?: item.get("cover").takeIf { !it.isnil() }?.tojstring()
                val author = item.get("author").takeIf { !it.isnil() }?.tojstring() ?: ""

                novelMap["id"] = link
                novelMap["title"] = title
                novelMap["cover"] = cover
                novelMap["author"] = author
                list.add(novelMap)
            }
        }
        return list
    }

    private fun parseNovelDetails(result: LuaValue): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        if (!result.istable()) return map

        map["title"] = result.get("title").takeIf { !it.isnil() }?.tojstring() ?: ""

        val authorsVal = result.get("authors")
        if (authorsVal.istable()) {
            val authorsList = mutableListOf<String>()
            val aTable = authorsVal.checktable()
            for (i in 1..aTable.length()) {
                val a = aTable.get(i).takeIf { !it.isnil() }?.tojstring()
                if (!a.isNullOrBlank()) authorsList.add(a)
            }
            map["author"] = authorsList.joinToString(", ")
        } else {
            map["author"] = result.get("author").takeIf { !it.isnil() }?.tojstring() ?: ""
        }

        map["synopsis"] = result.get("description").takeIf { !it.isnil() }?.tojstring()
            ?: result.get("synopsis").takeIf { !it.isnil() }?.tojstring() ?: ""
        map["cover"] = result.get("imageURL").takeIf { !it.isnil() }?.tojstring()
            ?: itemOrNil(result, "cover") ?: itemOrNil(result, "image")

        val chaptersList = mutableListOf<Map<String, Any?>>()
        val chaptersVal = result.get("chapters")
        if (chaptersVal.istable()) {
            val chTable = chaptersVal.checktable()
            for (i in 1..chTable.length()) {
                val chItem = chTable.get(i)
                if (chItem.istable()) {
                    val link = chItem.get("link").takeIf { !it.isnil() }?.tojstring()
                        ?: chItem.get("url").takeIf { !it.isnil() }?.tojstring()
                        ?: chItem.get("id").takeIf { !it.isnil() }?.tojstring() ?: ""
                    val chTitle = chItem.get("title").takeIf { !it.isnil() }?.tojstring() ?: "Chapter $i"
                    val release = chItem.get("release").takeIf { !it.isnil() }?.tojstring()

                    chaptersList.add(mapOf(
                        "id" to link,
                        "title" to chTitle,
                        "url" to link,
                        "release" to release
                    ))
                }
            }
        }
        map["chapters"] = chaptersList
        return map
    }

    private fun itemOrNil(table: LuaValue, key: String): String? {
        val v = table.get(key)
        return if (!v.isnil()) v.tojstring() else null
    }
}
