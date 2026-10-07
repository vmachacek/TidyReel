package com.tidyreel.local_media_hub.platform

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class PlaybackLeaseRegistry {
    private val activeLeaseIds = ConcurrentHashMap.newKeySet<String>()

    fun openDirect(sourceUri: String): PlaybackLeaseMessage {
        val leaseId = UUID.randomUUID().toString()
        activeLeaseIds.add(leaseId)
        return PlaybackLeaseMessage(
            leaseId = leaseId,
            sourceUri = sourceUri,
            strategy = "directContentUri",
        )
    }

    fun close(leaseId: String) {
        activeLeaseIds.remove(leaseId)
    }

    fun closeAll() {
        activeLeaseIds.clear()
    }

    internal fun isActive(leaseId: String): Boolean =
        activeLeaseIds.contains(leaseId)
}
