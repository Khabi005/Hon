package com.hon.reader.hon

import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import java.util.concurrent.ConcurrentHashMap

/** One chapter per source, at most two globally. Cancellation remains cooperative. */
internal object DownloadRequestGate {
    private val global = Semaphore(2)
    private val sources = ConcurrentHashMap<String, Mutex>()
    private val nextRequest = ConcurrentHashMap<String, Long>()
    suspend fun <T> run(source: String, block: suspend () -> T): T =
        sources.getOrPut(source) { Mutex() }.withLock {
            val wait = (nextRequest[source] ?: 0) - System.nanoTime()
            if (wait > 0) delay((wait / 1_000_000).coerceAtLeast(1))
            global.withPermit {
                try { block() } finally {
                    nextRequest[source] = System.nanoTime() + 800_000_000L
                }
            }
        }
}
