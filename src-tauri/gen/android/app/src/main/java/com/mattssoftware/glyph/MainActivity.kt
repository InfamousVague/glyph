package com.mattssoftware.glyph

import android.Manifest
import android.app.KeyguardManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.activity.OnBackPressedCallback
import androidx.activity.enableEdgeToEdge
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.exifinterface.media.ExifInterface
import androidx.lifecycle.Lifecycle
import com.mattssoftware.glyph.location.LocationAccess
import com.mattssoftware.glyph.media.VideoPick
import com.mattssoftware.glyph.files.ExportTarget
import org.json.JSONObject
import java.io.FileOutputStream
import java.util.Locale
import java.util.UUID
import com.mattssoftware.glyph.capture.MeetingService
import com.mattssoftware.glyph.capture.OtherApps
import com.mattssoftware.glyph.recordings.RecordingAlerts
import com.mattssoftware.glyph.recordings.RecordingJob
import com.mattssoftware.glyph.recordings.RecordingWorker
import com.mattssoftware.glyph.notices.NoticeAlerts
import com.mattssoftware.glyph.updates.UpdateAlerts
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The one activity, and the door the side key comes in through.
 *
 * HAND-WRITTEN AND TRACKED. `tauri android init` would replace this with its
 * two-line template and never recreate what is below; `.gitignore` re-includes
 * it by name for that reason.
 *
 * Everything here is about one question - "was this a request to start
 * recording?" - and getting that answer to the page. A capture arrives two ways:
 * cold (Glyph was not running; the answer is read by the page as it boots) and
 * warm (Glyph was open or backgrounded; the answer is pushed to the page). Both
 * paths are needed because a `singleTask` activity receives a second launch as
 * `onNewIntent`, not `onCreate`, and a page that is already up will never ask.
 */
