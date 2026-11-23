package app.quietfeed.firetv

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast

/** How a platform runs on Fire TV. */
sealed interface Experience {
    /** Filtered inside QuietFeed. [autoFullscreen]: choosing a video opens it full screen. */
    data class InApp(val autoFullscreen: Boolean) : Experience

    /**
     * Opens the platform's own Fire TV app, as the Apple TV version does. Their websites use DRM
     * players that refuse to run in an embedded view on Android, so filtering isn't possible.
     */
    data class NativeApp(val packageName: String) : Experience

    companion object {
        fun of(platformId: String): Experience = when (platformId) {
            "netflix" -> NativeApp("com.netflix.ninja")
            "amazon_prime" -> NativeApp("com.amazon.avod")
            "spotify" -> NativeApp("com.spotify.tv.android")
            "youtube" -> InApp(autoFullscreen = true)
            else -> InApp(autoFullscreen = false)
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
