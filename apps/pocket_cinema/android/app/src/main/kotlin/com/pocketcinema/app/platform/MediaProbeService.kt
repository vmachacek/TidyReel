package com.pocketcinema.app.platform

import java.io.FileNotFoundException
import java.io.IOException

class ProbeException(
    val code: String,
    safeMessage: String,
) : RuntimeException(safeMessage)

class MediaProbeService(
    private val backendFactory: () -> ProbeBackend,
) {
    fun probe(documentUri: String): ProbeResultMessage {
        val backend = backendFactory()
        return try {
            val retriever = backend.readRetrieverMetadata(documentUri)
            val tracks = backend.readTracks(documentUri)
            ProbeResultMessage(
                durationMs = retriever.durationMs,
                containerFormat = retriever.containerMime,
                width = retriever.width,
                height = retriever.height,
                rotationDegrees = retriever.rotation,
                videoCodec = tracks.firstOrNull { track ->
                    track.type == "video"
                }?.mime,
                audioCodecSummary = tracks
                    .filter { track -> track.type == "audio" }
                    .mapNotNull { track -> track.mime }
                    .distinct()
                    .joinToString(", ")
                    .ifEmpty { null },
                streamCount = tracks.size.toLong(),
            )
        } catch (_: IllegalArgumentException) {
            throw ProbeException(
                "UNSUPPORTED_PROBE_FORMAT",
                "The selected media format is unsupported.",
            )
        } catch (_: FileNotFoundException) {
            throw ProbeException(
                "FILE_UNAVAILABLE",
                "The selected media file is unavailable.",
            )
        } catch (_: SecurityException) {
            throw ProbeException(
                "PERMISSION_REVOKED",
                "Read access to the selected media file is unavailable.",
            )
        } catch (_: IOException) {
            throw ProbeException(
                "PROBE_FAILED",
                "The selected media file could not be inspected.",
            )
        } catch (error: ProbeException) {
            throw error
        } catch (_: Exception) {
            throw ProbeException(
                "PROBE_FAILED",
                "The selected media file could not be inspected.",
            )
        } finally {
            backend.close()
        }
    }
}
