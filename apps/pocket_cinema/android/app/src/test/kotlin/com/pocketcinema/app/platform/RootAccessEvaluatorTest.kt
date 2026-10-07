package com.pocketcinema.app.platform

import org.junit.Assert.assertEquals
import org.junit.Test

class RootAccessEvaluatorTest {
    @Test
    fun `missing read grant is permission revoked`() {
        assertEquals(
            RootAccessState.PERMISSION_REVOKED,
            RootAccessEvaluator.evaluate(
                hasPersistedRead = false,
                rootQueryable = false,
            ),
        )
    }

    @Test
    fun `persisted grant with unavailable provider is unavailable`() {
        assertEquals(
            RootAccessState.UNAVAILABLE,
            RootAccessEvaluator.evaluate(
                hasPersistedRead = true,
                rootQueryable = false,
            ),
        )
    }
}
