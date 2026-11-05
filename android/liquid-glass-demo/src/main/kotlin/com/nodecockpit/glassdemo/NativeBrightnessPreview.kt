package com.nodecockpit.glassdemo

import android.animation.ValueAnimator
import android.app.Activity
import android.app.Dialog
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import com.nodecockpit.customization.GlassBrightnessGeometry
import com.nodecockpit.customization.GlassBrightnessMaterial

/** Uses exactly the engine material used by the adapter. No hooks or hidden-API exemptions. */
internal class NativeBrightnessPreview(private val activity: Activity) : Dialog(activity) {
    private val density get() = context.resources.displayMetrics.density
    private fun dp(value: Int) = (value * density).toInt()
    private lateinit var slider: BrightnessControl
    private lateinit var status: TextView
    private var progressBlur = 60f
    private var indicatorBlur = 60f
    private var motion: ValueAnimator? = null

    private fun label(value: String) = TextView(context).apply {
        text = value; setTextColor(Color.WHITE); textSize = 13f
        setBackgroundColor(0xff101722.toInt())
        setPadding(dp(8), dp(4), dp(8), dp(4))
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window?.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window?.setDimAmount(.88f)
        val body = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(18), dp(16), dp(18), dp(16)) }
        body.addView(label("Native brightness material").apply { textSize = 19f })
        body.addView(label("Same engine drawing as Node Cockpit. One native SeekBar controls this preview only; device brightness is untouched."))
        status = label("Waiting for native draw…").apply { minHeight = dp(66); maxLines = 4 }
        body.addView(status)
        body.addView(label("☼  Brightness"))
        slider = BrightnessControl()
        body.addView(slider, LinearLayout.LayoutParams(-1, dp(88)))
        fun blurOption(title: String, changed: (Float) -> Unit) {
            val level = label("$title · 60 px")
            body.addView(level)
            body.addView(SeekBar(context).apply {
                max = 100; progress = 60
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onStartTrackingTouch(bar: SeekBar) {}
                    override fun onStopTrackingTouch(bar: SeekBar) {}
                    override fun onProgressChanged(bar: SeekBar, value: Int, fromUser: Boolean) {
                        level.text = "$title · $value px"; changed(value.toFloat()); slider.recreate()
                    }
                })
            })
        }
        blurOption("Progress blur") { progressBlur = it }
        blurOption("Indicator blur") { indicatorBlur = it }
        fun action(title: String, run: () -> Unit) { body.addView(Button(context).apply { text = title; setOnClickListener { run() } }) }
        action("Animate native translation / scale") {
            if (motion != null) stopMotion() else {
                motion = ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = 1400; repeatMode = ValueAnimator.REVERSE; repeatCount = ValueAnimator.INFINITE
                    addUpdateListener {
                        val p = it.animatedValue as Float
                        slider.translationX = (p - .5f) * dp(16); slider.scaleX = .86f + .14f * p; slider.scaleY = slider.scaleX
                    }
                    start()
                }
            }
        }
        action("Hide / show") { slider.visibility = if (slider.visibility == View.VISIBLE) View.INVISIBLE else View.VISIBLE }
        action("Recreate material / retry availability") { slider.recreate() }
        action("Read material status") { status.text = slider.diagnostics() }
        action("Close") { dismiss() }
        setContentView(ScrollView(context).apply { addView(body) })
        window?.setLayout((activity.resources.displayMetrics.widthPixels * .94f).toInt(), (activity.resources.displayMetrics.heightPixels * .85f).toInt())
    }
    override fun onStop() { stopMotion(); slider.release(); super.onStop() }
    private fun stopMotion() { motion?.cancel(); motion = null; if (::slider.isInitialized) { slider.translationX = 0f; slider.scaleX = 1f; slider.scaleY = 1f } }

    private inner class BrightnessControl : SeekBar(context) {
        private var material: GlassBrightnessMaterial? = null
        private var lastSuccess: Boolean? = null
        private var unavailable = ""
        private val fallback = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xff344257.toInt() }
        init {
            max = 1000; progress = 620
            setPadding(dp(18), 0, dp(18), 0)
            progressDrawable = ColorDrawable(Color.TRANSPARENT)
            thumb = GradientDrawable().apply { setColor(Color.TRANSPARENT); setSize(dp(4), dp(44)) }
            thumbOffset = dp(2); splitTrack = false
            contentDescription = "Preview brightness"
            setOnSeekBarChangeListener(object : OnSeekBarChangeListener {
                override fun onStartTrackingTouch(bar: SeekBar) {}
                override fun onStopTrackingTouch(bar: SeekBar) {}
                override fun onProgressChanged(bar: SeekBar, value: Int, fromUser: Boolean) { invalidate() }
            })
        }
        fun release() { material?.close(); material = null }
        fun recreate() { release(); lastSuccess = null; unavailable = ""; if (isAttachedToWindow) material = GlassBrightnessMaterial(this, progressBlur, indicatorBlur); invalidate() }
        fun diagnostics() = material?.diagnostics() ?: unavailable.ifEmpty { "Native material not attached" }
        override fun onAttachedToWindow() { super.onAttachedToWindow(); recreate() }
        override fun onDetachedFromWindow() { release(); super.onDetachedFromWindow() }
        override fun onVisibilityChanged(changedView: View, visibility: Int) { super.onVisibilityChanged(changedView, visibility); material?.setVisible(isShown) }
        override fun onDraw(canvas: Canvas) {
            val w = (width - paddingLeft - paddingRight).toFloat()
            val h = dp(56).toFloat()
            if (w <= 0 || height <= 0) return
            val save = canvas.save()
            var applied = false
            try {
                canvas.translate(paddingLeft.toFloat(), (height - h) / 2f)
                if (layoutDirection == View.LAYOUT_DIRECTION_RTL) canvas.scale(-1f, 1f, w / 2f, h / 2f)
                val base = GlassBrightnessGeometry.track(0f, 0f, w, h, h / 2f, h / 2f, false)
                val end = w * progress / max
                val fill = GlassBrightnessGeometry.track(0f, 0f, end, h, h / 2f, 0f, false)
                val rest = GlassBrightnessGeometry.track(end, 0f, w - end, h, 0f, h / 2f, false)
                val markerW = dp(4).toFloat()
                val indicator = GlassBrightnessGeometry.track(end - markerW / 2f, dp(6).toFloat(), markerW, h - dp(12), markerW / 2f, markerW / 2f, false)
                val current = material
                val baseDrawn = current?.draw(canvas, 0, GlassBrightnessMaterial.Role.CONTAINER, base, 1f) == true
                val fillDrawn = fill == null || current?.draw(canvas, 1, GlassBrightnessMaterial.Role.TRACK, fill, 1f) == true
                val restDrawn = rest == null || current?.draw(canvas, 2, GlassBrightnessMaterial.Role.TRACK, rest, 1f) == true
                val indicatorDrawn = current?.draw(canvas, 3, GlassBrightnessMaterial.Role.INDICATOR, indicator, 1f) == true
                applied = baseDrawn && fillDrawn && restDrawn && indicatorDrawn
                if (!applied) {
                    if (current != null) { unavailable = current.diagnostics(); release() }
                    // Explicit solid stock-like fallback, never a second blur or refraction path.
                    fallback.color = 0xff344257.toInt(); canvas.drawRoundRect(0f, 0f, w, h, h / 2f, h / 2f, fallback)
                    fallback.color = Color.WHITE; canvas.drawRoundRect(end - markerW / 2f, dp(6).toFloat(), end + markerW / 2f, h - dp(6), markerW / 2f, markerW / 2f, fallback)
                }
            } finally { canvas.restoreToCount(save) }
            // Native SeekBar supplies touch, keyboard and accessibility semantics. Its stock paint is transparent.
            super.onDraw(canvas)
            if (lastSuccess != applied) {
                lastSuccess = applied
                val message = if (applied) "Native material drawn. Check its motion visually; no shader blur or screen-geometry observer is used."
                    else "Native blur unavailable; showing an explicit solid fallback.\n${diagnostics()}"
                post { status.text = message }
            }
        }
    }
}
