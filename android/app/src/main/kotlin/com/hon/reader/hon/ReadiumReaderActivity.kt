package com.hon.reader.hon

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
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
    private lateinit var titleView: TextView
    private lateinit var backBtn: TextView
    private lateinit var tocBtn: TextView
    private lateinit var aaBtn: TextView
    private lateinit var prevBtn: TextView
    private lateinit var nextBtn: TextView
    private lateinit var progressPill: LinearLayout
    private lateinit var progressText: TextView
    private var areControlsVisible: Boolean = true
    private var isClosedReported: Boolean = false
    private var loadingIndicator: ProgressBar? = null

    // Apple Books Color Palette
    private fun getThemeBackgroundColor(): Int {
        return when (currentTheme) {
            Theme.LIGHT -> Color.WHITE
            Theme.SEPIA -> Color.parseColor("#F4ECD8")
            Theme.DARK -> Color.parseColor("#1C1C1E")
        }
    }

    private fun getBarBackgroundColor(): Int {
        return when (currentTheme) {
            Theme.LIGHT -> Color.parseColor("#F8F8F9")
            Theme.SEPIA -> Color.parseColor("#EFE6D0")
            Theme.DARK -> Color.parseColor("#1C1C1E")
        }
    }

    private fun getPrimaryTextColor(): Int {
        return when (currentTheme) {
            Theme.LIGHT -> Color.parseColor("#1C1C1E")
            Theme.SEPIA -> Color.parseColor("#5F4B32")
            Theme.DARK -> Color.WHITE
        }
    }

    private fun getSecondaryTextColor(): Int {
        return when (currentTheme) {
            Theme.LIGHT -> Color.parseColor("#8E8E93")
            Theme.SEPIA -> Color.parseColor("#8C775D")
            Theme.DARK -> Color.parseColor("#A0A0A5")
        }
    }

    private fun getPillBackgroundColor(): Int {
        return when (currentTheme) {
            Theme.LIGHT -> Color.parseColor("#EBEBEF")
            Theme.SEPIA -> Color.parseColor("#E4DAC2")
            Theme.DARK -> Color.parseColor("#2C2C2E")
        }
    }

    private fun getAccentColor(): Int {
        return when (currentTheme) {
            Theme.LIGHT -> Color.parseColor("#007AFF")
            Theme.SEPIA -> Color.parseColor("#B25E00")
            Theme.DARK -> Color.parseColor("#0A84FF")
        }
    }

    private fun getDividerColor(): Int {
        return when (currentTheme) {
            Theme.LIGHT -> Color.parseColor("#E5E5EA")
            Theme.SEPIA -> Color.parseColor("#DED5BF")
            Theme.DARK -> Color.parseColor("#2C2C2E")
        }
    }

    private fun makeCardDrawable(
        bgColor: Int,
        cornerRadiusDp: Float,
        strokeColor: Int? = null,
        strokeWidthDp: Int = 0
    ): GradientDrawable {
        val density = resources.displayMetrics.density
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = cornerRadiusDp * density
            setColor(bgColor)
            if (strokeColor != null && strokeWidthDp > 0) {
                setStroke((strokeWidthDp * density).toInt(), strokeColor)
            }
        }
    }

    private fun updateSystemBars() {
        val insetsController = WindowInsetsControllerCompat(window, window.decorView)
        val isLightPage = (currentTheme == Theme.LIGHT || currentTheme == Theme.SEPIA)

        if (areControlsVisible) {
            val barBgColor = getBarBackgroundColor()
            window.statusBarColor = barBgColor
            window.navigationBarColor = barBgColor
            insetsController.isAppearanceLightStatusBars = isLightPage
            insetsController.isAppearanceLightNavigationBars = isLightPage
        } else {
            val pageBgColor = getThemeBackgroundColor()
            window.statusBarColor = pageBgColor
            window.navigationBarColor = pageBgColor
            insetsController.isAppearanceLightStatusBars = isLightPage
            insetsController.isAppearanceLightNavigationBars = isLightPage
        }
    }

    private fun updateThemeStyling() {
        val pageBg = getThemeBackgroundColor()
        val barBg = getBarBackgroundColor()
        val primaryText = getPrimaryTextColor()
        val secondaryText = getSecondaryTextColor()
        val pillBg = getPillBackgroundColor()
        val accent = getAccentColor()

        rootLayout.setBackgroundColor(pageBg)
        topBar.setBackgroundColor(barBg)
        bottomBar.setBackgroundColor(barBg)

        titleView.setTextColor(primaryText)
        backBtn.setTextColor(primaryText)
        backBtn.background = makeCardDrawable(pillBg, 18f)

        tocBtn.setTextColor(primaryText)
        tocBtn.background = makeCardDrawable(pillBg, 18f)

        aaBtn.setTextColor(primaryText)
        aaBtn.background = makeCardDrawable(pillBg, 18f)

        prevBtn.setTextColor(accent)
        nextBtn.setTextColor(accent)

        progressPill.background = makeCardDrawable(pillBg, 16f)
        progressText.setTextColor(secondaryText)

        updateSystemBars()
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
                val isFg = lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)
                HonReaderBridge.instance?.reportReady(bookId, requestId, isFg)
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
            val isFg = lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)
            HonReaderBridge.instance?.reportReady(bookId, requestId, isFg)
        }
    }

    private fun buildReaderLayout(showLoading: Boolean = false) {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(getThemeBackgroundColor())
        }
        rootLayout = root

        val density = resources.displayMetrics.density

        // 1. Top Bar (Classic Apple Books Header)
        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(getBarBackgroundColor())
            setPadding((16 * density).toInt(), (36 * density).toInt(), (16 * density).toInt(), (12 * density).toInt())

            backBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "✕"
                textSize = 15f
                gravity = Gravity.CENTER
                setTextColor(getPrimaryTextColor())
                background = makeCardDrawable(getPillBackgroundColor(), 18f)
                val size = (36 * density).toInt()
                layoutParams = LinearLayout.LayoutParams(size, size).apply {
                    setMargins(0, 0, (12 * density).toInt(), 0)
                }
                setOnClickListener { finish() }
            }
            addView(backBtn)

            titleView = TextView(this@ReadiumReaderActivity).apply {
                text = bookTitle
                textSize = 15f
                setTextColor(getPrimaryTextColor())
                paint.isFakeBoldText = true
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            addView(
                titleView,
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            )

            // Table of Contents button (Apple Books pill)
            tocBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "≡"
                textSize = 18f
                gravity = Gravity.CENTER
                setTextColor(getPrimaryTextColor())
                background = makeCardDrawable(getPillBackgroundColor(), 18f)
                val size = (36 * density).toInt()
                layoutParams = LinearLayout.LayoutParams(size, size).apply {
                    setMargins((8 * density).toInt(), 0, (6 * density).toInt(), 0)
                }
                setOnClickListener { showTocDialog() }
            }
            addView(tocBtn)

            // Appearance settings button (Apple Books Aa pill)
            aaBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "Aa"
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(getPrimaryTextColor())
                paint.isFakeBoldText = true
                background = makeCardDrawable(getPillBackgroundColor(), 18f)
                val size = (36 * density).toInt()
                layoutParams = LinearLayout.LayoutParams(size, size).apply {
                    setMargins((6 * density).toInt(), 0, 0, 0)
                }
                setOnClickListener { showAppearanceDialog() }
            }
            addView(aaBtn)
        }

        ViewCompat.setOnApplyWindowInsetsListener(topBar) { v, insets ->
            val statusBarTop = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top
            v.setPadding((16 * density).toInt(), statusBarTop + (8 * density).toInt(), (16 * density).toInt(), (12 * density).toInt())
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

        // 3. Bottom Bar (Classic Apple Books Capsule Scrubber)
        bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(getBarBackgroundColor())
            setPadding((16 * density).toInt(), (12 * density).toInt(), (16 * density).toInt(), (24 * density).toInt())

            prevBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "❮ Prev"
                textSize = 13f
                setTextColor(getAccentColor())
                paint.isFakeBoldText = true
                setPadding((12 * density).toInt(), (8 * density).toInt(), (12 * density).toInt(), (8 * density).toInt())
                setOnClickListener { navigator?.goBackward(animated = true) }
            }
            addView(prevBtn)

            progressPill = LinearLayout(this@ReadiumReaderActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                background = makeCardDrawable(getPillBackgroundColor(), 16f)
                setPadding((14 * density).toInt(), (8 * density).toInt(), (14 * density).toInt(), (8 * density).toInt())

                progressText = TextView(this@ReadiumReaderActivity).apply {
                    text = "Reading"
                    textSize = 12f
                    gravity = Gravity.CENTER
                    setTextColor(getSecondaryTextColor())
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }
                addView(progressText)
            }
            addView(
                progressPill,
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    setMargins((8 * density).toInt(), 0, (8 * density).toInt(), 0)
                }
            )

            nextBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "Next ❯"
                textSize = 13f
                setTextColor(getAccentColor())
                paint.isFakeBoldText = true
                setPadding((12 * density).toInt(), (8 * density).toInt(), (12 * density).toInt(), (8 * density).toInt())
                setOnClickListener { navigator?.goForward(animated = true) }
            }
            addView(nextBtn)
        }

        ViewCompat.setOnApplyWindowInsetsListener(bottomBar) { v, insets ->
            val navBarBottom = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
            v.setPadding((16 * density).toInt(), (10 * density).toInt(), (16 * density).toInt(), navBarBottom + (10 * density).toInt())
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
        updateThemeStyling()
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
        updateThemeStyling()
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

        val density = resources.displayMetrics.density
        val cardBg = getBarBackgroundColor()
        val primaryText = getPrimaryTextColor()
        val secondaryText = getSecondaryTextColor()
        val dividerColor = getDividerColor()
        val accent = getAccentColor()

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = makeCardDrawable(cardBg, 16f, dividerColor, 1)
            setPadding((20 * density).toInt(), (20 * density).toInt(), (20 * density).toInt(), (20 * density).toInt())
        }

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((4 * density).toInt(), 0, (4 * density).toInt(), (16 * density).toInt())
        }

        val title = TextView(this).apply {
            text = "Table of Contents"
            textSize = 17f
            setTextColor(primaryText)
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        headerRow.addView(title)

        val closeBtn = TextView(this).apply {
            text = "✕"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(secondaryText)
            background = makeCardDrawable(getPillBackgroundColor(), 14f)
            val size = (28 * density).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size)
            setOnClickListener { dialog.dismiss() }
        }
        headerRow.addView(closeBtn)
        layout.addView(headerRow)

        val scrollView = ScrollView(this)
        val listContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        val currentHref = currentLocator?.href?.toString()

        for (item in allItems) {
            val isCurrent = currentHref != null && item.link.url().toString().contains(currentHref)
            val indent = (item.depth * 18 * density).toInt()

            val chapterItem = TextView(this).apply {
                text = item.title
                textSize = if (item.depth == 0) 14f else 13.5f
                setTextColor(if (isCurrent) accent else (if (item.depth == 0) primaryText else secondaryText))
                if (isCurrent) paint.isFakeBoldText = true
                setPadding((12 * density).toInt() + indent, (14 * density).toInt(), (12 * density).toInt(), (14 * density).toInt())
                setOnClickListener {
                    lifecycleScope.launch {
                        navigator?.go(item.link, animated = true)
                    }
                    dialog.dismiss()
                }
            }

            val divider = View(this).apply {
                setBackgroundColor(dividerColor)
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1)
            }
            listContainer.addView(chapterItem)
            listContainer.addView(divider)
        }

        scrollView.addView(listContainer)
        layout.addView(scrollView, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (420 * density).toInt()))

        dialog.setContentView(layout)
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        dialog.window?.setLayout(
            (resources.displayMetrics.widthPixels * 0.92).toInt(),
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        dialog.show()
    }

    private fun showAppearanceDialog() {
        val dialog = Dialog(this)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)

        val density = resources.displayMetrics.density
        val cardBg = getBarBackgroundColor()
        val primaryText = getPrimaryTextColor()
        val secondaryText = getSecondaryTextColor()
        val pillBg = getPillBackgroundColor()
        val dividerColor = getDividerColor()
        val accent = getAccentColor()

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = makeCardDrawable(cardBg, 18f, dividerColor, 1)
            setPadding((22 * density).toInt(), (20 * density).toInt(), (22 * density).toInt(), (22 * density).toInt())
        }

        // Header
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((4 * density).toInt(), 0, (4 * density).toInt(), (18 * density).toInt())
        }

        val sheetTitle = TextView(this).apply {
            text = "Themes & Settings"
            textSize = 17f
            setTextColor(primaryText)
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        headerRow.addView(sheetTitle)

        val closeBtn = TextView(this).apply {
            text = "✕"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(secondaryText)
            background = makeCardDrawable(pillBg, 14f)
            val size = (28 * density).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size)
            setOnClickListener { dialog.dismiss() }
        }
        headerRow.addView(closeBtn)
        layout.addView(headerRow)

        // Font Size Stepper Card (Apple Books Stepper)
        val sizeCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = makeCardDrawable(pillBg, 12f)
            setPadding((16 * density).toInt(), (10 * density).toInt(), (16 * density).toInt(), (10 * density).toInt())
        }

        val minusBtn = TextView(this).apply {
            text = "A"
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(primaryText)
            setPadding((12 * density).toInt(), (8 * density).toInt(), (16 * density).toInt(), (8 * density).toInt())
        }

        val sizeLabel = TextView(this).apply {
            text = "${(currentFontSize * 100).toInt()}%"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(primaryText)
            paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }

        val plusBtn = TextView(this).apply {
            text = "A"
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(primaryText)
            paint.isFakeBoldText = true
            setPadding((16 * density).toInt(), (8 * density).toInt(), (12 * density).toInt(), (8 * density).toInt())
        }

        minusBtn.setOnClickListener {
            if (currentFontSize > 0.6) {
                currentFontSize = (currentFontSize - 0.1).coerceAtLeast(0.5)
                sizeLabel.text = "${(currentFontSize * 100).toInt()}%"
                saveDurablePreferences()
                applyPreferences()
            }
        }

        plusBtn.setOnClickListener {
            if (currentFontSize < 2.5) {
                currentFontSize = (currentFontSize + 0.1).coerceAtMost(2.5)
                sizeLabel.text = "${(currentFontSize * 100).toInt()}%"
                saveDurablePreferences()
                applyPreferences()
            }
        }

        sizeCard.addView(minusBtn)
        sizeCard.addView(sizeLabel)
        sizeCard.addView(plusBtn)
        layout.addView(sizeCard)

        // Theme Selection Label
        val themeLabel = TextView(this).apply {
            text = "THEME"
            textSize = 11.5f
            setTextColor(secondaryText)
            paint.isFakeBoldText = true
            setPadding((4 * density).toInt(), (20 * density).toInt(), (4 * density).toInt(), (10 * density).toInt())
        }
        layout.addView(themeLabel)

        // Theme Selection Cards (Light, Sepia, Dark)
        val themeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        fun makeThemeCard(name: String, theme: Theme, bg: Int, textCol: Int, isBorder: Boolean): LinearLayout {
            val isSelected = (currentTheme == theme)
            return LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                val strokeCol = if (isSelected) accent else (if (isBorder) Color.parseColor("#D0D0D5") else null)
                val strokeWidth = if (isSelected) 2 else (if (isBorder) 1 else 0)
                background = makeCardDrawable(bg, 10f, strokeCol, strokeWidth)
                setPadding((8 * density).toInt(), (16 * density).toInt(), (8 * density).toInt(), (16 * density).toInt())
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    setMargins((4 * density).toInt(), 0, (4 * density).toInt(), 0)
                }

                val titleTv = TextView(this@ReadiumReaderActivity).apply {
                    text = if (isSelected) "✓ $name" else name
                    textSize = 13f
                    gravity = Gravity.CENTER
                    setTextColor(textCol)
                    if (isSelected) paint.isFakeBoldText = true
                }
                addView(titleTv)

                setOnClickListener {
                    currentTheme = theme
                    saveDurablePreferences()
                    applyPreferences()
                    dialog.dismiss()
                }
            }
        }

        themeRow.addView(makeThemeCard("Light", Theme.LIGHT, Color.WHITE, Color.BLACK, true))
        themeRow.addView(makeThemeCard("Sepia", Theme.SEPIA, Color.parseColor("#F4ECD8"), Color.parseColor("#5F4B32"), false))
        themeRow.addView(makeThemeCard("Dark", Theme.DARK, Color.parseColor("#1C1C1E"), Color.WHITE, false))
        layout.addView(themeRow)

        // Reading Navigation Mode Label
        val layoutLabel = TextView(this).apply {
            text = "READING MODE"
            textSize = 11.5f
            setTextColor(secondaryText)
            paint.isFakeBoldText = true
            setPadding((4 * density).toInt(), (20 * density).toInt(), (4 * density).toInt(), (10 * density).toInt())
        }
        layout.addView(layoutLabel)

        // Navigation Mode Capsule Switcher
        val modeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            background = makeCardDrawable(pillBg, 12f)
            setPadding((4 * density).toInt(), (4 * density).toInt(), (4 * density).toInt(), (4 * density).toInt())
        }

        val pagedBtn = TextView(this).apply {
            text = "Paged"
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(if (!isScrollMode) Color.WHITE else secondaryText)
            background = if (!isScrollMode) makeCardDrawable(accent, 8f) else null
            setPadding((16 * density).toInt(), (10 * density).toInt(), (16 * density).toInt(), (10 * density).toInt())
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            setOnClickListener {
                isScrollMode = false
                saveDurablePreferences()
                applyPreferences()
                dialog.dismiss()
            }
        }

        val scrollBtn = TextView(this).apply {
            text = "Scroll"
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(if (isScrollMode) Color.WHITE else secondaryText)
            background = if (isScrollMode) makeCardDrawable(accent, 8f) else null
            setPadding((16 * density).toInt(), (10 * density).toInt(), (16 * density).toInt(), (10 * density).toInt())
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
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
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        dialog.window?.setLayout(
            (resources.displayMetrics.widthPixels * 0.92).toInt(),
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
