package com.tidyreel.local_media_hub.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackLeaseRegistryTest {
    @Test
    fun `direct leases use unique ids and preserve content uri`() {
        val registry = PlaybackLeaseRegistry()

        val first = registry.openDirect("content://provider/document/first")
        val second = registry.openDirect("content://provider/document/second")

        assertNotEquals(first.leaseId, second.leaseId)
        assertEquals("content://provider/document/first", first.sourceUri)
        assertEquals("directContentUri", first.strategy)
        assertTrue(registry.isActive(first.leaseId))
        assertTrue(registry.isActive(second.leaseId))
    }

    @Test
    fun `closing a direct lease is idempotent`() {
        val registry = PlaybackLeaseRegistry()
        val lease = registry.openDirect("content://provider/document/video")

        registry.close(lease.leaseId)
        registry.close(lease.leaseId)

        assertFalse(registry.isActive(lease.leaseId))
    }
}
