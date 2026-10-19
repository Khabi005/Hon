package com.hon.reader.hon.shosetsu

import org.jsoup.nodes.Node
import org.jsoup.nodes.Attributes
import org.jsoup.nodes.Attribute
import org.jsoup.nodes.Document
import org.jsoup.select.Elements
import org.luaj.vm2.*
import org.luaj.vm2.lib.VarArgFunction
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.util.concurrent.ConcurrentHashMap

/**
 * Explicit capabilities for the Jsoup and HTTP value objects in the Shosetsu
 * API. Never uses LuaJ's Java bridge: scripts cannot look up classes, reflect on
 * returned objects, or reach Object.getClass()/ClassLoader through host values.
 */
internal object SafeShosetsuObjects {
    private val domMethods = setOf(
        "traverse", "select", "selectFirst", "selectXpath", "is", "closest", "parents", "children", "child", "childrenSize",
        "childNode", "childNodes", "childNodesCopy", "childNodeSize", "parent", "ownerDocument", "root",
        "nextElementSibling", "previousElementSibling", "nextSibling", "previousSibling", "siblingElements", "siblingIndex",
        "firstElementChild", "lastElementChild", "first", "last", "eq", "not", "hasClass", "className", "classNames",
        "textNodes", "hasText", "isBlank", "lastChild", "firstChild", "elementSiblingIndex", "lastElementSibling",
        "nextElementSiblings", "previousElementSiblings",
        "id", "tagName", "normalName", "nodeName", "text", "wholeText", "ownText", "getWholeText", "data",
        "html", "outerHtml", "innerHtml", "attr", "hasAttr", "attributes", "removeAttr", "clearAttributes",
        "absUrl", "baseUri", "setBaseUri", "remove", "empty", "unwrap", "wrap", "before", "after", "clone",
        "append", "prepend", "appendChild", "prependChild", "appendElement", "prependElement", "appendText", "prependText",
        "addClass", "removeClass", "toggleClass", "getElementsByTag", "getElementsByClass", "getElementById", "getAllElements",
        "head", "body", "title", "location", "charset", "outputSettings", "prettyPrint", "outline", "indentAmount",
        "maxPaddingWidth", "escapeMode", "syntax", "isBlock", "isEmpty", "size", "get", "set", "add", "addAll", "contains",
        "asList", "getKey", "getValue", "setValue", "put", "hasKey", "hasKeyIgnoreCase", "removeIgnoreCase",
    )
    private val builderMethods = setOf(
        "add", "set", "removeAll", "addUnsafeNonAscii", "addEncoded", "build", "newBuilder", "get",
        "url", "scheme", "host", "port", "encodedPath", "addPathSegment", "addEncodedPathSegment", "addQueryParameter",
        "addEncodedQueryParameter", "setQueryParameter", "removeAllQueryParameters", "query", "encodedQuery", "fragment",
        "header", "addHeader", "removeHeader", "headers", "cacheControl", "method", "post", "put", "patch", "delete",
        "isHttps", "name", "value", "names", "values", "size", "string", "contentType", "contentLength",
    )
    private val methods = ConcurrentHashMap<Class<*>, Map<String, List<Method>>>()

