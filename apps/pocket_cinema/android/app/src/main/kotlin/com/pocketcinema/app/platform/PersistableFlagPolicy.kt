package com.pocketcinema.app.platform

import android.content.Intent

object PersistableFlagPolicy {
    fun readOnly(returnedFlags: Int): Int =
        returnedFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION
}
