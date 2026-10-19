package com.hon.reader.hon.shosetsu

import org.luaj.vm2.*
import org.luaj.vm2.lib.TwoArgFunction

/** LuaJ uses one static string metatable. Dispatch its method lookups to the
 * current synchronous script invocation, never another source's mutable table.
 * The protected metatable itself cannot be obtained or changed by Lua code. */
internal object SandboxStringMethods {
    private val current = ThreadLocal<Globals>()
    private val metatable = LuaTable().apply {
        set("__metatable", LuaValue.FALSE)
        set("__index", object : TwoArgFunction() {
            override fun call(value: LuaValue, key: LuaValue): LuaValue =
                current.get()?.get("string")?.get(key) ?: LuaValue.NIL
        })
    }
    @Synchronized fun enter(globals: Globals) {
        LuaString.s_metatable = metatable
        current.set(globals)
    }
    fun leave() { current.remove() }
}
