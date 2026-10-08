package com.pocketcinema.app.platform

import android.view.KeyEvent

/** Tracks the controls lock independently from its optional hardware volume key policy. */
class PlayerControlsLock {
    private var locked = false
    private var lockHardwareVolumeButtons = true

    /** Touch controls and brightness remain locked even when volume keys are allowed. */
    val isLocked: Boolean get() = locked

    fun setLocked(value: Boolean, lockHardwareVolumeButtons: Boolean = true) {
        locked = value
        this.lockHardwareVolumeButtons = lockHardwareVolumeButtons
    }

    fun shouldConsume(keyCode: Int): Boolean = locked && lockHardwareVolumeButtons && when (keyCode) {
        KeyEvent.KEYCODE_VOLUME_UP,
        KeyEvent.KEYCODE_VOLUME_DOWN,
        KeyEvent.KEYCODE_VOLUME_MUTE -> true
        else -> false
    }

    fun close() {
        locked = false
        lockHardwareVolumeButtons = true
    }
}
