package com.pocketcinema.app.platform

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

/** App-private selected artwork. Opaque catalog keys never become path components. */
internal class ArtworkStore(
    private val directory: File,
    private val validateImage: (ByteArray) -> Boolean,
    private val atomicReplace: (File, File) -> Unit = { source, target ->
        Files.move(source.toPath(), target.toPath(),
            StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        Unit
    },
) {
    @Synchronized
    fun save(key: String, bytes: ByteArray) {
        val destination = fileFor(key)
        require(bytes.isNotEmpty() && bytes.size <= MAXIMUM_BYTES) { "Invalid artwork size." }
        require(validateImage(bytes)) { "Invalid artwork image." }
        check(directory.isDirectory || directory.mkdirs()) { "Artwork storage is unavailable." }
        val pending = Files.createTempFile(directory.toPath(), ".pending-", ".image").toFile()
        try {
            FileOutputStream(pending).use { output ->
                output.write(bytes)
                output.fd.sync()
            }
            // A failed replacement leaves the previous image in place. Never fall back to copy/delete.
            atomicReplace(pending, destination)
        } finally {
            pending.delete()
        }
    }

    @Synchronized
    fun read(key: String): ByteArray? {
        val source = fileFor(key)
        if (!source.exists()) return null
        require(source.length() in 1..MAXIMUM_BYTES.toLong()) { "Invalid artwork size." }
        val bytes = source.inputStream().use { input ->
            ByteArrayOutputStream().use { output ->
                val buffer = ByteArray(16 * 1024)
                var count = input.read(buffer)
                while (count != -1) {
                    require(output.size() + count <= MAXIMUM_BYTES) { "Invalid artwork size." }
                    output.write(buffer, 0, count)
                    count = input.read(buffer)
                }
                output.toByteArray()
            }
        }
        require(bytes.isNotEmpty() && validateImage(bytes)) { "Invalid saved artwork image." }
        return bytes
    }

    @Synchronized
    fun delete(key: String) {
        Files.deleteIfExists(fileFor(key).toPath())
    }

    private fun fileFor(key: String): File {
        require(key.isNotBlank() && key.length <= 16_384) { "Invalid artwork identifier." }
        val digest = MessageDigest.getInstance("SHA-256").digest(key.toByteArray(Charsets.UTF_8))
        val name = digest.joinToString("") { "%02x".format(it.toInt() and 0xff) }
        return File(directory, "$name.image")
    }

    companion object {
        const val MAXIMUM_BYTES = 8 * 1024 * 1024
    }
}
