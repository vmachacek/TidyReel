package com.tidyreel.local_media_hub.platform

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract

class AndroidDocumentQueryGateway(
    private val contentResolver: ContentResolver,
    private val treeUri: Uri,
) : DocumentQueryGateway {
    override val authority: String =
        treeUri.authority
            ?: throw ScanException("ROOT_UNAVAILABLE", "The provider has no authority.")

    override fun children(parentDocumentId: String): List<DocumentNode> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            parentDocumentId,
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS,
        )
        val results = mutableListOf<DocumentNode>()
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            val sizeColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_SIZE,
            )
            val modifiedColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
            val flagsColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_FLAGS,
            )
            while (cursor.moveToNext()) {
                val mimeType = cursor.getString(mimeColumn)
                results += DocumentNode(
                    documentId = cursor.getString(idColumn),
                    displayName = cursor.getString(nameColumn) ?: "Unnamed item",
                    isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR,
                    mimeType = mimeType,
                    sizeBytes = cursor.longOrNull(sizeColumn),
                    modifiedAtEpochMs = cursor.longOrNull(modifiedColumn),
                    flags = cursor.longOrNull(flagsColumn) ?: 0L,
                )
            }
        } ?: throw ScanException(
            "ROOT_UNAVAILABLE",
            "The selected folder could not be queried.",
        )
        return results
    }
}

private fun android.database.Cursor.longOrNull(column: Int): Long? =
    if (isNull(column)) null else getLong(column)
