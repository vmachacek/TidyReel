package com.pocketcinema.app.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class WatchingDisplaySessionTest {
    @Test fun watchingPinsSystemBrightnessAndKeepsTheScreenOnUntilEnding() {
        val display = FakeDisplay(systemLevel = 0.63)
        val activity = FakeActivity(display)
        val session = activity.session
        activity.resume()

        assertEquals(0.63, session.begin(1L), 0.00001)
        assertEquals(0.63f, display.state.brightness, 0.00001f)
        assertTrue(display.state.keepScreenOn)

        display.systemLevel = 0.15
        assertEquals(0.63, session.begin(1L), 0.00001)
        assertEquals(0.63f, display.state.brightness, 0.00001f)

        session.end(1L)
        assertEquals(WatchingDisplayState(-1f, false), display.state)
    }

    @Test fun originalWindowOverrideAndKeepAwakeFlagAreRestored() {
        val original = WatchingDisplayState(0.27f, true)
        val display = FakeDisplay(state = original, systemLevel = 0.9)
        val activity = FakeActivity(display)
        val session = activity.session
        activity.resume()

        assertEquals(0.27, session.begin(1L), 0.00001)
        session.setBrightness(0.8, 1L)
        activity.pause()
        assertEquals(original, display.state)

        activity.resume()
        assertEquals(WatchingDisplayState(0.8f, true), display.state)
        session.end(1L)
        assertEquals(original, display.state)
    }

    @Test fun backgroundRestoresTheDisplayAndRetainsSelectedBrightnessForReturning() {
        val display = FakeDisplay()
        val activity = FakeActivity(display)
        val session = activity.session
        activity.resume()
        session.begin(1L)
        session.setBrightness(0.72, 1L)

        activity.pause()
        assertEquals(WatchingDisplayState(-1f, false), display.state)
        val pausedWrites = display.writes
        display.systemLevel = 0.2
        assertEquals(0.72, session.begin(1L), 0.00001)
        session.setBrightness(0.84, 1L)
        activity.pause()
        assertEquals(pausedWrites, display.writes)

        activity.resume()
        assertEquals(WatchingDisplayState(0.84f, true), display.state)
        session.end(1L)
        assertEquals(WatchingDisplayState(-1f, false), display.state)
    }

    @Test fun beginningBeforeActivityResumeDoesNotKeepABackgroundDisplayAwake() {
        val display = FakeDisplay(systemLevel = 0.45)
        val activity = FakeActivity(display)
        val session = activity.session

        assertEquals(0.45, session.begin(1L), 0.00001)
        assertEquals(0, display.writes)
        assertFalse(display.state.keepScreenOn)
        activity.resume()
        assertEquals(WatchingDisplayState(0.45f, true), display.state)
    }

    @Test fun repeatedBeginDoesNotReplaceTheOriginalSnapshotOrSelectedLevel() {
        val display = FakeDisplay(systemLevel = 0.4)
        val activity = FakeActivity(display)
        val session = activity.session
        activity.resume()
        session.begin(1L)
        session.setBrightness(0.9, 1L)

        assertEquals(0.9, session.begin(1L), 0.00001)
        assertEquals(1, display.snapshots)
        session.end(1L)
        assertEquals(WatchingDisplayState(-1f, false), display.state)
        val endedWrites = display.writes
        session.end(1L)
        activity.pause()
        activity.resume()
        assertEquals(endedWrites, display.writes)
    }

    @Test fun endingWhilePausedDoesNotOverwriteChangesMadeAfterRestoration() {
        val display = FakeDisplay()
        val activity = FakeActivity(display)
        val session = activity.session
        activity.resume()
        session.begin(1L)
        activity.pause()

        val changedWhilePaused = WatchingDisplayState(0.8f, false)
        display.state = changedWhilePaused
        val pausedWrites = display.writes
        session.end(1L)
        activity.resume()
        assertEquals(pausedWrites, display.writes)
        assertEquals(changedWhilePaused, display.state)
        assertEquals(0.8, session.begin(1L), 0.00001)
        session.end(1L)
        assertEquals(changedWhilePaused, display.state)
    }

    @Test fun invalidLevelsAreRejectedWithoutChangingTheChosenBrightness() {
        val display = FakeDisplay(systemLevel = 0.5)
        val activity = FakeActivity(display)
        val session = activity.session
        activity.resume()
        session.begin(1L)

        listOf(Double.NaN, Double.NEGATIVE_INFINITY, Double.POSITIVE_INFINITY, -1.0, 0.0, 0.009, 1.001)
            .forEach { value ->
                try {
                    session.setBrightness(value, 1L)
                    fail("Accepted invalid brightness $value")
                } catch (_: IllegalArgumentException) {
                    assertEquals(WatchingDisplayState(0.5f, true), display.state)
                }
            }
        session.setBrightness(0.01, 1L)
        assertEquals(WatchingDisplayState(0.01f, true), display.state)
        session.setBrightness(1.0, 1L)
        assertEquals(WatchingDisplayState(1f, true), display.state)
    }

    @Test fun brightnessRequiresAnActiveWatchingSession() {
        val display = FakeDisplay()
        val activity = FakeActivity(display)
        val session = activity.session
        activity.resume()

        try {
            session.setBrightness(0.5, 1L)
            fail("Changed brightness without a watching session")
        } catch (_: IllegalStateException) {
            assertEquals(0, display.writes)
            assertEquals(WatchingDisplayState(-1f, false), display.state)
        }
    }

    @Test fun initialBrightnessIsAlwaysAUsableSliderValue() {
        listOf(0.0 to 0.01, 1.4 to 1.0, Double.NaN to 0.5).forEach { (system, expected) ->
            val display = FakeDisplay(systemLevel = system)
            val session = FakeActivity(display).session
            assertEquals(expected, session.begin(1L), 0.00001)
        }

        val darkWindow = FakeDisplay(state = WatchingDisplayState(0f, false))
        val activity = FakeActivity(darkWindow)
        val session = activity.session
        activity.resume()
        assertEquals(0.01, session.begin(1L), 0.00001)
        session.end(1L)
        assertEquals(WatchingDisplayState(0f, false), darkWindow.state)
    }

    @Test fun attachingAfterActivityResumeStillAppliesBrightnessWithoutAResumeCallback() {
        val display = FakeDisplay(systemLevel = 0.6)
        val activity = FakeActivity(display, resumed = true)
        val session = activity.session

        assertEquals(0.6, session.begin(1L), 0.00001)
        assertEquals(WatchingDisplayState(0.6f, true), display.state)
        session.setBrightness(0.2, 1L)
        assertEquals(WatchingDisplayState(0.2f, true), display.state)
        session.end(1L)
        assertEquals(WatchingDisplayState(-1f, false), display.state)
    }

    @Test fun brightnessChangesReadCurrentActivityStateWithoutLifecycleCallbacks() {
        val display = FakeDisplay()
        val activity = FakeActivity(display, resumed = true)
        val session = activity.session
        session.begin(1L)

        activity.resumed = false
        val foregroundWrites = display.writes
        session.setBrightness(0.8, 1L)
        assertEquals(foregroundWrites, display.writes)

        activity.resumed = true
        session.setBrightness(0.3, 1L)
        assertEquals(WatchingDisplayState(0.3f, true), display.state)
        session.end(1L)
        assertEquals(WatchingDisplayState(-1f, false), display.state)
    }

    @Test fun regainingFocusReappliesSelectedBrightnessAfterAnExternalWindowChange() {
        val display = FakeDisplay()
        val activity = FakeActivity(display, resumed = true)
        val session = activity.session
        session.begin(1L)
        session.setBrightness(0.25, 1L)

        display.state = WatchingDisplayState(0.9f, false)
        activity.resume()
        assertEquals(WatchingDisplayState(0.25f, true), display.state)
        session.setBrightness(0.65, 1L)
        assertEquals(WatchingDisplayState(0.65f, true), display.state)
        session.end(1L)
        assertEquals(WatchingDisplayState(-1f, false), display.state)
    }

    @Test fun repeatedBackgroundAndFocusCyclesKeepBrightnessAdjustableAndRestoreOriginal() {
        val original = WatchingDisplayState(0.37f, false)
        val display = FakeDisplay(state = original)
        val activity = FakeActivity(display, resumed = true)
        val session = activity.session
        session.begin(1L)

        repeat(8) { cycle ->
            val selected = 0.15 + cycle * 0.08
            session.setBrightness(selected, 1L)
            assertEquals(WatchingDisplayState(selected.toFloat(), true), display.state)

            display.state = WatchingDisplayState(1f, false)
            activity.resume()
            assertEquals(WatchingDisplayState(selected.toFloat(), true), display.state)

            activity.pause()
            assertEquals(original, display.state)
            val pausedWrites = display.writes
            session.setBrightness(selected + 0.03, 1L)
            assertEquals(pausedWrites, display.writes)

            activity.resume()
            assertEquals(WatchingDisplayState((selected + 0.03).toFloat(), true), display.state)
            session.setBrightness(selected + 0.04, 1L)
            assertEquals(WatchingDisplayState((selected + 0.04).toFloat(), true), display.state)
        }

        session.end(1L)
        assertEquals(original, display.state)
        assertEquals(1, display.snapshots)
    }

    @Test fun replacementPlayerKeepsBrightnessWhenThePreviousPlayerEndsLate() {
        val original = WatchingDisplayState(-1f, false)
        val display = FakeDisplay(state = original, systemLevel = 0.67)
        val activity = FakeActivity(display, resumed = true)
        val session = activity.session
        session.begin(1L)
        session.setBrightness(0.72, 1L)

        assertEquals(0.72, session.begin(2L), 0.00001)
        val handoffWrites = display.writes
        session.end(1L)
        assertEquals(handoffWrites, display.writes)
        assertEquals(WatchingDisplayState(0.72f, true), display.state)

        session.setBrightness(0.37, 2L)
        assertEquals(WatchingDisplayState(0.37f, true), display.state)
        activity.pause()
        session.end(1L)
        activity.resume()
        assertEquals(WatchingDisplayState(0.37f, true), display.state)
        session.end(2L)
        assertEquals(original, display.state)
        assertEquals(1, display.snapshots)
    }

    @Test fun replacedPlayerCannotChangeTheCurrentPlayersBrightness() {
        val display = FakeDisplay()
        val activity = FakeActivity(display, resumed = true)
        val session = activity.session
        session.begin(1L)
        session.begin(2L)
        session.setBrightness(0.3, 2L)
        val currentWrites = display.writes

        try {
            session.setBrightness(0.9, 1L)
            fail("An old player changed the current player's brightness")
        } catch (_: StaleWatchingSessionException) {
            assertEquals(currentWrites, display.writes)
            assertEquals(WatchingDisplayState(0.3f, true), display.state)
        }

        activity.pause()
        activity.resume()
        assertEquals(WatchingDisplayState(0.3f, true), display.state)
        session.end(2L)
        assertEquals(WatchingDisplayState(-1f, false), display.state)
    }

    @Test fun theSameOwnerCanRecoverAfterItsWatchingSessionIsLost() {
        val display = FakeDisplay(systemLevel = 0.67)
        val activity = FakeActivity(display, resumed = true)
        val session = activity.session
        session.begin(1L)
        session.setBrightness(0.8, 1L)
        session.endAll()

        try {
            session.setBrightness(0.2, 1L)
            fail("Brightness changed without an active watching session")
        } catch (error: IllegalStateException) {
            assertFalse(error is StaleWatchingSessionException)
        }

        display.systemLevel = 0.41
        assertEquals(0.41, session.begin(1L), 0.00001)
        session.setBrightness(0.2, 1L)
        assertEquals(WatchingDisplayState(0.2f, true), display.state)
        session.end(1L)
        assertEquals(WatchingDisplayState(-1f, false), display.state)
        assertEquals(2, display.snapshots)
    }

    @Test fun activityCleanupRestoresBrightnessRegardlessOfTheCurrentOwner() {
        val original = WatchingDisplayState(0.26f, true)
        val display = FakeDisplay(state = original)
        val activity = FakeActivity(display, resumed = true)
        val session = activity.session
        session.begin(1L)
        session.setBrightness(0.9, 1L)
        session.begin(2L)
        session.setBrightness(0.4, 2L)

        session.endAll()
        assertEquals(original, display.state)
        val endedWrites = display.writes
        session.endAll()
        session.end(2L)
        activity.pause()
        activity.resume()
        assertEquals(endedWrites, display.writes)
        assertEquals(original, display.state)
    }

    private class FakeActivity(display: FakeDisplay, var resumed: Boolean = false) {
        val session = WatchingDisplaySession(display) { resumed }

        fun resume() {
            resumed = true
            session.resume()
        }

        fun pause() {
            resumed = false
            session.pause()
        }
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
