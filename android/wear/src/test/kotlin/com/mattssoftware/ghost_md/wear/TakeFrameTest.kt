package com.mattssoftware.ghost_md.wear

import com.mattssoftware.ghost_md.watchlink.TakeFrame
import com.mattssoftware.ghost_md.watchlink.TakeMeta
import com.mattssoftware.ghost_md.watchlink.WatchLink
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.IOException

/** The frame as the watch writes it is the frame the phone reads, and the WAV follows it untouched. */
class TakeFrameTest {
    @Test
    fun theHeaderAndTheSoundCrossTogether() {
        val wav = WavWriter.header(4) + byteArrayOf(1, 2, 3, 4)
        val meta = TakeMeta(id = "6f1c-aa_9", recordedAt = 1_760_000_000_000, durationMs = 4200, watch = "Galaxy Watch9 (4XZ1)", bytes = wav.size.toLong())
        val out = ByteArrayOutputStream()
        TakeFrame.write(out, meta)
        out.write(wav)

        val input = ByteArrayInputStream(out.toByteArray())
        assertEquals(meta, TakeFrame.read(input))
        assertArrayEquals(wav, input.readBytes())
    }

    @Test
    fun aLongWatchNameIsCutAndAnythingElseIsRefused() {
        val out = ByteArrayOutputStream()
        TakeFrame.write(out, TakeMeta("a", 1, 1, "x".repeat(200), 44))
        assertEquals(64, TakeFrame.read(ByteArrayInputStream(out.toByteArray())).watch.length)

        fun refused(bytes: ByteArray) = try {
            TakeFrame.read(ByteArrayInputStream(bytes))
            fail("read a frame it should have refused")
        } catch (_: IOException) {
        }
        refused("RIFF....".toByteArray())
        refused(ByteArray(0))
        // An id that would name a file elsewhere.
        val sneaky = ByteArrayOutputStream()
        DataOutputStream(sneaky).apply { writeInt(0x47484D57); writeInt(1); writeUTF("../library"); writeLong(1); writeLong(1); writeUTF("w"); writeLong(44) }
        refused(sneaky.toByteArray())
        // More sound than an hour's take.
        val huge = ByteArrayOutputStream()
        TakeFrame.write(huge, TakeMeta("a", 1, 1, "w", WatchLink.MAX_TAKE_BYTES + 1))
        refused(huge.toByteArray())
    }

    @Test
    fun anIdIsOnlyWhatCanNameAFile() {
        assertTrue(WatchLink.plainId("0b8e2c1e-5d0a-4f43-9d1e-6a7f8c9d0e1f"))
        assertFalse(WatchLink.plainId(""))
        assertFalse(WatchLink.plainId("a/b"))
        assertFalse(WatchLink.plainId("a.wav"))
        assertFalse(WatchLink.plainId("x".repeat(65)))
    }
}
