package com.hon.reader.hon

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.zip.ZipFile

class HonReaderBridge(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.hon.reader/readium_reader")
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        var instance: HonReaderBridge? = null
    }

    private var activePublicationPath: String? = null
    private var activeLocator: String? = null
    private var activeChapterIndex: Int = 0

    init {
        instance = this
        channel.setMethodCallHandler(this)
    }

    fun cleanup() {
        if (instance == this) {
            instance = null
        }
        channel.setMethodCallHandler(null)
    }

    fun reportLocator(bookId: String, locatorJson: String, progression: Double) {
        mainHandler.post {
            channel.invokeMethod(
                "onLocatorChanged",
                mapOf(
                    "bookId" to bookId,
                    "locator" to locatorJson,
                    "progression" to progression,
                    "totalProgression" to progression
                )
            )
        }
    }

    fun reportError(bookId: String, requestId: String, errorCode: String, errorMessage: String) {
        mainHandler.post {
            channel.invokeMethod(
                "onReaderError",
                mapOf(
                    "bookId" to bookId,
                    "requestId" to requestId,
                    "code" to errorCode,
                    "message" to errorMessage
                )
            )
        }
    }

    fun reportReady(bookId: String, requestId: String, isForegrounded: Boolean = true) {
        mainHandler.post {
            channel.invokeMethod(
                "onReaderReady",
                mapOf(
                    "bookId" to bookId,
                    "requestId" to requestId,
                    "isForegrounded" to isForegrounded
                )
            )
        }
    }

    fun reportClosed(bookId: String, locatorJson: String?, totalProgression: Double?) {
        mainHandler.post {
            val payload = mutableMapOf<String, Any?>(
                "bookId" to bookId,
                "locator" to locatorJson
            )
            if (totalProgression != null) {
                payload["totalProgression"] = totalProgression
            }
            channel.invokeMethod("onReaderClosed", payload)
        }
    }

    fun reportPaused(bookId: String, locatorJson: String?, totalProgression: Double?) {
        mainHandler.post {
            val payload = mutableMapOf<String, Any?>(
                "bookId" to bookId,
                "locator" to locatorJson
            )
            if (totalProgression != null) {
                payload["totalProgression"] = totalProgression
            }
            channel.invokeMethod("onReaderPaused", payload)
        }
    }

    fun reportResumed(bookId: String) {
        mainHandler.post {
            channel.invokeMethod(
                "onReaderResumed",
                mapOf("bookId" to bookId)
            )
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isPlatformSupported" -> {
                result.success(true)
            }
            "openEpub" -> {
                val filePath = call.argument<String>("filePath")
                val bookId = call.argument<String>("bookId") ?: ""
                val title = call.argument<String>("title") ?: ""
                val initialLocator = call.argument<String>("initialLocator")
                val chapterIndex = call.argument<Int>("chapterIndex") ?: 0
                val requestId = call.argument<String>("requestId") ?: ""

                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "filePath is required", null)
                    return
                }

                val file = File(filePath)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "EPUB file does not exist at $filePath", null)
                    return
                }

                try {
                    // Pre-validate zip/container structure
                    ZipFile(file).use { zip ->
                        val containerEntry = zip.getEntry("META-INF/container.xml")
                        if (containerEntry == null) {
                            result.error("INVALID_EPUB", "Missing META-INF/container.xml in EPUB", null)
                            return
                        }
                    }

                    activePublicationPath = filePath
                    activeLocator = initialLocator
                    activeChapterIndex = chapterIndex

                    val intent = Intent(context, ReadiumReaderActivity::class.java).apply {
                        putExtra("filePath", filePath)
                        putExtra("bookId", bookId)
                        putExtra("title", title)
                        putExtra("initialLocator", initialLocator)
                        putExtra("chapterIndex", chapterIndex)
                        putExtra("requestId", requestId)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(intent)

                    val response = mapOf(
                        "success" to true,
                        "launched" to true,
                        "filePath" to filePath,
                        "initialChapterIndex" to activeChapterIndex,
                        "initialLocator" to activeLocator,
                        "requestId" to requestId,
                        "engine" to "Readium/Android-Native"
                    )
                    result.success(response)
                } catch (e: Exception) {
                    result.error("OPEN_FAILED", "Failed to launch Readium reader: ${e.message}", null)
                }
            }
            "saveLocator" -> {
                val locator = call.argument<String>("locator")
                val chapterIndex = call.argument<Int>("chapterIndex")
                if (locator != null) {
                    activeLocator = locator
                }
                if (chapterIndex != null) {
                    activeChapterIndex = chapterIndex
                }
                result.success(true)
            }
            "applySettings" -> {
                val fontSize = call.argument<Double>("fontSize")
                val theme = call.argument<String>("theme")
                val isScroll = call.argument<Boolean>("isScroll")

                // Durably save settings to SharedPreferences so subsequent reader opens use them
                val prefs = context.getSharedPreferences("hon_reader_preferences", Context.MODE_PRIVATE)
                val editor = prefs.edit()
                if (fontSize != null) editor.putFloat("readium_font_size", fontSize.toFloat())
                if (theme != null) editor.putString("readium_theme", theme.uppercase())
                if (isScroll != null) editor.putBoolean("readium_scroll_mode", isScroll)
                editor.apply()

                val active = ReadiumReaderActivity.activeInstance
                if (active != null) {
                    active.applyExternalSettings(fontSize, theme, isScroll)
                    result.success(mapOf(
                        "applied" to true,
                        "activeReader" to true,
                        "fontSize" to fontSize,
                        "theme" to theme,
                        "isScroll" to isScroll
                    ))
                } else {
                    result.success(mapOf(
                        "applied" to true,
                        "activeReader" to false,
                        "savedDurably" to true,
                        "fontSize" to fontSize,
                        "theme" to theme,
                        "isScroll" to isScroll
                    ))
                }
            }
            "closeSession" -> {
                val finalLocator = activeLocator
                val finalChapter = activeChapterIndex
                activePublicationPath = null
                result.success(mapOf(
                    "closed" to true,
                    "finalLocator" to finalLocator,
                    "finalChapterIndex" to finalChapter
                ))
            }
            else -> {
                result.notImplemented()
            }
        }
    }
}
