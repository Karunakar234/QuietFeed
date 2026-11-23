package app.quietfeed.firetv

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Onboarding, then the three tabs the iOS app has room for on a TV: Home, Filters and Settings.
 * Each screen is rebuilt when shown, so it always reflects the saved switches.
 */
class MainActivity : Activity() {

    private enum class Screen { WELCOME, PICK, HOME, FILTERS, SETTINGS }

    private lateinit var prefs: Prefs
    private lateinit var store: RuleStore
    private var screen = Screen.HOME
    private val picked = mutableSetOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)
        store = RuleStore.get(this)
        val saved = savedInstanceState?.getString("screen")?.let { Screen.valueOf(it) }
        show(saved ?: if (prefs.didOnboard) Screen.HOME else Screen.WELCOME)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("screen", screen.name)
    }

    /** Coming back from a platform: refresh, so this week's count is current. */
    override fun onRestart() {
        super.onRestart()
        if (screen == Screen.HOME) show(Screen.HOME)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            goBack()
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    @Deprecated("Kept for Fire OS versions that deliver Back here instead of as a key event.")
    override fun onBackPressed() {
        goBack()
    }

    private fun goBack() {
        when (screen) {
            Screen.FILTERS, Screen.SETTINGS -> show(Screen.HOME)
            Screen.PICK -> show(Screen.WELCOME)
            else -> finish()
        }
    }

    private fun show(next: Screen) {
        screen = next
        val content = when (next) {
            Screen.WELCOME -> welcome()
            Screen.PICK -> pickPlatforms()
            Screen.HOME -> page(Screen.HOME, home())
            Screen.FILTERS -> page(Screen.FILTERS, filters())
            Screen.SETTINGS -> page(Screen.SETTINGS, settings())
        }
        setContentView(content)
        content.post { firstFocusable(content)?.requestFocus() }
    }

    // MARK: Onboarding

    private fun welcome(): View = centered {
        add(text("QuietFeed", 22f, Ui.ACCENT, bold = true))
        add(text("Keep your people. Skip the pull.", 44f, bold = true).apply { setPadding(0, dp(12), 0, dp(12)) })
        add(text("Instagram and YouTube, without Reels, Shorts or the feed of strangers.", 22f, Ui.TEXT_MUTED))
        add(horizontal { setPadding(0, dp(40), 0, 0); add(pillButton("Get started", primary = true) { show(Screen.PICK) }, wrap()) })
    }

    private fun pickPlatforms(): View = centered {
        add(text("Choose your platforms", 40f, bold = true))
        add(text("You can change this any time.", 20f, Ui.TEXT_MUTED).apply { setPadding(0, dp(8), 0, dp(32)) })
        val continueButton = pillButton("Continue", primary = true) {
            if (picked.isEmpty()) return@pillButton
            store.platforms.forEach { prefs.setEnabled(it.id, it.id in picked) }
            prefs.didOnboard = true
            show(Screen.HOME)
        }
        fun refreshContinue() { continueButton.alpha = if (picked.isEmpty()) 0.4f else 1f }
        add(horizontal(24) {
            store.platforms.forEach { platform ->
                val card = platformCard(platform, selectable = true, selected = platform.id in picked)
                card.makeFocusable {
                    if (!picked.add(platform.id)) picked.remove(platform.id)
                    (card.tag as TextView).text = checkLabel(platform.id in picked)
                    refreshContinue()
                }
                add(card, dp(260), dp(200))
            }
        })
        add(horizontal { setPadding(0, dp(40), 0, 0); add(continueButton, wrap()) })
        refreshContinue()
    }

    // MARK: Tabs

    /** A tab bar along the top and the screen's content underneath, scrollable. */
    private fun page(current: Screen, body: View): View {
        val root = vertical {
            setBackgroundColor(Ui.BG)
            setPadding(dp(56), dp(32), dp(56), 0)
        }
        root.add(horizontal(16) {
            gravity = Gravity.CENTER_VERTICAL
            add(text("QuietFeed", 26f, Ui.ACCENT, bold = true).apply { setPadding(0, 0, dp(24), 0) }, wrap())
            listOf(Screen.HOME to "Home", Screen.FILTERS to "Filters", Screen.SETTINGS to "Settings").forEach { (tab, label) ->
                add(tabButton(label, selected = tab == current) { if (tab != screen) show(tab) }, wrap())
            }
        })
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            clipToPadding = false
            setPadding(0, dp(28), 0, dp(40))
            addView(body)
        }
        // Room for focused cards to grow without being clipped.
        body.setPadding(dp(8), dp(8), dp(8), dp(8))
        root.add(scroll, match(), 0, 1f)
        return root
    }

    private fun tabButton(label: String, selected: Boolean, onClick: () -> Unit): TextView =
        text(label, 18f, if (selected) Ui.ON_ACCENT else Ui.TEXT, bold = true).apply {
            setPadding(dp(22), dp(10), dp(22), dp(10))
            background = if (selected) rounded(Ui.ACCENT, 999) else focusBackground(999)
            makeFocusable(1.06f, onClick)
            if (selected) setOnFocusChangeListener { v, has ->
                background = if (has) rounded(Ui.ACCENT, 999, Ui.TEXT, 3) else rounded(Ui.ACCENT, 999)
                v.animate().scaleX(if (has) 1.06f else 1f).scaleY(if (has) 1.06f else 1f).setDuration(120).start()
            }
        }

    private fun home(): View = vertical(28) {
        add(text("Your calmer entertainment hub", 32f, bold = true))
        val enabled = store.platforms.filter { prefs.isEnabled(it.id) }
        if (enabled.isEmpty()) {
            add(text("No platforms on your home screen yet. Turn some on in Settings.", 20f, Ui.TEXT_MUTED))
        } else {
            add(horizontal(28) {
                enabled.forEach { platform ->
                    val card = platformCard(platform, selectable = false, selected = false)
                    card.makeFocusable { open(platform) }
                    add(card, dp(300), dp(220))
                }
            })
        }
        add(insightsCard(), wrap())
        add(text("Move with the arrows and press the center button to select. Inside a platform, the arrows move a pointer.", 16f, Ui.TEXT_MUTED))
    }

    private fun insightsCard(): View = vertical {
        background = rounded(Ui.SURFACE, 20, Ui.BORDER, 1)
        setPadding(dp(28), dp(22), dp(28), dp(22))
        add(text("Your Weekly Insights", 18f, Ui.TEXT_MUTED, bold = true))
        add(horizontal(12) {
            gravity = Gravity.BOTTOM
            add(text(prefs.totalHidden().toString(), 48f, Ui.ACCENT, bold = true), wrap())
            add(text("items filtered this week", 20f).apply { setPadding(0, 0, 0, dp(10)) }, wrap())
        })
    }

    private fun filters(): View = vertical(32) {
        add(text("Filters", 32f, bold = true))
        add(text("Choose what QuietFeed hides on each platform. Changes apply the next time you open it.", 18f, Ui.TEXT_MUTED))
        store.platforms.forEach { platform ->
            val toggles = store.toggles(platform.id)
            if (toggles.isEmpty()) return@forEach
            add(vertical(12) {
                add(text(platform.name, 24f, Ui.tint(platform.id), bold = true))
                toggles.forEach { toggle ->
                    add(switchRow(toggle.title, toggle.detail, { prefs.toggles(platform.id)[toggle.key] ?: toggle.defaultOn }) { on ->
                        prefs.setToggle(platform.id, toggle.key, on)
                    })
                }
            })
        }
    }

    private fun settings(): View = vertical(32) {
        add(text("Settings", 32f, bold = true))
        add(vertical(12) {
            add(text("Platforms on your home screen", 22f, bold = true))
            store.platforms.forEach { platform ->
                add(switchRow(platform.name, platform.tagline, { prefs.isEnabled(platform.id) }) { on ->
                    prefs.setEnabled(platform.id, on)
                })
            }
        })
        add(vertical(12) {
            add(text("Your data", 22f, bold = true))
            add(text("Resets the count of items filtered this week back to zero.", 16f, Ui.TEXT_MUTED))
            add(horizontal { add(pillButton("Delete weekly insight data") { confirmResetInsights() }, wrap()) })
            add(text("Signs you out of every platform in QuietFeed, clears your weekly insights and resets every switch, as on first launch.", 16f, Ui.TEXT_MUTED))
            add(horizontal { add(pillButton("Delete my data") { confirmDeleteEverything() }.apply { setTextColor(Ui.DANGER) }, wrap()) })
        })
        add(text("QuietFeed is independent and not affiliated with Instagram, Meta, YouTube or Google.", 16f, Ui.TEXT_MUTED))
    }

    // MARK: Pieces

    private fun platformCard(platform: Platform, selectable: Boolean, selected: Boolean): LinearLayout = vertical {
        background = focusBackground(24)
        setPadding(dp(24), dp(22), dp(24), dp(22))
        val top = horizontal {
            add(text(Ui.glyph(platform.id), 40f, Ui.tint(platform.id), bold = true), 0, wrap(), 1f)
            if (selectable) {
                val check = text(checkLabel(selected), 18f, Ui.ACCENT, bold = true)
                add(check, wrap())
                this@vertical.tag = check
            }
        }
        add(top)
        add(View(context), match(), 0, 1f)
        add(text(platform.name, 26f, bold = true))
        platform.tagline?.let { add(text(it, 16f, Ui.TEXT_MUTED).apply { maxLines = 2 }) }
    }

    private fun checkLabel(selected: Boolean) = if (selected) "✓ On" else "Off"

    /** A row with a title, a detail line and an On/Off pill. Selecting it flips the switch. */
    private fun switchRow(title: String, detail: String?, isOn: () -> Boolean, onChange: (Boolean) -> Unit): View {
        val state = text("", 16f, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(dp(18), dp(6), dp(18), dp(6))
        }
        fun render() {
            val on = isOn()
            state.text = if (on) "On" else "Off"
            state.setTextColor(if (on) Ui.ON_ACCENT else Ui.TEXT_MUTED)
            state.background = rounded(if (on) Ui.ACCENT else Ui.SURFACE_RAISED, 999, Ui.BORDER, if (on) 0 else 1)
        }
        val row = horizontal(16) {
            gravity = Gravity.CENTER_VERTICAL
            background = focusBackground(16)
            setPadding(dp(24), dp(16), dp(24), dp(16))
            add(vertical {
                add(text(title, 20f, bold = true))
                detail?.let { add(text(it, 15f, Ui.TEXT_MUTED)) }
            }, 0, wrap(), 1f)
            add(state, wrap())
        }
        row.makeFocusable(1.02f) { onChange(!isOn()); render() }
        render()
        return row
    }

    private fun centered(block: LinearLayout.() -> Unit): View = FrameLayout(this).apply {
        setBackgroundColor(Ui.BG)
        addView(vertical { block() }, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.CENTER).apply {
            leftMargin = dp(80); rightMargin = dp(80)
        })
    }

    private fun firstFocusable(view: View): View? {
        if (view.isFocusable && view.visibility == View.VISIBLE) return view
        if (view is android.view.ViewGroup) {
            for (i in 0 until view.childCount) firstFocusable(view.getChildAt(i))?.let { return it }
        }
        return null
    }

    private fun open(platform: Platform) {
        startActivity(Intent(this, PlayerActivity::class.java).putExtra(PlayerActivity.EXTRA_PLATFORM, platform.id))
    }

    // MARK: Data

    private fun confirmResetInsights() {
        AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle("Delete weekly insight data?")
            .setMessage("This will reset your count of filtered items for this week back to zero.")
            .setPositiveButton("Delete") { _, _ -> prefs.resetInsights() }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun confirmDeleteEverything() {
        AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle("Delete everything QuietFeed has stored on this device?")
            .setMessage("You'll be signed out of every platform.")
            .setPositiveButton("Delete my data") { _, _ ->
                CookieManager.getInstance().removeAllCookies(null)
                CookieManager.getInstance().flush()
                WebStorage.getInstance().deleteAllData()
                prefs.resetAll()
                picked.clear()
                show(Screen.WELCOME)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
}
