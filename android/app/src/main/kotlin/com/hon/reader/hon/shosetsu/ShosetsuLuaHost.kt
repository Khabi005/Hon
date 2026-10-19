package com.hon.reader.hon.shosetsu

import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.select.NodeVisitor
import org.luaj.vm2.*
import org.luaj.vm2.lib.VarArgFunction
import java.io.ByteArrayOutputStream
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/** Shosetsu 1.x host contract, with explicit bounded network capabilities. */
internal class ShosetsuLuaHost(
    private val globals: Globals,
    client: OkHttpClient,
    private val budget: SourceOperationBudget,
    private val policy: SourceNetworkPolicy = SourceNetworkPolicy()
) {
    private val http = client
    private var requests = 0
    private var responseBytes = 0

    private fun fn(name: String, block: (Varargs) -> LuaValue) {
        globals.set(name, object : VarArgFunction() { override fun invoke(args: Varargs): Varargs = block(args) })
    }
    private fun wrap(value: Any?): LuaValue = SafeShosetsuObjects.wrap(value)
    private fun raw(value: LuaValue): Any? = SafeShosetsuObjects.unwrap(value)
    private fun constructor(): LuaTable = LuaTable().also { table ->
        for (field in listOf("title", "alternativeTitles", "link", "imageURL", "language", "description", "status", "tags", "genres", "authors", "artists", "chapters", "chapterCount", "wordCount", "commentCount", "viewCount", "favoriteCount", "order", "release")) {
            table.set("set" + field.replaceFirstChar { it.uppercase() }, object : VarArgFunction() {
                override fun invoke(args: Varargs): Varargs { table.set(field, args.arg(2)); return table }
            })
            table.set("get" + field.replaceFirstChar { it.uppercase() }, object : VarArgFunction() {
                override fun invoke(args: Varargs): Varargs = table.get(field)
            })
        }
    }

    fun install() {
        globals.set("QUERY", 0)
        globals.set("PAGE", 1)
        globals.set("KEY_CHAPTER_URL", 0)
        globals.set("KEY_NOVEL_URL", 1)
        for (name in listOf("_Novel", "_NovelInfo", "_NovelChapter")) fn(name) { constructor() }
        fn("_NovelStatus") { it.arg1() }
        fn("_ChapterType") { it.arg1() }
        fn("AsList") { it.arg1() }
        fn("List") { wrap(mutableListOf<Any?>()) }
        fn("Reverse") { args ->
            val list = args.arg1()
            if (list.istable()) for (i in 1..list.length() / 2) {
                val last = list.length() + 1 - i
                val old = list.get(i); list.set(i, list.get(last)); list.set(last, old)
            }
            LuaValue.NIL
        }
        fn("Listing") { args -> LuaTable().apply { set("name", args.arg(1)); set("increments", args.arg(2)); set("fn", args.arg(3)) } }
        for (name in listOf("TextFilter", "PasswordFilter", "SwitchFilter", "CheckboxFilter", "TriStateFilter", "DropdownFilter", "RadioGroupFilter", "HeaderFilter", "SeparatorFilter", "FilterList", "FilterGroup")) {
            fn(name) { args -> LuaTable().apply {
                set("kind", name)
                if (name == "FilterGroup" || name == "FilterList") {
                    set("id", -1); set("name", args.arg(1)); set("filters", args.arg(2))
                } else {
                    set("id", args.arg(1)); set("name", args.arg(2)); set("options", args.arg(3))
                    set("state", when (name) {
                        "TextFilter", "PasswordFilter" -> LuaValue.valueOf("")
                        "SwitchFilter", "CheckboxFilter" -> LuaValue.FALSE
                        else -> LuaValue.ZERO
                    })
                }
            } }
        }
        fn("Document") { args -> wrap(Jsoup.parse(args.arg1().checkjstring())) }
        fn("HeadersBuilder") { wrap(Headers.Builder()) }
        fn("FormBodyBuilder") { wrap(FormBody.Builder()) }
        fn("RequestBuilder") { wrap(Request.Builder()) }
        fn("HttpUrlBuilder") { wrap(HttpUrl.Builder()) }
        fn("HttpUrl") { args -> wrap(args.arg1().checkjstring().toHttpUrlOrNull()) }
        fn("DefaultCacheControl") { wrap(CacheControl.Builder()) }
        fn("DEFAULT_CACHE_CONTROL") { wrap(CacheControl.Builder().build()) }
        fn("DEFAULT_HEADERS") { wrap(defaultHeaders()) }
        fn("DEFAULT_BODY") { wrap(FormBody.Builder().build()) }
        fn("MediaType") { args -> wrap(args.arg1().checkjstring().toMediaTypeOrNull()) }
        fn("RequestBody") { args -> wrap(args.arg1().checkjstring().toRequestBody(raw(args.arg(2)) as? MediaType)) }
        fn("_GET") { args -> wrap(request(args, false)) }
        fn("_POST") { args -> wrap(request(args, true)) }
        fn("Request") { args -> response(execute(raw(args.arg1()) as? Request ?: throw LuaError("Request expects an HTTP request"))) }
        fn("RequestDocument") { args ->
            val req = raw(args.arg1()) as? Request ?: throw LuaError("RequestDocument expects an HTTP request")
            val result = execute(req)
            if (result.code !in 200..299) throw SourceHttpException(result.code, result.retryAfterMillis)
            wrap(Jsoup.parse(result.body, req.url.toString()))
        }
        fn("GETDocument") { args ->
            val req = Request.Builder().url(args.arg1().checkjstring()).headers(defaultHeaders()).build()
            val result = execute(req)
            if (result.code !in 200..299) throw SourceHttpException(result.code, result.retryAfterMillis)
            wrap(Jsoup.parse(result.body, req.url.toString()))
        }
        fn("_PageOfElem") { args ->
            val element = (raw(args.arg1()) as? Element)?.clone() ?: throw LuaError("pageOfElem expects a document or element")
            val removeStyles = args.arg(2).toboolean()
            val keepScripts = args.arg(4).toboolean()
            if (!keepScripts) element.select("script").remove()
            if (removeStyles) element.select("style").remove()
            for (node in element.getAllElements()) {
                for (attr in node.attributes().asList()) {
                    if (!keepScripts && attr.key.startsWith("on", true) || removeStyles && attr.key == "style") node.removeAttr(attr.key)
                }
                if (node.tagName() == "img") {
                    val src = node.absUrl("src").ifBlank { node.absUrl("data-src") }
                    if (src.isNotBlank()) node.attr("src", src)
                }
                if (node.tagName() == "a") node.absUrl("href").takeIf { it.isNotBlank() }?.let { node.attr("href", it) }
            }
            val style = args.arg(3).optjstring("")
            LuaValue.valueOf("<!DOCTYPE html><html><head>" + (if (style.isEmpty()) "" else "<style>$style</style>") +
                "</head><body>${if (element is org.jsoup.nodes.Document) element.body().html() else element.outerHtml()}</body></html>")
        }
        fn("_NodeVisitor") { args ->
            val head = args.arg(1); val tail = args.arg(2); val onlyElements = args.arg(3).toboolean()
            wrap(object : NodeVisitor {
                override fun head(node: Node, depth: Int) { if (!onlyElements || node is Element) head.call(wrap(node), LuaValue.valueOf(depth)) }
                override fun tail(node: Node, depth: Int) { if (!onlyElements || node is Element) tail.call(wrap(node), LuaValue.valueOf(depth)) }
            })
        }
        fn("Log") { LuaValue.NIL }
        fn("delay") { args ->
            val delay = args.arg1().checklong()
            if (delay !in 0..1000 || delay > budget.remainingMillis()) throw LuaError("Extension delay exceeds execution budget")
            Thread.sleep(delay); LuaValue.NIL
        }
        fn("Require") { args -> when (val name = args.arg1().checkjstring()) {
            "url" -> builtInUrl()
            "FilterOptions" -> filterOptions()
            else -> throw LuaError("Unsupported extension module: $name")
        } }
        // Use the upstream implementations for collection semantics and models.
        for (name in listOf("wrap", "map", "mapNotNil", "filter", "first", "flatten", "map2flat", "pipeline", "Novel", "NovelInfo", "NovelChapter", "NovelStatus", "ChapterType", "GET", "POST", "pageOfElem", "NodeVisitor")) {
            val stream = javaClass.classLoader?.getResourceAsStream("shosetsu/$name.lua") ?: error("Missing Shosetsu standard helper: $name")
            val source = stream.bufferedReader().use { it.readText() }
            globals.set(name, LuaPrototypeCache.load(globals, source, "shosetsu/$name").call())
        }
    }

    private fun defaultHeaders() = Headers.Builder().add("User-Agent", "Mozilla/5.0 (Linux; Android; Hon/1.0)").add("Accept", "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8").build()

    private fun request(args: Varargs, post: Boolean): Request {
        val url = args.arg(1).checkjstring()
        val builder = Request.Builder().url(url).headers(raw(args.arg(2)) as? Headers ?: defaultHeaders())
        if (post) builder.post(raw(args.arg(3)) as? RequestBody ?: FormBody.Builder().build())
        val cache = raw(args.arg(if (post) 4 else 3)) as? CacheControl
        if (cache != null) builder.cacheControl(cache)
        return builder.build()
    }

    private data class ResponseData(val code: Int, val body: String, val headers: Headers, val message: String, val retryAfterMillis: Long)
    private fun execute(request: Request): ResponseData {
        if (++requests > budget.requestLimit || Thread.currentThread().isInterrupted) throw LuaError("Extension exceeded its network budget")
        val remaining = budget.remainingMillis().coerceAtMost(30_000)
        try {
            policy.checkUrl(request.url)
            val clientWithPolicy = http.newBuilder()
                .callTimeout(remaining, TimeUnit.MILLISECONDS)
                .addNetworkInterceptor { chain ->
                    val req = chain.request()
                    policy.checkUrl(req.url)
                    chain.proceed(req)
                }
                .build()

            return clientWithPolicy.newCall(request).execute().use { response ->
                val output = ByteArrayOutputStream()
                response.body?.byteStream()?.use { input ->
                    val bytes = ByteArray(8192)
                    while (true) {
                        budget.remainingMillis()
                        val count = input.read(bytes)
                        if (count < 0) break
                        responseBytes += count
                        if (output.size() + count > 5 * 1024 * 1024 || responseBytes > budget.totalBytes) throw LuaError("Extension network response exceeds its size budget")
                        output.write(bytes, 0, count)
                    }
                }
                ResponseData(response.code, output.toString(response.body?.contentType()?.charset(Charsets.UTF_8)?.name() ?: "UTF-8"), response.headers, response.message,
                    response.header("Retry-After")?.let { raw ->
                        raw.toLongOrNull()?.coerceIn(0, 86400)?.times(1000)
                            ?: runCatching { java.time.ZonedDateTime.parse(raw, java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli() - System.currentTimeMillis() }.getOrNull()?.coerceIn(0, 86_400_000)
                    } ?: 0)
            }
        } catch (e: SourceNetworkPolicyException) {
            throw LuaError("Network request to '${e.host}' blocked by source network policy.")
        }
    }

    private fun response(value: ResponseData): LuaValue = LuaTable().apply {
        set("code", method { LuaValue.valueOf(value.code) })
        set("message", method { LuaValue.valueOf(value.message) })
        set("isSuccessful", method { LuaValue.valueOf(value.code in 200..299) })
        set("headers", method { wrap(value.headers) })
        set("header", object : VarArgFunction() { override fun invoke(args: Varargs): Varargs = wrap(value.headers[args.arg(if (args.arg1().istable()) 2 else 1).checkjstring()]) })
        set("body", method { LuaTable().apply {
            set("string", method { LuaValue.valueOf(value.body) })
            set("close", method { LuaValue.NIL })
        } })
        set("close", method { LuaValue.NIL })
    }
    private fun method(block: () -> LuaValue): LuaValue = object : VarArgFunction() { override fun invoke(args: Varargs): Varargs = block() }

    private fun filterOptions(): LuaValue = object : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val options = args.arg1(); val default = args.arg(2)
            return LuaTable().apply {
                set("valueOfOrFirst", object : VarArgFunction() {
                    override fun invoke(values: Varargs): Varargs {
                        val input = values.arg(2)
                        if (!input.isnil()) return input
                        if (!default.isnil()) return default
                        val first = options.get(1)
                        return if (first.istable()) first.checktable().keys().firstOrNull() ?: LuaValue.NIL else first
                    }
                })
                set("labels", method { LuaTable().apply {
                    for (i in 1..options.length()) {
                        val entry = options.get(i)
                        set(i, if (entry.istable()) entry.checktable().keys().firstOrNull()?.let { entry.get(it) } ?: LuaValue.NIL else entry)
                    }
                } })
            }
        }
    }
    private fun builtInUrl(): LuaValue = LuaTable().apply {
        set("encode", object : VarArgFunction() { override fun invoke(args: Varargs): Varargs = LuaValue.valueOf(URLEncoder.encode(args.arg1().optjstring(""), "UTF-8")) })
        set("querystring", object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val values = args.arg1().checktable(); val base = args.arg(2).optjstring("")
                val query = values.keys().joinToString("&") { key -> URLEncoder.encode(key.tojstring(), "UTF-8") + "=" + URLEncoder.encode(values.get(key).tojstring(), "UTF-8") }
                return LuaValue.valueOf(base + if (query.isEmpty()) "" else (if (base.contains('?')) "&" else "?") + query)
            }
        })
    }
}
