package com.example.remote_control

/** Observes short Power presses without consuming stock input. */
internal class PowerTapGesture {
    companion object {
        const val QUIET_MS = 550L
        private const val MAX_TAP_MS = 220L
    }

    private val volumeDown = mutableSetOf<PhysicalButton>()
    private var powerDown = false
    private var downAt: Long? = null
    private var lastRelease: Long? = null
    private var count = 0
    private var bindings: ButtonShortcutSettings? = null

    fun cancel() {
        downAt = null
        lastRelease = null
        count = 0
        bindings = null
    }

    fun reset() {
        cancel()
        volumeDown.clear()
        powerDown = false
    }

    fun accept(event: ButtonEvent, allowed: Boolean, startsScreenOff: Boolean, settings: ButtonShortcutSettings) {
        if (event.button != PhysicalButton.POWER) {
            if (event.down) volumeDown.add(event.button) else volumeDown.remove(event.button)
            cancel()
            return
        }
        if (!allowed || volumeDown.isNotEmpty() || (bindings != null && bindings != settings)) cancel()
        if (event.down) {
            if (powerDown) return
            powerDown = true
            val previous = lastRelease
            if (previous == null || event.timeMs - previous !in 0..QUIET_MS) cancel()
            if (allowed && volumeDown.isEmpty() && (count > 0 || startsScreenOff) &&
                (settings.action(PhysicalButton.POWER, ButtonGesture.DOUBLE) != ButtonAction.NONE ||
                    settings.action(PhysicalButton.POWER, ButtonGesture.TRIPLE) != ButtonAction.NONE)) {
                downAt = event.timeMs
                bindings = settings
            }
            return
        }
        powerDown = false
        val start = downAt ?: return
        downAt = null
        if (event.timeMs - start !in 0..MAX_TAP_MS) {
            cancel()
            return
        }
        lastRelease = event.timeMs
        // Four or more presses suppress our action for the whole sequence, including SOS.
        count = (count + 1).coerceAtMost(4)
    }

    fun waiting() = !powerDown && count in 2..3

    fun finish(allowed: Boolean, settings: ButtonShortcutSettings): ButtonAction? {
        val kind = when (count) {
            2 -> ButtonGesture.DOUBLE
            3 -> ButtonGesture.TRIPLE
            else -> null
        }
        val action = if (allowed && !powerDown && bindings == settings && kind != null) {
            settings.action(PhysicalButton.POWER, kind)
        } else ButtonAction.NONE
        cancel()
        return action.takeIf { it != ButtonAction.NONE }
    }
}
