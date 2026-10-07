package com.pocketcinema.app.platform

import kotlin.math.max
import kotlin.math.roundToInt

/** Measures callback delivery, not a file's declared frame rate or panel scanout. */
class FrameCadence {
    private var previousNanos = 0L
    private var intervals = 0
    private var elapsedNanos = 0L
    private var longestNanos = 0L
    private var missed = 0

    fun frame(timestampNanos: Long, refreshHz: Double) {
        if (previousNanos != 0L && timestampNanos > previousNanos) {
            val gap = timestampNanos - previousNanos
            intervals++
            elapsedNanos += gap
            longestNanos = max(longestNanos, gap)
            if (refreshHz > 0) {
                missed += max(0, (gap * refreshHz / 1_000_000_000.0).roundToInt() - 1)
            }
        }
        previousNanos = timestampNanos
    }

    fun sample(refreshHz: Double): Map<String, Any> {
        val result = mapOf<String, Any>(
            "refreshHz" to refreshHz,
            "callbackFps" to if (elapsedNanos > 0) intervals * 1_000_000_000.0 / elapsedNanos else 0.0,
            "maxGapMs" to longestNanos / 1_000_000.0,
            "missedVsyncs" to missed,
        )
        intervals = 0
        elapsedNanos = 0
        longestNanos = 0
        missed = 0
        return result
    }

    fun reset() {
        previousNanos = 0
        sample(0.0)
    }
}
