package com.pocketcinema.app.platform

import android.app.Activity
import android.view.Choreographer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Native vsync delivery diagnostics; does not force Flutter to redraw the video. */
class RenderingPerformancePlatform(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.pocketcinema.app/rendering")
    private val choreographer = Choreographer.getInstance()
    private val cadence = FrameCadence()
    private var enabled = false
    private var foreground = true
    private var queued = false

    @Suppress("DEPRECATION")
    private fun refreshHz(): Double = activity.windowManager.defaultDisplay.refreshRate.toDouble()

    private val callback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            queued = false
            if (!enabled || !foreground) return
            cadence.frame(frameTimeNanos, refreshHz())
            schedule()
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    enabled = true
                    cadence.reset()
                    schedule()
                    result.success(null)
                }
                "sample" -> result.success(cadence.sample(refreshHz()))
                "stop" -> {
                    enabled = false
                    cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun schedule() {
        if (enabled && foreground && !queued) {
            queued = true
            choreographer.postFrameCallback(callback)
        }
    }

    private fun cancel() {
        choreographer.removeFrameCallback(callback)
        queued = false
        cadence.reset()
    }

    fun resume() { foreground = true; cadence.reset(); schedule() }
    fun pause() { foreground = false; cancel() }
    fun close() { enabled = false; cancel(); channel.setMethodCallHandler(null) }
}
