package com.mattssoftware.ghost_md.reminders

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.TimePickerDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.format.DateFormat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.mattssoftware.ghost_md.R
import com.mattssoftware.ghost_md.home.Doors
import com.mattssoftware.ghost_md.home.HomeScreen
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.Calendar
import java.util.Locale

/**
 * Reminders for to-dos and tickets (docs/FEATURES_2_1.md; lib/reminders): the phone's half of `ghost_md/reminders`
 * (lib/reminders/reminder_host.dart), the alarms, and the notification each one rings with.
 *
 * - `set {json}`: the app's whole plan, `{items: [{id, at: "2026-10-03 09:00", note, line, words, title, text, tick}]}`,
 *   kept here (SharedPreferences, so a restart and an update can arm it again with the app closed: ReminderRestart)
 *   and armed; what was armed and is no longer in it is let go.
 * - `state` -> `{notify, exact}`: whether Android shows the app's notifications, and whether it lets an alarm ring on
 *   its minute.
 * - `allowExact`: Android's Alarms and reminders page for the app (Android 12+).
 * - `pickTime {hour, minute}` -> "HH:MM" or null: the phone's own clock, in its light or dark.
 * - `tick {note, line, words}` is said TO the app (GhostBackground.kt), for a Done while it runs.
 *
 * **Exact or not.** An alarm rings on its minute where Android allows it (`setExactAndAllowWhileIdle`): before Android
 * 12 always; from 12, once the person allows Alarms and reminders for the app, which is the SCHEDULE_EXACT_ALARM
 * permission. Not USE_EXACT_ALARM: Google Play keeps that for alarm clocks and calendars, and a notes app is
 * neither. Where it is not allowed (from Android 14 a new install starts without it), the alarm is inexact
 * (`setAndAllowWhileIdle`): it still rings with the phone asleep, and Android may move it some minutes on.
 * Settings › Notifications › Reminders says so and offers the page.
 *
 * **The time is the clock's.** A reminder is kept as the day and time written, and turned into a moment each time it
 * is armed, so one written for nine rings at nine in whatever zone the phone is in: a change of zone or of the clock
 * arms them again (ReminderRestart).
 *
 * **What rings.** The notification ("Reminders" channel, high importance) says the item's words and its note; a tap
 * opens the note at that line; Done ticks it (GhostBackground.kt) and Snooze 1 hour rings it again in an hour. A
 * reminder missed while the phone was off is rung once when it starts again, if it was due in the last twelve hours.
 */
object Reminders {
  const val CHANNEL = "ghost_md/reminders"
  const val NOTIFY_CHANNEL = "ghost_reminders"
  private const val TAG = "GhostReminders"
  private const val PREFS = "ghost_reminders"
  private const val KEY_PLAN = "plan"
  private const val KEY_SNOOZED = "snoozed"
  private const val KEY_ARMED = "armed"
  private const val KEY_FIRED = "fired"
  private const val FIRED_KEPT = 400
  private const val MISSED_MS = 12L * 60 * 60 * 1000
  const val SNOOZE_MS = 60L * 60 * 1000

  const val ACTION_FIRE = "com.mattssoftware.ghost_md.reminders.FIRE"
  const val ACTION_DONE = "com.mattssoftware.ghost_md.reminders.DONE"
  const val ACTION_SNOOZE = "com.mattssoftware.ghost_md.reminders.SNOOZE"

  /** The app's channel while an engine runs, for a Done handed to it (GhostBackground.kt); null otherwise. */
  @Volatile internal var live: MethodChannel? = null

  /** The activity, for the clock and Android's page; never held past it. */
  private var activity: WeakReference<Activity>? = null

  private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  // ---- the channel -------------------------------------------------------------------------------------------------

