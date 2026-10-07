package com.pocketcinema.app.platform

import java.io.File
import java.io.IOException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ArtworkStoreTest {
    @get:Rule
    val temporary = TemporaryFolder()

    private fun store(directory: File, validator: (ByteArray) -> Boolean = { true }) =
        ArtworkStore(directory, validator)

    @Test
    fun `selected image survives reopening and deletion restores missing state`() {
        val directory = File(temporary.root, "private_artwork")
        val first = store(directory)
        assertNull(first.read("show:poster"))
        first.save("show:poster", byteArrayOf(1, 2, 3))

        val reopened = store(directory)
        assertArrayEquals(byteArrayOf(1, 2, 3), reopened.read("show:poster"))
        reopened.save("show:poster", byteArrayOf(4, 5))
        assertArrayEquals(byteArrayOf(4, 5), store(directory).read("show:poster"))
        reopened.delete("show:poster")
        reopened.delete("show:poster")
        assertNull(reopened.read("show:poster"))
    }

    @Test
    fun `opaque keys cannot escape private directory and keep artwork kinds separate`() {
        val directory = File(temporary.root, "private_artwork")
        val artwork = store(directory)
        val posterKey = "[content://tree/../movie, ../../show, poster]"
        val backdropKey = "[content://tree/../movie, ../../show, backdrop]"
        artwork.save(posterKey, byteArrayOf(1))
        artwork.save(backdropKey, byteArrayOf(2))

        assertArrayEquals(byteArrayOf(1), artwork.read(posterKey))
        assertArrayEquals(byteArrayOf(2), artwork.read(backdropKey))
        assertEquals(2, directory.listFiles()!!.size)
        directory.listFiles()!!.forEach {
            assertEquals(directory.canonicalPath, it.parentFile!!.canonicalPath)
            assertEquals(70, it.name.length)
            assertFalse(it.name.contains("show"))
        }
    }

    @Test
    fun `invalid image and oversized replacements preserve selected image`() {
        val directory = File(temporary.root, "private_artwork")
        val artwork = store(directory) { it.firstOrNull() == 1.toByte() }
        artwork.save("show:poster", byteArrayOf(1, 2))

        assertThrows(IllegalArgumentException::class.java) {
            artwork.save("show:poster", byteArrayOf(2, 3))
        }
        assertThrows(IllegalArgumentException::class.java) {
            artwork.save("show:poster", ByteArray(ArtworkStore.MAXIMUM_BYTES + 1) { 1 })
        }
        assertThrows(IllegalArgumentException::class.java) {
            artwork.save("show:poster", byteArrayOf())
        }
        assertArrayEquals(byteArrayOf(1, 2), artwork.read("show:poster"))
        assertEquals(1, directory.listFiles()!!.size)
    }

    @Test
    fun `failed atomic replacement preserves old file and removes pending file`() {
        val directory = File(temporary.root, "private_artwork")
        store(directory).save("show:poster", byteArrayOf(1, 2))
        val failing = ArtworkStore(directory, { true }) { _, _ -> throw IOException("Write failed") }

        assertThrows(IOException::class.java) {
            failing.save("show:poster", byteArrayOf(3, 4))
        }
        assertArrayEquals(byteArrayOf(1, 2), store(directory).read("show:poster"))
        assertEquals(1, directory.listFiles()!!.size)
    }

    @Test
    fun `invalid saved files are rejected before they reach Dart`() {
        val directory = File(temporary.root, "private_artwork")
        val artwork = store(directory)
        artwork.save("show:poster", byteArrayOf(1))
        directory.listFiles()!!.single().writeBytes(byteArrayOf(2))
        val validating = store(directory) { it.firstOrNull() == 1.toByte() }
        assertThrows(IllegalArgumentException::class.java) { validating.read("show:poster") }
        directory.listFiles()!!.single().writeBytes(ByteArray(ArtworkStore.MAXIMUM_BYTES + 1))
        assertThrows(IllegalArgumentException::class.java) { artwork.read("show:poster") }
    }
}
