package com.hon.reader.hon.shosetsu

import com.google.common.net.InternetDomainName
import okhttp3.HttpUrl
import java.io.IOException

class SourceNetworkPolicyException(val host: String) :
    IOException("Network request to '$host' blocked by source network policy.")

/**
 * Restricts network requests made by Shosetsu extension Lua scripts.
 * Allowed targets:
 *  1. The extension's declared baseURL registrable domain and all its subdomains.
 *  2. An explicit per-source allowlist of additional hosts/domains.
 */
class SourceNetworkPolicy(
    var baseHost: String? = null,
    val extraAllowedHosts: MutableSet<String> = mutableSetOf()
) {
    fun isAllowed(url: HttpUrl): Boolean {
        val host = url.host.lowercase()

        // 1. Check extra allowed hosts
        for (allowed in extraAllowedHosts) {
            val a = cleanHost(allowed)
            if (a.isEmpty()) continue
            if (host == a || host.endsWith(".$a")) return true
        }

        // 2. Check baseHost and its registrable domain
        val base = baseHost?.trim()
        if (!base.isNullOrBlank()) {
            val cleanBase = cleanHost(base)
            val baseHostName = cleanBase.substringBefore('/').substringBefore(':')
            if (baseHostName.isNotEmpty()) {
                if (host == baseHostName || host.endsWith(".$baseHostName")) return true
                val regDomain = registrableDomain(baseHostName)
                if (host == regDomain || host.endsWith(".$regDomain")) return true
            }
        }

        return false
    }

    fun checkUrl(url: HttpUrl) {
        if (!isAllowed(url)) {
            throw SourceNetworkPolicyException(url.host)
        }
    }

    private fun cleanHost(raw: String): String {
        return raw.trim()
            .lowercase()
            .removePrefix("https://")
            .removePrefix("http://")
            .trimEnd('/')
    }

    private fun registrableDomain(hostname: String): String {
        return try {
            if (InternetDomainName.isValid(hostname)) {
                val idn = InternetDomainName.from(hostname)
                if (idn.isUnderPublicSuffix) {
                    idn.topPrivateDomain().toString().lowercase()
                } else {
                    hostname
                }
            } else {
                hostname
            }
        } catch (_: Exception) {
            hostname
        }
    }
}
