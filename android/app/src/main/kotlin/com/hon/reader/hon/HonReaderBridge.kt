package com.hon.reader.hon

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.zip.ZipFile
import android.view.WindowManager

class HonReaderBridge(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.hon.reader/readium_reader")
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        var instance: HonReaderBridge? = null
    }

    private var activePublicationPath: String? = null
    private var activeLocator: String? = null
    private var activeChapterIndex: Int = 0
    private data class PendingOpen(val result: MethodChannel.Result, val timeout: Runnable)
    private val pendingOpens = mutableMapOf<String, PendingOpen>()

    private fun settleOpen(requestId: String, response: Map<String, Any?>) {
        val pending = pendingOpens.remove(requestId) ?: return
        mainHandler.removeCallbacks(pending.timeout)
        pending.result.success(response)
        Log.d("HonReadium", "settled request=$requestId state=${response["errorCode"] ?: if (response["cancelled"] == true) "cancelled" else "ready"}")
    }

    init {
        instance = this
        channel.setMethodCallHandler(this)
    }

    fun cleanup() {
        for (requestId in pendingOpens.keys.toList()) {
            settleOpen(requestId, mapOf("success" to false, "cancelled" to true, "launched" to true))
        }
        if (instance == this) {
            instance = null
        }
        channel.setMethodCallHandler(null)
    }

    fun reportLocator(bookId: String, requestId: String, locatorJson: String, progression: Double) {
        mainHandler.post {
            channel.invokeMethod(
                "onLocatorChanged",
                mapOf(
                    "bookId" to bookId,
                    "requestId" to requestId,
                    "locator" to locatorJson,
                    "progression" to progression,
                    "totalProgression" to progression
                )
            )
        }
    }

    fun reportError(bookId: String, requestId: String, errorCode: String, errorMessage: String) {
        mainHandler.post {
            settleOpen(requestId, mapOf(
                "success" to false, "launched" to true,
                "errorCode" to errorCode, "errorMessage" to errorMessage
            ))
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
            settleOpen(requestId, mapOf("success" to true, "launched" to true))
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

    fun reportClosed(bookId: String, requestId: String, locatorJson: String?, totalProgression: Double?) {
        mainHandler.post {
            settleOpen(requestId, mapOf("success" to false, "cancelled" to true, "launched" to true))
            val payload = mutableMapOf<String, Any?>(
                "bookId" to bookId,
                "requestId" to requestId,
                "locator" to locatorJson
            )
            if (totalProgression != null) {
                payload["totalProgression"] = totalProgression
            }
            channel.invokeMethod("onReaderClosed", payload)
        }
    }

    fun reportPaused(bookId: String, requestId: String, locatorJson: String?, totalProgression: Double?) {
        mainHandler.post {
            val payload = mutableMapOf<String, Any?>(
                "bookId" to bookId,
                "requestId" to requestId,
                "locator" to locatorJson
            )
            if (totalProgression != null) {
                payload["totalProgression"] = totalProgression
            }
            channel.invokeMethod("onReaderPaused", payload)
        }
    }

    fun reportResumed(bookId: String, requestId: String) {
        mainHandler.post {
            channel.invokeMethod(
                "onReaderResumed",
                mapOf("bookId" to bookId, "requestId" to requestId)
            )
        }
    }

    fun reportPreferences(theme: String, scroll: Boolean, fontSize: Double, bookId: String? = null) {
        val typography = try {
            org.json.JSONObject(context.getSharedPreferences("hon_reader_preferences", Context.MODE_PRIVATE).getString("readium_typography", "{}") ?: "{}")
        } catch (_: Exception) { org.json.JSONObject() }
        val values = typography.keys().asSequence().associateWith { typography.opt(it) }
        mainHandler.post {
            val payload = mutableMapOf<String, Any?>(
                "theme" to theme,
                "isScroll" to scroll,
                "fontSize" to fontSize,
                "typography" to values
            )
            if (bookId != null && bookId.isNotEmpty()) {
                payload["bookId"] = bookId
            }
            channel.invokeMethod("onReaderPreferencesChanged", payload)
        }
    }

    fun getBookmarks(bookId: String, done: (List<Map<String, Any?>>) -> Unit) {
        channel.invokeMethod("getReaderBookmarks", mapOf("bookId" to bookId), object : MethodChannel.Result {
            override fun success(result: Any?) {
                @Suppress("UNCHECKED_CAST")
                done((result as? List<*>)?.mapNotNull { it as? Map<String, Any?> } ?: emptyList())
            }
            override fun error(code: String, message: String?, details: Any?) { done(emptyList()) }
            override fun notImplemented() { done(emptyList()) }
        })
    }

    fun toggleBookmark(
        bookId: String,
        chapter: Int,
        title: String,
        locatorJson: String? = null,
        locatorVersion: String? = "readium-v2",
        snippet: String? = null,
        done: (Boolean?) -> Unit
    ) {
        val payload = mutableMapOf<String, Any?>(
            "bookId" to bookId,
            "chapterIndex" to chapter,
            "title" to title,
            "locatorVersion" to locatorVersion
        )
        if (locatorJson != null) payload["locator"] = locatorJson
        if (snippet != null) payload["snippet"] = snippet
        channel.invokeMethod("toggleReaderBookmark", payload, object : MethodChannel.Result {
            override fun success(result: Any?) { done(result as? Boolean) }
            override fun error(code: String, message: String?, details: Any?) { done(null) }
            override fun notImplemented() { done(null) }
        })
    }

    fun getHighlights(bookId: String, done: (List<Map<String, Any?>>) -> Unit) {
        channel.invokeMethod("getReaderHighlights", mapOf("bookId" to bookId), object : MethodChannel.Result {
            override fun success(result: Any?) {
                @Suppress("UNCHECKED_CAST")
                done((result as? List<*>)?.mapNotNull { it as? Map<String, Any?> } ?: emptyList())
            }
            override fun error(code: String, message: String?, details: Any?) { done(emptyList()) }
            override fun notImplemented() { done(emptyList()) }
        })
    }

    fun saveHighlight(highlight: Map<String, Any?>, done: (Boolean?) -> Unit) {
        channel.invokeMethod("saveReaderHighlight", highlight, object : MethodChannel.Result {
            override fun success(result: Any?) { done(result as? Boolean) }
            override fun error(code: String, message: String?, details: Any?) { done(null) }
            override fun notImplemented() { done(null) }
        })
    }

    fun deleteHighlight(id: String, done: (Boolean?) -> Unit) {
        channel.invokeMethod("deleteReaderHighlight", mapOf("id" to id), object : MethodChannel.Result {
            override fun success(result: Any?) { done(result as? Boolean) }
            override fun error(code: String, message: String?, details: Any?) { done(null) }
            override fun notImplemented() { done(null) }
        })
    }

    fun getBookReaderSettings(bookId: String, done: (Map<String, Any?>?) -> Unit) {
        channel.invokeMethod("getBookReaderSettings", mapOf("bookId" to bookId), object : MethodChannel.Result {
            override fun success(result: Any?) {
                @Suppress("UNCHECKED_CAST")
                done(result as? Map<String, Any?>)
            }
            override fun error(code: String, message: String?, details: Any?) { done(null) }
            override fun notImplemented() { done(null) }
        })
    }

    fun saveBookReaderSettings(bookId: String, settings: Map<String, Any?>, done: (Boolean?) -> Unit) {
        channel.invokeMethod("saveBookReaderSettings", mapOf("bookId" to bookId, "settings" to settings), object : MethodChannel.Result {
            override fun success(result: Any?) { done(result as? Boolean) }
            override fun error(code: String, message: String?, details: Any?) { done(null) }
            override fun notImplemented() { done(null) }
        })
    }

    fun resetBookReaderSettings(bookId: String, done: (Boolean?) -> Unit) {
        channel.invokeMethod("resetBookReaderSettings", mapOf("bookId" to bookId), object : MethodChannel.Result {
            override fun success(result: Any?) { done(result as? Boolean) }
            override fun error(code: String, message: String?, details: Any?) { done(null) }
            override fun notImplemented() { done(null) }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setBrightness" -> {
                val brightness = call.argument<Double>("brightness") ?: -1.0
                val activity = context as? android.app.Activity
                if (activity != null) {
                    activity.window.attributes = activity.window.attributes.apply {
                        screenBrightness = if (brightness < 0) {
                            WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        } else {
                            brightness.toFloat().coerceIn(0.05f, 1.0f)
                        }
                    }
                }
                result.success(true)
            }
            "openLink" -> {
                val uri = android.net.Uri.parse(call.argument<String>("url") ?: "")
                if (uri.scheme !in listOf("https", "http", "mailto")) {
                    result.error("UNSUPPORTED_LINK", "Unsupported link", null)
                } else try {
                    context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } catch (error: Exception) {
                    result.error("LINK_FAILED", error.message, null)
                }
            }
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

                    ReadiumReaderActivity.activeInstance?.finish()

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
                    // Complete the Flutter call only when the native navigator is ready,
                    // fails, or is intentionally closed. A Dart timer cannot reliably
                    // distinguish these states while another Activity is foregrounded.
                    val timeout = Runnable {
                        if (pendingOpens.containsKey(requestId)) {
                            ReadiumReaderActivity.activeInstance?.closeIfWaiting(requestId)
                            settleOpen(requestId, mapOf(
                                "success" to false, "launched" to true,
                                "errorCode" to "TIMEOUT",
                                "errorMessage" to "Timed out waiting for Readium reader ready signal (30s)"
                            ))
                        }
                    }
                    pendingOpens[requestId] = PendingOpen(result, timeout)
                    mainHandler.postDelayed(timeout, 30_000L)
                    context.startActivity(intent)
                } catch (e: Exception) {
                    pendingOpens.remove(requestId)?.let { mainHandler.removeCallbacks(it.timeout) }
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
                val isGlass = call.argument<Boolean>("isGlass")
                val typography = call.argument<Map<String, Any?>>("typography")

                // Durably save settings to SharedPreferences so subsequent reader opens use them
                val prefs = context.getSharedPreferences("hon_reader_preferences", Context.MODE_PRIVATE)
                val editor = prefs.edit()
                if (fontSize != null) editor.putFloat("readium_font_size", fontSize.toFloat())
                if (theme != null) editor.putString("readium_theme", theme.lowercase())
                if (isScroll != null) editor.putBoolean("readium_scroll_mode", isScroll)
                if (isGlass != null) editor.putBoolean("is_glass", isGlass)
                if (typography != null) {
                    val merged = try { org.json.JSONObject(prefs.getString("readium_typography", "{}") ?: "{}") } catch (_: Exception) { org.json.JSONObject() }
                    typography.forEach { (key, value) -> merged.put(key, value) }
                    editor.putString("readium_typography", merged.toString())
                }
                editor.apply()

                val active = ReadiumReaderActivity.activeInstance
                if (active != null) {
                    active.applyExternalSettings(fontSize, theme, isScroll, isGlass)
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
            "shareFile" -> {
                val filePath = call.argument<String>("filePath")
                val mimeType = call.argument<String>("mimeType") ?: "application/epub+zip"
                val title = call.argument<String>("title") ?: "Share File"
                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "filePath is required", null)
                    return
                }
                val file = File(filePath)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                    return
                }
                try {
                    val shareFile = try {
                        androidx.core.content.FileProvider.getUriForFile(
                            context,
                            "${context.packageName}.fileprovider",
                            file
                        )
                        file
                    } catch (_: Exception) {
                        val exportCacheDir = File(context.cacheDir, "exports").apply { mkdirs() }
                        val cachedFile = File(exportCacheDir, file.name)
                        file.copyTo(cachedFile, overwrite = true)
                        cachedFile
                    }
                    val uri = androidx.core.content.FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        shareFile
                    )
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    val chooser = Intent.createChooser(shareIntent, title).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(chooser)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e("HonReaderBridge", "Failed to share file: ${e.message}", e)
                    result.error("SHARE_FAILED", e.message ?: "Failed to share file", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }
}
