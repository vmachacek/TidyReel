package com.pocketcinema.app.platform

data class WatchingDisplayState(val brightness: Float, val keepScreenOn: Boolean)

interface WatchingDisplay {
    fun snapshot(): WatchingDisplayState
    fun systemBrightness(): Double
    fun apply(state: WatchingDisplayState)
}

/** Holds a fixed, app-local backlight level only while the watching activity is resumed. */
class WatchingDisplaySession(private val display: WatchingDisplay) {
    private var original: WatchingDisplayState? = null
    private var brightness: Double? = null
    private var foreground = false
    private var applied = false

    fun begin(): Double {
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
        applyWatchingState()
        return checkNotNull(brightness)
    }

    fun setBrightness(value: Double) {
        require(value.isFinite() && value in 0.01..1.0) {
            "Brightness must be a finite number between 0.01 and 1.0."
        }
        check(original != null) { "No watching display session is active." }
        brightness = value
        applyWatchingState()
    }

    fun resume() {
        foreground = true
        applyWatchingState()
    }

    fun pause() {
        foreground = false
        restore()
    }

    fun end() {
        restore()
        original = null
        brightness = null
    }

    private fun applyWatchingState() {
        if (!foreground || original == null) return
        display.apply(WatchingDisplayState(checkNotNull(brightness).toFloat(), true))
        applied = true
    }

    private fun restore() {
        if (!applied) return
        display.apply(checkNotNull(original))
        applied = false
    }
}
