package com.hon.reader.hon

import android.graphics.BitmapFactory
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RealImageCodecRobolectricTest {

    @Test
    fun testRealFixturesWithAndroidImageCodec() {
        val codec = AndroidImageCodec()
        val fixturesDir = File("src/test/resources/fixtures/images")

        val formats = listOf(
            Triple("real_1800.png", "image/png", "png"),
            Triple("real_1800.jpg", "image/jpeg", "jpg"),
            Triple("real_1800.gif", "image/gif", "png"), // resized non-jpeg becomes png
            Triple("real_1800.webp", "image/webp", "png") // resized non-jpeg becomes png
        )

        for ((filename, mime, expectedExt) in formats) {
            val file = File(fixturesDir, filename)
            assertTrue("File exists: ${file.absolutePath}", file.exists())
            val bytes = file.readBytes()

            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
            println("Format $filename: outWidth=${opts.outWidth}, outHeight=${opts.outHeight}")

            val processed = codec.process(bytes, mime)
            println("Processed $filename: width=${processed.width}, mime=${processed.mimeType}")
            val expectedMime = if (mime == "image/jpeg") "image/jpeg" else "image/png"
            assertEquals("MIME must match expected for $filename", expectedMime, processed.mimeType)
            assertEquals("Extension must match expected for $filename", expectedExt, processed.extension)
            assertTrue("Width must be <= 1600px for $filename, was ${processed.width}", processed.width <= 1600)
            assertTrue("Bytes must be non-empty", processed.bytes.isNotEmpty())

            // Assert real output decodes as valid Bitmap and is <= 1600
            val decoded = BitmapFactory.decodeByteArray(processed.bytes, 0, processed.bytes.size)
            assertNotNull("Output must decode to a valid Bitmap for $filename", decoded)
            assertEquals(processed.width, decoded.width)
            assertTrue(decoded.width <= 1600)
            decoded.recycle()
        }
    }
}
