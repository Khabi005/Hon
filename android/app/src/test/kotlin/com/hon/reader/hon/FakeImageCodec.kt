package com.hon.reader.hon

import java.util.Base64

class FakeImageCodec : ImageCodec {
    override fun process(bytes: ByteArray, initialMime: String): ProcessedImage {
        require(bytes.size >= 8) { "Corrupt or invalid image dimensions" }

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
                basePng + byteArrayOf(initialMime.hashCode().toByte())
            }
            return ProcessedImage(scaledBytes, outMime, outExt, 1600, (height.toDouble() * (1600.0 / width)).toInt())
        }

        val ext = when (initialMime) {
            "image/jpeg" -> "jpg"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            else -> "png"
        }
        return ProcessedImage(bytes, initialMime, ext, width, height)
    }

    private fun parseDimensions(bytes: ByteArray, initialMime: String): Pair<Int, Int>? {
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
}
