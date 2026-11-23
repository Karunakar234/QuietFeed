package app.quietfeed.firetv

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** A platform QuietFeed can open. Read from the same rules.json the iOS app ships. */
data class Platform(
    val id: String,
    val name: String,
    val baseUrl: String,
    val allowedHosts: List<String>,
    val tagline: String?,
    val isPro: Boolean,
)

/**
 * One filter rule. [raw] is the rule exactly as rules.json has it (snake_case keys), because
 * FilterEngine.js reads that shape; the typed fields are what the native side needs.
 */
data class FilterRule(
    val platformId: String,
    val key: String,
    val title: String,
    val detail: String?,
    val action: String,
    val urlPatterns: List<String>,
    val redirectTo: String?,
    val isPro: Boolean,
    val defaultOn: Boolean,
    val raw: JSONObject,
) {
    companion object {
        const val REDIRECT = "redirect"
        const val BLOCK_NAVIGATION = "block_navigation"
        const val DISABLE_SCROLL = "disable_scroll"
    }
}

/** One switch on the Filters screen: a key can cover several rules. */
data class RuleToggle(val key: String, val title: String, val detail: String?, val defaultOn: Boolean)

class RuleStore private constructor(
    val platforms: List<Platform>,
    private val rules: List<FilterRule>,
) {
    fun platform(id: String): Platform? = platforms.firstOrNull { it.id == id }

    fun rules(platformId: String): List<FilterRule> = rules.filter { it.platformId == platformId }

    /** One switch per key, in file order. */
    fun toggles(platformId: String): List<RuleToggle> {
        val all = rules(platformId)
        return all.distinctBy { it.key }.map { rule ->
            RuleToggle(
                key = rule.key,
                title = rule.title,
                detail = all.firstOrNull { it.key == rule.key && it.detail != null }?.detail,
                defaultOn = rule.defaultOn,
            )
        }
    }

    /** The rules to run, given the person's switches. */
    fun enabledRules(platformId: String, toggles: Map<String, Boolean>): List<FilterRule> =
        rules(platformId).filter { toggles[it.key] ?: it.defaultOn }

    companion object {
        @Volatile private var shared: RuleStore? = null

        fun get(context: Context): RuleStore = shared ?: synchronized(this) {
            shared ?: load(context).also { shared = it }
        }

        private fun load(context: Context): RuleStore {
            val text = context.assets.open("rules.json").bufferedReader().use { it.readText() }
            return parse(JSONObject(text))
        }

        fun parse(root: JSONObject): RuleStore {
            val platforms = root.getJSONArray("platforms").objects().map { p ->
                Platform(
                    id = p.getString("id"),
                    name = p.getString("name"),
                    baseUrl = p.getString("base_url"),
                    allowedHosts = p.getJSONArray("allowed_hosts").strings(),
                    tagline = p.optStringOrNull("tagline"),
                    isPro = p.optBoolean("is_pro", false),
                )
            }
            val rules = root.getJSONArray("rules").objects().map { r ->
                FilterRule(
                    platformId = r.getString("platform_id"),
                    key = r.getString("key"),
                    title = r.getString("title"),
                    detail = r.optStringOrNull("detail"),
                    action = r.getString("action"),
                    urlPatterns = r.optJSONArray("url_patterns")?.strings().orEmpty(),
                    redirectTo = r.optStringOrNull("redirect_to"),
                    isPro = r.optBoolean("is_pro", false),
                    defaultOn = r.optBoolean("default_on", true),
                    raw = r,
                )
            }
            return RuleStore(platforms, rules)
        }

        /** The rules as the JSON array FilterEngine.js boots with. */
        fun toEngineJson(rules: List<FilterRule>): String =
            JSONArray().apply { rules.forEach { put(it.raw) } }.toString()
    }
}

private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }
private fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }
private fun JSONObject.optStringOrNull(name: String): String? =
    if (has(name) && !isNull(name)) getString(name) else null
