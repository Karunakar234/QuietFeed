package app.quietfeed.firetv

import android.net.Uri
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream

/**
 * Blocks known ad requests before they download: the same list as the iOS AdBlocker's
 * content rules. It can't stop ads YouTube serves from the video's own host; FilterEngine.js
 * handles those.
 */
object AdBlocker {
    private val blockedHosts = listOf("doubleclick.net", "googlesyndication.com", "googleadservices.com")
    private val blockedPaths = mapOf("youtube.com" to listOf("/pagead/", "/api/stats/ads"))

    fun shouldBlock(url: Uri): Boolean {
        val host = url.host?.lowercase() ?: return false
        if (blockedHosts.any { host == it || host.endsWith(".$it") }) return true
        val path = url.encodedPath.orEmpty()
        return blockedPaths.any { (domain, prefixes) ->
            (host == domain || host.endsWith(".$domain")) && prefixes.any { path.startsWith(it) }
        }
    }

    /** An empty answer, so the page sees the request finish rather than hang. */
    fun emptyResponse(): WebResourceResponse =
        WebResourceResponse("text/plain", "utf-8", 204, "No Content", emptyMap(), ByteArrayInputStream(ByteArray(0)))
}
