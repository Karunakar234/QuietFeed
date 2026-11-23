package app.quietfeed.firetv

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
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
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/**
 * One platform, filtered: the Fire TV counterpart of PlatformScreen + WebModel. The same
 * FilterEngine.js runs in the page, NavigationGuard and AdBlocker run natively, and the remote
 * drives an on-screen pointer, because these sites are built for touch.
 *
 * Remote: arrows move the pointer (and scroll at the screen's edge), center taps (hold to
 * long-press), Back goes back a page then closes, Menu reloads, play/pause and
 * rewind/fast-forward control the video.
 */
class PlayerActivity : Activity() {

    companion object {
        const val EXTRA_PLATFORM = "platform"
        private const val SEEK_SECONDS = 10
    }

    private lateinit var platform: Platform
    private lateinit var guard: NavigationGuard
    private lateinit var root: FrameLayout
    private lateinit var webView: WebView
    private lateinit var cursor: CursorView
    private lateinit var progress: ProgressBar
    private var errorView: View? = null
    private var fullscreenView: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private var touchDownTime = 0L
    private var usesFallbackInjection = false
    private lateinit var pageScript: String

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val store = RuleStore.get(this)
        val prefs = Prefs(this)
        platform = intent.getStringExtra(EXTRA_PLATFORM)?.let { store.platform(it) } ?: run { finish(); return }
        val rules = store.enabledRules(platform.id, prefs.toggles(platform.id))
        guard = NavigationGuard(platform, rules)

        val engine = assets.open("FilterEngine.js").bufferedReader().use { it.readText() }
        pageScript = PageBridge.SHIM + "\n" + engine + "\n" + bootScript(RuleStore.toEngineJson(rules))

