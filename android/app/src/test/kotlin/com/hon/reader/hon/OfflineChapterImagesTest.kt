package com.hon.reader.hon

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.Base64

class OfflineChapterImagesTest {
    @Before
    fun setUp() {
        OfflineChapterImages.defaultCodec = FakeImageCodec()
    }

    private val valid1x1Png = Base64.getDecoder().decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )

    @Test
    fun embedsRelativeImagesOnceForOfflineReading() {
        var requests = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            assertEquals("https://example.org/images/map.png", chain.request().url.toString())
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK")
                .body(valid1x1Png.toResponseBody("image/png".toMediaType()))
                .build()
        }.build()
        val html = "<p>Text</p><img src='../images/map.png'><img src='../images/map.png'>"
        val result = OfflineChapterImages.embed(html, "https://example.org/chapter/1", client) { false }
        assertEquals(1, requests)
        assertEquals(2, Regex("data:image/png;base64,").findAll(result).count())
        assertTrue(result.contains("Text"))
    }

    @Test(expected = IllegalStateException::class)
    fun cancelledChapterCannotCommitImages() {
        OfflineChapterImages.embed("<img src='https://example.org/a.png'>", "https://example.org/", OkHttpClient()) { true }
    }

    @Test
    fun invalidBytesProduceMissingImageFallback() {
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK")
                .body(byteArrayOf(1, 2, 3).toResponseBody("image/png".toMediaType()))
                .build()
        }.build()
        val html = "<p>Text</p><img src='https://example.org/bad.png' alt='Corrupt Image'>"
        val result = OfflineChapterImages.embed(html, "https://example.org/", client) { false }
        assertTrue(result.contains("class=\"hon-missing-image\""))
        assertTrue(result.contains("Corrupt Image"))
        assertTrue(result.contains("class=\"hon-offline-notice\""))
        assertFalse(result.contains("data:image/"))
    }

    @Test
    fun resizedWebpGifPngCompressToPngWithMatchingMimeAndExtension() {
        val tempDir = File.createTempFile("hon_test_img_", "").apply {
            delete()
            mkdirs()
        }
        try {
            // PNG > 1600px (1800 x 1200)
            val widePng = byteArrayOf(
                -119, 80, 78, 71, 13, 10, 26, 10,
                0, 0, 0, 13,
                73, 72, 68, 82,
                0, 0, 7, 8, // width = 1800
                0, 0, 4, -80, // height = 1200
                8, 6, 0, 0, 0,
                0, 0, 0, 0
            )

            // GIF > 1600px (1920 x 1080)
            val wideGif = byteArrayOf(
                71, 73, 70, 56, 57, 97, // GIF89a
                -128, 7, // width = 1920 (0x0780)
                56, 4 // height = 1080 (0x0438)
            )

            // WebP > 1600px (1800 x 1200 VP8)
            val wideWebp = ByteArray(32).apply {
                "RIFF".toByteArray().copyInto(this, 0)
                "WEBP".toByteArray().copyInto(this, 8)
                "VP8 ".toByteArray().copyInto(this, 12)
                this[26] = 8 // width 1800
                this[27] = 7
                this[28] = (-80).toByte() // height 1200
                this[29] = 4
            }

            val client = OkHttpClient.Builder().addInterceptor { chain ->
                val url = chain.request().url.toString()
                val (bytes, mime) = when {
                    url.endsWith("wide.png") -> widePng to "image/png"
                    url.endsWith("wide.gif") -> wideGif to "image/gif"
                    url.endsWith("wide.webp") -> wideWebp to "image/webp"
                    else -> error("Unexpected url $url")
                }
                Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                    .code(200).message("OK")
                    .body(bytes.toResponseBody(mime.toMediaType()))
                    .build()
            }.build()

            // 1. Data URI mode: all resized non-JPEG images become data:image/png
            val dataUriHtml = """
                <img src='https://example.org/wide.png'>
                <img src='https://example.org/wide.gif'>
                <img src='https://example.org/wide.webp'>
            """.trimIndent()
            val dataUriResult = OfflineChapterImages.embed(dataUriHtml, "https://example.org/", client) { false }
            assertEquals(3, Regex("data:image/png;base64,").findAll(dataUriResult).count())
            assertFalse(dataUriResult.contains("data:image/gif;base64"))
            assertFalse(dataUriResult.contains("data:image/webp;base64"))

            // 2. Directory mode: all resized non-JPEG files on disk have .png extension and PNG decoded format
            val fileHtml = """
                <img src='https://example.org/wide.png'>
                <img src='https://example.org/wide.gif'>
                <img src='https://example.org/wide.webp'>
            """.trimIndent()
            OfflineChapterImages.embed(fileHtml, "https://example.org/", client, imagesDir = tempDir) { false }
            val filesOnDisk = tempDir.listFiles() ?: emptyArray()
            assertEquals(3, filesOnDisk.size)
            for (f in filesOnDisk) {
                // Assert extension
                assertTrue("File on disk should be .png: ${f.name}", f.name.endsWith(".png"))
                assertFalse("File on disk must not retain .gif: ${f.name}", f.name.endsWith(".gif"))
                assertFalse("File on disk must not retain .webp: ${f.name}", f.name.endsWith(".webp"))

                // Assert decoded format (PNG magic header: 0x89, 'P', 'N', 'G')
                val bytes = f.readBytes()
                assertTrue(
                    "Decoded format must be PNG magic header: ${f.name}",
                    bytes.size >= 8 &&
                        bytes[0] == (-119).toByte() &&
                        bytes[1] == 80.toByte() &&
                        bytes[2] == 78.toByte() &&
                        bytes[3] == 71.toByte()
                )
            }
        } finally {
            tempDir.deleteRecursively()
        }
    }

    @Test
    fun unresizedWebpAndGifRetainMatchingMimeAndExtension() {
        val tempDir = File.createTempFile("hon_test_img2_", "").apply {
            delete()
            mkdirs()
        }
        try {
            // PNG <= 1600px (1 x 1)
            val smallPng = valid1x1Png

            // GIF <= 1600px (100 x 100)
            val smallGif = byteArrayOf(
                71, 73, 70, 56, 57, 97, // GIF89a
                100, 0, // width = 100
                100, 0 // height = 100
            )

            // WebP <= 1600px (100 x 100 VP8)
            val smallWebp = ByteArray(32).apply {
                "RIFF".toByteArray().copyInto(this, 0)
                "WEBP".toByteArray().copyInto(this, 8)
                "VP8 ".toByteArray().copyInto(this, 12)
                this[26] = 100 // width 100
                this[27] = 0
                this[28] = 100 // height 100
                this[29] = 0
            }

            val client = OkHttpClient.Builder().addInterceptor { chain ->
                val url = chain.request().url.toString()
                val (bytes, mime) = when {
                    url.endsWith("small.png") -> smallPng to "image/png"
                    url.endsWith("small.gif") -> smallGif to "image/gif"
                    url.endsWith("small.webp") -> smallWebp to "image/webp"
                    else -> error("Unexpected url $url")
                }
                Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                    .code(200).message("OK")
                    .body(bytes.toResponseBody(mime.toMediaType()))
                    .build()
            }.build()

            // 1. Data URI mode: unresized images retain their respective MIME types
            val dataUriHtml = """
                <img src='https://example.org/small.png'>
                <img src='https://example.org/small.gif'>
                <img src='https://example.org/small.webp'>
            """.trimIndent()
            val dataUriResult = OfflineChapterImages.embed(dataUriHtml, "https://example.org/", client) { false }
            assertTrue("MIME must be image/png", dataUriResult.contains("data:image/png;base64,"))
            assertTrue("MIME must be image/gif", dataUriResult.contains("data:image/gif;base64,"))
            assertTrue("MIME must be image/webp", dataUriResult.contains("data:image/webp;base64,"))

            // 2. Directory mode: unresized images retain their respective extensions and decoded formats
            val fileHtml = """
                <img src='https://example.org/small.png'>
                <img src='https://example.org/small.gif'>
                <img src='https://example.org/small.webp'>
            """.trimIndent()
            OfflineChapterImages.embed(fileHtml, "https://example.org/", client, imagesDir = tempDir) { false }
            val filesOnDisk = tempDir.listFiles() ?: emptyArray()
            assertEquals(3, filesOnDisk.size)

            // PNG check: extension + decoded format (magic bytes)
            val pngFile = filesOnDisk.first { it.name.endsWith(".png") }
            val pngBytes = pngFile.readBytes()
            assertTrue("PNG extension asserted", pngFile.name.endsWith(".png"))
            assertTrue(
                "Decoded format must be PNG magic bytes",
                pngBytes.size >= 8 &&
                    pngBytes[0] == (-119).toByte() &&
                    pngBytes[1] == 80.toByte() &&
                    pngBytes[2] == 78.toByte() &&
                    pngBytes[3] == 71.toByte()
            )

            // GIF check: extension + decoded format (magic bytes)
            val gifFile = filesOnDisk.first { it.name.endsWith(".gif") }
            val gifBytes = gifFile.readBytes()
            assertTrue("GIF extension asserted", gifFile.name.endsWith(".gif"))
            assertTrue(
                "Decoded format must be GIF header (GIF89a)",
                gifBytes.take(6).toByteArray().contentEquals("GIF89a".toByteArray())
            )

            // WebP check: extension + decoded format (magic bytes)
            val webpFile = filesOnDisk.first { it.name.endsWith(".webp") }
            val webpBytes = webpFile.readBytes()
            assertTrue("WebP extension asserted", webpFile.name.endsWith(".webp"))
            assertTrue(
                "Decoded format must be WebP header (RIFF....WEBP)",
                webpBytes.take(4).toByteArray().contentEquals("RIFF".toByteArray()) &&
                    webpBytes.copyOfRange(8, 12).contentEquals("WEBP".toByteArray())
            )
        } finally {
            tempDir.deleteRecursively()
        }
    }
}
