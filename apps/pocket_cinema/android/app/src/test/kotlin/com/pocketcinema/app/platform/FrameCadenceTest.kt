package com.pocketcinema.app.platform

import org.junit.Assert.assertEquals
import org.junit.Test

class FrameCadenceTest {
    @Test fun stalledCallbacksReduceMeasuredFpsAndCountMissedVsyncs() {
        val cadence = FrameCadence()
        cadence.frame(1_000_000_000L, 60.0)
        cadence.frame(1_016_666_667L, 60.0)
        cadence.frame(1_066_666_667L, 60.0)
        val stats = cadence.sample(60.0)
        assertEquals(30.0, stats["callbackFps"] as Double, 0.01)
        assertEquals(50.0, stats["maxGapMs"] as Double, 0.01)
        assertEquals(2, stats["missedVsyncs"])
    }

    @Test fun sampleWindowsPreserveBoundaryIntervalAndResetAfterBackground() {
        val cadence = FrameCadence()
        cadence.frame(1_000_000_000L, 120.0)
        cadence.frame(1_008_333_333L, 120.0)
        cadence.sample(120.0)
        cadence.frame(1_016_666_666L, 120.0)
        assertEquals(120.0, cadence.sample(120.0)["callbackFps"] as Double, 0.01)
        cadence.reset()
        cadence.frame(10_000_000_000L, 120.0)
        assertEquals(0, cadence.sample(120.0)["missedVsyncs"])
    }
}
