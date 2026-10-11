package com.mattssoftware.ghost_md

import android.Manifest
import android.app.Activity
import android.app.KeyguardManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.content.ContextCompat
import com.mattssoftware.glyph.capture.MeetingService
import com.mattssoftware.glyph.capture.OtherApps
import com.mattssoftware.glyph.recordings.RecordingAlerts
import com.mattssoftware.glyph.recordings.RecordingJob
import com.mattssoftware.glyph.recordings.RecordingWorker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Meetings, the write-up and the capture launch, as the Flutter app asks for them: what `window.GlyphHost`'s
 * meeting methods and `window.__glyph`'s inbound calls were to the Tauri app's page
 * (../glyph/src-tauri/gen/android/…/MainActivity.kt, the `@JavascriptInterface` block), method for method, with the
 * same words answered. lib/capture/meeting_host.dart is the other side.
 *
 * THE CHANNEL `ghost_md/meeting` (every answer is the Tauri bridge's own):
 * - `startMeeting {noteId, title}` -> "started" | "permission" | "recording" | a reason in the app's words.
 * - `startMeetingWith {noteId, title, otherApps}` -> the same, asking for the screen-share consent first.
 * - `meetingSound` -> JSON `{supported, reason}`.
 * - `stopMeeting`, `discardMeeting` -> null.
 * - `meetingState` -> JSON `{recording, noteId, title, startedAt, elapsedMs, silenced, otherApps, otherAppsHeard,
 *   otherAppsNote, writingUp, discarded}`.
 * - `requestNotifications` -> "allowed" | "asked" | "blocked"; `canNotify` -> bool.
 * - `writeUp {noteId, now}` -> "queued" | a reason; `cancelWriteUp {noteId}` -> null; `cancelWriteUps` -> null,
 *   once every run has let go; `forgetDiscarded {noteId}` -> null.
 * - `takeLaunch` -> "capture" | "meeting" | "": what this launch was for, once.
 * - `isLocked` -> bool; `setCapturing {on}` -> null (the screen kept on, and its going off heard);
 *   `endCapture {leave}` -> null.
 * - `isAssistant` -> bool; `openAssistantSettings` -> bool; `deviceMaker` -> String; `assistantEnabled` -> whether
 *   this build has the phone assistant at all (`@bool/ghost_assistant`).
 *
 * THE EVENTS on `ghost_md/meeting/events`, each `{name, argument}` where the Tauri page was called
 * `window.__glyph.<name>(argument)`:
 * - `meeting`: JSON `{event, noteId, elapsedMs, reason?, granted?, message?}`; `event` is started, silenced,
 *   sounding, stopped, failed, discarded, permission or open.
 * - `recordingDone`: JSON `{id, outcome}`, a write-up ended while the app was in front.
 * - `notified`: the notification prompt was answered. `capture`: a capture launch arrived while the app was open.
 *   `screenOff`: the screen went off during a dictation (the side key pressed to stop). `unlocked`: the phone was
 *   unlocked during a dictation. The Tauri page asked `isLocked()` at each use and was answered at once; a channel
 *   answers a moment later, so the app keeps the last answer, and this tells it the one moment that answer goes
 *   stale while a take runs (a take begun over the lock screen and unlocked ends as any other does).
 */
class MeetingBridge(private val activity: Activity) {
  companion object {
    const val CHANNEL = "ghost_md/meeting"
    const val EVENTS = "ghost_md/meeting/events"
    private const val TAG = "GhostMeeting"
    private const val REQUEST_MEETING_NOTIFICATIONS = 4103
    private const val REQUEST_MICROPHONE = 4104
    private const val REQUEST_PROJECTION = 4105

    /** The trash's cancel and the write-up's request, one after the other in the order the app made them. */
    private val writeUpDoor: ExecutorService by lazy { Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "glyph-write-up-door") } }
  }

  /** Whoever listens on the event channel now, or null: the page's handler, in the Tauri app's words. */
  @Volatile var sink: EventChannel.EventSink? = null
    private set

  @Volatile private var pendingLaunch: String? = null
  @Volatile private var pendingPermission: Boolean? = null
  @Volatile private var microphoneFor: String? = null
  @Volatile private var projectionFor: Pair<String, String>? = null

  private class ProjectionAnswer(val noteId: String, val title: String, val code: Int, val data: Intent?)
  @Volatile private var pendingProjection: ProjectionAnswer? = null
  private var resumed = false
  private var capturing = false

  /** Whether this build has the phone assistant and the capture launch at all (res/values/voice_assistant.xml). */
  private val assistant: Boolean get() = activity.resources.getBoolean(R.bool.ghost_assistant)

  fun register(messenger: BinaryMessenger) {
    EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
      override fun onCancel(arguments: Any?) { sink = null }
    })
    MethodChannel(messenger, CHANNEL).setMethodCallHandler(::answer)
  }

  /** One event to Dart, on the main thread; false when nobody is listening. */
  fun say(name: String, argument: String?): Boolean {
    val listener = sink ?: return false
    listener.success(mapOf("name" to name, "argument" to argument))
    return true
  }

  private fun answer(call: MethodCall, result: MethodChannel.Result) {
    val noteId = call.argument<String>("noteId") ?: ""
    when (call.method) {
      "startMeeting" -> result.success(startMeeting(noteId, call.argument<String>("title") ?: ""))
      "startMeetingWith" -> result.success(startMeetingWith(noteId, call.argument<String>("title") ?: "", call.argument<Boolean>("otherApps") == true))
      "meetingSound" -> {
        val reason = OtherApps.unsupported()
        result.success(JSONObject().put("supported", reason == null).put("reason", reason ?: JSONObject.NULL).toString())
      }
      "stopMeeting" -> {
        MeetingService.stop()
        result.success(null)
      }
      "discardMeeting" -> {
        MeetingService.discard()
        result.success(null)
      }
      "meetingState" -> result.success(MeetingService.meetingState(activity))
      "requestNotifications" -> result.success(requestNotifications())
      "canNotify" -> result.success(RecordingAlerts.canNotify(activity))
      "writeUp" -> {
        if (!isNoteId(noteId)) return result.success("not a note id")
        val context = activity.applicationContext
        val now = call.argument<Boolean>("now") == true
        writeUpDoor.execute { RecordingWorker.enqueue(context, noteId, null, now, fresh = true) }
        result.success("queued")
      }
      "cancelWriteUp" -> {
        if (isNoteId(noteId)) {
          val dataDir = activity.dataDir.absolutePath
          writeUpDoor.execute {
            try {
              RecordingJob.cancel(dataDir, noteId, "cancel")
            } catch (error: Throwable) {
              Log.w(TAG, "cancelWriteUp failed", error)
            }
          }
        }
        result.success(null)
      }
      "cancelWriteUps" -> {
        // The Tauri bridge waited on its own thread; this channel answers on the main one, so the wait (at most
        // five seconds a run) is the door's, and the answer follows it.
        val context = activity.applicationContext
        val dataDir = activity.dataDir.absolutePath
        writeUpDoor.execute {
          RecordingWorker.cancelAll(context)
          for (id in listOfNotNull(MeetingService.writingUp, RecordingWorker.running).distinct()) {
            try {
              RecordingJob.cancel(dataDir, id, "cancel")
            } catch (error: Throwable) {
              Log.w(TAG, "cancelWriteUps failed for $id", error)
            }
          }
          activity.runOnUiThread { result.success(null) }
        }
      }
      "forgetDiscarded" -> {
        MeetingService.forgetDiscarded(activity, noteId)
        result.success(null)
      }
      "takeLaunch" -> {
        val launch = pendingLaunch ?: ""
        pendingLaunch = null
        result.success(launch)
      }
      "isLocked" -> result.success((activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked)
      "setCapturing" -> {
        setCapturing(call.argument<Boolean>("on") == true)
        result.success(null)
      }
      "endCapture" -> {
        setLockScreenCapture(false)
        if (call.argument<Boolean>("leave") == true) activity.moveTaskToBack(true)
        result.success(null)
      }
      "assistantEnabled" -> result.success(assistant)
      "isAssistant" -> result.success(isAssistant())
      "openAssistantSettings" -> result.success(openAssistantSettings())
      "deviceMaker" -> result.success(Build.MANUFACTURER ?: "")
      else -> result.notImplemented()
    }
  }

  // ---- meetings -------------------------------------------------------------------------------------------------

  private fun startMeeting(noteId: String, title: String): String {
    if (!isNoteId(noteId)) return "not a note id"
    if (MeetingService.isRecording()) return "recording"
    if (MeetingService.isEnding()) return MeetingService.STILL_STOPPING
    if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      microphoneFor = noteId
      activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_MICROPHONE)
      return "permission"
    }
    launchMeeting(noteId, title, null)
    return "started"
  }

  private fun startMeetingWith(noteId: String, title: String, otherApps: Boolean): String {
    if (!otherApps || OtherApps.unsupported() != null) return startMeeting(noteId, title)
    if (!isNoteId(noteId)) return "not a note id"
    if (MeetingService.isRecording()) return "recording"
    if (MeetingService.isEnding()) return MeetingService.STILL_STOPPING
    if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      microphoneFor = noteId
      activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_MICROPHONE)
      return "permission"
    }
    projectionFor = noteId to title
    val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    val ask = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
    } else {
      manager.createScreenCaptureIntent()
    }
    try {
      @Suppress("DEPRECATION")
      activity.startActivityForResult(ask, REQUEST_PROJECTION)
    } catch (error: Exception) {
      Log.w(TAG, "the screen-share consent could not be asked", error)
      projectionFor = null
      launchMeeting(noteId, title, ProjectionAnswer(noteId, title, Activity.RESULT_CANCELED, null))
    }
    return "started"
  }

  /** The meeting's service started for `noteId`, on the UI thread with the activity in front. */
  private fun launchMeeting(noteId: String, title: String, projection: ProjectionAnswer?) {
    val intent = Intent(activity, MeetingService::class.java)
      .setAction(MeetingService.ACTION_START)
      .putExtra(MeetingService.EXTRA_NOTE_ID, noteId)
      .putExtra(MeetingService.EXTRA_TITLE, title)
    if (projection != null) {
      intent.putExtra(MeetingService.EXTRA_PROJECTION_CODE, projection.code)
      if (projection.data != null) intent.putExtra(MeetingService.EXTRA_PROJECTION_DATA, projection.data)
    }
    try {
      ContextCompat.startForegroundService(activity, intent)
    } catch (error: Exception) {
      // Android 12+ refuses a foreground start from an app it does not see in front; the app undoes the note.
      Log.w(TAG, "the meeting service could not start", error)
      say("meeting", JSONObject().put("event", "failed").put("noteId", noteId).put("elapsedMs", 0).put("message", "The meeting could not start.").toString())
    }
  }

  private fun deliverPermission(granted: Boolean) {
    val noteId = microphoneFor
    microphoneFor = null
    say("meeting", JSONObject().put("event", "permission").put("noteId", noteId ?: JSONObject.NULL).put("elapsedMs", 0).put("granted", granted).toString())
  }

  /** Also Settings › Notifications' Allow, through the notices' own channel (Notices.kt `allow`). */
  fun requestNotifications(): String {
    if (RecordingAlerts.canNotify(activity)) return "allowed"
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return "blocked"
    val permission = Manifest.permission.POST_NOTIFICATIONS
    // Granted and still not able to notify: turned off in the phone's settings, which no dialog changes.
    if (activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return "blocked"
    // Refused twice: Android shows no third dialog, and asking would answer nothing.
    if (RecordingAlerts.wasAsked(activity) && !activity.shouldShowRequestPermissionRationale(permission)) return "blocked"
    RecordingAlerts.rememberAsked(activity)
    activity.requestPermissions(arrayOf(permission), REQUEST_MEETING_NOTIFICATIONS)
    return "asked"
  }

  /** The shape Rust's `fsx::plain_id` accepts; an id that fails it names no file and starts nothing. */
  private fun isNoteId(id: String): Boolean = id.length in 1..128 && id.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_' }

  // ---- the activity's own moments, handed on by MainActivity ---------------------------------------------------

  fun onCreate(intent: Intent?) {
    takeCapture(intent)
    takeMeeting(intent)
    // Off the main thread: it opens WorkManager and reads the jobs folder (it calls no Rust).
    val context = activity.applicationContext
    Thread({ MeetingService.recover(context) }, "glyph-meeting-recover").start()
  }

  fun onNewIntent(intent: Intent) {
    if (takeCapture(intent) && say("capture", null)) pendingLaunch = null
    if (takeMeeting(intent)) {
      val json = JSONObject().put("event", "open").put("noteId", MeetingService.recordingNoteId() ?: JSONObject.NULL).put("elapsedMs", 0).toString()
      if (say("meeting", json)) pendingLaunch = null
    }
  }

  fun onResume() {
    resumed = true
    // The microphone's answer, now that the app's retry can start the service while the activity is resumed.
    pendingPermission?.let { granted ->
      pendingPermission = null
      deliverPermission(granted)
    }
    // The screen-share consent's answer: the meeting's service starts now, with the activity back in front,
    // which the microphone's foreground type needs.
    pendingProjection?.let { answer ->
      pendingProjection = null
      launchMeeting(answer.noteId, answer.title, answer)
    }
    MeetingService.flushPending()
  }

  fun onPause() {
    resumed = false
  }

  fun onDestroy() {
    setCapturing(false)
  }

  /** True when the request was one of this bridge's. */
  fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean = when (requestCode) {
    REQUEST_MEETING_NOTIFICATIONS -> {
      say("notified", null)
      true
    }
    REQUEST_MICROPHONE -> {
      val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
      // After a dialog this callback comes before onResume, which delivers the answer; with no dialog (refused
      // twice before) the activity never left the front and no resume follows: the answer goes now.
      if (resumed) deliverPermission(granted) else pendingPermission = granted
      true
    }
    else -> false
  }

  /** True when the result was the screen-share consent's. */
  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != REQUEST_PROJECTION) return false
    val asked = projectionFor
    projectionFor = null
    if (asked != null) {
      // Declined is no data: the meeting starts all the same, with the microphone, and its screen says why.
      val answer = ProjectionAnswer(asked.first, asked.second, resultCode, if (resultCode == Activity.RESULT_OK) data else null)
      if (resumed) launchMeeting(answer.noteId, answer.title, answer) else pendingProjection = answer
    }
    return true
  }

  // ---- the capture launch and the lock screen (8F: in every build but one made with the assistant off) -----------

  private fun isCapture(intent: Intent?): Boolean = assistant && (intent?.action == MainActivity.ACTION_CAPTURE || intent?.action == Intent.ACTION_ASSIST)

  /** The recording notification tapped: a plain launch carrying EXTRA_MEETING. */
  private fun takeMeeting(intent: Intent?): Boolean {
    if (intent?.getBooleanExtra(MainActivity.EXTRA_MEETING, false) != true) return false
    pendingLaunch = "meeting"
    return true
  }

  /** Record the request and let this one launch show over the lock screen; taken back by `endCapture`. */
  private fun takeCapture(intent: Intent?): Boolean {
    if (!isCapture(intent)) return false
    pendingLaunch = "capture"
    setLockScreenCapture(true)
    return true
  }

  private fun setLockScreenCapture(on: Boolean) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      activity.setShowWhenLocked(on)
      activity.setTurnScreenOn(on)
    } else {
      @Suppress("DEPRECATION")
      val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
      if (on) activity.window.addFlags(flags) else activity.window.clearFlags(flags)
    }
  }

  /**
   * The side key pressed during a dictation, seen the only way an app can see it: the screen going off. And the
   * phone unlocked during one (ACTION_USER_PRESENT, sent once the keyguard has gone): the app asks again whether
   * it is locked.
   */
  private val screenOff = object : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
      when (intent.action) {
        Intent.ACTION_SCREEN_OFF -> say("screenOff", null)
        Intent.ACTION_USER_PRESENT -> say("unlocked", null)
      }
    }
  }

  /** A dictation started or ended: keep the screen on while it runs, and listen for it going off. */
  private fun setCapturing(on: Boolean) {
    if (on == capturing) return
    capturing = on
    if (on) {
      activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      val heard = IntentFilter(Intent.ACTION_SCREEN_OFF).apply { addAction(Intent.ACTION_USER_PRESENT) }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        activity.registerReceiver(screenOff, heard, Context.RECEIVER_NOT_EXPORTED)
      } else {
        @Suppress("UnspecifiedRegisterReceiverFlag")
        activity.registerReceiver(screenOff, heard)
      }
    } else {
      activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      try {
        activity.unregisterReceiver(screenOff)
      } catch (_: IllegalArgumentException) {
        // Never registered: nothing to take back.
      }
    }
  }

  private fun isAssistant(): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      val roles = activity.getSystemService(RoleManager::class.java) ?: return false
      return roles.isRoleAvailable(RoleManager.ROLE_ASSISTANT) && roles.isRoleHeld(RoleManager.ROLE_ASSISTANT)
    }
    return try {
      val assistant = Settings.Secure.getString(activity.contentResolver, "assistant") ?: return false
      ComponentName.unflattenFromString(assistant)?.packageName == activity.packageName
    } catch (e: SecurityException) {
      false
    }
  }

  /** Opens the settings screen closest to choosing the digital assistant app; whether one opened. */
  private fun openAssistantSettings(): Boolean =
    listOf(Settings.ACTION_VOICE_INPUT_SETTINGS, Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS).any { action ->
      try {
        activity.startActivity(Intent(action))
        true
      } catch (e: ActivityNotFoundException) {
        false
      }
    }
}
