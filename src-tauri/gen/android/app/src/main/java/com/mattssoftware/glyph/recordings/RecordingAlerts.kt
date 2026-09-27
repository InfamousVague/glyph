package com.mattssoftware.glyph.recordings

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.mattssoftware.glyph.MainActivity
import com.mattssoftware.glyph.capture.MeetingService

/**
 * The recordings channel and everything posted on it: the notification a
 * meeting is recorded under, the two-hour question, the write-up's progress and
 * the word that a meeting has been written up.
 *
 * One channel, `glyph_recordings`, made the way UpdateAlerts makes
 * `glyph_updates`. The recording notification is public on the lock screen: a
 * running microphone should be stoppable by whoever holds the phone, and it
 * says nothing but a counter. The written-up one is private, with a public
 * version that says only that a recording was written up: the app's own rule is
 * that a locked phone shows nothing of a note, and a meeting's first sentence
 * says who decided what.
 *
 * Nothing here asks for the permission. That is MainActivity's
 * (`requestNotifications`), because only an activity can raise the dialog.
 */
internal object RecordingAlerts {
  const val CHANNEL_ID = "glyph_recordings"
  /** The foreground notification while a meeting is recorded and, after Stop, while the service writes it up. */
  const val RECORDING_ID = 4201
  /** The worker's foreground notification, when Android lets it have one. */
  const val WORKER_ID = 4202
  /** "Still recording?", its own notification because a question nobody can hear is not a question. */
  const val QUESTION_ID = 4203
  /** The written-up notifications, one per note, under this tag with the note id's hash. */
  const val WRITTEN_UP_TAG = "GlyphRecordings"
  private const val PREFS = "glyph_recordings"
  private const val KEY_ASKED = "asked"
  private const val TAG = "GlyphRecordings"

  private const val CODE_STOP = 1
  private const val CODE_DISCARD = 2
  private const val CODE_KEEP_GOING = 3
  private const val CODE_OPEN = 4

  internal fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  /** Whether the person was asked for POST_NOTIFICATIONS from here before (the first refusal is not "blocked"). */
  fun wasAsked(context: Context): Boolean = prefs(context).getBoolean(KEY_ASKED, false)

  fun rememberAsked(context: Context) {
    prefs(context).edit().putBoolean(KEY_ASKED, true).apply()
  }

  /** Granted below Android 13, else the permission; and notifications on for the app; and the channel not silenced to nothing. */
  fun canNotify(context: Context): Boolean {
    val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
      context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    if (!granted || !NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
    val channel = context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL_ID) ?: return true
    return channel.importance != NotificationManager.IMPORTANCE_NONE
  }

  fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java)
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return
    val channel = NotificationChannel(CHANNEL_ID, "Recordings", NotificationManager.IMPORTANCE_DEFAULT)
    channel.description = "While a meeting is being recorded, and when one has been written up"
    manager.createNotificationChannel(channel)
  }

  /** "Recording · 12:40" with Stop and Discard, or "Muted by another app · 12:40" while another app has the microphone. */
  fun recording(context: Context, elapsedMs: Long, silenced: Boolean): Notification {
    ensureChannel(context)
    val word = if (silenced) "Muted by another app" else "Recording"
    return NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.ic_btn_speak_now)
      .setContentTitle("$word · ${counter(elapsedMs)}")
      .setContentIntent(openMeeting(context))
      .addAction(0, "Stop", serviceAction(context, MeetingService.ACTION_STOP, CODE_STOP))
      .addAction(0, "Discard", serviceAction(context, MeetingService.ACTION_DISCARD, CODE_DISCARD))
      .setOngoing(true)
      .setSilent(true)
      .setOnlyAlertOnce(true)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setCategory(NotificationCompat.CATEGORY_SERVICE)
      .build()
  }

  /** "Still recording? · 2:00:00" with Keep going and Stop. Not silent: it is a question. */
  fun question(context: Context, elapsedMs: Long): Notification {
    ensureChannel(context)
    return NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.ic_btn_speak_now)
      .setContentTitle("Still recording? · ${counter(elapsedMs)}")
      .setContentIntent(openMeeting(context))
      .addAction(0, "Keep going", serviceAction(context, MeetingService.ACTION_KEEP_GOING, CODE_KEEP_GOING))
      .addAction(0, "Stop", serviceAction(context, MeetingService.ACTION_STOP, CODE_STOP))
      .setOngoing(true)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setCategory(NotificationCompat.CATEGORY_REMINDER)
      .build()
  }

  /** The write-up's progress, under the same id as the recording was: "Listening to the recording, 40%", then "Summarizing". No actions. */
  fun writeUp(context: Context, title: String?, line: String): Notification {
    ensureChannel(context)
    return NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.ic_btn_speak_now)
      .setContentTitle(title ?: "Writing up")
      .setContentText(line)
      .setOngoing(true)
      .setSilent(true)
      .setOnlyAlertOnce(true)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setCategory(NotificationCompat.CATEGORY_PROGRESS)
      .build()
  }

  /** The line under the write-up's title, from the `.progress` file's phase and percent. */
  fun progressLine(phase: String?, percent: Int): String = when (phase) {
    "listening" -> "Listening to the recording, $percent%"
    "summarizing" -> "Summarizing"
    else -> "Writing up"
  }

  /**
   * "Written up: Meeting, 26 Sep 14:05" with the summary's first sentence, or
   * what stood in for one; tapping it opens the note through its `ghostmd://`
   * link. Private: the sentence shows once the phone is unlocked, and a locked
   * one says only that a recording was written up.
   */
  fun postWrittenUp(context: Context, noteId: String, title: String, text: String) {
    ensureChannel(context)
    val open = Intent(Intent.ACTION_VIEW, Uri.parse("ghostmd://note/$noteId"))
      .setPackage(context.packageName)
      .setClass(context, MainActivity::class.java)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val pending = PendingIntent.getActivity(context, noteId.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    val public = NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.ic_btn_speak_now)
      .setContentTitle("A recording was written up")
      .setContentIntent(pending)
      .setAutoCancel(true)
      .build()
    val notification = NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.ic_btn_speak_now)
      .setContentTitle("Written up: $title")
      .setContentText(text)
      .setStyle(NotificationCompat.BigTextStyle().bigText(text))
      .setContentIntent(pending)
      .setAutoCancel(true)
      .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
      .setPublicVersion(public)
      .build()
    try {
      NotificationManagerCompat.from(context).notify(WRITTEN_UP_TAG, noteId.hashCode(), notification)
    } catch (error: SecurityException) {
      Log.w(TAG, "written-up notification refused", error)
    }
  }

  /** Post or refresh one of the ongoing notifications by id, with the refusal logged rather than thrown. */
  fun show(context: Context, id: Int, notification: Notification) {
    try {
      NotificationManagerCompat.from(context).notify(id, notification)
    } catch (error: SecurityException) {
      Log.w(TAG, "notification $id refused", error)
    }
  }

  fun cancel(context: Context, id: Int) {
    NotificationManagerCompat.from(context).cancel(id)
  }

  /** A plain launch that carries the meeting extra: at boot `takeLaunch()` answers "meeting", warm the page hears `open`. */
  private fun openMeeting(context: Context): PendingIntent {
    val open = Intent(context, MainActivity::class.java)
      .setAction(Intent.ACTION_MAIN)
      .addCategory(Intent.CATEGORY_LAUNCHER)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      .putExtra(MainActivity.EXTRA_MEETING, true)
    return PendingIntent.getActivity(context, CODE_OPEN, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
  }

  /** An action on the service itself. From Android 8 a notification's tap must start it as foreground, or the start is refused. */
  private fun serviceAction(context: Context, action: String, code: Int): PendingIntent {
    val intent = Intent(context, MeetingService::class.java).setAction(action)
    val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      PendingIntent.getForegroundService(context, code, intent, flags)
    } else {
      PendingIntent.getService(context, code, intent, flags)
    }
  }
}

/** The tape's counter as the page draws it (capture/tape.ts `counter`): "12:40", or "1:02:03" past an hour. */
internal fun counter(ms: Long): String {
  val total = maxOf(0L, ms / 1000)
  val hours = total / 3600
  val minutes = (total % 3600) / 60
  val seconds = (total % 60).toString().padStart(2, '0')
  return if (hours > 0) "$hours:${minutes.toString().padStart(2, '0')}:$seconds" else "$minutes:$seconds"
}
