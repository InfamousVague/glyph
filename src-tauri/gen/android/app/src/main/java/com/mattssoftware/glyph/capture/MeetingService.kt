package com.mattssoftware.glyph.capture

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import com.mattssoftware.glyph.MainActivity
import com.mattssoftware.glyph.recordings.Outcome
import com.mattssoftware.glyph.recordings.RecordingAlerts
import com.mattssoftware.glyph.recordings.RecordingJob
import com.mattssoftware.glyph.recordings.RecordingWorker
import com.mattssoftware.glyph.recordings.WriteUp
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * A meeting: the one microphone Glyph ever holds outside the page, and the
 * service that writes the meeting up once it stops.
 *
 * Matt: "I'm going to start recording meetings and stuff and letting the audio
 * be transcribed then summarized by AI so I get summarized recording notes
 * automatically via a background task, when it's done send a notification that
 * a new recording has been summarized." He chose a recording that keeps going
 * with the screen off, and summaries on the phone, never the server.
 *
 * The page's microphone is the WebView's, held only while the recorder is on
 * screen with the screen kept on. A meeting is the other case: the phone on
 * the table, the screen off, the app left or swiped away. So this is a
 * foreground service of type `microphone`, started while the app is in front
 * (the one moment Android allows that type to start), holding a partial wake
 * lock, reading `AudioRecord` at 16 kHz mono PCM16 and writing the WAV as it
 * goes (WavSpool), so a kill loses nothing but the last ten seconds of the
 * header's number. No `FLAG_KEEP_SCREEN_ON`, no screen-off receiver: those are
 * the dictation's, and the screen going off is this service's whole point.
 *
 * Stop (Done on the meeting screen, the notification's Stop, the four-hour cap,
 * a read error) lets the microphone go, has Rust record the tape's length
 * (`RecordingJob.finish`), and then carries on as the write-up under a
 * `mediaProcessing` type (`specialUse` on Android 14), with the chain request
 * enqueued first so a kill mid-write-up is picked up by WorkManager's backoff
 * (recordings/RecordingWorker.kt) rather than at the next launch. Discard
 * deletes the WAV and marks the job cancelled; from the notification, with the
 * app closed, the id is remembered in `discarded` until the page has deleted
 * the note and said so.
 *
 * The page hears every change as `window.__glyph.meeting(json)` while an
 * activity is resumed (MainActivity.tell) and reads `meetingState()` when it
 * comes back. State lives in the companion (`@Volatile`, read from the bridge
 * thread) and is mirrored in SharedPreferences `glyph_meeting` for the meeting
 * a kill left unfinished, which `recover` finishes at the next launch.
 */
