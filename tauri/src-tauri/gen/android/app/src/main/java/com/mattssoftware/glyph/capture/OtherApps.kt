package com.mattssoftware.glyph.capture

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import androidx.annotation.RequiresApi
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The sound of other apps in a meeting: Android's AudioPlaybackCapture (Android
 * 10 and later), read beside the microphone and mixed into it (SoundMix.kt).
 * Matt chose it knowing the limit, and the page says it plainly: Android lets an
 * app hear media and games, never calls. A call app plays its voices as
 * USAGE_VOICE_COMMUNICATION, which no app may capture, so the far side of a
 * phone call, a Meet or a Zoom on this phone is not in the tape; a video playing,
 * a podcast, a game is.
 *
 * It runs on a MediaProjection, the screen-share consent: MainActivity asks for
 * it (`createScreenCaptureIntent`, the whole screen on Android 14 so the dialog
 * does not offer one app's), and the meeting service, already a foreground
 * service of type mediaProjection by then as Android 14 requires, turns the
 * answer into the projection and this capture. Nothing of the screen is taken;
 * only the playback capture is ever made from it.
 *
 * MEDIA, GAME and UNKNOWN are the usages asked for (an app that labels nothing
 * is UNKNOWN), and this app's own uid is left out, so nothing Ghost.md plays is
 * recorded back into its own tape. 16 kHz mono first, the meeting's own format;
 * a phone whose capture will not open that way is read at 48 kHz stereo and
 * brought down (BoxResampler).
 */
@RequiresApi(Build.VERSION_CODES.Q)
internal class OtherApps private constructor(
  private val projection: MediaProjection,
  private val record: AudioRecord,
  private val rate: Int,
  private val channels: Int,
) {
  /** Waiting for the microphone's next read. */
  val ring = SoundRing()
  /** Anything but silence has come through: shown on the meeting screen. */
  @Volatile var heard = false
    private set
  /** Reading now: false once stopped, or once the person stopped the share from the status bar. */
  @Volatile var running = false
    private set
  private val reading = AtomicBoolean(false)
  private var reader: Thread? = null

  /** The share ended from outside (the status bar's Stop, another projection): the meeting carries on, microphone only. */
  private val ended = object : MediaProjection.Callback() {
    override fun onStop() {
      Log.i(TAG, "the projection stopped: other apps' sound ends, the microphone carries on")
      stop()
    }
  }

  private fun start(onEnded: () -> Unit) {
    endedHook = onEnded
    record.startRecording()
    if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) throw IllegalStateException("the playback capture did not start")
    running = true
    reading.set(true)
    reader = Thread({ read() }, "glyph-meeting-other-apps").also { it.start() }
  }

  @Volatile private var endedHook: (() -> Unit)? = null

  private fun read() {
    val frames = READ_FRAMES
    val raw = ShortArray(frames * channels)
    val resampler = if (rate == WavSpool.SAMPLE_RATE && channels == 1) null else BoxResampler(rate, channels)
    val out = ShortArray(frames)
    while (reading.get()) {
      val n = record.read(raw, 0, raw.size)
      if (n < 0) {
        Log.w(TAG, "playback capture read failed ($n)")
        break
      }
      if (n == 0) continue
      val got = n / channels
      if (!heard) for (i in 0 until n) if (kotlin.math.abs(raw[i].toInt()) > SoundMix.HEARD_ABOVE) {
        heard = true
        break
      }
      if (resampler == null) {
        ring.put(raw, got)
      } else {
        val written = resampler.process(raw, got, out)
        ring.put(out, written)
      }
    }
    running = false
  }

  /** The capture and the projection let go. Safe to call twice, and from the projection's own callback. */
  fun stop() {
    if (!reading.getAndSet(false) && !running) return
    running = false
    try {
      record.stop()
    } catch (_: IllegalStateException) {
      // Never started.
    }
    val thread = reader
    if (thread != null && thread !== Thread.currentThread()) thread.join(2_000)
    reader = null
    record.release()
    ring.clear()
    try {
      projection.unregisterCallback(ended)
      projection.stop()
    } catch (error: Exception) {
      Log.w(TAG, "the projection did not stop cleanly", error)
    }
    endedHook?.invoke()
    endedHook = null
  }

  companion object {
    private const val TAG = "GlyphMeeting"
    /** 100 ms at 16 kHz: a read's worth, in the ring before the microphone's next 128 ms read takes it. */
    private const val READ_FRAMES = 1_600
    private const val FALLBACK_RATE = 48_000

    /** Whether this phone can hear other apps at all, and why not when it cannot. */
    fun unsupported(): String? =
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) "Android 10 or later can record the sound of other apps. This phone records the microphone." else null

    /**
     * The capture opened on `projection` and started, or null when it would
     * not open (the projection is then stopped). `onEnded` hears it stop, from
     * whichever side stopped it.
     */
    @SuppressLint("MissingPermission")
    fun open(context: Context, projection: MediaProjection, onEnded: () -> Unit): OtherApps? {
      if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
        projection.stop()
        return null
      }
      val config = AudioPlaybackCaptureConfiguration.Builder(projection)
        .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
        .addMatchingUsage(AudioAttributes.USAGE_GAME)
        .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
        .excludeUid(Process.myUid())
        .build()
      for ((rate, mask, channels) in listOf(
        Triple(WavSpool.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, 1),
        Triple(FALLBACK_RATE, AudioFormat.CHANNEL_IN_STEREO, 2),
      )) {
        val record = try {
          val minimum = AudioRecord.getMinBufferSize(rate, mask, AudioFormat.ENCODING_PCM_16BIT)
          AudioRecord.Builder()
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate).setChannelMask(mask).build())
            .setBufferSizeInBytes(maxOf(minimum, rate * channels * 2))
            .setAudioPlaybackCaptureConfig(config)
            .build()
        } catch (error: Exception) {
          Log.i(TAG, "playback capture would not open at $rate Hz: $error")
          null
        } ?: continue
        if (record.state != AudioRecord.STATE_INITIALIZED) {
          record.release()
          continue
        }
        val capture = OtherApps(projection, record, rate, channels)
        try {
          // Registered before anything reads from the projection, as Android 14 asks.
          projection.registerCallback(capture.ended, Handler(Looper.getMainLooper()))
          capture.start(onEnded)
          return capture
        } catch (error: Exception) {
          Log.w(TAG, "playback capture did not start", error)
          capture.stop()
          return null
        }
      }
      projection.stop()
      return null
    }
  }
}
