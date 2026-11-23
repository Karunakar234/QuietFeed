package app.quietfeed.firetv

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

/** A small view kit for a 10-foot screen: big type, and an obvious focus ring on everything. */
object Ui {
    val BG = Color.parseColor("#0C1112")
    val SURFACE = Color.parseColor("#151C1D")
    val SURFACE_RAISED = Color.parseColor("#1D2627")
    val BORDER = Color.parseColor("#2A3536")
    val TEXT = Color.parseColor("#EEF5F4")
    val TEXT_MUTED = Color.parseColor("#A0B0AE")
    val ACCENT = Color.parseColor("#5CC6C4")
    val ON_ACCENT = Color.parseColor("#06201F")
    val DANGER = Color.parseColor("#FF7070")

    /** The tint each platform's card uses, matching the Apple TV launcher. */
    fun tint(platformId: String): Int = when (platformId) {
        "youtube" -> Color.parseColor("#FF4E45")
        "youtube_music" -> Color.parseColor("#FF5C9A")
        "instagram" -> Color.parseColor("#C77DFF")
        else -> ACCENT
    }

    fun glyph(platformId: String): String = when (platformId) {
        "youtube" -> "▶"
        "youtube_music" -> "♪"
        "instagram" -> "◎"
        else -> "●"
    }
}

fun Context.dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

fun Context.text(value: CharSequence, sizeSp: Float, color: Int = Ui.TEXT, bold: Boolean = false): TextView =
    TextView(this).apply {
        text = value
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        if (bold) typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

fun Context.rounded(fill: Int, radiusDp: Int, strokeColor: Int = Color.TRANSPARENT, strokeDp: Int = 0): GradientDrawable =
    GradientDrawable().apply {
        setColor(fill)
        cornerRadius = dp(radiusDp).toFloat()
        if (strokeDp > 0) setStroke(dp(strokeDp), strokeColor)
    }

/** Raised with an accent ring when focused, flat with a hairline otherwise. */
fun Context.focusBackground(radiusDp: Int, fill: Int = Ui.SURFACE, focusFill: Int = Ui.SURFACE_RAISED): Drawable =
    StateListDrawable().apply {
        addState(intArrayOf(android.R.attr.state_focused), rounded(focusFill, radiusDp, Ui.ACCENT, 3))
        addState(intArrayOf(), rounded(fill, radiusDp, Ui.BORDER, 1))
    }

/** Makes a view selectable with the remote, growing slightly when it has focus. */
fun View.makeFocusable(scale: Float = 1.04f, onClick: () -> Unit) {
    isFocusable = true
    isClickable = true
    setOnClickListener { onClick() }
    setOnFocusChangeListener { v, hasFocus ->
        val target = if (hasFocus) scale else 1f
        v.animate().scaleX(target).scaleY(target).setDuration(120).start()
        v.elevation = if (hasFocus) v.context.dp(8).toFloat() else 0f
    }
}

fun Context.pillButton(label: String, primary: Boolean = false, onClick: () -> Unit): TextView =
    text(label, 18f, if (primary) Ui.ON_ACCENT else Ui.TEXT, bold = true).apply {
        gravity = Gravity.CENTER
        setPadding(dp(28), dp(12), dp(28), dp(12))
        background = if (primary) {
            StateListDrawable().apply {
                addState(intArrayOf(android.R.attr.state_focused), rounded(Ui.ACCENT, 999, Ui.TEXT, 3))
                addState(intArrayOf(), rounded(Ui.ACCENT, 999))
            }
        } else {
            focusBackground(999)
        }
        makeFocusable(1.06f, onClick)
    }

fun Context.vertical(spacingDp: Int = 0, block: LinearLayout.() -> Unit = {}): LinearLayout =
    LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        if (spacingDp > 0) {
            showDividers = LinearLayout.SHOW_DIVIDER_MIDDLE
            dividerDrawable = GradientDrawable().apply { setSize(1, dp(spacingDp)) }
        }
        block()
    }

fun Context.horizontal(spacingDp: Int = 0, block: LinearLayout.() -> Unit = {}): LinearLayout =
    LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        if (spacingDp > 0) {
            showDividers = LinearLayout.SHOW_DIVIDER_MIDDLE
            dividerDrawable = GradientDrawable().apply { setSize(dp(spacingDp), 1) }
        }
        block()
    }

fun wrap() = ViewGroup.LayoutParams.WRAP_CONTENT
fun match() = ViewGroup.LayoutParams.MATCH_PARENT

fun LinearLayout.add(view: View, width: Int = match(), height: Int = wrap(), weight: Float = 0f): View {
    addView(view, LinearLayout.LayoutParams(width, height, weight))
    return view
}
