package com.mattssoftware.glyph.capture

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.io.RandomAccessFile

/**
 * The spooled WAV's header is the one src-tauri/src/whisper/wav.rs writes:
 * `wav::ours` recognises exactly that layout and nothing else, so these bytes
 * are pinned here as they are pinned there.
 */
class WavSpoolTest {
  @Test
  fun the_header_is_the_canonical_44_bytes() {
    val header = WavSpool.header(1_000)
    assertEquals(44, header.size)
    assertEquals("RIFF", String(header, 0, 4, Charsets.US_ASCII))
    assertEquals(36 + 1_000L, le32(header, 4))
    assertEquals("WAVE", String(header, 8, 4, Charsets.US_ASCII))
    assertEquals("fmt ", String(header, 12, 4, Charsets.US_ASCII))
    assertEquals(16L, le32(header, 16))
    assertEquals(1, le16(header, 20)) // PCM
    assertEquals(1, le16(header, 22)) // mono
    assertEquals(16_000L, le32(header, 24))
    assertEquals(32_000L, le32(header, 28))
    assertEquals(2, le16(header, 32))
    assertEquals(16, le16(header, 34))
    assertEquals("data", String(header, 36, 4, Charsets.US_ASCII))
    assertEquals(1_000L, le32(header, 40))
  }

  @Test
  fun a_patch_rewrites_the_two_lengths_and_nothing_else() {
    val file = File.createTempFile("glyph-spool", ".wav")
    try {
      val out = WavSpool.open(file)
      val samples = ByteArray(320) { (it % 7).toByte() }
      out.write(samples)
      WavSpool.patch(out, samples.size.toLong())
      // The position is back at the end, so the next write goes after the samples, not over them.
      out.write(byteArrayOf(9, 9))
      out.close()
      val bytes = file.readBytes()
      assertEquals(44 + 320 + 2, bytes.size)
      assertArrayEquals(WavSpool.header(320), bytes.copyOfRange(0, 44))
      assertArrayEquals(samples, bytes.copyOfRange(44, 44 + 320))
      assertEquals(9, bytes[44 + 320].toInt())
    } finally {
      file.delete()
    }
  }

  @Test
  fun opening_replaces_what_was_under_the_id() {
    val file = File.createTempFile("glyph-spool", ".wav")
    try {
      RandomAccessFile(file, "rw").use { it.write(ByteArray(500)) }
      WavSpool.open(file).close()
      assertEquals(44L, file.length())
    } finally {
      file.delete()
    }
  }

  @Test
  fun a_length_in_bytes_is_a_duration_at_16_khz_mono() {
    assertEquals(0L, WavSpool.durationMs(0))
    assertEquals(1_000L, WavSpool.durationMs(32_000))
    assertEquals(3_600_000L, WavSpool.durationMs(32_000L * 3_600))
  }

  private fun le32(bytes: ByteArray, at: Int): Long =
    (0 until 4).fold(0L) { acc, i -> acc or ((bytes[at + i].toLong() and 0xff) shl (8 * i)) }

  private fun le16(bytes: ByteArray, at: Int): Int =
    (bytes[at].toInt() and 0xff) or ((bytes[at + 1].toInt() and 0xff) shl 8)
}
