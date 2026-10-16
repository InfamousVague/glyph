package com.mattssoftware.ghost_md.home

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import com.mattssoftware.ghost_md.R
import com.mattssoftware.ghost_md.reminders.GhostBackground

/**
 * The three home-screen widgets (docs/FEATURES_2_1.md, "Home screen"), RemoteViews in the app's dark look: no
 * Compose, no collection service, nothing running. Each draws what the app last handed over (HomeScreen.kt) and
 * opens the app by a `ghostmd://` link (Doors.kt). A list's rows are as many as its height holds: on the Fold's cover
 * screen and its inner one a widget made taller shows more, and one made smaller says how many did not fit.
 */
private const val HEAD_DP = 40
private const val FOOT_DP = 22

/** How many rows of [rowDp] a widget of these options holds under its heading. */
private fun rowsFor(options: Bundle?, rowDp: Int, fallbackDp: Int): Int {
  // Upright, a widget is its minimum width by its maximum height; that is the height it has on a phone held as one.
  val tall = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)?.takeIf { it > 0 } ?: fallbackDp
  return ((tall - HEAD_DP - FOOT_DP) / rowDp).coerceAtLeast(1)
}

/** The app's home page: its own launch, no link. */
private fun home(context: Context): PendingIntent? {
  val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
  return PendingIntent.getActivity(context, 7_200, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
}

/** Quick note: a new note to type in, and a voice note. */
class QuickNoteWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) manager.updateAppWidget(id, views(context))
  }

  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
    manager.updateAppWidget(id, views(context, options))
  }

  companion object {
    fun views(context: Context, options: Bundle? = null): RemoteViews {
      val views = RemoteViews(context.packageName, R.layout.ghost_widget_quick_note)
      views.setOnClickPendingIntent(R.id.ghost_quick_new, Doors.press(context, Doors.NEW))
      views.setOnClickPendingIntent(R.id.ghost_quick_voice, Doors.press(context, Doors.VOICE))
      // Too narrow for the words beside the pen: the pen alone.
      val wide = (options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 0).let { it == 0 || it >= 150 }
      views.setViewVisibility(R.id.ghost_quick_new_words, if (wide) View.VISIBLE else View.GONE)
      return views
    }

    fun drawAll(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      for (id in HomeScreen.ids(context, QuickNoteWidget::class.java)) manager.updateAppWidget(id, views(context, manager.getAppWidgetOptions(id)))
    }
  }
}

/** Today: the open to-dos due today and before, from every note, each ticked in place or opened at its line. */
class TodayWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) draw(context, manager, id)
    HomeScreen.armMidnight(context)
  }

  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) = draw(context, manager, id)

  override fun onEnabled(context: Context) = HomeScreen.armMidnight(context)

  override fun onDisabled(context: Context) = HomeScreen.disarmMidnight(context)

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action == HomeScreen.ACTION_MIDNIGHT) {
      drawAll(context)
      if (HomeScreen.ids(context, TodayWidget::class.java).isNotEmpty()) HomeScreen.armMidnight(context)
    }
  }

  companion object {
    private const val ROW_DP = 44

    fun drawAll(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      for (id in HomeScreen.ids(context, TodayWidget::class.java)) draw(context, manager, id)
    }

    fun draw(context: Context, manager: AppWidgetManager, id: Int) {
      val day = HomeScreen.today()
      val todos = HomeScreen.dueNow(context, day)
      val views = RemoteViews(context.packageName, R.layout.ghost_widget_list)
      views.setTextViewText(R.id.ghost_list_title, "Today")
      views.setTextViewText(R.id.ghost_list_count, if (todos.isEmpty()) "" else "${todos.size} to do")
      home(context)?.let { views.setOnClickPendingIntent(R.id.ghost_list_head, it) }
      views.removeAllViews(R.id.ghost_list_rows)
      val room = rowsFor(manager.getAppWidgetOptions(id), ROW_DP, 160)
      val shown = todos.take(room)
      for (todo in shown) views.addView(R.id.ghost_list_rows, row(context, todo, day))
      val left = todos.size - shown.size
      views.setViewVisibility(R.id.ghost_list_more, if (left > 0) View.VISIBLE else View.GONE)
      views.setTextViewText(R.id.ghost_list_more, "$left more")
      home(context)?.let { views.setOnClickPendingIntent(R.id.ghost_list_more, it) }
      views.setViewVisibility(R.id.ghost_list_empty, if (todos.isEmpty()) View.VISIBLE else View.GONE)
      views.setTextViewText(R.id.ghost_list_empty, "Nothing due today.")
      manager.updateAppWidget(id, views)
    }

    private fun row(context: Context, todo: HomeScreen.Todo, day: String): RemoteViews {
      val row = RemoteViews(context.packageName, R.layout.ghost_widget_today_row)
      val code = "${todo.note}:${todo.line}".hashCode()
      row.setTextViewText(R.id.ghost_row_words, todo.words)
      val overdue = todo.due < day
      row.setTextViewText(R.id.ghost_row_note, if (overdue) "${todo.title} · Overdue" else todo.title)
      row.setTextColor(R.id.ghost_row_note, context.getColor(if (overdue) R.color.ghost_widget_overdue else R.color.ghost_widget_ink_3))
      row.setOnClickPendingIntent(R.id.ghost_row_text, Doors.press(context, Doors.noteAt(todo.note, todo.line, todo.words), code))
      if (!todo.tick) {
        row.setViewVisibility(R.id.ghost_row_check, View.INVISIBLE)
        return row
      }
      val tick = PendingIntent.getBroadcast(
        context,
        code,
        Intent(context, WidgetTicks::class.java)
          .setAction(WidgetTicks.ACTION_TICK)
          .setData(Uri.Builder().scheme("ghostmd-widget").authority("tick").appendPath(todo.note).appendPath(todo.line.toString()).build())
          .putExtra("words", todo.words),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
      )
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        row.setCompoundButtonChecked(R.id.ghost_row_check, false)
        row.setOnCheckedChangeResponse(R.id.ghost_row_check, RemoteViews.RemoteResponse.fromPendingIntent(tick))
      } else {
        row.setOnClickPendingIntent(R.id.ghost_row_check, tick)
      }
      return row
    }
  }
}

