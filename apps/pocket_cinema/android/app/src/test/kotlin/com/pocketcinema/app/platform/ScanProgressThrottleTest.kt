package com.pocketcinema.app.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScanProgressThrottleTest {
    @Test
    fun `dense progress updates are limited without postponing the next event`() {
        var now = 0L
        val throttle = ScanProgressThrottle(nanoTime = { now })

        assertTrue(throttle.shouldEmit())
        for (millisecond in 1..149) {
            now = millisecond * 1_000_000L
            assertFalse(throttle.shouldEmit())
        }
        now = 150_000_000L
        assertTrue(throttle.shouldEmit())
        assertFalse(throttle.shouldEmit())
        now = 299_999_999L
        assertFalse(throttle.shouldEmit())
        now = 300_000_000L
        assertTrue(throttle.shouldEmit())
    }

    @Test
    fun `each scan emits its first progress immediately`() {
        var now = 42_000_000L
        val firstScan = ScanProgressThrottle(nanoTime = { now })
        assertTrue(firstScan.shouldEmit())

        now += 1_000_000L
        assertFalse(firstScan.shouldEmit())
        val secondScan = ScanProgressThrottle(nanoTime = { now })
        assertTrue(secondScan.shouldEmit())
    }

    @Test
    fun `a fast large scan queues only a bounded number of progress events`() {
        var now = 0L
        val throttle = ScanProgressThrottle(nanoTime = { now })
        var emissionCount = 0

        repeat(10_000) {
            now = it * 1_000_000L
            if (throttle.shouldEmit()) emissionCount++
        }

        assertEquals(67, emissionCount)
    }

    @Test
    fun `a pause does not delay the next available progress event`() {
        var now = -1_000_000_000L
        val throttle = ScanProgressThrottle(nanoTime = { now })

        assertTrue(throttle.shouldEmit())
        now += 5_000_000_000L
        assertTrue(throttle.shouldEmit())
        assertFalse(throttle.shouldEmit())
    }

    @Test
    fun `elapsed time remains valid when the monotonic clock wraps`() {
        var now = Long.MAX_VALUE - 75_000_000L
        val throttle = ScanProgressThrottle(nanoTime = { now })

        assertTrue(throttle.shouldEmit())
        now = Long.MIN_VALUE + 74_999_998L
        assertFalse(throttle.shouldEmit())
        now = Long.MIN_VALUE + 74_999_999L
        assertTrue(throttle.shouldEmit())
    }
}
