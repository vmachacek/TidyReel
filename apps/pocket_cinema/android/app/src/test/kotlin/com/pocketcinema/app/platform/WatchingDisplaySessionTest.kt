package com.pocketcinema.app.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class WatchingDisplaySessionTest {
    @Test fun watchingPinsSystemBrightnessAndKeepsTheScreenOnUntilEnding() {
        val display = FakeDisplay(systemLevel = 0.63)
        val session = WatchingDisplaySession(display)
        session.resume()

        assertEquals(0.63, session.begin(), 0.00001)
        assertEquals(0.63f, display.state.brightness, 0.00001f)
        assertTrue(display.state.keepScreenOn)

        display.systemLevel = 0.15
        assertEquals(0.63, session.begin(), 0.00001)
        assertEquals(0.63f, display.state.brightness, 0.00001f)

        session.end()
        assertEquals(WatchingDisplayState(-1f, false), display.state)
    }

    @Test fun originalWindowOverrideAndKeepAwakeFlagAreRestored() {
        val original = WatchingDisplayState(0.27f, true)
        val display = FakeDisplay(state = original, systemLevel = 0.9)
        val session = WatchingDisplaySession(display)
        session.resume()

        assertEquals(0.27, session.begin(), 0.00001)
        session.setBrightness(0.8)
        session.pause()
        assertEquals(original, display.state)

        session.resume()
        assertEquals(WatchingDisplayState(0.8f, true), display.state)
        session.end()
        assertEquals(original, display.state)
    }

    @Test fun backgroundRestoresTheDisplayAndRetainsSelectedBrightnessForReturning() {
        val display = FakeDisplay()
        val session = WatchingDisplaySession(display)
        session.resume()
        session.begin()
        session.setBrightness(0.72)

        session.pause()
        assertEquals(WatchingDisplayState(-1f, false), display.state)
        val pausedWrites = display.writes
        display.systemLevel = 0.2
        assertEquals(0.72, session.begin(), 0.00001)
        session.setBrightness(0.84)
        session.pause()
        assertEquals(pausedWrites, display.writes)

        session.resume()
        assertEquals(WatchingDisplayState(0.84f, true), display.state)
        session.end()
        assertEquals(WatchingDisplayState(-1f, false), display.state)
    }

    @Test fun beginningBeforeActivityResumeDoesNotKeepABackgroundDisplayAwake() {
        val display = FakeDisplay(systemLevel = 0.45)
        val session = WatchingDisplaySession(display)

        assertEquals(0.45, session.begin(), 0.00001)
        assertEquals(0, display.writes)
        assertFalse(display.state.keepScreenOn)
        session.resume()
        assertEquals(WatchingDisplayState(0.45f, true), display.state)
    }

    @Test fun repeatedBeginDoesNotReplaceTheOriginalSnapshotOrSelectedLevel() {
        val display = FakeDisplay(systemLevel = 0.4)
        val session = WatchingDisplaySession(display)
        session.resume()
        session.begin()
        session.setBrightness(0.9)

        assertEquals(0.9, session.begin(), 0.00001)
        assertEquals(1, display.snapshots)
        session.end()
        assertEquals(WatchingDisplayState(-1f, false), display.state)
        val endedWrites = display.writes
        session.end()
        session.pause()
        session.resume()
        assertEquals(endedWrites, display.writes)
    }

    @Test fun endingWhilePausedDoesNotOverwriteChangesMadeAfterRestoration() {
        val display = FakeDisplay()
        val session = WatchingDisplaySession(display)
        session.resume()
        session.begin()
        session.pause()

        val changedWhilePaused = WatchingDisplayState(0.8f, false)
        display.state = changedWhilePaused
        val pausedWrites = display.writes
        session.end()
        session.resume()
        assertEquals(pausedWrites, display.writes)
        assertEquals(changedWhilePaused, display.state)
        assertEquals(0.8, session.begin(), 0.00001)
        session.end()
        assertEquals(changedWhilePaused, display.state)
    }

    @Test fun invalidLevelsAreRejectedWithoutChangingTheChosenBrightness() {
        val display = FakeDisplay(systemLevel = 0.5)
        val session = WatchingDisplaySession(display)
        session.resume()
        session.begin()

        listOf(Double.NaN, Double.NEGATIVE_INFINITY, Double.POSITIVE_INFINITY, -1.0, 0.0, 0.009, 1.001)
            .forEach { value ->
                try {
                    session.setBrightness(value)
                    fail("Accepted invalid brightness $value")
                } catch (_: IllegalArgumentException) {
                    assertEquals(WatchingDisplayState(0.5f, true), display.state)
                }
            }
        session.setBrightness(0.01)
        assertEquals(WatchingDisplayState(0.01f, true), display.state)
        session.setBrightness(1.0)
        assertEquals(WatchingDisplayState(1f, true), display.state)
    }

    @Test fun brightnessRequiresAnActiveWatchingSession() {
        val display = FakeDisplay()
        val session = WatchingDisplaySession(display)
        session.resume()

        try {
            session.setBrightness(0.5)
            fail("Changed brightness without a watching session")
        } catch (_: IllegalStateException) {
            assertEquals(0, display.writes)
            assertEquals(WatchingDisplayState(-1f, false), display.state)
        }
    }

    @Test fun initialBrightnessIsAlwaysAUsableSliderValue() {
        listOf(0.0 to 0.01, 1.4 to 1.0, Double.NaN to 0.5).forEach { (system, expected) ->
            val display = FakeDisplay(systemLevel = system)
            val session = WatchingDisplaySession(display)
            assertEquals(expected, session.begin(), 0.00001)
        }

        val darkWindow = FakeDisplay(state = WatchingDisplayState(0f, false))
        val session = WatchingDisplaySession(darkWindow)
        session.resume()
        assertEquals(0.01, session.begin(), 0.00001)
        session.end()
        assertEquals(WatchingDisplayState(0f, false), darkWindow.state)
    }

    private class FakeDisplay(
        var state: WatchingDisplayState = WatchingDisplayState(-1f, false),
        var systemLevel: Double = 0.5,
    ) : WatchingDisplay {
        var writes = 0
        var snapshots = 0

        override fun snapshot(): WatchingDisplayState {
            snapshots++
            return state
        }

        override fun systemBrightness(): Double = systemLevel

        override fun apply(state: WatchingDisplayState) {
            this.state = state
            writes++
        }
    }
}
