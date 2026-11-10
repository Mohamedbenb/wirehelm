package com.example.remote_control

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ButtonHoldGestureTest {
    private val settings = ButtonShortcutSettings(ButtonAction.TORCH, ButtonAction.RESUME_MEDIA, 800)

    @Test fun onlyEligibleHoldsFireAndEachButtonHasItsOwnAction() {
        val gesture = ButtonHoldGesture()
        assertNull(gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, true, 100), true, settings))
        assertNull(gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, false, 400), true, settings))
        gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, true, 1000), true, settings)
        assertEquals(ButtonAction.TORCH, gesture.accept(
            ButtonEvent(PhysicalButton.VOLUME_UP, false, 1800), true, settings))
        gesture.accept(ButtonEvent(PhysicalButton.VOLUME_DOWN, true, 2100), true, settings)
        assertEquals(ButtonAction.RESUME_MEDIA, gesture.accept(
            ButtonEvent(PhysicalButton.VOLUME_DOWN, false, 3000), true, settings))
    }

    @Test fun playbackAndPowerCancelAnInProgressHold() {
        val gesture = ButtonHoldGesture()
        gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, true, 100), true, settings)
        gesture.cancel()
        assertNull(gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, false, 1200), true, settings))
        gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, true, 1300), true, settings)
        gesture.accept(ButtonEvent(PhysicalButton.POWER, true, 1600), true, settings)
        assertNull(gesture.accept(ButtonEvent(PhysicalButton.POWER, false, 2700), true, settings))
        assertNull(gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, false, 2800), true, settings))
        gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, true, 3000), false, settings)
        assertNull(gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, false, 4000), true, settings))
    }

    @Test fun readsOnlyPhysicalButtonTransitions() {
        assertEquals(ButtonEvent(PhysicalButton.VOLUME_DOWN, true, 15642),
            ButtonEvent.parse("[   15.642104] EV_KEY       KEY_VOLUMEDOWN       DOWN"))
        assertNull(ButtonEvent.parse("[   15.642104] EV_KEY       KEY_VOLUMEUP         REPEAT"))
        assertNull(ButtonEvent.parse("[   15.642104] EV_SYN       SYN_REPORT           00000000"))
    }

    @Test fun tripleTapWinsOverDoubleTapAndTapHoldWinsOverHold() {
        val bindings = settings.copy(extra = mapOf(
            "up_double" to ButtonAction.RINGER,
            "up_triple" to ButtonAction.DND,
            "up_tap_hold" to ButtonAction.BOOKMARK,
        ))
        val gesture = ButtonHoldGesture()
        fun event(down: Boolean, ms: Long) =
            gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, down, ms), true, bindings)
        event(true, 100); assertNull(event(false, 150))
        event(true, 210); assertNull(event(false, 260))
        assertTrue(gesture.waitingForThirdTap())
        event(true, 310); assertEquals(ButtonAction.DND, event(false, 360))
        assertNull(gesture.finishTaps(true, bindings))

        event(true, 1000); event(false, 1050)
        event(true, 1100); assertNull(event(false, 1150))
        assertEquals(ButtonAction.RINGER, gesture.finishTaps(true, bindings))

        event(true, 2000); event(false, 2050)
        event(true, 2100); assertEquals(ButtonAction.BOOKMARK, event(false, 3000))
    }

    @Test fun queuedDoubleTapIsCancelledByPlaybackOrAPowerPress() {
        val bindings = settings.copy(extra = mapOf("up_double" to ButtonAction.RINGER, "up_triple" to ButtonAction.DND))
        val gesture = ButtonHoldGesture()
        fun tap(at: Long) {
            gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, true, at), true, bindings)
            gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, false, at + 40), true, bindings)
        }
        tap(100); tap(200)
        assertNull(gesture.finishTaps(false, bindings))
        tap(1000); tap(1100)
        gesture.accept(ButtonEvent(PhysicalButton.POWER, true, 1160), true, bindings)
        assertNull(gesture.finishTaps(true, bindings))
    }
}
