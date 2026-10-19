package com.hon.reader.hon.shosetsu

import android.content.Context
import android.webkit.CookieManager
import okhttp3.Cookie
import com.google.common.net.InternetDomainName
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/** Cookies are checked per URL, including redirects, rather than attached as
 * a raw request header that could follow a redirect to another website. */
object SourceHttpClient {
    private val trustManager: X509TrustManager by lazy {
        val systemTmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply {
            init(null as KeyStore?)
        }
        val systemTm = systemTmf.trustManagers.filterIsInstance<X509TrustManager>().first()

        val bundledCerts = mutableListOf<X509Certificate>()
        try {
            val cf = CertificateFactory.getInstance("X.509")
            SourceHttpClient::class.java.classLoader?.getResourceAsStream("certificates/isrg_root_yr.crt")?.use { stream ->
                cf.generateCertificates(stream).filterIsInstance<X509Certificate>().forEach { bundledCerts.add(it) }
            }
        } catch (_: Exception) {}

        if (bundledCerts.isEmpty()) {
            systemTm
        } else {
            val customKeyStore = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
                load(null, null)
            }
            var idx = 0
            for (issuer in systemTm.acceptedIssuers) {
                customKeyStore.setCertificateEntry("sys_${idx++}", issuer)
            }
            for (cert in bundledCerts) {
                customKeyStore.setCertificateEntry("bundled_${idx++}", cert)
            }
            val customTmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply {
                init(customKeyStore)
            }
            val customTm = customTmf.trustManagers.filterIsInstance<X509TrustManager>().first()

            object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                    try {
                        systemTm.checkClientTrusted(chain, authType)
                    } catch (e: CertificateException) {
                        customTm.checkClientTrusted(chain, authType)
                    }
                }

                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                    try {
                        systemTm.checkServerTrusted(chain, authType)
                    } catch (e: CertificateException) {
                        customTm.checkServerTrusted(chain, authType)
                    }
                }

                override fun getAcceptedIssuers(): Array<X509Certificate> =
                    systemTm.acceptedIssuers + customTm.acceptedIssuers
            }
        }
    }

    private val sslSocketFactory by lazy {
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf(trustManager), null)
        sslContext.socketFactory
    }

    private val shared = OkHttpClient.Builder()
        .connectTimeout(25, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(25, java.util.concurrent.TimeUnit.SECONDS)
        .callTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
        .sslSocketFactory(sslSocketFactory, trustManager)
        .build()
    fun allowsCookies(origin: String?, url: HttpUrl): Boolean {
        val chosen = origin?.toHttpUrlOrNull() ?: return false
        if (!chosen.isHttps) return false
        val base = chosen.host.removePrefix("www.")
        if (InternetDomainName.isValid(base) && InternetDomainName.from(base).isPublicSuffix) return false
        return url.isHttps && (url.host == base || url.host.endsWith(".$base"))
    }
    fun create(context: Context, sourceId: String): OkHttpClient = shared.newBuilder()
        .cookieJar(cookies(context, sourceId))
        .addNetworkInterceptor { chain ->
            val preferences = context.getSharedPreferences("hon_source_auth_origins", Context.MODE_PRIVATE)
            val request = chain.request()
            val agent = preferences.getString("${sourceId}_user_agent", null)
            val authenticated = allowsCookies(preferences.getString(sourceId, null), request.url)
            chain.proceed(if (authenticated && !agent.isNullOrBlank()) request.newBuilder().header("User-Agent", agent).build() else request)
        }.build()

    fun cookies(context: Context, sourceId: String) = object : CookieJar {
        private fun allowed(url: HttpUrl) = allowsCookies(context.getSharedPreferences("hon_source_auth_origins", Context.MODE_PRIVATE).getString(sourceId, null), url)
        override fun loadForRequest(url: HttpUrl): List<Cookie> {
            if (!allowed(url)) return emptyList()
            val raw = CookieManager.getInstance().getCookie(url.toString()) ?: return emptyList()
            return raw.split(';').mapNotNull { part ->
                val pair = part.trim().split('=', limit = 2)
                if (pair.size != 2) null else try {
                    Cookie.Builder().name(pair[0]).value(pair[1]).hostOnlyDomain(url.host).path("/").secure().build()
                } catch (_: IllegalArgumentException) { null }
            }
        }
        override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
            if (!allowed(url)) return
            val manager = CookieManager.getInstance()
            for (cookie in cookies) manager.setCookie(url.toString(), cookie.toString())
            manager.flush()
        }
    }
}
