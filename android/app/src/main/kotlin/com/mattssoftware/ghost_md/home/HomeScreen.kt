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
import java.util.Locale

/**
 * The home screen's half of the notes (docs/FEATURES_2_1.md, "Home screen"; lib/home_screen): the phone's half of
 * `ghost_md/home_screen`, where the app hands over what the widgets draw and what the icon's recent shortcuts name,
 * kept in SharedPreferences so they draw with the app closed.
 *
 * - `put {kind: today|pinned|recent, json}`: kept, and the widgets of that kind drawn again (or the shortcuts set).
 *   The app hands one over only when it is another than the last (lib/home_screen/home_screen_data.dart).
 *
 * The Today widget is handed the open to-dos due up to a week ahead and draws those due today and before, so its
 * day turns at midnight with nothing asked of the app: an alarm at the next midnight draws it again (within ten minutes
 * of it, and not waking the phone: a widget nobody is looking at can wait for the screen to come on).
 */
object HomeScreen {
  const val CHANNEL = "ghost_md/home_screen"
  private const val TAG = "GhostHomeScreen"
  private const val PREFS = "ghost_home_screen"
  const val ACTION_MIDNIGHT = "com.mattssoftware.ghost_md.home.MIDNIGHT"
  private const val MIDNIGHT_WINDOW_MS = 10L * 60 * 1000

  private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  fun register(context: Context, messenger: BinaryMessenger) {
    val app = context.applicationContext
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
      "today" -> {
        prefs(context).edit().putString("today", json).commit()
        TodayWidget.drawAll(context)
      }
      "pinned" -> {
        prefs(context).edit().putString("pinned", json).commit()
        PinnedWidget.drawAll(context)
      }
      "recent" -> {
        prefs(context).edit().putString("recent", json).commit()
        recent(context, json)
      }
      else -> return false
    }
    return true
  }

  /** Every widget drawn again: after a restart, an update, a new zone. */
  fun redraw(context: Context) {
    TodayWidget.drawAll(context)
    PinnedWidget.drawAll(context)
    QuickNoteWidget.drawAll(context)
  }

  // ---- Today -------------------------------------------------------------------------------------------------------

  /** One to-do, as the app handed it. */
  data class Todo(val note: String, val line: Int, val words: String, val due: String, val title: String, val tick: Boolean)

  /** Today on this phone's clock, `2026-10-03`. */
  fun today(): String {
    val now = Calendar.getInstance()
    return String.format(Locale.US, "%04d-%02d-%02d", now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1, now.get(Calendar.DAY_OF_MONTH))
  }

  /** The to-dos due today and before, the soonest due first, as the app sorted them. */
  fun dueNow(context: Context, day: String = today()): List<Todo> {
    val raw = prefs(context).getString("today", null) ?: return emptyList()
    return try {
      val items = JSONObject(raw).optJSONArray("items") ?: return emptyList()
      (0 until items.length()).map { items.getJSONObject(it) }.map {
        Todo(it.optString("note"), it.optInt("line"), it.optString("words"), it.optString("due"), it.optString("title"), it.optBoolean("tick"))
      }.filter { it.note.isNotEmpty() && it.due.isNotEmpty() && it.due <= day }
    } catch (_: Throwable) {
      emptyList()
    }
  }

  /**
   * A to-do ticked outside the app (the widget's box, a reminder's Done): out of the Today widget at once, before
   * the tick has been written (GhostBackground.kt), and its reminders let go. The app's next pass hands over the
   * notes as they are then.
   */
  @Synchronized
  fun ticked(context: Context, note: String, line: Int) {
    val raw = prefs(context).getString("today", null) ?: return
    try {
      val items = JSONObject(raw).optJSONArray("items") ?: return
      val kept = JSONArray()
      var words: String? = null
      for (index in 0 until items.length()) {
        val item = items.getJSONObject(index)
        if (item.optString("note") == note && item.optInt("line") == line) words = item.optString("words") else kept.put(item)
      }
      prefs(context).edit().putString("today", JSONObject().put("items", kept).toString()).commit()
      TodayWidget.drawAll(context)
      if (words != null) com.mattssoftware.ghost_md.reminders.Reminders.forget(context, note, words)
    } catch (error: Throwable) {
      Log.w(TAG, "the tick was not taken off Today", error)
    }
  }

  /** The Today widgets drawn again at the next midnight, and every midnight after while there is one. */
  fun armMidnight(context: Context) {
    val manager = context.getSystemService(AlarmManager::class.java) ?: return
    val next = Calendar.getInstance().apply {
      add(Calendar.DAY_OF_YEAR, 1)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 30)
      set(Calendar.MILLISECOND, 0)
    }
    // Within ten minutes of midnight, never waking the phone for it: `set` alone may be an hour late.
    manager.setWindow(AlarmManager.RTC, next.timeInMillis, MIDNIGHT_WINDOW_MS, midnight(context))
  }

  fun disarmMidnight(context: Context) {
    context.getSystemService(AlarmManager::class.java)?.cancel(midnight(context))
  }

  private fun midnight(context: Context): PendingIntent = PendingIntent.getBroadcast(
    context,
    7_100,
    Intent(context, TodayWidget::class.java).setAction(ACTION_MIDNIGHT),
    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
  )

  // ---- Pinned ------------------------------------------------------------------------------------------------------

  data class Named(val id: String, val title: String)

  private fun named(raw: String?): List<Named> = try {
    val notes = JSONObject(raw ?: "{}").optJSONArray("notes") ?: JSONArray()
    (0 until notes.length()).map { notes.getJSONObject(it) }.map { Named(it.optString("id"), it.optString("title")) }.filter { it.id.isNotEmpty() }
  } catch (_: Throwable) {
    emptyList()
  }

  fun pinned(context: Context): List<Named> = named(prefs(context).getString("pinned", null))

  // ---- the icon's recent notes -------------------------------------------------------------------------------------

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
