package com.pocketcinema.app.platform

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class PlayerControlsPlatform(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.pocketcinema.app/player_controls")
    private val controlsLock = PlayerControlsLock()

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
                else -> result.notImplemented()
            }
        }
    }

    fun shouldConsume(keyCode: Int): Boolean = controlsLock.shouldConsume(keyCode)

    fun close() {
        controlsLock.close()
        channel.setMethodCallHandler(null)
    }
}
