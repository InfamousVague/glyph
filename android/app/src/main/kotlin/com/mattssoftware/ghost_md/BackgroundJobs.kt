package com.mattssoftware.ghost_md

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * A job the app runs on its own, held up while it runs: the phone's half of `ghost_md/jobs`
 * (lib/core/background_jobs.dart). The first is Lovart's header images for the recent notes
 * (lib/plugins/lovart/banner_run.dart; Matt, 2026-10-26: "Make the header generation async and a background task
 * that runs while the app is generating the images").
 *
 * The work itself is Dart's, in the app's own engine: what is needed of Android is that the process is not frozen or
 * killed while it goes, with the screen off or the app behind another. So, as the meeting's recording and write-up are
 * held up (glyph/capture/MeetingService.kt), a foreground service with a notification, and a partial wake lock with
 * it. No WorkManager: a worker would need an engine of its own to run Dart in, and the job is the one running already.
 *
 * - `running {id, title, text, done?, total?}` -> "started" | "running" | "refused". The service is started for the
 *   job, or told what to say now: "Making header images", "12 of 100", with a bar and Stop. Refused where Android will
 *   not start one (the app not in front on Android 12 and later); the job runs anyway, for as long as the app does.
 * - `ended {id, title, text?}` -> "ended". The service goes, and a notification says how it ended ("Header images
 *   made for 97 notes · 3 skipped"), as a meeting's "Written up" does; tapping it opens the app.
 * - Stop on the notification is said back to Dart as `stop {id}`.
 *
 * Swiped out of the recents, the activity goes and its engine with it, and the job with the engine: the service lets
 * itself go and says the job goes on when Ghost.md is opened, which is when the app takes it up again from where it
 * kept it.
 */
class BackgroundJobs(private val context: Context) {
  fun register(messenger: BinaryMessenger) {
    val channel = MethodChannel(messenger, CHANNEL)
    val main = Handler(Looper.getMainLooper())
    stopAsked = { id -> main.post { channel.invokeMethod("stop", mapOf("id" to id)) } }
    channel.setMethodCallHandler { call, result ->
      val id = call.argument<String>("id") ?: ""
      val title = call.argument<String>("title") ?: ""
      when (call.method) {
        "running" -> result.success(
          BackgroundJobService.running(context, id, title, call.argument<String>("text") ?: "", call.argument<Int>("done"), call.argument<Int>("total"))
        )
        "ended" -> {
          BackgroundJobService.ended(context, id, title, call.argument<String>("text"))
          result.success("ended")
        }
        else -> result.notImplemented()
      }
    }
  }

  companion object {
    const val CHANNEL = "ghost_md/jobs"

    /** Says Stop to the app's engine, while one is listening. */
    @Volatile internal var stopAsked: ((String) -> Unit)? = null
  }
}

/** The foreground service a running job holds (see [BackgroundJobs]). Not exported: only this app starts it. */
class BackgroundJobService : Service() {
  private var wakeLock: PowerManager.WakeLock? = null

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    current = this
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_STOP -> {
        val job = said ?: return START_NOT_STICKY
        BackgroundJobs.stopAsked?.invoke(job.id)
        show(job.copy(text = "Stopping after the ones being made…"))
      }
      else -> {
        // A start asked for must become a foreground one within seconds, even where the job has ended meanwhile.
        val job = said ?: Said("", "Ghost.md", "", null, null)
        startAsForeground(notification(this, job))
        if (said == null) {
          finish()
        } else {
          holdWakeLock()
        }
      }
    }
    return START_NOT_STICKY
  }

  /** The app's task swiped away: the engine, and the job in it, are gone. */
  override fun onTaskRemoved(rootIntent: Intent?) {
    super.onTaskRemoved(rootIntent)
    val job = said
    if (job != null) postEnded(this, job.id, job.title, "Paused. It goes on when you open Ghost.md.")
    said = null
    finish()
  }

  override fun onDestroy() {
    dropWakeLock()
    if (current === this) current = null
    super.onDestroy()
  }

  private fun show(job: Said) {
    said = job
    holdWakeLock()
    try {
      NotificationManagerCompat.from(this).notify(ONGOING_ID, notification(this, job))
    } catch (error: SecurityException) {
      Log.w(TAG, "job notification refused", error)
    }
  }

  private fun finish() {
    dropWakeLock()
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  /** `specialUse` from Android 14 (declared in the manifest with what it is for); below that types are not asked for. */
  private fun startAsForeground(notification: Notification) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      startForeground(ONGOING_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
    } else {
      startForeground(ONGOING_ID, notification)
    }
  }

  private fun holdWakeLock() {
    val lock = wakeLock ?: (getSystemService(POWER_SERVICE) as PowerManager)
      .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ghost:job")
      .also {
        it.setReferenceCounted(false)
        wakeLock = it
      }
    // Renewed with every word from the job: one whose app died lets the phone sleep within the half hour.
    lock.acquire(WAKE_MS)
  }

  private fun dropWakeLock() {
    val lock = wakeLock ?: return
    if (lock.isHeld) lock.release()
  }

  /** What the job said last. */
  internal data class Said(val id: String, val title: String, val text: String, val done: Int?, val total: Int?)

  companion object {
    const val CHANNEL_ID = "ghost_jobs"
    const val ONGOING_ID = 4301
    private const val ENDED_TAG = "GhostJobs"
    private const val ACTION_RUN = "com.mattssoftware.ghost_md.JOB_RUN"
    private const val ACTION_STOP = "com.mattssoftware.ghost_md.JOB_STOP"
    private const val CODE_STOP = 1
    private const val CODE_OPEN = 2
    private const val WAKE_MS = 30 * 60_000L
    private const val TAG = "GhostJobs"

    @Volatile private var current: BackgroundJobService? = null

    /** The job's last word, null once it has ended. */
    @Volatile private var said: Said? = null

    fun running(context: Context, id: String, title: String, text: String, done: Int?, total: Int?): String {
      val job = Said(id, title, text, done, total)
      val service = current
      if (service != null && said != null) {
        service.show(job)
        return "running"
      }
      said = job
      return try {
        ContextCompat.startForegroundService(context, Intent(context, BackgroundJobService::class.java).setAction(ACTION_RUN))
        "started"
      } catch (error: Exception) {
        // ForegroundServiceStartNotAllowedException and its kin: the job runs while the app does.
        said = null
        Log.w(TAG, "the job's service was refused", error)
        "refused"
      }
    }

    fun ended(context: Context, id: String, title: String, text: String?) {
      val had = said
      said = null
      current?.finish()
      if (had != null && had.id == id) postEnded(context, id, title, text)
    }

    private fun ensureChannel(context: Context) {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
      val manager = context.getSystemService(NotificationManager::class.java)
      if (manager.getNotificationChannel(CHANNEL_ID) != null) return
      val channel = NotificationChannel(CHANNEL_ID, "Background work", NotificationManager.IMPORTANCE_DEFAULT)
      channel.description = "While Ghost.md works on your notes by itself, and when it is done"
      manager.createNotificationChannel(channel)
    }

    private fun open(context: Context): PendingIntent {
      val intent = Intent(context, MainActivity::class.java)
        .setAction(Intent.ACTION_MAIN)
        .addCategory(Intent.CATEGORY_LAUNCHER)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      return PendingIntent.getActivity(context, CODE_OPEN, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** "Making header images", "12 of 100", with its bar and Stop. Quiet: it says how far, it asks nothing. */
    private fun notification(context: Context, job: Said): Notification {
      ensureChannel(context)
      val stop = PendingIntent.getService(
        context,
        CODE_STOP,
        Intent(context, BackgroundJobService::class.java).setAction(ACTION_STOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
      )
      val builder = NotificationCompat.Builder(context, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.stat_notify_sync)
        .setContentTitle(job.title)
        .setContentText(job.text)
        .setContentIntent(open(context))
        .addAction(0, "Stop", stop)
        .setOngoing(true)
        .setSilent(true)
        .setOnlyAlertOnce(true)
        .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        .setCategory(NotificationCompat.CATEGORY_PROGRESS)
      val total = job.total
      if (total != null && total > 0) builder.setProgress(total, (job.done ?: 0).coerceIn(0, total), false)
      return builder.build()
    }

    /** How it ended, once, as a meeting's "Written up" says so. */
    private fun postEnded(context: Context, id: String, title: String, text: String?) {
      ensureChannel(context)
      val builder = NotificationCompat.Builder(context, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.stat_notify_sync)
        .setContentTitle(title)
        .setContentIntent(open(context))
        .setAutoCancel(true)
      if (!text.isNullOrBlank()) builder.setContentText(text)
      try {
        NotificationManagerCompat.from(context).notify(ENDED_TAG, id.hashCode(), builder.build())
      } catch (error: SecurityException) {
        Log.w(TAG, "job's ended notification refused", error)
      }
    }
  }
}
