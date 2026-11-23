package app.quietfeed.firetv

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.view.Gravity
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.webkit.ScriptHandler
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONArray
import org.json.JSONObject

/**
 * One platform, filtered, driven like a TV app: the Fire TV counterpart of PlatformScreen +
 * WebModel. FilterEngine.js and NavigationGuard filter the site as on iPhone; TvNav.js moves a
 * highlight between the things you can select, and choosing a video opens it full screen with
 * native playback controls.
 *
 * Remote: arrows move between items, OK selects, Back goes back a page then closes, Menu opens
 * the menu (Home, Reload, Filters, Pointer mode, Close). In full-screen video: OK or play/pause
 * plays and pauses, left and right skip 10 seconds, Back leaves full screen.
 */
class PlayerActivity : Activity() {

    companion object {
        const val EXTRA_PLATFORM = "platform"
        private const val SEEK_SECONDS = 10
        private const val MOVE_INTERVAL_MS = 90L
    }

    private lateinit var platform: Platform
    private lateinit var experience: Experience.InApp
    private lateinit var prefs: Prefs
    private lateinit var store: RuleStore
    private lateinit var bridge: PageBridge
    private lateinit var guard: NavigationGuard
    private lateinit var engineSource: String
    private lateinit var tvNavSource: String
    private lateinit var pageScript: String

    private lateinit var root: FrameLayout
    private lateinit var webView: WebView
    private lateinit var cursor: CursorView
    private lateinit var progress: ProgressBar
    private var splash: View? = null
    private var menu: View? = null
    private var errorView: View? = null
    private lateinit var osd: LinearLayout
    private lateinit var osdTitle: TextView
    private lateinit var osdState: TextView
    private lateinit var osdTime: TextView
    private lateinit var osdBar: ProgressBar

    private var fullscreenView: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private var scriptHandler: ScriptHandler? = null
    private var usesFallbackInjection = false
    private var pointerMode = false
    private var firstLoadDone = false
    private var lastMoveAt = 0L
    private var touchDownTime = 0L

    private val hideOsd = Runnable { osd.animate().alpha(0f).setDuration(300).withEndAction { osd.visibility = View.GONE }.start() }
    private val pollOsd = object : Runnable {
        override fun run() {
            if (osd.visibility != View.VISIBLE) return
            media("status")
            osd.postDelayed(this, 500)
        }
    }

    // MARK: Setup

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = RuleStore.get(this)
        prefs = Prefs(this)
        bridge = PageBridge(prefs)
        platform = intent.getStringExtra(EXTRA_PLATFORM)?.let { store.platform(it) } ?: run { finish(); return }
        experience = Experience.of(platform.id) as? Experience.InApp ?: run { finish(); return }
        val rules = currentRules()
        guard = NavigationGuard(platform, rules)
        engineSource = asset("FilterEngine.js")
        tvNavSource = asset("TvNav.js")
        pageScript = buildPageScript(rules)

