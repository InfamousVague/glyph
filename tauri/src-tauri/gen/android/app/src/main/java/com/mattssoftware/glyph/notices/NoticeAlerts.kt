package com.mattssoftware.glyph.notices

import android.Manifest
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
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.mattssoftware.glyph.MainActivity
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * The bell's rows as the phone's own notifications (native generation 23; docs/TEAMS.md "On the phone"). Matt: "also
 * send notifications as actual phone notifications too".
 *
 * Two roads reach `post`, and it lets each row through once whichever comes first:
 *
 * - the page, while it runs in the background, for the rows a sync brings (core/notifications/phone.ts), with a sealed
 *   row's own words since the page holds the account key;
 * - NoticeWorker, every fifteen minutes or so while the app is closed, which asks the service for the rows since its
 *   cursor with the session the page handed it (`watch`), and words a sealed row by its kind alone.
 *
 * One channel, `glyph_notices`, "Notifications". Private on the lock screen, as a written-up meeting is
 * (recordings/RecordingAlerts.kt): a team's name and a handle are not for whoever picks the phone up. Tapping one opens
 * the `ghostmd://` place it names (share/appLinks.ts): an organization's dashboard, or the notifications drawer.
 *
 * State is SharedPreferences, because the worker runs without the page: the watch (where the service is, the
 * session, the switches), the worker's cursor, and the last few hundred row ids posted.
 */
object NoticeAlerts {
  const val CHANNEL_ID = "glyph_notices"
  private const val WORK_NAME = "glyph-notices"
  private const val WORK_NOW = "glyph-notices-now"
  private const val PREFS = "glyph_notices"
  private const val KEY_WATCH = "watch"
  private const val KEY_CURSOR = "cursor"
  private const val KEY_POSTED = "posted"
  private const val TAG = "GlyphNotices"
  /** Row ids remembered as posted: far more than one pass brings, few enough to read at every post. */
  private const val POSTED_KEPT = 300

  internal fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  /** Whether a notification on this channel would be shown: the permission, the app's switch and the channel all on. */
  fun canNotify(context: Context): Boolean {
    val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
      context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    if (!granted || !NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
    val channel = context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL_ID) ?: return true
    return channel.importance != NotificationManager.IMPORTANCE_NONE
  }

  /** "off" (nothing watched), "on", or "blocked" (watched, but Android will not show them). */
  fun state(context: Context): String = when {
    watched(context) == null -> "off"
    !canNotify(context) -> "blocked"
    else -> "on"
  }

  // --- the watch ---------------------------------------------------------------------------------------------------

  /** What the worker needs, as the page last handed it; null when nothing is watched. */
  internal fun watched(context: Context): JSONObject? = prefs(context).getString(KEY_WATCH, null)?.let {
    try {
      JSONObject(it).takeIf { watch -> watch.optString("token").isNotEmpty() && watch.optString("api").startsWith("https://") }
    } catch (_: Throwable) {
      null
    }
  }

  /**
   * The page's watch, kept and the worker scheduled: `{ api, token, accountId, cursor, team, claude, mutedOrgs }`. A
   * different account starts afresh: its cursor is the page's and nothing posted for the last one is kept. The worker's
   * cursor only moves forward, so a page behind it never makes it post a row twice.
   */
  fun watch(context: Context, json: String) {
    val watch = JSONObject(json)
    val prefs = prefs(context)
    val was = watched(context)
    val sameAccount = was != null && was.optLong("accountId") == watch.optLong("accountId")
    val cursor = if (sameAccount) maxOf(prefs.getLong(KEY_CURSOR, 0), watch.optLong("cursor")) else watch.optLong("cursor")
    val edit = prefs.edit().putString(KEY_WATCH, watch.toString()).putLong(KEY_CURSOR, cursor)
    if (!sameAccount) edit.remove(KEY_POSTED)
    edit.apply()
    ensureChannel(context)
    val connected = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
    val work = WorkManager.getInstance(context)
    // Fifteen minutes is the least WorkManager runs a periodic job at. KEEP: a watch handed again at every sync must
    // not push the next run further out each time.
    work.enqueueUniquePeriodicWork(
      WORK_NAME,
      ExistingPeriodicWorkPolicy.KEEP,
      PeriodicWorkRequestBuilder<NoticeWorker>(15, TimeUnit.MINUTES).setConstraints(connected).build(),
    )
    if (!sameAccount) {
      work.enqueueUniqueWork(WORK_NOW, ExistingWorkPolicy.REPLACE, OneTimeWorkRequestBuilder<NoticeWorker>().setConstraints(connected).build())
    }
  }

