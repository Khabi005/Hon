package com.hon.reader.hon

import com.hon.reader.hon.shosetsu.ShosetsuBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var readerBridge: HonReaderBridge? = null
    private var downloadBridge: HonDownloadManagerBridge? = null
    private var shosetsuBridge: ShosetsuBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readerBridge = HonReaderBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        downloadBridge = HonDownloadManagerBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        shosetsuBridge = ShosetsuBridge(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        readerBridge?.cleanup()
        readerBridge = null
        downloadBridge?.cleanup()
        downloadBridge = null
        shosetsuBridge?.cleanup()
        shosetsuBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
