package com.mattssoftware.glyph.capture

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.tanh
import kotlin.math.withSign

/**
 * Other apps' sound mixed into the meeting's microphone, sample by sample,
 * before WavSpool writes it (docs/DESIGN.md "Meetings with the computer's
 * sound"; Matt: "listen to the microphone and system audio so that we can
 * record meetings with raw audio").
 *
 * The same mix as the Mac's (src-tauri/src/system_audio.rs `Mixer`), because
 * the tape is the same tape: one 16 kHz mono PCM16 stream, the room and the
 * other apps summed, so whisper/wav.rs, the write-up's `read_span` and
 * WavSpool's header need nothing new. Kept apart from OtherApps.kt so the JVM
 * tests can run it with no Android under them (SoundMixTest.kt).
 *
 * Two readers, two clocks: the microphone's AudioRecord and the playback
 * capture's. The capture's reader puts its samples in a short ring; each
 * microphone read takes as many as it has samples and adds them in. A read that
 * finds the ring short leaves the rest of itself microphone-only, and the ring
 * is fuller for the next, so it settles at the jitter between the two; a ring
 * that grows past a second drops its oldest, so other apps are never heard more
 * than a second late.
 */
internal object SoundMix {
  /** The most other apps' sound may run behind the microphone: a second of it. */
  const val MOST_BEHIND = WavSpool.SAMPLE_RATE

  /** Below this the sum is passed straight through, the raw audio Matt asked for. */
  private const val KNEE = 0.8f

  /** Above this a sample is heard: about -80 dBFS in PCM16, above a muted app's zeros. */
  const val HEARD_ABOVE = 3

  /** The sum kept inside full scale: unchanged to the knee, then bent smoothly rather than clipped flat. */
  fun softClip(x: Float): Float {
    val size = abs(x)
    if (size <= KNEE) return x
    val room = 1f - KNEE
    return (KNEE + room * tanh((size - KNEE) / room)).withSign(x)
  }

  /**
   * `length` bytes of little-endian PCM16 microphone in `buffer`, with as much
   * of `ring` as has arrived added in, in place. Answers how many samples of
   * other apps' sound went in.
   */
  fun mixInto(buffer: ByteArray, length: Int, ring: SoundRing, scratch: ShortArray): Int {
    val samples = length / 2
    val taken = ring.take(scratch, minOf(samples, scratch.size))
    for (i in 0 until taken) {
      val low = buffer[2 * i].toInt() and 0xff
      val high = buffer[2 * i + 1].toInt()
      val mic = ((high shl 8) or low).toShort()
      val sum = softClip((mic + scratch[i]) / 32768f)
      val out = (sum * 32767f).toInt().coerceIn(-32768, 32767)
      buffer[2 * i] = (out and 0xff).toByte()
      buffer[2 * i + 1] = ((out shr 8) and 0xff).toByte()
    }
    return taken
  }
}

/**
 * The ring between the playback capture's reader and the microphone's: PCM16
 * at 16 kHz mono, at most `capacity` of it, the oldest dropped past that. One
 * lock, held for a copy of a read's worth on each side.
 */
internal class SoundRing(private val capacity: Int = SoundMix.MOST_BEHIND) {
  private val samples = ShortArray(capacity)
  private var start = 0
  private var size = 0

  @Synchronized
  fun waiting(): Int = size

  @Synchronized
  fun clear() {
    start = 0
    size = 0
  }

  /** `count` samples from `from`, after what is waiting. */
  @Synchronized
  fun put(from: ShortArray, count: Int) {
    for (i in 0 until count) {
      if (size == capacity) {
        start = (start + 1) % capacity
        size--
      }
      samples[(start + size) % capacity] = from[i]
      size++
    }
  }

  /** Up to `most` of the oldest samples into `into`; how many there were. */
  @Synchronized
  fun take(into: ShortArray, most: Int): Int {
    val count = minOf(most, size, into.size)
    for (i in 0 until count) into[i] = samples[(start + i) % capacity]
    start = (start + count) % capacity
    size -= count
    return count
  }
}

/**
 * Down to 16 kHz mono, for a phone whose playback capture will not open at the
 * meeting's own rate: the channels averaged, then each output sample the mean
 * of the input samples its window covers. The page's resampler
 * (capture/audio.ts `createResampler`) and Rust's (system_audio.rs `Resampler`),
 * a third time: a box average is a crude low-pass, but it is the one decimation
 * needs, and Whisper was trained on far rougher audio. Its position carries
 * across reads, so a read boundary never clicks.
 */
internal class BoxResampler(fromRate: Int, private val channels: Int, toRate: Int = WavSpool.SAMPLE_RATE) {
  private val step = fromRate.toDouble() / toRate
  private var carry = FloatArray(0)
  private var position = 0.0

  /** `frames` interleaved frames from `input` (`channels` samples each), resampled, into `out`; how many were written. */
  fun process(input: ShortArray, frames: Int, out: ShortArray): Int {
    val mono = FloatArray(carry.size + frames)
    carry.copyInto(mono)
    val share = 1f / channels
    for (f in 0 until frames) {
      var sum = 0f
      for (c in 0 until channels) sum += input[f * channels + c]
      mono[carry.size + f] = sum * share
    }
    var written = 0
    while (position + step <= mono.size && written < out.size) {
      val first = floor(position).toInt()
      val end = floor(position + step).toInt()
      val value = if (end <= first) {
        mono[first]
      } else {
        var sum = 0f
        for (i in first until end) sum += mono[i]
        sum / (end - first)
      }
      out[written++] = value.toInt().coerceIn(-32768, 32767).toShort()
      position += step
    }
    val consumed = minOf(floor(position).toInt(), mono.size)
    carry = mono.copyOfRange(consumed, mono.size)
    position -= consumed
    return written
  }
}
