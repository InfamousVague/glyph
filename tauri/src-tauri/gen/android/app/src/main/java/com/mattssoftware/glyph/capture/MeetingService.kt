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
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import com.mattssoftware.glyph.MainActivity
import com.mattssoftware.glyph.files.LibraryTree
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
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
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
 * the table, the screen off, the app left (a swipe from Recents stops the
 * meeting, and what was recorded is written up: `onTaskRemoved`). So this is a
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
 * (recordings/RecordingWorker.kt) rather than at the next launch. No new
 * meeting starts while a Stop is being put away (`isEnding`): the Stop's
 * bookkeeping would otherwise clear the new meeting's state and change the
 * service's type from under its open microphone. The write-up runs on a thread
 * of its own, so a later meeting's Done and Discard never wait behind it, and
 * a new meeting asks any write-up in hand, this service's or the worker's, to
 * let go (`yieldWriteUps`). Discard
 * deletes the WAV and marks the job cancelled; from the notification, with the
 * app closed, the id is remembered in `discarded` until the page has deleted
 * the note and said so.
 *
 * Other apps' sound (native generation 25; "Include sound from other apps",
 * off by default): when the page asked for it and the person allowed the
 * screen-share consent, the START carries that answer, the service comes to the
 * front as `microphone|mediaProjection` (Android 14 refuses a projection to a
 * service of any other type), and OtherApps.kt reads the playback capture
 * beside the microphone; the reader mixes it into each read before the spool
 * writes it (SoundMix.kt), so the tape is still one 16 kHz mono stream. Media
 * and games only: Android never lets an app capture a call. A capture that will
 * not open, or a share stopped from the status bar, leaves the microphone
 * recording on its own, and `meetingState` says so (`otherApps`, `otherAppsNote`).
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
    /** The screen-share consent's answer (MainActivity, REQUEST_PROJECTION), when other apps' sound is wanted. */
    const val EXTRA_PROJECTION_CODE = "projectionCode"
    const val EXTRA_PROJECTION_DATA = "projectionData"
    /** Said on the meeting screen when other apps' sound was asked for and is not in the meeting. */
    const val OTHER_APPS_DECLINED = "Sharing was not allowed, so only the microphone is recording."
    const val OTHER_APPS_FAILED = "Other apps' sound could not be opened, so only the microphone is recording."
    const val OTHER_APPS_ENDED = "Sharing stopped, so only the microphone is recording now."
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
    /** How long a new meeting keeps asking a write-up in hand to let go, and how often. */
    private const val YIELD_MS = 5_000L
    private const val YIELD_EVERY_MS = 250L
    /** How long `onTimeout` waits for the run to let go before the service stops. */
    private const val TIMEOUT_WAIT_MS = 2_000L
    /** Said when a meeting is started while the last one's Stop is still being put away. */
    const val STILL_STOPPING = "The last meeting is still stopping. Try again in a moment."

    @Volatile private var instance: MeetingService? = null
    @Volatile private var recording = false
    @Volatile private var noteId: String? = null
    @Volatile private var title: String? = null
    @Volatile private var startedAt: Long? = null
    @Volatile private var startedAtElapsed = 0L
    @Volatile private var silenced = false
    /** Other apps' sound is being mixed into the meeting now. */
    @Volatile private var otherAppsOn = false
    /** Why other apps' sound was asked for and is not in the meeting, or null. */
    @Volatile private var otherAppsNote: String? = null

    /** The note id this service is writing up now, or null. */
    @Volatile var writingUp: String? = null
      private set

    /** A meeting a kill left unfinished, finished at launch and still to be said to the page once an activity is resumed. */
    private val died = AtomicReference<String?>(null)

    fun isRecording(): Boolean = recording

    /** The note being recorded now, or null: named in the notification tap's `open`. */
    fun recordingNoteId(): String? = if (recording) noteId else null

    /** The JSON the page polls (capture/meetingLive.ts `MeetingState`). */
    fun meetingState(context: Context): String {
      val elapsed = if (recording) SystemClock.elapsedRealtime() - startedAtElapsed else 0L
      return JSONObject()
        .put("recording", recording)
        .put("noteId", noteId ?: JSONObject.NULL)
        .put("title", title ?: JSONObject.NULL)
        .put("startedAt", startedAt ?: JSONObject.NULL)
        .put("elapsedMs", elapsed)
        .put("silenced", silenced)
        .put("otherApps", recording && otherAppsOn)
        .put("otherAppsHeard", recording && otherAppsOn && instance?.otherApps?.heard == true)
        .put("otherAppsNote", if (recording) otherAppsNote ?: JSONObject.NULL else JSONObject.NULL)
        .put("writingUp", writingUp ?: JSONObject.NULL)
        .put("discarded", JSONArray(discarded(context).toList()))
        .toString()
    }

    /**
     * A Stop or Discard is being put away: the microphone let go, the tape's
     * length being recorded, the type being changed for the write-up. A start
     * in that window is refused (MainActivity.startMeeting, `start`), since the
     * Stop's bookkeeping would clear the new meeting's state.
     */
    fun isEnding(): Boolean = instance?.ending?.get() == true

    /** Where the tape goes, and where Rust reads it from: `RECORDINGS` in src-tauri/src/paths.rs. Rename both together. */
    fun recordingsDir(context: Context): File = File(context.dataDir, "recordings")

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
     *
     * Only a meeting Rust never heard of is handed over here. One whose Stop got
     * as far as `finish` has a progress file, which the sweep below looks after,
     * and one whose request is in the chain already (the task swiped away,
     * `onTaskRemoved`) is not asked for twice: a second fresh request after the
     * page has taken the first one's result would write the meeting up again.
     */
    fun recover(context: Context) {
      val saved = prefs(context)
      val id = saved.getString(KEY_NOTE_ID, null)
      if (id != null && !recording) {
        val name = saved.getString(KEY_TITLE, null)
        Log.i(TAG, "finishing a meeting a kill left unfinished")
        clearMeeting(context)
        // "Still recording?" outlives a killed process on the shade; nobody is there to answer it now.
        RecordingAlerts.cancel(context, RecordingAlerts.QUESTION_ID)
        if (WriteUp.readProgress(context, id) == null && !RecordingWorker.isQueued(context, id)) {
          RecordingWorker.enqueue(context, id, name, now = false, fresh = true)
        }
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

  /** Stop's and Discard's bookkeeping, one at a time, off the thread that asked. */
  private lateinit var control: ExecutorService
  /** The write-ups, one at a time, on a thread of their own: a later meeting's Done and Discard never queue behind one. */
  private lateinit var writer: ExecutorService
  /** The main thread, where starts arrive: the one place a stop can be decided without racing a new START. */
  private val main = Handler(Looper.getMainLooper())
  /** The newest start this service was given, for `stopSelfResult`: a stop over a newer start is refused by Android. */
  @Volatile private var lastStartId = 0
  private var wakeLock: PowerManager.WakeLock? = null
  private var record: AudioRecord? = null
  /** Other apps' sound, while it is in the meeting (Android 10+). */
  @Volatile private var otherApps: OtherApps? = null
  private var reader: Thread? = null
  private val reading = AtomicBoolean(false)
  /** A Stop or Discard is on its way, until its bookkeeping is done: the second one is ignored, and no new meeting starts. */
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
    writer = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "glyph-meeting-write-up") }
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    lastStartId = startId
    when (intent?.action) {
      ACTION_START -> start(intent.getStringExtra(EXTRA_NOTE_ID), intent.getStringExtra(EXTRA_TITLE), startId, projectionOf(intent))
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
  private fun start(id: String?, name: String?, startId: Int, projection: Projection?) {
    if (id == null) {
      idleStop(startId)
      return
    }
    if (recording) {
      pushFailed(id, "A meeting is already being recorded.")
      return
    }
    if (ending.get()) {
      pushFailed(id, STILL_STOPPING)
      return
    }
    val file = File(recordingsDir(this), "$id.wav")
    var recorder: AudioRecord? = null
    var out: RandomAccessFile? = null
    otherAppsNote = projection?.note
    try {
      // With the projection's type when other apps' sound is wanted; Android refusing that type is the microphone alone.
      val sharing = projection?.data != null && startRecordingForeground(RecordingAlerts.recording(this, 0, false), projection = true)
      if (!sharing) startRecordingForeground(RecordingAlerts.recording(this, 0, false), projection = false)
      if (projection?.data != null && !sharing) otherAppsNote = OTHER_APPS_FAILED
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
      if (sharing && projection != null) openOtherApps(projection)
      recording = true
      reading.set(true)
      reader = Thread({ read(mic, spool) }, "glyph-meeting-mic").also { it.start() }
      push("started", id)
      yieldWriteUps()
    } catch (error: Exception) {
      Log.w(TAG, "the meeting could not start", error)
      closeOtherApps()
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
      otherAppsNote = null
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
    val sound = ShortArray(READ_BYTES / 2)
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
          // Other apps' sound added in before the bytes are written, as much of it as has arrived (SoundMix.kt).
          otherApps?.let { if (it.running) SoundMix.mixInto(buffer, n, it.ring, sound) }
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
    if (!onControl { finishRecording(reason) }) ending.set(false)
  }

  private fun requestDiscard(fromNotification: Boolean) {
    if (!recording || !ending.compareAndSet(false, true)) return
    if (!onControl { discardRecording(fromNotification) }) ending.set(false)
  }

  /** `work` on the control thread; false once the service has gone and the thread with it (onDestroy closes the file itself). */
  private fun onControl(work: () -> Unit): Boolean = try {
    control.execute(work)
    true
  } catch (error: RejectedExecutionException) {
    Log.w(TAG, "the service has gone", error)
    false
  }

  /**
   * Stop: the microphone let go, the tape's length recorded by Rust, the page
   * told, the chain request made, and then the write-up, on its own thread,
   * under the type a write-up is allowed. `finish` never deletes anything; on
   * its error the chain alone takes the job (the worker's `run` repeats
   * `finish`'s steps). `ending` stays set until the type has changed, so no
   * new meeting can start under the old one's bookkeeping.
   */
  private fun finishRecording(reason: String) {
    val id = noteId
    if (id == null) {
      ending.set(false)
      return
    }
    val name = title ?: ""
    val elapsed = SystemClock.elapsedRealtime() - startedAtElapsed
    endReader()
    RecordingAlerts.cancel(this, RecordingAlerts.QUESTION_ID)
    recording = false
    silenced = false
    val answer = try {
      // The note may be in a folder chosen through Android's picker, which Rust reaches through Kotlin.
      LibraryTree.install(this)
      JSONObject(RecordingJob.finish(dataDir.absolutePath, id, name) ?: "{}")
    } catch (error: Throwable) {
      Log.w(TAG, "finish threw", error)
      JSONObject().put("error", error.toString())
    }
    forget(id)
    if (answer.has("error")) {
      Log.w(TAG, "the tape was not recorded: ${answer.optString("error")}")
      // `finish` writes the queued progress file before anything that can fail, so the chain's run resumes it
      // as it is. If even that did not happen (it threw before writing), the request is fresh, so Rust makes the
      // file from the title; a request that is not fresh does nothing for an id with no file.
      RecordingWorker.enqueue(this, id, name, now = false, fresh = WriteUp.readProgress(this, id) == null)
      pushStopped(id, reason, elapsed)
      ending.set(false)
      settleAfter()
      return
    }
    pushStopped(id, reason, elapsed)
    // In hand before the chain request exists, so a worker that starts at once finds it so and waits its turn
    // rather than racing this service for the same job.
    writingUp = id
    // Waited for, briefly: when the task was swiped away the process has a fraction of a second left
    // (`onTaskRemoved`), and a request still in WorkManager's queue when it goes is no request at all.
    try {
      RecordingWorker.enqueue(this, id, name, now = false, fresh = false).result.get(2, TimeUnit.SECONDS)
    } catch (error: Exception) {
      Log.w(TAG, "the chain request was not confirmed", error)
    }
    holdWakeLock(WRITE_UP_WAKE_MS)
    try {
      startWriteUpForeground(RecordingAlerts.writeUp(this, name, RecordingAlerts.progressLine("listening", 0)))
    } catch (error: Exception) {
      // The type change refused (§127 section 9 has this unmeasured): the chain request exists, so the worker takes it.
      Log.w(TAG, "the write-up could not stay in the foreground", error)
      if (writingUp == id) writingUp = null
      ending.set(false)
      settleAfter()
      return
    }
    ending.set(false)
    try {
      writer.execute { runWriteUp(id, name) }
    } catch (error: RejectedExecutionException) {
      // The service went while this Stop was put away: the chain request exists, and the worker takes the job.
      Log.w(TAG, "the write-up was left to the chain", error)
      if (writingUp == id) writingUp = null
    }
  }

  /** The meeting's state let go, the saved copy with it, but only while it still names `id`. */
  private fun forget(id: String) {
    if (noteId != id) return
    clearMeeting(this)
    noteId = null
    title = null
    startedAt = null
  }

  /**
   * The write-up loop (WriteUp.kt), the service's flavour: heat waits a minute
   * at a time, every other hold leaves it to the chain, and so does a meeting
   * that started meanwhile (it has the cores; the chain request exists).
   */
  private fun runWriteUp(id: String, name: String) {
    var thermalWaits = 0
    while (!destroyed && !recording) {
      val outcome = WriteUp.runOnce(this, id, name, now = false, fresh = false, requestedAt = null) { line ->
        // Not over a new meeting's own notification while this run lets go for it, and not after the service went.
        if (!destroyed && writingUp == id && !recording) RecordingAlerts.show(this, RecordingAlerts.RECORDING_ID, RecordingAlerts.writeUp(this, name, line))
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
    if (writingUp == id) writingUp = null
    // Android's budget ran out (`onTimeout`) and the service went while the run let go: the progress line it may
    // have posted as a plain notification goes too.
    if (destroyed) RecordingAlerts.cancel(this, RecordingAlerts.RECORDING_ID) else settleAfter()
  }

  /** Discard: the microphone let go, the WAV removed, the job marked cancelled. The page deletes the note, now or when it next asks. */
  private fun discardRecording(fromNotification: Boolean) {
    val id = noteId
    if (id == null) {
      ending.set(false)
      return
    }
    endReader()
    RecordingAlerts.cancel(this, RecordingAlerts.QUESTION_ID)
    recording = false
    silenced = false
    File(recordingsDir(this), "$id.wav").delete()
    try {
      RecordingJob.cancel(dataDir.absolutePath, id, "cancel")
    } catch (error: Throwable) {
      Log.w(TAG, "cancel threw", error)
    }
    forget(id)
    ending.set(false)
    if (fromNotification) {
      prefs(this).edit().putStringSet(KEY_DISCARDED, discarded(this).apply { add(id) }).apply()
      push("discarded", id)
    }
    settleAfter()
  }

  /** After a recording or a write-up ends: stop when there is nothing left, else put the write-up's notification back. */
  private fun settleAfter() {
    if (recording || ending.get()) return
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
    closeOtherApps()
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

  /**
   * A new meeting has the cores: the write-up in hand, this service's or the
   * worker's, is asked to let go as "meeting" (the chain retries it once the
   * meeting ends). Asked again for a few seconds, because a run that has not
   * yet told Rust which job it is on (`RUNNING_JOB`) cannot hear the first ask.
   */
  private fun yieldWriteUps() {
    val dataDir = dataDir.absolutePath
    Thread({
      val until = SystemClock.elapsedRealtime() + YIELD_MS
      while (recording && SystemClock.elapsedRealtime() < until) {
        val running = listOfNotNull(writingUp, RecordingWorker.running).distinct()
        if (running.isEmpty()) break
        var heard = true
        for (id in running) {
          try {
            // `{"cancelled": true}` when that run was in hand and heard it (write_up.rs `cancel`).
            val answer = RecordingJob.cancel(dataDir, id, "meeting")
            if (answer == null || !JSONObject(answer).optBoolean("cancelled")) heard = false
          } catch (error: Throwable) {
            Log.w(TAG, "cancel threw", error)
            heard = false
          }
        }
        if (heard) break
        try {
          Thread.sleep(YIELD_EVERY_MS)
        } catch (_: InterruptedException) {
          break
        }
      }
    }, "glyph-meeting-yield").start()
  }

  /**
   * The task swiped away from Recents while a meeting records. The Tauri shell
   * exits its process when its last activity is destroyed, and this service
   * goes with it (seen on the emulator: "exited cleanly (0)" a moment after the
   * swipe, the service still in front), so the meeting cannot carry on. It is
   * stopped as Done would stop it, so the tape is measured and the chain request
   * made while there is still time, and what was recorded is written up with the
   * app closed rather than at the next launch. Should the process outlive the
   * swipe, the service writes it up itself, as after any Stop.
   */
  override fun onTaskRemoved(rootIntent: Intent?) {
    super.onTaskRemoved(rootIntent)
    if (!recording) return
    Log.i(TAG, "the task was removed while recording: the meeting stops")
    requestStop("died")
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
        // The run lets go within one graph computation; waited for briefly, inside the seconds Android allows, so
        // its last progress line is not posted after the service's own notification has gone.
        val until = SystemClock.elapsedRealtime() + TIMEOUT_WAIT_MS
        while (writingUp == id && SystemClock.elapsedRealtime() < until) {
          try {
            Thread.sleep(100)
          } catch (_: InterruptedException) {
            break
          }
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
    RecordingAlerts.cancel(this, RecordingAlerts.QUESTION_ID)
    dropWakeLock()
    instance = null
    control.shutdown()
    writer.shutdown()
    super.onDestroy()
  }

  /** Started for nothing (a stale action, no id): be foreground for a moment, as the start demanded, then go. */
  private fun idleStop(startId: Int) {
    if (recording || writingUp != null || ending.get()) return
    RecordingAlerts.cancel(this, RecordingAlerts.QUESTION_ID)
    try {
      startWriteUpForeground(RecordingAlerts.writeUp(this, null, "Writing up"))
    } catch (error: Exception) {
      Log.i(TAG, "idle start could not be foreground: $error")
    }
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelfResult(startId)
  }

  /**
   * The recording's type: microphone, and mediaProjection beside it when other apps' sound is wanted, which Android
   * 14 requires before the projection can be had. With `projection`, false when Android refused that type (the
   * caller then comes to the front with the microphone alone); without it, it throws as it always has.
   */
  private fun startRecordingForeground(notification: android.app.Notification, projection: Boolean): Boolean {
    if (projection) {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
      return try {
        val types = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
          ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        } else {
          ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        }
        startForeground(RecordingAlerts.RECORDING_ID, notification, types)
        true
      } catch (error: Exception) {
        Log.w(TAG, "the meeting could not come to the front with the projection", error)
        false
      }
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      startForeground(RecordingAlerts.RECORDING_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
    } else {
      startForeground(RecordingAlerts.RECORDING_ID, notification)
    }
    return true
  }

  /** The consent's answer a START carried, or null when other apps' sound was not asked for. */
  private class Projection(val code: Int, val data: Intent?, val note: String?)

  private fun projectionOf(intent: Intent): Projection? {
    if (!intent.hasExtra(EXTRA_PROJECTION_CODE)) return null
    val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      intent.getParcelableExtra(EXTRA_PROJECTION_DATA, Intent::class.java)
    } else {
      @Suppress("DEPRECATION")
      intent.getParcelableExtra(EXTRA_PROJECTION_DATA)
    }
    // No data is the consent declined: the meeting records the microphone, and says why.
    return Projection(intent.getIntExtra(EXTRA_PROJECTION_CODE, 0), data, if (data == null) OTHER_APPS_DECLINED else null)
  }

  /** The projection made from the consent's answer, and other apps' sound read from it; the microphone alone if not. */
  private fun openOtherApps(projection: Projection) {
    val data = projection.data ?: return
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
    val opened = try {
      val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
      val media = manager.getMediaProjection(projection.code, data)
      if (media == null) null else OtherApps.open(this, media) {
        // Stopped from either side; only a stop from outside is worth a line on the meeting screen.
        if (otherAppsOn && recording) otherAppsNote = OTHER_APPS_ENDED
        otherAppsOn = false
      }
    } catch (error: Exception) {
      Log.w(TAG, "other apps' sound could not be opened", error)
      null
    }
    otherApps = opened
    otherAppsOn = opened != null
    if (opened == null) otherAppsNote = OTHER_APPS_FAILED
  }

  private fun closeOtherApps() {
    val sound = otherApps ?: return
    otherApps = null
    otherAppsOn = false
    sound.stop()
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
