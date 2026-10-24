package com.hon.reader.hon

import android.app.Activity
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Draws the EPUB reader's menus (reader menu, Contents, Search, Themes &
 * Settings) with Hon's Flutter sheets, over the book, so they match the web
 * novel reader. A small second engine runs `epubMenuMain` with no plugins;
 * the activity stays the owner of the book and its settings and answers the
 * sheets' calls through [host]. Until the engine reports ready, or if it
 * could not start, [show] returns false and the activity uses its native
 * dialogs.
 */
class EpubFlutterMenus(
    private val activity: Activity,
    private val host: (method: String, args: Map<String, Any?>, reply: (Any?) -> Unit) -> Unit,
) {
    companion object {
        private const val TAG = "HonEpubMenus"
        private const val CHANNEL = "com.hon.reader/epub_menus"
        private const val ENTRYPOINT = "epubMenuMain"
        private var group: FlutterEngineGroup? = null
    }

    private var engine: FlutterEngine? = null
    private var view: FlutterView? = null
    private var channel: MethodChannel? = null
    private var activityResumed = true

    var isReady = false
        private set

    val isShowing: Boolean get() = view?.visibility == View.VISIBLE

    /** Called with true when a sheet opens over the book, false when it closes. */
    var onShowingChanged: ((Boolean) -> Unit)? = null

    /** Starts the engine ahead of the first menu, covering [parent]. */
    fun prewarm(parent: ViewGroup) {
        if (engine != null) return
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            val engineGroup = group ?: FlutterEngineGroup(activity.applicationContext).also { group = it }
            val created = engineGroup.createAndRunEngine(
                FlutterEngineGroup.Options(activity)
                    .setDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT))
                    .setAutomaticallyRegisterPlugins(false)
            )
            engine = created
            channel = MethodChannel(created.dartExecutor.binaryMessenger, CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "ready" -> { isReady = true; result.success(null) }
                        "closed" -> { hide(); result.success(null) }
                        else -> {
                            @Suppress("UNCHECKED_CAST")
                            val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                            var replied = false
                            host(call.method, args) { value ->
                                if (!replied) { replied = true; result.success(value) }
                            }
                        }
                    }
                }
            }
            // A see-through texture, so the page stays visible behind a sheet.
            val texture = FlutterTextureView(activity).apply { isOpaque = false }
            val flutterView = FlutterView(activity, texture).apply { visibility = View.GONE }
            parent.addView(
                flutterView,
                FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            )
            flutterView.attachToFlutterEngine(created)
            view = flutterView
            created.lifecycleChannel.appIsPaused()
        } catch (error: Throwable) {
            Log.w(TAG, "Flutter menus unavailable; using native menus", error)
            destroy()
        }
    }

    /** Opens [sheet] with [state]. False when the native dialog should be used. */
    fun show(sheet: String, state: Map<String, Any?>): Boolean {
        val target = view ?: return false
        val messages = channel ?: return false
        if (!isReady) return false
        if (!isShowing) {
            target.visibility = View.VISIBLE
            target.requestFocus()
            if (activityResumed) engine?.lifecycleChannel?.appIsResumed()
            onShowingChanged?.invoke(true)
        }
        messages.invokeMethod("show", mapOf("sheet" to sheet, "state" to state))
        return true
    }

    /** Back closes the top sheet. */
    fun back() {
        channel?.invokeMethod("back", null)
    }

    fun hide() {
        val target = view ?: return
        if (!isShowing) return
        target.visibility = View.GONE
        engine?.lifecycleChannel?.appIsPaused()
        onShowingChanged?.invoke(false)
    }

    fun onResume() {
        activityResumed = true
        if (isShowing) engine?.lifecycleChannel?.appIsResumed()
    }

    fun onPause() {
        activityResumed = false
        engine?.lifecycleChannel?.appIsPaused()
    }

    fun destroy() {
        try {
            view?.let { flutterView ->
                flutterView.detachFromFlutterEngine()
                (flutterView.parent as? ViewGroup)?.removeView(flutterView)
            }
        } catch (error: Throwable) {
            Log.w(TAG, "Could not detach menus", error)
        }
        channel?.setMethodCallHandler(null)
        try { engine?.destroy() } catch (error: Throwable) { Log.w(TAG, "Could not stop menus", error) }
        view = null
        channel = null
        engine = null
        isReady = false
    }
}
