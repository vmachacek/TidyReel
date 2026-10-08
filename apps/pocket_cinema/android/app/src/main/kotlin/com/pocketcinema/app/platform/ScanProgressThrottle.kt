package com.pocketcinema.app.platform

/** Limits advisory progress events before they enter the main-thread queue. */
internal class ScanProgressThrottle(
    private val nanoTime: () -> Long = System::nanoTime,
    private val intervalNanos: Long = 150_000_000L,
) {
    private var lastEmissionNanos: Long? = null

    fun shouldEmit(): Boolean {
        val now = nanoTime()
        val previous = lastEmissionNanos
        if (previous != null && now - previous < intervalNanos) return false
        lastEmissionNanos = now
        return true
    }
}
