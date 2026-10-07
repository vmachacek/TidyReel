package com.tidyreel.local_media_hub.platform

import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class SmallFileReaderTest {
    @Test
    fun `small file reader rejects content above limit and closes stream`() {
        val stream = RecordingInputStream(ByteArray(9) { 1 })

        val failure = assertThrows(SmallFileException::class.java) {
            SmallFileReader { stream }.read(
                "content://subtitle",
                maximumBytes = 8,
            )
        }

        assertEquals("FILE_TOO_LARGE", failure.code)
        assertEquals(1, stream.closeCount)
    }
}

private class RecordingInputStream(bytes: ByteArray) :
    ByteArrayInputStream(bytes) {
    var closeCount: Int = 0

    override fun close() {
        closeCount += 1
        super.close()
    }
}
