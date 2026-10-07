package com.tidyreel.local_media_hub.platform

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract

class AndroidRootPermissionStore(
    private val contentResolver: ContentResolver,
) {
    fun persistReadPermission(
        treeUri: Uri,
        returnedFlags: Int,
    ): AuthorizedRootMessage {
        val readFlags = PersistableFlagPolicy.readOnly(returnedFlags)
        if (readFlags == 0) {
            throw FlutterError(
                code = "PERMISSION_REVOKED",
                message = "The selected provider did not return read access.",
            )
        }

        try {
            contentResolver.takePersistableUriPermission(treeUri, readFlags)
        } catch (_: SecurityException) {
            throw FlutterError(
                code = "PERMISSION_REVOKED",
                message = "Read access could not be retained.",
            )
        }

        return authorizedRoot(treeUri)
    }

    fun listPersistedRoots(): List<AuthorizedRootMessage> =
        contentResolver.persistedUriPermissions
            .asSequence()
            .filter { permission -> permission.isReadPermission }
            .map { permission -> authorizedRoot(permission.uri) }
            .toList()

    fun checkRoot(treeUri: String): RootAccessMessage {
        val uri = Uri.parse(treeUri)
        val hasPersistedRead = contentResolver.persistedUriPermissions.any { permission ->
            permission.isReadPermission && permission.uri == uri
        }
        val state = RootAccessEvaluator.evaluate(
            hasPersistedRead = hasPersistedRead,
            rootQueryable = hasPersistedRead && queryDisplayName(uri) != null,
        )
        return RootAccessMessage(state = state.wireValue)
    }

    fun releasePermission(treeUri: String) {
        val uri = Uri.parse(treeUri)
        val hasPersistedRead = contentResolver.persistedUriPermissions.any { permission ->
            permission.isReadPermission && permission.uri == uri
        }
        if (!hasPersistedRead) {
            throw FlutterError(
                code = "PERMISSION_REVOKED",
                message = "Persisted read access is absent.",
            )
        }

        try {
            contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            throw FlutterError(
                code = "PERMISSION_REVOKED",
                message = "Persisted read access is absent.",
            )
        }
    }

    private fun authorizedRoot(treeUri: Uri): AuthorizedRootMessage =
        AuthorizedRootMessage(
            treeUri = treeUri.toString(),
            displayName = queryDisplayName(treeUri) ?: "Selected folder",
        )

    private fun queryDisplayName(treeUri: Uri): String? {
        return try {
            val documentId = DocumentsContract.getTreeDocumentId(treeUri)
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                documentId,
            )
            contentResolver.query(
                documentUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    return null
                }
                cursor.getString(0)?.takeIf { value -> value.isNotBlank() }
                    ?: "Selected folder"
            }
        } catch (_: Exception) {
            null
        }
    }
}
