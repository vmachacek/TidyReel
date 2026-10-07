package com.pocketcinema.app.platform

data class RetrieverData(
    val durationMs: Long? = null,
    val width: Long? = null,
    val height: Long? = null,
    val rotation: Long? = null,
    val containerMime: String? = null,
)

data class TrackData(
    val type: String,
    val mime: String? = null,
    val language: String? = null,
    val channelCount: Long? = null,
    val sampleRate: Long? = null,
)

interface ProbeBackend : AutoCloseable {
    fun readRetrieverMetadata(documentUri: String): RetrieverData

    fun readTracks(documentUri: String): List<TrackData>
}
