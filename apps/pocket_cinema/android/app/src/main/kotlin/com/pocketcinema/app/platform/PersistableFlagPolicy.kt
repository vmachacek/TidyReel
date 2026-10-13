package com.pocketcinema.app.platform

import android.content.Intent

object PersistableFlagPolicy {
    fun readAndWrite(returnedFlags: Int): Int =
        returnedFlags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
}
