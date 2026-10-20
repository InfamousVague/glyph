package com.mattssoftware.ghost_md.wear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class WavWriterTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun le(bytes: ByteArray) = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

    @Test
    fun aTakeIsSixteenKilohertzMonoSixteenBitWithItsSizesPutRight() {
        val file = File(tmp.root, "a.wav")
        val writer = WavWriter(file)
        val second = ShortArray(16_000) { i -> (i % 200 - 100).toShort() }
        writer.write(second, second.size)
        writer.write(second, 8_000)
        assertEquals(1500L, writer.durationMs)
        writer.close()

        val bytes = file.readBytes()
        assertEquals(44 + 24_000 * 2, bytes.size)
        val h = le(bytes)
        assertEquals("RIFF", String(bytes, 0, 4, Charsets.US_ASCII))
        assertEquals(36 + 48_000, h.getInt(4))
        assertEquals("WAVE", String(bytes, 8, 4, Charsets.US_ASCII))
        assertEquals("fmt ", String(bytes, 12, 4, Charsets.US_ASCII))
        assertEquals(16, h.getInt(16))
        assertEquals(1, h.getShort(20).toInt()) // PCM
        assertEquals(1, h.getShort(22).toInt()) // mono
        assertEquals(16_000, h.getInt(24))
        assertEquals(32_000, h.getInt(28))
        assertEquals(2, h.getShort(32).toInt())
        assertEquals(16, h.getShort(34).toInt())
        assertEquals("data", String(bytes, 36, 4, Charsets.US_ASCII))
        assertEquals(48_000, h.getInt(40))
        // The samples, little-endian, as they were read.
        assertEquals(-100, h.getShort(44).toInt())
        assertEquals(-99, h.getShort(46).toInt())
    }

    @Test
    fun aFileAKillLeftWithZeroSizesIsRepairedFromItsLength() {
        val file = File(tmp.root, "killed.wav")
        // What a take's file holds mid-take: the header with its sizes at zero, the sound after it, and half a sample.
        file.writeBytes(WavWriter.header(0) + ByteArray(32_000 * 3) + byteArrayOf(7))
        assertEquals(3000L, WavWriter.repair(file))
        val bytes = file.readBytes()
        assertEquals(44 + 96_000, bytes.size)
        assertEquals(96_000, le(bytes).getInt(40))
        assertEquals(36 + 96_000, le(bytes).getInt(4))
    }

    @Test
    fun aFileThatIsNoWavIsNotRepaired() {
        val file = File(tmp.root, "junk.wav")
        file.writeBytes(ByteArray(100) { 1 })
        assertNull(WavWriter.repair(file))
        assertNull(WavWriter.repair(File(tmp.root, "missing.wav")))
    }

    @Test
    fun theLevelIsZeroForSilenceAndOneAtFullScale() {
        assertEquals(0f, Levels.of(ShortArray(160), 160))
        assertEquals(1f, Levels.of(ShortArray(160) { Short.MAX_VALUE }, 160), 0.01f)
        val quiet = Levels.of(ShortArray(160) { if (it % 2 == 0) 300 else -300 }, 160)
        assertTrue("a quiet voice is low but not nothing: $quiet", quiet in 0.1f..0.6f)
        assertEquals(0f, Levels.of(ShortArray(0), 0))
    }

    @Test
    fun theClockReadsAsAWatchDoes() {
        assertEquals("0:00", clock(0))
        assertEquals("0:42", clock(42_900))
        assertEquals("12:05", clock(725_000))
        assertEquals("1:02:09", clock(3_729_000))
    }
}
