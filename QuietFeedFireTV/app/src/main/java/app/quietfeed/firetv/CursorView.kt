package app.quietfeed.firetv

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View

/**
 * The pointer drawn over the web view. Websites are built for touch and mouse, not a D-pad,
 * so the remote's arrows move this and the center button taps where it points.
 */
class CursorView(context: Context) : View(context) {
    var x0 = 0f
        private set
    var y0 = 0f
        private set

    private val radius = context.dp(14).toFloat()
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xCCFFFFFF.toInt(); style = Paint.Style.FILL }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Ui.ACCENT
        style = Paint.Style.STROKE
        strokeWidth = context.dp(3).toFloat()
    }
    private val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x66000000; style = Paint.Style.FILL }
    private var pressed = false
    private val hide = Runnable { animate().alpha(0f).setDuration(400).start() }

    init {
        isFocusable = false
        isClickable = false
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (oldw == 0 && oldh == 0) {
            x0 = w / 2f
            y0 = h / 2f
        } else {
            x0 = x0.coerceIn(0f, w.toFloat())
            y0 = y0.coerceIn(0f, h.toFloat())
        }
    }

    /** Moves by (dx, dy), stopping at the screen's edges. Returns how far it couldn't go. */
    fun moveBy(dx: Float, dy: Float): Pair<Float, Float> {
        val nx = x0 + dx
        val ny = y0 + dy
        x0 = nx.coerceIn(0f, width.toFloat())
        y0 = ny.coerceIn(0f, height.toFloat())
        wake()
        return (nx - x0) to (ny - y0)
    }

    /** Shrinks the pointer while the center button is held, like a tap. */
    fun setDown(down: Boolean) {
        pressed = down
        wake()
    }

    /** Shows the pointer, then fades it after a few idle seconds so it doesn't sit over a video. */
    fun wake() {
        removeCallbacks(hide)
        animate().cancel()
        alpha = 1f
        invalidate()
        postDelayed(hide, 3500)
    }

    override fun onDraw(canvas: Canvas) {
        val r = if (pressed) radius * 0.75f else radius
        canvas.drawCircle(x0 + 2, y0 + 3, r, shadow)
        canvas.drawCircle(x0, y0, r, fill)
        canvas.drawCircle(x0, y0, r, ring)
    }
}