class MainActivity : TauriActivity() {
  companion object {
    /** Sent by `GlyphSession` when the side key is held, and by the launcher shortcut. */
    const val ACTION_CAPTURE = "com.mattssoftware.glyph.CAPTURE"
    const val EXTRA_SOURCE = "com.mattssoftware.glyph.SOURCE"
    /** On the recording notification's tap: a plain launch that opens the meeting screen (native generation 20). */
    const val EXTRA_MEETING = "com.mattssoftware.glyph.MEETING"
    private const val TAG = "GlyphCapture"
    private const val REQUEST_NOTIFICATIONS = 4101
    private const val REQUEST_PICTURE = 4102
    /** Meetings ask for notifications with their own code: 4101 is update alerts', and its answer must not switch those on. */
    private const val REQUEST_MEETING_NOTIFICATIONS = 4103
    /** The microphone, for a meeting on a phone that never dictated (the WebView asks for its own). */
    private const val REQUEST_MICROPHONE = 4104
    /** The screen-share consent, for a meeting with other apps' sound in it (native generation 25). */
    private const val REQUEST_PROJECTION = 4105
    /** A picked picture is shrunk so its long side is at most this, as a JPEG. Plenty for a note; ~300 KB. */
    private const val PICTURE_MAX_PX = 1600

    /**
     * The activity in front, for the meeting service to reach the page through
     * (native generation 20). Set in onResume and cleared in onPause, and a
     * WeakReference, never a captured activity: the service outlives the task,
     * and an activity it held on to would be a leaked window.
     */
    @Volatile private var resumed: WeakReference<MainActivity>? = null

    /** Whether the app is in front: the notices worker then leaves the feed to the page (notices/NoticeWorker.kt). */
    fun isInFront(): Boolean = resumed?.get() != null

    /**
     * The trash's cancel and the write-up's request, one after the other in the
     * order the page made them (native generation 20). A meeting put in the
     * trash and brought straight back by the toast's Undo asks for both within
     * a second; the cancel waits for the run to let go before it marks the file,
     * and a request enqueued meanwhile would be older than that mark, which Rust
     * honours over it. Made one at a time, the request is always the newer.
     */
    private val writeUpDoor: ExecutorService by lazy { Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "glyph-write-up-door") } }

    /**
     * `window.__glyph.<name>(argument)` on the page, from anywhere in the
     * process, while an activity is resumed; false when none is, and the call is
     * dropped (the page reads `meetingState()` when it is next visible). The
     * WebView is resumed first, as `deliverCapture` does: a paused one queues
     * the script instead of running it.
     */
    internal fun tell(name: String, argument: String?): Boolean = tell(name, argument, null)

    /**
     * As above, and `taken` hears whether the page had a handler for it: false
     * when it did not (the page is still loading, or an older page), so a word
     * that must not be lost can be kept and said again.
     */
    internal fun tell(name: String, argument: String?, taken: ((Boolean) -> Unit)?): Boolean {
      val activity = resumed?.get() ?: return false
      val wv = activity.webView ?: return false
      val call = if (argument == null) "window.__glyph.$name()" else "window.__glyph.$name(${JSONObject.quote(argument)})"
      activity.runOnUiThread {
        wv.onResume()
        wv.evaluateJavascript("window.__glyph && window.__glyph.$name ? ($call, 'ok') : 'no'") { result ->
          taken?.invoke(result == "\"ok\"")
        }
      }
      return true
    }
  }

  private var webView: WebView? = null

  /**
   * A capture request the page has not collected yet. Volatile because the page
   * reads it on the WebView's JavaBridge thread while this activity writes it
   * on the main thread.
   */
  @Volatile private var pendingLaunch: String? = null

  /**
   * A `ghostmd://` link this activity was opened with, until the page takes it
   * (`GlyphHost.takeLink`). The deep-link plugin carries the same link when it
   * can; it cannot in an activity recreated inside a live process (the app
   * swiped away during a write-up, then the notification tapped), where its
   * channel is null, so the link is kept here as well and the page takes both.
   */
  @Volatile private var pendingLink: String? = null

  /** The microphone permission's answer, delivered from onResume so the page's retry runs with the activity resumed. */
  @Volatile private var pendingPermission: Boolean? = null

  /** The note whose meeting asked for the microphone, named in the answer so the page knows whose it is. */
  @Volatile private var microphoneFor: String? = null

  /** The meeting waiting on the screen-share consent: its note and its title. */
  @Volatile private var projectionFor: Pair<String, String>? = null

  /** The consent's answer, for the meeting it was asked for; started from onResume, with the activity in front. */
  private class ProjectionAnswer(val noteId: String, val title: String, val code: Int, val data: Intent?)
  @Volatile private var pendingProjection: ProjectionAnswer? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    // Before super: the window's lock-screen behaviour has to be decided before
    // the window is shown, and super.onCreate is what shows it.
    takeCapture(intent)
    takeMeeting(intent)
    takeLink(intent)
    super.onCreate(savedInstanceState)
    // Off the main thread: it opens WorkManager and reads the jobs folder, and it
    // must not race Tauri's own index open in the same second (it calls no Rust).
    Thread({ MeetingService.recover(applicationContext) }, "glyph-meeting-recover").start()
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    if (takeCapture(intent)) deliverCapture()
    if (takeMeeting(intent)) deliverMeeting()
    takeLink(intent)
  }

  /**
   * The notification permission answer, for update alerts. `super` first: Tauri's
   * plugins route their own permission results through this same callback.
   * The page is then told to re-read the switch, because `setUpdateAlerts`
   * returned before the person had answered.
   */
  /**
   * The picked picture, shrunk and rotated the right way up, written to
   * cacheDir/picked/ and announced to the page as `window.__glyph.image(json)`.
   * Rust then files it under the app's data (`save_image`); the cache copy is
   * the only thing this activity ever writes. A picked film is media/VideoPick.kt's
   * (native generation 21), and is announced as its own event, `video`.
   */
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode == REQUEST_PROJECTION) {
      val asked = projectionFor
      projectionFor = null
      if (asked != null) {
        // Declined is no data: the meeting starts all the same, with the microphone, and its screen says why.
        val answer = ProjectionAnswer(asked.first, asked.second, resultCode, if (resultCode == RESULT_OK) data else null)
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) launchMeeting(answer.noteId, answer.title, answer) else pendingProjection = answer
      }
      return
    }
    if (VideoPick.answered(this, requestCode, resultCode, data, ::tellVideo)) return
    if (ExportTarget.answered(this, requestCode, resultCode, data, ::tellExport)) return
    if (requestCode != REQUEST_PICTURE) return
    val uri = data?.data
    if (resultCode != RESULT_OK || uri == null) {
      tellPage(JSONObject().put("cancelled", true))
      return
    }
    Thread {
      val answer = try {
        JSONObject().put("path", shrinkPicture(uri).absolutePath)
      } catch (error: Exception) {
        Log.w(TAG, "picture not read", error)
        JSONObject().put("error", "That picture could not be read.")
      }
      tellPage(answer)
    }.start()
  }

  private fun tellPage(answer: JSONObject) {
    val wv = webView ?: return
    val script = "window.__glyph && window.__glyph.image && window.__glyph.image(${JSONObject.quote(answer.toString())})"
    runOnUiThread { wv.evaluateJavascript(script, null) }
  }

  /**
   * A picked film's answer to the page, `window.__glyph.video(json)` (core/videos.ts). A page that is not listening
   * (still loading after the process was recreated behind the picker) drops it, and the copies it named wait in
   * picked/ for the launch sweep (src-tauri/src/videos.rs).
   */
  private fun tellVideo(json: String) {
    val wv = webView ?: return
    val script = "window.__glyph && window.__glyph.video && window.__glyph.video(${JSONObject.quote(json)})"
    runOnUiThread { wv.evaluateJavascript(script, null) }
  }

  /**
   * Where an export goes, `window.__glyph.exportTarget(json)` (core/exportAll.ts): the descriptor of the file the
   * picker made, `{ cancelled }` or `{ error }` (files/ExportTarget.kt). Native generation 22.
   */
  private fun tellExport(json: String) {
    val wv = webView ?: return
    val script = "window.__glyph && window.__glyph.exportTarget && window.__glyph.exportTarget(${JSONObject.quote(json)})"
    runOnUiThread { wv.evaluateJavascript(script, null) }
  }

  /*
   * The hinge, streamed to the page while Glyph is up.
   *
   * The note screen draws its unfold from the angle (core/unfold.ts), so it
   * needs the angle as it changes, not the fold state after the fact. The
   * sensor is Android's own (TYPE_HINGE_ANGLE, degrees, 0 closed to 180 flat):
   * no permission, and a phone without one - every slab - answers null and
   * nothing here runs. Registered in onResume and dropped in onPause, so a
   * backgrounded Glyph is not woken fifty times a second by a hand opening
   * the phone for something else. Readings reach the page the way tellPage's
   * do, on the main thread, as `window.__glyph.hinge(degrees)`.
   */
  private val hinge: Sensor? by lazy {
    (getSystemService(SENSOR_SERVICE) as? SensorManager)?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)
  }
  private var lastHinge = Float.NaN

  private val hingeListener = object : SensorEventListener {
    override fun onSensorChanged(event: SensorEvent) {
      val angle = event.values[0]
      // Half a degree is below anything the page draws; a sensor that
      // chatters in hundredths would otherwise post a script per tick.
      if (!lastHinge.isNaN() && kotlin.math.abs(angle - lastHinge) < 0.5f) return
      lastHinge = angle
      val wv = webView ?: return
      val script = "window.__glyph && window.__glyph.hinge && window.__glyph.hinge(${String.format(Locale.US, "%.1f", angle)})"
      runOnUiThread { wv.evaluateJavascript(script, null) }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
  }

  override fun onResume() {
    super.onResume()
    resumed = WeakReference(this)
    // The microphone's answer, now that the page's retry can start the service while the activity is resumed.
    pendingPermission?.let { granted ->
      pendingPermission = null
      deliverPermission(granted)
    }
    // The screen-share consent's answer: the meeting's service starts now, with the activity back in front, which
    // the microphone's foreground type needs.
    pendingProjection?.let { answer ->
      pendingProjection = null
      launchMeeting(answer.noteId, answer.title, answer)
    }
    MeetingService.flushPending()
    // Registered whether or not the WebView exists yet: on a cold start it
    // may not, and the listener drops readings until it does. Waiting for it
    // here would mean no hinge until the second resume.
    val sensor = hinge ?: return
    lastHinge = Float.NaN
    (getSystemService(SENSOR_SERVICE) as SensorManager).registerListener(hingeListener, sensor, SensorManager.SENSOR_DELAY_GAME)
  }

  override fun onPause() {
    if (resumed?.get() === this) resumed = null
    (getSystemService(SENSOR_SERVICE) as? SensorManager)?.unregisterListener(hingeListener)
    super.onPause()
  }

  /**
   * The side key pressed during a recording, seen the only way an app can see
   * it: the screen going off.
   *
   * Android never gives an app the power key's press or release (it is kept
   * from every app so none can stop a phone turning off), and nothing lets an
   * app ask whether it is held. What an app CAN hear is ACTION_SCREEN_OFF,
   * which a quick press of the side key causes. So while a recording is going
   * the screen is kept on (FLAG_KEEP_SCREEN_ON, so a timeout never looks like
   * a press), and the screen going off means "stop": the page is told as
   * `window.__glyph.screenOff()` and saves the take the way Done does. The
   * receiver only exists while a recording does; `setCapturing` adds and
   * removes both. A held press does not turn the screen off, so letting go of
   * the hold that started the recording does not stop it.
   */
  private val screenOff = object : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
      if (intent.action != Intent.ACTION_SCREEN_OFF) return
      val wv = webView ?: return
      runOnUiThread {
        // A paused WebView queues evaluateJavascript instead of running it
        // (see deliverCapture), and the screen going off pauses the activity.
        wv.onResume()
        wv.evaluateJavascript("window.__glyph && window.__glyph.screenOff ? (window.__glyph.screenOff(), 'ok') : 'no'", null)
      }
    }
  }
  private var capturing = false

  private fun setCapturingNow(on: Boolean) {
    if (on == capturing) return
    capturing = on
    if (on) {
      window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      // Not exported: only the system sends SCREEN_OFF, and it has to be
      // registered at run time; a manifest entry is never delivered.
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF), Context.RECEIVER_NOT_EXPORTED)
      } else {
        @Suppress("UnspecifiedRegisterReceiverFlag")
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
      }
    } else {
      window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      try {
        unregisterReceiver(screenOff)
      } catch (_: IllegalArgumentException) {
        // Never registered: nothing to take back.
      }
    }
  }

  override fun onDestroy() {
    setCapturingNow(false)
    super.onDestroy()
  }

  /** Decodes `uri` at a sample size that keeps memory sane, rotates it per EXIF, caps the long side, writes a JPEG. */
  private fun shrinkPicture(uri: Uri): File {
    val resolver = contentResolver
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    val longest = maxOf(bounds.outWidth, bounds.outHeight).coerceAtLeast(1)
    var sample = 1
    while (longest / (sample * 2) >= PICTURE_MAX_PX) sample *= 2
    val decoded = resolver.openInputStream(uri)?.use {
      BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
    } ?: throw IllegalStateException("decode failed")
    val rotation = resolver.openInputStream(uri)?.use { stream ->
      when (ExifInterface(stream).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
        ExifInterface.ORIENTATION_ROTATE_90 -> 90f
        ExifInterface.ORIENTATION_ROTATE_180 -> 180f
        ExifInterface.ORIENTATION_ROTATE_270 -> 270f
        else -> 0f
      }
    } ?: 0f
    val scale = minOf(1f, PICTURE_MAX_PX.toFloat() / maxOf(decoded.width, decoded.height))
    val matrix = Matrix().apply {
      if (scale < 1f) postScale(scale, scale)
      if (rotation != 0f) postRotate(rotation)
    }
    val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
    // Where `save_image` adopts from: `PICKED` in src-tauri/src/paths.rs. Rename both together.
    val dir = File(cacheDir, "picked").apply { mkdirs() }
    val out = File(dir, "${UUID.randomUUID()}.jpg")
    FileOutputStream(out).use { upright.compress(Bitmap.CompressFormat.JPEG, 85, it) }
    return out
  }

  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    // Location's own answer (location/LocationAccess.kt, native generation 20): kept, and the page reads the state again.
    if (LocationAccess.answered(this, requestCode, grantResults, webView)) return
    when (requestCode) {
      REQUEST_NOTIFICATIONS -> webView?.let { wv ->
        runOnUiThread { wv.evaluateJavascript("window.__glyph && window.__glyph.alerts && window.__glyph.alerts()", null) }
      }
      // Meetings' own answer, its own inbound call: `alerts` belongs to update alerts and is never reused.
      REQUEST_MEETING_NOTIFICATIONS -> webView?.let { wv ->
        runOnUiThread { wv.evaluateJavascript("window.__glyph && window.__glyph.notified && window.__glyph.notified()", null) }
      }
      REQUEST_MICROPHONE -> {
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        // After a dialog this callback comes before onResume, which delivers the answer, so the page's retry
        // starts the service with the activity resumed. With no dialog (refused twice before, Android answers on
        // the spot) the activity never left the front and no resume follows: the answer goes now.
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) deliverPermission(granted) else pendingPermission = granted
      }
    }
  }

  /**
   * The meeting's service started for `noteId`, on the UI thread with the activity in front, carrying the
   * screen-share consent's answer when other apps' sound was asked for (MeetingService `projectionOf`).
   */
  private fun launchMeeting(noteId: String, title: String, projection: ProjectionAnswer?) {
    val intent = Intent(this, MeetingService::class.java)
      .setAction(MeetingService.ACTION_START)
      .putExtra(MeetingService.EXTRA_NOTE_ID, noteId)
      .putExtra(MeetingService.EXTRA_TITLE, title)
    if (projection != null) {
      intent.putExtra(MeetingService.EXTRA_PROJECTION_CODE, projection.code)
      if (projection.data != null) intent.putExtra(MeetingService.EXTRA_PROJECTION_DATA, projection.data)
    }
    try {
      ContextCompat.startForegroundService(this, intent)
    } catch (error: Exception) {
      // Android 12+ refuses a foreground start from an app it does not see in front; the page undoes the note.
      Log.w(TAG, "the meeting service could not start", error)
      tell("meeting", JSONObject().put("event", "failed").put("noteId", noteId).put("elapsedMs", 0).put("message", "The meeting could not start.").toString())
    }
  }

  /** The microphone's answer to the page, `meeting { event: "permission", noteId, granted }`. */
  private fun deliverPermission(granted: Boolean) {
    val noteId = microphoneFor
    microphoneFor = null
    tell("meeting", JSONObject().put("event", "permission").put("noteId", noteId ?: JSONObject.NULL).put("elapsedMs", 0).put("granted", granted).toString())
  }

  override fun onWebViewCreate(webView: WebView) {
    super.onWebViewCreate(webView)
    this.webView = webView
    webView.addJavascriptInterface(GlyphHost(), "GlyphHost")
    fitAboveKeyboard(webView)
    /*
     * The back gesture, routed into the app instead of out of it.
     *
     * TauriActivity opts out of wry's own back handling (handleBackNavigation
     * = false), so with no callback of our own a back swipe fell through to the
     * framework default, finish(): the whole app closed from an open note. The
     * page is the only side that knows what is on screen - a note, the settings
     * page and a pane inside it, the guide - so the gesture is handed to it
     * (window.__glyph.back, core/back.ts), which steps back one screen and
     * answers true, or answers false at the list. At the list the app goes
     * behind the home screen like any other; it is never finished, so the
     * side key's next press finds it warm. The same shape as AttackFM's.
     */
    onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
      override fun handleOnBackPressed() {
        val wv = this@MainActivity.webView
        if (wv == null) {
          moveTaskToBack(true)
          return
        }
        wv.evaluateJavascript("window.__glyph && window.__glyph.back ? window.__glyph.back() : false") { result ->
          // The JSON of the expression: "true" when the page used the gesture.
          // Anything else - false, null from a page still loading - is the root.
          if (result != "true") moveTaskToBack(true)
        }
      }
    })
  }

  private fun isCapture(intent: Intent?): Boolean =
    intent?.action == ACTION_CAPTURE || intent?.action == Intent.ACTION_ASSIST

  /**
   * The recording notification tapped: a plain launch carrying EXTRA_MEETING.
   * Cold, the page reads "meeting" through `takeLaunch` and opens the meeting
   * screen; warm, it is pushed as `meeting { event: "open" }`.
   */
  private fun takeMeeting(intent: Intent?): Boolean {
    if (intent?.getBooleanExtra(EXTRA_MEETING, false) != true) return false
    pendingLaunch = "meeting"
    return true
  }

  /** Push a warm meeting tap to a running page, the way deliverCapture does; held for `takeLaunch` until the page says it took it. */
  private fun deliverMeeting() {
    val wv = webView ?: return
    val json = JSONObject.quote(JSONObject().put("event", "open").put("noteId", MeetingService.recordingNoteId() ?: JSONObject.NULL).put("elapsedMs", 0).toString())
    runOnUiThread {
      wv.onResume()
      wv.evaluateJavascript("window.__glyph && window.__glyph.meeting ? (window.__glyph.meeting($json), 'ok') : 'no'") { result ->
        if (result == "\"ok\"") pendingLaunch = null
        else Log.i(TAG, "meeting held: page not ready ($result)")
      }
    }
  }

  /** A `ghostmd://` link on the intent, kept for `takeLink` (the deep-link plugin's copy reaches the page when its channel is up). */
  private fun takeLink(intent: Intent?) {
    val link = intent?.data?.takeIf { it.scheme == "ghostmd" } ?: return
    pendingLink = link.toString()
  }

  /**
   * Record the request and let this one launch show over the lock screen.
   *
   * Showing over the keyguard is granted per capture and taken back when it ends
   * (see `GlyphHost.endCapture`), never left on. A notes app that stayed visible
   * over the lock screen would hand every note to anyone holding the phone; a
   * capture screen that shows only the note being dictated does not.
   */
  private fun takeCapture(intent: Intent?): Boolean {
    if (!isCapture(intent)) return false
    pendingLaunch = "capture"
    setLockScreenCapture(true)
    return true
  }

  private fun setLockScreenCapture(on: Boolean) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      setShowWhenLocked(on)
      setTurnScreenOn(on)
    } else {
      @Suppress("DEPRECATION")
      val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
      if (on) window.addFlags(flags) else window.clearFlags(flags)
    }
  }

  /**
   * Push a warm capture to a page that is already running.
   *
   * The WebView is resumed first because a backgrounded one is paused, and a
   * paused WebView QUEUES evaluateJavascript rather than running it - AttackFM
   * measured that the hard way. The request is only cleared once the page says
   * it took it; if the page is mid-reload, it stays pending and the page
   * collects it through `takeLaunch` as it boots.
   */
  private fun deliverCapture() {
    val wv = webView ?: return
    runOnUiThread {
      wv.onResume()
      wv.evaluateJavascript(
        "window.__glyph && window.__glyph.capture ? (window.__glyph.capture(), 'ok') : 'no'",
      ) { result ->
        if (result == "\"ok\"") pendingLaunch = null
        else Log.i(TAG, "capture held: page not ready ($result)")
      }
    }
  }

  /**
   * The page ends where the keyboard begins.
   *
   * `enableEdgeToEdge` draws the page under the system bars, which the page
   * pads for itself (env(safe-area-inset-*)), and on Android 15 and later the
   * old `adjustResize` no longer shrinks an edge-to-edge window for the
   * keyboard. So the keyboard simply covered the note: a line tapped near the
   * bottom stayed under it, typing included (measured on the emulator), and
   * the caret could not be scrolled to. Now, while the keyboard is up, the
   * content frame is padded by its height, so the WebView is that much
   * shorter: the page sees an ordinary resize, and the editor keeps the caret
   * in view (editor/Editor.tsx). Native generation 15.
   */
  private fun fitAboveKeyboard(webView: WebView) {
    // On the frame around the WebView, never on the WebView itself: the WebView
    // listens for its own insets to give the page env(safe-area-inset-*), and a
    // listener set on it replaces that one (the header slid under the clock).
    // The insets go on down unchanged; only the frame's padding moves.
    val frame = (webView.parent as? View) ?: findViewById<View>(android.R.id.content) ?: return
    ViewCompat.setOnApplyWindowInsetsListener(frame) { view, insets ->
      val keyboard = if (insets.isVisible(WindowInsetsCompat.Type.ime())) insets.getInsets(WindowInsetsCompat.Type.ime()).bottom else 0
      if (view.paddingBottom != keyboard) view.setPadding(view.paddingLeft, view.paddingTop, view.paddingRight, keyboard)
      insets
    }
    ViewCompat.requestApplyInsets(frame)
  }

  /** The page's line to the activity. Every method is called on the JavaBridge thread. */
  inner class GlyphHost {
    /**
     * The status and navigation bar icons, dark on a light page or light on a
     * dark one. `enableEdgeToEdge` picks them from the phone's dark mode, so
     * Glyph's own Light or Dark setting left them white on white paper, or
     * black on black. The page calls this whenever its theme settles. Native
     * generation 15.
     */
    @JavascriptInterface
    fun setLightChrome(light: Boolean) {
      runOnUiThread {
        WindowCompat.getInsetsController(window, window.decorView).apply {
          isAppearanceLightStatusBars = light
          isAppearanceLightNavigationBars = light
        }
        // The text selection handles follow the app's theme, not the phone's: black on the light page, white on the
        // dark, each with its holographic sheen (res/drawable/glyph_handle_*). The WebView reads them from the
        // activity's theme as it draws a handle, so the next selection picks them up.
        theme.applyStyle(if (light) R.style.GlyphHandles_Ink else R.style.GlyphHandles_Paper, true)
      }
    }

    /**
     * Opens the notes' folder in the phone's Files app (files/LibraryDocuments.kt): the Files app shown at Ghost.md's
     * place in it, or where a phone's Files app won't open a place by itself, the system's file browser starting there.
     * Native generation 18.
     */
    @JavascriptInterface
    fun browseFiles() {
      runOnUiThread {
        val authority = com.mattssoftware.glyph.files.LibraryDocuments.authority(packageName)
        val root = android.provider.DocumentsContract.buildRootUri(authority, com.mattssoftware.glyph.files.LibraryDocuments.ROOT_ID)
        try {
          startActivity(
            Intent(Intent.ACTION_VIEW)
              .setDataAndType(root, android.provider.DocumentsContract.Root.MIME_TYPE_ITEM)
              .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
          )
        } catch (notOpened: ActivityNotFoundException) {
          val start = android.provider.DocumentsContract.buildDocumentUri(authority, com.mattssoftware.glyph.files.LibraryDocuments.rootDocumentId())
          try {
            startActivity(
              Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
                .putExtra(android.provider.DocumentsContract.EXTRA_INITIAL_URI, start),
            )
          } catch (e: ActivityNotFoundException) {
            Log.w("Glyph", "no file browser to show the library in", e)
          }
        }
      }
    }

    /** "capture" once, if a capture launch is waiting; otherwise "". */
    @JavascriptInterface
    fun takeLaunch(): String {
      val launch = pendingLaunch ?: ""
      pendingLaunch = null
      return launch
    }

    /**
     * Whether the phone is locked right now. The page asks before deciding
     * where to go when a capture ends: straight back to the lock screen, or on
     * into the note.
     */
    @JavascriptInterface
    fun isLocked(): Boolean =
      (getSystemService(KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked

    /**
     * The capture is over. Withdraw the lock-screen permission, and when the
     * phone is locked, step back behind the keyguard so the saved note is not
     * left on display.
     */
    /**
     * A recording started or ended: keep the screen on while it runs, and
     * listen for it going off, which is the side key pressed to stop
     * (native generation 12).
     */
    @JavascriptInterface
    fun setCapturing(on: Boolean) {
      runOnUiThread { setCapturingNow(on) }
    }

    @JavascriptInterface
    fun endCapture(leave: Boolean) {
      runOnUiThread {
        setLockScreenCapture(false)
        if (leave) moveTaskToBack(true)
      }
    }

    /**
     * Whether Glyph is the digital assistant app. That is what pressing and
     * holding the side key opens once Samsung's side-key setting is on
     * "Digital assistant". The guide's side-key page asks this to show its
     * tick, and asks again when the person comes back from settings.
     *
     * On Android 10 and up this is the assistant role. Older versions have no
     * roles; there the assistant is the component in the secure "assistant"
     * setting. Reading that setting is wrapped because a settings key Android
     * has not made public can throw instead of returning null.
     */
    @JavascriptInterface
    fun isAssistant(): Boolean {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val roles = getSystemService(RoleManager::class.java) ?: return false
        return roles.isRoleAvailable(RoleManager.ROLE_ASSISTANT) && roles.isRoleHeld(RoleManager.ROLE_ASSISTANT)
      }
      return try {
        val assistant = Settings.Secure.getString(contentResolver, "assistant") ?: return false
        ComponentName.unflattenFromString(assistant)?.packageName == packageName
      } catch (e: SecurityException) {
        false
      }
    }

    /**
     * Opens the settings screen closest to choosing the digital assistant
     * app. Returns true if a screen opened.
     *
     * An app cannot ask for the assistant role with a system dialog, the way it
     * can for the dialer or SMS roles, because that role is not requestable. So
     * the best Glyph can do is open the right settings page: voice input
     * settings, where stock Android puts the assistant choice, or the default
     * apps list, which every phone since Android 7 has. Starting the activity
     * happens on the main thread and the bridge thread waits for the result.
     * The page's JavaScript is blocked meanwhile, but the main thread never is.
     */
    @JavascriptInterface
    fun openAssistantSettings(): Boolean {
      val screens = listOf(Settings.ACTION_VOICE_INPUT_SETTINGS, Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
      val opened = AtomicBoolean(false)
      val done = CountDownLatch(1)
      runOnUiThread {
        try {
          opened.set(
            screens.any { action ->
              try {
                startActivity(Intent(action))
                true
              } catch (e: ActivityNotFoundException) {
                false
              }
            },
          )
        } finally {
          done.countDown()
        }
      }
      return done.await(2, TimeUnit.SECONDS) && opened.get()
    }

    /** `Build.MANUFACTURER`, e.g. "samsung", so the guide shows that maker's side-key steps. */
    @JavascriptInterface
    fun deviceMaker(): String = Build.MANUFACTURER ?: ""

    // Location (native generation 20): whether the app may know where the phone is, and the ask; location/LocationAccess.kt.
    @JavascriptInterface
    fun locationAccess(): String = LocationAccess.state(this@MainActivity)
    @JavascriptInterface
    fun requestLocation() { runOnUiThread { LocationAccess.request(this@MainActivity) } }
    @JavascriptInterface
    fun openLocationSettings(): Boolean = LocationAccess.openSettings(this@MainActivity)

    /**
     * Hand a downloaded APK to Android's package installer.
     *
     * The page cannot do this and Rust has no Context to do it with, so the
     * download and its SHA-256 check happen in Rust (`ota_fetch_apk`) and only
     * the last step is here. Android then shows its own "update this app?"
     * screen, which no sideloaded app can skip, and replaces the process.
     *
     * Only a file inside `cacheDir/updates` is accepted. This method is callable
     * by anything running in the page, and without the check it would be a way
     * to hand any readable file to a content URI.
     *
     * The first time, Android also wants Glyph allowed to install apps. That is
     * a settings page, not a prompt, so this opens it and answers "permission";
     * the page asks the person to come back and tap Install again.
     */
    /** Update alerts: "off", "on", or "blocked" (on, but notifications are not allowed). */
    @JavascriptInterface
    fun updateAlerts(): String = UpdateAlerts.state(this@MainActivity)

    /**
     * Turn update alerts on or off, answering the new state. Turning them on
     * where Android 13+ has not yet allowed notifications asks for that too;
     * the answer arrives later (onRequestPermissionsResult), so the page reads
     * "blocked" now and is told to look again.
     */
    @JavascriptInterface
    fun setUpdateAlerts(on: Boolean): String {
      if (!on) {
        UpdateAlerts.disable(this@MainActivity)
        return UpdateAlerts.state(this@MainActivity)
      }
      UpdateAlerts.enable(this@MainActivity)
      if (!UpdateAlerts.canNotify(this@MainActivity) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        runOnUiThread { requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS) }
      }
      return UpdateAlerts.state(this@MainActivity)
    }

    /**
     * Pictures (native generation 8): open the phone's picture picker. The
     * answer arrives later as an `image` event; see onActivityResult.
     */
    @JavascriptInterface
    fun pickImage(): String {
      val intent = Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
      return try {
        runOnUiThread { startActivityForResult(Intent.createChooser(intent, "Choose a picture"), REQUEST_PICTURE) }
        "started"
      } catch (error: ActivityNotFoundException) {
        "This phone has no picture picker."
      }
    }

    /**
     * A film for a note (native generation 21): opens the Photo Picker for a
     * video, no permission asked. "started"; the film, copied with its poster,
     * arrives later as a `video` event (media/VideoPick.kt).
     */
    @JavascriptInterface
    fun pickVideo(): String = VideoPick.start(this@MainActivity, ::tellVideo)

    /**
     * Where to export everything (native generation 22; files/ExportTarget.kt): the system's picker, making a zip of
     * this name wherever is chosen, a USB drive among the places. "started"; the descriptor arrives as an
     * `exportTarget` event, and so does a picker that would not open, as `{ error }`.
     */
    @JavascriptInterface
    fun chooseExport(name: String): String = ExportTarget.start(this@MainActivity, name, ::tellExport)

    /** The export failed or was stopped: the half-written file the picker made goes. */
    @JavascriptInterface
    fun discardExport() = ExportTarget.discard(this@MainActivity)

    /** The export is whole, and the file stays. */
    @JavascriptInterface
    fun exportDone() = ExportTarget.done()

    /**
     * What is on the clipboard, for the editor's own Paste (its press-and-hold
     * menu): the page cannot read the clipboard itself in the WebView. JSON:
     * `{ "text": … }` for words, `{ "path": … }` for a picture (shrunk and
     * turned the right way up into cacheDir/picked/, the way the picker does,
     * for `save_image` to adopt), `{ "error": … }` when a picture could not be
     * read, `{}` when there is nothing. Native generation 12.
     */
    @JavascriptInterface
    fun readClipboard(): String {
      // A page's call arrives on a binder thread, and the clipboard is the UI thread's to read: asked from here it
      // can come back empty or throw, and the note's Paste then did nothing at all. What is on it is taken on the UI
      // thread and waited for - briefly, and never from the UI thread itself, which would wait on work only it can
      // do. A picture is shrunk back here, off it.
      val clip =
        if (Looper.myLooper() == Looper.getMainLooper()) {
          clipboardNow()
        } else {
          val answer = java.util.concurrent.ArrayBlockingQueue<Array<String?>>(1)
          runOnUiThread { answer.offer(clipboardNow()) }
          answer.poll(500, java.util.concurrent.TimeUnit.MILLISECONDS)
        }
      if (clip == null) {
        Log.w(TAG, "clipboard read timed out")
        return "{}"
      }
      val uri = clip[0]?.let { Uri.parse(it) }
      if (uri != null && (contentResolver.getType(uri) ?: "").startsWith("image/")) {
        return try {
          JSONObject().put("path", shrinkPicture(uri).absolutePath).toString()
        } catch (error: Exception) {
          Log.w(TAG, "clipboard picture unreadable", error)
          JSONObject().put("error", "That picture couldn't be read from the clipboard.").toString()
        }
      }
      val text = clip[1].orEmpty()
      // Since Android 10 the clipboard only answers an app that holds focus, and a refusal reads as nothing at all:
      // logged so an empty paste can be told apart from an empty clipboard (logcat -s ClipboardService says which).
      if (text.isEmpty()) Log.i(TAG, "clipboard read came back empty (uri=${clip[0] != null})")
      return if (text.isEmpty()) "{}" else JSONObject().put("text", text).toString()
    }

    /** The first thing on the clipboard as `[uri, words]`, read on the UI thread where the clipboard belongs. */
    private fun clipboardNow(): Array<String?> {
      val empty = arrayOf<String?>(null, null)
      val clipboard = getSystemService(CLIPBOARD_SERVICE) as? ClipboardManager ?: return empty
      val clip = clipboard.primaryClip ?: return empty
      if (clip.itemCount == 0) return empty
      val item = clip.getItemAt(0)
      return arrayOf(item.uri?.toString(), item.coerceToText(this@MainActivity)?.toString())
    }

    @JavascriptInterface
    fun installApk(path: String): String {
      // A copy from a store updates through the store, and Play forbids installing APKs (build.gradle.kts, GLYPH_STORE).
      if (BuildConfig.STORE.isNotEmpty()) return "store"
      // Where `ota_fetch_apk` downloads to: `UPDATES` in src-tauri/src/paths.rs. Rename both together.
      val updates = File(cacheDir, "updates").canonicalFile
      val apk = File(path).canonicalFile
      if (apk.parentFile != updates || !apk.name.endsWith(".apk") || !apk.isFile) return "not an update"
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
        runOnUiThread {
          startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
              .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
          )
        }
        return "permission"
      }
      return try {
        // The provider and its `cache-path` entry come from Tauri's template
        // (res/xml/file_paths.xml), which already covers cacheDir.
        val uri = FileProvider.getUriForFile(this@MainActivity, "$packageName.fileprovider", apk)
        val intent = Intent(Intent.ACTION_VIEW)
          .setDataAndType(uri, "application/vnd.android.package-archive")
          .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        runOnUiThread { startActivity(intent) }
        "started"
      } catch (error: Exception) {
        Log.w(TAG, "installApk failed", error)
        error.javaClass.simpleName
      }
    }

    /*
     * Meetings (native generation 20): a recording that keeps going with the
     * screen off, in capture/MeetingService.kt, and the write-up that follows
     * it with the app closed. The page makes the note first and then asks here;
     * everything below answers from what can be checked on this thread and
     * posts the rest to the UI thread, where a foreground service may be
     * started while the app is in front.
     */

    /**
     * Start recording a meeting into `noteId`'s tape. "started" (the service was
     * asked; `meeting { event: "started" }` confirms it and `failed` undoes it),
     * "permission" (the microphone was asked for with REQUEST_MICROPHONE; the
     * page retries on `meeting { event: "permission", granted: true }`),
     * "recording" (one is being recorded already), or a reason: the last
     * meeting's Stop still being put away is one, said in the app's words,
     * since its bookkeeping would clear a meeting started under it.
     */
    @JavascriptInterface
    fun startMeeting(noteId: String, title: String): String {
      if (!isNoteId(noteId)) return "not a note id"
      if (MeetingService.isRecording()) return "recording"
      if (MeetingService.isEnding()) return MeetingService.STILL_STOPPING
      if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
        microphoneFor = noteId
        runOnUiThread { requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_MICROPHONE) }
        return "permission"
      }
      runOnUiThread { launchMeeting(noteId, title, null) }
      return "started"
    }

    /**
     * As `startMeeting`, with other apps' sound in the meeting when `otherApps` is set (native generation 25; the
     * page's "Include sound from other apps"). The microphone is asked for first, as above; then Android's
     * screen-share consent, the whole screen on Android 14 and later so the dialog does not offer a single app's,
     * and the service starts once it is answered (onResume), declined or not: a meeting asked for is recorded, and
     * its screen says when it is the microphone alone. Below Android 10, or with the switch off, it is `startMeeting`.
     */
    @JavascriptInterface
    fun startMeetingWith(noteId: String, title: String, otherApps: Boolean): String {
      if (!otherApps || OtherApps.unsupported() != null) return startMeeting(noteId, title)
      if (!isNoteId(noteId)) return "not a note id"
      if (MeetingService.isRecording()) return "recording"
      if (MeetingService.isEnding()) return MeetingService.STILL_STOPPING
      if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
        microphoneFor = noteId
        runOnUiThread { requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_MICROPHONE) }
        return "permission"
      }
      projectionFor = noteId to title
      runOnUiThread {
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val ask = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
          manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
          manager.createScreenCaptureIntent()
        }
        try {
          startActivityForResult(ask, REQUEST_PROJECTION)
        } catch (error: Exception) {
          Log.w(TAG, "the screen-share consent could not be asked", error)
          projectionFor = null
          launchMeeting(noteId, title, ProjectionAnswer(noteId, title, RESULT_CANCELED, null))
        }
      }
      return "started"
    }

    /** `{ supported, reason }`: whether this phone can put other apps' sound in a meeting (Android 10+). */
    @JavascriptInterface
    fun meetingSound(): String {
      val reason = OtherApps.unsupported()
      return JSONObject().put("supported", reason == null).put("reason", reason ?: JSONObject.NULL).toString()
    }

    /** Done: the service stops recording and carries on as the write-up. */
    @JavascriptInterface
    fun stopMeeting() {
      MeetingService.stop()
    }

    /** Discard: the service stops and deletes the WAV; the page deletes the note itself. */
    @JavascriptInterface
    fun discardMeeting() {
      MeetingService.discard()
    }

    /** `{ recording, noteId, title, startedAt, elapsedMs, silenced, writingUp, discarded }`, polled once a second while the page is visible. */
    @JavascriptInterface
    fun meetingState(): String = MeetingService.meetingState(this@MainActivity)

    /**
     * Ask to post notifications, for "Let Ghost.md tell you when it is written
     * up". "allowed", "asked" (the answer arrives as `window.__glyph.notified()`),
     * or "blocked" (refused for good, or notifications off for the app: the
     * meeting screen then says to stop it there). Never touches update alerts.
     */
    @JavascriptInterface
    fun requestNotifications(): String {
      if (RecordingAlerts.canNotify(this@MainActivity)) return "allowed"
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return "blocked"
      val permission = Manifest.permission.POST_NOTIFICATIONS
      // Granted and still not able to notify: turned off in the phone's settings, which no dialog changes.
      if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return "blocked"
      // Refused twice: Android shows no third dialog, and asking would answer nothing.
      if (RecordingAlerts.wasAsked(this@MainActivity) && !shouldShowRequestPermissionRationale(permission)) return "blocked"
      RecordingAlerts.rememberAsked(this@MainActivity)
      runOnUiThread { requestPermissions(arrayOf(permission), REQUEST_MEETING_NOTIFICATIONS) }
      return "asked"
    }

    /** Whether a written-up notification would be shown: the permission, the app's switch and the channel all on. */
    @JavascriptInterface
    fun canNotify(): Boolean = RecordingAlerts.canNotify(this@MainActivity)

    /**
     * The bell's rows on the phone (native generation 23; notices/NoticeAlerts.kt): the session and switches the
     * worker needs while the app is closed, as JSON, or "" to stop watching (signed out, or the switch turned off).
     * Answers "off", "on" or "blocked" (watched, but Android will not show them: the page offers to ask).
     */
    @JavascriptInterface
    fun watchNotices(json: String): String {
      try {
        if (json.isBlank()) NoticeAlerts.unwatch(this@MainActivity) else NoticeAlerts.watch(this@MainActivity, json)
      } catch (error: Throwable) {
        Log.w(TAG, "notices watch refused", error)
      }
      return NoticeAlerts.state(this@MainActivity)
    }

    /**
     * One row as a phone notification, from the page while it runs in the background: JSON `{ id, title, text?,
     * link }`. "posted", "seen" (posted before, by either road), "blocked", or a reason.
     */
    @JavascriptInterface
    fun postNotice(json: String): String = try {
      val notice = JSONObject(json)
      NoticeAlerts.post(this@MainActivity, notice.getString("id"), notice.getString("title"), notice.optString("text").ifEmpty { null }, notice.optString("link"))
    } catch (error: Throwable) {
      "could not read the notice"
    }

    /** "off", "on" or "blocked", for the Notifications page's phone row. */
    @JavascriptInterface
    fun noticesState(): String = NoticeAlerts.state(this@MainActivity)

    /**
     * Write `noteId` up (again): "Write up now", Try again, restore from the
     * trash, a model arrived. One request at the end of the chain, fresh, with
     * `now` skipping the battery rule. "queued", or a reason.
     */
    @JavascriptInterface
    fun writeUp(noteId: String, now: Boolean): String {
      if (!isNoteId(noteId)) return "not a note id"
      val context = applicationContext
      writeUpDoor.execute { RecordingWorker.enqueue(context, noteId, null, now, fresh = true) }
      return "queued"
    }

    /**
     * The note went to the trash: its write-up is cancelled through Rust alone,
     * never through WorkManager (cancelling one member of the chain would cancel
     * everything queued after it); the worker that reaches the id later finds
     * the job cancelled and moves on.
     */
    @JavascriptInterface
    fun cancelWriteUp(noteId: String) {
      if (!isNoteId(noteId)) return
      val dataDir = dataDir.absolutePath
      writeUpDoor.execute {
        try {
          RecordingJob.cancel(dataDir, noteId, "cancel")
        } catch (error: Throwable) {
          Log.w(TAG, "cancelWriteUp failed", error)
        }
      }
    }

    /**
     * Reset, before `reset_local_data`: both unique works whole, then any run
     * in hand, waited for here on the bridge thread (at most five seconds a
     * run). The page's call returns only once the run has let go and marked its
     * file, so Rust's reset removes the jobs folder after the last write to it,
     * not before one that would leave a file behind.
     */
    @JavascriptInterface
    fun cancelWriteUps() {
      RecordingWorker.cancelAll(this@MainActivity)
      val dataDir = dataDir.absolutePath
      for (id in listOfNotNull(MeetingService.writingUp, RecordingWorker.running).distinct()) {
        try {
          RecordingJob.cancel(dataDir, id, "cancel")
        } catch (error: Throwable) {
          Log.w(TAG, "cancelWriteUps failed for $id", error)
        }
      }
    }

    /** The page has deleted a note the notification's Discard threw away. */
    @JavascriptInterface
    fun forgetDiscarded(noteId: String) {
      MeetingService.forgetDiscarded(this@MainActivity, noteId)
    }

    /** A `ghostmd://` link this activity was opened with, once; "" otherwise. */
    @JavascriptInterface
    fun takeLink(): String {
      val link = pendingLink ?: ""
      pendingLink = null
      return link
    }

    /** The shape Rust's `fsx::plain_id` accepts (1 to `PLAIN_ID_MAX`, 128, of these); an id that fails it names no file and starts nothing. */
    private fun isNoteId(id: String): Boolean = id.length in 1..128 && id.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_' }
  }
}
