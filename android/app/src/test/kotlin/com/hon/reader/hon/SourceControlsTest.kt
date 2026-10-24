package com.hon.reader.hon

import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import com.hon.reader.hon.shosetsu.SourceHttpClient
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class SourceControlsTest {
    private val script = """
        local settings={}
        return {
          baseURL='https://source.test',
          settings={TextFilter(2,'Account name'),DropdownFilter(3,'Language',{'English','Japanese'}),SwitchFilter(4,'Feature')},
          setSettings=function(values) settings=values end,
          searchFilters={FilterGroup('Genre',{TextFilter(10,'Tag'),TriStateFilter(11,'Fantasy')})},
          search=function(data) return {{title=settings[2]..'/'..settings[3]..'/'..data[10]..'/'..data[11],link='novel'}} end,
          parseNovel=function() return {title=settings[2],chapters={}} end,
          getPassage=function() return '<p>'..settings[2]..'</p>' end
        }
    """.trimIndent()
    @Test fun exposesTypedControlsAndAppliesSettingsAndSearchFilters() = runBlocking {
        val engine=ShosetsuKotlinEngine()
        val info=engine.describeExtension(script)
        assertEquals("https://source.test",info["baseUrl"])
        assertEquals(3,(info["settings"] as List<*>).size)
        val filter=(info["filters"] as List<*>).first() as Map<*,*>
        assertEquals("Genre",filter["group"])
        val settings=mapOf("2" to "Alice","3" to 1,"4" to true)
        assertEquals("Alice/1/forest/2",engine.search(script,"story",0,null,settings,mapOf("10" to "forest","11" to 2)).single()["title"])
        assertEquals("<p>Alice</p>",engine.getPassage(script,"chapter",settings))
    }
    @Test fun rejectsInvalidControlTypesAndOptionIndices() = runBlocking {
        val engine=ShosetsuKotlinEngine()
        for (settings in listOf(mapOf("3" to 99),mapOf("4" to "true"))) {
            try { engine.search(script,"story",0,null,settings); fail("Invalid control was accepted") }
            catch (_:IllegalArgumentException) {}
        }
    }
    @Test fun sessionCookiesAreRestrictedToTheChosenSecureWebsite() {
        assertTrue(SourceHttpClient.allowsCookies("https://www.source.test", "https://source.test/novel".toHttpUrl()))
        assertTrue(SourceHttpClient.allowsCookies("https://source.test", "https://api.source.test/novel".toHttpUrl()))
        assertFalse(SourceHttpClient.allowsCookies("http://source.test", "https://source.test/".toHttpUrl()))
        assertFalse(SourceHttpClient.allowsCookies("https://co.uk", "https://another.co.uk/".toHttpUrl()))
        for(url in listOf("https://source.test.evil.test/","https://other-source.test/","http://source.test/")) {
            assertFalse(SourceHttpClient.allowsCookies("https://source.test",url.toHttpUrl()))
        }
    }

    @Test fun trustManagerAcceptsIsrgRootYrChain() {
        val cf = java.security.cert.CertificateFactory.getInstance("X.509")
        val leafPem = """
-----BEGIN CERTIFICATE-----
MIIFEjCCA/qgAwIBAgISBuOg1IVZpj3n4t533DO1rN9rMA0GCSqGSIb3DQEBCwUA
MDMxCzAJBgNVBAYTAlVTMRYwFAYDVQQKEw1MZXQncyBFbmNyeXB0MQwwCgYDVQQD
EwNZUjIwHhcNMjYxMDEwMTQwNTEwWhcNMjcwMTA4MTQwNTA5WjAcMRowGAYDVQQD
ExExc3RraXNzbm92ZWwubG92ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
ggEBAOm5r+BVGOeQJ9t4Al31qwHXI09DW7qCBSTeit1ty15DebrEPWayYtP32tak
RP70GT+cebSRIyOaR/lh4cKzo+Irl79y8YYiUnjcvdFsB6QR6W8ec6QstwtaJ+Lz
XiEO5C0XFuTjKC84sN0enlNYIRQzsU01ESpZjUv7mvl1xpP5aQNDkrLcp+Tdx5HJ
AudfmxaoZXEOYNJJpGm7h4s7yawTF96REj/B+UlaCCtxhXyK+WjaMrT89B5T3Z3f
XrORsg8vmyN57RnRN+FPQsMr6BdTdUs4GyRVvfOJFXIO3i5Lc227NMqgEkgx2+1w
O3RmuEje9u0Vcao+PN24vHqWqRcCAwEAAaOCAjUwggIxMA4GA1UdDwEB/wQEAwIF
oDATBgNVHSUEDDAKBggrBgEFBQcDATAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBRc
oWSZ/EizRzhIVF3TyS+lNOopyjAfBgNVHSMEGDAWgBRAFS0mee0yIJ7fmnId1jIf
gQyBDDAzBggrBgEFBQcBAQQnMCUwIwYIKwYBBQUHMAKGF2h0dHA6Ly95cjIuaS5s
ZW5jci5vcmcvMDEGA1UdEQQqMCiCEyouMXN0a2lzc25vdmVsLmxvdmWCETFzdGtp
c3Nub3ZlbC5sb3ZlMBMGA1UdIAQMMAowCAYGZ4EMAQIBMC8GA1UdHwQoMCYwJKAi
oCCGHmh0dHA6Ly95cjIuYy5sZW5jci5vcmcvMTA4LmNybDCCAQwGCisGAQQB1nkC
BAIEgf0EgfoA+AB3ANbVjanQF1Pzakqgx1dJAq/rx9ws04zZ92TIDIkZHp8CAAAB
oSZXV8AAAAQDAEgwRgIhAMIXR4D1VIL24cC+zK0fqDGTCFiI0XfOS1VWSMM0EzL0
AiEAukdBWRj1Cbajq70Q93SI7UrVYw1wKTao/N/MEMJ9MCcAfQCOykcLrN5q86IG
sKR6hLdG/h/Gv5U+JeabTuQCSPPG6AAAAaEmV1e0AAgAAAUAIIDW2wQDAEYwRAIg
Bv+58wOZ9B4goM5lqoI9X+TcG7IsubQlqDPo22tYC5cCIExjmTrCSsz9HQtv0sU0
8xDEMkMn+qbX6vqkWxie6wTBMA0GCSqGSIb3DQEBCwUAA4IBAQCVq+ZBjlOCGc2b
PyMtoYtY0z7KedaINa/9NA0qvEtJIY5arwRC+tJAFYlepWq29wXuEY5MhktwAbkr
pknTPXCvnp87C9gdZU7SUX70hiNsgo7od+Wf3233VHkl3bC5/TcVmK1yQDC7UMuS
tvFv8I/nlKCfRyDWhbZHVimIDMl/I/c5ny507mwVsuovNYVMqcQTvLqO6CaNlaTL
Y8i8giJ25TTRElRwdhRAqMc6yGJEFUC6+5vJeNPLUXsqaJq77eja5F5BGiXfAuzm
CWrZuavFIpd3PWaXvj0Jw3CZoYEFr1tSJM2NXL4vCx/QFJLN+oK9JB0jOnfl9P2g
miYuebiq
-----END CERTIFICATE-----
"""
        val intermediatePem = """
-----BEGIN CERTIFICATE-----
MIIE2jCCAsKgAwIBAgIQTr0klH4k05SALYSlL9WzGTANBgkqhkiG9w0BAQsFADAu
MQswCQYDVQQGEwJVUzENMAsGA1UEChMESVNSRzEQMA4GA1UEAxMHUm9vdCBZUjAe
Fw0yNTA5MDMwMDAwMDBaFw0yODA5MDIyMzU5NTlaMDMxCzAJBgNVBAYTAlVTMRYw
FAYDVQQKEw1MZXQncyBFbmNyeXB0MQwwCgYDVQQDEwNZUjIwggEiMA0GCSqGSIb3
DQEBAQUAA4IBDwAwggEKAoIBAQDZ0LxwBppqh84luqMerV/eeL/fXQ7mLQQv1Lnp
WKZbyvGpx6wh6AfnslAnF6ewTkcHA+gSOoBvm3Dfm06AuGiF+KRut4fAcowqnAQQ
CW98+QPP/eOv/wug7Iyk4NkOxf2I6g2f55T6nJoOTLFcukeRq80JGQEYan+dPFr9
OGUgQK2hGKgNkW87pappsOAuUJcroYhRt5uUis4qaZireiseu32gzDJNBAiKtsvd
6HX4v25bpkRNcS/B/Gtc9kVbUpD+2PLPxdei3Tim55k4tfAEXwD2qyiPTxrTNq6l
N+AMr5g2c1dNqkOTwjxeV6L5lpP1rGiYvLnRaPlOqyZRPW+5AgMBAAGjge4wgesw
DgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMBMBIGA1UdEwEB/wQI
MAYBAf8CAQAwHQYDVR0OBBYEFEAVLSZ57TIgnt+ach3WMh+BDIEMMB8GA1UdIwQY
MBaAFN7nW2DQIm1AKH0/DQH+pLVStFGUMDIGCCsGAQUFBwEBBCYwJDAiBggrBgEF
BQcwAoYWaHR0cDovL3lyLmkubGVuY3Iub3JnLzATBgNVHSAEDDAKMAgGBmeBDAEC
ATAnBgNVHR8EIDAeMBygGqAYhhZodHRwOi8veXIuYy5sZW5jci5vcmcvMA0GCSqG
SIb3DQEBCwUAA4ICAQB0ZUQWZ9/Yn9COEpo+JfecMnB0h0vwDm/M66IqXqw3LoaL
mx9lZvRTeDIS67PUeI3yCA2W6PKRD0/FE/G57lOmS+Xy5AaaL00ICGOqjNcCaMWW
8o8nevHOd4i4lqgtznE/28QwlcdJyF8yBiWHpnyjhEpmNWJURgOCOg2xpwRMBCsj
MScqYPtOhBeuYQvSwAEeTML2Ukh6uGuX4E14q65Ja8cdjF5bAldnP1eE4FBaAwsZ
G2fOqqrKV03Y85Nw2btedP1AtliQuJZs/Jo/gXxXdc7LrH3McgnpnbTiAncX7yES
hP6kzQejllqMCIt52HOjxDGWafS7Xw+DKwqmH+Eqy8dcbOuag/1AYlQoKNVK3F5q
Hh6tEDiMqQcLIibGKteE6iHo4A/bIScbzrhXUYuism42ZYzmc48FMVIH3qy4L84E
TdAH2gtxw0PAhvRVXp8HP7wfngpzsN/8xOTpeRSbM4+Qbc56G6+Bifmv6sk1ieQb
NA3wJdl4DDUuQSV8hBgx6zoI1ZSGORprDFux7c6rhc77QZMSRrEgomBeklervEve
86ylWmZ3WWHV6RLMi8xNvjd71r4EPIGgY7BZU/VPBkq+uA7Gb6mbJnFgV43uh3xy
LRFgxIAphIukwTGSMZZR+AI+Qnp0BYTWovHXozOf3H8r6hozEoT02JHn0AeTfA==
-----END CERTIFICATE-----
"""
        // Conscrypt only treats input as PEM when it starts with '-', so trim
        // the raw strings' leading newline.
        val leaf = cf.generateCertificate(leafPem.trim().byteInputStream()) as java.security.cert.X509Certificate
        val intermediate = cf.generateCertificate(intermediatePem.trim().byteInputStream()) as java.security.cert.X509Certificate
        val tm = SourceHttpClient.customTrustManagerForTesting()
        assertNotNull(tm)
        // The sample leaf expires (2027-01-08), so validate the chain at a
        // fixed date inside its lifetime against the trust manager's roots.
        // That keeps proving the bundled ISRG Root YR anchors it after expiry.
        val anchors = tm.acceptedIssuers.map { java.security.cert.TrustAnchor(it, null) }.toSet()
        val params = java.security.cert.PKIXParameters(anchors).apply {
            isRevocationEnabled = false
            date = java.util.Date(leaf.notBefore.time + 24L * 60 * 60 * 1000)
        }
        val path = cf.generateCertPath(listOf(leaf, intermediate))
        java.security.cert.CertPathValidator.getInstance("PKIX").validate(path, params)
        // While the leaf is still current, also go through the real check.
        if (java.util.Date().before(leaf.notAfter)) {
            tm.checkServerTrusted(arrayOf(leaf, intermediate), "RSA")
        }
    }
}

