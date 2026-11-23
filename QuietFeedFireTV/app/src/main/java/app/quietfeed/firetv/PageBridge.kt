package app.quietfeed.firetv

import android.webkit.JavascriptInterface
import org.json.JSONObject

/**
 * Receives FilterEngine.js's messages. On iOS they arrive through
 * window.webkit.messageHandlers.stillfeed; on Android a small shim forwards them here.
 * Only the "hidden" count is acted on, as in the iOS app.
 */
class PageBridge(private val prefs: Prefs) {
    /** Older WebViews: called through addJavascriptInterface. */
    @JavascriptInterface
    fun postMessage(json: String) = handle(json)

    /** Newer WebViews deliver through a web message listener, which has already checked the origin. */
    fun handle(json: String) {
        val message = try { JSONObject(json) } catch (e: Exception) { return }
        if (message.optString("type") == "hidden") {
            prefs.recordHidden(message.optInt("count", 0))
        }
    }

    companion object {
        const val NAME = "QuietFeedAndroid"

        /** Gives the engine the iOS-shaped message handler it posts to. */
        val SHIM = """
(function () {
  if (!window.$NAME) return;
  var bridge = window.$NAME;
  var handlers = { stillfeed: { postMessage: function (msg) {
    try { bridge.postMessage(JSON.stringify(msg)); } catch (e) {}
  } } };
  try {
    if (!window.webkit) window.webkit = {};
    window.webkit.messageHandlers = handlers;
  } catch (e) {}
})();
"""
    }
}
