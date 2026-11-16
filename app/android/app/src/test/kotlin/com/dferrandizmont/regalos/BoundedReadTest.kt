package com.dferrandizmont.regalos

import java.io.ByteArrayInputStream
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test
import com.dferrandizmont.regalos.PickerOutcome.Action

/** ADR 0008: lecturas acotadas y resultado del selector al recrear la Activity. */
class BoundedReadTest {
    /** Cuenta lo que se lee de verdad: un fichero grande no se materializa. */
    private class Counting(size: Int, head: ByteArray) : InputStream() {
        private val data = ByteArray(size).also { head.copyInto(it) }
        var read = 0
            private set

        override fun read(): Int = if (read < data.size) data[read++].toInt() and 0xFF else -1

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (read >= data.size) return -1
            val n = minOf(len, data.size - read)
            data.copyInto(b, off, read, read + n)
            read += n
            return n
        }
    }

    private val ghk = byteArrayOf(0x47, 0x48, 0x4B, 1)

    @Test
    fun recoveryFileIsCutAt513BytesWithoutReadingTheRest() {
        val input = Counting(2 * 1024 * 1024, ghk)
        val bytes = BoundedRead.incoming(input)!!
        assertEquals(BoundedRead.MAX_RECOVERY_BYTES + 1, bytes.size)
        assertEquals(BoundedRead.MAX_RECOVERY_BYTES + 1, input.read)
    }

    @Test
    fun smallRecoveryFileIsReadWhole() {
        val input = Counting(200, ghk)
        assertEquals(200, BoundedRead.incoming(input)!!.size)
    }

    @Test
    fun envelopesKeepTheir2MiBLimit() {
        val rg = byteArrayOf(0x52, 0x47, 1)
        assertEquals(100_000, BoundedRead.incoming(Counting(100_000, rg))!!.size)
        assertNull(BoundedRead.incoming(Counting(BoundedRead.MAX_ENVELOPE_BYTES + 1, rg)))
    }

    @Test
    fun tinyFilesAndEmpty() {
        assertArrayEquals(byteArrayOf(0x47, 0x48), BoundedRead.incoming(ByteArrayInputStream(byteArrayOf(0x47, 0x48))))
        assertEquals(0, BoundedRead.incoming(ByteArrayInputStream(ByteArray(0)))!!.size)
    }

    @Test
    fun exactReadsAtMostMaxPlusOne() {
        assertEquals(512, BoundedRead.exact(Counting(512, ghk), 512).size)
        val big = Counting(10_000_000, ghk)
        try {
            BoundedRead.exact(big, 512)
            fail("too large")
        } catch (e: BoundedRead.TooLargeException) {
            assertEquals(513, big.read)
        }
    }

    @Test
    fun pickerOutcomeAfterRecreation() {
        assertEquals(Action.PROCESS, PickerOutcome.decide(true, null, ok = true, hasUri = true))
        assertEquals(Action.CANCELLED, PickerOutcome.decide(true, null, ok = false, hasUri = false))
        assertEquals(Action.CANCELLED, PickerOutcome.decide(true, null, ok = true, hasUri = false))
        // Recreated while saving: the created document is deleted, nothing is written.
        assertEquals(Action.DELETE_ORPHAN, PickerOutcome.decide(false, PickerOutcome.CREATE, ok = true, hasUri = true))
        assertEquals(Action.IGNORE_ORPHAN, PickerOutcome.decide(false, PickerOutcome.CREATE, ok = false, hasUri = false))
        // Recreated while opening: nothing is delivered to the new Flutter.
        assertEquals(Action.IGNORE_ORPHAN, PickerOutcome.decide(false, PickerOutcome.OPEN, ok = true, hasUri = true))
        assertEquals(Action.IGNORE_ORPHAN, PickerOutcome.decide(false, null, ok = true, hasUri = true))
    }
}

class IncomingReadGateTest {
    @Test
    fun oneReadAtATimeAndOneDeliveryEach() {
        val gate = IncomingReadGate()
        val first = gate.begin()!!
        // Another VIEW/SEND while the first is pending: refused (null delivered).
        assertNull(gate.begin())
        // The timeout fires first: it delivers; the late result does not.
        assertEquals(true, gate.end(first))
        assertEquals(false, gate.end(first))
        val second = gate.begin()!!
        // A stale result of the first read never ends the second.
        assertEquals(false, gate.end(first))
        assertEquals(true, gate.end(second))
        assertEquals(false, gate.end(second))
    }
}

class CancellableStreamTest {
    private class Probe : java.io.Closeable {
        var closed = 0
        override fun close() {
            closed++
        }
    }

    @Test
    fun aStreamPublishedAfterTheTimeoutIsClosedUnread() {
        val slot = CancellableStream<Probe>()
        assertNull(slot.cancel()) // the timeout fires while openInputStream hangs
        val late = Probe()
        assertEquals(false, slot.publish(late))
        assertEquals(1, late.closed)
    }

    @Test
    fun theTimeoutGetsAPublishedStreamToClose() {
        val slot = CancellableStream<Probe>()
        val open = Probe()
        assertEquals(true, slot.publish(open))
        assertEquals(open, slot.cancel())
        assertNull(slot.cancel())
        slot.release(open) // the reader finishing later changes nothing
        assertEquals(false, slot.publish(Probe()))
    }

    @Test
    fun aFinishedReadLeavesNothingToClose() {
        val slot = CancellableStream<Probe>()
        val open = Probe()
        assertEquals(true, slot.publish(open))
        slot.release(open)
        assertNull(slot.cancel())
        assertEquals(0, open.closed)
    }
}
