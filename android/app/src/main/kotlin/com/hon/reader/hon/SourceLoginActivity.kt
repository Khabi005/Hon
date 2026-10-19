package com.hon.reader.hon

import android.app.Activity
import android.os.Bundle
import android.webkit.*
import android.widget.LinearLayout
import android.widget.Button
import android.view.ViewGroup
import android.net.Uri

class SourceLoginActivity : Activity() {
    private var web: WebView? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra("url") ?: return finish()
        val uri = Uri.parse(url)
        if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) return finish()
        val sourceId = intent.getStringExtra("sourceId") ?: return finish()
        getSharedPreferences("hon_source_auth_origins", MODE_PRIVATE).edit().putString(sourceId, url).apply()
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; fitsSystemWindows = true }
        layout.addView(Button(this).apply { text = "Done · ${uri.host}"; setOnClickListener { finish() } }, LinearLayout.LayoutParams(-1,-2))
        web = WebView(this).apply {
            settings.javaScriptEnabled = true; settings.domStorageEnabled = true
            settings.allowFileAccess = false; settings.allowContentAccess = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean = request?.url?.scheme != "https"
            }
            getSharedPreferences("hon_source_auth_origins", MODE_PRIVATE).edit()
                .putString("${sourceId}_user_agent", settings.userAgentString).apply()
            loadUrl(url)
        }
        layout.addView(web, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,0,1f))
        setContentView(layout)
    }
    override fun onPause() { CookieManager.getInstance().flush(); super.onPause() }
    override fun onDestroy() { web?.stopLoading(); web?.destroy(); web = null; super.onDestroy() }
}
