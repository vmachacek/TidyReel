package com.tidyreel.local_media_hub.platform

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

const val STORAGE_SCAN_EVENT_CHANNEL =
    "com.tidyreel.local_media_hub/storage_scan_events"

class StorageScanEventHandler(
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) : EventChannel.StreamHandler {
    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun scanSink(scanId: String): ScanSink = object : ScanSink {
        override fun batch(entries: List<StorageEntryMessage>) {
            emit(
                mapOf(
                    "scanId" to scanId,
                    "eventType" to "batch",
                    "entries" to entries.map(StorageEntryMessage::eventPayload),
                ),
            )
        }

        override fun progress(visitedEntries: Int) {
            emit(
                mapOf(
                    "scanId" to scanId,
                    "eventType" to "progress",
                    "visitedEntries" to visitedEntries,
                ),
            )
        }

        override fun warning(code: String) {
            emit(
                mapOf(
                    "scanId" to scanId,
                    "eventType" to "warning",
                    "code" to code,
                ),
            )
        }

        override fun completed() {
            emit(mapOf("scanId" to scanId, "eventType" to "completed"))
        }

        override fun cancelled() {
            emit(mapOf("scanId" to scanId, "eventType" to "cancelled"))
        }

        override fun failed(code: String) {
            emit(
                mapOf(
                    "scanId" to scanId,
                    "eventType" to "failed",
                    "code" to code,
                ),
            )
        }
    }

    fun error(code: String, safeMessage: String) {
        mainHandler.post {
            eventSink?.error(code, safeMessage, null)
        }
    }

    fun endOfStream() {
        mainHandler.post {
            eventSink?.endOfStream()
            eventSink = null
        }
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }
}

private fun StorageEntryMessage.eventPayload(): Map<String, Any?> = mapOf(
    "storageKey" to storageKey,
    "parentStorageKey" to parentStorageKey,
    "relativePath" to relativePath,
    "displayName" to displayName,
    "isDirectory" to isDirectory,
    "mimeType" to mimeType,
    "sizeBytes" to sizeBytes,
    "modifiedAtEpochMs" to modifiedAtEpochMs,
    "flags" to flags,
)