class MeetingService : Service() {
  companion object {
    const val ACTION_START = "com.mattssoftware.glyph.meeting.START"
    const val ACTION_STOP = "com.mattssoftware.glyph.meeting.STOP"
    const val ACTION_DISCARD = "com.mattssoftware.glyph.meeting.DISCARD"
    const val ACTION_KEEP_GOING = "com.mattssoftware.glyph.meeting.KEEP_GOING"
    const val EXTRA_NOTE_ID = "noteId"
    const val EXTRA_TITLE = "title"
    /** The hard cap: a meeting stops here whatever was answered. */
    const val MEETING_MAX_MS = 4 * 60 * 60 * 1000L
    /** When "Still recording?" is asked. */
    const val MEETING_ASK_MS = 2 * 60 * 60 * 1000L
    /** How long the question waits for an answer before the meeting stops as Done. */
    const val MEETING_ANSWER_MS = 5 * 60 * 1000L
    private const val PREFS = "glyph_meeting"
    private const val KEY_NOTE_ID = "noteId"
    private const val KEY_TITLE = "title"
    private const val KEY_STARTED_AT = "startedAt"
    private const val KEY_DISCARDED = "discarded"
    private const val TAG = "GlyphMeeting"
    private const val THERMAL_WAIT_MS = 60_000L
    private const val THERMAL_WAITS = 30
    /** How often, and how many times, the word of a died meeting is offered to a page that has not registered for it yet. */
    private const val FLUSH_EVERY_MS = 2_000L
    private const val FLUSH_TRIES = 15
    /** The wake lock's own limit, past the cap and the question: a lock this service forgot must not outlive the phone's night. */
    private const val RECORDING_WAKE_MS = MEETING_MAX_MS + MEETING_ANSWER_MS + 60_000L
    private const val WRITE_UP_WAKE_MS = 4 * 60 * 60 * 1000L
    /** Two seconds of PCM16 at 16 kHz. The reader has its own thread and a wake lock; the room is for the moments it does not get the CPU. */
    private const val RECORD_BUFFER_BYTES = 64_000
    private const val READ_BYTES = 4096

    @Volatile private var instance: MeetingService? = null
    @Volatile private var recording = false
    @Volatile private var noteId: String? = null
    @Volatile private var title: String? = null
    @Volatile private var startedAt: Long? = null
    @Volatile private var startedAtElapsed = 0L
    @Volatile private var silenced = false

    /** The note id this service is writing up now, or null. */
    @Volatile var writingUp: String? = null
      private set

    /** A meeting a kill left unfinished, finished at launch and still to be said to the page once an activity is resumed. */
    private val died = AtomicReference<String?>(null)

    fun isRecording(): Boolean = recording

    /** The JSON the page polls (the contract's 1.4). */
    fun meetingState(context: Context): String {
      val elapsed = if (recording) SystemClock.elapsedRealtime() - startedAtElapsed else 0L
      return JSONObject()
        .put("recording", recording)
        .put("noteId", noteId ?: JSONObject.NULL)
        .put("title", title ?: JSONObject.NULL)
        .put("startedAt", startedAt ?: JSONObject.NULL)
        .put("elapsedMs", elapsed)
        .put("silenced", silenced)
        .put("writingUp", writingUp ?: JSONObject.NULL)
        .put("discarded", JSONArray(discarded(context).toList()))
        .toString()
    }

    /** Done, from the page. Nothing when no meeting is being recorded. */
    fun stop() {
      instance?.requestStop("done")
    }

    /** Discard, from the page, which deletes the note itself: `discarded` is not touched. */
    fun discard() {
      instance?.requestDiscard(fromNotification = false)
    }

    /** The page has deleted a note the notification's Discard threw away. */
    fun forgetDiscarded(context: Context, id: String) {
      val left = discarded(context).apply { remove(id) }
      prefs(context).edit().putStringSet(KEY_DISCARDED, left).apply()
    }

    /**
     * At launch, off the main thread: a meeting the process died in the middle
     * of is handed to the chain (the worker's `run` repeats `finish`'s steps,
     * so nothing here calls into Rust beside Tauri's own index open in the same
     * second), and the page is told it stopped as `died`. Then every unfinished
     * job goes back into the chain.
     */
    fun recover(context: Context) {
      val saved = prefs(context)
      val id = saved.getString(KEY_NOTE_ID, null)
      if (id != null && !recording) {
        val name = saved.getString(KEY_TITLE, null)
        Log.i(TAG, "finishing a meeting a kill left unfinished")
        clearMeeting(context)
        RecordingWorker.enqueue(context, id, name, now = false, fresh = true)
        died.set(id)
        flushPending()
      }
      RecordingWorker.sweep(context)
    }

    /** One chain of offers at a time: `recover` and onResume both flush, and two chains would knock twice as often. */
    private val flushing = AtomicBoolean(false)

    /**
     * Says what was held for the page, once an activity is resumed
     * (MainActivity.onResume). At a cold launch the activity is resumed before
     * its WebView exists, and the page registers its handler later still, so
     * the word is kept until the page says it took it, and offered again every
     * two seconds for half a minute; after that it waits for the next resume.
     */
    fun flushPending() {
      if (died.get() == null || !flushing.compareAndSet(false, true)) return
      offerDied(0)
    }

    private fun offerDied(attempt: Int) {
      val id = died.get()
      if (id == null) {
        flushing.set(false)
        return
      }
      val json = JSONObject().put("event", "stopped").put("noteId", id).put("elapsedMs", 0).put("reason", "died")
      val told = MainActivity.tell("meeting", json.toString()) { taken ->
        if (taken) {
          died.compareAndSet(id, null)
          flushing.set(false)
        } else {
          offerLater(attempt)
        }
      }
      if (!told) offerLater(attempt)
    }

    private fun offerLater(attempt: Int) {
      if (attempt < FLUSH_TRIES) {
        Handler(Looper.getMainLooper()).postDelayed({ offerDied(attempt + 1) }, FLUSH_EVERY_MS)
      } else {
        flushing.set(false)
        Log.i(TAG, "the page did not take word of the meeting a kill left; kept for the next resume")
      }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun discarded(context: Context): MutableSet<String> =
      prefs(context).getStringSet(KEY_DISCARDED, emptySet())?.toMutableSet() ?: mutableSetOf()

    private fun clearMeeting(context: Context) {
      prefs(context).edit().remove(KEY_NOTE_ID).remove(KEY_TITLE).remove(KEY_STARTED_AT).apply()
    }
  }

  /** Everything after the microphone runs here, one thing at a time: Stop's bookkeeping, then the write-up. */
  private lateinit var control: ExecutorService
  /** The main thread, where starts arrive: the one place a stop can be decided without racing a new START. */
  private val main = Handler(Looper.getMainLooper())
  /** The newest start this service was given, for `stopSelfResult`: a stop over a newer start is refused by Android. */
  @Volatile private var lastStartId = 0
  private var wakeLock: PowerManager.WakeLock? = null
  private var record: AudioRecord? = null
  private var reader: Thread? = null
  private val reading = AtomicBoolean(false)
  /** A Stop or Discard is on its way: the second one is ignored. */
  private val ending = AtomicBoolean(false)
  @Volatile private var destroyed = false
  @Volatile private var asked = false
  @Volatile private var askedAtElapsed = 0L
  @Volatile private var keptGoing = false

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    instance = this
    control = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "glyph-meeting") }
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    lastStartId = startId
    when (intent?.action) {
      ACTION_START -> start(intent.getStringExtra(EXTRA_NOTE_ID), intent.getStringExtra(EXTRA_TITLE), startId)
      ACTION_STOP -> if (recording) requestStop("notification") else idleStop(startId)
      ACTION_DISCARD -> if (recording) requestDiscard(fromNotification = true) else idleStop(startId)
      ACTION_KEEP_GOING -> keepGoing(startId)
      else -> idleStop(startId)
    }
    // A microphone service cannot be restarted from the background on Android 14+, and a restarted one would have
    // no meeting to record anyway: the next launch's `recover` finishes what a kill left.
    return START_NOT_STICKY
  }

  /**
   * The microphone opened, in the order Android wants: foreground first (a
   * service started with `startForegroundService` has seconds to call this),
   * then the wake lock, then `AudioRecord`. Anything thrown, or a recorder
   * that did not initialise, undoes it all and tells the page `failed`.
   */
  private fun start(id: String?, name: String?, startId: Int) {
    if (id == null) {
      idleStop(startId)
      return
    }
    if (recording) {
      pushFailed(id, "A meeting is already being recorded.")
      return
    }
    // Where the tape goes, and where Rust reads it from: `RECORDINGS` in src-tauri/src/paths.rs. Rename both together.
    val file = File(File(dataDir, "recordings"), "$id.wav")
    var recorder: AudioRecord? = null
    var out: RandomAccessFile? = null
    try {
      startRecordingForeground(RecordingAlerts.recording(this, 0, false))
      holdWakeLock(RECORDING_WAKE_MS)
      val minimum = AudioRecord.getMinBufferSize(WavSpool.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
      // Plain MIC, no effects: the WebView path's noise suppression and gain are tuned for close talk; across a
      // table is unmeasured, and the first real meeting decides whether VOICE_RECOGNITION is better (§127 section 9).
      val mic = AudioRecord(
        MediaRecorder.AudioSource.MIC,
        WavSpool.SAMPLE_RATE,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT,
        maxOf(minimum, RECORD_BUFFER_BYTES),
      )
      recorder = mic
      if (mic.state != AudioRecord.STATE_INITIALIZED) throw IllegalStateException("the microphone did not open")
      val spool = WavSpool.open(file)
      out = spool
      record = mic
      noteId = id
      title = name
      startedAt = System.currentTimeMillis()
      startedAtElapsed = SystemClock.elapsedRealtime()
      silenced = false
      asked = false
      keptGoing = false
      ending.set(false)
      prefs(this).edit().putString(KEY_NOTE_ID, id).putString(KEY_TITLE, name).putLong(KEY_STARTED_AT, startedAt ?: 0L).apply()
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) mic.registerAudioRecordingCallback(ContextCompat.getMainExecutor(this), silence)
      mic.startRecording()
      if (mic.recordingState != AudioRecord.RECORDSTATE_RECORDING) throw IllegalStateException("the microphone did not start")
      recording = true
      reading.set(true)
      reader = Thread({ read(mic, spool) }, "glyph-meeting-mic").also { it.start() }
      push("started", id)
      // A write-up in hand belongs to the last meeting; this one has the cores now. The chain retries it later.
      writingUp?.let { earlier -> cancelWriteUp(earlier, "meeting") }
    } catch (error: Exception) {
      Log.w(TAG, "the meeting could not start", error)
      if (recorder != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) recorder.unregisterAudioRecordingCallback(silence)
      recorder?.release()
      record = null
      try {
        out?.close()
      } catch (_: IOException) {
        // Nothing to keep: the file goes next.
      }
      file.delete()
      noteId = null
      title = null
      startedAt = null
      recording = false
      clearMeeting(this)
      pushFailed(id, if (error is SecurityException) "Ghost.md needs the microphone to record a meeting." else "The meeting could not start.")
      if (writingUp == null) {
        dropWakeLock()
        stopSelf()
      } else {
        RecordingAlerts.show(this, RecordingAlerts.RECORDING_ID, RecordingAlerts.writeUp(this, null, "Writing up"))
      }
    }
  }

  /**
   * The reader: 4 KB at a time straight into the file, the header's lengths
   * brought up to date every ten seconds along with the notification's counter,
   * and the question and the cap checked on the same tick. A read error ends
   * the meeting as Stop does, with the reason said.
   */
  private fun read(recorder: AudioRecord, out: RandomAccessFile) {
    val buffer = ByteArray(READ_BYTES)
    var dataLen = 0L
    var lastPatch = SystemClock.elapsedRealtime()
    try {
      while (reading.get()) {
        val n = recorder.read(buffer, 0, buffer.size)
        if (n < 0) {
          if (reading.get()) {
            Log.w(TAG, "microphone read failed ($n)")
            requestStop("error")
          }
          break
        }
        if (n > 0) {
          out.write(buffer, 0, n)
          dataLen += n
        }
        val at = SystemClock.elapsedRealtime()
        if (at - lastPatch >= WavSpool.PATCH_EVERY_MS) {
          lastPatch = at
          WavSpool.patch(out, dataLen)
          val elapsed = at - startedAtElapsed
          RecordingAlerts.show(this, RecordingAlerts.RECORDING_ID, RecordingAlerts.recording(this, elapsed, silenced))
          tick(elapsed)
        }
      }
    } catch (error: IOException) {
      Log.w(TAG, "the recording could not be written", error)
      if (reading.get()) requestStop("error")
    } finally {
      try {
        WavSpool.patch(out, dataLen)
        out.close()
      } catch (error: IOException) {
        Log.w(TAG, "the recording's header could not be closed", error)
      }
    }
  }

  /** The two-hour question and the four-hour cap, judged every ten seconds on the reader's tick. */
  private fun tick(elapsed: Long) {
    if (elapsed >= MEETING_MAX_MS) {
      requestStop("cap")
      return
    }
    if (!asked && elapsed >= MEETING_ASK_MS) {
      asked = true
      askedAtElapsed = elapsed
      RecordingAlerts.show(this, RecordingAlerts.QUESTION_ID, RecordingAlerts.question(this, elapsed))
      push("asked", noteId)
      return
    }
    if (asked && !keptGoing && elapsed - askedAtElapsed >= MEETING_ANSWER_MS) requestStop("cap")
  }

  private fun keepGoing(startId: Int) {
    keptGoing = true
    RecordingAlerts.cancel(this, RecordingAlerts.QUESTION_ID)
    if (!recording && writingUp == null) idleStop(startId)
  }

  /** Another app took the microphone, or gave it back (Android 10+). The file keeps growing with silence so the timeline stays honest. */
  private val silence = object : AudioManager.AudioRecordingCallback() {
    override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !recording) return
      // Registered on the AudioRecord itself, so the list holds only this recorder's configuration.
      val mine = configs.firstOrNull() ?: return
      val now = mine.isClientSilenced
      if (now == silenced) return
      silenced = now
      push(if (now) "silenced" else "sounding", noteId)
      RecordingAlerts.show(this@MeetingService, RecordingAlerts.RECORDING_ID, RecordingAlerts.recording(this@MeetingService, SystemClock.elapsedRealtime() - startedAtElapsed, now))
    }
  }

  private fun requestStop(reason: String) {
    if (!recording || !ending.compareAndSet(false, true)) return
    control.execute { finishRecording(reason) }
  }

  private fun requestDiscard(fromNotification: Boolean) {
    if (!recording || !ending.compareAndSet(false, true)) return
    control.execute { discardRecording(fromNotification) }
  }

  /**
   * Stop: the microphone let go, the tape's length recorded by Rust, the page
   * told, the chain request made, and then the write-up here under the type a
   * write-up is allowed. `finish` never deletes anything; on its error the
   * chain alone takes the job (the worker's `run` repeats `finish`'s steps).
   */
  private fun finishRecording(reason: String) {
    val id = noteId ?: return
    val name = title ?: ""
    val elapsed = SystemClock.elapsedRealtime() - startedAtElapsed
    endReader()
    RecordingAlerts.cancel(this, RecordingAlerts.QUESTION_ID)
    recording = false
    silenced = false
    val answer = try {
      JSONObject(RecordingJob.finish(dataDir.absolutePath, id, name) ?: "{}")
    } catch (error: Throwable) {
      Log.w(TAG, "finish threw", error)
      JSONObject().put("error", error.toString())
    }
    clearMeeting(this)
    noteId = null
    title = null
    startedAt = null
    ending.set(false)
    if (answer.has("error")) {
      Log.w(TAG, "the tape was not recorded: ${answer.optString("error")}")
      // `finish` writes the queued progress file before anything that can fail, so the chain's run resumes it
      // as it is. If even that did not happen (it threw before writing), the request is fresh, so Rust makes the
      // file from the title; a request that is not fresh does nothing for an id with no file.
      RecordingWorker.enqueue(this, id, name, now = false, fresh = WriteUp.readProgress(this, id) == null)
      pushStopped(id, reason, elapsed)
      settleAfter()
      return
    }
    pushStopped(id, reason, elapsed)
    RecordingWorker.enqueue(this, id, name, now = false, fresh = false)
    // The last meeting's write-up, if one was cancelled for this recording, ran on this same thread and has ended.
    writingUp = id
    holdWakeLock(WRITE_UP_WAKE_MS)
    try {
      startWriteUpForeground(RecordingAlerts.writeUp(this, name, RecordingAlerts.progressLine("listening", 0)))
    } catch (error: Exception) {
      // The type change refused (§127 section 9 has this unmeasured): the chain request exists, so the worker takes it.
      Log.w(TAG, "the write-up could not stay in the foreground", error)
      writingUp = null
      settleAfter()
      return
    }
    runWriteUp(id, name)
  }

  /** The write-up loop (the contract's 7.2), the service's flavour: heat waits a minute at a time, every other hold leaves it to the chain. */
  private fun runWriteUp(id: String, name: String) {
    var thermalWaits = 0
    while (!destroyed) {
      val outcome = WriteUp.runOnce(this, id, name, now = false, fresh = false) { line ->
        if (writingUp == id) RecordingAlerts.show(this, RecordingAlerts.RECORDING_ID, RecordingAlerts.writeUp(this, name, line))
      }
      if (outcome is Outcome.Retry && outcome.reason == "thermal" && thermalWaits < THERMAL_WAITS) {
        var cooled = false
        while (thermalWaits < THERMAL_WAITS && !destroyed && !recording) {
          thermalWaits++
          try {
            Thread.sleep(THERMAL_WAIT_MS)
          } catch (_: InterruptedException) {
            break
          }
          if (!WriteUp.thermalSevere(this)) {
            cooled = true
            break
          }
        }
        if (cooled && !destroyed && !recording) continue
      }
      WriteUp.settle(this, id, name, outcome)
      break
    }
    writingUp = null
    settleAfter()
  }

  /** Discard: the microphone let go, the WAV removed, the job marked cancelled. The page deletes the note, now or when it next asks. */
  private fun discardRecording(fromNotification: Boolean) {
    val id = noteId ?: return
    endReader()
    RecordingAlerts.cancel(this, RecordingAlerts.QUESTION_ID)
    recording = false
    silenced = false
    File(File(dataDir, "recordings"), "$id.wav").delete()
    try {
      RecordingJob.cancel(dataDir.absolutePath, id, "cancel")
    } catch (error: Throwable) {
      Log.w(TAG, "cancel threw", error)
    }
    clearMeeting(this)
    noteId = null
    title = null
    startedAt = null
    ending.set(false)
    if (fromNotification) {
      prefs(this).edit().putStringSet(KEY_DISCARDED, discarded(this).apply { add(id) }).apply()
      push("discarded", id)
    }
    settleAfter()
  }

  /** After a recording or a write-up ends: stop when there is nothing left, else put the write-up's notification back. */
  private fun settleAfter() {
    if (recording) return
    val current = writingUp
    if (current == null) {
      dropWakeLock()
      // Decided on the main thread, where a START is handled: one delivered meanwhile has set `recording` by the
      // time this runs, and one not yet delivered carries a newer start id, which stopSelfResult will not stop over.
      // A plain stopSelf here could take down a meeting that began while the last write-up was ending.
      main.post { if (!recording && writingUp == null) stopSelfResult(lastStartId) }
    } else {
      RecordingAlerts.show(this, RecordingAlerts.RECORDING_ID, RecordingAlerts.writeUp(this, null, "Writing up"))
    }
  }

  private fun endReader() {
    reading.set(false)
    val recorder = record
    try {
      recorder?.stop()
    } catch (_: IllegalStateException) {
      // Never started: nothing to stop.
    }
    reader?.join(5_000)
    reader = null
    if (recorder != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) recorder.unregisterAudioRecordingCallback(silence)
    recorder?.release()
    record = null
  }

  private fun cancelWriteUp(id: String, reason: String) {
    val dataDir = dataDir.absolutePath
    Thread({
      try {
        RecordingJob.cancel(dataDir, id, reason)
      } catch (error: Throwable) {
        Log.w(TAG, "cancel threw", error)
      }
    }, "glyph-meeting-cancel").start()
  }

  /**
   * Android 15's budget for `mediaProcessing` ran out: the run is asked to let
   * go as a timeout and the service stops within seconds, as the platform
   * requires. The chain request already exists, so the job resumes later.
   */
  override fun onTimeout(startId: Int, fgsType: Int) {
    super.onTimeout(startId, fgsType)
    Log.i(TAG, "foreground time ran out (type $fgsType)")
    val id = writingUp
    val dataDir = dataDir.absolutePath
    Thread({
      if (id != null) {
        try {
          RecordingJob.cancel(dataDir, id, "timeout")
        } catch (error: Throwable) {
          Log.w(TAG, "timeout cancel threw", error)
        }
      }
      stopSelf()
    }, "glyph-meeting-timeout").start()
  }

  override fun onDestroy() {
    destroyed = true
    if (recording) {
      // Stopped from outside while recording: close the file cleanly and leave `glyph_meeting` as it is, so the next
      // launch finishes this meeting as one a kill left.
      Log.w(TAG, "destroyed while recording")
      endReader()
      recording = false
    }
    dropWakeLock()
    instance = null
    control.shutdown()
    super.onDestroy()
  }

  /** Started for nothing (a stale action, no id): be foreground for a moment, as the start demanded, then go. */
  private fun idleStop(startId: Int) {
    if (recording || writingUp != null) return
    try {
      startWriteUpForeground(RecordingAlerts.writeUp(this, null, "Writing up"))
    } catch (error: Exception) {
      Log.i(TAG, "idle start could not be foreground: $error")
    }
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelfResult(startId)
  }

  private fun startRecordingForeground(notification: android.app.Notification) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      startForeground(RecordingAlerts.RECORDING_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
    } else {
      startForeground(RecordingAlerts.RECORDING_ID, notification)
    }
  }

  /** The write-up's type: `mediaProcessing` exists from Android 15, `specialUse` from 14, and below that types are not asked for. */
  private fun startWriteUpForeground(notification: android.app.Notification) {
    when {
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM ->
        startForeground(RecordingAlerts.RECORDING_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING)
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
        startForeground(RecordingAlerts.RECORDING_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
      else -> startForeground(RecordingAlerts.RECORDING_ID, notification)
    }
  }

  private fun holdWakeLock(timeoutMs: Long) {
    val lock = wakeLock ?: (getSystemService(POWER_SERVICE) as PowerManager)
      .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "glyph:meeting")
      .also {
        it.setReferenceCounted(false)
        wakeLock = it
      }
    lock.acquire(timeoutMs)
  }

  private fun dropWakeLock() {
    val lock = wakeLock ?: return
    if (lock.isHeld) lock.release()
  }

  private fun push(event: String, id: String?) {
    val json = JSONObject()
      .put("event", event)
      .put("noteId", id ?: JSONObject.NULL)
      .put("elapsedMs", if (recording) SystemClock.elapsedRealtime() - startedAtElapsed else 0L)
    MainActivity.tell("meeting", json.toString())
  }

  private fun pushStopped(id: String, reason: String, elapsed: Long) {
    val json = JSONObject().put("event", "stopped").put("noteId", id).put("elapsedMs", elapsed).put("reason", reason)
    MainActivity.tell("meeting", json.toString())
  }

  private fun pushFailed(id: String, message: String) {
    val json = JSONObject().put("event", "failed").put("noteId", id).put("elapsedMs", 0).put("message", message)
    MainActivity.tell("meeting", json.toString())
  }
}
