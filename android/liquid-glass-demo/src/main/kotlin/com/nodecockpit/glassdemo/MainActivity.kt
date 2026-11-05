package com.nodecockpit.glassdemo

import android.app.Activity
import android.app.AlertDialog
import android.animation.ValueAnimator
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.PixelFormat
import android.graphics.ColorFilter
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.*
import com.nodecockpit.customization.GlassLabState
import com.nodecockpit.customization.GlassLabCatalog
import com.nodecockpit.customization.ForegroundInkStyle
import com.nodecockpit.customization.GlassInkDrawable
import com.nodecockpit.customization.GlassPreviewView
import com.nodecockpit.customization.LiquidGlassEngine
import java.util.IdentityHashMap
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

/** Native widget examples over the engine preview. This app never hooks SystemUI. */
class MainActivity : Activity() {
    private lateinit var preview: GlassPreviewView
    private lateinit var nativeLayer: FrameLayout
    private lateinit var motionButton: TextView
    private lateinit var componentOptions: LinearLayout
    private val state = GlassLabState()
    private val materialItems = mutableListOf<View>()
    private val baseBounds = IdentityHashMap<View, RectF>()
    private val sampleChoices = LinkedHashMap<Sample, TextView>()
    private var sample = Sample.NOTIFICATION
    private var showNotificationText = true
    private var showNotificationActions = true
    private var notificationContainer = false
    private var notificationExpanded = false
    private var notificationReveal = 0f
    private var notificationAnimator: ValueAnimator? = null
    private var notificationExpandButton: ImageButton? = null
    private var notificationGroupChildren: View? = null
    private val notificationParts = mutableListOf<NotificationParts>()
    private var qsPage = 0
    private var qsPageAnimator: ValueAnimator? = null
    private val qsEnabled = mutableMapOf<String, Boolean>()
    private val qsAmounts = mutableMapOf<String, Float>()
    private val qsAnimators = mutableMapOf<String, ValueAnimator>()
    private data class QsTileSpec(val id: String, val title: String, val icon: String, val detail: String)
    private data class QsTileParts(val spec: QsTileSpec, val root: View, val icon: TextView, val detail: TextView)
    private val qsParts = mutableListOf<QsTileParts>()
    private val buttonStates = mutableMapOf<String, Boolean>()
    private val buttonParts = mutableListOf<Pair<String, View>>()
    private var volumeStream = "Media"
    private val volumeLevels = mutableMapOf("Media" to .68f, "Ring" to .45f, "Alarm" to .72f)
    private val volumeSavedLevels = mutableMapOf<String, Float>()
    private var volumeIcon: ImageButton? = null
    private var volumeValue: TextView? = null
    private var volumeTitle: TextView? = null
    private val qsPages = listOf(
        listOf(QsTileSpec("wifi", "Wi-Fi", "◉", "Connected"), QsTileSpec("bluetooth", "Bluetooth", "ᛒ", "Connected"), QsTileSpec("modes", "Modes", "◖", "Do Not Disturb"), QsTileSpec("data", "Mobile data", "↕", "5G")),
        listOf(QsTileSpec("torch", "Torch", "☼", "On"), QsTileSpec("airplane", "Airplane mode", "✈", "On"), QsTileSpec("cast", "Cast", "▣", "Connected"), QsTileSpec("alarm", "Alarm", "◷", "07:00"))
    )
    private var background = 0
    private var diagnostics = "No preview frames yet"
    private var maskProfile = 4
    private var previewHidden = false
    private var renderedProgress = .5f
    private var nativeBlurProbe: NativeBlurProbe? = null
    private var nativeBrightnessPreview: NativeBrightnessPreview? = null
    private val density get() = resources.displayMetrics.density
    private fun dp(value: Int) = (value * density).roundToInt()

