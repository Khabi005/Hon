package com.hon.reader.hon

import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class OfflineChapterImagesTest {
    @Test fun embedsRelativeImagesOnceForOfflineReading() {
        var requests = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            assertEquals("https://example.org/images/map.png", chain.request().url.toString())
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK").body(byteArrayOf(1, 2, 3).toResponseBody("image/png".toMediaType())).build()
        }.build()
        val html = "<p>Text</p><img src='../images/map.png'><img src='../images/map.png'>"
        val result = OfflineChapterImages.embed(html, "https://example.org/chapter/1", client) { false }
        assertEquals(1, requests)
        assertEquals(2, Regex("data:image/png;base64,AQID").findAll(result).count())
        assertTrue(result.contains("Text"))
    }

    @Test(expected = IllegalStateException::class)
    fun cancelledChapterCannotCommitImages() {
        OfflineChapterImages.embed("<img src='https://example.org/a.png'>", "https://example.org/", OkHttpClient()) { true }
    }
}
