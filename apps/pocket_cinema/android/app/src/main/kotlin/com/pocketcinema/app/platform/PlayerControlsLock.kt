package com.pocketcinema.app.platform

import android.view.KeyEvent

/** Suppresses volume keys while the current player controls are locked. */
class PlayerControlsLock {
    private var locked = false

    val isLocked: Boolean get() = locked

    fun setLocked(value: Boolean) {
        locked = value
    }

    fun shouldConsume(keyCode: Int): Boolean = locked && when (keyCode) {
        KeyEvent.KEYCODE_VOLUME_UP,
        KeyEvent.KEYCODE_VOLUME_DOWN,
        KeyEvent.KEYCODE_VOLUME_MUTE -> true
        else -> false
    }

    fun close() {
        locked = false
    }
}
