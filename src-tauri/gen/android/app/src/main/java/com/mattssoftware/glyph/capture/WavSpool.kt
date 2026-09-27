package com.mattssoftware.glyph.capture

import java.io.File
import java.io.RandomAccessFile

/**
 * The meeting's WAV, written as the microphone is read.
 *
 * The header is the one src-tauri/src/whisper/wav.rs `header` writes, byte for
 * byte: `RIFF`, the file size less eight, `WAVE`, a sixteen-byte `fmt ` chunk
 * (PCM, one channel, 16 kHz, 32 000 bytes a second, block align two, sixteen
 * bits), then `data` and its length. Nothing else, because `wav::ours` only
 * recognises that layout and a later Add to the tape refuses to append to
 * anything it does not recognise.
 *
 * The two lengths are patched every ten seconds and at close, so a kill leaves
 * a file whose header is at most ten seconds short. Rust reads such a file to
 * its end (`wav::data_end`: `data` as the last chunk runs to the end of the
 * file), so nothing recorded is lost, only the number on the label.
 */
internal object WavSpool {
  const val SAMPLE_RATE = 16_000
  const val HEADER_LEN = 44
  /** How often the header's lengths are brought up to date while recording. */
  const val PATCH_EVERY_MS = 10_000L

  /** The header for `dataLen` bytes of samples. */
  fun header(dataLen: Long): ByteArray {
    val out = ByteArray(HEADER_LEN)
    ascii(out, 0, "RIFF")
    le32(out, 4, HEADER_LEN - 8 + dataLen)
    ascii(out, 8, "WAVE")
    ascii(out, 12, "fmt ")
    le32(out, 16, 16)
    le16(out, 20, 1) // PCM
    le16(out, 22, 1) // mono
    le32(out, 24, SAMPLE_RATE.toLong())
    le32(out, 28, SAMPLE_RATE.toLong() * 2)
    le16(out, 32, 2)
    le16(out, 34, 16)
    ascii(out, 36, "data")
    le32(out, 40, dataLen)
    return out
  }

  /** Opens `file` afresh (an old file under the id is replaced, never appended to) with an empty header. */
  fun open(file: File): RandomAccessFile {
    file.parentFile?.mkdirs()
    val out = RandomAccessFile(file, "rw")
    out.setLength(0)
    out.write(header(0))
    return out
  }

  /** Writes the two lengths for `dataLen` bytes of samples and puts the position back at the end. */
  fun patch(out: RandomAccessFile, dataLen: Long) {
    val size = ByteArray(4)
    le32(size, 0, HEADER_LEN - 8 + dataLen)
    out.seek(4)
    out.write(size)
    le32(size, 0, dataLen)
    out.seek(40)
    out.write(size)
    out.seek(HEADER_LEN + dataLen)
  }

  /** `bytes` of PCM16 mono at 16 kHz, as a length in milliseconds. */
  fun durationMs(dataLen: Long): Long = dataLen * 1000 / (SAMPLE_RATE * 2)

  private fun ascii(out: ByteArray, at: Int, word: String) {
    for (i in word.indices) out[at + i] = word[i].code.toByte()
  }

  private fun le32(out: ByteArray, at: Int, value: Long) {
    for (i in 0 until 4) out[at + i] = ((value shr (8 * i)) and 0xff).toByte()
  }

  private fun le16(out: ByteArray, at: Int, value: Int) {
    out[at] = (value and 0xff).toByte()
    out[at + 1] = ((value shr 8) and 0xff).toByte()
  }
}
