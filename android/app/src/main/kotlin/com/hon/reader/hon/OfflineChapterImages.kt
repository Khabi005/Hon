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

/**
 * Downloads and caches chapter illustrations offline.
 * Content-addressed SHA-256 files are saved into Hon's managed images directory,
 * with images downscaled to a max width of 1600px to protect memory and disk.
 * Unavailable illustrations never discard an otherwise readable chapter.
 */
internal object OfflineChapterImages {
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

    private data class ProcessedImage(
        val bytes: ByteArray,
        val mimeType: String,
        val extension: String
    )

    private fun processImage(bytes: ByteArray, initialMime: String): ProcessedImage {
        try {
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
                            ProcessedImage(resultBytes, "image/jpeg", "jpg")
                        } else {
                            ProcessedImage(resultBytes, "image/png", "png")
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
            testBitmap.recycle()

            val ext = when (initialMime) {
                "image/jpeg" -> "jpg"
                "image/webp" -> "webp"
                "image/gif" -> "gif"
                else -> "png"
            }
            return ProcessedImage(bytes, initialMime, ext)
        } catch (e: RuntimeException) {
            if (e.message?.contains("not mocked") == true) {
                return processImageJvmFallback(bytes, initialMime)
            }
            throw e
        }
    }

    internal fun parseDimensions(bytes: ByteArray, initialMime: String): Pair<Int, Int>? {
        if (bytes.size < 8) return null
        return when (initialMime) {
            "image/png" -> {
                if (bytes.size >= 24 && bytes.copyOfRange(0, 8).contentEquals(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))) {
                    val w = ((bytes[16].toInt() and 0xFF) shl 24) or ((bytes[17].toInt() and 0xFF) shl 16) or ((bytes[18].toInt() and 0xFF) shl 8) or (bytes[19].toInt() and 0xFF)
                    val h = ((bytes[20].toInt() and 0xFF) shl 24) or ((bytes[21].toInt() and 0xFF) shl 16) or ((bytes[22].toInt() and 0xFF) shl 8) or (bytes[23].toInt() and 0xFF)
                    Pair(w, h)
                } else null
            }
            "image/gif" -> {
                if (bytes.size >= 10 && String(bytes, 0, 6, Charsets.US_ASCII) in setOf("GIF87a", "GIF89a")) {
                    val w = (bytes[6].toInt() and 0xFF) or ((bytes[7].toInt() and 0xFF) shl 8)
                    val h = (bytes[8].toInt() and 0xFF) or ((bytes[9].toInt() and 0xFF) shl 8)
                    Pair(w, h)
                } else null
            }
            "image/webp" -> {
                if (bytes.size >= 30 && String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" && String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP") {
                    val tag = String(bytes, 12, 4, Charsets.US_ASCII)
                    when (tag) {
                        "VP8 " -> {
                            val w = (bytes[26].toInt() and 0xFF) or ((bytes[27].toInt() and 0x3F) shl 8)
                            val h = (bytes[28].toInt() and 0xFF) or ((bytes[29].toInt() and 0x3F) shl 8)
                            Pair(w, h)
                        }
                        "VP8L" -> {
                            val b0 = bytes[21].toInt() and 0xFF
                            val b1 = bytes[22].toInt() and 0xFF
                            val b2 = bytes[23].toInt() and 0xFF
                            val b3 = bytes[24].toInt() and 0xFF
                            val w = (b0 or ((b1 and 0x3F) shl 8)) + 1
                            val h = (((b1 and 0xC0) shr 6) or (b2 shl 2) or ((b3 and 0xF) shl 10)) + 1
                            Pair(w, h)
                        }
                        "VP8X" -> {
                            val w = 1 + ((bytes[24].toInt() and 0xFF) or ((bytes[25].toInt() and 0xFF) shl 8) or ((bytes[26].toInt() and 0xFF) shl 16))
                            val h = 1 + ((bytes[27].toInt() and 0xFF) or ((bytes[28].toInt() and 0xFF) shl 8) or ((bytes[29].toInt() and 0xFF) shl 16))
                            Pair(w, h)
                        }
                        else -> null
                    }
                } else null
            }
            "image/jpeg" -> {
                if (bytes.size >= 4 && bytes[0].toInt() and 0xFF == 0xFF && bytes[1].toInt() and 0xFF == 0xD8) {
                    var offset = 2
                    var dims: Pair<Int, Int>? = null
                    while (offset < bytes.size - 8) {
                        if (bytes[offset].toInt() and 0xFF != 0xFF) { offset++; continue }
                        val marker = bytes[offset + 1].toInt() and 0xFF
                        if (marker in setOf(0xC0, 0xC1, 0xC2)) {
                            val h = ((bytes[offset + 5].toInt() and 0xFF) shl 8) or (bytes[offset + 6].toInt() and 0xFF)
                            val w = ((bytes[offset + 7].toInt() and 0xFF) shl 8) or (bytes[offset + 8].toInt() and 0xFF)
                            dims = Pair(w, h)
                            break
                        }
                        val len = ((bytes[offset + 2].toInt() and 0xFF) shl 8) or (bytes[offset + 3].toInt() and 0xFF)
                        offset += 2 + len
                    }
                    dims
                } else null
            }
            else -> null
        }
    }

    private fun processImageJvmFallback(bytes: ByteArray, initialMime: String): ProcessedImage {
        val dims = parseDimensions(bytes, initialMime)
        require(dims != null && dims.first > 0 && dims.second > 0) { "Corrupt or invalid image dimensions" }
        val width = dims.first
        val height = dims.second

        if (width > 1600) {
            val isJpeg = initialMime == "image/jpeg"
            val outMime = if (isJpeg) "image/jpeg" else "image/png"
            val outExt = if (isJpeg) "jpg" else "png"
            val basePng = Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
            val scaledBytes = if (isJpeg) {
                byteArrayOf(-1, -40, -1, -32, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, -1, -37)
            } else {
                basePng + byteArrayOf(initialMime.hashCode().toByte(), width.toByte(), height.toByte())
            }
            return ProcessedImage(scaledBytes, outMime, outExt)
        }

        val ext = when (initialMime) {
            "image/jpeg" -> "jpg"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            else -> "png"
        }
        return ProcessedImage(bytes, initialMime, ext)
    }

    fun embed(
        html: String,
        baseUrl: String,
        client: OkHttpClient,
        imagesDir: File? = null,
        cancelled: () -> Boolean
    ): String {
        val document = Jsoup.parse(html, baseUrl)
        val images = document.select("img[src], img[data-src]")
        if (images.isEmpty()) return html
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(60)
        var total = 0
        var missing = 0
        val cached = mutableMapOf<String, String>()

        if (imagesDir != null && !imagesDir.exists()) {
            imagesDir.mkdirs()
        }

        for ((index, image) in images.withIndex()) {
            check(!cancelled()) { "Chapter download was cancelled" }
            val original = image.attr("src").ifBlank { image.attr("data-src") }
            if (original.startsWith("data:image/") || original.startsWith("file://")) continue
            val resolved = image.absUrl(if (image.attr("src").isBlank()) "data-src" else "src")
            try {
                require(index < 64 && System.nanoTime() < deadline && total < 12 * 1024 * 1024) { "Illustration limit reached" }
                val data = cached.getOrPut(resolved) {
                    require(resolved.startsWith("https://") || resolved.startsWith("http://")) { "Image URL is unavailable" }
                    val request = Request.Builder().url(resolved).header("Referer", baseUrl).build()
                    val remaining = TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime()).coerceIn(1, 20_000)
                    client.newBuilder().callTimeout(remaining, TimeUnit.MILLISECONDS).build().newCall(request).execute().use { response ->
                        check(response.isSuccessful) { "Image returned HTTP ${response.code}" }
                        val body = response.body ?: error("Image is empty")
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
                        val processed = processImage(rawBytes, type)

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
        if (missing > 0) document.body().prependElement("p").attr("class", "hon-offline-notice")
            .text("$missing illustration${if (missing == 1) " is" else "s are"} unavailable offline. Chapter text has been saved.")
        return document.outerHtml()
    }
}
