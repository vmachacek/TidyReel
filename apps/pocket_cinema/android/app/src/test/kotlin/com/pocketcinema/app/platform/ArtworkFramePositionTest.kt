package com.pocketcinema.app.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ArtworkFramePositionTest {
    @Test fun preservesInteriorFramePositionWithoutRoundingToAKeyFrame() {
        val positionMs = ArtworkFramePosition.clamp(47_321L, 1_800_000L)
        assertEquals(47_321L, positionMs)
        assertEquals(47_321_000L, ArtworkFramePosition.microseconds(positionMs))
    }

    @Test fun durationAndPastEndRequestsStayInsidePlayableRange() {
        assertEquals(59_999L, ArtworkFramePosition.clamp(60_000L, 60_000L))
        assertEquals(59_999L, ArtworkFramePosition.clamp(Long.MAX_VALUE, 60_000L))
        assertEquals(0L, ArtworkFramePosition.clamp(50L, 1L))
        assertEquals(0L, ArtworkFramePosition.clamp(0L, 60_000L))
    }

    @Test fun rejectsInvalidTimelineAndOverflowingDuration() {
        assertThrows(IllegalArgumentException::class.java) { ArtworkFramePosition.clamp(-1L, 60_000L) }
        assertThrows(IllegalArgumentException::class.java) { ArtworkFramePosition.clamp(0L, 0L) }
        assertThrows(IllegalArgumentException::class.java) { ArtworkFramePosition.clamp(0L, -1L) }
        assertThrows(IllegalArgumentException::class.java) { ArtworkFramePosition.clamp(0L, Long.MAX_VALUE) }
        assertThrows(IllegalArgumentException::class.java) { ArtworkFramePosition.microseconds(-1L) }
        assertThrows(IllegalArgumentException::class.java) { ArtworkFramePosition.microseconds(Long.MAX_VALUE) }
    }

    @Test fun largestSupportedPositionConvertsWithoutOverflow() {
        val maximum = Long.MAX_VALUE / 1000L
        assertEquals(maximum * 1000L, ArtworkFramePosition.microseconds(maximum))
    }
}
