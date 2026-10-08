package com.pocketcinema.app.platform

import android.app.Activity
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class PlayerControlsPlatform(activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.pocketcinema.app/player_controls")
    private val controlsLock = PlayerControlsLock()
    private val watchingDisplay = WatchingDisplaySession(object : WatchingDisplay {
        override fun snapshot(): WatchingDisplayState {
            val attributes = activity.window.attributes
            return WatchingDisplayState(
                attributes.screenBrightness,
                attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0,
            )
        }

        override fun systemBrightness(): Double = runCatching {
            Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0
        }.getOrDefault(0.5)

        override fun apply(state: WatchingDisplayState) {
            val attributes = activity.window.attributes
            attributes.screenBrightness = state.brightness
            attributes.flags = if (state.keepScreenOn) {
                attributes.flags or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            } else {
                attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON.inv()
            }
            activity.window.attributes = attributes
        }
    })

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setLocked" -> {
                    val locked = call.arguments as? Boolean
                    if (locked == null) {
                        result.error("INVALID_ARGUMENT", "setLocked expects a boolean.", null)
                    } else {
                        controlsLock.setLocked(locked)
                        result.success(null)
                    }
                }
                "beginWatching" -> result.success(watchingDisplay.begin())
                "setBrightness" -> {
                    val brightness = (call.arguments as? Number)?.toDouble()
                    when {
                        brightness == null || !brightness.isFinite() || brightness !in 0.01..1.0 ->
                            result.error("INVALID_ARGUMENT", "setBrightness expects a number between 0.01 and 1.0.", null)
                        controlsLock.isLocked ->
                            result.error("CONTROLS_LOCKED", "Player controls are locked.", null)
                        else -> {
                            try {
                                watchingDisplay.setBrightness(brightness)
                                result.success(null)
                            } catch (error: IllegalStateException) {
                                result.error("NOT_WATCHING", error.message, null)
                            }
                        }
                    }
                }
                "endWatching" -> {
                    watchingDisplay.end()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun shouldConsume(keyCode: Int): Boolean = controlsLock.shouldConsume(keyCode)

    fun resume() = watchingDisplay.resume()

    fun pause() = watchingDisplay.pause()

    fun close() {
        watchingDisplay.end()
        controlsLock.close()
        channel.setMethodCallHandler(null)
    }
}
