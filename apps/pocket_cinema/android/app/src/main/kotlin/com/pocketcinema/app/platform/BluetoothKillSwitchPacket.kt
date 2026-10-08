package com.pocketcinema.app.platform

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Ten bytes leave room for a 128-bit service-data UUID in a legacy BLE advert. */
data class BluetoothKillSwitchPacket(val active: Boolean, val session: Long, val revision: Long) {
    val sender: String get() = session.toString(16).padStart(8, '0')

    fun encode(): ByteArray {
        require(session in 0..MAX_UNSIGNED_INT && revision in 0..MAX_UNSIGNED_INT)
        return ByteBuffer.allocate(SIZE).order(ByteOrder.BIG_ENDIAN)
            .put(VERSION.toByte())
            .put(if (active) 1.toByte() else 0.toByte())
            .putInt(session.toInt())
            .putInt(revision.toInt())
            .array()
    }

    companion object {
        const val SIZE = 10
        const val VERSION = 1
        const val MAX_UNSIGNED_INT = 0xffff_ffffL

        fun decode(bytes: ByteArray): BluetoothKillSwitchPacket? {
            if (bytes.size != SIZE || bytes[0].toInt() != VERSION || bytes[1].toInt() !in 0..1) return null
            val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
            buffer.position(2)
            return BluetoothKillSwitchPacket(
                bytes[1].toInt() == 1,
                buffer.int.toLong() and MAX_UNSIGNED_INT,
                buffer.int.toLong() and MAX_UNSIGNED_INT,
            )
        }
    }
}
