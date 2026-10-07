package com.tidyreel.local_media_hub.platform

import android.content.ContentResolver
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.FileNotFoundException

class AndroidProbeBackend(
    private val contentResolver: ContentResolver,
) : ProbeBackend {
    private var descriptor: ParcelFileDescriptor? = null
    private var retriever: MediaMetadataRetriever? = null
    private var extractor: MediaExtractor? = null

    override fun readRetrieverMetadata(documentUri: String): RetrieverData {
        val mediaRetriever = MediaMetadataRetriever().also { retriever = it }
        mediaRetriever.setDataSource(fileDescriptor(documentUri).fileDescriptor)
        return RetrieverData(
            durationMs = mediaRetriever.metadataLong(
                MediaMetadataRetriever.METADATA_KEY_DURATION,
            ),
            width = mediaRetriever.metadataLong(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH,
            ),
            height = mediaRetriever.metadataLong(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT,
            ),
            rotation = mediaRetriever.metadataLong(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
            ),
            containerMime = mediaRetriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_MIMETYPE,
            ),
        )
    }

    override fun readTracks(documentUri: String): List<TrackData> {
        val mediaExtractor = MediaExtractor().also { extractor = it }
        mediaExtractor.setDataSource(fileDescriptor(documentUri).fileDescriptor)
        return (0 until mediaExtractor.trackCount).map { index ->
            mediaExtractor.getTrackFormat(index).toTrackData()
        }
    }

    override fun close() {
        extractor?.release()
        extractor = null
        retriever?.release()
        retriever = null
        descriptor?.close()
        descriptor = null
    }

    private fun fileDescriptor(documentUri: String): ParcelFileDescriptor {
        descriptor?.let { current -> return current }
        return contentResolver.openFileDescriptor(Uri.parse(documentUri), "r")
            ?.also { opened -> descriptor = opened }
            ?: throw FileNotFoundException("The selected media file is unavailable.")
    }
}

private fun MediaMetadataRetriever.metadataLong(key: Int): Long? =
    extractMetadata(key)?.toLongOrNull()

private fun MediaFormat.toTrackData(): TrackData {
    val mime = stringOrNull(MediaFormat.KEY_MIME)
    val type = when {
        mime?.startsWith("video/") == true -> "video"
        mime?.startsWith("audio/") == true -> "audio"
        mime?.startsWith("text/") == true ||
            mime?.startsWith("application/") == true -> "subtitle"
        else -> "unknown"
    }
    return TrackData(
        type = type,
        mime = mime,
        language = stringOrNull(MediaFormat.KEY_LANGUAGE),
        channelCount = longOrNull(MediaFormat.KEY_CHANNEL_COUNT),
        sampleRate = longOrNull(MediaFormat.KEY_SAMPLE_RATE),
    )
}

private fun MediaFormat.stringOrNull(key: String): String? =
    if (containsKey(key)) getString(key) else null

private fun MediaFormat.longOrNull(key: String): Long? =
    if (containsKey(key)) getInteger(key).toLong() else null
