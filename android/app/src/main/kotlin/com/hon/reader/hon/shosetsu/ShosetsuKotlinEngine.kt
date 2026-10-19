package com.hon.reader.hon.shosetsu

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import org.luaj.vm2.*
import org.luaj.vm2.compiler.LuaC
import org.luaj.vm2.lib.BaseLib
import org.luaj.vm2.lib.Bit32Lib
import org.luaj.vm2.lib.DebugLib
import org.luaj.vm2.lib.PackageLib
import org.luaj.vm2.lib.StringLib
import org.luaj.vm2.lib.TableLib
import org.luaj.vm2.lib.jse.JseMathLib
import java.util.concurrent.TimeUnit

class ShosetsuKotlinEngine(
    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(15, TimeUnit.SECONDS)
        .build()
) {

    private class BudgetDebugLib(private val budget: SourceOperationBudget) : DebugLib() {
        private var instructions = 0
        override fun onInstruction(pc: Int, v: Varargs?, top: Int) {
            instructions++
            if (instructions > budget.instructionLimit || Thread.currentThread().isInterrupted) {
                throw LuaError("Extension exceeded its execution budget")
            }
            if (instructions % 4096 == 0) budget.remainingMillis()
        }
    }

    suspend fun search(
        luaScript: String,
        query: String,
        page: Int,
        listingIndex: Int? = null,
        userSettings: Map<String, Any?> = emptyMap(),
        userFilters: Map<String, Any?> = emptyMap(),
        allowedHosts: Set<String> = emptySet(),
        initialBaseUrl: String? = null
    ): List<Map<String, Any?>> = runScript {
        val (globals, extensionTable) = loadExtension(luaScript, userSettings, allowedHosts = allowedHosts, initialBaseUrl = initialBaseUrl)
        val sourcePage = page.coerceAtLeast(0) + extensionTable.get("startIndex").optint(1)
        val data = filterValues(extensionTable.get("searchFilters"), userFilters).apply {
            set(globals.get("QUERY"), LuaValue.valueOf(query))
            set(globals.get("PAGE"), LuaValue.valueOf(sourcePage))
            set("query", LuaValue.valueOf(query)); set("page", LuaValue.valueOf(sourcePage))
        }
        val listings = extensionTable.get("listings")
        val entry = if (listings.istable()) listings.get((listingIndex ?: 0).coerceAtLeast(0) + 1) else LuaValue.NIL
        val listing = if (entry.istable()) entry.get("fn") else LuaValue.NIL
        if (query.isBlank() && listing.isfunction()) return@runScript parseNovelList(listing.call(data))
        val searchFn = extensionTable.get("search")
        if (!searchFn.isfunction() || extensionTable.get("hasSearch") == LuaValue.FALSE) {
            if (query.isNotBlank()) throw IllegalArgumentException("This source does not support text search")
            if (!listing.isfunction()) throw IllegalArgumentException("Source has no searchable catalog or listing")
            return@runScript parseNovelList(listing.call(data))
        }

        val result = searchFn.call(data)
        return@runScript parseNovelList(result)
    }

    suspend fun describeExtension(
        luaScript: String,
        userSettings: Map<String, Any?> = emptyMap(),
        allowedHosts: Set<String> = emptySet(),
        initialBaseUrl: String? = null
    ): Map<String, Any?> = runScript {
        val (_, extension) = loadExtension(luaScript, userSettings, allowedHosts = allowedHosts, initialBaseUrl = initialBaseUrl)
        val listings = extension.get("listings")
        mapOf(
            "baseUrl" to extension.get("baseURL").optjstring(extension.get("baseUrl").optjstring("")),
            "settings" to describeFilters(extension.get("settings")),
            "filters" to describeFilters(extension.get("searchFilters")),
            "hasSearch" to (extension.get("search").isfunction() && extension.get("hasSearch") != LuaValue.FALSE),
            "searchIncrementing" to extension.get("isSearchIncrementing").optboolean(true),
            "listings" to (1..(if (listings.istable()) listings.length().coerceAtMost(128) else 0)).map { index ->
                val listing = listings.get(index)
                mapOf("index" to index - 1, "name" to listing.get("name").optjstring("Browse"),
                    "incrementing" to listing.get("increments").optboolean(false))
            },
        )
    }

    suspend fun parseNovel(
        luaScript: String,
        novelUrl: String,
        loadChapters: Boolean,
        userSettings: Map<String, Any?> = emptyMap(),
        allowedHosts: Set<String> = emptySet(),
        initialBaseUrl: String? = null
    ): Map<String, Any?> = runScript {
        val (_, extensionTable) = loadExtension(luaScript, userSettings, SourceOperationBudget(chapters = loadChapters), allowedHosts = allowedHosts, initialBaseUrl = initialBaseUrl)
        val parseFn = extensionTable.get("parseNovel")
        if (parseFn.isnil() || !parseFn.isfunction()) {
            throw IllegalArgumentException("Script does not export 'parseNovel' function in returned extension table")
        }

        val result = parseFn.call(LuaValue.valueOf(novelUrl), LuaValue.valueOf(loadChapters))
        return@runScript parseNovelDetails(result)
    }

    suspend fun getPassage(
        luaScript: String,
        chapterUrl: String,
        userSettings: Map<String, Any?> = emptyMap(),
        allowedHosts: Set<String> = emptySet(),
        initialBaseUrl: String? = null
    ): String = runScript {
        val (_, extensionTable) = loadExtension(luaScript, userSettings, allowedHosts = allowedHosts, initialBaseUrl = initialBaseUrl)
        val passageFn = extensionTable.get("getPassage")
        if (passageFn.isnil() || !passageFn.isfunction()) {
            throw IllegalArgumentException("Script does not export 'getPassage' function in returned extension table")
        }

        val result = passageFn.call(LuaValue.valueOf(chapterUrl))
        if (!result.isstring()) throw IllegalArgumentException("Extension did not return chapter text")
        if (extensionTable.get("chapterType").optint(1) == 0) {
            return@runScript "<p>" + org.jsoup.nodes.Entities.escape(result.tojstring()).replace("\n", "<br>") + "</p>"
        }
        return@runScript result.tojstring()
    }

    private fun extractDeclaredBaseUrl(luaScript: String): String? {
        val match = Regex("""(?:local\s+)?base(?:URL|Url)\s*=\s*["']([^"']+)["']""").find(luaScript)
            ?: Regex("""["']?base(?:URL|Url)["']?\s*[:=]\s*["']([^"']+)["']""").find(luaScript)
        return match?.groupValues?.get(1)?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun loadExtension(
        luaScript: String,
        userSettings: Map<String, Any?> = emptyMap(),
        budget: SourceOperationBudget = SourceOperationBudget(),
        allowedHosts: Set<String> = emptySet(),
        initialBaseUrl: String? = null
    ): Pair<Globals, LuaTable> {
        val resolvedBaseUrl = initialBaseUrl?.trim()?.takeIf { it.isNotEmpty() } ?: extractDeclaredBaseUrl(luaScript)
        val policy = SourceNetworkPolicy(baseHost = resolvedBaseUrl, extraAllowedHosts = allowedHosts.toMutableSet())
        val globals = createSandboxedGlobals(budget, policy)
        val chunk = LuaPrototypeCache.load(globals, luaScript, "extension")
        val extensionTable = chunk.call()
        if (!extensionTable.istable()) {
            throw IllegalArgumentException("Upstream Shosetsu extension script must return an extension table")
        }
        val rawBaseUrl = extensionTable.get("baseURL").optjstring(extensionTable.get("baseUrl").optjstring(""))
        if (rawBaseUrl.isNotBlank()) {
            policy.baseHost = rawBaseUrl
        }
        val settings = filterValues(extensionTable.get("settings"), userSettings)
        extensionTable.get("setSettings").takeIf { it.isfunction() }?.call(settings)
        extensionTable.get("updateSetting").takeIf { it.isfunction() }?.let { update ->
            for (id in settings.keys()) update.call(id, settings.get(id))
        }
        return Pair(globals, extensionTable.checktable())
    }

    private fun describeFilters(filters: LuaValue): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        fun walk(items: LuaValue, group: String, depth: Int) {
            if (!items.istable() || depth > 16 || result.size >= 2048) return
            for (i in 1..items.length().coerceAtMost(512)) {
                if (result.size >= 2048) return
                val item = items.get(i)
                if (!item.istable()) continue
                val name = item.get("name").optjstring("").take(500)
                if (item.get("filters").istable()) { walk(item.get("filters"), if (group.isBlank()) name else "$group / $name", depth + 1); continue }
                val id = item.get("id")
                if (!id.isint() || id.toint() < 0) continue
                val state = item.get("state")
                val options = item.get("options")
                result.add(mapOf("id" to id.toint(), "label" to name, "group" to group,
                    "kind" to item.get("kind").optjstring("TextFilter"),
                    "value" to when { state.isboolean() -> state.toboolean(); state.isnumber() -> state.todouble(); else -> state.optjstring("") },
                    "options" to (1..(if(options.istable()) options.length().coerceAtMost(512) else 0)).map { options.get(it).tojstring().take(500) }))
            }
        }
        walk(filters, "", 0)
        return result
    }

    private fun filterValues(filters: LuaValue, overrides: Map<String, Any?>): LuaTable {
        val result = filterDefaults(filters)
        for (control in describeFilters(filters)) {
            val id = control["id"] as Int
            if (!overrides.containsKey(id.toString())) continue
            val value = overrides[id.toString()]
            val kind = control["kind"] as String
            val options = control["options"] as List<*>
            val lua = when (kind) {
                "CheckboxFilter", "SwitchFilter" -> if (value is Boolean) LuaValue.valueOf(value) else throw IllegalArgumentException("Invalid switch value")
                "TriStateFilter" -> if (value is Number && value.toDouble() == value.toInt().toDouble() && value.toInt() in 0..2) LuaValue.valueOf(value.toInt()) else throw IllegalArgumentException("Invalid tri-state value")
                "DropdownFilter", "RadioGroupFilter" -> if (value is Number && value.toDouble() == value.toInt().toDouble() && value.toInt() in 0 until options.size) LuaValue.valueOf(value.toInt()) else throw IllegalArgumentException("Invalid option index")
                "TextFilter", "PasswordFilter" -> if (value is String && value.length <= 4096) LuaValue.valueOf(value) else throw IllegalArgumentException("Invalid text setting")
                else -> continue
            }
            result.set(id, lua)
        }
        return result
    }

    private fun filterDefaults(filters: LuaValue): LuaTable {
        val result = LuaTable()
        var visited = 0
        fun collect(items: LuaValue, depth: Int) {
            if (!items.istable() || depth > 16) return
            for (i in 1..items.length().coerceAtMost(512)) {
                if (++visited > 2048) return
                val filter = items.get(i)
                if (!filter.istable()) continue
                val nested = filter.get("filters")
                if (nested.istable()) collect(nested, depth + 1)
                else {
                    val id = filter.get("id")
                    val state = filter.get("state")
                    if (id.isint() && id.toint() >= 0 && !state.isnil()) result.set(id, state)
                }
            }
        }
        collect(filters, 0)
        return result
    }

    suspend fun validateExtension(
        luaScript: String,
        allowedHosts: Set<String> = emptySet(),
        initialBaseUrl: String? = null
    ): Boolean = runScript {
        val (_, extension) = loadExtension(luaScript, allowedHosts = allowedHosts, initialBaseUrl = initialBaseUrl)
        for (method in listOf("parseNovel", "getPassage")) {
            if (!extension.get(method).isfunction()) {
                throw IllegalArgumentException("Extension does not implement $method")
            }
        }
        if (!extension.get("search").isfunction() &&
            (!extension.get("listings").istable() || !extension.get("listings").get(1).get("fn").isfunction())) {
            throw IllegalArgumentException("Extension has no search function or listing")
        }
        true
    }

    private suspend fun <T> runScript(block: () -> T): T = withContext(Dispatchers.IO) {
        try { block() } finally { SandboxStringMethods.leave() }
    }

    fun selfCheck() {
        val globals = createSandboxedGlobals(SourceOperationBudget())
        val chunk = globals.load("return 42", "selfCheck")
        val result = chunk.call()
        if (result.toint() != 42) {
            throw IllegalStateException("Source engine self-check failed")
        }
    }

    fun createSandboxedGlobals(): Globals = createSandboxedGlobals(SourceOperationBudget(), SourceNetworkPolicy())

    internal fun createSandboxedGlobals(budget: SourceOperationBudget): Globals = createSandboxedGlobals(budget, SourceNetworkPolicy())

    internal fun createSandboxedGlobals(budget: SourceOperationBudget, policy: SourceNetworkPolicy): Globals {
        val globals = Globals()
        globals.load(BaseLib())
        globals.load(PackageLib())
        globals.load(Bit32Lib())
        globals.load(TableLib())
        globals.load(StringLib())
        globals.load(JseMathLib())
        LoadState.install(globals)
        LuaC.install(globals)
        globals.load(BudgetDebugLib(budget))
        for (name in listOf("os", "io", "luajava", "debug", "package", "require", "dofile", "loadfile", "load", "loadstring", "collectgarbage")) {
            globals.set(name, LuaValue.NIL)
        }
        ShosetsuLuaHost(globals, httpClient, budget, policy).install()
        installAllocationLimits(globals)
        SandboxStringMethods.enter(globals)
        return globals
    }

    private fun installAllocationLimits(globals: Globals) {
        val strings = globals.get("string")
        val repeat = strings.get("rep")
        strings.set("rep", object : org.luaj.vm2.lib.VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val size = args.arg1().checkstring().length().toLong()
                val count = args.arg(2).checklong().coerceAtLeast(0)
                val separator = args.arg(3).optjstring("").length.toLong()
                if (count > 1_000_000 || (size + separator) * count > 8 * 1024 * 1024) throw LuaError("Extension string exceeds its allocation budget")
                return repeat.invoke(args)
            }
        })
        val format = strings.get("format")
        strings.set("format", object : org.luaj.vm2.lib.VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val pattern = args.arg1().checkjstring()
                if (Regex("%[-+ #0]*(\\d+)").findAll(pattern).any { (it.groupValues[1].toLongOrNull() ?: Long.MAX_VALUE) > 1_000_000 }) {
                    throw LuaError("Extension format exceeds its allocation budget")
                }
                return format.invoke(args)
            }
        })
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
                        "release" to release,
                        "order" to chItem.get("order").optdouble(i.toDouble())
                    ))
                }
            }
        }
        map["chapters"] = chaptersList.sortedBy { (it["order"] as? Number)?.toDouble() ?: 0.0 }
        return map
    }

    private fun itemOrNil(table: LuaValue, key: String): String? {
        val v = table.get(key)
        return if (!v.isnil()) v.tojstring() else null
    }
}