    internal class Value(val raw: Any) : LuaUserdata(raw) {
        override fun get(key: LuaValue): LuaValue {
            if (raw is List<*> && key.type() == TNUMBER && key.isint()) return wrap(raw.getOrNull(key.toint()))
            if (!key.isstring()) {
                return NIL
            }
            val name = key.tojstring()
            if (name in setOf("append", "prepend", "before", "after") && raw is Node) {
                return function { args ->
                    val input = unwrap(args.arg1())
                    val nodes = when (input) {
                        is Node -> listOf(input)
                        is Collection<*> -> input.filterIsInstance<Node>()
                        else -> null
                    }
                    if (nodes != null) {
                        when (name) {
                            "append" -> (raw as? org.jsoup.nodes.Element)?.appendChildren(nodes) ?: throw LuaError("append requires an element")
                            "prepend" -> (raw as? org.jsoup.nodes.Element)?.prependChildren(nodes) ?: throw LuaError("prepend requires an element")
                            "before" -> nodes.forEach { raw.before(it) }
                            "after" -> nodes.asReversed().forEach { raw.after(it) }
                        }
                    } else {
                        val text = args.arg1().checkjstring()
                        when (name) {
                            "append" -> (raw as? org.jsoup.nodes.Element)?.append(text) ?: throw LuaError("append requires an element")
                            "prepend" -> (raw as? org.jsoup.nodes.Element)?.prepend(text) ?: throw LuaError("prepend requires an element")
                            "before" -> raw.before(text)
                            "after" -> raw.after(text)
                        }
                    }
                    wrap(raw)
                }
            }
            // Newer source snapshots use selectLast, which was added after the
            // bundled Jsoup version. Keep the same DOM result without exposing
            // an additional host capability.
            if (name == "selectLast" && (raw is org.jsoup.nodes.Element || raw is Elements)) {
                return function { args ->
                    val query = args.arg1().checkjstring()
                    wrap(if (raw is org.jsoup.nodes.Element) raw.select(query).lastOrNull() else (raw as Elements).select(query).lastOrNull())
                }
            }
            if (raw is List<*> && raw !is Elements) {
                return when (name) {
                    "size" -> function { LuaValue.valueOf(raw.size) }
                    "isEmpty" -> function { LuaValue.valueOf(raw.isEmpty()) }
                    "get" -> function { args -> wrap(raw.getOrNull(args.arg(1).checkint())) }
                    else -> NIL
                }
            }
            val allowed = when {
                raw is Node || raw is Elements || raw is Attributes || raw is Attribute || raw is Document.OutputSettings -> domMethods
                raw.javaClass.name.startsWith("okhttp3.") -> builderMethods
                else -> emptySet()
            }
            if (name !in allowed) return NIL
            val overloads = methods.getOrPut(raw.javaClass) { raw.javaClass.methods.filter { !it.isSynthetic }.groupBy { it.name } }[name] ?: return NIL
            return function { args ->
                val candidates = overloads.filter { it.parameterTypes.size == args.narg() }
                    .sortedBy { method -> method.parameterTypes.count { it == Any::class.java } }
                for (method in candidates) {
                    val converted = try { method.parameterTypes.mapIndexed { index, type -> convert(args.arg(index + 1), type) }.toTypedArray() }
                        catch (_: IllegalArgumentException) { continue }
                    try { return@function wrap(method.invoke(raw, *converted)) }
                    catch (error: InvocationTargetException) { throw LuaError(error.targetException.message ?: "Host operation failed") }
                    catch (error: ReflectiveOperationException) { throw LuaError("Unsupported host operation: $name") }
                }
                throw LuaError("No compatible $name overload for ${args.narg()} arguments")
            }
        }

        private fun function(block: (Varargs) -> LuaValue): LuaValue = object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs = block(if (args.arg1() === this@Value) args.subargs(2) else args)
        }
        override fun tojstring(): String = raw.toString()
    }

    fun unwrap(value: LuaValue): Any? = when {
        value is Value -> value.raw
        value.isnil() -> null
        value.isboolean() -> value.toboolean()
        value.isint() -> value.toint()
        value.isnumber() -> value.todouble()
        value.isstring() -> value.tojstring()
        value.istable() -> (1..value.length()).map { unwrap(value.get(it)) }
        else -> null
    }

    fun wrap(value: Any?): LuaValue = when (value) {
        null -> LuaValue.NIL
        is LuaValue -> value
        is String -> LuaValue.valueOf(value)
        is CharSequence -> LuaValue.valueOf(value.toString())
        is Boolean -> LuaValue.valueOf(value)
        is Int -> LuaValue.valueOf(value)
        is Long -> LuaValue.valueOf(value.toDouble())
        is Number -> LuaValue.valueOf(value.toDouble())
        is Node, is Elements, is Attributes, is Attribute, is Document.OutputSettings, is List<*>, is org.jsoup.select.NodeVisitor -> Value(value)
        is Enum<*> -> LuaValue.valueOf(value.name)
        else -> if (value.javaClass.name.startsWith("okhttp3.")) Value(value) else throw LuaError("Unsupported host value")
    }

    private fun convert(value: LuaValue, type: Class<*>): Any? {
        if (value.isnil() && !type.isPrimitive) return null
        val raw = unwrap(value)
        return when {
            raw != null && type.isInstance(raw) -> raw
            type == String::class.java && (value.isstring() || value.isnumber()) -> value.tojstring()
            (type == Int::class.javaPrimitiveType || type == Int::class.javaObjectType) && value.isnumber() -> value.toint()
            (type == Long::class.javaPrimitiveType || type == Long::class.javaObjectType) && value.isnumber() -> value.tolong()
            (type == Double::class.javaPrimitiveType || type == Double::class.javaObjectType) && value.isnumber() -> value.todouble()
            (type == Boolean::class.javaPrimitiveType || type == Boolean::class.javaObjectType) && value.isboolean() -> value.toboolean()
            type == Any::class.java -> raw
            else -> throw IllegalArgumentException("Unsupported argument")
        }
    }
}