        root = FrameLayout(this).apply { setBackgroundColor(Ui.BG) }
        webView = WebView(this)
        cursor = CursorView(this)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progressTintList = ColorStateList.valueOf(Ui.ACCENT)
        }
        root.addView(webView, FrameLayout.LayoutParams(match(), match()))
        root.addView(cursor, FrameLayout.LayoutParams(match(), match()))
        root.addView(progress, FrameLayout.LayoutParams(match(), dp(4), Gravity.TOP))
        setContentView(root)

        configure(webView, prefs)
        webView.requestFocus()
        webView.loadUrl(platform.baseUrl)
        showHint()
    }

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
    private fun configure(view: WebView, prefs: Prefs) {
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            setSupportMultipleWindows(false) // target=_blank links load here, through the guard
            // The rules are written for the mobile sites, so present as a phone browser.
            userAgentString = mobileUserAgent()
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST)) {
            // Don't announce the app's package name to every site (Google sign-in checks it).
            WebSettingsCompat.setRequestedWithHeaderOriginAllowList(view.settings, emptySet())
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(view, true)
        view.addJavascriptInterface(PageBridge(prefs), PageBridge.NAME)

        // Before the page's own scripts, as on iOS; very old WebViews get it as the page starts.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(view, pageScript, setOf("*"))
        } else {
            usesFallbackInjection = true
        }

        view.webViewClient = Client()
        view.webChromeClient = Chrome()
    }

    private fun mobileUserAgent(): String {
        val chrome = Regex("Chrome/([\\d.]+)").find(WebSettings.getDefaultUserAgent(this))?.groupValues?.get(1)
            ?: "120.0.0.0"
        return "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chrome Mobile Safari/537.36"
    }

    // MARK: Remote

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val down = event.action == KeyEvent.ACTION_DOWN
        val up = event.action == KeyEvent.ACTION_UP

        errorView?.let {
            if (event.keyCode == KeyEvent.KEYCODE_BACK) { if (up) finish(); return true }
            return super.dispatchKeyEvent(event)
        }

        if (fullscreenView != null) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK -> { if (up) exitFullscreen(); return true }
                KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                    if (up) togglePlayback(); return true
                }
                KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_MEDIA_REWIND -> { if (down) seek(-SEEK_SECONDS); return true }
                KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { if (down) seek(SEEK_SECONDS); return true }
            }
            return super.dispatchKeyEvent(event)
        }

        when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> { if (down) move(0, -1, event.repeatCount); return true }
            KeyEvent.KEYCODE_DPAD_DOWN -> { if (down) move(0, 1, event.repeatCount); return true }
            KeyEvent.KEYCODE_DPAD_LEFT -> { if (down) move(-1, 0, event.repeatCount); return true }
            KeyEvent.KEYCODE_DPAD_RIGHT -> { if (down) move(1, 0, event.repeatCount); return true }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                if (down && event.repeatCount == 0) touch(MotionEvent.ACTION_DOWN)
                if (up) touch(MotionEvent.ACTION_UP)
                return true
            }
            KeyEvent.KEYCODE_BACK -> {
                if (up) { if (webView.canGoBack()) webView.goBack() else finish() }
                return true
            }
            KeyEvent.KEYCODE_MENU -> { if (up) reload(); return true }
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                if (up) togglePlayback(); return true
            }
            KeyEvent.KEYCODE_MEDIA_REWIND -> { if (down) seek(-SEEK_SECONDS); return true }
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { if (down) seek(SEEK_SECONDS); return true }
        }
        return super.dispatchKeyEvent(event)
    }

    /** Moves the pointer, faster the longer an arrow is held; pushing past an edge scrolls. */
    private fun move(dx: Int, dy: Int, repeat: Int) {
        val step = dp(8) + dp(3) * minOf(repeat, 10)
        val (overX, overY) = cursor.moveBy((dx * step).toFloat(), (dy * step).toFloat())
        if (overX != 0f || overY != 0f) scrollPage(dx, dy)
    }

    /**
     * Scrolls whatever is scrollable under the pointer (these sites scroll inner panes, not the
     * window), falling back to the window. Not on a single reel, which the filters keep still.
     */
    private fun scrollPage(dx: Int, dy: Int) {
        if (guard.isSingleItem(webView.url?.let(Uri::parse))) return
        val density = resources.displayMetrics.density
        val x = cursor.x0 / density
        val y = cursor.y0 / density
        val amount = 140
        webView.evaluateJavascript(
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
            """.trimIndent(),
            null,
        )
    }

    /** A real touch at the pointer, so every site reacts as it would to a finger. */
    private fun touch(action: Int) {
        val now = SystemClock.uptimeMillis()
        if (action == MotionEvent.ACTION_DOWN) {
            touchDownTime = now
            if (!webView.hasFocus()) webView.requestFocus()
        }
        cursor.setDown(action == MotionEvent.ACTION_DOWN)
        val event = MotionEvent.obtain(touchDownTime, now, action, cursor.x0, cursor.y0, 0)
        event.source = InputDevice.SOURCE_TOUCHSCREEN
        webView.dispatchTouchEvent(event)
        event.recycle()
    }

    private fun togglePlayback() {
        webView.evaluateJavascript(
            """
            (function () {
              var media = document.querySelector('video');
              if (!media) return;
              if (media.paused) { media.play().catch(function () {}); } else { media.pause(); }
            })();
            """.trimIndent(),
            null,
        )
    }

    private fun seek(seconds: Int) {
        webView.evaluateJavascript(
            "(function(){var m=document.querySelector('video');if(m&&isFinite(m.duration))" +
                "{m.currentTime=Math.min(m.duration,Math.max(0,m.currentTime+($seconds)));}})();",
            null,
        )
    }

    private fun reload() {
        hideError()
        if (webView.url == null) webView.loadUrl(platform.baseUrl) else webView.reload()
    }

    private fun showHint() {
        val hint = text("Arrows move the pointer  ·  Center selects  ·  Back goes back  ·  Menu reloads", 18f).apply {
            setPadding(dp(24), dp(12), dp(24), dp(12))
            background = rounded(0xE6151C1D.toInt(), 999, Ui.BORDER, 1)
        }
        root.addView(hint, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
            bottomMargin = dp(32)
        })
        hint.postDelayed({ hint.animate().alpha(0f).setDuration(600).withEndAction { root.removeView(hint) }.start() }, 6000)
    }

    // MARK: Errors

    private fun showError(offline: Boolean) {
        if (errorView != null) return
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
            setBackgroundColor(0xCC0C1112.toInt())
            addView(panel, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.CENTER))
        }
        errorView = overlay
        root.addView(overlay, FrameLayout.LayoutParams(match(), match()))
        panel.post { (((panel.getChildAt(2) as ViewGroup).getChildAt(0))).requestFocus() }
    }

    private fun hideError() {
        errorView?.let { root.removeView(it) }
        errorView = null
        webView.requestFocus()
    }

    // MARK: Fullscreen video

    private fun exitFullscreen() {
        fullscreenCallback?.onCustomViewHidden()
        fullscreenView?.let { root.removeView(it) }
        fullscreenView = null
        fullscreenCallback = null
        webView.visibility = View.VISIBLE
        cursor.visibility = View.VISIBLE
    }

    private inner class Chrome : WebChromeClient() {
        override fun onProgressChanged(view: WebView, newProgress: Int) {
            progress.progress = newProgress
            progress.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
        }

        override fun onShowCustomView(view: View, callback: CustomViewCallback) {
            if (fullscreenView != null) { callback.onCustomViewHidden(); return }
            fullscreenView = view
            fullscreenCallback = callback
            root.addView(view, FrameLayout.LayoutParams(match(), match()))
            webView.visibility = View.INVISIBLE
            cursor.visibility = View.GONE
        }

        override fun onHideCustomView() {
            fullscreenView?.let { root.removeView(it) }
            fullscreenView = null
            fullscreenCallback = null
            webView.visibility = View.VISIBLE
            cursor.visibility = View.VISIBLE
        }

        /** No grey play-button placeholder before a video starts. */
        override fun getDefaultVideoPoster(): Bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    }

    // MARK: Navigation

    private inner class Client : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
            when (val decision = guard.decide(request.url, request.isForMainFrame)) {
                NavigationGuard.Decision.Allow -> false
                is NavigationGuard.Decision.Redirect -> { view.loadUrl(decision.url); true }
                is NavigationGuard.Decision.External -> { openOutside(decision.url); true }
                NavigationGuard.Decision.Cancel -> true
            }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
            if (AdBlocker.shouldBlock(request.url)) AdBlocker.emptyResponse() else null

        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
            if (usesFallbackInjection) view.evaluateJavascript(pageScript, null)
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
