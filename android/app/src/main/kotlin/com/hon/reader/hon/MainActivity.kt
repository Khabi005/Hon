package com.hon.reader.hon

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var readerBridge: HonReaderBridge? = null
    private var downloadBridge: HonDownloadManagerBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readerBridge = HonReaderBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        downloadBridge = HonDownloadManagerBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        readerBridge?.cleanup()
        readerBridge = null
        downloadBridge?.cleanup()
        downloadBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
