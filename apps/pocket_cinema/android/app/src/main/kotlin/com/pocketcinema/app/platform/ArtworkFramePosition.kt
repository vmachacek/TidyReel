package com.pocketcinema.app.platform

/** Keeps screenshot requests on the playable timeline and avoids microsecond overflow. */
internal object ArtworkFramePosition {
    fun clamp(requestedPositionMs: Long, durationMs: Long): Long {
        require(requestedPositionMs >= 0L)
        require(durationMs in 1L..Long.MAX_VALUE / 1000L)
        // The duration is the end boundary, rather than a position containing a frame.
        return requestedPositionMs.coerceAtMost(durationMs - 1L)
    }

    fun microseconds(positionMs: Long): Long {
        require(positionMs in 0L..Long.MAX_VALUE / 1000L)
        return positionMs * 1000L
    }
}
