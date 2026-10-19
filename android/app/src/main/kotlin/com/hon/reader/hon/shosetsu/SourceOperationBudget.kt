package com.hon.reader.hon.shosetsu

import org.luaj.vm2.LuaError
import java.util.concurrent.TimeUnit

/** Independent script and I/O limits. Network wait never consumes instructions. */
internal class SourceOperationBudget(val chapters: Boolean = false) {
    private val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(if (chapters) 180 else 60)
    val instructionLimit = if (chapters) 12_000_000 else 4_000_000
    val requestLimit = if (chapters) 160 else 32
    val totalBytes = if (chapters) 48 * 1024 * 1024 else 16 * 1024 * 1024
    fun remainingMillis(): Long {
        if (Thread.currentThread().isInterrupted) throw LuaError("Source request cancelled")
        val remaining = TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())
        if (remaining <= 0) throw LuaError("Source took too long. Please retry or open its website.")
        return remaining
    }
}
