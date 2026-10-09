package com.pocketcinema.app.platform

import android.provider.Settings
import android.view.WindowManager
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class PlayerControlsPlatform(private val activity: FragmentActivity, messenger: BinaryMessenger) {
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
    }) { activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) }

    private val lifecycleObserver = object : DefaultLifecycleObserver {
        override fun onResume(owner: LifecycleOwner) {
            // ON_RESUME runs after the activity lifecycle reaches RESUMED.
            watchingDisplay.resume()
        }

        override fun onPause(owner: LifecycleOwner) {
            watchingDisplay.pause()
        }
    }

    init {
        activity.lifecycle.addObserver(lifecycleObserver)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setLocked" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val locked = arguments?.get("locked") as? Boolean
                    val lockHardwareVolumeButtons = arguments?.get("lockHardwareVolumeButtons") as? Boolean
                    if (locked == null || lockHardwareVolumeButtons == null) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "setLocked expects a map with boolean locked and lockHardwareVolumeButtons values.",
                            null,
                        )
                    } else {
                        controlsLock.setLocked(locked, lockHardwareVolumeButtons)
                        result.success(null)
                    }
                }
                "beginWatching" -> {
                    val sessionId = watchingSessionId(call.arguments)
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENT", "beginWatching expects an integer session ID.", null)
                    } else {
                        result.success(watchingDisplay.begin(sessionId))
                    }
                }
                "setBrightness" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val sessionId = watchingSessionId(arguments?.get("sessionId"))
                    val brightness = (arguments?.get("brightness") as? Number)?.toDouble()
                    when {
                        sessionId == null || brightness == null || !brightness.isFinite() || brightness !in 0.01..1.0 ->
                            result.error("INVALID_ARGUMENT", "setBrightness expects an integer sessionId and brightness between 0.01 and 1.0.", null)
                        controlsLock.isLocked ->
                            result.error("CONTROLS_LOCKED", "Player controls are locked.", null)
                        else -> {
                            try {
                                watchingDisplay.setBrightness(brightness, sessionId)
                                result.success(null)
                            } catch (error: StaleWatchingSessionException) {
                                result.error("STALE_WATCHING", error.message, null)
                            } catch (error: IllegalStateException) {
                                result.error("NOT_WATCHING", error.message, null)
                            }
                        }
                    }
                }
                "endWatching" -> {
                    val sessionId = watchingSessionId(call.arguments)
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENT", "endWatching expects an integer session ID.", null)
                    } else {
                        watchingDisplay.end(sessionId)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun watchingSessionId(value: Any?): Long? = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    fun shouldConsume(keyCode: Int): Boolean = controlsLock.shouldConsume(keyCode)

    fun reapplyWatchingDisplay() = watchingDisplay.resume()

    fun close() {
        activity.lifecycle.removeObserver(lifecycleObserver)
        watchingDisplay.endAll()
        controlsLock.close()
        channel.setMethodCallHandler(null)
    }
}
