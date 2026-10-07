package com.tidyreel.local_media_hub.platform

class StorageHostApiImpl(
    private val chooseDirectoryAction: suspend () -> AuthorizedRootMessage,
    private val rootPermissionStore: AndroidRootPermissionStore,
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

    override fun startScan(treeUri: String, scanId: String, batchSize: Long) =
        notImplemented("startScan")

    override fun cancelScan(scanId: String) = notImplemented("cancelScan")

    override fun readSmallFile(
        treeUri: String,
        storageKey: String,
        maximumBytes: Long,
    ): SmallFileMessage = notImplemented("readSmallFile")

    override fun openPlaybackSource(
        treeUri: String,
        storageKey: String,
        strategy: String,
    ): PlaybackLeaseMessage = notImplemented("openPlaybackSource")

    override fun closePlaybackSource(leaseId: String) =
        notImplemented("closePlaybackSource")

    override fun probeFile(
        treeUri: String,
        storageKey: String,
    ): ProbeResultMessage = notImplemented("probeFile")

    private fun notImplemented(operation: String): Nothing =
        throw FlutterError(
            code = "NOT_IMPLEMENTED",
            message = "$operation is not available in this milestone step.",
        )
}
