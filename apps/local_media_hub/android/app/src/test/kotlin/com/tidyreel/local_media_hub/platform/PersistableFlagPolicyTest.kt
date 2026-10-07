package com.tidyreel.local_media_hub.platform

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Test

class PersistableFlagPolicyTest {
    @Test
    fun `retains only returned read flag`() {
        val flags =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION

        assertEquals(
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
            PersistableFlagPolicy.readOnly(flags),
        )
    }
}
