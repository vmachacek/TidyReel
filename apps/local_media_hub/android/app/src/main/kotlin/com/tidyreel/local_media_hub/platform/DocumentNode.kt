package com.tidyreel.local_media_hub.platform

data class DocumentNode(
    val documentId: String,
    val displayName: String,
    val isDirectory: Boolean,
    val mimeType: String?,
    val sizeBytes: Long?,
    val modifiedAtEpochMs: Long?,
    val flags: Long,
) {
    fun toMessage(
        authority: String,
        parentDocumentId: String,
        relativePath: String,
    ): StorageEntryMessage =
        StorageEntryMessage(
            storageKey = "$authority|$documentId",
            parentStorageKey = "$authority|$parentDocumentId",
            relativePath = relativePath,
            displayName = displayName,
            isDirectory = isDirectory,
            mimeType = mimeType,
            sizeBytes = sizeBytes,
            modifiedAtEpochMs = modifiedAtEpochMs,
            flags = flags,
        )
}
