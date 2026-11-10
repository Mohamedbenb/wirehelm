package com.example.remote_control

internal enum class PhysicalButton { VOLUME_UP, VOLUME_DOWN, POWER }

internal data class ButtonEvent(val button: PhysicalButton, val down: Boolean, val timeMs: Long) {
    companion object {
        private val line = Regex("""\[\s*(\d+)\.(\d{6})]\s+EV_KEY\s+KEY_(VOLUMEUP|VOLUMEDOWN|POWER)\s+(DOWN|UP)\s*""")

        fun parse(raw: String): ButtonEvent? {
            val match = line.matchEntire(raw) ?: return null
            val (seconds, micros, key, state) = match.destructured
            val button = when (key) {
                "VOLUMEUP" -> PhysicalButton.VOLUME_UP
                "VOLUMEDOWN" -> PhysicalButton.VOLUME_DOWN
                else -> PhysicalButton.POWER
            }
            return ButtonEvent(button, state == "DOWN", seconds.toLong() * 1000 + micros.toLong() / 1000)
        }
    }
}

internal enum class ButtonAction(val id: String) {
    NONE("none"), TORCH("torch"), RESUME_MEDIA("resume_media"),
    TIMED_TORCH("timed_torch"), RINGER("ringer"), DND("dnd"), BOOKMARK("bookmark");

    companion object {
        fun parse(id: String?) = entries.firstOrNull { it.id == id } ?: NONE
    }
}

internal enum class ButtonGesture(val suffix: String) {
    HOLD(""), DOUBLE("_double"), TRIPLE("_triple"), TAP_HOLD("_tap_hold")
}

internal data class ButtonShortcutSettings(
    val up: ButtonAction,
    val down: ButtonAction,
    val holdMs: Long,
    val extra: Map<String, ButtonAction> = emptyMap(),
    val torchMinutes: Int = 5,
) {
    fun action(button: PhysicalButton, gesture: ButtonGesture = ButtonGesture.HOLD): ButtonAction {
        if (button == PhysicalButton.POWER) return when (gesture) {
            ButtonGesture.DOUBLE, ButtonGesture.TRIPLE -> extra["power" + gesture.suffix] ?: ButtonAction.NONE
            else -> ButtonAction.NONE
        }
        val volumeUp = button == PhysicalButton.VOLUME_UP
        return if (gesture == ButtonGesture.HOLD) {
            if (volumeUp) up else down
        } else {
            val prefix = if (volumeUp) "up" else "down"
            extra[prefix + gesture.suffix] ?: ButtonAction.NONE
        }
    }

    fun assigned() = up != ButtonAction.NONE || down != ButtonAction.NONE ||
        extra.values.any { it != ButtonAction.NONE }

    companion object {
        val extraKeys = listOf("up", "down").flatMap { prefix ->
            ButtonGesture.entries.filter { it != ButtonGesture.HOLD }.map { prefix + it.suffix }
        } + listOf("power_double", "power_triple")
    }
}

/** Recognizes gestures on physical transitions while Android continues to own the keys. */
internal class ButtonHoldGesture {
    companion object { const val TAP_GAP_MS = 330L }

    private data class Press(val event: ButtonEvent, val settings: ButtonShortcutSettings, val precedingTaps: Int)
    private data class Taps(val button: PhysicalButton, val count: Int, val releasedAt: Long,
        val settings: ButtonShortcutSettings)
    private val pressed = mutableSetOf<PhysicalButton>()
    private var press: Press? = null
    private var taps: Taps? = null

    fun cancel() {
        press = null
        taps = null
    }

    fun reset() {
        cancel()
        pressed.clear()
    }

    fun accept(event: ButtonEvent, eligible: Boolean, settings: ButtonShortcutSettings): ButtonAction? {
        if (!eligible) cancel()
        if (event.down) {
            if (!pressed.add(event.button)) return null
            val preceding = taps?.takeIf {
                it.button == event.button && it.settings == settings &&
                    event.timeMs - it.releasedAt in 0..TAP_GAP_MS
            }
            val isolated = pressed.size == 1 && event.button != PhysicalButton.POWER
            press = if (eligible && isolated) Press(event, settings, preceding?.count ?: 0) else null
            taps = null
            return null
        }
        pressed.remove(event.button)
        val pending = press ?: return null
        if (pending.event.button != event.button) return null
        press = null
        if (!eligible || pending.settings != settings) return null
        val duration = event.timeMs - pending.event.timeMs
        if (duration in settings.holdMs..5000) {
            val kind = if (pending.precedingTaps == 1 &&
                settings.action(event.button, ButtonGesture.TAP_HOLD) != ButtonAction.NONE) {
                ButtonGesture.TAP_HOLD
            } else ButtonGesture.HOLD
            return settings.action(event.button, kind).takeIf { it != ButtonAction.NONE }
        }
        if (duration !in 0..250) return null
        val count = pending.precedingTaps + 1
        val triple = settings.action(event.button, ButtonGesture.TRIPLE)
        if (count == 3) return triple.takeIf { it != ButtonAction.NONE }
        val double = settings.action(event.button, ButtonGesture.DOUBLE)
        if (count == 2 && triple == ButtonAction.NONE) return double.takeIf { it != ButtonAction.NONE }
        if (triple != ButtonAction.NONE || double != ButtonAction.NONE ||
            settings.action(event.button, ButtonGesture.TAP_HOLD) != ButtonAction.NONE) {
            taps = Taps(event.button, count, event.timeMs, settings)
        }
        return null
    }

    fun waitingForThirdTap() = taps?.let {
        it.count == 2 && it.settings.action(it.button, ButtonGesture.DOUBLE) != ButtonAction.NONE
    } == true

    fun finishTaps(eligible: Boolean, settings: ButtonShortcutSettings): ButtonAction? {
        val pending = taps ?: return null
        taps = null
        if (!eligible || pending.settings != settings || pending.count != 2) return null
        return settings.action(pending.button, ButtonGesture.DOUBLE).takeIf { it != ButtonAction.NONE }
    }
}
