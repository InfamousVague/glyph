package com.mattssoftware.ghost_md.home

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.mattssoftware.ghost_md.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * The home screen's half of the notes (docs/WIDGETS_ANDROID.md; lib/home_screen): the phone's half of `ghost_md/home_screen`,
 * where the app hands over what the four widgets draw and what the icon's recent shortcuts name, kept in
 * SharedPreferences so they draw with the app closed.
 *
 * - `put {kind, json}`: kept, and the widgets that draw it drawn again (or the shortcuts set). The app hands one over
 *   only when it is another than the last (lib/home_screen/home_screen_data.dart). The kinds: `todos` (To-dos, and
 *   Calendar's dated to-dos), `notes` (Recent notes), `voice` (Voice note's recordings), `calendar` (Calendar's
 *   events, or that the plugin is off), `look` (the app theme's side, which the widgets are drawn in), `recent` (the
 *   icon's shortcuts); and `widgets`, the shared snapshot the iPhone's widgets read, taken as `todos`, `notes` and
 *   `calendar`. `today` and `pinned`, what the Today and
 *   Pinned widgets drew before the four replaced them, are taken and kept nowhere.
 *
 * The widgets word their days and times themselves (HomeData.kt), so two alarms of this app's draw them again with
 * nothing asked of it, neither waking the phone: one at midnight (within ten minutes of it), when "Tomorrow" becomes
 * "Today" and a to-do becomes overdue; and one about every quarter of an hour, which Android holds while the phone
 * sleeps and delivers as it wakes, so "20 min ago" and an event that has ended are right when someone looks. Both
 * only while a widget is on a home screen.
 */
object HomeScreen {
  const val CHANNEL = "ghost_md/home_screen"
  private const val TAG = "GhostHomeScreen"
  private const val PREFS = "ghost_home_screen"
  const val ACTION_MIDNIGHT = "com.mattssoftware.ghost_md.home.MIDNIGHT"
  const val ACTION_FRESHEN = "com.mattssoftware.ghost_md.home.FRESHEN"
  private const val MIDNIGHT_WINDOW_MS = 10L * 60 * 1000

  private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  fun register(context: Context, messenger: BinaryMessenger) {
    val app = context.applicationContext
    // What the Today and Pinned widgets drew before the four: nothing reads it now.
    prefs(app).edit().remove("today").remove("pinned").apply()
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "put" -> {
          val kind = call.argument<String>("kind") ?: ""
          val json = call.argument<String>("json") ?: ""
          // Off the main thread: a widget's drawing and the shortcuts are calls into other processes.
          Thread({
            val taken = try {
              put(app, kind, json)
            } catch (error: Throwable) {
              Log.w(TAG, "$kind was not kept", error)
              false
            }
            Handler(Looper.getMainLooper()).post { result.success(taken) }
          }, "ghost-home-screen").start()
        }
        else -> result.notImplemented()
      }
    }
  }

  @Synchronized
  fun put(context: Context, kind: String, json: String): Boolean {
    JSONObject(json)
    when (kind) {
      "todos" -> {
        prefs(context).edit().putString("todos", json).commit()
        WidgetKind.TODOS.drawAll(context)
        WidgetKind.CALENDAR.drawAll(context)
      }
      "notes" -> {
        prefs(context).edit().putString("notes", json).commit()
        WidgetKind.NOTES.drawAll(context)
      }
      "voice" -> {
        prefs(context).edit().putString("voice", json).commit()
        WidgetKind.VOICE.drawAll(context)
      }
      "calendar" -> {
        prefs(context).edit().putString("calendar", json).commit()
        WidgetKind.CALENDAR.drawAll(context)
      }
      "look" -> {
        if (prefs(context).getString("look", null) == json) return true
        prefs(context).edit().putString("look", json).commit()
        redraw(context)
      }
      // The shared widget snapshot (lib/home_screen/widget_snapshot.dart), where the app hands that over instead:
      // kept as the three it holds.
      "widgets" -> {
        val (todos, notes, calendar) = HomeData.split(json) ?: return false
        prefs(context).edit().putString("todos", todos).putString("notes", notes).putString("calendar", calendar).commit()
        redraw(context)
      }
      "recent" -> {
        prefs(context).edit().putString("recent", json).commit()
        recent(context, json)
      }
      // The old widgets' data: an app from before the four may still hand it over once.
      "today", "pinned" -> prefs(context).edit().remove(kind).apply()
      else -> return false
    }
    return true
  }

  /** What [kind] was last handed, or null where nothing has been. */
  fun kept(context: Context, kind: String): String? = prefs(context).getString(kind, null)

  /** The app theme's side the widgets are drawn in: `dark` (the app's own default), `light` or `system`. */
  fun look(context: Context): String = try {
    JSONObject(kept(context, "look") ?: "{}").optString("theme", "dark").ifEmpty { "dark" }
  } catch (_: Throwable) {
    "dark"
  }

  /** Every widget drawn again: after a restart, an update, a new zone, at midnight and as the phone wakes. */
  fun redraw(context: Context) {
    for (kind in WidgetKind.values()) kind.drawAll(context)
  }

  /** Today on this phone's clock, `2026-10-03`. */
  fun today(): String = HomeData.written(Calendar.getInstance())

  /**
   * A to-do ticked outside the app (the widget's box, a reminder's Done): off the To-dos and Calendar widgets at
   * once, before the tick has been written (GhostBackground.kt), and its reminders let go. The app's next pass hands
   * over the notes as they are then.
   */
  @Synchronized
  fun ticked(context: Context, note: String, line: Int) {
    try {
      val (left, gone) = HomeData.without(kept(context, "todos"), note, line) ?: return
      prefs(context).edit().putString("todos", left).commit()
      WidgetKind.TODOS.drawAll(context)
      WidgetKind.CALENDAR.drawAll(context)
      if (gone != null) com.mattssoftware.ghost_md.reminders.Reminders.forget(context, note, gone.match)
    } catch (error: Throwable) {
      Log.w(TAG, "the tick was not taken off the widgets", error)
    }
  }

  // ---- the two alarms ------------------------------------------------------------------------------------------------

  /** Whether any of the four is on a home screen (the old three's places among them). */
  fun anyPlaced(context: Context): Boolean = WidgetKind.values().any { it.ids(context).isNotEmpty() }

  /** The midnight and the quarter-hour alarms, armed (again: each replaces its own). */
  fun armClock(context: Context) {
    val manager = context.getSystemService(AlarmManager::class.java) ?: return
    // The midnight the Today widget armed before the four, to its own class: let go, as this one is the clock's.
    PendingIntent.getBroadcast(context, 7_100, Intent(context, TodayWidget::class.java).setAction(ACTION_MIDNIGHT), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE)?.let(manager::cancel)
    val next = Calendar.getInstance().apply {
      add(Calendar.DAY_OF_YEAR, 1)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 30)
      set(Calendar.MILLISECOND, 0)
    }
    // Within ten minutes of midnight, never waking the phone for it: `set` alone may be an hour late.
    manager.setWindow(AlarmManager.RTC, next.timeInMillis, MIDNIGHT_WINDOW_MS, clock(context, ACTION_MIDNIGHT))
    // RTC, not RTC_WAKEUP: while the phone sleeps it waits, and comes as the screen does.
    manager.setInexactRepeating(AlarmManager.RTC, System.currentTimeMillis() + AlarmManager.INTERVAL_FIFTEEN_MINUTES, AlarmManager.INTERVAL_FIFTEEN_MINUTES, clock(context, ACTION_FRESHEN))
  }

  fun disarmClock(context: Context) {
    val manager = context.getSystemService(AlarmManager::class.java) ?: return
    manager.cancel(clock(context, ACTION_MIDNIGHT))
    manager.cancel(clock(context, ACTION_FRESHEN))
  }

  private fun clock(context: Context, action: String): PendingIntent = PendingIntent.getBroadcast(
    context,
    if (action == ACTION_MIDNIGHT) 7_101 else 7_102,
    Intent(context, WidgetClock::class.java).setAction(action),
    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
  )

  // ---- the icon's recent notes -------------------------------------------------------------------------------------

  data class Named(val id: String, val title: String)

  private fun named(raw: String?): List<Named> = try {
    val notes = JSONObject(raw ?: "{}").optJSONArray("notes") ?: JSONArray()
    (0 until notes.length()).map { notes.getJSONObject(it) }.map { Named(it.optString("id"), it.optString("title")) }.filter { it.id.isNotEmpty() }
  } catch (_: Throwable) {
    emptyList()
  }

  /** How many of the icon's shortcuts are its own (res/xml/ghost_*_shortcuts.xml): the recent notes come after. */
  private const val OWN_SHORTCUTS = 4
  private const val MOST_RECENT = 3

  private fun recent(context: Context, json: String) {
    val room = (ShortcutManagerCompat.getMaxShortcutCountPerActivity(context) - OWN_SHORTCUTS).coerceIn(0, MOST_RECENT)
    val shortcuts = named(json).take(room).mapIndexed { rank, note ->
      val title = note.title.ifBlank { "Untitled" }
      ShortcutInfoCompat.Builder(context, "recent-${note.id}")
        .setShortLabel(title.take(24))
        .setLongLabel(title.take(40))
        .setIcon(IconCompat.createWithResource(context, R.drawable.ghost_shortcut_note))
        .setIntent(Doors.intent(context, Doors.noteAt(note.id)))
        .setRank(rank)
        .build()
    }
    try {
      ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts)
    } catch (error: Throwable) {
      // A launcher that holds fewer than it said, or rate-limits: the last set stays.
      Log.w(TAG, "the recent notes were not set on the icon", error)
    }
  }

  /** The widgets of [provider] on any home screen. */
  fun ids(context: Context, provider: Class<*>): IntArray = AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, provider))
}
