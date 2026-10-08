package com.mattssoftware.glyph.capture

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque
import kotlin.math.sqrt

/**
 * The dictation microphone (docs/STAGES_5_6_8_9.md, 8D): the Tauri app had none to port, since its WebView
 * recorded. An `AudioRecord` at 16 kHz, mono, float, read on a thread of its own in 200 ms chunks, which is what
 * Whisper consumes and what lib/capture/audio.dart asks for.
 *
 * NO ALWAYS-ON MICROPHONE. The device is opened by `open` and by nothing else, which the recorder calls when a
 * person starts recording, and it is let go by `close` (the recorder's pause, stop and cancel), when the reader
 * fails, and whenever the activity is no longer visible (`released`, from MainActivity.onStop): dictation is a
 * thing done with the screen in front of a person. A meeting, which goes on with the screen off, is the meeting
 * service's own microphone (MeetingService.kt) under its own notification.
 *
 * WHERE THE SAMPLES GO, chosen by `open`'s `direct`:
 *
 * - `direct: false`: every chunk goes to Dart on the event channel (`pcm`: little-endian f32 bytes), where
 *   lib/capture/device_mic.dart hands them on as the `MicrophoneInput` the recorder is written against, and the
 *   capture engine pushes them to the core itself.
 * - `direct: true`: every chunk goes straight into the Rust core over JNI (`push`, native/src/capture.rs
 *   `ghost_capture_push`), from this thread, with no base64 and no hop through two isolates; Dart hears only how
 *   loud each was. Chunks read before the capture has started (the model loads on the first press, and the
 *   first words of a note are usually its subject) are held here, at most [HELD_CHUNKS] of them, and handed
 *   over in order when Dart says `flow`. A chunk the core refuses (no capture is running) is dropped and counted.
 *
 * THE CHANNEL `ghost_md/mic`:
 * - `permission` -> "granted" | "ask" | "blocked" (refused for good: only the phone's settings change it).
 * - `request` -> "granted" | "denied" | "blocked", once the system's dialog is answered.
 * - `openSettings` -> whether the app's page in the phone's settings opened.
 * - `open {direct, noiseSuppression, autoGainControl, testWav?}` -> `{sampleRate, direct}`; an error
 *   "permission" when the microphone is not allowed, "unavailable" when the device would not open.
 * - `flow` -> null: the capture has started; what was held goes to the core (direct only).
 * - `close` -> `{samples, pushed, refused}`: let go of the device.
 *
 * THE EVENTS on `ghost_md/mic/events`, each a map:
 * - `{event: "chunk", rms, samples, pcm?}`: one chunk heard; `rms` is its level (0-1), `samples` how many have
 *   been read since `open`, `pcm` its bytes when not direct.
 * - `{event: "closed", reason}`: the device was let go without `close` ("background", "error").
 *
 * `testWav` is a DEBUG BUILD'S ONLY: a 16 kHz mono PCM16 WAV file played in place of the device at the pace a
 * microphone gives it, for an emulator started without audio. A build that is not debuggable refuses it.
 */
object DictationMic {
  private const val TAG = "GhostDictationMic"
  const val CHANNEL = "ghost_md/mic"
  const val EVENTS = "ghost_md/mic/events"
  const val SAMPLE_RATE = 16_000
  /** 200 ms: lib/capture/audio.dart's `_chunk`. */
  const val CHUNK = 3_200
  /** Thirty seconds of chunks held while a capture starts; older ones go first. */
  private const val HELD_CHUNKS = 150
  const val REQUEST_MICROPHONE = 4204

  init {
    System.loadLibrary("ghost_core")
  }

  /** native/src/capture.rs: 0 when the running capture took them, 1 when none is running, 2 when they could not be read. */
  @JvmStatic private external fun push(samples: FloatArray, count: Int): Int

  private val main = Handler(Looper.getMainLooper())
  @Volatile private var sink: EventChannel.EventSink? = null
  @Volatile private var session: Session? = null
  private var asking: MethodChannel.Result? = null

  private class Session(val record: AudioRecord?, val wav: File?, val direct: Boolean) {
    @Volatile var running = true
    @Volatile var flowing = false
    val held = ArrayDeque<FloatArray>()
    var samples = 0L
    var pushed = 0L
    var refused = 0L
    var thread: Thread? = null
    var suppressor: NoiseSuppressor? = null
    var gain: AutomaticGainControl? = null
  }

