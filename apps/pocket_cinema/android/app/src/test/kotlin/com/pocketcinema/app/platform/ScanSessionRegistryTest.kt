package com.pocketcinema.app.platform

import android.os.Process
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ScanSessionRegistryTest {
    @Test
    fun `scanner lowers only its dedicated worker priority before work and reuses it`() {
        val callingThread = Thread.currentThread()
        val priorityThread = AtomicReference<Thread>()
        val priority = AtomicInteger()
        val priorityCalls = AtomicInteger()
        val executor = Executors.newSingleThreadExecutor(BackgroundScanThreadFactory {
            priorityThread.set(Thread.currentThread())
            priority.set(it)
            priorityCalls.incrementAndGet()
        })
        try {
            val firstWorker = executor.submit<Thread> {
                assertSame(Thread.currentThread(), priorityThread.get())
                assertEquals(Process.THREAD_PRIORITY_BACKGROUND, priority.get())
                Thread.currentThread()
            }.get(5, TimeUnit.SECONDS)
            val secondWorker = executor.submit<Thread> { Thread.currentThread() }
                .get(5, TimeUnit.SECONDS)

            assertNotSame(callingThread, firstWorker)
            assertEquals("pocket-cinema-scan", firstWorker.name)
            assertSame(firstWorker, secondWorker)
            assertEquals(1, priorityCalls.get())
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `queued scan cancels immediately while busy worker continues with remaining scans`() {
        val enteredProvider = CountDownLatch(1)
        val releaseProvider = CountDownLatch(1)
        val queuedQueries = AtomicInteger()
        val blockingGateway = object : DocumentQueryGateway {
            override val authority = "provider"

            override fun children(parentDocumentId: String): List<DocumentNode> {
                enteredProvider.countDown()
                check(releaseProvider.await(5, TimeUnit.SECONDS))
                return emptyList()
            }
        }
        val queuedGateway = object : DocumentQueryGateway {
            override val authority = "provider"

            override fun children(parentDocumentId: String): List<DocumentNode> {
                queuedQueries.incrementAndGet()
                return emptyList()
            }
        }
        val executor = Executors.newSingleThreadExecutor(BackgroundScanThreadFactory {})
        ScanSessionRegistry(executor).use { registry ->
            val activeSink = TerminalResultSink()
            val queuedSink = TerminalResultSink()
            val nextSink = TerminalResultSink()
            try {
                registry.start("active", "root", blockingGateway, 100, activeSink)
                assertTrue(enteredProvider.await(5, TimeUnit.SECONDS))
                registry.start("queued", "root", queuedGateway, 100, queuedSink)

                registry.cancel("queued")
                assertEquals("cancelled", queuedSink.result.get(5, TimeUnit.SECONDS))
                registry.cancel("active")
                registry.start("next", "root", queuedGateway, 100, nextSink)
            } finally {
                releaseProvider.countDown()
            }

            assertEquals("cancelled", activeSink.result.get(5, TimeUnit.SECONDS))
            assertEquals("completed", nextSink.result.get(5, TimeUnit.SECONDS))
            assertEquals(1, queuedQueries.get())
            assertEquals(1, queuedSink.terminalCount.get())
            assertEquals(1, activeSink.terminalCount.get())
        }
    }
}

private class TerminalResultSink : ScanSink {
    val result = CompletableFuture<String>()
    val terminalCount = AtomicInteger()

    override fun batch(entries: List<StorageEntryMessage>) = Unit
    override fun progress(visitedEntries: Int) = Unit
    override fun warning(code: String) = Unit
    override fun completed() = finish("completed")
    override fun cancelled() = finish("cancelled")
    override fun failed(code: String) = finish(code)

    private fun finish(value: String) {
        terminalCount.incrementAndGet()
        result.complete(value)
    }
}