/** Pinned notes: the notes the person pinned, the one written in last first. */
class PinnedWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) draw(context, manager, id)
  }

  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) = draw(context, manager, id)

  companion object {
    private const val ROW_DP = 36

    fun drawAll(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      for (id in HomeScreen.ids(context, PinnedWidget::class.java)) draw(context, manager, id)
    }

    fun draw(context: Context, manager: AppWidgetManager, id: Int) {
      val pinned = HomeScreen.pinned(context)
      val views = RemoteViews(context.packageName, R.layout.ghost_widget_list)
      views.setTextViewText(R.id.ghost_list_title, "Pinned")
      views.setTextViewText(R.id.ghost_list_count, if (pinned.isEmpty()) "" else "${pinned.size}")
      home(context)?.let { views.setOnClickPendingIntent(R.id.ghost_list_head, it) }
      views.removeAllViews(R.id.ghost_list_rows)
      val room = rowsFor(manager.getAppWidgetOptions(id), ROW_DP, 160)
      val shown = pinned.take(room)
      for (note in shown) {
        val row = RemoteViews(context.packageName, R.layout.ghost_widget_pinned_row)
        row.setTextViewText(R.id.ghost_pin_title, note.title.ifBlank { "Untitled" })
        row.setOnClickPendingIntent(R.id.ghost_pin_row, Doors.press(context, Doors.noteAt(note.id), "pin:${note.id}".hashCode()))
        views.addView(R.id.ghost_list_rows, row)
      }
      val left = pinned.size - shown.size
      views.setViewVisibility(R.id.ghost_list_more, if (left > 0) View.VISIBLE else View.GONE)
      views.setTextViewText(R.id.ghost_list_more, "$left more")
      home(context)?.let { views.setOnClickPendingIntent(R.id.ghost_list_more, it) }
      views.setViewVisibility(R.id.ghost_list_empty, if (pinned.isEmpty()) View.VISIBLE else View.GONE)
      views.setTextViewText(R.id.ghost_list_empty, "Pin a note and it shows here.")
      manager.updateAppWidget(id, views)
    }
  }
}

/**
 * A to-do ticked on the Today widget: off the widget at once (HomeScreen.ticked), then written into its note through
 * the app's library (GhostBackground.kt). Not exported: only the widget's own PendingIntent reaches it.
 */
class WidgetTicks : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != ACTION_TICK) return
    val parts = intent.data?.pathSegments ?: return
    if (parts.size != 2) return
    val note = parts[0]
    val line = parts[1].toIntOrNull() ?: return
    val words = intent.getStringExtra("words") ?: ""
    val app = context.applicationContext
    HomeScreen.ticked(app, note, line)
    GhostBackground.tick(app, note, line, words)
  }

  companion object {
    const val ACTION_TICK = "com.mattssoftware.ghost_md.home.TICK"
  }
}
