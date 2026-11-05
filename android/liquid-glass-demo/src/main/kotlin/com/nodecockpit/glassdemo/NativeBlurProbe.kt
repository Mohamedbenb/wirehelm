package com.nodecockpit.glassdemo

import android.animation.ValueAnimator
import android.app.Activity
import android.app.Dialog
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.*
import com.nodecockpit.customization.GlassNativeBackdrop
import com.nodecockpit.customization.GlassNativeBlurRegion

/** Local diagnostic window. No hooks, device settings or hidden-API exemptions. */
internal class NativeBlurProbe(private val activity: Activity) : Dialog(activity) {
    private val density get() = context.resources.displayMetrics.density
    private fun dp(value: Int) = (value * density).toInt()
    private lateinit var card: BlurCard
    private lateinit var status: TextView
    private var motion: ValueAnimator? = null
    private var radius = 40f

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window?.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        val body = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(18), dp(20), dp(18))
            setBackgroundColor(0xe6101722.toInt())
        }
        fun text(value: String) = TextView(context).apply { text = value; setTextColor(Color.WHITE); textSize = 14f }
        body.addView(text("Native blur tracking prototype"))
        body.addView(text("Samples content behind this dialog. No refraction shader or pre-rendered dots input.").apply { textSize = 12f })
        status = text("Waiting for the native window…").apply { minHeight = dp(54); maxLines = 3; textSize = 12f }
        body.addView(status)
        val stage = FrameLayout(context).apply { clipChildren = false; clipToPadding = false }
        card = BlurCard().apply {
            addView(text("Native foreground").apply { gravity = Gravity.CENTER }, FrameLayout.LayoutParams(-1, -1))
        }
        stage.addView(card, FrameLayout.LayoutParams(-1, dp(80)).apply { gravity = Gravity.CENTER; setMargins(dp(18), 0, dp(18), 0) })
        body.addView(stage, LinearLayout.LayoutParams(-1, dp(120)))
        val level = text("Native blur radius · 40 px")
        body.addView(level)
        body.addView(SeekBar(context).apply {
            max = 100; progress = 40
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(bar: SeekBar) {}
                override fun onStopTrackingTouch(bar: SeekBar) {}
                override fun onProgressChanged(bar: SeekBar, value: Int, fromUser: Boolean) {
                    radius = value.toFloat(); level.text = "Native blur radius · $value px"; card.prepare(); card.invalidate()
                }
            })
        })
        body.addView(Button(context).apply {
            text = "Toggle native layer motion"
            setOnClickListener {
                if (motion != null) stopMotion() else {
                    motion = ValueAnimator.ofFloat(0f, 1f).apply {
                        duration = 1400; repeatMode = ValueAnimator.REVERSE; repeatCount = ValueAnimator.INFINITE
                        addUpdateListener {
                            val p = it.animatedValue as Float
                            // View properties animate the native RenderNode. Do not sample/copy screen bounds.
                            card.translationX = (p - .5f) * dp(18)
                            card.scaleX = .86f + .14f * p; card.scaleY = card.scaleX
                        }
                        start()
                    }
                }
            }
        })
        body.addView(Button(context).apply { text = "Hide / show component"; setOnClickListener { card.visibility = if (card.visibility == View.VISIBLE) View.GONE else View.VISIBLE } })
        body.addView(Button(context).apply { text = "Recreate native blur"; setOnClickListener { card.recreate() } })
        body.addView(Button(context).apply { text = "Close"; setOnClickListener { dismiss() } })
        setContentView(body)
        window?.setLayout((activity.resources.displayMetrics.widthPixels * .94f).toInt(), ViewGroup.LayoutParams.WRAP_CONTENT)
    }

    override fun onStart() { super.onStart(); card.post { if (isShowing) card.recreate() } }
    override fun onStop() { stopMotion(); card.release(); super.onStop() }
    private fun stopMotion() { motion?.cancel(); motion = null; if (::card.isInitialized) { card.translationX = 0f; card.scaleX = 1f; card.scaleY = 1f } }

    private inner class BlurCard : FrameLayout(context) {
        private var session: GlassNativeBackdrop? = null
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val rect = RectF()
        init { setWillNotDraw(false) }
        fun release() { session?.close(); session = null }
        fun recreate() {
            release()
            val attempt = GlassNativeBackdrop.tryCreate(this)
            session = attempt.session
            status.text = if (session == null) "UNAVAILABLE: ${attempt.unavailable}\nSolid fallback below; native blur has not been demonstrated."
                else "Native drawable acquired. Check motion/visibility manually; GPU output is not automatically validated."
            prepare(); invalidate()
        }
        private fun region(): GlassNativeBlurRegion {
            val corner = dp(28).toFloat()
            return GlassNativeBlurRegion(width, height, radius, corner, corner, corner, corner, 0x183a5778)
        }
        fun prepare() { if (width > 0 && height > 0) session?.prepare(region()) }
        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) { super.onSizeChanged(w, h, oldw, oldh); prepare() }
        override fun onDetachedFromWindow() { release(); super.onDetachedFromWindow() }
        override fun onVisibilityChanged(changedView: View, visibility: Int) {
            super.onVisibilityChanged(changedView, visibility)
            session?.setVisible(isShown)
        }
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (width < 1 || height < 1) return
            val corner = dp(28).toFloat()
            val drawn = session?.draw(canvas, region()) == true
            rect.set(.5f, .5f, width - .5f, height - .5f)
            if (!drawn) {
                paint.style = Paint.Style.FILL; paint.color = 0xff344257.toInt(); canvas.drawRoundRect(rect, corner, corner, paint)
                val failed = session?.diagnostics()
                if (failed != null) post { status.text = "$failed\nSolid fallback; native blur is unverified." }
            }
            paint.style = Paint.Style.STROKE; paint.strokeWidth = density; paint.color = 0xb0ffffff.toInt()
            canvas.drawRoundRect(rect, corner, corner, paint)
        }
    }
}
