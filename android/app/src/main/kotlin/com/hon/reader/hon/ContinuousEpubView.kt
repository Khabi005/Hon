package com.hon.reader.hon

import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.NestedScrollView
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.json.JSONTokener
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.KeyEvent
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

/**
 * A bounded vertical window of original EPUB resources. Each resource remains a
 * Readium navigator with its own document, CSS, resource resolver and selection.
 * Only the outer viewport scrolls; chapters are never flattened or concatenated.
 */
internal class ContinuousEpubView(
    private val activity: AppCompatActivity,
    private val container: FrameLayout,
    private val publication: Publication,
    private val configuration: (() -> EpubNavigatorFragment?) -> EpubNavigatorFragment.Configuration,
    private val onTap: () -> Unit,
    private val onLocator: (EpubNavigatorFragment, Locator) -> Unit,
    private val onReady: () -> Unit,
    private val onExternalLink: (String) -> Unit,
    private val onFailure: (String) -> Unit,
    initialPreferences: EpubPreferences,
    initialLocator: Locator?,
) {
    private class Page(val index: Int, val frame: FrameLayout) {
        var navigator: EpubNavigatorFragment? = null
        var loaded = false
        var cssWidth = 0.0
        var cssHeight = 0.0
        var anchorJob: Job? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private val pages = sortedMapOf<Int, Page>()
    private val heights = mutableMapOf<Int, Int>()
    private var preferences = initialPreferences.copy(scroll = true)
    private var pendingLocator = initialLocator ?: publication.locatorFromLink(publication.readingOrder.first())
    private var activeIndex = indexOf(pendingLocator?.href?.toString()).coerceAtLeast(0)
    private var changingWindow = false
    private var disposed = false
    private var restoreGeneration = 0
    private var lastLocator: Locator? = pendingLocator
    private var lastAnchorAt = 0L
    private var reportedReady = false
    private var failed = false
    var selectionActive = false
    private val activeDecorations = mutableMapOf<String, List<Decoration>>()
    private val column = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val scroll = object : NestedScrollView(activity) {
        override fun requestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {
            // Readium's horizontal pager must not capture vertical drags. Native
            // text-selection handles retain control while ActionMode is active.
            super.requestDisallowInterceptTouchEvent(disallowIntercept && selectionActive)
        }
        override fun onInterceptTouchEvent(event: MotionEvent): Boolean =
            !selectionActive && super.onInterceptTouchEvent(event)
    }.apply {
        isFillViewport = false
        isSmoothScrollingEnabled = false
        clipToPadding = true
        overScrollMode = View.OVER_SCROLL_NEVER
        addView(column, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        setOnScrollChangeListener(NestedScrollView.OnScrollChangeListener { _, _, _, _, _ -> scrolled() })
    }
    private val prune = Runnable {
        if (!disposed && pendingLocator == null) reconcile(activeIndex)
    }
    private val restore = Runnable { restorePending() }
    private val captureIdle = Runnable {
        if (!disposed && pendingLocator == null && !changingWindow) {
            val page = pages[activeIndex]
            val locator = lastLocator
            if (page != null && page.loaded && locator != null) {
                captureTextAnchor(page, locator, (scroll.scrollY - page.frame.top).coerceAtLeast(0))
            }
        }
    }

    init {
        container.addView(scroll, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        reconcile(activeIndex)
    }

    private fun indexOf(href: String?): Int {
        if (href == null) return -1
        val clean = href.substringBefore('#')
        return publication.readingOrder.indexOfFirst { it.url().toString().substringBefore('#') == clean }
    }

    private fun newPage(index: Int): Page {
        val frame = FrameLayout(activity).apply {
            id = View.generateViewId()
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                heights[index] ?: container.height.coerceAtLeast(activity.resources.displayMetrics.heightPixels / 2))
        }
        val page = Page(index, frame)
        pages[index] = page
        // Attach the frame before committing a child navigator into it.
        val insertion = pages.keys.indexOf(index)
        column.addView(frame, insertion.coerceAtMost(column.childCount))
        val config = configuration { page.navigator }.apply {
            disablePageTurnsWhileScrolling = true
            registerJavascriptInterface("HonContinuous") { Metrics(page) }
        }
        val listener = object : EpubNavigatorFragment.Listener {
            override fun shouldFollowInternalLink(link: Link, context: org.readium.r2.navigator.HyperlinkNavigator.LinkContext?): Boolean {
                val locator = publication.locatorFromLink(link)
                if (locator != null && indexOf(locator.href.toString()) >= 0) go(locator)
                return false
            }
            override fun onExternalLinkActivated(url: org.readium.r2.shared.util.AbsoluteUrl) {
                onExternalLink(url.toString())
            }
            override fun onResourceLoadFailed(href: org.readium.r2.shared.util.Url, error: org.readium.r2.shared.util.data.ReadError) {
                fail("Could not load EPUB chapter ${index + 1}: $error")
            }
        }
        val factory = EpubNavigatorFactory(publication).createFragmentFactory(
            initialLocator = publication.locatorFromLink(publication.readingOrder[index]),
            readingOrder = listOf(publication.readingOrder[index]),
            initialPreferences = preferences,
            listener = listener,
            paginationListener = object : EpubNavigatorFragment.PaginationListener {
                override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) = Unit
                override fun onPageLoaded() {
                    installMetrics(page)
                    for ((group, decs) in activeDecorations) {
                        activity.lifecycleScope.launch {
                            page.navigator?.applyDecorations(decs, group)
                        }
                    }
                }
            },
            configuration = config,
        )
        val fragment = factory.instantiate(activity.classLoader, EpubNavigatorFragment::class.java.name) as EpubNavigatorFragment
        page.navigator = fragment
        fragment.addInputListener(object : InputListener {
            override fun onTap(event: TapEvent): Boolean { onTap(); return true }
            override fun onKey(event: KeyEvent): Boolean = false
        })
        activity.supportFragmentManager.beginTransaction().add(frame.id, fragment, "hon_continuous_$index").commitNow()
        return page
    }

    private fun reconcile(center: Int) {
        if (disposed || changingWindow || activity.supportFragmentManager.isStateSaved) return
        changingWindow = true
        val active = pages[activeIndex]
        val relative = active?.let { scroll.scrollY - it.frame.top } ?: 0
        val wanted = ((center - 1).coerceAtLeast(0)..(center + 1).coerceAtMost(publication.readingOrder.lastIndex)).toSet()
        for (index in pages.keys.toList()) {
            if (index in wanted) continue
            val page = pages.remove(index) ?: continue
            page.anchorJob?.cancel()
            page.navigator?.let { activity.supportFragmentManager.beginTransaction().remove(it).commitNow() }
            column.removeView(page.frame)
        }
        for (index in wanted.sorted()) if (!pages.containsKey(index)) newPage(index)
        column.post {
            if (disposed) return@post
            if (pendingLocator == null) pages[activeIndex]?.let { scroll.scrollTo(0, (it.frame.top + relative).coerceAtLeast(0)) }
            changingWindow = false
            if (!pages.containsKey(activeIndex)) reconcile(activeIndex) else restorePending()
        }
    }

    private inner class Metrics(private val page: Page) {
        @JavascriptInterface fun resized(height: Double, width: Double) {
            handler.post {
                if (disposed || pages[page.index] !== page || !height.isFinite() || !width.isFinite() || width < 1 || height < 1) return@post
                val scale = page.frame.width / width
                if (scale <= 0) return@post
                if (height * scale > 8_000_000) {
                    fail("This EPUB chapter exceeds the continuous viewport size limit.")
                    return@post
                }
                val pixels = (height * scale).toInt().coerceAtLeast(1)
                page.cssWidth = width
                page.cssHeight = height
                page.loaded = true
                if (page.frame.layoutParams.height != pixels) {
                    val anchor = lastLocator
                    if (pendingLocator == null && anchor != null) pendingLocator = anchor
                    page.frame.layoutParams = (page.frame.layoutParams as LinearLayout.LayoutParams).apply { this.height = pixels }
                    heights[page.index] = pixels
                }
                handler.removeCallbacks(restore)
                handler.postDelayed(restore, 80)
            }
        }
    }

    private fun fail(message: String) {
        if (disposed || failed) return
        failed = true
        handler.post { if (!disposed) onFailure(message) }
    }

    private fun installMetrics(page: Page) {
        if (disposed || pages[page.index] !== page) return
        activity.lifecycleScope.launch {
            page.navigator?.evaluateJavascript("""
                (function() {
                  if (window.__honResizeObserver) window.__honResizeObserver.disconnect();
                  let scheduled = false;
                  function report() {
                    if (scheduled) return;
                    scheduled = true;
                    requestAnimationFrame(function() {
                      scheduled = false;
                      const root = document.documentElement;
                      const body = document.body;
                      if (!body || !root) return;
                      const range = document.createRange();
                      range.selectNodeContents(body);
                      const style = getComputedStyle(body);
                      const bottom = range.getBoundingClientRect().bottom + window.scrollY + parseFloat(style.paddingBottom || 0) + parseFloat(style.marginBottom || 0);
                      HonContinuous.resized(Math.max(1, bottom), root.clientWidth);
                    });
                  }
                  window.__honResizeObserver = new ResizeObserver(report);
                  window.__honResizeObserver.observe(document.documentElement);
                  window.__honResizeObserver.observe(document.body);
                  document.querySelectorAll('img').forEach(function(image) { image.addEventListener('load', report); });
                  if (document.fonts) document.fonts.ready.then(report);
                  report();
                })();
            """.trimIndent())
        }
    }

    private fun restorePending() {
        if (disposed || changingWindow) return
        val locator = pendingLocator ?: return
        val index = indexOf(locator.href.toString()).takeIf { it >= 0 } ?: activeIndex
        val page = pages[index] ?: return
        if (!page.loaded || page.frame.width <= 0) return
        val generation = ++restoreGeneration
        activity.lifecycleScope.launch {
            val selector = locator.locations.otherLocations["cssSelector"] as? String
            val textOffset = (locator.locations.otherLocations["honTextOffset"] as? Number)?.toInt()
            val fragment = locator.locations.fragments.firstOrNull()
            val target = selector ?: fragment?.let { "#" + it.substringAfter('#').replace(Regex("[^a-zA-Z0-9_-]"), "\\$0") }
            var cssTop: Double? = null
            if (target != null) {
                val script = """
                    (function() {
                      const element = document.querySelector(${JSONObject.quote(target)});
                      if (!element) return -1;
                      let offset = ${textOffset ?: -1};
                      if (offset >= 0) {
                        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                        let node;
                        while ((node = walker.nextNode())) {
                          if (offset <= node.length) {
                            const range = document.createRange();
                            range.setStart(node, offset); range.setEnd(node, Math.min(node.length, offset + 1));
                            return range.getBoundingClientRect().top + window.scrollY;
                          }
                          offset -= node.length;
                        }
                      }
                      return element.getBoundingClientRect().top + window.scrollY;
                    })();
                """.trimIndent()
                cssTop = page.navigator?.evaluateJavascript(script)?.toDoubleOrNull()?.takeIf { it >= 0 }
            }
            if (disposed || generation != restoreGeneration || pendingLocator !== locator) return@launch
            val within = cssTop?.let { it * page.frame.width / page.cssWidth }
                ?: ((locator.locations.progression ?: 0.0) * page.frame.height)
            activeIndex = index
            scroll.scrollTo(0, (page.frame.top + within).toInt().coerceAtLeast(0))
            pendingLocator = null
            lastLocator = locator
            page.navigator?.let { onLocator(it, locator) }
            handler.removeCallbacks(captureIdle)
            handler.postDelayed(captureIdle, 120)
            if (!reportedReady) { reportedReady = true; onReady() }
        }
    }

    private fun scrolled() {
        if (disposed || changingWindow || pendingLocator != null) return
        val page = pages.values.firstOrNull { it.frame.bottom > scroll.scrollY } ?: return
        if (!page.loaded) return
        activeIndex = page.index
        val local = (scroll.scrollY - page.frame.top).coerceAtLeast(0)
        val progression = (local.toDouble() / page.frame.height.coerceAtLeast(1)).coerceIn(0.0, 1.0)
        val base = publication.locatorFromLink(publication.readingOrder[page.index]) ?: return
        val locator = base.copy(locations = Locator.Locations(progression = progression))
        lastLocator = locator
        page.navigator?.let { onLocator(it, locator) }
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - lastAnchorAt >= 180L) {
            lastAnchorAt = now
            captureTextAnchor(page, locator, local)
        }
        handler.removeCallbacks(prune)
        handler.postDelayed(prune, 180)
        handler.removeCallbacks(captureIdle)
        handler.postDelayed(captureIdle, 120)
    }

    private fun captureTextAnchor(page: Page, locator: Locator, local: Int) {
        page.anchorJob?.cancel()
        page.anchorJob = activity.lifecycleScope.launch {
            val y = local * page.cssWidth / page.frame.width.coerceAtLeast(1)
            val script = """
                (function() {
                  const y = Math.max(1, $y + 2);
                  const x = Math.min(document.documentElement.clientWidth - 2, Math.max(8, document.body.getBoundingClientRect().left + 8));
                  const range = document.caretRangeFromPoint ? document.caretRangeFromPoint(x, y) : null;
                  let element = range && range.startContainer.nodeType === 3 ? range.startContainer.parentElement : document.elementFromPoint(x, y);
                  if (!element) return null;
                  while (element.parentElement && !/^(P|LI|H[1-6]|DIV|BLOCKQUOTE|FIGCAPTION)$/.test(element.tagName)) element = element.parentElement;
                  const path = [];
                  let node = element;
                  while (node && node !== document.documentElement) {
                    const parent = node.parentElement;
                    const index = parent ? Array.prototype.indexOf.call(parent.children, node) + 1 : 1;
                    path.unshift(node.tagName.toLowerCase() + ':nth-child(' + index + ')');
                    node = parent;
                  }
                  let offset = -1;
                  if (range && element.contains(range.startContainer)) {
                    const prefix = document.createRange();
                    prefix.selectNodeContents(element); prefix.setEnd(range.startContainer, range.startOffset);
                    offset = prefix.toString().length;
                  }
                  const text = element.textContent || '';
                  return JSON.stringify({selector: path.length ? 'html > ' + path.join(' > ') : 'html', offset: offset, before: text.slice(Math.max(0, offset - 32), offset), highlight: text.slice(Math.max(0, offset), Math.max(0, offset) + 64)});
                })();
            """.trimIndent()
            val result = page.navigator?.evaluateJavascript(script) ?: return@launch
            val value = try { JSONTokener(result).nextValue() } catch (_: Exception) { null }
            val data = try { if (value is String) JSONObject(value) else null } catch (_: Exception) { null } ?: return@launch
            if (disposed || activeIndex != page.index || pendingLocator != null || lastLocator !== locator) return@launch
            val other = mutableMapOf<String, Any>("cssSelector" to data.getString("selector"))
            if (data.optInt("offset", -1) >= 0) other["honTextOffset"] = data.getInt("offset")
            val anchored = locator.copy(locations = locator.locations.copy(otherLocations = other), text = Locator.Text(before = data.optString("before").takeIf { it.isNotEmpty() }, highlight = data.optString("highlight").takeIf { it.isNotEmpty() }))
            lastLocator = anchored
            page.navigator?.let { onLocator(it, anchored) }
        }
    }

    fun go(locator: Locator): Boolean {
        val index = indexOf(locator.href.toString())
        if (index < 0 || disposed) return false
        pendingLocator = locator
        lastLocator = locator
        activeIndex = index
        reconcile(index)
        handler.post(restore)
        return true
    }

    fun go(link: Link): Boolean = publication.locatorFromLink(link)?.let { go(it) } ?: false

    fun move(forward: Boolean): Boolean {
        val delta = (scroll.height * 0.85).toInt() * if (forward) 1 else -1
        scroll.smoothScrollBy(0, delta)
        return true
    }

    fun submitPreferences(value: EpubPreferences) {
        if (disposed) return
        pendingLocator = lastLocator
        preferences = value.copy(scroll = true)
        for (page in pages.values) page.navigator?.submitPreferences(preferences)
        handler.removeCallbacks(restore)
        handler.postDelayed(restore, 160)
    }

    fun reflow() {
        if (disposed) return
        pendingLocator = lastLocator
        for (page in pages.values) installMetrics(page)
        handler.postDelayed(restore, 160)
    }

    fun applyDecorations(decorations: List<Decoration>, group: String) {
        if (disposed) return
        activeDecorations[group] = decorations
        for (page in pages.values) {
            activity.lifecycleScope.launch {
                page.navigator?.applyDecorations(decorations, group)
            }
        }
    }

    fun dispose(removeFragments: Boolean = true) {
        if (disposed) return
        disposed = true
        handler.removeCallbacksAndMessages(null)
        for (page in pages.values) {
            page.anchorJob?.cancel()
            if (removeFragments && !activity.supportFragmentManager.isDestroyed) {
                page.navigator?.let { activity.supportFragmentManager.beginTransaction().remove(it).commitNowAllowingStateLoss() }
            }
        }
        pages.clear()
        container.removeView(scroll)
    }
}
