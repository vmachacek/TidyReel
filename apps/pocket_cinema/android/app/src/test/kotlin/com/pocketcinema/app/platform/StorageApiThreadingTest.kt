package com.pocketcinema.app.platform

import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class StorageApiThreadingTest {
    @Test
    fun `provider IO handlers share a background queue and picker stays on UI queue`() {
        RecordingStorageMessenger().use { messenger ->
            StorageHostApi.setUp(messenger, StubStorageHostApi())

            listOf(
                "listPersistedPermissions",
                "checkRoot",
                "readSmallFile",
                "probeFile",
                "releasePermission",
            ).forEach { method ->
                assertSame(method, messenger.backgroundQueue, messenger.registration(method).queue)
            }
            assertNull(messenger.registration("chooseDirectory").queue)
        }
    }

    @Test
    fun `root discovery executes off the calling thread and replies with its result`() {
        val callingThread = Thread.currentThread()
        var discoveryThread: Thread? = null
        val root = AuthorizedRootMessage("content://provider/tree/root", "Movies")
        RecordingStorageMessenger().use { messenger ->
            StorageHostApi.setUp(messenger, object : StubStorageHostApi() {
                override fun listPersistedPermissions(): List<AuthorizedRootMessage> {
                    discoveryThread = Thread.currentThread()
                    return listOf(root)
                }
            })

            val reply = messenger.dispatch("listPersistedPermissions", null)
                .get(5, TimeUnit.SECONDS)

            assertNotSame(callingThread, discoveryThread)
            assertEquals(listOf(listOf(root)), reply)
        }
    }
}

private class RecordingStorageMessenger : BinaryMessenger, AutoCloseable {
    val backgroundQueue = object : BinaryMessenger.TaskQueue {}
    private val worker = Executors.newSingleThreadExecutor()
    private val registrations = mutableMapOf<String, Registration>()

    data class Registration(
        val handler: BinaryMessenger.BinaryMessageHandler?,
        val queue: BinaryMessenger.TaskQueue?,
    )

    override fun makeBackgroundTaskQueue(): BinaryMessenger.TaskQueue = backgroundQueue

    override fun setMessageHandler(
        channel: String,
        handler: BinaryMessenger.BinaryMessageHandler?,
    ) {
        registrations[channel] = Registration(handler, null)
    }

    override fun setMessageHandler(
        channel: String,
        handler: BinaryMessenger.BinaryMessageHandler?,
        taskQueue: BinaryMessenger.TaskQueue?,
    ) {
        registrations[channel] = Registration(handler, taskQueue)
    }

    fun registration(method: String): Registration = registrations.getValue(
        "dev.flutter.pigeon.pocket_cinema.StorageHostApi.$method",
    )

    fun dispatch(method: String, arguments: Any?): CompletableFuture<Any?> {
        val registration = registration(method)
        val reply = CompletableFuture<Any?>()
        val operation = Runnable {
            try {
                val encoded = StorageHostApi.codec.encodeMessage(arguments)?.apply { flip() }
                registration.handler!!.onMessage(encoded) { response ->
                    response?.flip()
                    reply.complete(StorageHostApi.codec.decodeMessage(response))
                }
            } catch (error: Throwable) {
                reply.completeExceptionally(error)
            }
        }
        if (registration.queue === backgroundQueue) worker.execute(operation)
        else operation.run()
        return reply
    }

    override fun send(channel: String, message: ByteBuffer?) = error("Host sends are unused.")

    override fun send(
        channel: String,
        message: ByteBuffer?,
        callback: BinaryMessenger.BinaryReply?,
    ) = error("Host sends are unused.")

    override fun close() {
        worker.shutdownNow()
    }
}

private open class StubStorageHostApi : StorageHostApi {
    override suspend fun chooseDirectory(): AuthorizedRootMessage = error("Unused picker.")
    override fun listPersistedPermissions(): List<AuthorizedRootMessage> = emptyList()
    override fun checkRoot(treeUri: String): RootAccessMessage = error("Unused root check.")
    override fun startScan(treeUri: String, scanId: String, batchSize: Long) = Unit
    override fun cancelScan(scanId: String) = Unit
    override fun readSmallFile(
        treeUri: String,
        storageKey: String,
        maximumBytes: Long,
    ): SmallFileMessage = error("Unused sidecar read.")
    override fun openPlaybackSource(
        treeUri: String,
        storageKey: String,
        strategy: String,
    ): PlaybackLeaseMessage = error("Unused playback source.")
    override fun closePlaybackSource(leaseId: String) = Unit
    override fun probeFile(treeUri: String, storageKey: String): ProbeResultMessage = error("Unused probe.")
    override fun releasePermission(treeUri: String) = Unit
}
