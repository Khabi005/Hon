package com.hon.reader.hon

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.Window
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.input.DragEvent
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.KeyEvent
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.navigator.preferences.Theme
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.epub.EpubParser
import java.io.File
import java.util.concurrent.ConcurrentHashMap

object PublicationRepository {
    private val cache = ConcurrentHashMap<String, Publication>()
    fun get(path: String): Publication? = cache[path]
    fun put(path: String, pub: Publication) { cache[path] = pub }
    fun remove(path: String): Publication? = cache.remove(path)
}

class ReadiumReaderActivity : AppCompatActivity() {

    companion object {
        var activeInstance: ReadiumReaderActivity? = null
        private const val PREFS_NAME = "hon_reader_preferences"
        private const val KEY_FONT_SIZE = "readium_font_size"
        private const val KEY_THEME = "readium_theme"
        private const val KEY_SCROLL = "readium_scroll_mode"
    }

    private var publication: Publication? = null
    private var navigator: EpubNavigatorFragment? = null
    private var currentLocator: Locator? = null
    private var bookId: String = ""
    private var bookTitle: String = ""
    private var filePath: String? = null
    private var requestId: String = ""

    // Appearance State (durable across sessions)
    private var currentFontSize: Double = 1.0
    private var currentTheme: Theme = Theme.DARK
    private var isScrollMode: Boolean = false

    private lateinit var rootLayout: LinearLayout
    private lateinit var topBar: LinearLayout
    private lateinit var bottomBar: LinearLayout
    private lateinit var progressText: TextView
    private var areControlsVisible: Boolean = true
    private var isClosedReported: Boolean = false
    private var loadingIndicator: ProgressBar? = null

    private fun getThemeBackgroundColor(): Int {
        return when (currentTheme) {
            Theme.LIGHT -> Color.WHITE
            Theme.SEPIA -> Color.parseColor("#F4ECD8")
            Theme.DARK -> Color.parseColor("#1C1C1E")
        }
    }

    private fun updateSystemBars() {
        val insetsController = WindowInsetsControllerCompat(window, window.decorView)
        val isLightPage = (currentTheme == Theme.LIGHT || currentTheme == Theme.SEPIA)

        if (areControlsVisible) {
            window.statusBarColor = Color.parseColor("#EE1C1C1E")
            window.navigationBarColor = Color.parseColor("#EE1C1C1E")
            insetsController.isAppearanceLightStatusBars = false
            insetsController.isAppearanceLightNavigationBars = false
        } else {
            val pageBgColor = getThemeBackgroundColor()
            window.statusBarColor = pageBgColor
            window.navigationBarColor = pageBgColor
            insetsController.isAppearanceLightStatusBars = isLightPage
            insetsController.isAppearanceLightNavigationBars = isLightPage
        }
    }

    private fun resolveInitialLocator(
        pub: Publication,
        locatorJson: String?,
        chapterIndex: Int
    ): Locator? {
        val parsed = locatorJson?.takeIf { it.trim().startsWith("{") }?.let {
            try {
                Locator.fromJSON(JSONObject(it))
            } catch (_: Exception) {
                null
            }
        }
        if (parsed != null) return parsed

        return if (chapterIndex in 0 until pub.readingOrder.size) {
            pub.locatorFromLink(pub.readingOrder[chapterIndex])
        } else {
            null
        }
    }

    private fun setupFragment(fragment: EpubNavigatorFragment, pub: Publication) {
        navigator = fragment

        fragment.addInputListener(object : InputListener {
            override fun onTap(event: TapEvent): Boolean {
                toggleControls()
                return true
            }
            override fun onDrag(event: DragEvent): Boolean = false
            override fun onKey(event: KeyEvent): Boolean = false
        })

        applyPreferences()
        observeLocator(fragment, pub)
    }

