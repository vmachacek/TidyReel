package com.pocketcinema.app.platform

data class WatchingDisplayState(val brightness: Float, val keepScreenOn: Boolean)

interface WatchingDisplay {
    fun snapshot(): WatchingDisplayState
    fun systemBrightness(): Double
    fun apply(state: WatchingDisplayState)
}

class StaleWatchingSessionException : IllegalStateException("Another watching display session is active.")

/** Holds a fixed, app-local backlight level only while the watching activity is resumed. */
class WatchingDisplaySession(
    private val display: WatchingDisplay,
    private val isForeground: () -> Boolean,
) {
    private var original: WatchingDisplayState? = null
    private var brightness: Double? = null
    private var sessionId: Long? = null
    private var applied = false

    fun begin(sessionId: Long): Double {
        if (original == null) {
            val snapshot = display.snapshot()
            val initial = if (snapshot.brightness.isFinite() && snapshot.brightness >= 0f) {
                snapshot.brightness.toDouble()
            } else {
                display.systemBrightness()
            }
            original = snapshot
            brightness = (if (initial.isFinite()) initial else 0.5).coerceIn(0.01, 1.0)
        }
        // A replacement player inherits the selection and original snapshot.
        this.sessionId = sessionId
        applyWatchingState()
        return checkNotNull(brightness)
    }

    fun setBrightness(value: Double, sessionId: Long) {
        require(value.isFinite() && value in 0.01..1.0) {
            "Brightness must be a finite number between 0.01 and 1.0."
        }
        check(original != null) { "No watching display session is active." }
        if (this.sessionId != sessionId) throw StaleWatchingSessionException()
        brightness = value
        applyWatchingState()
    }

    fun resume() {
        applyWatchingState()
    }

    fun pause() {
        restore()
    }

    fun end(sessionId: Long) {
        if (this.sessionId != sessionId) return
        endAll()
    }

    fun endAll() {
        restore()
        original = null
        brightness = null
        sessionId = null
    }

    private fun applyWatchingState() {
        // Read the activity's current lifecycle, including when this bridge is
        // attached after onResume or a focus transition skips a resume callback.
        if (!isForeground() || original == null) return
        display.apply(WatchingDisplayState(checkNotNull(brightness).toFloat(), true))
        applied = true
    }

    private fun restore() {
        if (!applied) return
        display.apply(checkNotNull(original))
        applied = false
    }
}
