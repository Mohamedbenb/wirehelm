package com.example.remote_control

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PowerTapGestureTest {
    private val settings = ButtonShortcutSettings(ButtonAction.NONE, ButtonAction.NONE, 800,
        mapOf("power_double" to ButtonAction.TORCH, "power_triple" to ButtonAction.BOOKMARK))

    private fun tap(gesture: PowerTapGesture, at: Long, screenOff: Boolean, duration: Long = 50) {
        gesture.accept(ButtonEvent(PhysicalButton.POWER, true, at), true, screenOff, settings)
        gesture.accept(ButtonEvent(PhysicalButton.POWER, false, at + duration), true, false, settings)
    }

    @Test fun doubleAndTripleCanContinueAfterStockWake() {
        val gesture = PowerTapGesture()
        tap(gesture, 100, true)
        tap(gesture, 250, false)
        assertTrue(gesture.waiting())
        assertEquals(ButtonAction.TORCH, gesture.finish(true, settings))
        tap(gesture, 1000, true)
        tap(gesture, 1150, false)
        tap(gesture, 1300, false)
        assertEquals(ButtonAction.BOOKMARK, gesture.finish(true, settings))
    }

    @Test fun emergencySequenceAndLongPressNeverFire() {
        val gesture = PowerTapGesture()
        for (index in 0..4) tap(gesture, 100L + index * 300L, index == 0)
        assertNull(gesture.finish(true, settings))
        tap(gesture, 2000, true)
        tap(gesture, 2200, false, duration = 600)
        assertNull(gesture.finish(true, settings))
    }

    @Test fun aScreenOnStartOrVolumeChordDoesNotFire() {
        val gesture = PowerTapGesture()
        tap(gesture, 100, false)
        tap(gesture, 250, false)
        assertNull(gesture.finish(true, settings))
        gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, true, 900), true, true, settings)
        tap(gesture, 1000, true)
        tap(gesture, 1150, false)
        gesture.accept(ButtonEvent(PhysicalButton.VOLUME_UP, false, 1250), true, false, settings)
        assertNull(gesture.finish(true, settings))
    }
}