    private fun hideLoadingIndicator() {
        runOnUiThread {
            loadingIndicator?.visibility = View.GONE
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        activeInstance = this

        // 1. Extract session parameters
        filePath = savedInstanceState?.getString("filePath") ?: intent.getStringExtra("filePath")
        bookId = savedInstanceState?.getString("bookId") ?: intent.getStringExtra("bookId") ?: ""
        bookTitle = savedInstanceState?.getString("title") ?: intent.getStringExtra("title") ?: "Hon Reader"
        requestId = savedInstanceState?.getString("requestId") ?: intent.getStringExtra("requestId") ?: ""
        val initialLocatorJson = savedInstanceState?.getString("savedLocator") ?: intent.getStringExtra("initialLocator")
        val initialChapterIndex = intent.getIntExtra("chapterIndex", 0)

        // 2. Load durable appearance settings from SharedPreferences
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        currentFontSize = savedInstanceState?.getDouble("fontSize", 1.0)
            ?: prefs.getFloat(KEY_FONT_SIZE, 1.0f).toDouble()
        isScrollMode = savedInstanceState?.getBoolean("isScroll", false)
            ?: prefs.getBoolean(KEY_SCROLL, false)
        val savedThemeStr = savedInstanceState?.getString("theme")
            ?: prefs.getString(KEY_THEME, "DARK")
        savedThemeStr?.let {
            try { currentTheme = Theme.valueOf(it) } catch (_: Exception) {}
        }

        val path = filePath
        if (path == null) {
            super.onCreate(null)
            HonReaderBridge.instance?.reportError(bookId, requestId, "INVALID_PATH", "EPUB file path is null")
            finish()
            return
        }

        val file = File(path)
        if (!file.exists()) {
            super.onCreate(null)
            HonReaderBridge.instance?.reportError(bookId, requestId, "FILE_NOT_FOUND", "EPUB file does not exist: $path")
            finish()
            return
        }

        // Fast restoration path: Configuration change where publication is still alive in memory
        val cachedPub = PublicationRepository.get(path)
        if (savedInstanceState != null && cachedPub != null) {
            publication = cachedPub
            val initialLocator = resolveInitialLocator(cachedPub, initialLocatorJson, initialChapterIndex)
            val factory = EpubNavigatorFactory(cachedPub)
            supportFragmentManager.fragmentFactory = factory.createFragmentFactory(
                initialLocator = initialLocator
            )
            super.onCreate(savedInstanceState)
            buildReaderLayout(showLoading = false)

            val fragment = supportFragmentManager.findFragmentById(R.id.readium_fragment_container) as? EpubNavigatorFragment
            if (fragment != null) {
                setupFragment(fragment, cachedPub)
                HonReaderBridge.instance?.reportReady(bookId, requestId)
            }
            return
        }

        // Normal launch OR process restoration without cached publication:
        // Do NOT block UI with runBlocking! Call super.onCreate(null) immediately and load asynchronously!
        super.onCreate(null)
        buildReaderLayout(showLoading = true)

        lifecycleScope.launch {
            val pub = withContext(Dispatchers.IO) {
                try {
                    val assetRetriever = AssetRetriever(contentResolver, DefaultHttpClient())
                    val assetTry = assetRetriever.retrieve(file)
                    val asset = assetTry.getOrNull() ?: return@withContext null

                    val opener = PublicationOpener(EpubParser())
                    val pubTry = opener.open(asset, allowUserInteraction = false)
                    pubTry.getOrNull()
                } catch (e: Exception) {
                    null
                }
            }

            if (pub == null) {
                HonReaderBridge.instance?.reportError(
                    bookId,
                    requestId,
                    "PARSE_ERROR",
                    "Corrupt or unreadable EPUB publication"
                )
                finish()
                return@launch
            }

            publication = pub
            PublicationRepository.put(path, pub)

            val initialLocator = resolveInitialLocator(pub, initialLocatorJson, initialChapterIndex)
            val factory = EpubNavigatorFactory(pub)
            supportFragmentManager.fragmentFactory = factory.createFragmentFactory(
                initialLocator = initialLocator
            )

            hideLoadingIndicator()

            val fragment = supportFragmentManager.fragmentFactory.instantiate(
                classLoader,
                EpubNavigatorFragment::class.java.name
            ) as EpubNavigatorFragment

            supportFragmentManager.beginTransaction()
                .replace(R.id.readium_fragment_container, fragment)
                .commitNow()

            setupFragment(fragment, pub)
            HonReaderBridge.instance?.reportReady(bookId, requestId)
        }
    }

    private fun buildReaderLayout(showLoading: Boolean = false) {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(getThemeBackgroundColor())
        }
        rootLayout = root

        // 1. Top Bar
        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.parseColor("#EE1C1C1E"))
            setPadding(24, 48, 24, 20)

