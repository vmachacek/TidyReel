package com.pocketcinema.app.platform

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class BluetoothKillSwitchPacketTest {
    @Test fun onAndOffRoundTripUnsignedSessionsAndRevisions() {
        for (active in listOf(false, true)) {
            for (session in listOf(0L, 1L, 0x8000_0000L, 0xffff_ffffL)) {
                for (revision in listOf(0L, 1L, 0x8000_0000L, 0xffff_ffffL)) {
                    val packet = BluetoothKillSwitchPacket(active, session, revision)
                    assertEquals(packet, BluetoothKillSwitchPacket.decode(packet.encode()))
                    assertEquals(8, packet.sender.length)
                }
            }
        }
    }

    @Test fun networkByteOrderAndLegacyAdvertisementBudgetAreStable() {
        val packet = BluetoothKillSwitchPacket(true, 0x1234_abcdL, 0x0102_0304L)
        assertArrayEquals(byteArrayOf(1, 1, 0x12, 0x34, 0xab.toByte(), 0xcd.toByte(), 1, 2, 3, 4), packet.encode())
        assertEquals("1234abcd", packet.sender)
        // 16 UUID bytes + length/type + 3 Bluetooth flag bytes = 31 maximum.
        assertEquals(31, packet.encode().size + 18 + 3)
    }

    @Test fun unknownVersionsAndInvalidFlagsOrSizesAreIgnored() {
        val valid = BluetoothKillSwitchPacket(true, 42, 8).encode()
        for (size in listOf(0, 1, 9, 11, 31)) assertNull(BluetoothKillSwitchPacket.decode(ByteArray(size)))
        assertNull(BluetoothKillSwitchPacket.decode(valid.copyOf().apply { this[0] = 2 }))
        assertNull(BluetoothKillSwitchPacket.decode(valid.copyOf().apply { this[1] = 2 }))
        assertNull(BluetoothKillSwitchPacket.decode(valid.copyOf().apply { this[1] = (-1).toByte() }))
    }

    @Test fun invalidUnsignedFieldsCannotBeTruncatedIntoAnotherCommand() {
        for (packet in listOf(
            BluetoothKillSwitchPacket(true, -1, 0),
            BluetoothKillSwitchPacket(true, 0x1_0000_0000L, 0),
            BluetoothKillSwitchPacket(false, 0, -1),
            BluetoothKillSwitchPacket(false, 0, 0x1_0000_0000L),
        )) {
            try { packet.encode(); fail("Invalid field was silently truncated.") }
            catch (_: IllegalArgumentException) { }
        }
    }
}
