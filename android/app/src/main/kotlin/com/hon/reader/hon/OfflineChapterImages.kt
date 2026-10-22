package com.hon.reader.hon

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.Base64
import java.util.concurrent.TimeUnit

data class ProcessedImage(
    val bytes: ByteArray,
    val mimeType: String,
    val extension: String,
    val width: Int,
    val height: Int
)

interface ImageCodec {
    fun process(bytes: ByteArray, initialMime: String): ProcessedImage
}

class AndroidImageCodec : ImageCodec {
    override fun process(bytes: ByteArray, initialMime: String): ProcessedImage {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        require(options.outWidth > 0 && options.outHeight > 0) { "Corrupt or invalid image dimensions" }

        val origWidth = options.outWidth
        val origHeight = options.outHeight

        // Disallow excessive decompression bombs (> 30 megapixels) without aggressive subsampling
        var sampleSize = 1
        while (origWidth / sampleSize > 1600 || (origWidth.toLong() * origHeight.toLong()) / (sampleSize.toLong() * sampleSize.toLong()) > 4_000_000L) {
            sampleSize *= 2
        }

        if (sampleSize > 1 || origWidth > 1600) {
            val decodeOptions = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
            }
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOptions)
                ?: error("Failed to decode image bitmap")
            try {
                val targetWidth = if (bitmap.width > 1600) 1600 else bitmap.width
                val targetHeight = (bitmap.height.toDouble() * (targetWidth.toDouble() / bitmap.width.toDouble())).toInt().coerceAtLeast(1)
                val scaled = if (bitmap.width != targetWidth || bitmap.height != targetHeight) {
                    Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
                } else bitmap

                try {
                    val stream = ByteArrayOutputStream()
                    val isJpeg = initialMime == "image/jpeg"
                    val format = if (isJpeg) Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG
                    scaled.compress(format, 85, stream)
                    val resultBytes = stream.toByteArray()
                    return if (isJpeg) {
                        ProcessedImage(resultBytes, "image/jpeg", "jpg", scaled.width, scaled.height)
                    } else {
                        ProcessedImage(resultBytes, "image/png", "png", scaled.width, scaled.height)
                    }
                } finally {
                    if (scaled != bitmap) scaled.recycle()
                }
            } finally {
                bitmap.recycle()
            }
        }

        // For unresized images, also validate that the bitmap can actually be fully decoded
        val testBitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: error("Corrupt image data cannot be decoded")
        val w = testBitmap.width
        val h = testBitmap.height
        testBitmap.recycle()

        val ext = when (initialMime) {
            "image/jpeg" -> "jpg"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            else -> "png"
        }
        return ProcessedImage(bytes, initialMime, ext, w, h)
    }
}

/**
 * Downloads and caches chapter illustrations offline.
 * Content-addressed SHA-256 files are saved into Hon's managed images directory,
 * with images downscaled to a max width of 1600px to protect memory and disk.
 * Unavailable illustrations never discard an otherwise readable chapter.
 */
internal object OfflineChapterImages {
    var defaultCodec: ImageCodec = AndroidImageCodec()

    private val allowedMimes = setOf("image/jpeg", "image/png", "image/gif", "image/webp")

    private fun mime(bytes: ByteArray, headerMime: String? = null): String? {
        val magicMime = when {
            bytes.size >= 3 && bytes[0].toInt() and 255 == 255 && bytes[1].toInt() and 255 == 216 && bytes[2].toInt() and 255 == 255 -> "image/jpeg"
            bytes.size >= 8 && bytes.copyOfRange(0, 8).contentEquals(byteArrayOf(-119,80,78,71,13,10,26,10)) -> "image/png"
            bytes.size >= 6 && String(bytes, 0, 6, Charsets.US_ASCII) in setOf("GIF87a", "GIF89a") -> "image/gif"
            bytes.size >= 12 && String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" && String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP" -> "image/webp"
            else -> null
        }
        if (magicMime != null) return magicMime
        val cleanHeader = headerMime?.substringBefore(";")?.trim()?.lowercase()
        return if (cleanHeader in allowedMimes) cleanHeader else null
    }

