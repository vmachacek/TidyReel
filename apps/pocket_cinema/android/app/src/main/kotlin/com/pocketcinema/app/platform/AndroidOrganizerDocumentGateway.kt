package com.pocketcinema.app.platform

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract

class AndroidOrganizerDocumentGateway(
    private val resolver: ContentResolver,
    treeValue: String,
) : OrganizerDocumentGateway {
    private val tree = Uri.parse(treeValue).also {
        if (it.scheme != "content" || it.authority.isNullOrBlank() ||
            !DocumentsContract.isTreeUri(it) || it.pathSegments.size != 2 ||
            it.query != null || it.fragment != null) {
            throw OrganizerException("Choose a valid media folder before organizing files.")
        }
    }
    override val authority: String = tree.authority!!
    override val rootId: String = DocumentsContract.getTreeDocumentId(tree)
    private val query = AndroidDocumentQueryGateway(resolver, tree)

    override fun requireWritePermission() {
        if (!hasWritePermission()) throw SecurityException("A persisted read/write folder grant is required.")
        if (!document(rootId).directory) throw OrganizerException("The selected media folder is unavailable.")
    }

    fun hasWritePermission(): Boolean = resolver.persistedUriPermissions.any {
        it.uri == tree && it.isReadPermission && it.isWritePermission
    }

    override fun document(id: String): OrganizerDocument {
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_FLAGS,
        )
        resolver.query(uri(id), columns, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val actualId = cursor.getString(0)
                if (actualId != id) throw OrganizerException("The storage provider returned a different file.")
                return node(actualId, cursor.getString(1), cursor.getString(2), cursor.getLong(3))
            }
        }
        throw OrganizerException("The file or folder is no longer available. Refresh the library.")
    }

    override fun children(parentId: String): List<OrganizerDocument> = query.children(parentId).map {
        node(it.documentId, it.displayName, it.mimeType, it.flags)
    }

    override fun createDirectory(parentId: String, name: String): String = returnedId(
        DocumentsContract.createDocument(resolver, uri(parentId), DocumentsContract.Document.MIME_TYPE_DIR, name),
    )

    override fun rename(id: String, name: String): String = returnedId(
        DocumentsContract.renameDocument(resolver, uri(id), name),
    )

    override fun move(id: String, sourceParentId: String, targetParentId: String): String = returnedId(
        DocumentsContract.moveDocument(resolver, uri(id), uri(sourceParentId), uri(targetParentId)),
    )

    private fun returnedId(value: Uri?): String {
        if (value == null || value.scheme != "content" || value.authority != authority) {
            throw OrganizerException("The storage provider could not finish the file operation.")
        }
        return DocumentsContract.getDocumentId(value)
    }

    private fun uri(id: String): Uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)

    private fun node(id: String, name: String?, mime: String?, flags: Long) = OrganizerDocument(
        id = id,
        name = name ?: throw OrganizerException("A file or folder has no filename."),
        directory = mime == DocumentsContract.Document.MIME_TYPE_DIR,
        canMove = flags and DocumentsContract.Document.FLAG_SUPPORTS_MOVE.toLong() != 0L,
        canRename = flags and DocumentsContract.Document.FLAG_SUPPORTS_RENAME.toLong() != 0L,
        canCreate = flags and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE.toLong() != 0L,
    )
}
