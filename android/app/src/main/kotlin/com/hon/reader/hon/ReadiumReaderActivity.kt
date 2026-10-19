package com.hon.reader.hon

import android.app.Dialog
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.content.pm.ActivityInfo
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
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.CancellationException
import org.readium.r2.shared.publication.services.search.search
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.css.FontStyle
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.KeyEvent
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.Theme
import org.readium.r2.navigator.preferences.Color as ReadiumColor
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.epub.EpubLayout
import org.readium.r2.shared.publication.epub.layoutOf
import org.readium.r2.shared.publication.presentation.presentation
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
    private var continuousReader: ContinuousEpubView? = null
    private var lastReportedLocatorAt = 0L
    private var lastReportedHref: String? = null
    private var indexedPublication: Publication? = null
    private var chapterIndices = emptyMap<String, Int>()
    private lateinit var readerContainer: FrameLayout
    private var installingNavigator = false
    private var locatorJob: kotlinx.coroutines.Job? = null
    private var currentLocator: Locator? = null
    private var bookId: String = ""
    private var bookTitle: String = ""
    private var filePath: String? = null
    private var requestId: String = ""

    // Appearance State (durable across sessions)
    private var currentFontSize: Double = 1.0
    private var currentPreset: String = "calm"
    private var isScrollMode: Boolean = false

    private val currentTheme: Theme
        get() = when (currentPreset) {
            "quiet", "bold" -> Theme.DARK
            "calm" -> Theme.SEPIA
            else -> Theme.LIGHT
        }

    private lateinit var rootLayout: LinearLayout
    private lateinit var topBar: LinearLayout
    private lateinit var bottomBar: LinearLayout
    private lateinit var titleView: TextView
    private lateinit var backBtn: TextView
    private lateinit var aaBtn: TextView
    private lateinit var prevBtn: TextView
    private lateinit var progressPill: LinearLayout
    private lateinit var progressText: TextView
    private var areControlsVisible: Boolean = true
    private var isClosedReported: Boolean = false
    private var loadingIndicator: ProgressBar? = null
    private var readyReported = false

    private var cachedHighlights: List<Map<String, Any?>> = emptyList()

    fun refreshHighlights() {
        if (bookId.isEmpty()) return
        HonReaderBridge.instance?.getHighlights(bookId) { list ->
            cachedHighlights = list
            applyHighlightsToNavigator(list)
        }
    }

    private fun applyHighlightsToNavigator(highlights: List<Map<String, Any?>>) {
        val decorations = highlights.mapNotNull { hl ->
            val id = hl["id"] as? String ?: return@mapNotNull null
            val locJson = hl["locatorString"] as? String ?: hl["locator"] as? String ?: return@mapNotNull null
            val locator = try { Locator.fromJSON(JSONObject(locJson)) } catch (_: Exception) { null } ?: return@mapNotNull null
            val colorName = hl["color"] as? String ?: "yellow"
            val colorInt = when (colorName.lowercase()) {
                "pink" -> Color.parseColor("#F48FB1")
                "blue" -> Color.parseColor("#90CAF9")
                "green" -> Color.parseColor("#A5D6A7")
                "orange" -> Color.parseColor("#FFCC80")
                "purple" -> Color.parseColor("#CE93D8")
                else -> Color.parseColor("#FFF59D")
            }
            Decoration(
                id = id,
                locator = locator,
                style = Decoration.Style.Highlight(tint = colorInt, isActive = false)
            )
        }
        lifecycleScope.launch {
            navigator?.applyDecorations(decorations, "highlights")
            continuousReader?.applyDecorations(decorations, "highlights")
        }
    }

    private fun loadPerBookSettings() {
        if (bookId.isEmpty()) return
        HonReaderBridge.instance?.getBookReaderSettings(bookId) { settings ->
            if (settings != null && !isFinishing) {
                var changed = false
                (settings["fontSize"] as? Number)?.toDouble()?.let {
                    currentFontSize = it
                    changed = true
                }
                (settings["theme"] as? String)?.let {
                    currentPreset = it
                    changed = true
                }
                (settings["isScroll"] as? Boolean)?.let {
                    if (isScrollMode != it) {
                        isScrollMode = it
                        changed = true
                    }
                }
                (settings["typography"] as? String)?.let { typoStr ->
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                        .putString("readium_typography", typoStr)
                        .apply()
                    changed = true
                }
                if (changed) {
                    runOnUiThread {
                        applyPreferences()
                    }
                }
            }
        }
    }

    private fun showAddNoteDialog(locator: Locator, selectedText: String) {
        val dialog = Dialog(this)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = makeCardDrawable(getBarBackgroundColor(), 22f)
            setPadding(dp(20), dp(16), dp(20), dp(20))
        }
        layout.addView(TextView(this).apply {
            text = "Add Note"
            textSize = 18f
            setTextColor(getPrimaryTextColor())
            paint.isFakeBoldText = true
        })
        layout.addView(TextView(this).apply {
            text = "“$selectedText”"
            textSize = 13f
            setTextColor(getSecondaryTextColor())
            setPadding(0, dp(8), 0, dp(12))
            maxLines = 3
        })
        val input = android.widget.EditText(this).apply {
            hint = "Type your note here..."
            setTextColor(getPrimaryTextColor())
            setHintTextColor(getSecondaryTextColor())
            background = makeCardDrawable(getPillBackgroundColor(), 12f)
            setPadding(dp(12), dp(10), dp(12), dp(10))
            minLines = 3
            gravity = Gravity.TOP or Gravity.START
        }
        layout.addView(input)

        val buttons = LinearLayout(this).apply {
            gravity = Gravity.END
            setPadding(0, dp(16), 0, 0)
        }
        val cancelBtn = TextView(this).apply {
            text = "Cancel"
            textSize = 15f
            setTextColor(getSecondaryTextColor())
            setPadding(dp(16), dp(8), dp(16), dp(8))
            setOnClickListener { dialog.dismiss() }
        }
        val saveBtn = TextView(this).apply {
            text = "Save"
            textSize = 15f
            setTextColor(getAccentColor())
            paint.isFakeBoldText = true
            setPadding(dp(16), dp(8), dp(16), dp(8))
            setOnClickListener {
                val note = input.text.toString().trim().takeIf { it.isNotEmpty() }
                val highlightId = "hl_${System.currentTimeMillis()}"
                val highlightMap = mapOf(
                    "id" to highlightId,
                    "bookId" to bookId,
                    "locatorString" to locator.toJSON().toString(),
                    "selectedText" to selectedText,
                    "color" to "yellow",
                    "note" to note
                )
                HonReaderBridge.instance?.saveHighlight(highlightMap) { ok ->
                    if (ok == true) {
                        refreshHighlights()
                        Toast.makeText(this@ReadiumReaderActivity, "Highlight & Note saved", Toast.LENGTH_SHORT).show()
                    }
                }
                dialog.dismiss()
            }
        }
        buttons.addView(cancelBtn)
        buttons.addView(saveBtn)
        layout.addView(buttons)

        dialog.setContentView(layout)
        dialog.show()
        dialog.window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            setLayout((resources.displayMetrics.widthPixels * 0.9).toInt(), ViewGroup.LayoutParams.WRAP_CONTENT)
        }
    }

    private fun reportContentReady() {
        if (readyReported || isFinishing) return
        readyReported = true
        hideLoadingIndicator()
        loadPerBookSettings()
        refreshHighlights()
        HonReaderBridge.instance?.reportReady(bookId, requestId,
            lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED))
    }

    // Apple Books Color Palette
    private fun getThemeBackgroundColor(): Int {
        return when (currentPreset) {
            "original" -> Color.WHITE
            "quiet" -> Color.parseColor("#2C2C2E")
            "paper" -> Color.parseColor("#F2F2F7")
            "bold" -> Color.BLACK
            "focus" -> Color.parseColor("#FFFDF5")
            else -> Color.parseColor("#F1E5CD")
        }
    }

    private fun getBarBackgroundColor(): Int {
        return when (currentPreset) {
            "original" -> Color.parseColor("#F2F2F7")
            "quiet", "bold" -> Color.parseColor("#1C1C1E")
            "paper" -> Color.WHITE
            "focus" -> Color.parseColor("#F6F3E6")
            else -> Color.parseColor("#E8DCBF")
        }
    }

    private fun getPrimaryTextColor(): Int {
        return when (currentPreset) {
            "original" -> Color.parseColor("#1A1A1A")
            "quiet" -> Color.parseColor("#E5E5EA")
            "paper" -> Color.parseColor("#1C1C1E")
            "bold" -> Color.WHITE
            "focus" -> Color.parseColor("#262624")
            else -> Color.parseColor("#2C2211")
        }
    }

    private fun getSecondaryTextColor(): Int {
        return when (currentPreset) {
            "focus" -> Color.parseColor("#736E62")
            "calm" -> Color.parseColor("#70624E")
            "quiet", "bold" -> Color.parseColor("#B0B0B6")
            else -> Color.parseColor("#68686F")
        }
    }

    private fun getPillBackgroundColor(): Int {
        return when (currentPreset) {
            "quiet", "bold" -> Color.parseColor("#2C2C2E")
            "calm" -> Color.parseColor("#DFCFA8")
            else -> Color.parseColor("#EBEBEF")
        }
    }

    private fun getAccentColor(): Int {
        return when (currentPreset) {
            "calm" -> Color.parseColor("#B25E00")
            "quiet", "bold" -> Color.parseColor("#0A84FF")
            else -> Color.parseColor("#007AFF")
        }
    }

    private fun getDividerColor(): Int {
        return when (currentPreset) {
            "calm" -> Color.parseColor("#DED5BF")
            "quiet", "bold" -> Color.parseColor("#2C2C2E")
            else -> Color.parseColor("#E5E5EA")
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

        aaBtn.setTextColor(primaryText)
        prevBtn.setTextColor(secondaryText)
        progressPill.background = null
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
            override fun onKey(event: KeyEvent): Boolean = false
        })

        applyPreferences()
        observeLocator(fragment, pub)
    }

    private fun selectionConfiguration(selectedNavigator: () -> EpubNavigatorFragment? = { navigator }): EpubNavigatorFragment.Configuration =
        EpubNavigatorFragment.Configuration().apply {
            shouldApplyInsetsPadding = false
            servedAssets += "flutter_assets/assets/fonts/.*"
            for ((family, asset) in listOf("Newsreader" to "newsreader", "Literata" to "literata", "Lora" to "lora", "Libre Baskerville" to "librebaskerville")) {
                addFontFamilyDeclaration(FontFamily(family)) {
                    addFontFace {
                        addSource("flutter_assets/assets/fonts/$asset-Regular.ttf")
                        setFontStyle(FontStyle.NORMAL)
                        setFontWeight(200..900)
                    }
                    addFontFace {
                        addSource("flutter_assets/assets/fonts/$asset-Italic.ttf")
                        setFontStyle(FontStyle.ITALIC)
                        setFontWeight(200..900)
                    }
                }
            }
            selectionActionModeCallback = object : ActionMode.Callback {
                override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                    continuousReader?.selectionActive = true
                    menu.add(0, 1, 0, "Share quote").setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
                    menu.add(0, 2, 0, "Highlight").setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
                    menu.add(0, 3, 0, "Add Note").setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
                    return true
                }

                override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean = false

                override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
                    when (item.itemId) {
                        1 -> {
                            lifecycleScope.launch {
                                val selected = selectedNavigator()?.currentSelection()?.locator?.text?.highlight?.trim()
                                if (!selected.isNullOrEmpty()) {
                                    val author = publication?.metadata?.authors?.firstOrNull()?.name
                                        ?.takeUnless { it.isBlank() || it == "---" || it == "Unknown Author" }
                                    val attribution = listOfNotNull(author, bookTitle.takeIf { it.isNotBlank() })
                                        .joinToString(", ")
                                    val quote = "“$selected”" +
                                        if (attribution.isEmpty()) "" else "\n— $attribution"
                                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                        type = "text/plain"
                                        putExtra(Intent.EXTRA_TEXT, quote)
                                    }
                                    startActivity(Intent.createChooser(shareIntent, "Share quote"))
                                }
                                selectedNavigator()?.clearSelection()
                                mode.finish()
                            }
                            return true
                        }
                        2 -> {
                            lifecycleScope.launch {
                                val selection = selectedNavigator()?.currentSelection()
                                val locator = selection?.locator
                                val selected = locator?.text?.highlight?.trim()
                                if (locator != null && !selected.isNullOrEmpty()) {
                                    val highlightId = "hl_${System.currentTimeMillis()}"
                                    val highlightMap = mapOf(
                                        "id" to highlightId,
                                        "bookId" to bookId,
                                        "locatorString" to locator.toJSON().toString(),
                                        "selectedText" to selected,
                                        "color" to "yellow",
                                        "note" to null
                                    )
                                    HonReaderBridge.instance?.saveHighlight(highlightMap) { ok ->
                                        if (ok == true) {
                                            refreshHighlights()
                                            Toast.makeText(this@ReadiumReaderActivity, "Highlight saved", Toast.LENGTH_SHORT).show()
                                        }
                                    }
                                }
                                selectedNavigator()?.clearSelection()
                                mode.finish()
                            }
                            return true
                        }
                        3 -> {
                            lifecycleScope.launch {
                                val selection = selectedNavigator()?.currentSelection()
                                val locator = selection?.locator
                                val selected = locator?.text?.highlight?.trim()
                                selectedNavigator()?.clearSelection()
                                mode.finish()
                                if (locator != null && !selected.isNullOrEmpty()) {
                                    showAddNoteDialog(locator, selected)
                                }
                            }
                            return true
                        }
                        else -> return false
                    }
                }

                override fun onDestroyActionMode(mode: ActionMode) { continuousReader?.selectionActive = false }
            }
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
        currentPreset = (savedInstanceState?.getString("theme")
            ?: prefs.getString(KEY_THEME, "calm") ?: "calm").lowercase().let {
            when (it) {
                "light" -> "original"
                "sepia" -> "calm"
                "dark" -> "quiet"
                else -> it
            }
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
        if (savedInstanceState != null && cachedPub != null && !isScrollMode) {
            publication = cachedPub
            val initialLocator = resolveInitialLocator(cachedPub, initialLocatorJson, initialChapterIndex)
            val factory = EpubNavigatorFactory(cachedPub)
            supportFragmentManager.fragmentFactory = factory.createFragmentFactory(
                initialLocator = initialLocator,
                configuration = selectionConfiguration()
            )
            super.onCreate(savedInstanceState)
            buildReaderLayout(showLoading = false)

            val fragment = supportFragmentManager.findFragmentById(R.id.readium_fragment_container) as? EpubNavigatorFragment
            if (fragment != null) {
                setupFragment(fragment, cachedPub)

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
            showReadingContent(pub, initialLocator)

        }
    }

    private fun buildReaderLayout(showLoading: Boolean = false) {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(getThemeBackgroundColor())
        }
        rootLayout = root

        val density = resources.displayMetrics.density

        // Match the downloaded reader: location, remaining chapters, close.
        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(getBarBackgroundColor())
            setPadding(dp(16), dp(36), dp(16), dp(8))
            prevBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "↶ 1"
                textSize = 13f
                gravity = Gravity.CENTER_VERTICAL
                contentDescription = "Previous chapter"
                layoutParams = LinearLayout.LayoutParams(dp(64), dp(44))
                setOnClickListener {
                    val pub = publication ?: return@setOnClickListener
                    val index = currentChapterIndex(pub)
                    if (index > 0) goReading(pub.readingOrder[index - 1])
                }
            }
            addView(prevBtn)
            titleView = TextView(this@ReadiumReaderActivity).apply {
                text = bookTitle
                textSize = 13f
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            addView(titleView, LinearLayout.LayoutParams(0, dp(44), 1f))
            backBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "✕"
                textSize = 15f
                gravity = Gravity.CENTER
                contentDescription = "Close reader"
                background = makeCardDrawable(getPillBackgroundColor(), 18f)
                layoutParams = LinearLayout.LayoutParams(dp(36), dp(36)).apply { setMargins(dp(28), 0, 0, 0) }
                setOnClickListener { finish() }
            }
            addView(backBtn)
        }
        ViewCompat.setOnApplyWindowInsetsListener(topBar) { v, insets ->
            v.setPadding(dp(16), insets.getInsets(WindowInsetsCompat.Type.statusBars()).top + dp(8), dp(16), dp(8))
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
        readerContainer = container

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

        // Same progress/Aa footer as the downloaded and PDF readers.
        bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(getBarBackgroundColor())
            setPadding(dp(20), dp(8), dp(20), dp(24))
            addView(View(this@ReadiumReaderActivity), LinearLayout.LayoutParams(dp(48), dp(44)))
            progressPill = LinearLayout(this@ReadiumReaderActivity).apply {
                gravity = Gravity.CENTER
                progressText = TextView(this@ReadiumReaderActivity).apply {
                    text = "Opening book…"
                    textSize = 13f
                    gravity = Gravity.CENTER
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    setOnClickListener { showTocDialog() }
                }
                addView(progressText)
            }
            addView(progressPill, LinearLayout.LayoutParams(0, dp(44), 1f))
            aaBtn = TextView(this@ReadiumReaderActivity).apply {
                text = "Aa"
                textSize = 20f
                gravity = Gravity.CENTER
                contentDescription = "Reader menu"
                layoutParams = LinearLayout.LayoutParams(dp(48), dp(44))
                setOnClickListener { showReaderMenu() }
            }
            addView(aaBtn)
        }
        ViewCompat.setOnApplyWindowInsetsListener(bottomBar) { v, insets ->
            v.setPadding(dp(20), dp(8), dp(20), insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom + dp(8))
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
        locatorJob?.cancel()
        locatorJob = lifecycleScope.launch {
            fragment.currentLocator.collectLatest { loc ->
                receiveLocator(fragment, loc)

            }
        }
    }

    private fun receiveLocator(fragment: EpubNavigatorFragment, loc: Locator) {
        navigator = fragment
        currentLocator = loc
        val total = computeTotalProgression(loc)
        val index = currentChapterIndex(publication)
        val count = publication?.readingOrder?.size ?: 1
        val progressLabel = "Chapter ${index + 1} of $count"
        if (progressText.text.toString() != progressLabel) progressText.text = progressLabel
        val locationLabel = "↶ ${index + 1}"
        if (prevBtn.text.toString() != locationLabel) prevBtn.text = locationLabel
        prevBtn.isEnabled = index > 0
        prevBtn.alpha = if (index > 0) 1f else .4f
        val remainingLabel = if (index + 1 < count) "${count - index - 1} chapters left" else "Last chapter"
        if (titleView.text.toString() != remainingLabel) titleView.text = remainingLabel
        val now = android.os.SystemClock.elapsedRealtime()
        val href = loc.href.toString()
        if (now - lastReportedLocatorAt >= 250 || href != lastReportedHref || loc.locations.otherLocations.containsKey("honTextOffset")) {
            lastReportedLocatorAt = now
            lastReportedHref = href
            HonReaderBridge.instance?.reportLocator(bookId, requestId, loc.toJSON().toString(), total)
        }
        if (continuousReader == null) reportContentReady()
    }

    private fun showReadingContent(pub: Publication, anchor: Locator?) {
        if (installingNavigator || supportFragmentManager.isStateSaved || isFinishing) return
        normalizeLayout(pub)
        installingNavigator = true
        locatorJob?.cancel()
        locatorJob = null
        continuousReader?.dispose()
        continuousReader = null
        val previous = supportFragmentManager.findFragmentById(R.id.readium_fragment_container)
        if (previous != null) supportFragmentManager.beginTransaction().remove(previous).commitNow()
        readerContainer.removeAllViews()
        navigator = null
        if (isScrollMode) {
            continuousReader = ContinuousEpubView(
                activity = this, container = readerContainer, publication = pub,
                configuration = { selected -> selectionConfiguration(selected) },
                onTap = { toggleControls() },
                onLocator = { fragment, locator -> receiveLocator(fragment, locator) },
                onReady = { reportContentReady() },
                onExternalLink = { url ->
                    val uri = android.net.Uri.parse(url)
                    if (uri.scheme in listOf("https", "http", "mailto")) try {
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                    } catch (_: Exception) { Toast.makeText(this, "Could not open link", Toast.LENGTH_SHORT).show() }
                },
                onFailure = { message ->
                    if (!isFinishing && !supportFragmentManager.isStateSaved) {
                        Toast.makeText(this, "$message Opening Paged mode.", Toast.LENGTH_LONG).show()
                        isScrollMode = false
                        saveDurablePreferences()
                        showReadingContent(pub, currentLocator ?: anchor)
                    }
                },
                initialPreferences = readerPreferences(), initialLocator = anchor,
            )
        } else {
            val factory = EpubNavigatorFactory(pub).createFragmentFactory(
                initialLocator = anchor, initialPreferences = readerPreferences(), configuration = selectionConfiguration())
            supportFragmentManager.fragmentFactory = factory
            val fragment = factory.instantiate(classLoader, EpubNavigatorFragment::class.java.name) as EpubNavigatorFragment
            supportFragmentManager.beginTransaction().replace(R.id.readium_fragment_container, fragment).commitNow()
            setupFragment(fragment, pub)
        }
        installingNavigator = false
        applyHighlightsToNavigator(cachedHighlights)
    }

    private fun goReading(locator: Locator): Boolean = continuousReader?.go(locator) ?: (navigator?.go(locator, animated = false) ?: false)
    private fun goReading(link: Link): Boolean = continuousReader?.go(link) ?: (navigator?.go(link, animated = true) ?: false)
    private fun moveReading(forward: Boolean) {
        continuousReader?.let { it.move(forward); return }
        if (forward) navigator?.goForward(animated = true) else navigator?.goBackward(animated = true)
    }

    private fun computeTotalProgression(loc: Locator?): Double {
        if (loc == null) return 0.0
        val total = loc.locations.totalProgression
        if (total != null) {
            return total.coerceIn(0.0, 1.0)
        }
        val pub = publication
        if (pub != null && pub.readingOrder.isNotEmpty()) {
            val resourceIndex = currentChapterIndex(pub, loc)
            val chapterProg = loc.locations.progression ?: 0.0
            return ((resourceIndex + chapterProg) / pub.readingOrder.size.toDouble()).coerceIn(0.0, 1.0)
        }
        return (loc.locations.progression ?: 0.0).coerceIn(0.0, 1.0)
    }

    private fun toggleControls() {
        areControlsVisible = !areControlsVisible
        val visibility = if (areControlsVisible) View.VISIBLE else View.INVISIBLE
        topBar.visibility = visibility
        bottomBar.visibility = visibility
        updateSystemBars()
    }

    private fun saveDurablePreferences() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (bookId.isNotEmpty()) {
            val typoJson = prefs.getString("readium_typography", "{}") ?: "{}"
            val settingsMap = mapOf(
                "fontSize" to currentFontSize,
                "theme" to currentPreset,
                "isScroll" to isScrollMode,
                "typography" to typoJson
            )
            HonReaderBridge.instance?.saveBookReaderSettings(bookId, settingsMap) {}
            HonReaderBridge.instance?.reportPreferences(currentPreset, isScrollMode, currentFontSize, bookId = bookId)
        } else {
            prefs.edit()
                .putFloat(KEY_FONT_SIZE, currentFontSize.toFloat())
                .putString(KEY_THEME, currentPreset)
                .putBoolean(KEY_SCROLL, isScrollMode)
                .apply()
            HonReaderBridge.instance?.reportPreferences(currentPreset, isScrollMode, currentFontSize)
        }
    }

    fun applyExternalSettings(fontSize: Double?, themeStr: String?, isScroll: Boolean?) {
        if (fontSize != null) currentFontSize = fontSize
        if (themeStr != null) {
            currentPreset = themeStr.lowercase().takeIf {
                it in setOf("original", "quiet", "paper", "bold", "calm", "focus")
            } ?: currentPreset
        }
        if (isScroll != null) isScrollMode = isScroll

        saveDurablePreferences()

        runOnUiThread {
            applyPreferences()
        }
    }

    private fun readerPreferences(): EpubPreferences {
        val stored = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString("readium_typography", null)
        val typography = try { JSONObject(stored ?: "{}") } catch (_: Exception) { JSONObject() }
        val font = when (typography.optString("font", "georgia")) {
            "sanFrancisco" -> FontFamily.SANS_SERIF
            "newYork" -> FontFamily("Literata")
            "palatino" -> FontFamily("Lora")
            "baskerville" -> FontFamily("Libre Baskerville")
            else -> FontFamily("Newsreader")
        }
        window.attributes = window.attributes.apply {
            screenBrightness = typography.optDouble("brightness", 0.85).coerceIn(0.1, 1.0).toFloat()
        }
        return EpubPreferences(
                fontFamily = font,
                lineHeight = typography.optDouble("lineHeight", 1.65).coerceIn(1.2, 2.5),
                pageMargins = (typography.optDouble("margin", 24.0) / 24.0).coerceIn(0.2, 3.0),
                paragraphSpacing = typography.optDouble("paragraphSpacing", 8.0) / 18.0,
                paragraphIndent = typography.optDouble("indent", 24.0) / 18.0,
                textAlign = if (typography.optBoolean("justified", true)) TextAlign.JUSTIFY else TextAlign.START,
                publisherStyles = typography.optBoolean("publisherStyles", false),
                fontSize = currentFontSize,
                theme = currentTheme,
                backgroundColor = ReadiumColor(getThemeBackgroundColor()),
                textColor = ReadiumColor(getPrimaryTextColor()),
                scroll = isScrollMode
            )
    }

    private fun applyPreferences() {
        updateThemeStyling()
        val pub = publication
        if (pub != null) normalizeLayout(pub)
        if (!installingNavigator && pub != null && isScrollMode != (continuousReader != null)) {
            showReadingContent(pub, currentLocator)
            return
        }
        val value = readerPreferences()
        val continuous = continuousReader
        if (continuous != null) continuous.submitPreferences(value) else navigator?.submitPreferences(value)
    }

    private fun normalizeLayout(pub: Publication) {
        if (isScrollMode && pub.readingOrder.any { pub.metadata.presentation.layoutOf(it) == EpubLayout.FIXED }) {
            isScrollMode = false
            saveDurablePreferences()
            Toast.makeText(this, "This EPUB uses a fixed layout and opens in Paged mode.", Toast.LENGTH_LONG).show()
        }
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

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun currentChapterIndex(pub: Publication? = publication, locator: Locator? = currentLocator): Int {
        if (pub == null) return 0
        if (indexedPublication !== pub) {
            chapterIndices = pub.readingOrder.mapIndexed { index, link -> link.url().toString().substringBefore('#') to index }.toMap()
            indexedPublication = pub
        }
        return chapterIndices[locator?.href?.toString()?.substringBefore('#')] ?: 0
    }

    private fun showBottomSheet(dialog: Dialog, content: View, height: Int? = null) {
        dialog.setContentView(content)
        dialog.show()
        dialog.window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            navigationBarColor = getBarBackgroundColor()
            WindowInsetsControllerCompat(this, decorView).isAppearanceLightNavigationBars =
                androidx.core.graphics.ColorUtils.calculateLuminance(getBarBackgroundColor()) > .5
            setGravity(Gravity.BOTTOM)
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, height ?: ViewGroup.LayoutParams.WRAP_CONTENT)
            addFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            attributes = attributes.apply { dimAmount = 0.28f }
        }
    }

    private fun sheetHeader(title: String, dialog: Dialog): LinearLayout = LinearLayout(this).apply {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(20), dp(16), dp(12), dp(12))
        addView(TextView(this@ReadiumReaderActivity).apply {
            text = title; textSize = 19f; setTextColor(getPrimaryTextColor()); paint.isFakeBoldText = true
        }, LinearLayout.LayoutParams(0, dp(40), 1f))
        addView(TextView(this@ReadiumReaderActivity).apply {
            text = "✕"; textSize = 16f; gravity = Gravity.CENTER
            contentDescription = "Close $title"; setTextColor(getSecondaryTextColor())
            setOnClickListener { dialog.dismiss() }
        }, LinearLayout.LayoutParams(dp(44), dp(44)))
    }

    private fun showTocDialog() {
        val pub = publication ?: return
        val dialog = Dialog(this)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = makeCardDrawable(getBarBackgroundColor(), 22f)
        }
        layout.addView(sheetHeader("Contents", dialog))
        layout.addView(TextView(this).apply {
            text = bookTitle; setTextColor(getSecondaryTextColor()); textSize = 13f
            setPadding(dp(20), 0, dp(20), dp(12))
        })
        val tabs = LinearLayout(this).apply { setPadding(dp(20), 0, dp(20), dp(12)) }
        val list = android.widget.ListView(this).apply {
            dividerHeight = 1
            setPadding(dp(12), 0, dp(12), dp(20))
            clipToPadding = false
        }
        val toc = flattenToc(pub.tableOfContents.ifEmpty { pub.readingOrder })
        var bookmarkEntries = emptyList<Map<String, Any?>>()
        var highlightEntries = emptyList<Map<String, Any?>>()
        var currentTab = 0 // 0: chapters, 1: bookmarks, 2: highlights

        fun render() {
            list.adapter = object : android.widget.BaseAdapter() {
                override fun getCount(): Int = when (currentTab) {
                    0 -> toc.size
                    1 -> bookmarkEntries.size
                    2 -> highlightEntries.size
                    else -> 0
                }
                override fun getItem(position: Int): Any = when (currentTab) {
                    0 -> toc[position]
                    1 -> bookmarkEntries[position]
                    2 -> highlightEntries[position]
                    else -> ""
                }
                override fun getItemId(position: Int): Long = position.toLong()
                override fun getView(position: Int, convert: View?, parent: ViewGroup?): View {
                    if (currentTab == 2) {
                        val hl = highlightEntries[position]
                        val container = LinearLayout(this@ReadiumReaderActivity).apply {
                            orientation = LinearLayout.VERTICAL
                            setPadding(dp(12), dp(12), dp(12), dp(12))
                        }
                        val textStr = hl["selectedText"]?.toString() ?: ""
                        val noteStr = hl["note"]?.toString()
                        container.addView(TextView(this@ReadiumReaderActivity).apply {
                            text = "“$textStr”"
                            textSize = 15f
                            setTextColor(getPrimaryTextColor())
                        })
                        if (!noteStr.isNullOrEmpty()) {
                            container.addView(TextView(this@ReadiumReaderActivity).apply {
                                text = "Note: $noteStr"
                                textSize = 13f
                                setTextColor(getSecondaryTextColor())
                                setPadding(0, dp(4), 0, 0)
                            })
                        }
                        return container
                    }
                    return ((convert as? TextView) ?: TextView(this@ReadiumReaderActivity)).apply {
                        val item = if (currentTab == 0) toc[position] else null
                        text = if (currentTab == 1) bookmarkEntries[position]["label"]?.toString() ?: "Bookmark" else item!!.title
                        textSize = 15f
                        val current = item?.link?.url()?.toString()?.substringBefore('#') == currentLocator?.href?.toString()?.substringBefore('#')
                        setTextColor(if (current) getAccentColor() else getPrimaryTextColor())
                        paint.isFakeBoldText = current
                        setPadding(dp(12 + (item?.depth ?: 0) * 16), dp(16), dp(12), dp(16))
                    }
                }
            }
            if (currentTab == 1 && bookmarkEntries.isEmpty()) {
                Toast.makeText(this, "No bookmarks yet. Save one from the reader menu.", Toast.LENGTH_SHORT).show()
            } else if (currentTab == 2 && highlightEntries.isEmpty()) {
                Toast.makeText(this, "No highlights yet. Select text in reader to highlight.", Toast.LENGTH_SHORT).show()
            }
        }

        val chapterTab = TextView(this).apply { text = "Chapters" }
        val bookmarkTab = TextView(this).apply { text = "Bookmarks" }
        val highlightTab = TextView(this).apply { text = "Highlights" }

        fun select(tabIndex: Int) {
            currentTab = tabIndex
            val allTabs = listOf(chapterTab, bookmarkTab, highlightTab)
            for ((index, tab) in allTabs.withIndex()) {
                tab.background = makeCardDrawable(if (index == tabIndex) getPillBackgroundColor() else Color.TRANSPARENT, 10f)
                tab.setTextColor(getPrimaryTextColor())
            }
            render()
        }

        for (tab in listOf(chapterTab, bookmarkTab, highlightTab)) {
            tab.gravity = Gravity.CENTER; tab.textSize = 14f
            tabs.addView(tab, LinearLayout.LayoutParams(0, dp(40), 1f))
        }

        chapterTab.setOnClickListener { select(0) }
        bookmarkTab.setOnClickListener {
            HonReaderBridge.instance?.getBookmarks(bookId) { entries ->
                if (dialog.isShowing) { bookmarkEntries = entries; select(1) }
            }
        }
        highlightTab.setOnClickListener {
            HonReaderBridge.instance?.getHighlights(bookId) { entries ->
                if (dialog.isShowing) { highlightEntries = entries; select(2) }
            }
        }

        list.setOnItemClickListener { _, _, position, _ ->
            when (currentTab) {
                0 -> goReading(toc[position].link)
                1 -> {
                    val locatorJson = bookmarkEntries[position]["locatorString"] as? String
                    val locator = locatorJson?.let { try { Locator.fromJSON(JSONObject(it)) } catch (_: Exception) { null } }
                    if (locator != null) {
                        goReading(locator)
                    } else {
                        val index = (bookmarkEntries[position]["pageIndex"] as? Number)?.toInt()
                        if (index != null && index in pub.readingOrder.indices) goReading(pub.readingOrder[index])
                    }
                }
                2 -> {
                    val locJson = highlightEntries[position]["locatorString"] as? String ?: highlightEntries[position]["locator"] as? String
                    val locator = locJson?.let { try { Locator.fromJSON(JSONObject(it)) } catch (_: Exception) { null } }
                    if (locator != null) {
                        goReading(locator)
                    }
                }
            }
            dialog.dismiss()
        }

        list.setOnItemLongClickListener { _, _, position, _ ->
            if (currentTab == 2) {
                val hl = highlightEntries[position]
                val id = hl["id"] as? String
                if (id != null) {
                    androidx.appcompat.app.AlertDialog.Builder(this)
                        .setTitle("Delete Highlight")
                        .setMessage("Do you want to delete this highlight?")
                        .setPositiveButton("Delete") { _, _ ->
                            HonReaderBridge.instance?.deleteHighlight(id) { ok ->
                                if (ok == true) {
                                    refreshHighlights()
                                    HonReaderBridge.instance?.getHighlights(bookId) { updated ->
                                        if (dialog.isShowing) {
                                            highlightEntries = updated
                                            render()
                                        }
                                    }
                                    Toast.makeText(this@ReadiumReaderActivity, "Highlight deleted", Toast.LENGTH_SHORT).show()
                                }
                            }
                        }
                        .setNegativeButton("Cancel", null)
                        .show()
                    return@setOnItemLongClickListener true
                }
            }
            false
        }

        layout.addView(tabs)
        layout.addView(list, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        select(0)
        showBottomSheet(dialog, layout, (resources.displayMetrics.heightPixels * .8).toInt())
    }

    private fun showReaderMenu() {
        if (isFinishing || navigator == null) return
        val dialog = Dialog(this)
        val menu = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = makeCardDrawable(getBarBackgroundColor(), 22f, getDividerColor(), 1)
            setPadding(0, dp(4), 0, dp(4))
        }
        fun item(label: String, glyph: String, action: () -> Unit) {
            menu.addView(TextView(this).apply {
                text = "$label    $glyph"; textSize = 15f; setTextColor(getPrimaryTextColor())
                setPadding(dp(18), dp(15), dp(18), dp(15)); minHeight = dp(48)
                setOnClickListener { dialog.dismiss(); action() }
            })
            menu.addView(View(this).apply { setBackgroundColor(getDividerColor()) }, LinearLayout.LayoutParams(-1, 1))
        }
        item("Contents", "≡") { showTocDialog() }
        item("Search Book", "⌕") { showBookSearch() }
        item("Themes & Settings", "Aa") { showAppearanceDialog() }
        val row = LinearLayout(this).apply { gravity = Gravity.CENTER; setPadding(dp(8), dp(8), dp(8), dp(8)) }
        fun quick(label: String, glyph: String, action: () -> Unit) {
            row.addView(TextView(this).apply {
                text = glyph; textSize = 21f; gravity = Gravity.CENTER
                contentDescription = label; setTextColor(getPrimaryTextColor())
                if (android.os.Build.VERSION.SDK_INT >= 26) tooltipText = label
                setOnClickListener { dialog.dismiss(); action() }
            }, LinearLayout.LayoutParams(0, dp(44), 1f))
        }
        quick("Share quote", "↗") {
            Toast.makeText(this, "Select a passage, then choose Share quote.", Toast.LENGTH_SHORT).show()
        }
        quick("Rotation lock", if (requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_LOCKED) "▣" else "↻") {
            requestedOrientation = if (requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_LOCKED)
                ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED else ActivityInfo.SCREEN_ORIENTATION_LOCKED
        }
        val canReflow = publication?.let { pub -> pub.readingOrder.none { pub.metadata.presentation.layoutOf(it) == EpubLayout.FIXED } } ?: true
        if (canReflow) {
            quick(if (isScrollMode) "Paged mode" else "Scroll mode", if (isScrollMode) "▤" else "▥") {
                isScrollMode = !isScrollMode; saveDurablePreferences(); applyPreferences()
            }
        }
        quick("Bookmark", "☆") {
            HonReaderBridge.instance?.toggleBookmark(
                bookId,
                currentChapterIndex(),
                currentLocator?.title ?: "Chapter ${currentChapterIndex() + 1}",
                locatorJson = currentLocator?.toJSON()?.toString(),
                locatorVersion = "readium-v2",
                snippet = currentLocator?.text?.highlight
            ) { added ->
                Toast.makeText(this, if (added == true) "Bookmark saved" else if (added == false) "Bookmark removed" else "Could not save bookmark", Toast.LENGTH_SHORT).show()
            }
        }
        menu.addView(row)
        dialog.setContentView(menu)
        dialog.show()
        dialog.window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            setGravity(Gravity.BOTTOM or Gravity.RIGHT)
            setLayout(dp(268), ViewGroup.LayoutParams.WRAP_CONTENT)
            attributes = attributes.apply { x = dp(16); y = dp(72); dimAmount = .28f }
        }
    }

    private fun showBookSearch() {
        val pub = publication ?: return
        val dialog = Dialog(this)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = makeCardDrawable(getBarBackgroundColor(), 22f)
            setPadding(dp(12), 0, dp(12), dp(12))
        }
        layout.addView(sheetHeader("Search Book", dialog))
        val query = android.widget.EditText(this).apply {
            hint = "Find a word or passage"
            textSize = 16f; setTextColor(getPrimaryTextColor()); setHintTextColor(getSecondaryTextColor())
            isSingleLine = true; imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH
            setPadding(dp(12), dp(8), dp(12), dp(8))
        }
        layout.addView(query)
        val status = TextView(this).apply {
            text = "Enter a query and tap Search."
            textSize = 12f; setTextColor(getSecondaryTextColor())
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        layout.addView(status)
        val list = android.widget.ListView(this)
        layout.addView(list, LinearLayout.LayoutParams(-1, 0, 1f))
        var job: kotlinx.coroutines.Job? = null
        var matches = emptyList<Locator>()
        fun submit() {
            val value = query.text.toString().trim()
            if (value.length < 2) { status.text = "Enter at least two characters."; return }
            job?.cancel()
            (getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager)
                .hideSoftInputFromWindow(query.windowToken, 0)
            status.text = "Searching…"
            job = lifecycleScope.launch {
                try {
                    val found = withContext(Dispatchers.IO) {
                        withTimeout(15_000) {
                            val iterator = pub.search(value) ?: throw IllegalStateException("Text search is unavailable for this publication.")
                            try {
                                val result = mutableListOf<Locator>()
                                while (result.size < 100) {
                                    val batch = iterator.next() ?: break
                                    val collection = batch.getOrNull() ?: throw IllegalStateException("Could not read a resource while searching.")
                                    result.addAll(collection.locators)
                                }
                                result.take(100)
                            } finally { iterator.close() }
                        }
                    }
                    if (!dialog.isShowing) return@launch
                    matches = found
                    status.text = if (found.isEmpty()) "No matches." else if (found.size == 100) "Showing the first 100 matches. Refine your search for more." else "${found.size} matches"
                    list.adapter = object : android.widget.BaseAdapter() {
                        override fun getCount() = matches.size
                        override fun getItem(position: Int) = matches[position]
                        override fun getItemId(position: Int) = position.toLong()
                        override fun getView(position: Int, convert: View?, parent: ViewGroup?): View =
                            ((convert as? TextView) ?: TextView(this@ReadiumReaderActivity)).apply {
                                val loc = matches[position]
                                text = listOfNotNull(loc.title, loc.text.before, loc.text.highlight, loc.text.after).joinToString(" ").take(240)
                                textSize = 14f; setTextColor(getPrimaryTextColor())
                                maxLines = 4; ellipsize = android.text.TextUtils.TruncateAt.END
                                setPadding(dp(12), dp(14), dp(12), dp(14))
                            }
                    }
                } catch (error: kotlinx.coroutines.TimeoutCancellationException) {
                    if (dialog.isShowing) status.text = "Search took too long. Try a more specific query."
                } catch (error: CancellationException) { throw error }
                catch (error: Exception) { if (dialog.isShowing) status.text = error.message ?: "Search failed." }
            }
        }
        query.setOnEditorActionListener { _, action, event ->
            if (action == android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH || event?.keyCode == android.view.KeyEvent.KEYCODE_ENTER) { submit(); true } else false
        }
        layout.addView(TextView(this).apply {
            text = "Search"; textSize = 15f; gravity = Gravity.CENTER; setTextColor(getAccentColor())
            setPadding(dp(12), dp(12), dp(12), dp(12)); setOnClickListener { submit() }
        })
        list.setOnItemClickListener { _, _, position, _ -> goReading(matches[position]); dialog.dismiss() }
        dialog.setOnDismissListener { job?.cancel() }
        showBottomSheet(dialog, layout, (resources.displayMetrics.heightPixels * .8).toInt())
    }

    private fun showAppearanceDialog() {
        val dialog = Dialog(this)
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        fun typography(): JSONObject = try { JSONObject(prefs.getString("readium_typography", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
        fun store(key: String, value: Any) {
            val values = typography().put(key, value)
            prefs.edit().putString("readium_typography", values.toString()).apply()
            saveDurablePreferences()
            if (key != "brightness") applyPreferences()
        }
        val canReflow = publication?.let { pub -> pub.readingOrder.none { pub.metadata.presentation.layoutOf(it) == EpubLayout.FIXED } } ?: true
        var customize = false
        lateinit var render: () -> Unit
        var previousScroll: ScrollView? = null
        render = {
            val offset = previousScroll?.scrollY ?: 0
            val values = typography()
            val bg = getBarBackgroundColor()
            val primary = getPrimaryTextColor()
            val secondary = getSecondaryTextColor()
            val pill = getPillBackgroundColor()
            val layout = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                background = makeCardDrawable(bg, 22f)
                setPadding(dp(20), dp(12), dp(20), dp(28))
            }
            layout.addView(sheetHeader(if (customize) "Customize" else "Themes & Settings", dialog))
            fun label(text: String) {
                layout.addView(TextView(this).apply {
                    this.text = text; textSize = 13f; setTextColor(secondary)
                    setPadding(0, dp(16), 0, dp(8))
                })
            }
            fun button(text: String, description: String, action: () -> Unit): TextView = TextView(this).apply {
                this.text = text; textSize = 17f; gravity = Gravity.CENTER
                contentDescription = description; setTextColor(primary)
                background = makeCardDrawable(pill, 12f)
                minHeight = dp(44); setPadding(dp(12), dp(10), dp(12), dp(10))
                setOnClickListener { action() }
            }
            fun slider(key: String, name: String, minimum: Double, maximum: Double, fallback: Double) {
                val title = TextView(this).apply { textSize = 13f; setTextColor(primary) }
                var amount = values.optDouble(key, fallback).coerceIn(minimum, maximum)
                fun titleText() { title.text = "$name  ${String.format(java.util.Locale.ROOT, "%.2f", amount)}" }
                titleText(); layout.addView(title)
                layout.addView(android.widget.SeekBar(this).apply {
                    max = 100; progress = ((amount - minimum) / (maximum - minimum) * 100).toInt()
                    contentDescription = name
                    setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
                        override fun onProgressChanged(bar: android.widget.SeekBar?, progress: Int, user: Boolean) {
                            amount = minimum + progress / 100.0 * (maximum - minimum)
                            titleText()
                            if (key == "brightness" && user) window.attributes = window.attributes.apply { screenBrightness = amount.toFloat() }
                        }
                        override fun onStartTrackingTouch(bar: android.widget.SeekBar?) = Unit
                        override fun onStopTrackingTouch(bar: android.widget.SeekBar?) { store(key, amount) }
                    })
                }, LinearLayout.LayoutParams(-1, dp(44)))
            }
            if (!customize) {
                val controls = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
                if (canReflow) {
                    val sizes = LinearLayout(this).apply { background = makeCardDrawable(pill, 12f) }
                    sizes.addView(button("A", "Decrease font size") {
                        currentFontSize = (currentFontSize - 1.5 / 18).coerceAtLeast(12.0 / 18)
                        saveDurablePreferences(); applyPreferences(); render()
                    }, LinearLayout.LayoutParams(0, dp(44), 1f))
                    sizes.addView(button("A", "Increase font size") {
                        currentFontSize = (currentFontSize + 1.5 / 18).coerceAtMost(32.0 / 18)
                        saveDurablePreferences(); applyPreferences(); render()
                    }.apply { textSize = 22f }, LinearLayout.LayoutParams(0, dp(44), 1f))
                    controls.addView(sizes, LinearLayout.LayoutParams(0, dp(44), 3f))
                    controls.addView(button(if (isScrollMode) "▤" else "▥", "Switch reading mode") {
                        isScrollMode = !isScrollMode; saveDurablePreferences(); applyPreferences(); render()
                    }, LinearLayout.LayoutParams(dp(48), dp(44)).apply { leftMargin = dp(10) })
                }
                controls.addView(button("◐", "Invert theme") {
                    currentPreset = if (currentPreset == "bold") "original" else "bold"
                    saveDurablePreferences(); applyPreferences(); render()
                }, LinearLayout.LayoutParams(dp(48), dp(44)).apply { leftMargin = if (canReflow) dp(10) else 0 })
                layout.addView(controls)
                if (!canReflow) label("This book has a fixed page layout. Font changes are unavailable.")
                if (canReflow) layout.addView(TextView(this).apply {
                    text = "A quiet moment.\nJust you and the next chapter."
                    textSize = (currentFontSize * 18).toFloat().coerceIn(14f, 24f)
                    setTextColor(primary)
                    setPadding(dp(18), dp(16), dp(18), dp(16))
                    background = makeCardDrawable(getThemeBackgroundColor(), 14f)
                    val asset = when (values.optString("font", "georgia")) {
                        "newYork" -> "literata"
                        "palatino" -> "lora"
                        "baskerville" -> "librebaskerville"
                        "sanFrancisco" -> null
                        else -> "newsreader"
                    }
                    typeface = if (asset == null) android.graphics.Typeface.SANS_SERIF else
                        android.graphics.Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/$asset-Regular.ttf")
                    setLineSpacing(0f, values.optDouble("lineHeight", 1.65).toFloat())
                }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(18) })
                label("Brightness")
                slider("brightness", "Brightness", .1, 1.0, .85)
                val themes = listOf(
                    listOf("Original", "original", "#FFFFFF", "#1A1A1A"),
                    listOf("Quiet", "quiet", "#2C2C2E", "#E5E5EA"),
                    listOf("Paper", "paper", "#F2F2F7", "#1C1C1E"),
                    listOf("Bold", "bold", "#000000", "#FFFFFF"),
                    listOf("Calm", "calm", "#F1E5CD", "#2C2211"),
                    listOf("Focus", "focus", "#FFFDF5", "#262624")
                )
                for (row in themes.chunked(3)) {
                    val cards = LinearLayout(this)
                    for (theme in row) cards.addView(LinearLayout(this).apply {
                        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
                        val selected = currentPreset == theme[1]
                        background = makeCardDrawable(Color.parseColor(theme[2]), 12f,
                            if (selected) getAccentColor() else getDividerColor(), if (selected) 2 else 1)
                        addView(TextView(this@ReadiumReaderActivity).apply {
                            text = "Aa"; textSize = 20f; gravity = Gravity.CENTER
                            setTextColor(Color.parseColor(theme[3])); typeface = android.graphics.Typeface.SERIF
                        })
                        addView(TextView(this@ReadiumReaderActivity).apply {
                            text = theme[0]; textSize = 11f; gravity = Gravity.CENTER; setTextColor(Color.parseColor(theme[3]))
                            setPadding(0, dp(4), 0, 0)
                        })
                        contentDescription = "${theme[0]} theme${if (selected) ", selected" else ""}"
                        setOnClickListener { currentPreset = theme[1]; saveDurablePreferences(); applyPreferences(); render() }
                    }, LinearLayout.LayoutParams(0, dp(68), 1f).apply { setMargins(dp(4), dp(4), dp(4), dp(4)) })
                    layout.addView(cards)
                }
                if (canReflow) layout.addView(button("Customize", "Customize fonts and spacing") { customize = true; render() },
                    LinearLayout.LayoutParams(-1, dp(44)).apply { topMargin = dp(16) })
                layout.addView(button("Reset to defaults", "Reset reader settings to defaults") {
                    HonReaderBridge.instance?.resetBookReaderSettings(bookId) {
                        val globalPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        currentFontSize = globalPrefs.getFloat("readium_font_size", globalPrefs.getFloat(KEY_FONT_SIZE, 1.0f)).toDouble()
                        currentPreset = globalPrefs.getString("readium_theme", globalPrefs.getString(KEY_THEME, "calm") ?: "calm") ?: "calm"
                        isScrollMode = globalPrefs.getBoolean("readium_scroll_mode", globalPrefs.getBoolean(KEY_SCROLL, false))
                        prefs.edit().remove("readium_typography").apply()
                        applyPreferences()
                        render()
                        Toast.makeText(this@ReadiumReaderActivity, "Settings reset to defaults", Toast.LENGTH_SHORT).show()
                    }
                }, LinearLayout.LayoutParams(-1, dp(44)).apply { topMargin = dp(10) })
            } else {
                layout.addView(button("‹ Themes", "Back to themes") { customize = false; render() })
                label("Font Family")
                val fonts = listOf("georgia" to "Newsreader", "newYork" to "Literata", "sanFrancisco" to "System Sans", "palatino" to "Lora", "baskerville" to "Libre Baskerville")
                for ((key, name) in fonts) layout.addView(button(name, "Use $name") {
                    val next = typography().put("font", key).put("publisherStyles", false)
                    prefs.edit().putString("readium_typography", next.toString()).apply()
                    saveDurablePreferences(); applyPreferences(); render()
                }.apply {
                    if (values.optString("font", "georgia") == key && !values.optBoolean("publisherStyles", false)) {
                        text = "✓ $name"; setTextColor(getAccentColor())
                    }
                }, LinearLayout.LayoutParams(-1, dp(44)).apply { bottomMargin = dp(6) })
                label("Spacing")
                slider("lineHeight", "Line Spacing", 1.3, 2.2, 1.65)
                slider("margin", "Page Margins", 8.0, 48.0, 24.0)
                slider("paragraphSpacing", "Paragraph Spacing", 0.0, 32.0, 8.0)
                slider("indent", "First-line Indent", 0.0, 64.0, 24.0)
                for ((key, name, fallback) in listOf(Triple("justified", "Justify Text", true), Triple("publisherStyles", "Use publisher typography", false))) {
                    layout.addView(android.widget.Switch(this).apply {
                        text = name; textSize = 14f; setTextColor(primary); minHeight = dp(48)
                        isChecked = values.optBoolean(key, fallback)
                        setOnCheckedChangeListener { _, checked -> store(key, checked) }
                    })
                }
                layout.addView(button("Reset to defaults", "Reset reader settings to defaults") {
                    HonReaderBridge.instance?.resetBookReaderSettings(bookId) {
                        val globalPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        currentFontSize = globalPrefs.getFloat("readium_font_size", globalPrefs.getFloat(KEY_FONT_SIZE, 1.0f)).toDouble()
                        currentPreset = globalPrefs.getString("readium_theme", globalPrefs.getString(KEY_THEME, "calm") ?: "calm") ?: "calm"
                        isScrollMode = globalPrefs.getBoolean("readium_scroll_mode", globalPrefs.getBoolean(KEY_SCROLL, false))
                        prefs.edit().remove("readium_typography").apply()
                        applyPreferences()
                        render()
                        Toast.makeText(this@ReadiumReaderActivity, "Settings reset to defaults", Toast.LENGTH_SHORT).show()
                    }
                }, LinearLayout.LayoutParams(-1, dp(44)).apply { topMargin = dp(16) })
            }
            val scroll = object : ScrollView(this) {
                override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                    super.onMeasure(widthMeasureSpec, View.MeasureSpec.makeMeasureSpec((resources.displayMetrics.heightPixels * .88).toInt(), View.MeasureSpec.AT_MOST))
                }
            }.apply { addView(layout) }
            previousScroll = scroll
            if (!dialog.isShowing) showBottomSheet(dialog, scroll) else dialog.setContentView(scroll)
            scroll.post { scroll.scrollTo(0, offset.coerceAtMost(scroll.getChildAt(0).height)) }
        }
        render()
    }

    override fun onResume() {
        super.onResume()
        activeInstance = this
        updateSystemBars()
        if (readyReported && currentLocator != null) {
            HonReaderBridge.instance?.reportResumed(bookId, requestId)
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        val anchor = currentLocator
        super.onConfigurationChanged(newConfig)
        // The manifest keeps this Activity alive across rotation. Reapply the
        // Readium layout after the WebView receives its new viewport dimensions.
        window.decorView.post {
            applyPreferences()
            if (anchor != null) {
                window.decorView.postDelayed({ goReading(anchor); continuousReader?.reflow() }, 120L)
            }
        }
    }

    override fun onPause() {
        super.onPause()
        val loc = currentLocator
        if (loc != null) {
            val totalProg = computeTotalProgression(loc)
            HonReaderBridge.instance?.reportPaused(
                bookId,
                requestId,
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
        outState.putString("theme", currentPreset)
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
            requestId,
            locJson,
            totalProg
        )
    }

    fun closeIfWaiting(expectedRequestId: String) {
        if (requestId == expectedRequestId && !readyReported && !isFinishing) {
            finish()
        }
    }

    override fun finish() {
        notifyReaderClosed()
        super.finish()
    }

    override fun onDestroy() {
        if (isFinishing) notifyReaderClosed()
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
        locatorJob?.cancel()
        continuousReader?.dispose(removeFragments = false)
        continuousReader = null
        navigator = null
        super.onDestroy()
    }
}
