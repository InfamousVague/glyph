package com.mattssoftware.glyph.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Other apps' sound into the microphone's bytes (SoundMix.kt): the same mix the
 * Mac's tests pin in src-tauri/src/system_audio.rs, with synthetic buffers.
 */
class SoundMixTest {
  private fun pcm(vararg samples: Int): ByteArray {
    val out = ByteArray(samples.size * 2)
    samples.forEachIndexed { i, s ->
      out[2 * i] = (s and 0xff).toByte()
      out[2 * i + 1] = ((s shr 8) and 0xff).toByte()
    }
    return out
  }

  private fun sample(bytes: ByteArray, i: Int): Int = ((bytes[2 * i + 1].toInt() shl 8) or (bytes[2 * i].toInt() and 0xff)).toShort().toInt()

  @Test
  fun the_quiet_sum_is_the_plain_sum() {
    val ring = SoundRing()
    ring.put(shortArrayOf(1_000, -2_000, 3_000), 3)
    val mic = pcm(500, 500, -500, 700)
    val taken = SoundMix.mixInto(mic, mic.size, ring, ShortArray(4))
    assertEquals(3, taken)
    // Within one step of PCM16 for the float round trip; the fourth sample had nothing to take.
    assertTrue(abs(sample(mic, 0) - 1_500) <= 1)
    assertTrue(abs(sample(mic, 1) - -1_500) <= 1)
    assertTrue(abs(sample(mic, 2) - 2_500) <= 1)
    assertEquals(700, sample(mic, 3))
    assertEquals(0, ring.waiting())
  }

  @Test
  fun a_loud_sum_stays_inside_full_scale() {
    val ring = SoundRing()
    ring.put(shortArrayOf(30_000, -30_000), 2)
    val mic = pcm(30_000, -30_000)
    SoundMix.mixInto(mic, mic.size, ring, ShortArray(2))
    assertTrue(sample(mic, 0) in 31_000..32_767)
    assertTrue(sample(mic, 1) in -32_768..-31_000)
  }

  @Test
  fun the_ring_keeps_only_the_newest_second() {
    val ring = SoundRing(capacity = 4)
    ring.put(shortArrayOf(1, 2, 3, 4, 5, 6), 6)
    assertEquals(4, ring.waiting())
    val out = ShortArray(8)
    assertEquals(4, ring.take(out, 8))
    assertEquals(listOf<Short>(3, 4, 5, 6), out.take(4))
    assertEquals(0, ring.take(out, 8))
  }

  @Test
  fun a_short_ring_leaves_the_rest_of_the_read_to_the_microphone() {
    val ring = SoundRing()
    ring.put(ShortArray(100) { 1_000 }, 100)
    val mic = pcm(*IntArray(300))
    assertEquals(100, SoundMix.mixInto(mic, mic.size, ring, ShortArray(300)))
    assertTrue((0 until 100).all { abs(sample(mic, it) - 1_000) <= 1 })
    assertTrue((100 until 300).all { sample(mic, it) == 0 })
  }

  @Test
  fun forty_eight_kilohertz_stereo_comes_out_sixteen_mono_at_its_level() {
    // One second of a 440 Hz tone, the same on both channels, read in odd sizes.
    val rate = 48_000
    val stereo = ShortArray(rate * 2) { i -> (10_000 * sin(2 * PI * 440 * (i / 2) / rate)).toInt().toShort() }
    val resampler = BoxResampler(rate, 2)
    val whole = ArrayList<Short>()
    var at = 0
    val sizes = intArrayOf(480, 1_023, 7, 960)
    var turn = 0
    val piece = ShortArray(2 * 1_024)
    val out = ShortArray(1_024)
    while (at < rate) {
      val frames = minOf(sizes[turn++ % sizes.size], rate - at)
      stereo.copyInto(piece, 0, at * 2, (at + frames) * 2)
      val n = resampler.process(piece, frames, out)
      for (i in 0 until n) whole.add(out[i])
      at += frames
    }
    assertEquals(16_000, whole.size)
    // Every third input frame's neighbourhood: the level of the tone survives the trip.
    val outRms = sqrt(whole.map { it.toDouble() * it }.average())
    assertTrue("$outRms", abs(outRms - 10_000 / sqrt(2.0)) < 300)
  }

  @Test
  fun the_resampler_keeps_a_tones_level() {
    val rate = 48_000
    val mono = ShortArray(rate) { i -> (10_000 * sin(2 * PI * 300 * i / rate)).toInt().toShort() }
    val out = ShortArray(rate)
    val n = BoxResampler(rate, 1).process(mono, rate, out)
    assertEquals(16_000, n)
    val inRms = sqrt(mono.map { it.toDouble() * it }.average())
    val outRms = sqrt(out.take(n).map { it.toDouble() * it }.average())
    assertTrue("$inRms vs $outRms", abs(inRms - outRms) / inRms < 0.03)
  }

  @Test
  fun soft_clip_is_the_identity_below_the_knee() {
    assertEquals(0.5f, SoundMix.softClip(0.5f))
    assertEquals(-0.8f, SoundMix.softClip(-0.8f))
    assertTrue(SoundMix.softClip(1.6f) < 1f)
    assertTrue(SoundMix.softClip(-3f) >= -1f)
  }
}
