package app.quietfeed.firetv

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast

/** How a platform runs on Fire TV. */
sealed interface Experience {
    /**
     * Filtered inside QuietFeed.
     *
     * [tvInterface]: load YouTube's own TV interface (youtube.com/tv) from [startUrl]. It is the
     * interface YouTube's TV apps use, so it is driven by the remote exactly like the app: QuietFeed
     * passes the keys straight through. Otherwise the site is driven with TvNav.js's highlight.
     */
    data class InApp(val startUrl: String? = null, val tvInterface: Boolean = false) : Experience

    /**
     * Opens the platform's own Fire TV app, as the Apple TV version does. Their websites use DRM
     * players that refuse to run in an embedded view on Android, so filtering isn't possible.
     */
    data class NativeApp(val packageName: String) : Experience

    companion object {
        const val HIDE_SHORTS = "hide_shorts"
        private val AD_KEYS = setOf("skip_ads", "hide_ads")

        /**
         * In YouTube's TV interface the engine runs only its ad skipping: the shared layout rules
         * describe the mobile site, and Shorts are removed from the data by YtTv.js instead.
         */
        fun isTvInterfaceRule(rule: FilterRule): Boolean = rule.key in AD_KEYS

        /** The filter switches that do something on Fire TV for this platform. */
        fun visibleToggles(platformId: String, toggles: List<RuleToggle>): List<RuleToggle> {
            val experience = of(platformId)
            return if (experience is InApp && experience.tvInterface) {
                toggles.filter { it.key in AD_KEYS || it.key == HIDE_SHORTS }
            } else {
                toggles
            }
        }

        fun of(platformId: String): Experience = when (platformId) {
            "netflix" -> NativeApp("com.netflix.ninja")
            "amazon_prime" -> NativeApp("com.amazon.avod")
            "spotify" -> NativeApp("com.spotify.tv.android")
            // On Fire TV, YouTube Music lives inside YouTube's TV interface (there's no separate TV app).
            "youtube", "youtube_music" -> InApp(startUrl = "https://www.youtube.com/tv", tvInterface = true)
            else -> InApp()
        }
    }
}

object NativeApps {
    /** Opens the installed app, or its Appstore page when it isn't installed. */
    fun open(context: Context, platform: Platform, packageName: String) {
        val pm = context.packageManager
        val launch = pm.getLeanbackLaunchIntentForPackage(packageName) ?: pm.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        }
        try {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("amzn://apps/android?p=$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            Toast.makeText(context, "Install ${platform.name}, then open it from QuietFeed.", Toast.LENGTH_LONG).show()
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(context, "Install ${platform.name} from the Appstore, then try again.", Toast.LENGTH_LONG).show()
        }
    }
}
