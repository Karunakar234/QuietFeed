package app.quietfeed.firetv

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * What the iOS app keeps in SwiftData and @AppStorage: onboarding, which platforms are on the
 * home screen, each platform's filter switches, and this week's count of filtered items.
 */
class Prefs(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("quietfeed", Context.MODE_PRIVATE)

    var didOnboard: Boolean
        get() = prefs.getBoolean("didOnboard", false)
        set(value) = prefs.edit().putBoolean("didOnboard", value).apply()

    /** The one-time remote tip on a platform screen. */
    var sawTvTip: Boolean
        get() = prefs.getBoolean("sawTvTip", false)
        set(value) = prefs.edit().putBoolean("sawTvTip", value).apply()

    fun isEnabled(platformId: String): Boolean = prefs.getBoolean("enabled.$platformId", false)

    fun setEnabled(platformId: String, enabled: Boolean) {
        prefs.edit().putBoolean("enabled.$platformId", enabled).apply()
    }

    fun toggles(platformId: String): Map<String, Boolean> {
        val text = prefs.getString("toggles.$platformId", null) ?: return emptyMap()
        val json = JSONObject(text)
        return json.keys().asSequence().associateWith { json.getBoolean(it) }
    }

    fun setToggle(platformId: String, key: String, on: Boolean) {
        val next = toggles(platformId) + (key to on)
        prefs.edit().putString("toggles.$platformId", JSONObject(next).toString()).apply()
    }

    // MARK: Weekly insights (Monday-start week, as the iOS app's ISO calendar)

    /** Items filtered on each day of the current week, Monday first. */
    fun dailyHidden(): IntArray {
        val counts = IntArray(7)
        if (prefs.getString("insights.week", null) != currentWeekStart()) return counts
        val saved = JSONArray(prefs.getString("insights.counts", "[]"))
        for (i in 0 until minOf(7, saved.length())) counts[i] = saved.getInt(i)
        return counts
    }

    fun totalHidden(): Int = dailyHidden().sum()

    @Synchronized
    fun recordHidden(count: Int) {
        if (count <= 0) return
        val counts = dailyHidden()
        counts[todayIndex()] += count
        prefs.edit()
            .putString("insights.week", currentWeekStart())
            .putString("insights.counts", JSONArray(counts.toList()).toString())
            .apply()
    }

    fun resetInsights() {
        prefs.edit().remove("insights.week").remove("insights.counts").apply()
    }

    /** Back to first launch: every switch, every platform, onboarding and insights. */
    fun resetAll() {
        prefs.edit().clear().apply()
    }

    /** Monday of this week as yyyy-mm-dd. java.time isn't on Fire OS 6 (Android 7.1). */
    private fun currentWeekStart(): String {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_MONTH, -todayIndex())
        return String.format(Locale.US, "%04d-%02d-%02d", cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))
    }

    /** 0 for Monday through 6 for Sunday. */
    private fun todayIndex(): Int = (Calendar.getInstance().get(Calendar.DAY_OF_WEEK) + 5) % 7
}
