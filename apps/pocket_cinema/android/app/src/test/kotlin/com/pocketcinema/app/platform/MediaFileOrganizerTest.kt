package com.pocketcinema.app.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaFileOrganizerTest {
    @Test
    fun `creates canonical folders and moves then renames with new provider ids`() {
        val gateway = FakeOrganizerGateway().apply { file("video", "root", "Movie.2024.1080p-GROUP.mkv") }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Movie.2024.1080p-GROUP.mkv"))).single()

        assertEquals("moved", result.status)
        assertEquals("Movies/Movie (2024)/Movie (2024).mkv", gateway.path(result.newStorageKey!!.substringAfter('|')))
        assertEquals(listOf("mkdir:Movies", "mkdir:Movie (2024)", "move:Movie.2024.1080p-GROUP.mkv", "rename:Movie (2024).mkv"), gateway.operations)
        assertEquals(1, gateway.filesCount)
    }

    @Test
    fun `unchanged validates live identity without provider mutations`() {
        val gateway = FakeOrganizerGateway().apply {
            directory("movies", "root", "Movies")
            file("video", "movies", "Movie.mkv")
        }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Movies/Movie.mkv", "Movies/Movie.mkv", "movies"))).single()
        assertEquals("unchanged", result.status)
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `refuses read only grants before querying or modifying files`() {
        val gateway = FakeOrganizerGateway().apply { writeGranted = false; file("video", "root", "Raw.mkv") }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv"))).single()
        assertEquals("failed", result.status)
        assertTrue(result.message!!.contains("Choose the media folder again"))
        assertEquals(0, gateway.queries)
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `refuses foreign source and parent authority`() {
        for (foreignParent in listOf(false, true)) {
            val gateway = FakeOrganizerGateway().apply { file("video", "root", "Raw.mkv") }
            val item = request("video", "Raw.mkv").copy(
                storageKey = if (foreignParent) "provider|video" else "other|video",
                parentStorageKey = if (foreignParent) "other|root" else "provider|root",
            )
            assertEquals("failed", MediaFileOrganizer(gateway).organize(listOf(item)).single().status)
            assertTrue(gateway.operations.isEmpty())
        }
    }

    @Test
    fun `refuses stale filename and stale parent even with same provider document id`() {
        val gateway = FakeOrganizerGateway().apply {
            directory("downloads", "root", "Downloads")
            file("video", "downloads", "New.mkv")
        }
        for (item in listOf(
            request("video", "Downloads/Old.mkv", parent = "downloads"),
            request("video", "Downloads/New.mkv", parent = "root"),
            request("different-video", "Downloads/New.mkv", parent = "downloads"),
        )) {
            assertEquals("failed", MediaFileOrganizer(gateway).organize(listOf(item)).single().status)
        }
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `refuses unenumerated document id outside selected tree`() {
        val gateway = FakeOrganizerGateway().apply { file("video", "outside", "Raw.mkv") }
        assertEquals("failed", MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv", parent = "outside"))).single().status)
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `rejects traversal absolute paths and unclean destination components`() {
        val invalid = listOf("../Movies/Movie.mkv", "/Movies/Movie.mkv", "Movies//Movie.mkv",
            "Movies/../Movie.mkv", "Movies/./Movie.mkv", "Movies/Folder\\Movie.mkv",
            "movies/Movie.mkv", "Downloads/Movie.mkv", "TV", "Movies/ Movie.mkv",
            "Movies/Movie.mkv.", "Movies/Movie?.mkv", "Movies/Movie\u0000.mkv")
        for (destination in invalid) {
            val gateway = FakeOrganizerGateway().apply { file("video", "root", "Raw.mkv") }
            assertEquals(destination, "failed", MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv", destination))).single().status)
            assertTrue(destination, gateway.operations.isEmpty())
        }
    }

    @Test
    fun `never overwrites case insensitive existing destination file`() {
        val gateway = FakeOrganizerGateway().apply {
            file("video", "root", "Raw.mkv")
            directory("movies", "root", "Movies")
            file("existing", "movies", "MOVIE.MKV")
        }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv", "Movies/Movie.mkv"))).single()
        assertEquals("failed", result.status)
        assertTrue(result.message!!.contains("Nothing was overwritten"))
        assertEquals("Movies/MOVIE.MKV", gateway.path("existing"))
        assertEquals("Raw.mkv", gateway.path("video"))
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `rejects differently cased destination folders and files used as folders`() {
        for (directory in listOf(true, false)) {
            val gateway = FakeOrganizerGateway().apply {
                file("video", "root", "Raw.mkv")
                if (directory) directory("conflict", "root", "movies") else file("conflict", "root", "Movies")
            }
            assertEquals("failed", MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv"))).single().status)
            assertTrue(gateway.operations.isEmpty())
        }
    }

    @Test
    fun `refuses unsupported native move before creating folders`() {
        val gateway = FakeOrganizerGateway().apply { file("video", "root", "Raw.mkv", canMove = false) }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv"))).single()
        assertEquals("failed", result.status)
        assertTrue(result.message!!.contains("cannot move files safely"))
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `refuses unsupported native rename before creating folders`() {
        val gateway = FakeOrganizerGateway().apply { file("video", "root", "Raw.mkv", canRename = false) }
        assertEquals("failed", MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv"))).single().status)
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `renames in place when movement is unsupported`() {
        val gateway = FakeOrganizerGateway().apply {
            directory("movies", "root", "Movies")
            file("video", "movies", "Raw.mkv", canMove = false)
        }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Movies/Raw.mkv", "Movies/Movie.mkv", "movies"))).single()
        assertEquals("moved", result.status)
        assertEquals(listOf("rename:Movie.mkv"), gateway.operations)
    }

    @Test
    fun `supports moving without rename when rename is unsupported`() {
        val gateway = FakeOrganizerGateway().apply { file("video", "root", "Movie.mkv", canRename = false) }
        assertEquals("moved", MediaFileOrganizer(gateway).organize(listOf(request("video", "Movie.mkv", "Movies/Movie.mkv"))).single().status)
        assertFalse(gateway.operations.any { it.startsWith("rename:") })
    }

    @Test
    fun `moves first when a clean name already exists in source folder`() {
        val gateway = FakeOrganizerGateway().apply {
            file("video", "root", "Raw.mkv")
            file("existing", "root", "Movie.mkv")
        }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv", "Movies/Movie.mkv"))).single()
        assertEquals("moved", result.status)
        assertEquals("Movie.mkv", gateway.path("existing"))
        assertEquals(listOf("mkdir:Movies", "move:Raw.mkv", "rename:Movie.mkv"), gateway.operations)
    }

    @Test
    fun `renames first when original name already exists in target folder`() {
        val gateway = FakeOrganizerGateway().apply {
            file("video", "root", "Raw.mkv")
            directory("movies", "root", "Movies")
            file("existing", "movies", "raw.mkv")
        }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv", "Movies/Movie.mkv"))).single()
        assertEquals("moved", result.status)
        assertEquals(listOf("rename:Movie.mkv", "move:Movie.mkv"), gateway.operations)
        assertEquals("Movies/raw.mkv", gateway.path("existing"))
    }

    @Test
    fun `rolls back move if subsequent rename fails`() {
        val gateway = FakeOrganizerGateway().apply {
            file("video", "root", "Raw.mkv")
            failRenameName = "Movie.mkv"
        }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv", "Movies/Movie.mkv"))).single()
        assertEquals("failed", result.status)
        assertTrue(result.message!!.contains("original file location was restored"))
        assertEquals("Raw.mkv", gateway.path(result.newStorageKey!!.substringAfter('|')))
        assertEquals("Raw.mkv", result.actualRelativePath)
        assertTrue(result.newStorageKey != "provider|video")
        assertEquals("provider|root", result.newParentStorageKey)
        assertEquals(1, gateway.filesCount)
    }

    @Test
    fun `rolls back rename if subsequent move fails`() {
        val gateway = FakeOrganizerGateway().apply {
            file("video", "root", "Raw.mkv")
            directory("movies", "root", "Movies")
            file("existing", "movies", "Raw.mkv")
            failMoveOnce = true
        }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv", "Movies/Movie.mkv"))).single()
        assertEquals("failed", result.status)
        assertEquals("Raw.mkv", gateway.path(result.newStorageKey!!.substringAfter('|')))
        assertEquals("Movies/Raw.mkv", gateway.path("existing"))
    }

    @Test
    fun `reports partial location when rollback fails without deleting file`() {
        val gateway = FakeOrganizerGateway().apply {
            file("video", "root", "Raw.mkv")
            failRenameName = "Movie.mkv"
            failRollback = true
        }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv", "Movies/Movie.mkv"))).single()
        assertEquals("failed", result.status)
        assertTrue(result.message!!.contains("Automatic rollback could not complete"))
        assertEquals("Movies/Raw.mkv", gateway.path(result.newStorageKey!!.substringAfter('|')))
        assertEquals("Movies/Raw.mkv", result.actualRelativePath)
        assertEquals(1, gateway.filesCount)
    }

    @Test
    fun `restores actual provider filename when provider changes requested name`() {
        val gateway = FakeOrganizerGateway().apply {
            file("video", "root", "Raw.mkv")
            alteredRenameName = "Movie.mkv"
        }
        val result = MediaFileOrganizer(gateway).organize(listOf(request("video", "Raw.mkv", "Movies/Movie.mkv"))).single()
        assertEquals("failed", result.status)
        assertTrue(result.message!!.contains("original file location was restored"))
        assertEquals("Raw.mkv", gateway.path(result.newStorageKey!!.substringAfter('|')))
        assertEquals(1, gateway.filesCount)
    }

    @Test
    fun `rejects all planned case insensitive collisions before either file moves`() {
        val gateway = FakeOrganizerGateway().apply {
            file("one", "root", "One.mkv")
            file("two", "root", "Two.mkv")
        }
        val results = MediaFileOrganizer(gateway).organize(listOf(
            request("one", "One.mkv", "Movies/Movie.mkv"),
            request("two", "Two.mkv", "Movies/MOVIE.mkv"),
        ))
        assertEquals(listOf("failed", "failed"), results.map { it.status })
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `rejects duplicate sources even with different destinations`() {
        val gateway = FakeOrganizerGateway().apply { file("video", "root", "Raw.mkv") }
        val results = MediaFileOrganizer(gateway).organize(listOf(
            request("video", "Raw.mkv", "Movies/One.mkv"),
            request("video", "Raw.mkv", "Movies/Two.mkv"),
        ))
        assertEquals(listOf("failed", "failed"), results.map { it.status })
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `continues other files after one file fails`() {
        val gateway = FakeOrganizerGateway().apply {
            file("one", "root", "One.mkv", canMove = false)
            file("two", "root", "Two.mkv")
        }
        val results = MediaFileOrganizer(gateway).organize(listOf(
            request("one", "One.mkv", "Movies/One.mkv"),
            request("two", "Two.mkv", "Movies/Two.mkv"),
        ))
        assertEquals(listOf("failed", "moved"), results.map { it.status })
        assertEquals("One.mkv", gateway.path("one"))
        assertEquals(2, gateway.filesCount)
    }

    @Test
    fun `leaves sidecar in place if its video fails even when sidecar listed first`() {
        val gateway = FakeOrganizerGateway().apply {
            file("video", "root", "Raw.mkv", canMove = false)
            file("subtitle", "root", "Raw.en.srt")
        }
        val results = MediaFileOrganizer(gateway).organize(listOf(
            request("subtitle", "Raw.en.srt", "Movies/Movie.en.srt").copy(videoStorageKey = "provider|video"),
            request("video", "Raw.mkv", "Movies/Movie.mkv"),
        ))
        assertEquals(listOf("provider|subtitle", "provider|video"), results.map { it.storageKey })
        assertEquals(listOf("failed", "failed"), results.map { it.status })
        assertTrue(results.first().message!!.contains("matching video"))
        assertTrue(gateway.operations.isEmpty())
    }

    @Test
    fun `moves sidecar after successful paired video while preserving result order`() {
        val gateway = FakeOrganizerGateway().apply {
            file("video", "root", "Raw.mkv")
            file("subtitle", "root", "Raw.en.srt")
        }
        val results = MediaFileOrganizer(gateway).organize(listOf(
            request("subtitle", "Raw.en.srt", "Movies/Movie.en.srt").copy(videoStorageKey = "provider|video"),
            request("video", "Raw.mkv", "Movies/Movie.mkv"),
        ))
        assertEquals(listOf("moved", "moved"), results.map { it.status })
        assertEquals("Movies/Movie.en.srt", gateway.path(results.first().newStorageKey!!.substringAfter('|')))
        assertEquals(listOf("mkdir:Movies", "move:Raw.mkv", "rename:Movie.mkv", "move:Raw.en.srt", "rename:Movie.en.srt"), gateway.operations)
    }

    private fun request(id: String, source: String,
        destination: String = "Movies/Movie (2024)/Movie (2024).mkv", parent: String = "root") =
        OrganizeFileRequest("provider|$id", "provider|$parent", source, destination)
}

private class FakeOrganizerGateway : OrganizerDocumentGateway {
    override val authority = "provider"
    override val rootId = "root"
    private data class Entry(val document: OrganizerDocument, val parent: String?)
    private val entries = mutableMapOf("root" to Entry(OrganizerDocument("root", "root", true, canCreate = true), null))
    val operations = mutableListOf<String>()
    var writeGranted = true
    var queries = 0
    var failRenameName: String? = null
    var failMoveOnce = false
    var failRollback = false
    var alteredRenameName: String? = null
    private var nextId = 0
    val filesCount: Int get() = entries.values.count { !it.document.directory }

    fun file(id: String, parent: String, name: String, canMove: Boolean = true, canRename: Boolean = true) {
        entries[id] = Entry(OrganizerDocument(id, name, false, canMove, canRename), parent)
    }
    fun directory(id: String, parent: String, name: String) {
        entries[id] = Entry(OrganizerDocument(id, name, true, canCreate = true), parent)
    }
    fun path(id: String): String {
        val entry = entries.getValue(id)
        return if (entry.parent == rootId) entry.document.name else path(entry.parent!!) + "/" + entry.document.name
    }
    override fun requireWritePermission() {
        if (!writeGranted) throw SecurityException()
    }
    override fun document(id: String): OrganizerDocument {
        queries += 1
        return entries.getValue(id).document
    }
    override fun children(parentId: String): List<OrganizerDocument> {
        queries += 1
        return entries.values.filter { it.parent == parentId }.map { it.document }
    }
    override fun createDirectory(parentId: String, name: String): String {
        operations += "mkdir:$name"
        val id = "created-${++nextId}"
        directory(id, parentId, name)
        return id
    }
    override fun rename(id: String, name: String): String {
        if (name == failRenameName) throw UnsupportedOperationException()
        val previous = entries.remove(id)!!
        operations += "rename:$name"
        val changedId = "renamed-${++nextId}"
        entries[changedId] = previous.copy(document = previous.document.copy(id = changedId,
            name = if (name == alteredRenameName) "Unexpected $name" else name))
        return changedId
    }
    override fun move(id: String, sourceParentId: String, targetParentId: String): String {
        if (failMoveOnce) { failMoveOnce = false; throw UnsupportedOperationException() }
        if (failRollback && targetParentId == rootId) throw UnsupportedOperationException()
        val previous = entries.remove(id)!!
        check(previous.parent == sourceParentId)
        operations += "move:${previous.document.name}"
        val changedId = "moved-${++nextId}"
        entries[changedId] = previous.copy(document = previous.document.copy(id = changedId), parent = targetParentId)
        return changedId
    }
}
