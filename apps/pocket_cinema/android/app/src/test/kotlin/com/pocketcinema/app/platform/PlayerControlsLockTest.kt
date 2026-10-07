package com.pocketcinema.app.platform

import android.view.KeyEvent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerControlsLockTest {
    private val volumeKeys = listOf(
        KeyEvent.KEYCODE_VOLUME_UP,
        KeyEvent.KEYCODE_VOLUME_DOWN,
        KeyEvent.KEYCODE_VOLUME_MUTE,
    )

    @Test fun volumeKeysPassThroughUntilLockedAndAgainAfterUnlocking() {
        val controls = PlayerControlsLock()
        volumeKeys.forEach { assertFalse(controls.shouldConsume(it)) }

        controls.setLocked(true)
        volumeKeys.forEach { assertTrue(controls.shouldConsume(it)) }

        controls.setLocked(false)
        volumeKeys.forEach { assertFalse(controls.shouldConsume(it)) }
    }

    @Test fun unrelatedKeysPassThroughWhileLocked() {
        val controls = PlayerControlsLock()
        controls.setLocked(true)

        listOf(
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_POWER,
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MUTE,
            KeyEvent.KEYCODE_A,
        ).forEach { assertFalse(controls.shouldConsume(it)) }
    }

    @Test fun repeatedVolumeEventsRemainConsumedUntilEngineCleanup() {
        val controls = PlayerControlsLock()
        controls.setLocked(true)

        repeat(10) {
            volumeKeys.forEach { assertTrue(controls.shouldConsume(it)) }
        }

        controls.close()
        volumeKeys.forEach { assertFalse(controls.shouldConsume(it)) }
    }
}
