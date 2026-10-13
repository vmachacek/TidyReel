package com.pocketcinema.app.platform

data class OrganizeFileRequest(
    val storageKey: String,
    val parentStorageKey: String,
    val sourceRelativePath: String,
    val destinationRelativePath: String,
    val videoStorageKey: String? = null,
)

data class OrganizeFileResult(
    val storageKey: String,
    val destinationRelativePath: String,
    val status: String,
    val message: String? = null,
    val newStorageKey: String? = null,
    val newParentStorageKey: String? = null,
    val actualRelativePath: String? = null,
) {
    fun toMap(): Map<String, Any> = buildMap {
        put("storageKey", storageKey)
        put("destinationRelativePath", destinationRelativePath)
        put("status", status)
        message?.let { put("message", it) }
        newStorageKey?.let { put("newStorageKey", it) }
        newParentStorageKey?.let { put("newParentStorageKey", it) }
        actualRelativePath?.let { put("actualRelativePath", it) }
    }
}

data class OrganizerDocument(
    val id: String,
    val name: String,
    val directory: Boolean,
    val canMove: Boolean = false,
    val canRename: Boolean = false,
    val canCreate: Boolean = false,
)

/** Provider-native operations only: no copying, deleting, or replacing media. */
interface OrganizerDocumentGateway {
    val authority: String
    val rootId: String
    fun requireWritePermission()
    fun document(id: String): OrganizerDocument
    fun children(parentId: String): List<OrganizerDocument>
    fun createDirectory(parentId: String, name: String): String
    fun rename(id: String, name: String): String
    fun move(id: String, sourceParentId: String, targetParentId: String): String
}

/** Runs serially; every request is checked against the provider's current tree. */
class MediaFileOrganizer(private val gateway: OrganizerDocumentGateway) {
    fun organize(items: List<OrganizeFileRequest>): List<OrganizeFileResult> {
        val permissionFailure = runCatching { gateway.requireWritePermission() }.exceptionOrNull()
        if (permissionFailure != null) return items.map { failed(it, permissionFailure) }
        val repeatedSources = items.groupingBy { it.storageKey }.eachCount().filterValues { it > 1 }.keys
        val repeatedDestinations = items.groupingBy { folded(it.destinationRelativePath) }
            .eachCount().filterValues { it > 1 }.keys
        val results = mutableMapOf<Int, OrganizeFileResult>()
        val videoResults = mutableMapOf<String, OrganizeFileResult>()
        val order = items.indices.sortedBy { if (items[it].videoStorageKey == null) 0 else 1 }
        for (index in order) {
            val item = items[index]
            val result = when {
                item.storageKey in repeatedSources -> failed(item, "The same source file appears more than once.")
                folded(item.destinationRelativePath) in repeatedDestinations ->
                    failed(item, "Multiple files have the same destination. Resolve the collision first.")
                item.videoStorageKey != null &&
                    videoResults[item.videoStorageKey]?.status !in setOf("moved", "unchanged") ->
                    failed(item, "The matching video could not be organized. Its companion file was left in place.")
                else -> try {
                    organizeOne(item)
                } catch (error: Exception) {
                    failed(item, error)
                }
            }
            results[index] = result
            if (item.videoStorageKey == null) videoResults[item.storageKey] = result
        }
        return items.indices.map { results.getValue(it) }
    }