  fun register(activity: Activity, messenger: BinaryMessenger) {
    EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
      override fun onCancel(arguments: Any?) { sink = null }
    })
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "permission" -> result.success(permission(activity))
        "request" -> request(activity, result)
        "openSettings" -> result.success(openSettings(activity))
        "open" -> open(
          activity,
          direct = call.argument<Boolean>("direct") == true,
          noiseSuppression = call.argument<Boolean>("noiseSuppression") != false,
          autoGainControl = call.argument<Boolean>("autoGainControl") != false,
          testWav = call.argument<String>("testWav"),
          result = result,
        )
        "flow" -> {
          flow()
          result.success(null)
        }
        "close" -> result.success(close())
        else -> result.notImplemented()
      }
    }
  }

  private fun granted(context: Context) = context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

  private fun prefs(context: Context) = context.getSharedPreferences("ghost_mic", Context.MODE_PRIVATE)

  private fun permission(activity: Activity): String = when {
    granted(activity) -> "granted"
    // Refused before and Android will show no dialog again: asked once, and no rationale is offered.
    prefs(activity).getBoolean("asked", false) && !activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) -> "blocked"
    else -> "ask"
  }

  private fun request(activity: Activity, result: MethodChannel.Result) {
    if (granted(activity)) return result.success("granted")
    if (asking != null) return result.error("busy", "The microphone is already being asked for.", null)
    asking = result
    prefs(activity).edit().putBoolean("asked", true).apply()
    activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_MICROPHONE)
  }

  /** The system dialog's answer (MainActivity.onRequestPermissionsResult); true when the request was this one. */
  fun answered(activity: Activity, requestCode: Int, grantResults: IntArray): Boolean {
    if (requestCode != REQUEST_MICROPHONE) return false
    val result = asking ?: return true
    asking = null
    val allowed = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
    result.success(if (allowed) "granted" else if (activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)) "denied" else "blocked")
    return true
  }

  private fun openSettings(activity: Activity): Boolean = try {
    activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
    true
  } catch (error: Exception) {
    false
  }

  private fun open(activity: Activity, direct: Boolean, noiseSuppression: Boolean, autoGainControl: Boolean, testWav: String?, result: MethodChannel.Result) {
    close()
    if (testWav != null) {
      val debuggable = activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
      val file = File(testWav)
      if (!debuggable || !file.isFile) return result.error("unavailable", "A test recording is a debug build's, and it has to be there.", null)
      start(Session(null, file, direct))
      return result.success(mapOf("sampleRate" to SAMPLE_RATE, "direct" to direct))
    }
    if (!granted(activity)) return result.error("permission", "Ghost.md needs the microphone to record.", null)
    val record = try {
      val floor = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
      // Two seconds of room: the reader has a thread of its own, and this is for the moments it does not get the CPU.
      AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, maxOf(floor, SAMPLE_RATE * 4 * 2))
    } catch (error: Exception) {
      Log.w(TAG, "the microphone would not open", error)
      null
    }
    if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
      record?.release()
      return result.error("unavailable", "The microphone could not be opened.", null)
    }
    val opened = Session(record, null, direct)
    // What the web asked of getUserMedia: noise suppression and gain control, which help in a pocket or a street;
    // no echo cancellation. Each only where the phone has the effect.
    try {
      if (noiseSuppression && NoiseSuppressor.isAvailable()) opened.suppressor = NoiseSuppressor.create(record.audioSessionId)?.also { it.enabled = true }
      if (autoGainControl && AutomaticGainControl.isAvailable()) opened.gain = AutomaticGainControl.create(record.audioSessionId)?.also { it.enabled = true }
    } catch (error: Exception) {
      Log.i(TAG, "an audio effect would not attach: $error")
    }
    try {
      record.startRecording()
    } catch (error: Exception) {
      Log.w(TAG, "the microphone would not start", error)
      release(opened)
      return result.error("unavailable", "The microphone could not be started.", null)
    }
    if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
      // Another app holds it, or Android refused a start from an app it does not see in front.
      release(opened)
      return result.error("unavailable", "The microphone is in use, or Ghost.md is not in front.", null)
    }
    start(opened)
    result.success(mapOf("sampleRate" to record.sampleRate, "direct" to direct))
  }

  private fun start(opened: Session) {
    session = opened
    opened.thread = Thread({ read(opened) }, "ghost-dictation-mic").also { it.start() }
  }

  /** The reader: a chunk at a time until the session is closed or the device fails. */
  private fun read(mine: Session) {
    val chunk = FloatArray(CHUNK)
    val file = mine.wav?.let { RandomAccessFile(it, "r").apply { seek(44) } }
    val bytes = ByteArray(CHUNK * 2)
    var failed = false
    try {
      while (mine.running) {
        var filled = 0
        if (file != null) {
          // The test recording at a microphone's pace; then silence, as a room is once the speaker has stopped.
          val got = file.read(bytes).coerceAtLeast(0)
          val shorts = ByteBuffer.wrap(bytes, 0, got - got % 2).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
          while (shorts.hasRemaining()) chunk[filled++] = shorts.get() / 32768f
          while (filled < CHUNK) chunk[filled++] = 0f
          Thread.sleep(200)
        } else {
          while (filled < CHUNK && mine.running) {
            val got = mine.record!!.read(chunk, filled, CHUNK - filled, AudioRecord.READ_BLOCKING)
            if (got < 0) {
              failed = true
              break
            }
            filled += got
          }
          if (failed || filled < CHUNK) break
        }
        if (!mine.running) break
        heard(mine, chunk.copyOf())
      }
    } catch (error: Exception) {
      Log.w(TAG, "the microphone's reader stopped", error)
      failed = true
    } finally {
      file?.close()
    }
    if (failed && mine.running) {
      mine.running = false
      if (session === mine) session = null
      release(mine)
      tell(mapOf("event" to "closed", "reason" to "error"))
    }
  }

  private fun heard(mine: Session, chunk: FloatArray) {
    var sum = 0.0
    for (sample in chunk) sum += sample * sample
    val rms = sqrt(sum / chunk.size)
    mine.samples += chunk.size
    val said = HashMap<String, Any?>()
    said["event"] = "chunk"
    said["rms"] = rms
    said["samples"] = mine.samples
    if (mine.direct) {
      synchronized(mine) {
        if (mine.flowing) {
          send(mine, chunk)
        } else {
          if (mine.held.size >= HELD_CHUNKS) mine.held.removeFirst()
          mine.held.addLast(chunk)
        }
      }
    } else {
      val pcm = ByteBuffer.allocate(chunk.size * 4).order(ByteOrder.LITTLE_ENDIAN)
      pcm.asFloatBuffer().put(chunk)
      said["pcm"] = pcm.array()
    }
    tell(said)
  }

  /** One chunk into the core, counted. Called with the session's lock held, so held chunks and new ones stay in order. */
  private fun send(mine: Session, chunk: FloatArray) {
    if (push(chunk, chunk.size) == 0) mine.pushed += chunk.size else mine.refused += chunk.size
  }

  /** The capture has started: what was held goes to the core, in order, and every chunk after it follows directly. */
  private fun flow() {
    val mine = session ?: return
    synchronized(mine) {
      while (mine.held.isNotEmpty()) send(mine, mine.held.removeFirst())
      mine.flowing = true
    }
  }

  /** Lets go of the device; `{samples, pushed, refused}` for what was open, or null when nothing was. */
  private fun close(): Map<String, Any?>? {
    val mine = session ?: return null
    session = null
    mine.running = false
    release(mine)
    // The reader ends within one read (the device has stopped) or one chunk (a test recording).
    if (Thread.currentThread() !== mine.thread) mine.thread?.join(1_000)
    return mapOf("samples" to mine.samples, "pushed" to mine.pushed, "refused" to mine.refused)
  }

  private fun release(mine: Session) {
    try {
      mine.suppressor?.release()
      mine.gain?.release()
      mine.record?.let {
        if (it.recordingState == AudioRecord.RECORDSTATE_RECORDING) it.stop()
        it.release()
      }
    } catch (error: Exception) {
      Log.i(TAG, "letting go of the microphone: $error")
    }
  }

  /** The activity is no longer visible: a dictation still open is let go, and Dart is told why. */
  fun released() {
    if (close() != null) tell(mapOf("event" to "closed", "reason" to "background"))
  }

  private fun tell(said: Map<String, Any?>) {
    main.post { sink?.success(said) }
  }
}
