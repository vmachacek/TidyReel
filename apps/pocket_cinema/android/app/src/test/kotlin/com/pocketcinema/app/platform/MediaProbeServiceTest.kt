package com.pocketcinema.app.platform

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MediaProbeServiceTest {
    @Test
    fun `maps nullable metadata and always closes backend`() {
        val backend = FakeProbeBackend(
            retriever = RetrieverData(
                durationMs = 90_000,
                width = null,
                height = null,
                rotation = 90,
                containerMime = "video/mp4",
            ),
            tracks = listOf(
                TrackData(type = "video", mime = "video/hevc"),
                TrackData(type = "audio", mime = "audio/eac3", language = "en"),
            ),
        )

        val result = MediaProbeService { backend }.probe("content://document")

        assertEquals(90_000L, result.durationMs)
        assertEquals("video/mp4", result.containerFormat)
        assertEquals("video/hevc", result.videoCodec)
        assertEquals("audio/eac3", result.audioCodecSummary)
        assertEquals(2L, result.streamCount)
        assertEquals(1, backend.closeCount)
    }

    @Test
    fun `backend failure closes once and returns probe failed`() {
        val backend = FakeProbeBackend(failure = IOException("private uri"))

        val failure = assertThrows(ProbeException::class.java) {
            MediaProbeService { backend }.probe("content://document")
        }

        assertEquals("PROBE_FAILED", failure.code)
        assertEquals(1, backend.closeCount)
    }
}

private class FakeProbeBackend(
    private val retriever: RetrieverData = RetrieverData(),
    private val tracks: List<TrackData> = emptyList(),
    private val failure: Exception? = null,
) : ProbeBackend {
    var closeCount = 0

    override fun readRetrieverMetadata(documentUri: String): RetrieverData {
        failure?.let { error -> throw error }
        return retriever
    }

    override fun readTracks(documentUri: String): List<TrackData> {
        failure?.let { error -> throw error }
        return tracks
    }

    override fun close() {
        closeCount += 1
    }
}
