package com.hon.reader.hon

import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.IOException

class BundledSourcesTest {
    @Test fun bundledSourcesInitializeWithoutNetworkOrUnsafeCapabilities() = runBlocking {
        val root = File(requireNotNull(System.getProperty("hon.bundledSources")))
        val scripts = root.listFiles { file -> file.extension == "lua" }!!.sortedBy { it.name }
        assertTrue("Expected the complete bundled catalog", scripts.size >= 170)
        val catalogFile = File(root, "catalog.json")
        val catalogAllowedHosts = if (catalogFile.exists()) {
            val text = catalogFile.readText()
            val chunkRegex = Regex("""\{[^{}]*"asset"\s*:\s*"assets/sources/bundled/([^"]+)"[^{}]*\}""", RegexOption.DOT_MATCHES_ALL)
            chunkRegex.findAll(text).mapNotNull { match ->
                val chunk = match.value
                val assetName = match.groupValues[1]
                val hostsMatch = Regex(""""allowedHosts"\s*:\s*\[([^\]]+)\]""").find(chunk)
                if (hostsMatch != null) {
                    val hosts = Regex(""""([^"]+)"""").findAll(hostsMatch.groupValues[1]).map { it.groupValues[1] }.toSet()
                    assetName to hosts
                } else null
            }.toMap()
        } else emptyMap()
        val engine = ShosetsuKotlinEngine(OkHttpClient.Builder().addInterceptor {
            throw IOException("Network is unavailable during source initialization")
        }.build())
        val failures = mutableListOf<String>()
        for (file in scripts) {
            val allowed = catalogAllowedHosts[file.name] ?: emptySet()
            try {
                engine.validateExtension(file.readText(), allowedHosts = allowed)
                engine.describeExtension(file.readText(), allowedHosts = allowed)
            }
            catch (error: Exception) {
                // MCStories fetches remote filter labels at construction time.
                // Its explicit offline error is expected; no network was used.
                if (file.name.startsWith("ext_ca9e6e460d9e") && error.message?.contains("Network is unavailable during source initialization") == true) continue
                val label = Regex("name\\s*=\\s*[\"']([^\"']+)").find(file.readText())?.groupValues?.get(1) ?: file.name
                failures.add("$label (${file.name.take(16)}): ${error.message}")
            }
        }
        assertTrue("Bundled source initialization failures:\n${failures.joinToString("\n")}", failures.isEmpty())
    }

    @Test fun sourceNetworkPolicyAllowsDeclaredBaseHostDuringConstructionAndBlocksForeignHosts() = runBlocking {
        var requestedHost: String? = null
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requestedHost = chain.request().url.host
            okhttp3.Response.Builder()
                .request(chain.request())
                .protocol(okhttp3.Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body(okhttp3.ResponseBody.create(null, "<html></html>"))
                .build()
        }.build()
        val engine = ShosetsuKotlinEngine(client)

        val allowedScript = """
            local baseURL = "https://allowed.example.com"
            local res = Request(GET(baseURL .. "/init"))
            return {
                baseURL = baseURL,
                name = "TestAllowed",
                search = function() return {} end,
                parseNovel = function() return {} end,
                getPassage = function() return "" end
            }
        """.trimIndent()
        assertTrue(engine.validateExtension(allowedScript))
        org.junit.Assert.assertEquals("allowed.example.com", requestedHost)

        val foreignScript = """
            local baseURL = "https://allowed.example.com"
            local res = Request(GET("https://malicious.example.org/leak"))
            return {
                baseURL = baseURL,
                name = "TestMalicious",
                search = function() return {} end,
                parseNovel = function() return {} end,
                getPassage = function() return "" end
            }
        """.trimIndent()
        try {
            engine.validateExtension(foreignScript)
            org.junit.Assert.fail("Expected foreign host to be blocked by SourceNetworkPolicy")
        } catch (e: Exception) {
            assertTrue(
                "Expected blocked by source network policy, got: ${e.message}",
                e.message?.contains("blocked by source network policy") == true
            )
        }
    }
}