            val backBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "✕"
                textSize = 20f
                setTextColor(Color.WHITE)
                setPadding(16, 16, 24, 16)
                setOnClickListener { finish() }
            }
            addView(backBtn)

            val titleView = TextView(this@ReadiumReaderActivity).apply {
                text = bookTitle
                textSize = 16f
                setTextColor(Color.WHITE)
                paint.isFakeBoldText = true
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            addView(
                titleView,
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            )

            // Table of Contents button
            val tocBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "≡"
                textSize = 24f
                setTextColor(Color.WHITE)
                setPadding(20, 16, 20, 16)
                setOnClickListener { showTocDialog() }
            }
            addView(tocBtn)

            // Appearance settings button
            val aaBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "Aa"
                textSize = 17f
                setTextColor(Color.WHITE)
                paint.isFakeBoldText = true
                setPadding(20, 16, 16, 16)
                setOnClickListener { showAppearanceDialog() }
            }
            addView(aaBtn)
        }

        ViewCompat.setOnApplyWindowInsetsListener(topBar) { v, insets ->
            val statusBarTop = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top
            v.setPadding(24, statusBarTop + 16, 24, 16)
            insets
        }

        root.addView(
            topBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        // 2. Reading Fragment Container (takes all middle space, never obscured by bars!)
        val container = FrameLayout(this).apply {
            id = R.id.readium_fragment_container
        }

        if (showLoading) {
            val spinner = ProgressBar(this).apply {
                isIndeterminate = true
            }
            loadingIndicator = spinner
            val spinnerParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
            container.addView(spinner, spinnerParams)
        }

        root.addView(
            container,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1.0f
            )
        )

        // 3. Bottom Bar
        bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.parseColor("#EE1C1C1E"))
            setPadding(24, 20, 24, 48)

            val prevBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "❮ Prev"
                textSize = 13f
                setTextColor(Color.parseColor("#0A84FF"))
                setPadding(16, 12, 24, 12)
                setOnClickListener { navigator?.goBackward(animated = true) }
            }
            addView(prevBtn)

            progressText = TextView(this@ReadiumReaderActivity).apply {
                text = "Reading"
                textSize = 13f
                gravity = Gravity.CENTER
                setTextColor(Color.parseColor("#A0A0A5"))
            }
            addView(
                progressText,
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            )

            val nextBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "Next ❯"
                textSize = 13f
                setTextColor(Color.parseColor("#0A84FF"))
                setPadding(24, 12, 16, 12)
                setOnClickListener { navigator?.goForward(animated = true) }
            }
            addView(nextBtn)
        }

        ViewCompat.setOnApplyWindowInsetsListener(bottomBar) { v, insets ->
            val navBarBottom = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
            v.setPadding(24, 16, 24, navBarBottom + 16)
            insets
        }

        root.addView(
            bottomBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        setContentView(root)
        updateSystemBars()
    }

    private fun observeLocator(fragment: EpubNavigatorFragment, pub: Publication) {
        lifecycleScope.launch {
            fragment.currentLocator.collectLatest { loc ->
                currentLocator = loc
                val totalProg = computeTotalProgression(loc)
                val pct = (totalProg * 100).toInt()
                val chapterTitle = loc.title ?: ""

                runOnUiThread {
                    progressText.text = if (chapterTitle.isNotEmpty()) {
                        "$pct% • $chapterTitle"
                    } else {
                        "$pct% Completed"
                    }
                }

                HonReaderBridge.instance?.reportLocator(
                    bookId,
                    loc.toJSON().toString(),
                    totalProg
                )
            }
        }
    }

    private fun computeTotalProgression(loc: Locator?): Double {
        if (loc == null) return 0.0
        val total = loc.locations.totalProgression
        if (total != null) {
            return total.coerceIn(0.0, 1.0)
        }
        val pub = publication
        if (pub != null && pub.readingOrder.isNotEmpty()) {
            val resourceIndex = pub.readingOrder.indexOfFirst { it.url() == loc.href }.takeIf { it >= 0 } ?: 0
            val chapterProg = loc.locations.progression ?: 0.0
            return ((resourceIndex + chapterProg) / pub.readingOrder.size.toDouble()).coerceIn(0.0, 1.0)
        }
        return (loc.locations.progression ?: 0.0).coerceIn(0.0, 1.0)
    }

    private fun toggleControls() {
        areControlsVisible = !areControlsVisible
        val visibility = if (areControlsVisible) View.VISIBLE else View.GONE
        topBar.visibility = visibility
        bottomBar.visibility = visibility
        updateSystemBars()
    }

    private fun saveDurablePreferences() {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putFloat(KEY_FONT_SIZE, currentFontSize.toFloat())
            .putString(KEY_THEME, currentTheme.name)
            .putBoolean(KEY_SCROLL, isScrollMode)
            .apply()
    }

    fun applyExternalSettings(fontSize: Double?, themeStr: String?, isScroll: Boolean?) {
        if (fontSize != null) currentFontSize = fontSize
        if (themeStr != null) {
            currentTheme = when (themeStr.lowercase()) {
                "light" -> Theme.LIGHT
                "sepia" -> Theme.SEPIA
                else -> Theme.DARK
            }
        }
        if (isScroll != null) isScrollMode = isScroll

        saveDurablePreferences()

        runOnUiThread {
            applyPreferences()
        }
    }

    private fun applyPreferences() {
        rootLayout.setBackgroundColor(getThemeBackgroundColor())
        updateSystemBars()
        navigator?.submitPreferences(
            EpubPreferences(
                fontSize = currentFontSize,
                theme = currentTheme,
                scroll = isScrollMode
            )
        )
    }

    // Nested Table of Contents Model & Tree Flattening
    data class TocEntry(val title: String, val link: Link, val depth: Int)

    private fun flattenToc(links: List<Link>, depth: Int = 0): List<TocEntry> {
        val items = mutableListOf<TocEntry>()
        for (link in links) {
            val title = link.title?.takeIf { it.isNotBlank() } ?: (link.url().path?.substringAfterLast('/') ?: "Chapter")
            items.add(TocEntry(title, link, depth))
            if (link.children.isNotEmpty()) {
                items.addAll(flattenToc(link.children, depth + 1))
            }
        }
        return items
    }

    private fun showTocDialog() {
        val pub = publication ?: return
        val toc = pub.tableOfContents
        if (toc.isEmpty()) {
            Toast.makeText(this, "No Table of Contents available", Toast.LENGTH_SHORT).show()
            return
        }

        val allItems = flattenToc(toc)
        val dialog = Dialog(this)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1C1C1E"))
            setPadding(32, 32, 32, 32)
        }

        val title = TextView(this).apply {
            text = "Table of Contents"
            textSize = 18f
            setTextColor(Color.WHITE)
            paint.isFakeBoldText = true
            setPadding(16, 16, 16, 24)
        }
        layout.addView(title)

        val scrollView = ScrollView(this)
        val listContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        for (item in allItems) {
            val indent = "    ".repeat(item.depth)
            val chapterItem = TextView(this).apply {
                text = "$indent${item.title}"
                textSize = if (item.depth == 0) 15f else 14f
                setTextColor(if (item.depth == 0) Color.parseColor("#E5E5EA") else Color.parseColor("#A0A0A5"))
                setPadding(16 + (item.depth * 24), 20, 16, 20)
                setOnClickListener {
                    lifecycleScope.launch {
                        navigator?.go(item.link, animated = true)
                    }
                    dialog.dismiss()
                }
            }
            val divider = View(this).apply {
                setBackgroundColor(Color.parseColor("#2C2C2E"))
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1)
            }
            listContainer.addView(chapterItem)
            listContainer.addView(divider)
        }

        scrollView.addView(listContainer)
        layout.addView(scrollView, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 800))

        dialog.setContentView(layout)
        dialog.window?.setLayout(
            (resources.displayMetrics.widthPixels * 0.9).toInt(),
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        dialog.show()
    }

    private fun showAppearanceDialog() {
        val dialog = Dialog(this)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1C1C1E"))
            setPadding(32, 32, 32, 32)
        }

        val sheetTitle = TextView(this).apply {
            text = "Appearance & Text"
            textSize = 18f
            setTextColor(Color.WHITE)
            paint.isFakeBoldText = true
            setPadding(16, 16, 16, 24)
        }
        layout.addView(sheetTitle)

        // Font Size Row
        val sizeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(16, 16, 16, 16)
            setBackgroundColor(Color.parseColor("#2C2C2E"))
        }

        val sizeLabel = TextView(this).apply {
            text = "Font Size: ${(currentFontSize * 100).toInt()}%"
            textSize = 15f
            setTextColor(Color.WHITE)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }

        val minusBtn = TextView(this).apply {
            text = "  A-  "
            textSize = 16f
            setTextColor(Color.WHITE)
            setPadding(16, 16, 16, 16)
            setOnClickListener {
                if (currentFontSize > 0.6) {
                    currentFontSize -= 0.1
                    sizeLabel.text = "Font Size: ${(currentFontSize * 100).toInt()}%"
                    saveDurablePreferences()
                    applyPreferences()
                }
            }
        }

        val plusBtn = TextView(this).apply {
            text = "  A+  "
            textSize = 16f
            setTextColor(Color.WHITE)
            setPadding(16, 16, 16, 16)
            setOnClickListener {
                if (currentFontSize < 2.5) {
                    currentFontSize += 0.1
                    sizeLabel.text = "Font Size: ${(currentFontSize * 100).toInt()}%"
                    saveDurablePreferences()
                    applyPreferences()
                }
            }
        }

        sizeRow.addView(sizeLabel)
        sizeRow.addView(minusBtn)
        sizeRow.addView(plusBtn)
        layout.addView(sizeRow)

        // Theme Selection
        val themeLabel = TextView(this).apply {
            text = "Theme"
            textSize = 14f
            setTextColor(Color.parseColor("#A0A0A5"))
            setPadding(16, 24, 16, 12)
        }
        layout.addView(themeLabel)

        val themeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        fun makeThemeChip(name: String, theme: Theme, bg: Int, textCol: Int): TextView {
            return TextView(this).apply {
                text = name
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(textCol)
                setBackgroundColor(bg)
                setPadding(32, 24, 32, 24)
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    setMargins(8, 0, 8, 0)
                }
                setOnClickListener {
                    currentTheme = theme
                    saveDurablePreferences()
                    applyPreferences()
                    dialog.dismiss()
                }
            }
        }

        themeRow.addView(makeThemeChip("Dark", Theme.DARK, Color.parseColor("#2C2C2E"), Color.WHITE))
        themeRow.addView(makeThemeChip("Sepia", Theme.SEPIA, Color.parseColor("#F4ECD8"), Color.parseColor("#5F4B32")))
        themeRow.addView(makeThemeChip("Light", Theme.LIGHT, Color.WHITE, Color.BLACK))
        layout.addView(themeRow)

        // Reading Navigation Mode (Paged vs Scroll)
        val layoutLabel = TextView(this).apply {
            text = "Navigation Mode"
            textSize = 14f
            setTextColor(Color.parseColor("#A0A0A5"))
            setPadding(16, 24, 16, 12)
        }
        layout.addView(layoutLabel)

        val modeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }

        val pagedBtn = TextView(this).apply {
            text = "Paged (Reflow)"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(if (!isScrollMode) Color.WHITE else Color.parseColor("#A0A0A5"))
            setBackgroundColor(if (!isScrollMode) Color.parseColor("#0A84FF") else Color.parseColor("#2C2C2E"))
            setPadding(24, 20, 24, 20)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins(8, 0, 8, 0)
            }
            setOnClickListener {
                isScrollMode = false
                saveDurablePreferences()
                applyPreferences()
                dialog.dismiss()
            }
        }

        val scrollBtn = TextView(this).apply {
            text = "Continuous Scroll"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(if (isScrollMode) Color.WHITE else Color.parseColor("#A0A0A5"))
            setBackgroundColor(if (isScrollMode) Color.parseColor("#0A84FF") else Color.parseColor("#2C2C2E"))
            setPadding(24, 20, 24, 20)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins(8, 0, 8, 0)
            }
            setOnClickListener {
                isScrollMode = true
                saveDurablePreferences()
                applyPreferences()
                dialog.dismiss()
            }
        }

        modeRow.addView(pagedBtn)
        modeRow.addView(scrollBtn)
        layout.addView(modeRow)

        dialog.setContentView(layout)
        dialog.window?.setLayout(
            (resources.displayMetrics.widthPixels * 0.9).toInt(),
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        dialog.show()
    }

    override fun onResume() {
        super.onResume()
        activeInstance = this
        updateSystemBars()
        if (publication != null && currentLocator != null) {
            HonReaderBridge.instance?.reportResumed(bookId)
        }
    }

    override fun onPause() {
        super.onPause()
        if (activeInstance == this) {
            activeInstance = null
        }
        val loc = currentLocator
        if (loc != null) {
            val totalProg = computeTotalProgression(loc)
            HonReaderBridge.instance?.reportPaused(
                bookId,
                loc.toJSON().toString(),
                totalProg
            )
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("filePath", filePath)
        outState.putString("bookId", bookId)
        outState.putString("title", bookTitle)
        outState.putString("requestId", requestId)
        outState.putString("savedLocator", currentLocator?.toJSON()?.toString())
        outState.putDouble("fontSize", currentFontSize)
        outState.putString("theme", currentTheme.name)
        outState.putBoolean("isScroll", isScrollMode)
    }

    private fun notifyReaderClosed() {
        if (isClosedReported) return
        isClosedReported = true
        val loc = currentLocator
        val locJson = loc?.toJSON()?.toString()
        val totalProg = if (loc != null) computeTotalProgression(loc) else null
        HonReaderBridge.instance?.reportClosed(
            bookId,
            locJson,
            totalProg
        )
    }

    override fun finish() {
        notifyReaderClosed()
        super.finish()
    }

    override fun onDestroy() {
        notifyReaderClosed()
        if (activeInstance == this) {
            activeInstance = null
        }
        if (isFinishing) {
            filePath?.let { PublicationRepository.remove(it) }
            try {
                publication?.close()
            } catch (_: Exception) {}
            publication = null
        }
        navigator = null
        super.onDestroy()
    }
}
