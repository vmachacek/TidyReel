package com.tidyreel.local_media_hub.platform

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.atomic.AtomicBoolean

class ScanSessionRegistry(
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
) : AutoCloseable {
    private val sessions = ConcurrentHashMap<String, ScanSession>()

    fun start(
        scanId: String,
        rootDocumentId: String,
        queryGateway: DocumentQueryGateway,
        batchSize: Int,
        sink: ScanSink,
    ) {
        val cancellation = AtomicScanCancellation()
        val started = AtomicBoolean(false)
        val terminal = AtomicBoolean(false)
        lateinit var task: FutureTask<Unit>
        task = FutureTask {
            started.set(true)
            try {
                DocumentTreeEnumerator(queryGateway, batchSize).enumerate(
                    rootDocumentId,
                    TerminalScanSink(sink, terminal),
                    cancellation,
                )
            } catch (error: Exception) {
                if (terminal.compareAndSet(false, true)) {
                    if (cancellation.isCancelled) {
                        sink.cancelled()
                    } else {
                        sink.failed(error.toFailureCode())
                    }
                }
            } finally {
                sessions.remove(scanId)
            }
        }
        val session = ScanSession(cancellation, sink, started, terminal, task)
        if (sessions.putIfAbsent(scanId, session) != null) {
            throw ScanException("DUPLICATE_SCAN_ID", "The scan is already active.")
        }
        executor.execute(task)
    }

    fun cancel(scanId: String) {
        val session = sessions[scanId] ?: return
        session.cancellation.cancel()
        val wasStarted = session.started.get()
        val cancelled = session.future.cancel(false)
        if (cancelled && !wasStarted && session.terminal.compareAndSet(false, true)) {
            session.sink.cancelled()
            sessions.remove(scanId, session)
        }
    }

    override fun close() {
        sessions.keys.toList().forEach(::cancel)
        executor.shutdownNow()
        sessions.clear()
    }

    private data class ScanSession(
        val cancellation: AtomicScanCancellation,
        val sink: ScanSink,
        val started: AtomicBoolean,
        val terminal: AtomicBoolean,
        val future: FutureTask<Unit>,
    )
}

private class AtomicScanCancellation : ScanCancellation {
    private val cancelled = AtomicBoolean(false)

    override val isCancelled: Boolean
        get() = cancelled.get()

    fun cancel() {
        cancelled.set(true)
    }
}

private class TerminalScanSink(
    private val delegate: ScanSink,
    private val terminal: AtomicBoolean,
) : ScanSink by delegate {
    override fun completed() {
        if (terminal.compareAndSet(false, true)) {
            delegate.completed()
        }
    }

    override fun cancelled() {
        if (terminal.compareAndSet(false, true)) {
            delegate.cancelled()
        }
    }

    override fun failed(code: String) {
        if (terminal.compareAndSet(false, true)) {
            delegate.failed(code)
        }
    }
}

private fun Exception.toFailureCode(): String = when (this) {
    is SecurityException -> "PERMISSION_REVOKED"
    is java.io.FileNotFoundException -> "FILE_UNAVAILABLE"
    is ScanException -> code
    else -> "STORAGE_OPERATION_FAILED"
}