    private enum class SampleGroup(val title: String) { SYSTEM("SYSTEM UI COMPONENTS"), MATERIAL("MATERIAL STUDIES"), ENGINE("ENGINE BUILDING BLOCKS") }
    private enum class Sample(val title: String, val group: SampleGroup) {
        NOTIFICATION("Notification card", SampleGroup.SYSTEM),
        QUICK_SETTINGS("Quick settings", SampleGroup.SYSTEM),
        BRIGHTNESS("Brightness", SampleGroup.SYSTEM),
        VOLUME("Volume", SampleGroup.SYSTEM),
        LOCAL_LENS("Local lens", SampleGroup.MATERIAL),
        CARD("Card material", SampleGroup.MATERIAL),
        CLASSIC("Classic material", SampleGroup.MATERIAL),
        BUTTONS("Glass buttons", SampleGroup.ENGINE),
        MERGE("Merging cards", SampleGroup.ENGINE),
        RIPPLES("Touch ripples", SampleGroup.ENGINE),
        MOVING_CARDS("Movable cards", SampleGroup.ENGINE),
        GEOMETRY("Shapes", SampleGroup.ENGINE),
        MASKS("Region masks", SampleGroup.ENGINE),
        ICONS("Native icons", SampleGroup.ENGINE),
        POLICY("Contrast policy", SampleGroup.ENGINE)
    }
    private data class NotificationParts(val message: View, val details: View, val actions: View?)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        savedInstanceState?.let { restoreSession(it) }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(8), dp(16), dp(8))
            setBackgroundColor(Color.rgb(16, 23, 34))
        }
        root.setOnApplyWindowInsetsListener { view, insets ->
            val safe = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            view.setPadding(dp(16) + safe.left, dp(8) + safe.top, dp(16) + safe.right, dp(8) + safe.bottom)
            insets
        }
        setContentView(root)

        val toolbar = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        val heading = column().apply {
            addView(label("Liquid Glass", 21f, bold = true))
            addView(label("Engine preview · Android widgets", 12f, color = 0xffb9c4d2.toInt()))
        }
        toolbar.addView(heading, LinearLayout.LayoutParams(0, -2, 1f))
        toolbar.addView(action("Tune") { showCustomizer() })
        toolbar.addView(action("Info") { showDiagnostics() })
        root.addView(toolbar)

        val previewFrame = FrameLayout(this).apply {
            background = rounded(0xff202c3d.toInt(), dp(28))
            clipToOutline = true
            clipChildren = true
        }
        preview = GlassPreviewView(this).apply { useNativeForeground(true) }
        previewFrame.addView(preview, FrameLayout.LayoutParams(-1, -1))
        nativeLayer = FrameLayout(this).apply { clipChildren = false; clipToPadding = false }
        preview.addView(nativeLayer, FrameLayout.LayoutParams(-1, -1))
        preview.onNativeGeometry = ::positionNativeItems
        preview.onStatus = { diagnostics = it }
        preview.onRenderedProgress = { renderedProgress = it }
        preview.onProgress = {
            state.setNumber("progress", it)
            if (sample == Sample.VOLUME) {
                volumeLevels[volumeStream] = it
                if (it > 0f) volumeSavedLevels[volumeStream] = it
            }
        }
        root.addView(previewFrame, LinearLayout.LayoutParams(-1, dp(330)).apply { topMargin = dp(14) })

        val browse = column()
        root.addView(ScrollView(this).apply { addView(browse); isFillViewport = true }, LinearLayout.LayoutParams(-1, 0, 1f))
        buildSampleChoices(browse)
        componentOptions = column().apply {
            background = rounded(0xff1b2737.toInt(), dp(16))
            setPadding(dp(12), dp(8), dp(12), dp(8))
        }
        browse.addView(componentOptions, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })

        val footer = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(12), 0, dp(4))
        }
        motionButton = action("Still") { cycleMotion() }
        footer.addView(motionButton)
        footer.addView(label("Drag cards · tap native controls · customize material", 12f, color = 0xffb9c4d2.toInt()).apply {
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(8), 0, 0, 0)
        }, LinearLayout.LayoutParams(0, -2, 1f))
        browse.addView(footer)
        browse.addView(label("Engine-rendered glass with native Android text, icons and controls.", 11f, color = 0xff91a0b3.toInt()).apply {
            setPadding(0, dp(4), 0, dp(4))
        })

        configureSample(sample)
        savedInstanceState?.let {
            restoreMaterial(it.getBundle("material"))
            notificationExpanded = it.getBoolean("notificationExpanded")
            notificationReveal = if (notificationExpanded) 1f else 0f
            if (sample in listOf(Sample.LOCAL_LENS, Sample.CARD, Sample.CLASSIC, Sample.GEOMETRY)) refreshStudyItems()
            if (state.motion !in motionChoices().map { choice -> choice.first }) state.motion = 0
            preview.applyState(state)
            applyNativeInk()
            rebuildComponentOptions()
            motionButton.text = motionLabel()
            it.getFloatArray("positions")?.let { positions -> runCatching { preview.restoreRegionPositions(positions) } }
        }
        preview.visibility = if (previewHidden) View.INVISIBLE else View.VISIBLE
        root.requestApplyInsets()
    }

    private fun column() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    private fun label(value: String, size: Float, color: Int = Color.WHITE, bold: Boolean = false): TextView =
        InkTextView(this).apply {
            text = value
            baseSizeSp = size
            setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
            setTextColor(color)
            if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
            includeFontPadding = true
        }

    private fun action(value: String, run: () -> Unit): TextView = label(value, 14f, 0xffe7effa.toInt(), true).apply {
        gravity = Gravity.CENTER
        setPadding(dp(12), dp(9), dp(12), dp(9))
        background = rounded(0xff344358.toInt(), dp(18))
        isClickable = true
        isFocusable = true
        setOnClickListener { run() }
    }

    private fun rounded(color: Int, radius: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius.toFloat()
    }

    private fun chevron(up: Boolean): Drawable = object : Drawable() {
        private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = dp(2).toFloat()
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        override fun draw(canvas: Canvas) {
            val cx = bounds.exactCenterX()
            val cy = bounds.exactCenterY()
            val half = dp(4).toFloat()
            val path = Path()
            if (up) {
                path.moveTo(cx - half, cy + half / 2)
                path.lineTo(cx, cy - half / 2)
                path.lineTo(cx + half, cy + half / 2)
            } else {
                path.moveTo(cx - half, cy - half / 2)
                path.lineTo(cx, cy + half / 2)
                path.lineTo(cx + half, cy - half / 2)
            }
            canvas.drawPath(path, stroke)
        }
        override fun setAlpha(alpha: Int) { stroke.alpha = alpha; invalidateSelf() }
        override fun setColorFilter(colorFilter: ColorFilter?) { stroke.colorFilter = colorFilter; invalidateSelf() }
        @Suppress("DEPRECATION") override fun getOpacity() = PixelFormat.TRANSLUCENT
    }

    private fun buildSampleChoices(parent: LinearLayout) {
        sampleChoices.clear()
        SampleGroup.values().forEach { group ->
            parent.addView(label(group.title, 11f, color = 0xff9faec0.toInt(), bold = true).apply {
                letterSpacing = .12f
                setPadding(dp(2), dp(12), 0, dp(5))
            })
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            Sample.values().filter { it.group == group }.forEach { option ->
                val choice = action(option.title) { configureSample(option) }
                choice.tag = option
                sampleChoices[option] = choice
                row.addView(choice, LinearLayout.LayoutParams(-2, -2).apply { rightMargin = dp(8) })
            }
            parent.addView(HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
                addView(row)
            })
        }
        updateSampleSelection()
    }

    private fun updateSampleSelection() {
        sampleChoices.forEach { (option, view) ->
            view.background = rounded(if (option == sample) 0xff59799e.toInt() else 0xff344358.toInt(), dp(18))
        }
    }

    private fun configureSample(next: Sample) {
        state.setFlag("verticalSlider", false)
        state.setFlag("controlMaskPreview", next == Sample.MASKS && maskProfile == 3)
        state.setFlag("policyProbe", next == Sample.POLICY)
        if (next != Sample.MASKS) { state.setNumber("regionClip", 1f); state.setNumber("regionAlpha", 1f) }
        preview.useNativeForeground(next != Sample.POLICY)
        nativeLayer.visibility = if (next == Sample.POLICY) View.GONE else View.VISIBLE
        volumeIcon = null; volumeValue = null; volumeTitle = null
        if (next != Sample.QUICK_SETTINGS) { qsPageAnimator?.cancel(); qsPageAnimator = null }
        qsAnimators.values.toList().forEach { it.end() }
        qsAnimators.clear()
        qsParts.clear()
        buttonParts.clear()
        preview.setRegionPageOffset(0f)
        preview.setRegionActivity(floatArrayOf())
        notificationAnimator?.cancel()
        notificationAnimator = null
        sample = next
        baseBounds.clear()
        nativeLayer.removeAllViews()
        materialItems.clear()
        notificationParts.clear()
        notificationExpanded = false
        notificationReveal = 0f
        notificationExpandButton = null
        notificationGroupChildren = null
        when (next) {
            Sample.NOTIFICATION -> {
                state.profile = 3; state.scene = 1
                state.setNumber("width", .98f); state.setNumber("height", .44f); state.setNumber("offset", .5f)
                if (notificationContainer) {
                    materialItems += column().apply {
                        setPadding(dp(4), dp(3), dp(4), dp(3))
                        addView(LinearLayout(this@MainActivity).apply {
                            gravity = Gravity.CENTER_VERTICAL
                            setPadding(dp(14), dp(3), dp(10), 0)
                            addView(label("3 notifications", 12f, 0xffe2eaf4.toInt(), true), LinearLayout.LayoutParams(0, -2, 1f))
                            addView(notificationExpandControl(), LinearLayout.LayoutParams(dp(32), dp(32)))
                        })
                        addView(notificationCard("Messenger", "Amel Bouzaiene", "Can you send me the photo?", false))
                        val children = column().apply {
                            visibility = View.GONE
                            addView(notificationDivider())
                            addView(notificationCard("Calendar", "Team reminder", "Design review starts in 10 minutes.", false))
                            addView(notificationDivider())
                            addView(notificationCard("System", "Connection", "Your devices are connected.", false))
                        }
                        notificationGroupChildren = children
                        addView(children)
                    }
                } else {
                    materialItems += notificationCard("Messenger", "Amel Bouzaiene", "Can you send me the photo?", true, expandable = true)
                }
            }
            Sample.QUICK_SETTINGS -> {
                state.profile = 4; state.scene = 5; state.setNumber("count", 4f); state.setNumber("radius", 72f)
                materialItems += qsPages[qsPage].map { tile(it) }
                submitQsActivity()
            }
            Sample.BRIGHTNESS -> {
                state.profile = 4; state.scene = 0
                state.setNumber("width", .98f); state.setNumber("height", .56f); state.setNumber("progress", .62f)
                materialItems += brightnessCard()
            }
            Sample.VOLUME -> {
                state.profile = 4; state.scene = 0; state.setFlag("verticalSlider", true)
                state.setNumber("progress", volumeLevels.getValue(volumeStream))
                state.setNumber("width", .32f); state.setNumber("height", .9f); state.setNumber("offset", .5f)
                materialItems += volumeCard()
            }
            Sample.BUTTONS -> {
                state.profile = 4; state.scene = 7; state.setNumber("count", 4f)
                materialItems += listOf("Airplane" to "✈", "Cast" to "▣", "Alarm" to "◷", "Home" to "⌂").map { (name, icon) -> toggleTile(name, icon) }
                submitButtonActivity()
            }
            Sample.MERGE -> {
                state.profile = 2; state.scene = 6; state.setNumber("count", 2f)
                state.setNumber("merge", 36f)
                materialItems += listOf(blockCard("Glass shape A", "Drag toward B"), blockCard("Glass shape B", "Smooth union"))
            }
            Sample.RIPPLES -> {
                state.profile = 1; state.scene = 1
                state.setNumber("width", .9f); state.setNumber("height", .72f)
                state.setFlag("touchRipples", true); state.setFlag("pressEffects", true)
                materialItems += blockCard("Touch the material", "Press, move and release to emit a ripple")
            }
            Sample.MOVING_CARDS -> {
                state.profile = 3; state.scene = 6; state.setNumber("count", 3f)
                materialItems += listOf(
                    notificationCard("ChatGPT", "Codex", "Build is ready to review.", false),
                    notificationCard("Messages", "Amel", "See you later!", false),
                    notificationCard("System", "Connection", "Your devices are connected.", false)
                )
            }
            Sample.LOCAL_LENS, Sample.CARD, Sample.CLASSIC -> {
                state.profile = when (next) { Sample.LOCAL_LENS -> 0; Sample.CARD -> 1; else -> 5 }
                state.scene = 1; state.setNumber("width", .9f); state.setNumber("height", .65f)
                materialItems += blockCard(next.title, "Native foreground over the selected engine material")
            }
            Sample.GEOMETRY -> {
                state.profile = 4; state.scene = 1
                state.setNumber("width", .85f); state.setNumber("height", .7f)
                materialItems += blockCard("Shape study", "Corners, clipping and transforms")
            }
            Sample.MASKS -> {
                state.profile = maskProfile; state.scene = 5
                state.setNumber("count", state.number("count").coerceIn(1f, if (maskProfile == 3) 13f else 16f))
                repeat(state.number("count").roundToInt()) { materialItems += regionMaskCard(it) }
            }
            Sample.ICONS -> {
                state.profile = 1; state.scene = 1
                state.setNumber("width", .95f); state.setNumber("height", .65f)
                materialItems += iconStudy()
            }
            Sample.POLICY -> {
                state.profile = 1; state.scene = 1; state.text = "Contrast sample"
                state.setNumber("width", .9f); state.setNumber("height", .6f)
            }
        }
        attachMaterialItems(next)
        if (state.motion !in motionChoices().map { it.first }) state.motion = 0
        preview.resetInteraction()
        preview.applyState(state)
        applyNativeInk()
        updateSampleSelection()
        rebuildComponentOptions()
        motionButton.text = motionLabel()
    }

    private fun attachMaterialItems(next: Sample) {
        materialItems.forEach { item ->
            var downX = 0f
            var downY = 0f
            if (next == Sample.NOTIFICATION || next == Sample.VOLUME) {
                item.clipToOutline = true
                item.outlineProvider = object : android.view.ViewOutlineProvider() {
                    override fun getOutline(view: View, outline: android.graphics.Outline) {
                        outline.setRoundRect(0, 0, view.width, view.height, minOf(state.number("radius") * density, view.width / 2f, view.height / 2f))
                    }
                }
            }
            nativeLayer.addView(item, FrameLayout.LayoutParams(1, 1))
            item.setOnTouchListener { view, event ->
                preview.forwardNativeTouch(view, event)
                if (next == Sample.QUICK_SETTINGS) {
                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN -> { downX = event.rawX; downY = event.rawY }
                        MotionEvent.ACTION_UP -> {
                            val dx = event.rawX - downX; val dy = event.rawY - downY
                            if (kotlin.math.abs(dx) > dp(48) && kotlin.math.abs(dx) > kotlin.math.abs(dy) * 1.5f) changeQsPage(if (dx < 0) 1 else -1)
                            else if (kotlin.math.abs(dx) < dp(12) && kotlin.math.abs(dy) < dp(12)) view.performClick()
                        }
                    }
                    true
                } else next in listOf(Sample.BRIGHTNESS, Sample.VOLUME, Sample.MOVING_CARDS, Sample.MERGE, Sample.RIPPLES)
            }
        }
    }

    private fun notificationCard(app: String, sender: String, message: String, actions: Boolean, expandable: Boolean = false): View {
        val compact = notificationContainer && sample == Sample.NOTIFICATION
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(if (compact) 8 else 12), dp(14), dp(if (compact) 6 else 10))
        }
        val row = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        val avatar = label(if (app == "Messenger") "M" else "◉", 20f, 0xff101621.toInt(), true).apply {
            gravity = Gravity.CENTER
            background = rounded(0xffd9e7f8.toInt(), dp(28))
        }
        row.addView(avatar, LinearLayout.LayoutParams(dp(if (compact) 32 else 42), dp(if (compact) 32 else 42)).apply { rightMargin = dp(12) })
        val copy = column()
        copy.addView(label(if (compact) "$app · $sender" else "$app · 2m", 12f, 0xffe2eaf4.toInt()).apply { maxLines = 1; ellipsize = TextUtils.TruncateAt.END })
        if (!compact) copy.addView(label(sender, 15f, Color.WHITE, true))
        row.addView(copy, LinearLayout.LayoutParams(0, -2, 1f))
        val expand = if (expandable) notificationExpandControl() else InkImageButton(this).apply { visibility = View.INVISIBLE }
        row.addView(expand, LinearLayout.LayoutParams(dp(32), dp(32)))
        card.addView(row)
        val messageView = label(message, 14f, Color.WHITE).apply { setPadding(dp(if (compact) 44 else 54), dp(3), 0, dp(2)); maxLines = if (compact) 1 else 2; ellipsize = TextUtils.TruncateAt.END }
        card.addView(messageView)
        val details = column().apply {
            visibility = View.GONE
            setPadding(dp(54), dp(6), 0, 0)
            addView(label("I will send it now.", 14f, Color.WHITE))
            addView(label("Photo · 2 items", 12f, 0xffe2eaf4.toInt()).apply { setPadding(0, dp(3), 0, 0) })
        }
        card.addView(details)
        var actionRow: View? = null
        if (actions) {
            val buttons = LinearLayout(this).apply { gravity = Gravity.END }
            buttons.addView(action("Like") { toast("Native notification action") }.apply { background = selectableItemBackgroundBorderless() })
            buttons.addView(Space(this), LinearLayout.LayoutParams(dp(8), 1))
            buttons.addView(action("Reply") { toast("Native reply action") }.apply { background = selectableItemBackgroundBorderless() })
            card.addView(buttons)
            actionRow = buttons
        }
        notificationParts += NotificationParts(messageView, details, actionRow)
        applyNotificationOptions()
        return card
    }

    private fun notificationExpandControl() = InkImageButton(this).apply {
        setImageDrawable(chevron(up = false))
        imageTintList = ColorStateList.valueOf(Color.WHITE)
        background = selectableItemBackgroundBorderless()
        contentDescription = "Expand notification"
        isFocusable = true
        setOnClickListener { toggleNotificationExpansion() }
        notificationExpandButton = this
    }

    private fun toggleNotificationExpansion() {
        notificationAnimator?.cancel()
        notificationExpanded = !notificationExpanded
        notificationAnimator = ValueAnimator.ofFloat(notificationReveal, if (notificationExpanded) 1f else 0f).apply {
            duration = if (state.flag("reduceMotion")) 0 else 240
            addUpdateListener {
                notificationReveal = it.animatedValue as Float
                val expandedHeight = if (notificationContainer) .9f else .78f
                state.setNumber("height", .44f + (expandedHeight - .44f) * notificationReveal)
                preview.applyState(state)
            }
            start()
        }
    }

    private fun notificationDivider() = View(this).apply {
        setBackgroundColor(0x44ffffff)
        layoutParams = LinearLayout.LayoutParams(-1, dp(1)).apply { leftMargin = dp(56); rightMargin = dp(12) }
    }

    private fun regionMaskCard(index: Int): View = FrameLayout(this).apply {
        addView(label("${index + 1}", 14f, Color.WHITE, true).apply { gravity = Gravity.CENTER }, FrameLayout.LayoutParams(-1, -1))
        if (maskProfile == 3 && index < 10) addView(InkImageButton(this@MainActivity).apply {
            setImageDrawable(chevron(false)); background = selectableItemBackgroundBorderless()
            contentDescription = "Control ${index + 1}"
            setOnClickListener { toast("Control ${index + 1}") }
        }, FrameLayout.LayoutParams(dp(26), dp(18), Gravity.TOP or Gravity.END).apply { topMargin = dp(9); rightMargin = dp(7) })
    }

    private fun iconStudy(): View = column().apply {
        gravity = Gravity.CENTER
        addView(label("Native glyphs", 16f, Color.WHITE, true).apply { gravity = Gravity.CENTER })
        val row = LinearLayout(this@MainActivity).apply { gravity = Gravity.CENTER }
        val bitmap = android.graphics.Bitmap.createBitmap(dp(32), dp(32), android.graphics.Bitmap.Config.ARGB_8888)
        getDrawable(android.R.drawable.ic_lock_silent_mode_off)?.apply { setBounds(0, 0, bitmap.width, bitmap.height); draw(Canvas(bitmap)) }
        listOf<Drawable?>(getDrawable(android.R.drawable.btn_star_big_on), android.graphics.drawable.BitmapDrawable(resources, bitmap), chevron(false)).forEachIndexed { index, glyph ->
            row.addView(InkImageButton(this@MainActivity).apply {
                setImageDrawable(glyph); background = selectableItemBackgroundBorderless()
                contentDescription = listOf("Platform drawable", "Bitmap glyph", "Path glyph")[index]
                setOnClickListener { toast(contentDescription.toString()) }
            }, LinearLayout.LayoutParams(dp(52), dp(52)).apply { setMargins(dp(8), dp(8), dp(8), dp(8)) })
        }
        addView(row)
        addView(label("Bitmap · platform drawable · path", 11f).apply { gravity = Gravity.CENTER })
    }

    private fun refreshMaskItems() {
        nativeLayer.removeAllViews(); materialItems.clear(); baseBounds.clear()
        repeat(state.number("count").roundToInt()) { materialItems += regionMaskCard(it) }
        attachMaterialItems(sample); preview.resetInteraction(); preview.applyState(state); applyNativeInk()
    }

    private fun tile(spec: QsTileSpec): View = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(8), dp(12), dp(8))
        val iconView = label(spec.icon, 23f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER
        }
        addView(iconView, LinearLayout.LayoutParams(dp(40), dp(40)).apply { rightMargin = dp(8) })
        val detailView = label("", 12f, 0xffe2eaf4.toInt())
        addView(column().apply {
            addView(label(spec.title, 14f, Color.WHITE, true).apply { maxLines = 1; ellipsize = TextUtils.TruncateAt.END })
            addView(detailView.apply { maxLines = 1; ellipsize = TextUtils.TruncateAt.END })
        }, LinearLayout.LayoutParams(0, -2, 1f))
        isClickable = true
        isFocusable = true
        qsParts += QsTileParts(spec, this, iconView, detailView)
        setOnClickListener {
            val enabled = !(qsEnabled[spec.id] ?: false)
            qsEnabled[spec.id] = enabled
            qsAnimators.remove(spec.id)?.cancel()
            qsAnimators[spec.id] = ValueAnimator.ofFloat(qsAmounts[spec.id] ?: 0f, if (enabled) 1f else 0f).apply {
                duration = if (state.flag("reduceMotion")) 0 else 180
                addUpdateListener { qsAmounts[spec.id] = it.animatedValue as Float; submitQsActivity() }
                start()
            }
        }
    }

    private fun submitQsActivity() {
        preview.setRegionActivity(qsPages[qsPage].map { qsAmounts[it.id] ?: 0f }.toFloatArray())
    }

    private fun commitQsForeground() {
        qsParts.forEach { part ->
            val enabled = qsEnabled[part.spec.id] ?: false
            val detail = if (enabled) part.spec.detail else "Off"
            if (part.detail.text.toString() != detail) part.detail.text = detail
            part.root.isSelected = enabled
            val description = "${part.spec.title}, ${if (enabled) "On" else "Off"}"
            if (part.root.contentDescription != description) part.root.contentDescription = description
            part.icon.alpha = .65f + .35f * (qsAmounts[part.spec.id] ?: 0f)
        }
    }

    private fun changeQsPage(direction: Int) {
        if (sample != Sample.QUICK_SETTINGS || qsPageAnimator?.isRunning == true) return
        val destination = (qsPage + direction + qsPages.size) % qsPages.size
        var swapped = false
        qsPageAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = if (state.flag("reduceMotion")) 0 else 280
            addUpdateListener {
                val fraction = it.animatedValue as Float
                if (fraction >= .5f && !swapped) {
                    swapped = true
                    qsPage = destination
                    configureSample(Sample.QUICK_SETTINGS)
                }
                preview.setRegionPageOffset(if (fraction < .5f) -direction * fraction * 2f else direction * (1f - fraction) * 2f)
            }
            start()
        }
    }

    private fun brightnessCard(): View = column().apply {
        setPadding(dp(16), dp(12), dp(16), dp(12))
        val heading = LinearLayout(this@MainActivity).apply { gravity = Gravity.CENTER_VERTICAL }
        heading.addView(label("☼", 22f, Color.WHITE, true))
        heading.addView(label("Brightness", 15f, Color.WHITE, true).apply { setPadding(dp(10), 0, 0, 0) })
        heading.addView(Space(this@MainActivity), LinearLayout.LayoutParams(0, 1, 1f))
        addView(heading)
    }

    private fun volumeCard(): View = FrameLayout(this).apply {
        val rail = column().apply {
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(8), dp(10), dp(8), dp(10))
            addView(InkImageButton(this@MainActivity).apply {
                background = selectableItemBackgroundBorderless()
                imageTintList = ColorStateList.valueOf(Color.WHITE)
                setOnClickListener { toggleVolumeMute() }
                volumeIcon = this
            }, LinearLayout.LayoutParams(dp(44), dp(44)))
            volumeTitle = label(volumeStream, 12f, Color.WHITE, true).apply { gravity = Gravity.CENTER }
            addView(volumeTitle)
        }
        addView(rail, FrameLayout.LayoutParams(-1, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL))
        addView(column().apply {
            gravity = Gravity.CENTER_HORIZONTAL
            volumeValue = label("", 12f, Color.WHITE, true).apply { gravity = Gravity.CENTER }
            addView(volumeValue)
            addView(label("⋯", 22f, Color.WHITE, true).apply {
                gravity = Gravity.CENTER
                background = selectableItemBackgroundBorderless()
                contentDescription = "Choose volume stream"
                setOnClickListener { showVolumeStreams() }
            }, LinearLayout.LayoutParams(dp(44), dp(40)))
        }, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL))
    }

    private fun toggleVolumeMute() {
        val current = state.number("progress")
        if (current > 0f) volumeSavedLevels[volumeStream] = current
        val next = if (current > 0f) 0f else volumeSavedLevels[volumeStream] ?: .5f
        volumeLevels[volumeStream] = next
        state.setNumber("progress", next)
        preview.applyState(state)
    }

    private fun selectVolumeStream(stream: String) {
        volumeStream = stream
        state.setNumber("progress", volumeLevels.getValue(stream))
        preview.applyState(state)
        rebuildComponentOptions()
    }

    private fun showVolumeStreams() {
        val streams = volumeLevels.keys.toTypedArray()
        AlertDialog.Builder(this).setTitle("Preview volume stream")
            .setSingleChoiceItems(streams, streams.indexOf(volumeStream)) { dialog, index -> selectVolumeStream(streams[index]); dialog.dismiss() }
            .setNegativeButton("Cancel", null).show()
    }

    private fun commitVolumeForeground() {
        val muted = renderedProgress <= 0f
        val description = if (muted) "Unmute $volumeStream" else "Mute $volumeStream"
        volumeIcon?.let {
            if (it.contentDescription != description) {
                it.contentDescription = description
                it.setImageResource(if (muted) android.R.drawable.ic_lock_silent_mode else android.R.drawable.ic_lock_silent_mode_off)
            }
        }
        val value = "${(renderedProgress * 100).roundToInt()}%"
        if (volumeValue?.text?.toString() != value) volumeValue?.text = value
        if (volumeTitle?.text?.toString() != volumeStream) volumeTitle?.text = volumeStream
    }

    private fun toggleTile(title: String, icon: String): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        addView(label(icon, 25f, Color.WHITE, true).apply { gravity = Gravity.CENTER })
        addView(label(title, 12f, Color.WHITE, true).apply { gravity = Gravity.CENTER; setPadding(0, dp(2), 0, 0) })
        buttonParts += title to this
        setOnClickListener {
            buttonStates[title] = !(buttonStates[title] ?: false)
            submitButtonActivity()
        }
        isClickable = true
        isFocusable = true
    }

    private fun submitButtonActivity() = preview.setRegionActivity(buttonParts.map { if (buttonStates[it.first] == true) 1f else 0f }.toFloatArray())

    private fun commitButtonForeground() {
        buttonParts.forEachIndexed { index, (title, view) ->
            val disabled = state.flag("disableLastButton") && index == buttonParts.lastIndex
            val on = buttonStates[title] ?: false
            view.isEnabled = !disabled
            view.isSelected = on
            view.alpha = if (disabled) .35f else if (on) 1f else .72f
            val description = "$title, ${if (disabled) "Disabled" else if (on) "On" else "Off"}"
            if (view.contentDescription != description) view.contentDescription = description
        }
    }

    private fun blockCard(title: String, detail: String): View = column().apply {
        gravity = Gravity.CENTER
        setPadding(dp(18), dp(14), dp(18), dp(14))
        addView(label(title, 17f, Color.WHITE, true).apply { gravity = Gravity.CENTER })
        addView(label(detail, 12f, 0xffe2eaf4.toInt()).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(5), 0, 0)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
        })
    }

    /** Track the same shape coordinates as the engine; native widgets render after the shader. */
    private fun positionNativeItems(rects: List<RectF>, scale: Float, rotation: Float, alpha: Float, clip: Float) {
        if (sample == Sample.NOTIFICATION) applyNotificationOptions()
        if (sample == Sample.QUICK_SETTINGS) commitQsForeground()
        if (sample == Sample.VOLUME) commitVolumeForeground()
        if (sample == Sample.BUTTONS) commitButtonForeground()
        nativeLayer.pivotX = preview.width / 2f
        nativeLayer.pivotY = preview.height / 2f
        nativeLayer.scaleX = scale
        nativeLayer.scaleY = scale
        nativeLayer.rotation = rotation
        nativeLayer.alpha = alpha
        nativeLayer.clipBounds = Rect(0, 0, (preview.width * clip).roundToInt(), preview.height)
        for (index in materialItems.indices) {
            val item = materialItems[index]
            val rect = rects.getOrNull(index)
            if (rect == null) { item.visibility = View.INVISIBLE; continue }
            item.visibility = View.VISIBLE
            var base = baseBounds[item]
            if (base == null || baseBounds.size != materialItems.size) {
                val left = rect.left.roundToInt(); val top = rect.top.roundToInt()
                val width = max(1, rect.width().roundToInt()); val height = max(1, rect.height().roundToInt())
                item.layoutParams = FrameLayout.LayoutParams(width, height).apply { leftMargin = left; topMargin = top }
                item.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                item.layout(left, top, left + width, top + height)
                base = RectF(left.toFloat(), top.toFloat(), (left + width).toFloat(), (top + height).toFloat())
                baseBounds[item] = base
            } else if ((state.motion == 0 || sample == Sample.NOTIFICATION) && (rect.width().roundToInt() != base.width().roundToInt() || rect.height().roundToInt() != base.height().roundToInt())) {
                // Native expand/collapse changes content layout and glass bounds together in the preview frame.
                val left = rect.left.roundToInt(); val top = rect.top.roundToInt()
                val width = max(1, rect.width().roundToInt()); val height = max(1, rect.height().roundToInt())
                item.layoutParams = FrameLayout.LayoutParams(width, height).apply { leftMargin = left; topMargin = top }
                item.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                item.layout(left, top, left + width, top + height)
                base = RectF(left.toFloat(), top.toFloat(), (left + width).toFloat(), (top + height).toFloat())
                baseBounds[item] = base
            }
            item.pivotX = 0f
            item.pivotY = 0f
            item.translationX = rect.left - base.left
            item.translationY = rect.top - base.top
            item.scaleX = rect.width() / max(1f, base.width())
            item.scaleY = rect.height() / max(1f, base.height())
            if (sample == Sample.MASKS) {
                item.alpha = if (index % 2 == 1) state.number("regionAlpha") else 1f
                item.clipBounds = if (maskProfile == 4) Rect(0, 0, (item.width * state.number("regionClip")).roundToInt(), item.height) else null
            }
            if (sample == Sample.NOTIFICATION || sample == Sample.VOLUME) item.invalidateOutline()
        }
    }

    private fun motionChoices(): List<Pair<Int, String>> = listOf(0 to "Still", 3 to "Fade", 4 to "Scale", 6 to "Backdrop", 8 to "Stress") +
        (if (state.scene in 0..4) listOf(1 to "Move", 2 to "Resize") else emptyList()) +
        (if (state.scene == 0) listOf(5 to "Progress sweep") else emptyList()) +
        (if (sample == Sample.POLICY) listOf(7 to "Profile cycle") else emptyList())

    private fun cycleMotion() {
        val sequence = motionChoices().map { it.first }
        val next = sequence[(sequence.indexOf(state.motion).coerceAtLeast(0) + 1) % sequence.size]
        state.motion = next
        preview.resetMotion()
        preview.applyState(state)
        motionButton.text = motionLabel()
    }

    private fun motionLabel() = motionChoices().firstOrNull { it.first == state.motion }?.second ?: "Still"

    private fun showCustomizer(startTab: String = "Glass") {
        val scroll = ScrollView(this)
        val body = column().apply { setPadding(dp(16), dp(8), dp(16), dp(12)) }
        scroll.addView(body)
        val tabStrip = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val controls = column()
        body.addView(HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(tabStrip) })
        body.addView(controls, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        val tabs = listOf("Glass", "Shape", "Motion", "Touch", "Ink", "Checks")
        fun showTab(tab: String) {
            controls.removeAllViews()
            tabStrip.removeAllViews()
            tabs.forEach { name ->
                tabStrip.addView(action(name) { showTab(name) }, LinearLayout.LayoutParams(-2, -2).apply { rightMargin = dp(6) })
            }
            when (tab) {
                "Glass" -> {
                    if (state.profile == 5) {
                        buildClassicControls(controls)
                    } else {
                    controls.addView(label("Blur renderer", 14f, 0xffdbe5f2.toInt(), true))
                    val blurModes = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                    blurModes.addView(action(if (state.flag("androidBlur")) "Shader" else "Shader · selected") {
                        state.setFlag("androidBlur", false); preview.applyState(state); rebuildComponentOptions(); showTab(tab)
                    }, LinearLayout.LayoutParams(0, -2, 1f).apply { rightMargin = dp(6) })
                    blurModes.addView(action(if (state.flag("androidBlur")) "Android · selected" else "Android RenderEffect") {
                        state.setFlag("androidBlur", true); preview.applyState(state); rebuildComponentOptions(); showTab(tab)
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                    if (state.profile in 2..4) controls.addView(blurModes)
                    for (i in 0 until blurModes.childCount) {
                        blurModes.getChildAt(i).isEnabled = state.profile in 1..4
                        blurModes.getChildAt(i).alpha = if (state.profile in 1..4) 1f else .45f
                    }
                    controls.addView(label(
                        if (state.profile == 0) "Local lens uses its own material and blur path."
                        else if (state.profile == 1) "Card material consumes an Android-filtered backdrop. Use region materials for a shader/Android blur comparison."
                        else if (state.flag("androidBlur") && sample in listOf(Sample.BRIGHTNESS, Sample.VOLUME)) "Android RenderEffect is clipped to the slider progress fill. Shader blur is disabled for that comparison."
                        else if (state.flag("androidBlur")) "Android RenderEffect blurs the complete local sample; shader blur is disabled for this comparison."
                        else "The selected material shader supplies the backdrop blur. Android RenderEffect is disabled for this comparison.",
                        12f, 0xffaebbd0.toInt()
                    ))
                    addSlider(controls, "Blur strength", "blurStrength", 0f, 100f, "%")
                    addSlider(controls, "Refraction", "refraction", 0f, 240f, "")
                    addSlider(controls, "Glass tint", "glassTintStrength", 0f, 1f, "")
                    addSlider(controls, "Saturation", "saturation", 0f, 200f, "%")
                    addCatalogControls(controls, listOf("bevel", "falloff", "dispersion", "specular", "softness", "baseVeil", "dimming", "lightAngle"))
                    if (state.profile in listOf(3, 4)) addCatalogControls(controls, listOf("regularToneStrength"))
                    check(controls, "Outward refraction", "outward")
                    check(controls, "Live lighting", "sensorLighting")
                    if ((state.profile == 1 || (state.flag("androidBlur") && state.profile in 2..4)) && state.scene != 0) check(controls, "Reduced-resolution Android preblur", "kawasePreblur")
                    controls.addView(action("Material tint color") { chooseInkColor("glassTintColor", null) { showTab(tab) } })
                    controls.addView(action(if (state.flag("regular")) "Use clear glass" else "Use regular glass") {
                        state.setFlag("regular", !state.flag("regular")); preview.applyState(state); showTab(tab)
                    })
                    }
                    controls.addView(action("Change backdrop") { background = (background + 1) % 5; state.background = background; preview.applyState(state) })
                }
                "Shape" -> {
                    if (state.scene != 2 && state.scene != 3 && !state.flag("asymmetric")) addSlider(controls, "Corner radius", "radius", 0f, 100f, "dp")
                    if (state.profile in listOf(2, 3) || (state.profile == 0 && state.scene == 4)) addSlider(controls, "Merge distance", "merge", 0f, 100f, "dp")
                    if (state.scene in 0..3) {
                        addSlider(controls, "Material width", "width", .2f, 1f, "")
                        addSlider(controls, "Material height", "height", .15f, .9f, "")
                    }
                    if (state.profile in listOf(0, 1, 4)) {
                        check(controls, "Independent corners", "asymmetric")
                        addCatalogControls(controls, listOf("cornerTL", "cornerTR", "cornerBR", "cornerBL"))
                    }
                    if (state.scene == 4) addCatalogControls(controls, listOf("separation", "secondaryWidth", "secondaryHeight"))
                }
                "Motion" -> {
                    controls.addView(label("Choose a motion test", 14f, 0xffd8e2ef.toInt(), true))
                    val motionRow = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }.also { row ->
                        motionChoices().forEach { (id, title) ->
                            row.addView(action(title) { state.motion = id; preview.resetMotion(); preview.applyState(state); motionButton.text = motionLabel() }, LinearLayout.LayoutParams(-2, -2).apply { rightMargin = dp(4) })
                        }
                    }
                    controls.addView(HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(motionRow) })
                    check(controls, "Reduce motion", "reduceMotion")
                    addCatalogControls(controls, listOf("speed", "offset", "alpha", "scale", "rotation", "clip"))
                    if (state.scene == 0) controls.addView(label("Progress sweep and Stress animate the displayed level. Return to Still for manual slider input.", 11f, 0xffaebbd0.toInt()))
                }
                "Touch" -> {
                    if (state.profile == 5) {
                        controls.addView(label("Classic material does not use ripple, press or reaction uniforms. Use another material study for touch effects.", 12f, 0xffaebbd0.toInt()))
                    } else {
                    check(controls, "Touch ripples", "touchRipples")
                    check(controls, "Press response", "pressEffects")
                    check(controls, "Touch reaction", "reactionEnabled")
                    addCatalogControls(controls, listOf("reactionIntensity", "rippleStrength", "rippleSpeed", "rippleDamping"))
                    if (sample == Sample.MOVING_CARDS || sample == Sample.MERGE) {
                        check(controls, "Allow card dragging", "dragCards")
                        addCatalogControls(controls, listOf("dragSlop"))
                    }
                    }
                }
                "Ink" -> {
                    addSlider(controls, "Outline width", "outlineWidth", 0f, 3f, "dp")
                    addSlider(controls, "Outline strength", "outlineOpacity", 0f, 100f, "%")
                    addSlider(controls, "Shadow size", "shadowRadius", 0f, 8f, "dp")
                    addSlider(controls, "Shadow strength", "shadowOpacity", 0f, 100f, "%")
                    addSlider(controls, "Shadow horizontal offset", "shadowX", -6f, 6f, "dp")
                    addSlider(controls, "Shadow vertical offset", "shadowY", -6f, 6f, "dp")
                    check(controls, "Automatic outline color", "outlineAuto")
                    check(controls, "Automatic shadow color", "shadowAuto")
                    controls.addView(action("Outline color") { chooseInkColor("outlineColor", "outlineAuto") { showTab(tab) } })
                    controls.addView(action("Shadow color") { chooseInkColor("shadowColor", "shadowAuto") { showTab(tab) } })
                    controls.addView(action("Text and icon color") { chooseInkColor("inkColor", null) { showTab(tab) } })
                    addSlider(controls, "Text size", "font", 12f, 32f, "sp")
                    controls.addView(action("Text color: ${if (state.color("inkColor") == Color.WHITE) "White" else "Dark"}") {
                        state.setColor("inkColor", if (state.color("inkColor") == Color.WHITE) Color.BLACK else Color.WHITE)
                        applyNativeInk(); showTab(tab)
                    })
                    if (sample == Sample.POLICY) check(controls, "Known-backdrop automatic ink", "autoInk")
                }
                "Checks" -> buildExerciseControls(controls) { showTab(tab) }
            }
            for (i in 0 until tabStrip.childCount) {
                val child = tabStrip.getChildAt(i) as TextView
                child.background = rounded(if (child.text == tab) 0xff59799e.toInt() else 0xff344358.toInt(), dp(16))
            }
        }
        val dialog = AlertDialog.Builder(this).setTitle("Customize preview").setView(scroll).setPositiveButton("Done", null).create()
        showTab(startTab)
        dialog.setOnShowListener { dialog.window?.setLayout((resources.displayMetrics.widthPixels * .94f).roundToInt(), (resources.displayMetrics.heightPixels * .82f).roundToInt()) }
        dialog.show()
    }

    private fun addCatalogControls(parent: LinearLayout, keys: List<String>) {
        keys.forEach { key ->
            val control = GlassLabCatalog.byKey.getValue(key)
            if (parent === componentOptions) addComponentSlider(control.label, key, control.low, control.high, control.unit)
            else addSlider(parent, control.label, key, control.low, control.high, control.unit)
        }
    }

    private fun buildClassicControls(parent: LinearLayout) {
        parent.addView(label("Classic material presets", 14f, bold = true))
        val presets = LinearLayout(this)
        repeat(4) { index ->
            presets.addView(action("${index + 1}") {
                state.setNumber("classicPreset", index.toFloat()); preview.applyState(state)
                for (i in 0 until presets.childCount) presets.getChildAt(i).background = rounded(if (i == index) 0xff59799e.toInt() else 0xff344358.toInt(), dp(18))
            }.apply { background = rounded(if (index == state.number("classicPreset").roundToInt()) 0xff59799e.toInt() else 0xff344358.toInt(), dp(18)) }, LinearLayout.LayoutParams(0, -2, 1f))
        }
        parent.addView(presets)
        addCatalogControls(parent, listOf("classicBlur", "classicRefraction", "classicTint", "classicEdge", "classicContrast"))
        check(parent, "Dark material response", "darkInk")
    }

    private fun addStudyShapes(parent: LinearLayout, scenes: List<Int>) {
        val row = LinearLayout(this)
        scenes.forEach { scene ->
            row.addView(action(GlassLabCatalog.scenes[scene]) {
                state.scene = scene
                state.setFlag("asymmetric", scene == 3)
                if (sample == Sample.GEOMETRY) state.profile = if (scene == 4) 2 else 4
                refreshStudyItems(); rebuildComponentOptions()
            }, LinearLayout.LayoutParams(-2, -2).apply { rightMargin = dp(6) })
        }
        parent.addView(HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(row) })
    }

    private fun refreshStudyItems() {
        nativeLayer.removeAllViews(); materialItems.clear(); baseBounds.clear()
        repeat(if (state.scene == 4) 2 else 1) { materialItems += blockCard(sample.title, "Native content in the material shape") }
        attachMaterialItems(sample); preview.resetInteraction(); preview.applyState(state); applyNativeInk()
    }

    private fun buildExerciseControls(parent: LinearLayout, refresh: () -> Unit) {
        val status = label(preview.report(), 11f, 0xffb9c4d2.toInt()).apply { setTextIsSelectable(true) }
        parent.addView(action("Refresh status") { status.text = preview.report() })
        parent.addView(action("Native RenderNode blur prototype") {
            nativeBlurProbe?.dismiss()
            nativeBlurProbe = NativeBlurProbe(this).also { probe ->
                probe.setOnDismissListener { if (nativeBlurProbe === probe) nativeBlurProbe = null }
                probe.show()
            }
        })
        parent.addView(status)
        parent.addView(action("Run CPU contract checks") {
            AlertDialog.Builder(this).setTitle("CPU checks · GPU pixels not tested").setMessage(preview.runContractChecks()).setPositiveButton("Close", null).show()
        })
        parent.addView(action("Fail next shader submission") {
            state.setFlag("forceFallback", false); state.setFlag("simulatePowerSave", false); state.setFlag("simulateThermal", false)
            preview.applyState(state); preview.injectFailure()
        }.apply { isEnabled = state.profile != 0; alpha = if (isEnabled) 1f else .4f })
        parent.addView(label("Failure injection applies to recorded shader materials. Refresh status after exercising; recovery recreates the renderer.", 11f, 0xffaebbd0.toInt()))
        check(parent, "Force fallback material", "forceFallback")
        check(parent, "Simulate power restriction", "simulatePowerSave")
        check(parent, "Simulate thermal restriction", "simulateThermal")
        check(parent, "Show performance HUD", "performanceHud")
        check(parent, "Pause preview rendering", "paused")
        parent.addView(action(if (previewHidden) "Show preview" else "Hide preview") {
            previewHidden = !previewHidden; preview.visibility = if (previewHidden) View.INVISIBLE else View.VISIBLE; refresh()
        })
        parent.addView(action("Recover normal rendering") {
            listOf("forceFallback", "simulatePowerSave", "simulateThermal", "paused").forEach { state.setFlag(it, false) }
            previewHidden = false; preview.visibility = View.VISIBLE
            preview.recreateRenderer(); preview.applyState(state); refresh()
        })
        parent.addView(action("Recreate renderer") { preview.recreateRenderer(); refresh() })
        parent.addView(action("Recreate activity") { recreate() })
    }

    private fun submitControlChange(key: String) {
        if (sample == Sample.MASKS && key == "count") refreshMaskItems() else preview.applyState(state)
        applyNativeInk()
    }

    private fun addSlider(parent: LinearLayout, title: String, key: String, low: Float, high: Float, unit: String) {
        val heading = label("$title · ${format(state.number(key))}$unit", 13f, 0xffdbe5f2.toInt())
        parent.addView(heading)
        parent.addView(SeekBar(this).apply {
            max = 1000
            progress = (((state.number(key) - low) / (high - low)) * max).roundToInt().coerceIn(0, max)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(seekBar: SeekBar) {}
                override fun onStopTrackingTouch(seekBar: SeekBar) {}
                override fun onProgressChanged(seekBar: SeekBar, value: Int, fromUser: Boolean) {
                    if (!fromUser) return
                    val raw = low + (high - low) * value / max
                    val updated = if (key == "count") raw.roundToInt().toFloat() else raw
                    state.setNumber(key, updated)
                    heading.text = "$title · ${format(updated)}$unit"
                    submitControlChange(key)
                    rebuildComponentOptions()
                }
            })
        }, LinearLayout.LayoutParams(-1, dp(42)))
    }

    private fun check(parent: LinearLayout, title: String, key: String) {
        parent.addView(CheckBox(this).apply {
            text = title
            setTextColor(Color.WHITE)
            buttonTintList = ColorStateList.valueOf(0xffa9cafa.toInt())
            isChecked = state.flag(key)
            setOnCheckedChangeListener { _, checked -> state.setFlag(key, checked); preview.applyState(state); applyNativeInk() }
        })
    }

    private fun format(value: Float) = if (value >= 10f || value % 1f == 0f) "${value.roundToInt()}" else "%.2f".format(value)

    private fun rebuildComponentOptions() {
        componentOptions.removeAllViews()
        componentOptions.addView(label("COMPONENT OPTIONS · ${sample.title.uppercase()}", 10f, 0xff9faec0.toInt(), true).apply {
            letterSpacing = .08f
            setPadding(0, 0, 0, dp(4))
        })
        when (sample) {
            Sample.NOTIFICATION -> {
                optionCheck("Group notifications in one glass container", notificationContainer) {
                    notificationContainer = it
                    configureSample(Sample.NOTIFICATION)
                }
                optionCheck("Notification text", showNotificationText) { showNotificationText = it; applyNotificationOptions() }
                optionCheck("Action buttons", showNotificationActions) { showNotificationActions = it; applyNotificationOptions() }
                addComponentSlider("Text/icon outline", "outlineWidth", 0f, 3f, "dp")
                addComponentSlider("Text/icon shadow", "shadowOpacity", 0f, 100f, "%")
            }
            Sample.BRIGHTNESS -> {
                componentOptions.addView(action("Open native brightness backend") {
                    nativeBrightnessPreview?.dismiss()
                    nativeBrightnessPreview = NativeBrightnessPreview(this).also { dialog ->
                        dialog.setOnDismissListener { if (nativeBrightnessPreview === dialog) nativeBrightnessPreview = null }
                        dialog.show()
                    }
                })
                val shaderMode = !state.flag("androidBlur")
                addComponentSlider("Progress-region blur", "progressBlur", 0f, 100f, "%")
                addComponentSlider("Level indicator blur", "indicatorBlur", 0f, 100f, "%")
                componentOptions.addView(label(
                    if (shaderMode) "Shader mode blurs the filled progress and indicator masks independently. Drag the glass control to move its glass level indicator."
                    else "Android RenderEffect is clipped to the brightness progress fill in this sample. Drag the glass control to move its glass level indicator.",
                    11f, 0xffaebbd0.toInt()
                ))
            }
            Sample.QUICK_SETTINGS -> {
                componentOptions.addView(LinearLayout(this).apply {
                    gravity = Gravity.CENTER_VERTICAL
                    addView(action("Previous") { changeQsPage(-1) })
                    addView(label("Page ${qsPage + 1} of ${qsPages.size}", 12f).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
                    addView(action("Next") { changeQsPage(1) })
                })
                addComponentSlider("Tile material blur", "blurStrength", 0f, 100f, "%")
                componentOptions.addView(label("Tap tiles to toggle · swipe across tiles to change page. Tile states are retained between pages.", 11f, 0xffaebbd0.toInt()))
            }
            Sample.VOLUME -> {
                componentOptions.addView(action("Stream: $volumeStream") { showVolumeStreams() })
                addComponentSlider("Volume fill blur", "progressBlur", 0f, 100f, "%")
                addComponentSlider("Level indicator blur", "indicatorBlur", 0f, 100f, "%")
                componentOptions.addView(label("Drag up/down to adjust · tap the speaker to mute. Levels are local to this preview.", 11f, 0xffaebbd0.toInt()))
            }
            Sample.BUTTONS -> {
                optionCheck("Disable last button", state.flag("disableLastButton")) { state.setFlag("disableLastButton", it); preview.applyState(state) }
                addComponentSlider("Button outline", "outlineOpacity", 0f, 100f, "%")
                addComponentSlider("Button shadow", "shadowOpacity", 0f, 100f, "%")
            }
            Sample.MERGE -> addComponentSlider("Merge distance", "merge", 0f, 100f, "dp")
            Sample.RIPPLES -> {
                optionCheck("Touch ripples", state.flag("touchRipples")) { state.setFlag("touchRipples", it); preview.applyState(state) }
                optionCheck("Press response", state.flag("pressEffects")) { state.setFlag("pressEffects", it); preview.applyState(state) }
            }
            Sample.MOVING_CARDS -> componentOptions.addView(action("Next motion mode") { cycleMotion() })
            Sample.LOCAL_LENS, Sample.CARD -> {
                addStudyShapes(componentOptions, if (sample == Sample.LOCAL_LENS) listOf(1, 2, 3, 4) else listOf(1, 2, 3))
                addCatalogControls(componentOptions, listOf("blurStrength", "refraction"))
                if (state.scene == 4) addCatalogControls(componentOptions, listOf("merge", "separation", "secondaryWidth", "secondaryHeight"))
            }
            Sample.CLASSIC -> {
                addStudyShapes(componentOptions, listOf(1, 2))
                buildClassicControls(componentOptions)
            }
            Sample.GEOMETRY -> {
                addStudyShapes(componentOptions, listOf(1, 2, 3, 4))
                addCatalogControls(componentOptions, when (state.scene) { 4 -> listOf("radius", "separation", "merge", "secondaryWidth", "secondaryHeight"); 2, 3 -> emptyList(); else -> listOf("radius") })
            }
            Sample.MASKS -> {
                val modes = LinearLayout(this)
                listOf(4 to "Region clipping", 3 to "Control pills").forEach { (profile, title) ->
                    modes.addView(action(title) {
                        maskProfile = profile; state.profile = profile; state.setFlag("controlMaskPreview", profile == 3)
                        state.setNumber("count", state.number("count").coerceAtMost(if (profile == 3) 13f else 16f))
                        refreshMaskItems(); rebuildComponentOptions()
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                }
                componentOptions.addView(modes)
                addComponentSlider("Region count", "count", 1f, if (maskProfile == 3) 13f else 16f, "")
                addCatalogControls(componentOptions, listOf("regionAlpha"))
                if (maskProfile == 4) addCatalogControls(componentOptions, listOf("regionClip"))
                else {
                    addComponentSlider("Control pill blur (shader)", "pillBlur", 0f, 100f, "%", !state.flag("androidBlur"))
                    componentOptions.addView(label("Up to 13 regions and 10 control pills.", 11f, 0xffaebbd0.toInt()))
                    componentOptions.addView(label("Android mode blurs the material input; independent pill diffusion belongs to shader mode.", 11f, 0xffaebbd0.toInt()))
                }
            }
            Sample.ICONS -> componentOptions.addView(action("Tune glyph outline and shadow") { showCustomizer("Ink") })
            Sample.POLICY -> {
                componentOptions.addView(label("Known-input contrast model. Timing knobs validate configuration; they do not simulate cross-window transport.", 11f, 0xffaebbd0.toInt()))
                addCatalogControls(componentOptions, listOf("policyLuma", "policySurround", "toneDuration"))
                GlassLabCatalog.controls.filter { it.group == "Policy tuning" }.forEach { addCatalogControls(componentOptions, listOf(it.key)) }
                check(componentOptions, "Constrain other material", "policyConstrainOther")
            }
        }
    }

    private fun applyNotificationOptions() {
        val revealing = notificationReveal > 0f
        notificationExpandButton?.let {
            if (it.isSelected != notificationExpanded) {
                it.isSelected = notificationExpanded
                it.setImageDrawable(chevron(up = notificationExpanded))
            }
            it.contentDescription = if (notificationExpanded) "Collapse notification" else "Expand notification"
        }
        notificationGroupChildren?.apply {
            visibility = if (revealing) View.VISIBLE else View.GONE
            alpha = notificationReveal
        }
        notificationParts.forEach { parts ->
            parts.message.visibility = if (showNotificationText) View.VISIBLE else View.GONE
            parts.details.visibility = if (showNotificationText && revealing && !notificationContainer) View.VISIBLE else View.GONE
            parts.details.alpha = notificationReveal
            parts.actions?.visibility = if (showNotificationActions && revealing) View.VISIBLE else View.GONE
            parts.actions?.alpha = notificationReveal
        }
    }

    private fun optionCheck(title: String, initial: Boolean, changed: (Boolean) -> Unit) {
        componentOptions.addView(CheckBox(this).apply {
            text = title
            textSize = 12f
            setTextColor(Color.WHITE)
            buttonTintList = ColorStateList.valueOf(0xffa9cafa.toInt())
            isChecked = initial
            setOnCheckedChangeListener { _, checked -> changed(checked) }
        }, LinearLayout.LayoutParams(-1, dp(38)))
    }

    private fun addComponentSlider(title: String, key: String, low: Float, high: Float, unit: String, enabled: Boolean = true) {
        val heading = label("$title · ${format(state.number(key))}$unit", 11f, 0xffdbe5f2.toInt())
        componentOptions.addView(heading)
        componentOptions.addView(SeekBar(this).apply {
            max = 1000
            isEnabled = enabled
            alpha = if (enabled) 1f else .45f
            progress = (((state.number(key) - low) / (high - low)) * max).roundToInt().coerceIn(0, max)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(seekBar: SeekBar) {}
                override fun onStopTrackingTouch(seekBar: SeekBar) {}
                override fun onProgressChanged(seekBar: SeekBar, value: Int, fromUser: Boolean) {
                    if (!fromUser) return
                    val raw = low + (high - low) * value / max
                    val updated = if (key == "count") raw.roundToInt().toFloat() else raw
                    state.setNumber(key, updated)
                    heading.text = "$title · ${format(updated)}$unit"
                    submitControlChange(key)
                }
            })
        }, LinearLayout.LayoutParams(-1, dp(32)))
    }

    private fun selectableItemBackgroundBorderless(): android.graphics.drawable.Drawable? {
        val attributes = obtainStyledAttributes(intArrayOf(android.R.attr.selectableItemBackgroundBorderless))
        return try { attributes.getDrawable(0) } finally { attributes.recycle() }
    }

    private fun chooseInkColor(key: String, autoKey: String?, refresh: () -> Unit) {
        val input = EditText(this).apply { setSingleLine(); setText("#%06X".format(state.color(key) and 0xffffff)) }
        val title = when (key) { "outlineColor" -> "Outline"; "shadowColor" -> "Shadow"; "glassTintColor" -> "Material tint"; else -> "Text and icon" }
        val dialog = AlertDialog.Builder(this).setTitle("$title color")
            .setView(input).setPositiveButton("Apply", null).setNegativeButton("Cancel", null).create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val value = input.text.toString().trim()
                if (!value.matches(Regex("#[0-9a-fA-F]{6}"))) { input.error = "Use #RRGGBB"; return@setOnClickListener }
                state.setColor(key, Color.parseColor(value)); if (autoKey != null) state.setFlag(autoKey, false)
                preview.applyState(state); applyNativeInk(); dialog.dismiss(); refresh()
            }
        }
        dialog.show()
    }

    private fun applyNativeInk() {
        val style = ForegroundInkStyle(mapOf(
            "outlineWidth" to state.number("outlineWidth"), "outlineOpacity" to state.number("outlineOpacity"),
            "shadowRadius" to state.number("shadowRadius"), "shadowOpacity" to state.number("shadowOpacity"),
            "shadowX" to state.number("shadowX"), "shadowY" to state.number("shadowY"),
            "outlineAuto" to state.flag("outlineAuto"), "shadowAuto" to state.flag("shadowAuto"),
            "outlineColor" to "#%06X".format(state.color("outlineColor") and 0xffffff),
            "shadowColor" to "#%06X".format(state.color("shadowColor") and 0xffffff)
        ))
        materialItems.forEach { applyInkTree(it, style) }
    }
    private fun applyInkTree(view: View, style: ForegroundInkStyle) {
        if (view is InkTextView) {
            view.setTextSize(TypedValue.COMPLEX_UNIT_SP, view.baseSizeSp * state.number("font") / 17f)
            view.inkStyle = style
            view.setTextColor(state.color("inkColor"))
            view.invalidate()
        }
        if (view is InkImageButton) view.applyInk(style, state.color("inkColor"))
        if (view is ViewGroup) for (i in 0 until view.childCount) applyInkTree(view.getChildAt(i), style)
    }

    private inner class InkImageButton(context: android.content.Context) : ImageButton(context) {
        private var glyphStyle: ForegroundInkStyle? = null
        private var glyphColor = Color.WHITE
        override fun setImageDrawable(drawable: Drawable?) {
            if (this.drawable !== drawable) (this.drawable as? GlassInkDrawable)?.release()
            val glyph = drawable?.let { if (it is GlassInkDrawable) it else GlassInkDrawable(it) }
            glyph?.configure(glyphStyle ?: ForegroundInkStyle.DEFAULT, if (glyphStyle == null) Color.WHITE else glyphColor, density)
            super.setImageDrawable(glyph)
        }
        override fun setImageResource(resId: Int) { setImageDrawable(if (resId == 0) null else context.getDrawable(resId)) }
        fun applyInk(style: ForegroundInkStyle, color: Int) {
            glyphStyle = style; glyphColor = color
            (drawable as? GlassInkDrawable)?.configure(style, color, density)
            invalidate()
        }
        override fun onDetachedFromWindow() { (drawable as? GlassInkDrawable)?.release(); super.onDetachedFromWindow() }
    }

    private inner class InkTextView(context: android.content.Context) : TextView(context) {
        // App chrome uses this class too, but only sample foregrounds opt into ink styling.
        var baseSizeSp = 14f
        var inkStyle: ForegroundInkStyle? = null
        override fun onDraw(canvas: Canvas) {
            val style = inkStyle ?: return super.onDraw(canvas)
            val p = paint
            val fill = currentTextColor
            try {
                val nativeLayout = layout
                if (style.outlineWidth > 0 && style.outlineOpacity > 0 && nativeLayout != null && nativeLayout.lineCount > 0) {
                    p.clearShadowLayer(); p.style = Paint.Style.STROKE; p.strokeJoin = Paint.Join.ROUND
                    p.strokeWidth = style.outlineWidth * density * 2f; p.color = style.outline(fill)
                    val save = canvas.save()
                    try {
                        canvas.translate((compoundPaddingLeft - scrollX).toFloat(), (baseline - nativeLayout.getLineBaseline(0) - scrollY).toFloat())
                        nativeLayout.draw(canvas)
                    } finally { canvas.restoreToCount(save) }
                }
                p.style = Paint.Style.FILL; p.color = fill
                p.setShadowLayer(style.shadowRadius * density, style.shadowX * density, style.shadowY * density, style.shadow(fill))
                super.onDraw(canvas)
            } finally {
                p.clearShadowLayer(); p.style = Paint.Style.FILL; p.color = fill; p.alpha = 255
            }
        }
    }

    private fun showDiagnostics() {
        AlertDialog.Builder(this)
            .setTitle("Engine status")
            .setMessage("Liquid Glass Engine ${LiquidGlassEngine.VERSION}\n\n$diagnostics\n\n${preview.report()}\n\nThe component preview uses native Android Views. SystemUI hooks and remote surfaces are not used here.")
            .setPositiveButton("Close", null)
            .setNeutralButton("Recreate renderer") { _, _ -> preview.recreateRenderer() }
            .setNegativeButton("Recreate activity") { _, _ -> recreate() }
            .show()
    }

    override fun onStop() {
        nativeBlurProbe?.dismiss()
        super.onStop()
    }

    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    private fun restoreMaterial(bundle: Bundle?) {
        if (bundle == null) return
        GlassLabCatalog.controls.forEach { if (bundle.containsKey(it.key)) state.setNumber(it.key, bundle.getFloat(it.key)) }
        GlassLabCatalog.flags.forEach { if (bundle.containsKey(it)) state.setFlag(it, bundle.getBoolean(it)) }
        GlassLabCatalog.colors.forEach { if (bundle.containsKey(it)) state.setColor(it, bundle.getInt(it)) }
        state.profile = bundle.getInt("profile", state.profile)
        state.scene = bundle.getInt("scene", state.scene)
        state.motion = bundle.getInt("motion", state.motion)
        state.background = bundle.getInt("background", state.background)
        state.text = bundle.getString("text", state.text)
        state.validateSelections()
        background = state.background
    }

    private fun restoreSession(bundle: Bundle) {
        sample = runCatching { Sample.valueOf(bundle.getString("sample", Sample.NOTIFICATION.name)) }.getOrDefault(Sample.NOTIFICATION)
        restoreMaterial(bundle.getBundle("material"))
        showNotificationText = bundle.getBoolean("notificationText", true)
        showNotificationActions = bundle.getBoolean("notificationActions", true)
        notificationContainer = bundle.getBoolean("notificationContainer")
        maskProfile = if (bundle.getInt("maskProfile", 4) == 3) 3 else 4
        previewHidden = bundle.getBoolean("previewHidden")
        qsPage = bundle.getInt("qsPage").coerceIn(qsPages.indices)
        qsPages.flatten().forEach { tile ->
            qsEnabled[tile.id] = bundle.getBoolean("qs.${tile.id}")
            qsAmounts[tile.id] = if (qsEnabled[tile.id] == true) 1f else 0f
        }
        volumeStream = bundle.getString("volumeStream", "Media").takeIf { it in volumeLevels } ?: "Media"
        volumeLevels.keys.toList().forEach {
            val level = bundle.getFloat("volume.$it", volumeLevels.getValue(it))
            if (level.isFinite()) volumeLevels[it] = level.coerceIn(0f, 1f)
            val saved = bundle.getFloat("volumeSaved.$it", .5f)
            if (saved.isFinite()) volumeSavedLevels[it] = saved.coerceIn(0f, 1f)
        }
        listOf("Airplane", "Cast", "Alarm", "Home").forEach { buttonStates[it] = bundle.getBoolean("button.$it") }
    }

    private fun finishPreviewAnimations() {
        notificationAnimator?.end(); notificationAnimator = null
        qsPageAnimator?.end(); qsPageAnimator = null
        qsAnimators.values.toList().forEach { it.end() }; qsAnimators.clear()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        finishPreviewAnimations()
        outState.putString("sample", sample.name)
        outState.putBundle("material", Bundle().apply {
            GlassLabCatalog.controls.forEach { putFloat(it.key, state.number(it.key)) }
            GlassLabCatalog.flags.forEach { putBoolean(it, state.flag(it)) }
            GlassLabCatalog.colors.forEach { putInt(it, state.color(it)) }
            putInt("profile", state.profile); putInt("scene", state.scene); putInt("motion", state.motion)
            putInt("background", state.background); putString("text", state.text)
        })
        outState.putBoolean("notificationText", showNotificationText)
        outState.putBoolean("notificationActions", showNotificationActions)
        outState.putBoolean("notificationContainer", notificationContainer)
        outState.putBoolean("notificationExpanded", notificationExpanded)
        outState.putInt("maskProfile", maskProfile)
        outState.putBoolean("previewHidden", previewHidden)
        outState.putInt("qsPage", qsPage)
        qsEnabled.forEach { (key, value) -> outState.putBoolean("qs.$key", value) }
        outState.putString("volumeStream", volumeStream)
        volumeLevels.forEach { (key, value) -> outState.putFloat("volume.$key", value) }
        volumeSavedLevels.forEach { (key, value) -> outState.putFloat("volumeSaved.$key", value) }
        buttonStates.forEach { (key, value) -> outState.putBoolean("button.$key", value) }
        outState.putFloatArray("positions", preview.saveRegionPositions())
        super.onSaveInstanceState(outState)
    }
    override fun onResume() { super.onResume(); if (::preview.isInitialized) preview.setActive(true) }
    override fun onPause() {
        nativeBrightnessPreview?.dismiss()
        finishPreviewAnimations()
        if (::preview.isInitialized) preview.setActive(false)
        super.onPause()
    }
}
