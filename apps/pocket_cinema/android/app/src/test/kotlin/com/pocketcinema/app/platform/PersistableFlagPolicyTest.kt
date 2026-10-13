package com.pocketcinema.app.platform

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Test

class PersistableFlagPolicyTest {
    @Test
    fun `retains returned read and write flags without picker flags`() {
        val flags =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION

        assertEquals(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            PersistableFlagPolicy.readAndWrite(flags),
        )
    }

    @Test
    fun `read only providers retain read access without inventing write access`() {
        assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION,
            PersistableFlagPolicy.readAndWrite(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        assertEquals(0, PersistableFlagPolicy.readAndWrite(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION))
    }
}
