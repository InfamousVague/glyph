package com.mattssoftware.ghost_md.reminders

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.mattssoftware.ghost_md.home.HomeScreen
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * A reminder's alarm, and its notification's Done and Snooze 1 hour (Reminders.kt). Not exported: only the alarm
 * service, holding this app's own PendingIntent, and the app's own notification reach it.
 */
class ReminderAlarms : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val id = intent.data?.lastPathSegment ?: return
    val app = context.applicationContext
    when (intent.action) {
      Reminders.ACTION_FIRE -> Reminders.fired(app, id)
      Reminders.ACTION_DONE -> Reminders.done(app, id)
      Reminders.ACTION_SNOOZE -> Reminders.snooze(app, id)
    }
  }
}

/**
 * What takes the alarms away, or moves the clock under them: the phone started again (alarms do not outlive it), the
 * app updated, the time or the zone changed, the person allowing or taking back Alarms and reminders. Each arms
 * every reminder held again from what was kept (Reminders.kt), and a restart rings what it missed. Alarms only: no
 * service is started from here, which Android refuses an app woken by an update or a restart from Android 12 on.
 *
 * The home screen's Today widget turns its day too (HomeScreen.kt), since a restart or a new zone may have passed a
 * midnight. And a restart or an update registers the places' geofences again (Places.kt), which Play services drops
 * with either.
 */
class ReminderRestart : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val app = context.applicationContext
    val restarted = intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
    when (intent.action) {
      Intent.ACTION_BOOT_COMPLETED,
      Intent.ACTION_MY_PACKAGE_REPLACED,
      Intent.ACTION_TIME_CHANGED,
      Intent.ACTION_TIMEZONE_CHANGED,
      AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> {
        val pending = goAsync()
        Thread({
          try {
            Reminders.arm(app, missed = intent.action == Intent.ACTION_BOOT_COMPLETED)
            if (restarted || intent.action == Intent.ACTION_TIMEZONE_CHANGED || intent.action == Intent.ACTION_TIME_CHANGED) HomeScreen.redraw(app)
            if (restarted) {
              val registered = CountDownLatch(1)
              Places.arm(app) { registered.countDown() }
              registered.await(8, TimeUnit.SECONDS)
            }
          } finally {
            pending.finish()
          }
        }, "ghost-reminders-restart").start()
      }
    }
  }
}
