package com.mattssoftware.glyph.updates

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Update alerts: an opt-in notification when a new Glyph is published, delivered
 * with the app closed. OFF until the person turns it on in Settings.
 *
 * There is no push service behind this, on purpose: nothing to run, nothing that
 * learns who has Glyph installed. Instead a periodic WorkManager job looks at the
 * published manifest every few hours - Android picks the moment, batches it with
 * other work, and only runs it with a network. The check itself is Rust
 * (UpdateCheck), so it trusts only signed manifests.
 *
 * State is SharedPreferences, not the page's localStorage, because the worker
 * runs without the page.
 */
object UpdateAlerts {
  const val CHANNEL_ID = "glyph_updates"
  private const val WORK_NAME = "glyph-update-alerts"
  private const val WORK_NOW = "glyph-update-alerts-now"
  private const val PREFS = "glyph_update_alerts"
  private const val KEY_ENABLED = "enabled"
  internal const val KEY_LAST_BUILD = "last_notified_build"
  internal const val KEY_LAST_APK = "last_notified_apk"

  internal fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, false)

  fun canNotify(context: Context): Boolean =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
      context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

  /** "off", "on", or "blocked" (on, but Android will not show notifications from Glyph). */
  fun state(context: Context): String = when {
    !isEnabled(context) -> "off"
    !canNotify(context) -> "blocked"
    else -> "on"
  }

  fun enable(context: Context) {
    prefs(context).edit().putBoolean(KEY_ENABLED, true).apply()
    ensureChannel(context)
    val request = PeriodicWorkRequestBuilder<UpdateCheckWorker>(6, TimeUnit.HOURS, 1, TimeUnit.HOURS)
      .setConstraints(
        Constraints.Builder()
          .setRequiredNetworkType(NetworkType.CONNECTED)
          .setRequiresBatteryNotLow(true)
          .build(),
      )
      .build()
    // KEEP: turning alerts off and on again must not push the next check six
    // hours further out each time.
    val work = WorkManager.getInstance(context)
    work.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
    // And one look right away. A periodic job with a flex window first runs
    // near the END of its period - five hours after switching alerts on - and
    // a setting that does nothing observable for that long reads as broken.
    work.enqueueUniqueWork(
      WORK_NOW,
      ExistingWorkPolicy.REPLACE,
      OneTimeWorkRequestBuilder<UpdateCheckWorker>()
        .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
        .build(),
    )
  }

  fun disable(context: Context) {
    prefs(context).edit().putBoolean(KEY_ENABLED, false).apply()
    WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    WorkManager.getInstance(context).cancelUniqueWork(WORK_NOW)
  }

  internal fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java)
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return
    val channel = NotificationChannel(CHANNEL_ID, "Updates", NotificationManager.IMPORTANCE_DEFAULT)
    channel.description = "When a new version of Glyph is out. Off unless you turn on update alerts."
    manager.createNotificationChannel(channel)
  }
}
