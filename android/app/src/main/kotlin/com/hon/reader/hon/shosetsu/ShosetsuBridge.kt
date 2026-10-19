package com.hon.reader.hon.shosetsu

import android.app.Activity
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import com.hon.reader.hon.SourceLoginActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import kotlinx.coroutines.SupervisorJob

class ShosetsuBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.hon.reader/shosetsu_native")
    private fun engine(call: MethodCall) = ShosetsuKotlinEngine(SourceHttpClient.create(activity, call.argument<String>("sourceId") ?: ""))
    private fun settings(call: MethodCall): Map<String, Any?> {
        val id = call.argument<String>("sourceId") ?: return emptyMap()
        val json = SourcePreferenceStore.read(activity, id)
        return json.keys().asSequence().associateWith { json.get(it) }
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    init {
        channel.setMethodCallHandler(this)
    }

    fun cleanup() {
        scope.cancel()
        channel.setMethodCallHandler(null)
    }

    private fun allowedHosts(call: MethodCall): Set<String> {
        val list = call.argument<List<*>>("allowedHosts")?.filterIsInstance<String>()
        return list?.toSet() ?: emptySet()
    }

    private fun baseUrl(call: MethodCall): String? {
        return call.argument<String>("baseUrl")?.takeIf { it.isNotBlank() }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setSourcePreferences", "importSourcePreferences", "getSourcePreferences" -> {
                val id = call.argument<String>("sourceId") ?: ""
                val values = call.argument<Map<String, Any?>>("settings") ?: emptyMap()
                if (!Regex("^(ext_[0-9a-f]{64}|gutenberg)$").matches(id) || values.size > 2048) { result.error("INVALID_SETTINGS", "Invalid source preferences", null); return }
                scope.launch(Dispatchers.IO) {
                    try {
                        val value = if (call.method == "setSourcePreferences") JSONObject(values) else SourcePreferenceStore.read(activity, id)
                        if (call.method == "importSourcePreferences") for ((key, item) in values) value.put(key, item)
                        if (call.method != "getSourcePreferences") SourcePreferenceStore.write(activity, id, value)
                        val response = if (call.method == "getSourcePreferences") value.keys().asSequence().associateWith { value.get(it) } else true
                        kotlinx.coroutines.withContext(Dispatchers.Main) { result.success(response) }
                    } catch (error: Exception) {
                        kotlinx.coroutines.withContext(Dispatchers.Main) { result.error("SOURCE_SETTINGS_FAILED", "Could not open saved source settings. ${error.message}", null) }
                    }
                }
            }
            "openSourceWebsite" -> {
                val url = call.argument<String>("url") ?: ""
                val id = call.argument<String>("sourceId") ?: ""
                val uri = android.net.Uri.parse(url)
                if (!Regex("^(ext_[0-9a-f]{64}|gutenberg)$").matches(id) || uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) { result.error("INVALID_URL", "Source website must use HTTPS", null); return }
                activity.startActivity(Intent(activity, SourceLoginActivity::class.java).putExtra("url",url).putExtra("sourceId",id))
                result.success(true)
            }
            "isNativeSupported" -> {
                scope.launch(Dispatchers.IO) {
                    try {
                        engine(call).selfCheck()
                        kotlinx.coroutines.withContext(Dispatchers.Main) { result.success(true) }
                    } catch (error: LinkageError) {
                        kotlinx.coroutines.withContext(Dispatchers.Main) {
                            result.error("SOURCE_ENGINE_UNAVAILABLE", "The source engine could not load. Please update Hon. ${error.message}", null)
                        }
                    } catch (error: Exception) {
                        kotlinx.coroutines.withContext(Dispatchers.Main) {
                            result.error("SOURCE_ENGINE_UNAVAILABLE", "The source engine could not load. Please update Hon. ${error.message}", null)
                        }
                    }
                }
            }
            "validateExtension" -> {
                val script = call.argument<String>("script")
                if (script == null) {
                    result.error("INVALID_ARGUMENT", "script is required", null)
                    return
                }
                scope.launch(Dispatchers.IO) {
                    try {
                        result.success(engine(call).validateExtension(script, allowedHosts(call), baseUrl(call)))
                    } catch (error: LinkageError) {
                        result.error("SOURCE_ENGINE_UNAVAILABLE", "The source engine could not load. Please update Hon. ${error.message}", null)
                    } catch (e: Exception) {
                        result.error("INCOMPATIBLE_EXTENSION", e.message, null)
                    }
                }
            }
            "describeExtension" -> {
                val script = call.argument<String>("script")
                if (script == null) { result.error("INVALID_ARGUMENT", "script is required", null); return }
                scope.launch(Dispatchers.IO) {
                    try { result.success(engine(call).describeExtension(script, settings(call), allowedHosts(call), baseUrl(call))) }
                    catch (error: LinkageError) { result.error("SOURCE_ENGINE_UNAVAILABLE", "The source engine could not load. Please update Hon. ${error.message}", null) }
                    catch (error: Exception) { result.error("SOURCE_INFO_FAILED", error.message, null) }
                }
            }
            "search" -> {
                val script = call.argument<String>("script")
                val query = call.argument<String>("query") ?: ""
                val page = call.argument<Int>("page") ?: 0

                if (script == null) {
                    result.error("INVALID_ARGUMENT", "script is required", null)
                    return
                }

                scope.launch(Dispatchers.IO) {
                    try {
                        val novels = engine(call).search(script, query, page, call.argument<Int>("listing"), settings(call), call.argument<Map<String, Any?>>("filters") ?: emptyMap(), allowedHosts(call), baseUrl(call))
                        result.success(novels)
                    } catch (error: LinkageError) {
                        result.error("SOURCE_ENGINE_UNAVAILABLE", "The source engine could not load. Please update Hon. ${error.message}", null)
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

                scope.launch(Dispatchers.IO) {
                    try {
                        val details = engine(call).parseNovel(script, novelUrl, loadChapters, settings(call), allowedHosts(call), baseUrl(call))
                        result.success(details)
                    } catch (error: LinkageError) {
                        result.error("SOURCE_ENGINE_UNAVAILABLE", "The source engine could not load. Please update Hon. ${error.message}", null)
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

                scope.launch(Dispatchers.IO) {
                    try {
                        val passage = engine(call).getPassage(script, chapterUrl, settings(call), allowedHosts(call), baseUrl(call))
                        result.success(passage)
                    } catch (error: LinkageError) {
                        result.error("SOURCE_ENGINE_UNAVAILABLE", "The source engine could not load. Please update Hon. ${error.message}", null)
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
