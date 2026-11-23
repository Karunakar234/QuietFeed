package app.quietfeed.firetv

import android.net.Uri
import java.net.URI
import java.util.regex.Pattern
import java.util.regex.PatternSyntaxException

/**
 * Decides, natively, where a page load may go. A port of the iOS NavigationGuard: it backs up the
 * injected engine, so blocked places stay blocked even if a page's markup changes.
 */
class NavigationGuard(private val platform: Platform, private val rules: List<FilterRule>) {

    sealed interface Decision {
        data object Allow : Decision
        data class Redirect(val url: String) : Decision
        data class External(val url: String) : Decision
        data object Cancel : Decision
    }

    fun decide(url: Uri, isMainFrame: Boolean): Decision {
        val scheme = url.scheme?.lowercase().orEmpty()
        if (scheme == "about") return if (url.toString() == "about:blank") Decision.Allow else Decision.Cancel
        if (scheme == "blob" || scheme == "data") return if (isMainFrame) Decision.Cancel else Decision.Allow
        // Platform sessions and credentials must never be sent over a downgraded connection.
        if (scheme != "https") return Decision.Cancel
        if (!isMainFrame) return Decision.Allow
        val host = url.host?.lowercase() ?: return Decision.External(url.toString())
        if (!isAllowed(host)) return Decision.External(url.toString())
        if (!isPlatformHost(host)) return Decision.Allow

        val path = pathAndQuery(url)
        for (rule in rules) {
            if (rule.action != FilterRule.REDIRECT && rule.action != FilterRule.BLOCK_NAVIGATION) continue
            val pattern = firstMatch(rule.urlPatterns, path) ?: continue
            val target = if (rule.action == FilterRule.REDIRECT) {
                pattern.matcher(path).replaceAll(templateToJava(rule.redirectTo ?: "/"))
            } else {
                "/"
            }
            if (target != path) return Decision.Redirect(resolve(target))
        }
        return Decision.Allow
    }

    /** True on a page that should show one item only (a reel a friend sent). */
    fun isSingleItem(url: Uri?): Boolean {
        val host = url?.host?.lowercase() ?: return false
        if (!isPlatformHost(host)) return false
        val path = pathAndQuery(url)
        return rules.any { it.action == FilterRule.DISABLE_SCROLL && firstMatch(it.urlPatterns, path) != null }
    }

    /**
     * Script messages affect usage totals, so only the platform's own top-level document is
     * trusted to send them.
     */
    fun isTrustedMessageOrigin(host: String, isMainFrame: Boolean): Boolean =
        isMainFrame && isAllowed(host.lowercase())

    /** Origin rules for the web message listener: each allowed host and its subdomains, https only. */
    fun messageOriginRules(): Set<String> =
        platform.allowedHosts.flatMap { listOf("https://$it", "https://*.$it") }.toSet()

    private fun isAllowed(host: String) =
        platform.allowedHosts.any { host == it || host.endsWith(".$it") }

    private fun isPlatformHost(host: String): Boolean {
        val own = platform.allowedHosts.firstOrNull() ?: return false
        return host == own || host.endsWith(".$own")
    }

    /** Like iOS's URL(string:relativeTo:): a path resolves against the platform's home page. */
    private fun resolve(target: String): String = URI(platform.baseUrl).resolve(target).toString()

    companion object {
        /** The encoded path plus query, keeping a trailing slash, as the iOS guard and the engine see it. */
        fun pathAndQuery(url: Uri): String {
            var path = url.encodedPath.orEmpty().ifEmpty { "/" }
            val query = url.encodedQuery
            if (!query.isNullOrEmpty()) path += "?$query"
            return path
        }

        fun firstMatch(patterns: List<String>, path: String): Pattern? {
            for (source in patterns) {
                val pattern = try { Pattern.compile(source) } catch (e: PatternSyntaxException) { continue }
                if (pattern.matcher(path).find()) return pattern
            }
            return null
        }

        /**
         * Redirect templates are written for NSRegularExpression and JavaScript, which both use
         * `$1` for groups, as Java does; only a literal backslash needs escaping for Java.
         */
        private fun templateToJava(template: String): String = template.replace("\\", "\\\\")
    }
}
