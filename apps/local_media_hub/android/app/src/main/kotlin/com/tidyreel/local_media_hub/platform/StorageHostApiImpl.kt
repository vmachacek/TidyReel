package com.tidyreel.local_media_hub.platform

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract

class StorageHostApiImpl(
    private val chooseDirectoryAction: suspend () -> AuthorizedRootMessage,
    private val rootPermissionStore: AndroidRootPermissionStore,
    private val contentResolver: ContentResolver,
    private val scanSessionRegistry: ScanSessionRegistry,
    private val scanEventHandler: StorageScanEventHandler,
    private val smallFileReader: SmallFileReader,
    private val mediaProbeService: MediaProbeService,
    private val playbackLeaseRegistry: PlaybackLeaseRegistry,
) : StorageHostApi {
    override suspend fun chooseDirectory(): AuthorizedRootMessage =
        chooseDirectoryAction()

    override fun listPersistedPermissions(): List<AuthorizedRootMessage> =
        rootPermissionStore.listPersistedRoots()

    override fun checkRoot(treeUri: String): RootAccessMessage =
        rootPermissionStore.checkRoot(treeUri)

    override fun releasePermission(treeUri: String) {
        rootPermissionStore.releasePermission(treeUri)
    }

    override fun startScan(treeUri: String, scanId: String, batchSize: Long) {
        if (batchSize !in 1..128) {
            throw FlutterError(
                code = "INVALID_ARGUMENT",
                message = "Scan batch size must be between 1 and 128.",
            )
        }
        val uri = Uri.parse(treeUri)
        scanSessionRegistry.start(
            scanId = scanId,
            rootDocumentId = DocumentsContract.getTreeDocumentId(uri),
            queryGateway = AndroidDocumentQueryGateway(contentResolver, uri),
            batchSize = batchSize.toInt(),
            sink = scanEventHandler.scanSink(scanId),
        )
    }

    override fun cancelScan(scanId: String) {
        scanSessionRegistry.cancel(scanId)
    }

    override fun readSmallFile(
        treeUri: String,
        storageKey: String,
        maximumBytes: Long,
    ): SmallFileMessage {
        if (maximumBytes !in 1..2_097_152) {
            throw FlutterError(
                code = "INVALID_ARGUMENT",
                message = "Small-file limit is outside the allowed range.",
            )
        }
        return try {
            SmallFileMessage(
                bytes = smallFileReader.read(
                    documentUri(treeUri, storageKey),
                    maximumBytes.toInt(),
                ),
            )
        } catch (error: SmallFileException) {
            throw FlutterError(code = error.code, message = error.message)
        }
    }

    override fun openPlaybackSource(
        treeUri: String,
        storageKey: String,
        strategy: String,
    ): PlaybackLeaseMessage {
        if (strategy != "directContentUri") {
            throw FlutterError(
                code = "PLAYBACK_STRATEGY_UNAVAILABLE",
                message = "The requested playback source strategy is unavailable.",
            )
        }
        return playbackLeaseRegistry.openDirect(documentUri(treeUri, storageKey))
    }

    override fun closePlaybackSource(leaseId: String) {
        playbackLeaseRegistry.close(leaseId)
    }

    override fun probeFile(
        treeUri: String,
        storageKey: String,
    ): ProbeResultMessage = try {
        mediaProbeService.probe(documentUri(treeUri, storageKey))
    } catch (error: ProbeException) {
        throw FlutterError(code = error.code, message = error.message)
    }

    private fun documentUri(treeUri: String, storageKey: String): String {
        val tree = Uri.parse(treeUri)
        val separator = storageKey.indexOf('|')
        if (separator <= 0 || separator == storageKey.lastIndex) {
            throw FlutterError(
                code = "FILE_UNAVAILABLE",
                message = "The selected file identifier is invalid.",
            )
        }
        val authority = storageKey.substring(0, separator)
        if (authority != tree.authority) {
            throw FlutterError(
                code = "FILE_UNAVAILABLE",
                message = "The selected file belongs to another provider.",
            )
        }
        val documentId = storageKey.substring(separator + 1)
        return DocumentsContract.buildDocumentUriUsingTree(tree, documentId).toString()
    }

    private fun notImplemented(operation: String): Nothing =
        throw FlutterError(
            code = "NOT_IMPLEMENTED",
            message = "$operation is not available in this milestone step.",
        )
}