    fun embed(
        html: String,
        baseUrl: String,
        client: OkHttpClient,
        imagesDir: File? = null,
        codec: ImageCodec = defaultCodec,
        cancelled: () -> Boolean
    ): String {
        val document = Jsoup.parse(html, baseUrl)
        val images = document.select("img[src], img[data-src]")
        if (images.isEmpty()) return html
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(60)
        var total = 0
        var missing = 0
        val cached = mutableMapOf<String, String>()

        for (image in images) {
            check(!cancelled()) { "Chapter download was cancelled" }
            if (System.nanoTime() >= deadline || total >= 12 * 1024 * 1024) {
                missing++
                image.replaceWith(
                    Element("p").attr("class", "hon-missing-image")
                        .text(image.attr("alt").ifBlank { "Illustration omitted to prevent excessive chapter download size" })
                )
                continue
            }

            val source = (image.attr("src").ifBlank { image.attr("data-src") }).trim()
            if (source.startsWith("data:")) continue
            val absolute = try {
                document.baseUri().let { base ->
                    if (base.isNotBlank()) image.absUrl("src").ifBlank { image.absUrl("data-src") }
                    else source
                }
            } catch (_: Exception) { source }

            if (absolute.isBlank()) {
                missing++
                image.replaceWith(
                    Element("p").attr("class", "hon-missing-image")
                        .text(image.attr("alt").ifBlank { "Illustration link is empty" })
                )
                continue
            }

            try {
                val data = cached.getOrPut(absolute) {
                    val request = Request.Builder().url(absolute).build()
                    client.newCall(request).execute().use { response ->
                        require(response.isSuccessful) { "HTTP ${response.code}" }
                        val body = response.body ?: error("Empty response body")
                        val output = ByteArrayOutputStream()
                        body.byteStream().use { input ->
                            val buffer = ByteArray(8192)
                            while (true) {
                                check(!cancelled()) { "Chapter download was cancelled" }
                                val count = input.read(buffer)
                                if (count < 0) break
                                total += count
                                require(output.size() + count <= 2 * 1024 * 1024 && total <= 12 * 1024 * 1024 && System.nanoTime() < deadline) { "Illustration limit reached" }
                                output.write(buffer, 0, count)
                            }
                        }
                        val rawBytes = output.toByteArray()
                        val headerType = (response.body?.contentType()?.toString() ?: response.header("Content-Type"))?.substringBefore(";")?.trim()
                        val type = mime(rawBytes, headerType) ?: error("Unsupported illustration format")
                        val processed = codec.process(rawBytes, type)

                        if (imagesDir != null) {
                            val digest = MessageDigest.getInstance("SHA-256")
                            val hash = digest.digest(processed.bytes).joinToString("") { "%02x".format(it) }
                            val filename = "$hash.${processed.extension}"
                            val dest = File(imagesDir, filename)
                            if (!dest.exists()) {
                                val temp = File.createTempFile("hon_img_", ".tmp", imagesDir)
                                FileOutputStream(temp).use { fos ->
                                    fos.write(processed.bytes)
                                    fos.fd.sync()
                                }
                                if (!temp.renameTo(dest)) {
                                    temp.copyTo(dest, overwrite = true)
                                    temp.delete()
                                }
                            }
                            dest.toURI().toString()
                        } else {
                            "data:${processed.mimeType};base64," + Base64.getEncoder().encodeToString(processed.bytes)
                        }
                    }
                }
                image.attr("src", data).removeAttr("srcset").removeAttr("data-src")
            } catch (error: Exception) {
                check(!cancelled()) { "Chapter download was cancelled" }
                missing++
                image.replaceWith(
                    Element("p").attr("class", "hon-missing-image")
                        .text(image.attr("alt").ifBlank { "Illustration unavailable offline" })
                )
            }
        }

        if (missing > 0) {
            val notice = Element("p").attr("class", "hon-offline-notice")
                .text("$missing illustration(s) could not be downloaded for offline reading.")
            document.body().prependChild(notice)
        }

        return document.body().html()
    }
}
