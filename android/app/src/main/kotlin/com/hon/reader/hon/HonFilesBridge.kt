package com.hon.reader.hon

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class HonFilesBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.hon.reader/files")
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    init { channel.setMethodCallHandler(this) }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "exportBackup") { result.notImplemented(); return }
        if (pending != null) { result.error("BUSY", "A save dialog is already open.", null); return }
        val file = File(call.argument<String>("path") ?: "").canonicalFile
        val root = File(activity.filesDir.parentFile, "app_flutter/staging").canonicalFile
        if (!file.isFile || !file.path.startsWith(root.path + File.separator)) { result.error("INVALID_FILE", "Backup is outside staging storage.", null); return }
        pending = result; source = file
        try { activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); type = "application/zip"; putExtra(Intent.EXTRA_TITLE, file.name)
        }, 18447) } catch (error: Exception) { pending = null; source = null; result.error("SAVE_FAILED", error.message, null) }
    }
    fun handleResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 18447) return false
        val reply = pending ?: return true
        val file = source
        pending = null; source = null
        if (resultCode != Activity.RESULT_OK || data?.data == null || file == null) { reply.success(false); return true }
        val uri = data.data!!
        Thread {
            try {
                activity.contentResolver.openOutputStream(uri, "wt").use { output ->
                    requireNotNull(output) { "Could not open the selected destination." }
                    file.inputStream().use { input -> input.copyTo(output) }
                }
                Handler(Looper.getMainLooper()).post { reply.success(true) }
            } catch (error: Exception) { Handler(Looper.getMainLooper()).post { reply.error("SAVE_FAILED", error.message, null) } }
        }.start()
        return true
    }
    fun cleanup() { pending?.error("CLOSED", "Save dialog was interrupted.", null); pending = null; channel.setMethodCallHandler(null) }
}