        root = FrameLayout(this).apply { setBackgroundColor(Ui.BG) }
        webView = WebView(this)
        cursor = CursorView(this).apply { visibility = View.GONE }
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progressTintList = ColorStateList.valueOf(Ui.ACCENT)
            visibility = View.GONE
        }
        root.addView(webView, FrameLayout.LayoutParams(match(), match()))
        root.addView(cursor, FrameLayout.LayoutParams(match(), match()))
        root.addView(progress, FrameLayout.LayoutParams(match(), dp(3), Gravity.TOP))
        buildOsd()
        showSplash()
        setContentView(root)

        configure(webView)
        webView.requestFocus()
        webView.loadUrl(platform.baseUrl)
    }

    private fun asset(name: String) = assets.open(name).bufferedReader().use { it.readText() }

    private fun currentRules() = store.enabledRules(platform.id, prefs.toggles(platform.id))

    private fun buildPageScript(rules: List<FilterRule>): String =
        PageBridge.SHIM + "\n" + engineSource + "\n" + bootScript(RuleStore.toEngineJson(rules)) + "\n" + tvNavSource +
            "\nwindow.__qfTv && window.__qfTv.configure({ autoFullscreen: ${experience.autoFullscreen} });"

    /**
     * Android runs document-start scripts before the <html> element exists (WebKit runs them just
     * after), and the engine writes its style into it on boot. So boot as soon as <html> appears:
     * the observer fires before the page's first script runs.
     */
    private fun bootScript(rulesJson: String): String = """
        (function () {
          var rules = $rulesJson;
          function boot() { window.__stillfeed && window.__stillfeed.boot(rules); }
          if (document.documentElement) { boot(); return; }
          new MutationObserver(function (_, observer) {
            if (!document.documentElement) return;
            observer.disconnect();
            boot();
          }).observe(document, { childList: true });
        })();
    """.trimIndent()

    @SuppressLint("SetJavaScriptEnabled", "RequiresFeature")
    private fun configure(view: WebView) {
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            setSupportMultipleWindows(false) // target=_blank links load here, through the guard
            // The rules are written for the mobile sites, so present as a phone browser.
            userAgentString = mobileUserAgent()
        }
        view.isVerticalScrollBarEnabled = false
        view.isHorizontalScrollBarEnabled = false
        if (WebViewFeature.isFeatureSupported(WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST)) {
            // Don't announce the app's package name to every site (Google sign-in checks it).
            WebSettingsCompat.setRequestedWithHeaderOriginAllowList(view.settings, emptySet())
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(view, true)
        installBridge(view)
        installScript(view)
        view.webViewClient = Client()
        view.webChromeClient = Chrome()
    }

    /**
     * As on iOS since the bridge was hardened, only the platform's own top-level page may report
     * to the app. The web message listener tells us the sender's origin; very old WebViews fall
     * back to a plain interface.
     */
    @SuppressLint("RequiresFeature", "JavascriptInterface")
    private fun installBridge(view: WebView) {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            try {
                WebViewCompat.addWebMessageListener(view, PageBridge.NAME, guard.messageOriginRules()) { _, message, origin, isMainFrame, _ ->
                    if (guard.isTrustedMessageOrigin(origin.host.orEmpty(), isMainFrame)) {
                        message.data?.let { bridge.handle(it) }
                    }
                }
                return
            } catch (e: IllegalArgumentException) {
                // Fall through to the interface.
            }
        }
        view.addJavascriptInterface(bridge, PageBridge.NAME)
    }

    /** Before the page's own scripts, as on iOS; very old WebViews get it as the page starts. */
    @SuppressLint("RequiresFeature")
    private fun installScript(view: WebView) {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            scriptHandler?.remove()
            scriptHandler = WebViewCompat.addDocumentStartJavaScript(view, pageScript, setOf("*"))
        } else {
            usesFallbackInjection = true
        }
    }

    private fun mobileUserAgent(): String {
        val chrome = Regex("Chrome/([\\d.]+)").find(WebSettings.getDefaultUserAgent(this))?.groupValues?.get(1)
            ?: "120.0.0.0"
        return "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chrome Mobile Safari/537.36"
    }

    private fun js(source: String, result: ((String?) -> Unit)? = null) {
        if (result == null) webView.evaluateJavascript(source, null)
        else webView.evaluateJavascript(source) { value -> result(value) }
    }

    /** evaluateJavascript hands back the JSON encoding of the result; our helpers return JSON strings. */
    private fun decodeJsonString(raw: String?): JSONObject? {
        if (raw == null || raw == "null") return null
        return try { JSONObject(JSONArray("[$raw]").getString(0)) } catch (e: Exception) { null }
    }

    // MARK: Remote

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val down = event.action == KeyEvent.ACTION_DOWN
        val up = event.action == KeyEvent.ACTION_UP
        val code = event.keyCode

        if (errorView != null) {
            if (code == KeyEvent.KEYCODE_BACK) { if (up) finish(); return true }
            return super.dispatchKeyEvent(event)
        }
        if (menu != null) {
            if (code == KeyEvent.KEYCODE_BACK || code == KeyEvent.KEYCODE_MENU) { if (up) closeMenu(); return true }
            return super.dispatchKeyEvent(event)
        }
        if (fullscreenView != null) return fullscreenKey(event)
        if (splash != null) {
            if (code == KeyEvent.KEYCODE_BACK && up) finish()
            return true
        }

        when (code) {
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT -> {
                if (down) arrow(code, event.repeatCount)
                return true
            }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                if (pointerMode) {
                    if (down && event.repeatCount == 0) touch(MotionEvent.ACTION_DOWN, cursor.x0, cursor.y0)
                    if (up) touch(MotionEvent.ACTION_UP, cursor.x0, cursor.y0)
                } else if (up) {
                    select()
                }
                return true
            }
            KeyEvent.KEYCODE_BACK -> {
                if (up) { if (webView.canGoBack()) webView.goBack() else finish() }
                return true
            }
            KeyEvent.KEYCODE_MENU -> { if (up) openMenu(); return true }
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                if (up) media("toggle"); return true
            }
            KeyEvent.KEYCODE_MEDIA_REWIND -> { if (down) media("seek:-$SEEK_SECONDS"); return true }
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { if (down) media("seek:$SEEK_SECONDS"); return true }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun arrow(code: Int, repeat: Int) {
        val (dx, dy, dir) = when (code) {
            KeyEvent.KEYCODE_DPAD_UP -> Triple(0, -1, "up")
            KeyEvent.KEYCODE_DPAD_DOWN -> Triple(0, 1, "down")
            KeyEvent.KEYCODE_DPAD_LEFT -> Triple(-1, 0, "left")
            else -> Triple(1, 0, "right")
        }
        if (pointerMode) {
            val step = dp(8) + dp(3) * minOf(repeat, 10)
            val (overX, overY) = cursor.moveBy((dx * step).toFloat(), (dy * step).toFloat())
            if (overX != 0f || overY != 0f) scrollAtPointer(dx, dy)
            return
        }
        // Holding an arrow repeats fast; one step per interval keeps the page smooth.
        val now = SystemClock.uptimeMillis()
        if (now - lastMoveAt < MOVE_INTERVAL_MS) return
        lastMoveAt = now
        js("window.__qfTv && window.__qfTv.move('$dir');")
    }

    /** Taps the highlighted item, natively, so the site sees a real gesture. */
    private fun select() {
        js("window.__qfTv ? window.__qfTv.activate() : null") { raw ->
            val target = decodeJsonString(raw) ?: return@js
            @Suppress("DEPRECATION")
            val scale = webView.scale
            val x = (target.optDouble("x") * scale).toFloat()
            val y = (target.optDouble("y") * scale).toFloat()
            touch(MotionEvent.ACTION_DOWN, x, y)
            webView.postDelayed({ touch(MotionEvent.ACTION_UP, x, y) }, 60)
        }
    }

    private fun touch(action: Int, x: Float, y: Float) {
        val now = SystemClock.uptimeMillis()
        if (action == MotionEvent.ACTION_DOWN) {
            touchDownTime = now
            if (!webView.hasFocus()) webView.requestFocus()
        }
        if (pointerMode) cursor.setDown(action == MotionEvent.ACTION_DOWN)
        val event = MotionEvent.obtain(touchDownTime, now, action, x, y, 0)
        event.source = InputDevice.SOURCE_TOUCHSCREEN
        webView.dispatchTouchEvent(event)
        event.recycle()
    }

    /** Pointer mode: scrolls whatever is scrollable under the pointer, unless a single reel is locked. */
    private fun scrollAtPointer(dx: Int, dy: Int) {
        if (guard.isSingleItem(webView.url?.let(Uri::parse))) return
        @Suppress("DEPRECATION")
        val scale = webView.scale
        val x = cursor.x0 / scale
        val y = cursor.y0 / scale
        val amount = 140
        js(
            """
            (function (x, y, dx, dy) {
              var el = document.elementFromPoint(x, y);
              while (el && el !== document.body && el !== document.documentElement) {
                var s = getComputedStyle(el);
                var canY = dy && /(auto|scroll)/.test(s.overflowY) && el.scrollHeight > el.clientHeight;
                var canX = dx && /(auto|scroll)/.test(s.overflowX) && el.scrollWidth > el.clientWidth;
                if (canY || canX) { el.scrollBy({ left: dx, top: dy, behavior: 'smooth' }); return; }
                el = el.parentElement;
              }
              window.scrollBy({ left: dx, top: dy, behavior: 'smooth' });
            })($x, $y, ${dx * amount}, ${dy * amount});
            """.trimIndent()
        )
    }

    // MARK: Video

    private fun fullscreenKey(event: KeyEvent): Boolean {
        val down = event.action == KeyEvent.ACTION_DOWN
        val up = event.action == KeyEvent.ACTION_UP
        when (event.keyCode) {
            KeyEvent.KEYCODE_BACK -> { if (up) exitFullscreen(); return true }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER,
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                if (up) media("toggle"); return true
            }
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_MEDIA_REWIND -> { if (down) media("seek:-$SEEK_SECONDS"); return true }
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { if (down) media("seek:$SEEK_SECONDS"); return true }
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_MENU -> { if (up) showOsd(); return true }
        }
        return super.dispatchKeyEvent(event)
    }

    /** Runs a playback command on the main video and shows the controls if it's full screen. */
    private fun media(cmd: String) {
        js("window.__qfTv ? window.__qfTv.media('$cmd') : null") { raw ->
            val status = decodeJsonString(raw) ?: return@js
            if (fullscreenView != null) {
                renderOsd(status)
                if (cmd != "status") showOsd()
            }
        }
    }

    private fun buildOsd() {
        osdTitle = text("", 22f, bold = true).apply { maxLines = 1 }
        osdState = text("▶", 26f, Ui.ACCENT, bold = true)
        osdTime = text("", 18f, Ui.TEXT_MUTED)
        osdBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000
            progressTintList = ColorStateList.valueOf(Ui.ACCENT)
            progressBackgroundTintList = ColorStateList.valueOf(Ui.BORDER)
        }
        osd = vertical(12) {
            visibility = View.GONE
            background = GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, intArrayOf(0xF0000000.toInt(), 0x00000000))
            setPadding(dp(56), dp(48), dp(56), dp(36))
            add(osdTitle)
            add(horizontal(20) {
                gravity = Gravity.CENTER_VERTICAL
                add(osdState, wrap())
                add(osdBar, 0, dp(6), 1f)
                add(osdTime, wrap())
            })
            add(text("OK  play / pause    ◀ ▶  10 seconds    Back  leave full screen", 15f, Ui.TEXT_MUTED))
        }
    }

    private fun renderOsd(status: JSONObject) {
        val t = status.optDouble("t", 0.0)
        val d = status.optDouble("d", 0.0)
        osdTitle.text = status.optString("title")
        osdState.text = if (status.optBoolean("paused")) "❚❚" else "▶"
        osdTime.text = if (d > 0) "${clock(t)} / ${clock(d)}" else clock(t)
        osdBar.progress = if (d > 0) ((t / d) * 1000).toInt() else 0
    }

    private fun clock(seconds: Double): String {
        val s = seconds.toLong()
        return if (s >= 3600) String.format(java.util.Locale.US, "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        else String.format(java.util.Locale.US, "%d:%02d", s / 60, s % 60)
    }

    private fun showOsd() {
        if (osd.parent == null) return
        osd.bringToFront()
        osd.animate().cancel()
        osd.alpha = 1f
        if (osd.visibility != View.VISIBLE) {
            osd.visibility = View.VISIBLE
            osd.post(pollOsd)
        }
        osd.removeCallbacks(hideOsd)
        osd.postDelayed(hideOsd, 4000)
    }

    private fun exitFullscreen() {
        js("window.__qfTv && window.__qfTv.exitFullscreen();")
        fullscreenCallback?.onCustomViewHidden()
        leaveFullscreenViews()
    }

    private fun leaveFullscreenViews() {
        fullscreenView?.let { root.removeView(it) }
        fullscreenView = null
        fullscreenCallback = null
        osd.removeCallbacks(hideOsd)
        root.removeView(osd)
        osd.visibility = View.GONE
        webView.visibility = View.VISIBLE
        if (pointerMode) cursor.visibility = View.VISIBLE
        webView.requestFocus()
    }

    // MARK: Loading screen

    private fun showSplash() {
        val view = FrameLayout(this).apply {
            setBackgroundColor(Ui.BG)
            isClickable = true
            addView(vertical(14) {
                gravity = Gravity.CENTER_HORIZONTAL
                add(text(Ui.glyph(platform.id), 72f, Ui.tint(platform.id), bold = true).apply { gravity = Gravity.CENTER }, wrap())
                add(text(platform.name, 36f, bold = true).apply { gravity = Gravity.CENTER }, wrap())
                add(ProgressBar(context).apply {
                    isIndeterminate = true
                    indeterminateTintList = ColorStateList.valueOf(Ui.ACCENT)
                }, dp(40), dp(40))
            }, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.CENTER))
        }
        splash = view
        root.addView(view, FrameLayout.LayoutParams(match(), match()))
        // Never leave someone stuck on the loading screen if the page is slow to say it's done.
        view.postDelayed({ hideSplash() }, 15000)
    }

    private fun hideSplash() {
        val view = splash ?: return
        splash = null
        firstLoadDone = true
        view.animate().alpha(0f).setDuration(250).withEndAction { root.removeView(view) }.start()
        // Start with something selected, as a TV app does.
        webView.postDelayed({ if (!pointerMode) js("window.__qfTv && window.__qfTv.move('down');") }, 700)
        if (!prefs.sawTvTip) {
            prefs.sawTvTip = true
            showTip("◀ ▲ ▼ ▶ move  ·  OK select  ·  ≡ menu  ·  Back go back")
        }
    }

    private fun showTip(message: String) {
        val tip = text(message, 18f).apply {
            setPadding(dp(24), dp(12), dp(24), dp(12))
            background = rounded(0xE6151C1D.toInt(), 999, Ui.BORDER, 1)
        }
        root.addView(tip, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
            bottomMargin = dp(32)
        })
        tip.postDelayed({ tip.animate().alpha(0f).setDuration(600).withEndAction { root.removeView(tip) }.start() }, 7000)
    }

    // MARK: Menu

    private fun openMenu() {
        if (menu != null) return
        val list = vertical(10) {
            setPadding(dp(32), dp(36), dp(32), dp(36))
            add(horizontal(14) {
                gravity = Gravity.CENTER_VERTICAL
                add(text(Ui.glyph(platform.id), 30f, Ui.tint(platform.id), bold = true), wrap())
                add(text(platform.name, 28f, bold = true), wrap())
            })
            add(View(context), match(), dp(8))
            add(menuRow("Home") { closeMenu(); webView.loadUrl(platform.baseUrl) })
            add(menuRow("Reload") { closeMenu(); reload() })
            add(switchRow("Pointer mode", "Move a pointer instead, for anything the highlight can't reach.", { pointerMode }) { on ->
                setPointerMode(on)
            })
            val toggles = store.toggles(platform.id)
            if (toggles.isNotEmpty()) {
                add(text("Filters", 18f, Ui.TEXT_MUTED, bold = true).apply { setPadding(0, dp(16), 0, 0) })
                toggles.forEach { toggle ->
                    add(switchRow(toggle.title, toggle.detail, { prefs.toggles(platform.id)[toggle.key] ?: toggle.defaultOn }) { on ->
                        prefs.setToggle(platform.id, toggle.key, on)
                        applyRules()
                    })
                }
            }
            add(View(context), match(), dp(8))
            add(menuRow("Close ${platform.name}") { finish() })
        }
        val panel = ScrollView(this).apply {
            isFillViewport = true
            background = GradientDrawable().apply { setColor(Ui.SURFACE) }
            addView(list)
        }
        val scrim = FrameLayout(this).apply {
            setBackgroundColor(0x99000000.toInt())
            isClickable = true
            addView(panel, FrameLayout.LayoutParams(dp(440), match(), Gravity.START))
        }
        menu = scrim
        root.addView(scrim, FrameLayout.LayoutParams(match(), match()))
        list.post { list.getChildAt(2).requestFocus() }
    }

    private fun menuRow(label: String, onClick: () -> Unit): View =
        text(label, 20f, bold = true).apply {
            setPadding(dp(24), dp(16), dp(24), dp(16))
            background = focusBackground(16)
            makeFocusable(1.02f, onClick)
        }

    private fun closeMenu() {
        menu?.let { root.removeView(it) }
        menu = null
        webView.requestFocus()
    }

    private fun setPointerMode(on: Boolean) {
        pointerMode = on
        cursor.visibility = if (on) View.VISIBLE else View.GONE
        if (on) {
            cursor.wake()
            js("window.__qfTv && window.__qfTv.clear();")
        }
    }

    /** A filter switch changed: the guard, future pages and the open page all follow at once. */
    private fun applyRules() {
        val rules = currentRules()
        guard = NavigationGuard(platform, rules)
        pageScript = buildPageScript(rules)
        installScript(webView)
        js("window.__stillfeed && window.__stillfeed.update(${RuleStore.toEngineJson(rules)});")
    }

    private fun reload() {
        hideError()
        if (webView.url == null) webView.loadUrl(platform.baseUrl) else webView.reload()
    }

    // MARK: Errors

    private fun showError(offline: Boolean) {
        if (errorView != null) return
        splash?.let { root.removeView(it); splash = null; firstLoadDone = true }
        val panel = vertical(16) {
            background = rounded(Ui.SURFACE, 24, Ui.BORDER, 1)
            setPadding(dp(40), dp(32), dp(40), dp(32))
            gravity = Gravity.CENTER_HORIZONTAL
            add(text(if (offline) "You're offline" else "${platform.name} didn't load", 30f, bold = true), wrap())
            add(text("Check your connection and try again.", 18f, Ui.TEXT_MUTED), wrap())
            add(horizontal(16) {
                add(pillButton("Try again", primary = true) { reload() }, wrap())
                add(pillButton("Close") { finish() }, wrap())
            }, wrap())
        }
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(0xF00C1112.toInt())
            addView(panel, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.CENTER))
        }
        errorView = overlay
        root.addView(overlay, FrameLayout.LayoutParams(match(), match()))
        panel.post { ((panel.getChildAt(2) as ViewGroup).getChildAt(0)).requestFocus() }
    }

    private fun hideError() {
        errorView?.let { root.removeView(it) }
        errorView = null
        webView.requestFocus()
    }

    // MARK: Web view callbacks

    private inner class Chrome : WebChromeClient() {
        override fun onProgressChanged(view: WebView, newProgress: Int) {
            progress.progress = newProgress
            progress.visibility = if (firstLoadDone && newProgress < 100) View.VISIBLE else View.GONE
        }

        override fun onShowCustomView(view: View, callback: CustomViewCallback) {
            if (fullscreenView != null) { callback.onCustomViewHidden(); return }
            fullscreenView = view
            fullscreenCallback = callback
            root.addView(view, FrameLayout.LayoutParams(match(), match()))
            root.addView(osd, FrameLayout.LayoutParams(match(), wrap(), Gravity.BOTTOM))
            webView.visibility = View.INVISIBLE
            cursor.visibility = View.GONE
            media("status")
            showOsd()
        }

        override fun onHideCustomView() {
            leaveFullscreenViews()
        }

        /** No grey play-button placeholder before a video starts. */
        override fun getDefaultVideoPoster(): Bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    }

    private inner class Client : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
            when (val decision = guard.decide(request.url, request.isForMainFrame)) {
                NavigationGuard.Decision.Allow -> false
                is NavigationGuard.Decision.Redirect -> { view.loadUrl(decision.url); true }
                is NavigationGuard.Decision.External -> { openOutside(decision.url); true }
                NavigationGuard.Decision.Cancel -> true
            }

        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
            if (usesFallbackInjection) view.evaluateJavascript(pageScript, null)
        }

        override fun onPageFinished(view: WebView, url: String?) {
            if (splash != null) view.postDelayed({ hideSplash() }, 400)
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (!request.isForMainFrame) return
            val offline = error.errorCode == ERROR_HOST_LOOKUP || error.errorCode == ERROR_CONNECT ||
                error.errorCode == ERROR_TIMEOUT
            showError(offline)
        }

        /** The page's renderer crashed: start the screen again rather than show a dead page. */
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            recreate() // onDestroy releases the dead web view
            return true
        }
    }

    private fun openOutside(url: String) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, "That link opens outside ${platform.name}.", Toast.LENGTH_SHORT).show()
        }
    }

    // MARK: Lifecycle

    override fun onResume() {
        super.onResume()
        if (::webView.isInitialized) webView.onResume()
    }

    override fun onPause() {
        if (::webView.isInitialized) webView.onPause()
        CookieManager.getInstance().flush()
        super.onPause()
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            root.removeView(webView)
            webView.destroy()
        }
        super.onDestroy()
    }
}