    private fun organizeOne(item: OrganizeFileRequest): OrganizeFileResult {
        val sourceParts = pathParts(item.sourceRelativePath, destination = false)
        val destinationParts = pathParts(item.destinationRelativePath, destination = true)
        val sourceId = documentId(item.storageKey)
        val sourceParentId = documentId(item.parentStorageKey)
        val source = findSource(sourceParts, sourceId, sourceParentId)
        if (item.sourceRelativePath == item.destinationRelativePath) {
            return OrganizeFileResult(item.storageKey, item.destinationRelativePath, "unchanged",
                newStorageKey = item.storageKey, newParentStorageKey = item.parentStorageKey,
                actualRelativePath = item.sourceRelativePath)
        }

        val name = destinationParts.last()
        val needsRename = source.name != name
        // Check native capabilities before even creating destination folders.
        val destinationParentPath = destinationParts.dropLast(1).joinToString("/")
        val sourceParentPath = sourceParts.dropLast(1).joinToString("/")
        if (destinationParentPath != sourceParentPath && !source.canMove) {
            fail("This storage provider cannot move files safely. Choose a writable device folder.")
        }
        if (needsRename && !source.canRename) {
            fail("This storage provider does not support renaming this file.")
        }
        val targetParentId = destinationDirectory(destinationParts.dropLast(1))
        val needsMove = sourceParentId != targetParentId
        if (needsMove && !source.canMove) fail("This storage provider does not support moving this file.")
        requireFreeName(targetParentId, name, if (needsMove) null else sourceId)

        var currentId = sourceId
        var currentParentId = sourceParentId
        var currentName = source.name
        try {
            // Moving first avoids an unrelated clean filename in the source folder.
            // If the original filename exists at the destination, rename first instead.
            val renameFirst = needsMove && needsRename &&
                hasName(targetParentId, source.name, null)
            if (renameFirst) {
                requireFreeName(currentParentId, name, currentId)
                currentId = gateway.rename(currentId, name)
                currentName = name
                verify(currentParentId, currentId, currentName)
            }
            if (needsMove) {
                requireFreeName(targetParentId, currentName, null)
                currentId = gateway.move(currentId, currentParentId, targetParentId)
                currentParentId = targetParentId
                verify(currentParentId, currentId, currentName)
            }
            if (needsRename && !renameFirst) {
                requireFreeName(currentParentId, name, currentId)
                currentId = gateway.rename(currentId, name)
                currentName = name
                verify(currentParentId, currentId, currentName)
            }
            return OrganizeFileResult(
                item.storageKey, item.destinationRelativePath, "moved",
                newStorageKey = "${gateway.authority}|$currentId",
                newParentStorageKey = "${gateway.authority}|$currentParentId",
                actualRelativePath = item.destinationRelativePath,
            )
        } catch (error: Exception) {
            // Undo completed provider operations when their old names are still free.
            // A failed rollback is visible so the next scan can recover the live path.
            runCatching { gateway.document(currentId) }.getOrNull()?.let { currentName = it.name }
            val rollback = runCatching {
                if (currentParentId != sourceParentId) {
                    if (hasName(sourceParentId, currentName, null)) {
                        // The original name may be available even when the clean one isn't.
                        requireFreeName(currentParentId, source.name, currentId)
                        currentId = gateway.rename(currentId, source.name)
                        currentName = source.name
                    }
                    requireFreeName(sourceParentId, currentName, null)
                    currentId = gateway.move(currentId, currentParentId, sourceParentId)
                    currentParentId = sourceParentId
                }
                if (currentName != source.name) {
                    requireFreeName(sourceParentId, source.name, currentId)
                    currentId = gateway.rename(currentId, source.name)
                    currentName = source.name
                }
                verify(sourceParentId, currentId, source.name)
            }
            val actualPath = runCatching {
                val actual = gateway.children(currentParentId).singleOrNull { it.id == currentId && !it.directory }
                    ?: fail("The current file location is unavailable.")
                val parentParts = when (currentParentId) {
                    sourceParentId -> sourceParts.dropLast(1)
                    targetParentId -> destinationParts.dropLast(1)
                    else -> fail("The current folder is unavailable.")
                }
                val parts = parentParts + actual.name
                // Rewalk the tree so a provider ID alone cannot imply a stale path.
                findSource(parts, currentId, currentParentId)
                parts.joinToString("/")
            }.getOrNull()
            val detail = safeMessage(error) + if (rollback.isFailure) {
                " The file may now be at ${actualPath ?: currentName}; refresh the library to locate it. Automatic rollback could not complete."
            } else " The original file location was restored."
            return OrganizeFileResult(
                item.storageKey, item.destinationRelativePath, "failed", detail,
                newStorageKey = actualPath?.let { "${gateway.authority}|$currentId" },
                newParentStorageKey = actualPath?.let { "${gateway.authority}|$currentParentId" },
                actualRelativePath = actualPath,
            )
        }
    }

