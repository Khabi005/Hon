package com.hon.reader.hon

import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.Assume.assumeTrue
import java.io.File

class SourceRuntimeRegressionTest {
    @Test fun reflectiveLibrariesHaveTheirNamedConstructors() {
        // The companion release check inspects DEX, because JVM tests alone do
        // not exercise the shrinker that caused the Android crash.
        for (name in listOf("Bit32Lib\$Bit32LibV", "Bit32Lib\$Bit32Lib2")) {
            assertNotNull(Class.forName("org.luaj.vm2.lib.$name").getDeclaredConstructor())
        }
        val globals = ShosetsuKotlinEngine().createSandboxedGlobals()
        assertEquals(2, globals.load("return bit32.band(3, 2)").call().toint())
        assertEquals(8, globals.load("return bit32.lshift(1, 3)").call().toint())
    }

    /** Explicitly opt in: never makes CI or ordinary tests depend on websites. */
    @Test fun liveCatalogDiagnostic() = runBlocking {
        assumeTrue(System.getenv("HON_LIVE_SOURCE_CHECK") == "1")
        val root = File(requireNotNull(System.getProperty("hon.bundledSources")))
        for ((name, id) in listOf(
            "RoyalRoad" to "934c81536620b80bcb8750e8e3170dbacc8e3defb15fa28e56a9c9fd65666ebe",
            "ScribbleHub" to "84106451c6230a756e06965dfee6893736f0010bb1b67009e58a4e7529a696ee"
        )) {
            try {
                val items = ShosetsuKotlinEngine().search(File(root, "ext_$id.lua").readText(), "", 0)
                println("LIVE $name: ${items.size} novels; first=${items.firstOrNull()?.get("title")}")
            } catch (error: Exception) { println("LIVE $name: ${error.javaClass.simpleName}: ${error.message}") }
        }
    }
}
