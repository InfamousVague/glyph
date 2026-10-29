package com.mattssoftware.ghost_md

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * The app's running work as the phone's own notifications (docs/ACTIVITY.md, OS surfaces; Matt, 2026-10-29: "Android
 * progress notifications (and Samsung's Now Bar where offered) for recording, write-ups, banner runs and uploads"),
 * told by the record over `ghost_md/jobs` (lib/activity/activity_surfaces.dart; BackgroundJobs.kt hands it here).
 *
 * - One notification per job: its title, what it does now, a bar (how far, or going round), its glyph (res/drawable
 *   ghost_job_*, the tray's own: arrows for sync, the sparkle for writing, the brush for pictures, the reels for
 *   audio, people for meetings, the filling ring for downloads) and its kind's colour as the accent, Stop where it
 *   can be stopped (said back as `activityStop`), and a tap that opens what it makes (`activityOpen`).
 * - Grouped: with two or more, one summary over them, "2 jobs running".
 * - On Android 16 (API 36) and later, Android's progress-centric style (`Notification.ProgressStyle`), its bar in the
 *   kind's colour with the glyph riding it, asked to be promoted (a Live Update: the status bar's chip, "40%", the
 *   lock screen, and Samsung's Now Bar, which shows Live Updates); below that, an ongoing notification with a bar.
 * - Failed, it becomes a notification that says why, in red, until it is tapped or swiped.
 * - Done or stopped, it goes: the app's chip, or the service's "Header images made…" (BackgroundJobs.kt), says how.
 *
 * Its own channel, "Activity", low and silent (the app plays its own chime); the permission is the one the app
 * already asks for (MeetingBridge's `requestNotifications`): without it, nothing shows and nothing breaks. A locked
 * phone shows only what kind of work it is, never a note's title.
 *
 * The meeting's recording and its write-up are never told here: their own service's notification says them
 * (glyph/capture/MeetingService.kt, recordings/RecordingAlerts.kt).
 *
 * While the job service holds the app up (BackgroundJobs.kt), its foreground notification is one of these where any
 * shows ([first]), so a banner run is one notification, not two.
 */
object ActivityNotices {
  const val CHANNEL_ID = "ghost_activity"
  const val GROUP = "com.mattssoftware.ghost_md.ACTIVITY"
  const val SUMMARY_ID = 4400
  const val ACTION_OPEN = "com.mattssoftware.ghost_md.ACTIVITY_OPEN"
  const val ACTION_STOP = "com.mattssoftware.ghost_md.ACTIVITY_STOP"
  const val EXTRA_JOB = "com.mattssoftware.ghost_md.JOB"
  private const val FAILED_TAG = "GhostActivityFailed"
  private const val TAG = "GhostActivity"

  /** Android 16's ask to be shown as a Live Update (`Notification.EXTRA_REQUEST_PROMOTED_ONGOING`). */
  private const val PROMOTED = "android.requestPromotedOngoing"

  private val ids = NoticeIds()

  /** The live jobs shown, in the order they began, with what each notification is now. */
  private val shown = LinkedHashMap<String, Pair<NoticeJob, Notification>>()

  /** Calm (Settings › Appearance): the colours left out. */
  @Volatile private var calm = false

  /** Whether this process has looked for what an earlier one left. */
  private var swept = false

  /** `activity {event, job, jobs}`: the job shown, moved, or gone; and anything the app no longer says, gone too. */
  fun told(context: Context, event: String, job: Map<*, *>?, jobs: List<*>?) = synchronized(shown) {
    val one = NoticeJob.from(job)
    // No list (a Stop with no app to hear it): only the one job.
    val all = jobs?.mapNotNull { NoticeJob.from(it as? Map<*, *>) }
    if (all != null) for (gone in noticesGone(shown.keys.toList(), all.map { it.id })) if (gone != one?.id) remove(context, gone)
    if (one != null) {
      when {
        one.live && event != "ended" -> show(context, one)
        one.failed -> {
          remove(context, one.id)
          failed(context, one)
        }
        else -> remove(context, one.id)
      }
    }
    // One the app shows that this side missed.
    for (each in all.orEmpty()) if (each.live && !shown.containsKey(each.id)) show(context, each)
    summary(context)
  }

  /** `activityLook {calm}`, the app's first word as it starts: what an earlier run left is let go. */
  fun look(context: Context, calm: Boolean) = synchronized(shown) {
    val changed = this.calm != calm
    this.calm = calm
    if (!swept) {
      swept = true
      sweep(context)
    }
    if (changed) for ((job, _) in shown.values.toList()) show(context, job)
  }

  /** Everything shown let go: the engine, and the jobs in it, are gone. */
  fun clear(context: Context) = synchronized(shown) {
    for (id in shown.keys.toList()) remove(context, id)
    summary(context)
  }

  /** The first job shown and its notification, for the job service to hold the app up by (BackgroundJobs.kt). */
  internal fun first(): Pair<Int, Notification>? = synchronized(shown) {
    val (id, shownNow) = shown.entries.firstOrNull()?.toPair() ?: return null
    ids.of(id) to shownNow.second
  }

  private fun show(context: Context, job: NoticeJob) {
    val id = ids.of(job.id)
    val notification = if (Build.VERSION.SDK_INT >= 36) progressStyle(context, job, id) else compat(context, job, id)
    shown[job.id] = job to notification
    val manager = NotificationManagerCompat.from(context)
    manager.cancel(FAILED_TAG, job.id.hashCode())
    try {
      manager.notify(id, notification)
    } catch (error: SecurityException) {
      Log.w(TAG, "activity notification refused", error)
    }
    BackgroundJobService.reconsider()
  }

  private fun remove(context: Context, job: String) {
    shown.remove(job)
    val id = ids.release(job) ?: return
    // The job service may be holding the app up by it: it takes another (or its own) first, or this one would stay.
    BackgroundJobService.letGo(id)
    NotificationManagerCompat.from(context).cancel(id)
  }

  private fun summary(context: Context) {
    val manager = NotificationManagerCompat.from(context)
    val title = summaryTitle(shown.size)
    if (title == null) {
      manager.cancel(SUMMARY_ID)
      return
    }
    ensureChannel(context)
    val lines = NotificationCompat.InboxStyle().setBigContentTitle(title)
    for ((job, _) in shown.values) lines.addLine(if (job.text.isEmpty()) job.title else "${job.title} · ${job.text}")
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(R.drawable.ghost_job_ring)
      .setContentTitle(title)
      .setStyle(lines)
      .setGroup(GROUP)
      .setGroupSummary(true)
      .setOngoing(true)
      .setSilent(true)
      .setOnlyAlertOnce(true)
      .setCategory(NotificationCompat.CATEGORY_PROGRESS)
      .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
      .setPublicVersion(NotificationCompat.Builder(context, CHANNEL_ID).setSmallIcon(R.drawable.ghost_job_ring).setContentTitle(title).setGroup(GROUP).build())
      .setContentIntent(open(context, null, SUMMARY_ID))
    try {
      manager.notify(SUMMARY_ID, builder.build())
    } catch (error: SecurityException) {
      Log.w(TAG, "activity summary refused", error)
    }
  }

  /** Android 16's progress-centric notification, asked to be a Live Update. */
  @RequiresApi(36)
  private fun progressStyle(context: Context, job: NoticeJob, id: Int): Notification {
    ensureChannel(context)
    val colour = if (calm) null else job.colour
    val glyph = Icon.createWithResource(context, icon(job))
    val segment = Notification.ProgressStyle.Segment(NoticeJob.MAX)
    if (colour != null) segment.setColor(colour)
    val style = Notification.ProgressStyle()
      .setStyledByProgress(true)
      .setProgressSegments(listOf(segment))
      .setProgressTrackerIcon(glyph)
    val waiting = job.look == "waiting"
    if (job.indeterminate && !waiting) {
      style.setProgressIndeterminate(true)
    } else {
      style.setProgressIndeterminate(false).setProgress(job.progress ?: 0)
    }
    val builder = Notification.Builder(context, CHANNEL_ID)
      .setSmallIcon(icon(job))
      .setContentTitle(job.title)
      .setContentText(job.text)
      .setContentIntent(open(context, job.id, id))
      .setStyle(style)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setCategory(Notification.CATEGORY_PROGRESS)
      .setGroup(GROUP)
      .setWhen(job.startedAt)
      .setShowWhen(job.startedAt > 0)
      .setVisibility(Notification.VISIBILITY_PRIVATE)
      .setPublicVersion(publicVersion(context, job))
      .addExtras(Bundle().apply { putBoolean(PROMOTED, true) })
    job.chipText?.let { builder.setShortCriticalText(it) }
    if (colour != null) builder.setColor(colour)
    if (job.stoppable) builder.addAction(Notification.Action.Builder(Icon.createWithResource(context, R.drawable.ghost_job_needs_you), "Stop", stop(context, job.id, id)).build())
    return builder.build()
  }

  /** Below Android 16: an ongoing notification with a bar. */
  private fun compat(context: Context, job: NoticeJob, id: Int): Notification {
    ensureChannel(context)
    val colour = if (calm) null else job.colour
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(icon(job))
      .setContentTitle(job.title)
      .setContentText(job.text)
      .setContentIntent(open(context, job.id, id))
      .setOngoing(true)
      .setSilent(true)
      .setOnlyAlertOnce(true)
      .setCategory(NotificationCompat.CATEGORY_PROGRESS)
      .setGroup(GROUP)
      .setWhen(job.startedAt)
      .setShowWhen(job.startedAt > 0)
      .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
      .setPublicVersion(publicVersion(context, job))
      .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
    if (job.look == "waiting") {
      builder.setProgress(NoticeJob.MAX, job.progress ?: 0, false)
    } else {
      builder.setProgress(NoticeJob.MAX, job.progress ?: 0, job.indeterminate)
    }
    if (colour != null) builder.setColor(colour)
    if (job.stoppable) builder.addAction(R.drawable.ghost_job_needs_you, "Stop", stop(context, job.id, id))
    return builder.build()
  }

  /** What a locked phone shows: the kind of work, never the note's title. */
  private fun publicVersion(context: Context, job: NoticeJob): Notification =
    NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(icon(job))
      .setContentTitle(kindWords(job.kind))
      .setCategory(NotificationCompat.CATEGORY_PROGRESS)
      .setProgress(NoticeJob.MAX, job.progress ?: 0, job.indeterminate && job.look != "waiting")
      .build()

  /** Failed: why, and a tap to the app, where the tray has its fix. */
  private fun failed(context: Context, job: NoticeJob) {
    ensureChannel(context)
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(R.drawable.ghost_job_needs_you)
      .setContentTitle(job.title)
      .setContentText(job.cause ?: job.line)
      .setStyle(NotificationCompat.BigTextStyle().bigText(job.cause ?: job.line))
      .setContentIntent(open(context, job.id, job.id.hashCode()))
      .setAutoCancel(true)
      .setSilent(true)
      .setCategory(NotificationCompat.CATEGORY_ERROR)
      .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
      .setPublicVersion(NotificationCompat.Builder(context, CHANNEL_ID).setSmallIcon(R.drawable.ghost_job_needs_you).setContentTitle("Something needs you in Ghost.md").build())
    if (!calm) job.colour?.let { builder.setColor(it) }
    try {
      NotificationManagerCompat.from(context).notify(FAILED_TAG, job.id.hashCode(), builder.build())
    } catch (error: SecurityException) {
      Log.w(TAG, "activity failure notification refused", error)
    }
  }

  /** What an earlier run of the app left on the channel (its process went with its jobs). */
  private fun sweep(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    val mine = shown.keys.map { ids.of(it) }.toSet()
    for (left in manager.activeNotifications) {
      val ours = left.notification.group == GROUP || (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && left.notification.channelId == CHANNEL_ID && left.tag == null)
      if (ours && left.tag == null && left.id !in mine) manager.cancel(left.id)
    }
  }

  private fun icon(job: NoticeJob): Int = when (job.glyph) {
    "sync" -> R.drawable.ghost_job_sync
    "ai" -> R.drawable.ghost_job_ai
    "images" -> R.drawable.ghost_job_images
    "audio" -> R.drawable.ghost_job_audio
    "meetings" -> R.drawable.ghost_job_meetings
    "downloads" -> R.drawable.ghost_job_downloads
    "needs_you" -> R.drawable.ghost_job_needs_you
    else -> R.drawable.ghost_job_ring
  }

  private fun kindWords(kind: String): String = when (kind) {
    "sync" -> "Syncing"
    "ai" -> "Writing"
    "images" -> "Making pictures"
    "audio" -> "Working on a recording"
    "meetings" -> "Working on a meeting"
    "downloads" -> "Downloading"
    else -> "Ghost.md is working"
  }

  private fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java)
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return
    val channel = NotificationChannel(CHANNEL_ID, "Activity", NotificationManager.IMPORTANCE_LOW)
    channel.description = "What Ghost.md is doing by itself: header images, uploads, downloads, and how far each is"
    channel.setSound(null, null)
    channel.enableVibration(false)
    channel.setShowBadge(false)
    manager.createNotificationChannel(channel)
  }

  /** A tap: the app, and the job's own Open in it. [job] null is the app alone (the summary). */
  private fun open(context: Context, job: String?, code: Int): PendingIntent {
    val intent = Intent(context, MainActivity::class.java)
      .setAction(if (job == null) Intent.ACTION_MAIN else ACTION_OPEN)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    if (job != null) intent.putExtra(EXTRA_JOB, job)
    return PendingIntent.getActivity(context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
  }

  private fun stop(context: Context, job: String, code: Int): PendingIntent =
    PendingIntent.getBroadcast(
      context,
      code,
      Intent(context, ActivityStopReceiver::class.java).setAction(ACTION_STOP).putExtra(EXTRA_JOB, job),
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

  /** A notification's tap that opened the app ([open]): said to the app as `activityOpen`. */
  fun opened(intent: Intent?) {
    if (intent?.action != ACTION_OPEN) return
    val job = intent.getStringExtra(EXTRA_JOB) ?: return
    BackgroundJobs.say("activityOpen", job)
  }
}

/** Stop on a job's notification: said to the app as `activityStop`; with no app to hear it, the notification goes. */
class ActivityStopReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val job = intent.getStringExtra(ActivityNotices.EXTRA_JOB) ?: return
    if (!BackgroundJobs.say("activityStop", job)) ActivityNotices.told(context, "ended", mapOf("id" to job, "state" to "done"), null)
  }
}