  fun register(context: Context, owner: Activity, messenger: BinaryMessenger) {
    val app = context.applicationContext
    activity = WeakReference(owner)
    val channel = MethodChannel(messenger, CHANNEL)
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "set" -> {
          val json = call.argument<String>("json") ?: ""
          // Off the main thread: a plan of sixty alarms is sixty calls into the alarm service.
          Thread({
            val taken = try {
              set(app, json)
              true
            } catch (error: Throwable) {
              Log.w(TAG, "the plan was not taken", error)
              false
            }
            Handler(Looper.getMainLooper()).post { result.success(taken) }
          }, "ghost-reminders-set").start()
        }
        "state" -> result.success(mapOf("notify" to canNotify(app), "exact" to canExact(app)))
        "allowExact" -> result.success(allowExact(app))
        "pickTime" -> pickTime(call.argument<Int>("hour") ?: 9, call.argument<Int>("minute") ?: 0, result)
        else -> result.notImplemented()
      }
    }
    live = channel
  }

  /** The engine is going with its activity [owner]: nobody to hand a Done to, unless another has registered since. */
  fun released(owner: Activity) {
    if (activity?.get() !== owner) return
    live = null
    activity = null
  }

  // ---- what is kept ------------------------------------------------------------------------------------------------

  /** One reminder, as the app made it. */
  data class Item(val id: String, val at: String, val note: String, val line: Int, val words: String, val title: String, val text: String, val tick: Boolean) {
    fun json(): JSONObject = JSONObject().put("id", id).put("at", at).put("note", note).put("line", line).put("words", words).put("title", title).put("text", text).put("tick", tick)

    companion object {
      fun of(json: JSONObject): Item? {
        val id = json.optString("id")
        val at = json.optString("at")
        val note = json.optString("note")
        if (id.isEmpty() || millisOf(at) == null || note.isEmpty()) return null
        return Item(id, at, note, json.optInt("line"), json.optString("words"), json.optString("title"), json.optString("text"), json.optBoolean("tick"))
      }
    }
  }

  private fun items(context: Context, key: String): List<Item> {
    val raw = prefs(context).getString(key, null) ?: return emptyList()
    return try {
      val array = if (key == KEY_PLAN) JSONObject(raw).optJSONArray("items") ?: JSONArray() else JSONArray(raw)
      (0 until array.length()).mapNotNull { Item.of(array.getJSONObject(it)) }
    } catch (_: Throwable) {
      emptyList()
    }
  }

  private fun ids(context: Context, key: String): List<String> = try {
    val array = JSONArray(prefs(context).getString(key, "[]"))
    (0 until array.length()).map { array.getString(it) }
  } catch (_: Throwable) {
    emptyList()
  }

  private fun keepIds(context: Context, key: String, ids: List<String>) {
    val array = JSONArray()
    ids.forEach { array.put(it) }
    prefs(context).edit().putString(key, array.toString()).apply()
  }

  private fun keepSnoozed(context: Context, items: List<Item>) {
    val array = JSONArray()
    items.forEach { array.put(it.json()) }
    prefs(context).edit().putString(KEY_SNOOZED, array.toString()).apply()
  }

  /** Every reminder held: the plan's and the snoozed ones. */
  fun held(context: Context): List<Item> = items(context, KEY_PLAN) + items(context, KEY_SNOOZED)

  fun find(context: Context, id: String): Item? = held(context).firstOrNull { it.id == id }

  // ---- arming ------------------------------------------------------------------------------------------------------

  /** The app's plan, kept and armed. */
  @Synchronized
  fun set(context: Context, json: String) {
    JSONObject(json) // refused here, not after it is kept, if it will not read
    prefs(context).edit().putString(KEY_PLAN, json).commit()
    arm(context, missed = false)
  }

  /**
   * Everything held armed again, and what was armed and is held no longer let go. [missed]: a reminder due in the
   * last twelve hours that never rang (the phone was off) rings now; only after a restart.
   */
  @Synchronized
  fun arm(context: Context, missed: Boolean) {
    val now = System.currentTimeMillis()
    val fired = ids(context, KEY_FIRED).toMutableSet()
    // A snooze that has rung is let go.
    val snoozed = items(context, KEY_SNOOZED)
    val stillSnoozed = snoozed.filter { (millisOf(it.at) ?: 0) > now || (missed && it.id !in fired) }
    if (stillSnoozed.size != snoozed.size) keepSnoozed(context, stillSnoozed)
    val all = items(context, KEY_PLAN) + stillSnoozed
    val wanted = all.map { it.id }.toSet()
    for (id in ids(context, KEY_ARMED)) if (id !in wanted) cancel(context, id)
    val armed = mutableListOf<String>()
    for (item in all) {
      val at = millisOf(item.at) ?: continue
      if (at > now) {
        alarm(context, item.id, at)
        armed.add(item.id)
      } else if (missed && now - at < MISSED_MS && item.id !in fired) {
        ring(context, item)
      }
    }
    keepIds(context, KEY_ARMED, armed)
  }

  private fun alarmIntent(context: Context, id: String, flags: Int): PendingIntent? =
    PendingIntent.getBroadcast(
      context,
      id.hashCode(),
      Intent(context, ReminderAlarms::class.java).setAction(ACTION_FIRE).setData(Uri.parse("ghostmd-reminder://fire/$id")),
      flags or PendingIntent.FLAG_IMMUTABLE,
    )

  private fun alarm(context: Context, id: String, at: Long) {
    val manager = context.getSystemService(AlarmManager::class.java) ?: return
    val pending = alarmIntent(context, id, PendingIntent.FLAG_UPDATE_CURRENT) ?: return
    try {
      if (canExact(context)) manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending) else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
    } catch (error: SecurityException) {
      // Allowed a moment ago and taken back since: inexact, as without it.
      manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
    }
  }

  private fun cancel(context: Context, id: String) {
    val pending = alarmIntent(context, id, PendingIntent.FLAG_NO_CREATE) ?: return
    context.getSystemService(AlarmManager::class.java)?.cancel(pending)
    pending.cancel()
  }

  /** Whether Android lets an alarm ring on its minute. */
  fun canExact(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
    return context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
  }

  private fun allowExact(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
    val from = activity?.get() ?: return false
    return try {
      from.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}")))
      true
    } catch (error: Throwable) {
      Log.w(TAG, "the alarms page did not open", error)
      false
    }
  }

  // ---- ringing -----------------------------------------------------------------------------------------------------

  /** Whether a notification on the reminders' channel would be shown. */
  fun canNotify(context: Context): Boolean {
    val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    if (!granted || !NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
    val channel = context.getSystemService(NotificationManager::class.java).getNotificationChannel(NOTIFY_CHANNEL) ?: return true
    return channel.importance != NotificationManager.IMPORTANCE_NONE
  }

  private fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java)
    if (manager.getNotificationChannel(NOTIFY_CHANNEL) != null) return
    val channel = NotificationChannel(NOTIFY_CHANNEL, "Reminders", NotificationManager.IMPORTANCE_HIGH)
    channel.description = "A to-do or a ticket when it is due, or at the time set on it."
    manager.createNotificationChannel(channel)
  }

  /** The id a reminder's notification is posted under. */
  private fun code(id: String) = id.hashCode()

  private fun action(context: Context, action: String, id: String): PendingIntent = PendingIntent.getBroadcast(
    context,
    code(id),
    Intent(context, ReminderAlarms::class.java).setAction(action).setData(Uri.parse("ghostmd-reminder://${action.substringAfterLast('.').lowercase(Locale.US)}/$id")),
    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
  )

  /** An alarm's moment: the reminder held under [id] rings, once. */
  fun fired(context: Context, id: String) {
    val item = find(context, id) ?: return
    ring(context, item)
  }

  @Synchronized
  private fun ring(context: Context, item: Item) {
    val fired = ids(context, KEY_FIRED)
    if (item.id !in fired) keepIds(context, KEY_FIRED, (fired + item.id).takeLast(FIRED_KEPT))
    if (!canNotify(context)) return
    ensureChannel(context)
    val open = Doors.press(context, Doors.noteAt(item.note, item.line, item.words), code(item.id))
    val public = NotificationCompat.Builder(context, NOTIFY_CHANNEL)
      .setSmallIcon(R.drawable.ghost_ic_alarm)
      .setContentTitle("A reminder from Ghost.md")
      .setContentIntent(open)
      .build()
    val builder = NotificationCompat.Builder(context, NOTIFY_CHANNEL)
      .setSmallIcon(R.drawable.ghost_ic_alarm)
      .setContentTitle(item.title)
      .setContentText(item.text)
      .setContentIntent(open)
      .setAutoCancel(true)
      .setCategory(NotificationCompat.CATEGORY_REMINDER)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
      .setPublicVersion(public)
      .setWhen(millisOf(item.at) ?: System.currentTimeMillis())
      .setShowWhen(true)
    if (item.tick) builder.addAction(R.drawable.ghost_ic_check, "Done", action(context, ACTION_DONE, item.id))
    builder.addAction(R.drawable.ghost_ic_alarm, "Snooze 1 hour", action(context, ACTION_SNOOZE, item.id))
    try {
      NotificationManagerCompat.from(context).notify(TAG, code(item.id), builder.build())
    } catch (error: SecurityException) {
      Log.w(TAG, "the reminder was refused", error)
    }
  }

  /** Done pressed: the notification goes, and the item is ticked in its note. */
  fun done(context: Context, id: String) {
    NotificationManagerCompat.from(context).cancel(TAG, code(id))
    val item = find(context, id) ?: return
    dropSnoozed(context, id)
    forget(context, item.note, item.words)
    HomeScreen.ticked(context, item.note, item.line)
    GhostBackground.tick(context, item.note, item.line, item.words)
  }

  /**
   * An item ticked outside the app: its other reminders (the day before's, a snooze) let go at once, before the app
   * has read the tick and handed over a plan without them.
   */
  @Synchronized
  fun forget(context: Context, note: String, words: String) {
    val raw = prefs(context).getString(KEY_PLAN, null) ?: return
    try {
      val items = JSONObject(raw).optJSONArray("items") ?: return
      val kept = JSONArray()
      var dropped = false
      for (index in 0 until items.length()) {
        val item = items.getJSONObject(index)
        if (item.optString("note") == note && item.optString("words") == words) dropped = true else kept.put(item)
      }
      val snoozed = items(context, KEY_SNOOZED)
      val stillSnoozed = snoozed.filter { !(it.note == note && it.words == words) }
      if (!dropped && stillSnoozed.size == snoozed.size) return
      prefs(context).edit().putString(KEY_PLAN, JSONObject().put("items", kept).toString()).commit()
      keepSnoozed(context, stillSnoozed)
      arm(context, missed = false)
    } catch (error: Throwable) {
      Log.w(TAG, "the ticked item's reminders were not let go", error)
    }
  }

  /** Snooze 1 hour pressed: the notification goes, and rings again an hour from now. */
  @Synchronized
  fun snooze(context: Context, id: String) {
    NotificationManagerCompat.from(context).cancel(TAG, code(id))
    val item = find(context, id) ?: return
    val at = writtenOf(System.currentTimeMillis() + SNOOZE_MS + 59_999)
    val again = item.copy(id = "${item.id.substringBefore('~')}~$at", at = at)
    keepSnoozed(context, items(context, KEY_SNOOZED).filter { it.id != id } + again)
    arm(context, missed = false)
  }

  private fun dropSnoozed(context: Context, id: String) {
    val snoozed = items(context, KEY_SNOOZED)
    if (snoozed.any { it.id == id }) keepSnoozed(context, snoozed.filter { it.id != id })
  }

  // ---- the clock ---------------------------------------------------------------------------------------------------

  private val WRITTEN = Regex("""^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$""")

  /** "2026-10-03 09:00" as a moment on this phone's clock now; null for anything else. */
  fun millisOf(at: String): Long? {
    val (year, month, day, hour, minute) = WRITTEN.matchEntire(at)?.destructured ?: return null
    val calendar = Calendar.getInstance()
    calendar.clear()
    calendar.set(year.toInt(), month.toInt() - 1, day.toInt(), hour.toInt(), minute.toInt(), 0)
    return calendar.timeInMillis
  }

  /** A moment as a reminder is written, to the minute it is in. */
  fun writtenOf(millis: Long): String {
    val calendar = Calendar.getInstance()
    calendar.timeInMillis = millis
    return String.format(Locale.US, "%04d-%02d-%02d %02d:%02d", calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH) + 1, calendar.get(Calendar.DAY_OF_MONTH), calendar.get(Calendar.HOUR_OF_DAY), calendar.get(Calendar.MINUTE))
  }

  private var picking: TimePickerDialog? = null

  private fun pickTime(hour: Int, minute: Int, result: MethodChannel.Result) {
    val from = activity?.get()
    if (from == null) {
      result.success(null)
      return
    }
    picking?.dismiss()
    var answered = false
    val night = (from.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val theme = if (night) android.R.style.Theme_DeviceDefault_Dialog_Alert else android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
    val dialog = TimePickerDialog(
      from,
      theme,
      { _, h, m ->
        if (!answered) {
          answered = true
          result.success(String.format(Locale.US, "%02d:%02d", h, m))
        }
      },
      hour.coerceIn(0, 23),
      minute.coerceIn(0, 59),
      DateFormat.is24HourFormat(from),
    )
    dialog.setOnDismissListener {
      if (picking === dialog) picking = null
      if (!answered) {
        answered = true
        result.success(null)
      }
    }
    picking = dialog
    dialog.show()
  }
}
