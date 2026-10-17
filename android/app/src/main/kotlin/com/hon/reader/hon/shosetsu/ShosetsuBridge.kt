package com.hon.reader.hon.shosetsu

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class ShosetsuBridge(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.hon.reader/shosetsu_native")
    private val engine = ShosetsuKotlinEngine()
    private val scope = CoroutineScope(Dispatchers.Main)

    init {
        channel.setMethodCallHandler(this)
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isNativeSupported" -> {
                result.success(true)
            }
            "search" -> {
                val script = call.argument<String>("script")
                val query = call.argument<String>("query") ?: ""
                val page = call.argument<Int>("page") ?: 0

                if (script == null) {
                    result.error("INVALID_ARGUMENT", "script is required", null)
                    return
                }

                scope.launch {
                    try {
                        val novels = engine.search(script, query, page)
                        result.success(novels)
                    } catch (e: Exception) {
                        result.error("SEARCH_FAILED", e.message, null)
                    }
                }
            }
            "parseNovel" -> {
                val script = call.argument<String>("script")
                val novelUrl = call.argument<String>("novelUrl")
                val loadChapters = call.argument<Boolean>("loadChapters") ?: true

                if (script == null || novelUrl == null) {
                    result.error("INVALID_ARGUMENT", "script and novelUrl are required", null)
                    return
                }

                scope.launch {
                    try {
                        val details = engine.parseNovel(script, novelUrl, loadChapters)
                        result.success(details)
                    } catch (e: Exception) {
                        result.error("PARSE_FAILED", e.message, null)
                    }
                }
            }
            "getPassage" -> {
                val script = call.argument<String>("script")
                val chapterUrl = call.argument<String>("chapterUrl")

                if (script == null || chapterUrl == null) {
                    result.error("INVALID_ARGUMENT", "script and chapterUrl are required", null)
                    return
                }

                scope.launch {
                    try {
                        val passage = engine.getPassage(script, chapterUrl)
                        result.success(passage)
                    } catch (e: Exception) {
                        result.error("PASSAGE_FAILED", e.message, null)
                    }
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }
}