    private fun findSource(parts: List<String>, sourceId: String, parentId: String): OrganizerDocument {
        var parent = gateway.rootId
        val visited = mutableSetOf(parent)
        for ((index, name) in parts.withIndex()) {
            val matches = gateway.children(parent).filter { it.name == name }
            if (matches.size != 1) fail("The source path has changed. Refresh the library before organizing.")
            val node = matches.single()
            if (index == parts.lastIndex) {
                if (node.directory || node.id != sourceId || parent != parentId) {
                    fail("The source file or parent has changed. Refresh the library before organizing.")
                }
                return node
            }
            if (!node.directory || !visited.add(node.id)) fail("The source is outside the selected folder.")
            parent = node.id
        }
        fail("The source file is unavailable.")
    }

    private fun destinationDirectory(parts: List<String>): String {
        var parent = gateway.rootId
        val visited = mutableSetOf(parent)
        for (name in parts) {
            val matches = gateway.children(parent).filter { folded(it.name) == folded(name) }
            val child = when {
                matches.size > 1 -> fail("The destination folder has a case-insensitive name collision.")
                matches.size == 1 -> matches.single().also {
                    if (!it.directory || it.name != name) fail("A different file or folder already uses the destination folder name: $name.")
                }
                else -> {
                    if (!gateway.document(parent).canCreate) fail("This destination folder cannot create subfolders.")
                    val id = gateway.createDirectory(parent, name)
                    gateway.children(parent).singleOrNull { it.id == id && it.name == name && it.directory }
                        ?: fail("The storage provider could not create the exact destination folder: $name.")
                }
            }
            if (!visited.add(child.id)) fail("The destination is outside the selected folder.")
            parent = child.id
        }
        return parent
    }

    private fun verify(parent: String, id: String, name: String) {
        if (gateway.children(parent).count { it.id == id && it.name == name && !it.directory } != 1) {
            fail("The storage provider did not preserve the requested filename or location.")
        }
    }

    private fun hasName(parent: String, name: String, excludingId: String?): Boolean =
        gateway.children(parent).any { it.id != excludingId && folded(it.name) == folded(name) }

    private fun requireFreeName(parent: String, name: String, excludingId: String?) {
        if (hasName(parent, name, excludingId)) fail("A file or folder already exists at the destination: $name. Nothing was overwritten.")
    }

    private fun documentId(key: String): String {
        val separator = key.indexOf('|')
        if (separator < 1 || separator == key.lastIndex || key.substring(0, separator) != gateway.authority) {
            fail("The file belongs to a different storage provider.")
        }
        return key.substring(separator + 1)
    }

    private fun pathParts(path: String, destination: Boolean): List<String> {
        val parts = path.split('/')
        if (parts.isEmpty() || parts.any { it.isEmpty() || it == "." || it == ".." ||
                it.contains('\\') || it.any { character -> character.code < 32 || character.code == 127 } }) {
            fail("The file path is invalid.")
        }
        if (destination && (parts.size < 2 || parts.first() !in setOf("TV", "Movies") ||
                parts.any { it != it.trim() || it.endsWith('.') || it.any { ch -> ch in "<>:\"|?*" } })) {
            fail("The destination must be a clean path inside TV/ or Movies/.")
        }
        return parts
    }

    private fun failed(item: OrganizeFileRequest, error: Throwable): OrganizeFileResult = failed(item, safeMessage(error))
    private fun failed(item: OrganizeFileRequest, message: String) =
        OrganizeFileResult(item.storageKey, item.destinationRelativePath, "failed", message)
    private fun safeMessage(error: Throwable): String = when (error) {
        is OrganizerException -> error.message ?: "The file could not be organized."
        is SecurityException -> "Write access is unavailable. Choose the media folder again to allow renaming and moving."
        is UnsupportedOperationException -> "This storage provider does not support safe file moves or renaming."
        else -> "The storage provider could not organize this file. Refresh the library and try again."
    }
    // Match Unicode case-insensitive comparisons without locale-specific expansion.
    private fun folded(value: String): String = value.map { it.uppercaseChar().lowercaseChar() }.joinToString("")
    private fun fail(message: String): Nothing = throw OrganizerException(message)
}

class OrganizerException(message: String) : RuntimeException(message)
