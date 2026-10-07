package com.pocketcinema.app.platform

import java.util.ArrayDeque

interface ScanCancellation {
    val isCancelled: Boolean
}

interface ScanSink {
    fun batch(entries: List<StorageEntryMessage>)

    fun progress(visitedEntries: Int)

    fun warning(code: String)

    fun completed()

    fun cancelled()

    fun failed(code: String)
}

class ScanException(
    val code: String,
    safeMessage: String,
) : RuntimeException(safeMessage)

class DocumentTreeEnumerator(
    private val queryGateway: DocumentQueryGateway,
    private val batchSize: Int,
) {
    init {
        require(batchSize in 1..128) { "Batch size must be between 1 and 128." }
    }

    fun enumerate(
        rootDocumentId: String,
        sink: ScanSink,
        cancellation: ScanCancellation,
    ) {
        val queue = ArrayDeque<DirectoryWork>()
        val visited = mutableSetOf(rootDocumentId)
        val batch = ArrayList<StorageEntryMessage>(batchSize)
        queue.add(DirectoryWork(rootDocumentId, ""))
        var visitedEntries = 0

        while (queue.isNotEmpty() && !cancellation.isCancelled) {
            val directory = queue.removeFirst()
            for (node in queryGateway.children(directory.documentId)) {
                if (cancellation.isCancelled) {
                    break
                }
                if (!visited.add(node.documentId)) {
                    continue
                }
                visitedEntries += 1
                val relativePath = directory.relativePath
                    .takeIf { path -> path.isNotEmpty() }
                    ?.let { path -> path + "/" + node.displayName }
                    ?: node.displayName
                if (node.isDirectory) {
                    queue.add(DirectoryWork(node.documentId, relativePath))
                } else {
                    batch.add(
                        node.toMessage(
                            authority = queryGateway.authority,
                            parentDocumentId = directory.documentId,
                            relativePath = relativePath,
                        ),
                    )
                    if (batch.size == batchSize) {
                        sink.batch(batch.toList())
                        batch.clear()
                    }
                }
                sink.progress(visitedEntries)
            }
        }

        if (cancellation.isCancelled) {
            sink.cancelled()
        } else {
            if (batch.isNotEmpty()) {
                sink.batch(batch.toList())
            }
            sink.completed()
        }
    }

    private data class DirectoryWork(
        val documentId: String,
        val relativePath: String,
    )
}
