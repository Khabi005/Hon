package com.hon.reader.hon

import com.hon.reader.hon.shosetsu.ShosetsuBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var filesBridge: HonFilesBridge? = null
    private var readerBridge: HonReaderBridge? = null
    private var downloadBridge: HonDownloadManagerBridge? = null
    private var shosetsuBridge: ShosetsuBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        filesBridge = HonFilesBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        readerBridge = HonReaderBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        downloadBridge = HonDownloadManagerBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        shosetsuBridge = ShosetsuBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (filesBridge?.handleResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        filesBridge?.cleanup(); filesBridge = null
        readerBridge?.cleanup()
        readerBridge = null
        downloadBridge?.cleanup()
        downloadBridge = null
        shosetsuBridge?.cleanup()
        shosetsuBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