  /** Nothing watched any more: signed out, or the phone's switch turned off. The session goes with it. */
  fun unwatch(context: Context) {
    prefs(context).edit().remove(KEY_WATCH).remove(KEY_CURSOR).remove(KEY_POSTED).apply()
    WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    WorkManager.getInstance(context).cancelUniqueWork(WORK_NOW)
  }

  internal fun cursor(context: Context): Long = prefs(context).getLong(KEY_CURSOR, 0)

  internal fun keepCursor(context: Context, cursor: Long) {
    prefs(context).edit().putLong(KEY_CURSOR, maxOf(cursor, cursor(context))).apply()
  }

  /** The session again, after the worker refreshed it: the page's own is untouched, and both stay good. */
  internal fun keepToken(context: Context, token: String) {
    val watch = watched(context) ?: return
    prefs(context).edit().putString(KEY_WATCH, watch.put("token", token).toString()).apply()
  }

  // --- posting -----------------------------------------------------------------------------------------------------

  private fun posted(context: Context): MutableList<String> {
    val held = prefs(context).getString(KEY_POSTED, null) ?: return mutableListOf()
    return try {
      val array = JSONArray(held)
      MutableList(array.length()) { array.getString(it) }
    } catch (_: Throwable) {
      mutableListOf()
    }
  }

  /**
   * A row as a notification, once: "posted", "seen" when it was posted before, or "blocked" when Android would not
   * show it. `link` is a `ghostmd://` place; anything else opens the drawer.
   */
  @Synchronized
  fun post(context: Context, id: String, title: String, text: String?, link: String): String {
    val seen = posted(context)
    if (id in seen) return "seen"
    if (!canNotify(context)) return "blocked"
    ensureChannel(context)
    val place = if (link.startsWith("ghostmd://")) link else "ghostmd://notifications"
    val open = Intent(Intent.ACTION_VIEW, Uri.parse(place))
      .setPackage(context.packageName)
      .setClass(context, MainActivity::class.java)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val pending = PendingIntent.getActivity(context, id.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    val public = NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.stat_notify_chat)
      .setContentTitle("New in Ghost.md")
      .setContentIntent(pending)
      .setAutoCancel(true)
      .build()
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.stat_notify_chat)
      .setContentTitle(title)
      .setContentIntent(pending)
      .setAutoCancel(true)
      .setOnlyAlertOnce(true)
      .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
      .setPublicVersion(public)
    if (!text.isNullOrBlank()) builder.setContentText(text).setStyle(NotificationCompat.BigTextStyle().bigText(text))
    try {
      NotificationManagerCompat.from(context).notify(TAG, id.hashCode(), builder.build())
    } catch (error: SecurityException) {
      Log.w(TAG, "notification refused", error)
      return "blocked"
    }
    seen.add(id)
    val kept = JSONArray()
    seen.takeLast(POSTED_KEPT).forEach { kept.put(it) }
    prefs(context).edit().putString(KEY_POSTED, kept.toString()).apply()
    return "posted"
  }

  internal fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java)
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return
    val channel = NotificationChannel(CHANNEL_ID, "Notifications", NotificationManager.IMPORTANCE_DEFAULT)
    channel.description = "Team news and Claude's changes to your notes: what the bell in Ghost.md shows."
    manager.createNotificationChannel(channel)
  }
}
