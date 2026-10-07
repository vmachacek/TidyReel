package com.tidyreel.local_media_hub.platform

import org.junit.Assert.assertEquals
import org.junit.Test

class DocumentTreeEnumeratorTest {
    @Test
    fun `enumerates nested nodes once when provider repeats an id`() {
        val gateway = FakeDocumentQueryGateway.tree(
            root = listOf(
                dir("shows"),
                file("movie", "Movie.mkv", size = null),
            ),
            children = mapOf(
                "shows" to listOf(
                    file("episode", "Episode.mp4"),
                    dir("shows"),
                ),
            ),
        )
        val sink = RecordingScanSink()

        DocumentTreeEnumerator(gateway, batchSize = 2).enumerate(
            "root",
            sink,
            TestScanCancellation(),
        )

        assertEquals(
            listOf("provider|movie", "provider|episode"),
            sink.files.map { entry -> entry.storageKey },
        )
        assertEquals(1, sink.completedCount)
    }

    @Test
    fun `cancellation emits cancelled and never completed`() {
        val signal = TestScanCancellation(cancelled = true)
        val sink = RecordingScanSink()

        DocumentTreeEnumerator(FakeDocumentQueryGateway.empty(), 100)
            .enumerate("root", sink, signal)

        assertEquals(1, sink.cancelledCount)
        assertEquals(0, sink.completedCount)
    }
}

private class FakeDocumentQueryGateway(
    private val childrenByParent: Map<String, List<DocumentNode>>,
) : DocumentQueryGateway {
    override val authority: String = "provider"
    val queries = mutableListOf<String>()

    override fun children(parentDocumentId: String): List<DocumentNode> {
        queries += parentDocumentId
        return childrenByParent[parentDocumentId].orEmpty()
    }

    companion object {
        fun tree(
            root: List<DocumentNode>,
            children: Map<String, List<DocumentNode>>,
        ): FakeDocumentQueryGateway =
            FakeDocumentQueryGateway(children + ("root" to root))

        fun empty(): FakeDocumentQueryGateway = FakeDocumentQueryGateway(emptyMap())
    }
}

private class RecordingScanSink : ScanSink {
    val files = mutableListOf<StorageEntryMessage>()
    var completedCount = 0
    var cancelledCount = 0

    override fun batch(entries: List<StorageEntryMessage>) {
        files += entries
    }

    override fun progress(visitedEntries: Int) = Unit

    override fun warning(code: String) = Unit

    override fun completed() {
        completedCount += 1
    }

    override fun cancelled() {
        cancelledCount += 1
    }

    override fun failed(code: String) = Unit
}

private class TestScanCancellation(
    cancelled: Boolean = false,
) : ScanCancellation {
    override var isCancelled: Boolean = cancelled
}

private fun dir(documentId: String): DocumentNode =
    DocumentNode(
        documentId = documentId,
        displayName = documentId,
        isDirectory = true,
        mimeType = null,
        sizeBytes = null,
        modifiedAtEpochMs = null,
        flags = 0,
    )

private fun file(
    documentId: String,
    displayName: String,
    size: Long? = 1024,
): DocumentNode =
    DocumentNode(
        documentId = documentId,
        displayName = displayName,
        isDirectory = false,
        mimeType = "video/mp4",
        sizeBytes = size,
        modifiedAtEpochMs = null,
        flags = 0,
    )
