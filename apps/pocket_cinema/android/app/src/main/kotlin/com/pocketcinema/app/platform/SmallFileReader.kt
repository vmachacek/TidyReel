package com.pocketcinema.app.platform

import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream

class SmallFileException(
    val code: String,
    safeMessage: String,
) : RuntimeException(safeMessage)

class SmallFileReader(
    private val openInput: (String) -> InputStream,
) {
    fun read(documentUri: String, maximumBytes: Int): ByteArray {
        require(maximumBytes > 0) { "Maximum bytes must be positive." }
        return try {
            openInput(documentUri).use { input ->
                val output = ByteArrayOutputStream(minOf(maximumBytes, 8192))
                val buffer = ByteArray(8192)
                var total = 0
                while (total <= maximumBytes) {
                    val remaining = maximumBytes + 1 - total
                    val count = input.read(buffer, 0, minOf(buffer.size, remaining))
                    if (count < 0) {
                        break
                    }
                    output.write(buffer, 0, count)
                    total += count
                }
                if (total > maximumBytes) {
                    throw SmallFileException(
                        "FILE_TOO_LARGE",
                        "The sidecar exceeds the configured limit.",
                    )
                }
                output.toByteArray()
            }
        } catch (error: SmallFileException) {
            throw error
        } catch (_: FileNotFoundException) {
            throw SmallFileException(
                "FILE_UNAVAILABLE",
                "The requested sidecar is unavailable.",
            )
        } catch (_: SecurityException) {
            throw SmallFileException(
                "PERMISSION_REVOKED",
                "Read access to the sidecar is unavailable.",
            )
        } catch (_: IOException) {
            throw SmallFileException(
                "FILE_UNAVAILABLE",
                "The requested sidecar could not be read.",
            )
        }
    }
}
