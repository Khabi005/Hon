package com.hon.reader.hon.shosetsu

import org.luaj.vm2.Globals
import org.luaj.vm2.LuaClosure
import org.luaj.vm2.Prototype
import org.luaj.vm2.compiler.LuaC
import java.io.ByteArrayInputStream
import java.security.MessageDigest

/** Cache immutable bytecode only. Every invocation still has fresh sandbox
 * globals, closures and budgets, so source state cannot leak between requests. */
internal object LuaPrototypeCache {
    private data class Entry(val prototype: Prototype, val sourceBytes: Int)
    private val entries = LinkedHashMap<String, Entry>(32, .75f, true)
    private var bytes = 0

    fun load(globals: Globals, source: String, name: String): LuaClosure {
        val data = source.toByteArray(Charsets.UTF_8)
        val hash = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { it.toUByte().toString(16).padStart(2, '0') }
        val key = "$name:$hash"
        val cached = synchronized(entries) { entries[key]?.prototype }
        val prototype = cached ?: LuaC.instance.compile(ByteArrayInputStream(data), name).also { compiled ->
            synchronized(entries) {
                if (entries[key] == null) {
                    entries[key] = Entry(compiled, data.size)
                    bytes += data.size
                    while (entries.size > 40 || bytes > 4 * 1024 * 1024) {
                        val oldest = entries.entries.iterator()
                        val entry = oldest.next()
                        bytes -= entry.value.sourceBytes
                        oldest.remove()
                    }
                }
            }
        }
        return LuaClosure(prototype, globals)
    }
}
