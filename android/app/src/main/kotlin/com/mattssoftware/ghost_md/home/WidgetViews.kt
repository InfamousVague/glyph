package com.mattssoftware.ghost_md.home

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.format.DateFormat
import android.util.SizeF
import android.view.Gravity
import android.view.View
import android.widget.RemoteViews
import com.mattssoftware.ghost_md.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * How each of the four widgets is drawn (docs/WIDGETS_ANDROID.md), in the app's look: the frame (layout/ghost_w_frame.xml),
 * its heading as the home page heads a section, and the rows each widget has room for at the size it is.
 *
 * - **Voice note**: the dock's filled ring made big, which records a voice note at once (`ghostmd://voice`: the app
 *   opens straight into the recorder); beside it the last recording, its name and length. Large: under it, the
 *   recordings, each a tap from its note.
 * - **To-dos**: the open to-dos from every note in the To-dos view's groups (Overdue, Today, Later, Someday), each
 *   with the view's round tick, which ticks it without opening the app, a due day's chip, and the note it is in.
 * - **Calendar**: from today, each day's events (the time, a ring, the title, the calendar) beside the to-dos due that
 *   day (a dot, red where late), as the app's calendar of to-dos shows them. The plugin off, where to turn it on.
 * - **Recent notes**: the notes written in last, each as a home page's row: its mark, name, how it starts, when.
 *   Large and wide (the Fold opened), two columns of them.
 *
 * Sizes: from Android 12 the launcher says each size the widget is drawn at (upright and on its side), and a view is
 * made for each (`RemoteViews(Map<SizeF, RemoteViews>)`), so the launcher shows the right one as it turns or resizes
 * with nothing asked of the app. Before 12, the size the widget says it is in this orientation.
 */
object WidgetViews {
  // The frame's own room, in dp (layout/ghost_w_frame.xml): its padding above and below and its heading.
  private const val FRAME_DP = 14 + 34
  private const val MORE_DP = 18
  private const val EYEBROW_DP = 22
  private const val TODO_DP = 48
  private const val NOTE_DP = 52
  private const val EVENT_DP = 46
  private const val HERO_DP = 76

  /** A widget this tall or more is large: Voice note lists its recordings under the microphone. */
  private const val LARGE_DP = 230

  /** Recent notes in two columns from this wide, when large. */
  private const val TWO_COLUMNS_DP = 420

  fun draw(context: Context, manager: AppWidgetManager, id: Int, kind: WidgetKind) {
    manager.updateAppWidget(id, views(context, manager.getAppWidgetOptions(id), kind))
  }

  fun views(context: Context, options: Bundle?, kind: WidgetKind): RemoteViews {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val sizes = sizesOf(options)
      if (sizes.isNotEmpty()) return RemoteViews(sizes.associateWith { build(context, kind, it.width.toInt(), it.height.toInt()) })
    }
    // Upright, a widget is its minimum width by its maximum height; on its side, its maximum width by its minimum
    // height (the Fold opened and turned).
    val sideways = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
    val wide = options?.getInt(if (sideways) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)?.takeIf { it > 0 } ?: 250
    val tall = options?.getInt(if (sideways) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)?.takeIf { it > 0 } ?: 160
    return build(context, kind, wide, tall)
  }

  @Suppress("DEPRECATION")
  private fun sizesOf(options: Bundle?): List<SizeF> {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || options == null) return emptyList()
    val sizes: List<SizeF>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      options.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, SizeF::class.java)
    } else {
      options.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES)
    }
    // A launcher says two or three at most; a map holds sixteen.
    return sizes.orEmpty().filter { it.width > 0 && it.height > 0 }.distinct().take(8)
  }

  fun build(context: Context, kind: WidgetKind, wide: Int, tall: Int): RemoteViews = when (kind) {
    WidgetKind.VOICE -> voice(context, wide, tall)
    WidgetKind.TODOS -> todos(context, wide, tall)
    WidgetKind.CALENDAR -> calendar(context, wide, tall)
    WidgetKind.NOTES -> notes(context, wide, tall)
  }

  // ---- the frame ---------------------------------------------------------------------------------------------------

  /**
   * Whether the widgets are drawn dark: the app's theme (HomeScreen.look; its own default is Dark), the phone's mode
   * where the app follows the phone.
   */
  private fun dark(context: Context): Boolean = when (HomeScreen.look(context)) {
    "light" -> false
    "system" -> (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    else -> true
  }

  /** A colour set from here (a due chip's words), in the look the widget is drawn in. */
  private fun ink(context: Context, light: Int, dark: Int): Int = context.getColor(if (dark(context)) dark else light)

  private fun frame(context: Context, mark: Int, title: String, count: String, action: Int, actionSaid: String, actionLink: String): RemoteViews {
    // The look is the theme on the frame's own root (layout/ghost_w_frame_*.xml): the rows added to it read it too.
    val layout = when (HomeScreen.look(context)) {
      "light" -> R.layout.ghost_w_frame_light
      "system" -> R.layout.ghost_w_frame_system
      else -> R.layout.ghost_w_frame_dark
    }
    val views = RemoteViews(context.packageName, layout)
    views.setImageViewResource(R.id.ghost_w_mark, mark)
    views.setTextViewText(R.id.ghost_w_title, title)
    views.setTextViewText(R.id.ghost_w_count, count)
    views.setImageViewResource(R.id.ghost_w_action_icon, action)
    views.setContentDescription(R.id.ghost_w_action, actionSaid)
    views.setOnClickPendingIntent(R.id.ghost_w_action, Doors.press(context, actionLink))
    home(context)?.let { views.setOnClickPendingIntent(R.id.ghost_w_head, it) }
    views.removeAllViews(R.id.ghost_w_col_a)
    views.removeAllViews(R.id.ghost_w_col_b)
    // Everything a size may change, said again for every size: a launcher applies a widget's new views over its old
    // ones, and what one size set and another does not say stays (a medium's centring under a large's rows).
    views.setViewVisibility(R.id.ghost_w_head, View.VISIBLE)
    views.setViewPadding(R.id.ghost_w_root, dp(context, 16), dp(context, 8), dp(context, 10), dp(context, 6))
    views.setInt(R.id.ghost_w_root, "setGravity", Gravity.TOP or Gravity.START)
    views.setInt(R.id.ghost_w_body, "setGravity", Gravity.TOP or Gravity.START)
    return views
  }

  private fun more(context: Context, views: RemoteViews, left: Int) {
    views.setViewVisibility(R.id.ghost_w_more, if (left > 0) View.VISIBLE else View.GONE)
    views.setTextViewText(R.id.ghost_w_more, "$left more")
    home(context)?.let { views.setOnClickPendingIntent(R.id.ghost_w_more, it) }
  }

  private fun empty(context: Context, views: RemoteViews, title: String?, words: String = "", link: PendingIntent? = home(context)) {
    views.setViewVisibility(R.id.ghost_w_empty, if (title == null) View.GONE else View.VISIBLE)
    views.setViewVisibility(R.id.ghost_w_body, if (title == null) View.VISIBLE else View.GONE)
    if (title == null) return
    views.setTextViewText(R.id.ghost_w_empty_title, title)
    views.setTextViewText(R.id.ghost_w_empty_words, words)
    views.setViewVisibility(R.id.ghost_w_empty_words, if (words.isEmpty()) View.GONE else View.VISIBLE)
    link?.let { views.setOnClickPendingIntent(R.id.ghost_w_empty, it) }
  }

  /** The app's home page: its own launch, no link. */
  private fun home(context: Context): PendingIntent? {
    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
    return PendingIntent.getActivity(context, 7_200, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
  }

  private fun dp(context: Context, value: Int): Int = (value * context.resources.displayMetrics.density).toInt()

  /** The room under the heading for rows, in dp. */
  private fun room(tall: Int): Int = tall - FRAME_DP

  /**
   * The room for rows where one of [need] dp must fit: under the heading where it does; else (a widget a cell high,
   * as the Today and Pinned widgets placed before the four may be) the heading put away and the rows in all of it.
   */
  private fun roomFor(context: Context, views: RemoteViews, tall: Int, need: Int): Int {
    if (room(tall) >= need) return room(tall)
    views.setViewVisibility(R.id.ghost_w_head, View.GONE)
    views.setViewPadding(R.id.ghost_w_root, dp(context, 12), dp(context, 4), dp(context, 8), dp(context, 4))
    return tall - 8
  }

  /** A row's height at the phone's text size: its words grow, so it does. */
  private fun scaled(context: Context, dp: Int): Int = (dp * context.resources.configuration.fontScale.coerceAtLeast(1f)).toInt()

  private fun eyebrow(context: Context, words: String, count: Int?): RemoteViews = RemoteViews(context.packageName, R.layout.ghost_w_eyebrow).apply {
    setTextViewText(R.id.ghost_w_eyebrow_words, words)
    setTextViewText(R.id.ghost_w_eyebrow_count, count?.toString() ?: "")
  }

  // ---- words, in the phone's own ------------------------------------------------------------------------------------

  private fun locale(context: Context): Locale = context.resources.configuration.locales[0] ?: Locale.getDefault()

  private fun weekdayOf(context: Context, ms: Long): String = SimpleDateFormat("EEEE", locale(context)).format(Date(ms))

  private fun dateOf(context: Context, ms: Long): String = SimpleDateFormat(DateFormat.getBestDateTimePattern(locale(context), "MMMMd"), locale(context)).format(Date(ms))

  /** A day `2026-10-03` at noon on this phone's clock. */
  private fun noonOf(day: String): Long {
    val (y, m, d) = day.split('-').map { it.toInt() }
    return Calendar.getInstance().apply {
      clear()
      set(y, m - 1, d, 12, 0)
    }.timeInMillis
  }

  private fun ago(context: Context, ms: Long, now: Long): String = HomeData.ago(ms, now, { weekdayOf(context, it) }, { dateOf(context, it) })

  private fun dueWords(context: Context, due: String, today: String): String =
    HomeData.dueWords(due, today, { weekdayOf(context, noonOf(it)) }, { dateOf(context, noonOf(it)) })

  private fun timeOf(context: Context, ms: Long): String = DateFormat.getTimeFormat(context).format(Date(ms))

  // ---- Voice note ----------------------------------------------------------------------------------------------------

  private fun voice(context: Context, wide: Int, tall: Int): RemoteViews {
    val takes = HomeData.notes(HomeScreen.kept(context, "voice"))
    val now = System.currentTimeMillis()
    val large = tall >= LARGE_DP
    val views = frame(context, R.drawable.ghost_w_ic_mic, "Voice note", "", R.drawable.ghost_w_ic_pen, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    // A cell high (a Quick note placed before the four): the ring at the dock's own size and no heading.
    val small = tall < FRAME_DP + HERO_DP
    if (small) {
      views.setViewVisibility(R.id.ghost_w_head, View.GONE)
      views.setViewPadding(R.id.ghost_w_root, dp(context, 10), dp(context, 4), dp(context, 10), dp(context, 4))
      views.setInt(R.id.ghost_w_root, "setGravity", Gravity.CENTER_VERTICAL)
    }
    val hero = RemoteViews(context.packageName, if (small) R.layout.ghost_w_voice_small else R.layout.ghost_w_voice_hero)
    val record = Doors.press(context, Doors.VOICE)
    hero.setOnClickPendingIntent(R.id.ghost_w_voice_ring, record)
    val last = takes.firstOrNull()
    if (large || last == null) {
      hero.setTextViewText(R.id.ghost_w_voice_title, "Tap to record")
      hero.setTextViewText(R.id.ghost_w_voice_line, "A new note, in your own words")
      hero.setOnClickPendingIntent(R.id.ghost_w_voice_words, record)
    } else {
      hero.setTextViewText(R.id.ghost_w_voice_title, last.title)
      hero.setTextViewText(R.id.ghost_w_voice_line, "${HomeData.counter(last.ms)} · ${ago(context, last.updated, now)}")
      hero.setOnClickPendingIntent(R.id.ghost_w_voice_words, Doors.press(context, Doors.noteAt(last.id), "voice:${last.id}".hashCode()))
    }
    views.addView(R.id.ghost_w_col_a, hero)
    // Medium: the microphone in the middle of what the heading leaves; large, the recordings under it from the top.
    views.setInt(R.id.ghost_w_body, "setGravity", if (large) Gravity.TOP else Gravity.CENTER_VERTICAL)
    if (large && takes.isNotEmpty()) {
      val room = room(tall) - HERO_DP - scaled(context, EYEBROW_DP)
      val shown = HomeData.fitting(room, takes.map { scaled(context, NOTE_DP) }, MORE_DP)
      if (shown > 0) {
        views.addView(R.id.ghost_w_col_a, eyebrow(context, "Recordings", null))
        for (take in takes.take(shown)) views.addView(R.id.ghost_w_col_a, noteRow(context, take, now))
      }
    }
    more(context, views, 0)
    empty(context, views, null)
    return views
  }

  // ---- To-dos --------------------------------------------------------------------------------------------------------

  private fun todos(context: Context, wide: Int, tall: Int): RemoteViews {
    val today = HomeScreen.today()
    val todos = HomeData.todos(HomeScreen.kept(context, "todos"))
    val views = frame(context, R.drawable.ghost_w_ic_todos, "To-dos", if (todos.isEmpty()) "" else "${todos.size}", R.drawable.ghost_w_ic_plus, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    // Each group's eyebrow, then its rows, in as many as fit; a group's eyebrow is never the last thing shown, and
    // where an eyebrow and a row do not both fit, the rows alone.
    val room = roomFor(context, views, tall, scaled(context, TODO_DP))
    val eyebrows = room >= scaled(context, EYEBROW_DP + TODO_DP)
    val parts = mutableListOf<Any>()
    for ((group, items) in HomeData.grouped(todos, today)) {
      if (eyebrows) parts.add(group to items.size)
      parts.addAll(items)
    }
    val heights = parts.map { if (it is HomeData.Todo) scaled(context, TODO_DP) else scaled(context, EYEBROW_DP) }
    var shown = HomeData.fitting(room, heights, 0)
    while (shown > 0 && parts[shown - 1] !is HomeData.Todo) shown -= 1
    for (part in parts.take(shown)) {
      if (part is HomeData.Todo) {
        views.addView(R.id.ghost_w_col_a, todoRow(context, part, today))
      } else if (part is Pair<*, *>) {
        views.addView(R.id.ghost_w_col_a, eyebrow(context, (part.first as HomeData.Group).words, part.second as Int))
      }
    }
    // The heading counts them all, so no line says how many did not fit: the room is rows'.
    more(context, views, 0)
    empty(context, views, if (todos.isEmpty()) "Nothing to do." else null, "To-dos you write in any note show here.")
    return views
  }

  private fun todoRow(context: Context, todo: HomeData.Todo, today: String): RemoteViews {
    val row = RemoteViews(context.packageName, R.layout.ghost_w_todo_row)
    val code = "${todo.note}:${todo.line}".hashCode()
    val group = HomeData.groupOf(todo.due, today)
    val overdue = group == HomeData.Group.OVERDUE
    row.setTextViewText(R.id.ghost_w_todo_words, todo.words)
    // A ticket is its whole note, whose title is its words already; a priority worth a word after the note's name.
    row.setTextViewText(R.id.ghost_w_todo_note, listOfNotNull(if (todo.line == 0) "Ticket" else todo.title, HomeData.priorityWords(todo.priority)).joinToString(" · "))
    val due = todo.due
    if (due == null) {
      row.setViewVisibility(R.id.ghost_w_todo_due, View.GONE)
    } else {
      // The chip as a note's line has it (field_chips.dart): red once passed, amber on the day, the second ink after.
      val (ground, ink, icon) = when (group) {
        HomeData.Group.OVERDUE -> Triple(R.drawable.ghost_w_chip_overdue, ink(context, R.color.ghost_w_light_red_11, R.color.ghost_w_dark_red_11), R.drawable.ghost_w_ic_due_overdue)
        HomeData.Group.TODAY -> Triple(R.drawable.ghost_w_chip_today, ink(context, R.color.ghost_w_light_amber_11, R.color.ghost_w_dark_amber_11), R.drawable.ghost_w_ic_due_today)
        else -> Triple(R.drawable.ghost_w_chip, ink(context, R.color.ghost_w_light_ink_2, R.color.ghost_w_dark_ink_2), R.drawable.ghost_w_ic_due)
      }
      row.setViewVisibility(R.id.ghost_w_todo_due, View.VISIBLE)
      row.setTextViewText(R.id.ghost_w_todo_due, dueWords(context, due, today))
      row.setInt(R.id.ghost_w_todo_due, "setBackgroundResource", ground)
      row.setTextColor(R.id.ghost_w_todo_due, ink)
      row.setTextViewCompoundDrawables(R.id.ghost_w_todo_due, icon, 0, 0, 0)
    }
    row.setOnClickPendingIntent(R.id.ghost_w_todo_text, Doors.press(context, Doors.noteAt(todo.note, todo.line, todo.match), code))
    val tick = tickOf(context, todo, code)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val box = if (overdue) R.id.ghost_w_check_late else R.id.ghost_w_check
      row.setViewVisibility(R.id.ghost_w_check, if (overdue) View.GONE else View.VISIBLE)
      row.setViewVisibility(R.id.ghost_w_check_late, if (overdue) View.VISIBLE else View.GONE)
      if (tick == null) {
        row.setViewVisibility(box, View.INVISIBLE)
      } else {
        row.setCompoundButtonChecked(box, false)
        row.setOnCheckedChangeResponse(box, RemoteViews.RemoteResponse.fromPendingIntent(tick))
      }
    } else {
      row.setImageViewResource(R.id.ghost_w_tick_ring, if (overdue) R.drawable.ghost_w_tick_late else R.drawable.ghost_w_tick_off)
      if (tick == null) row.setViewVisibility(R.id.ghost_w_tick, View.INVISIBLE) else row.setOnClickPendingIntent(R.id.ghost_w_tick, tick)
    }
    return row
  }

  private fun tickOf(context: Context, todo: HomeData.Todo, code: Int): PendingIntent? {
    return PendingIntent.getBroadcast(
      context,
      code,
      Intent(context, WidgetTicks::class.java)
        .setAction(WidgetTicks.ACTION_TICK)
        .setData(Uri.Builder().scheme("ghostmd-widget").authority("tick").appendPath(todo.note).appendPath(todo.line.toString()).build())
        .putExtra("words", todo.match),
      // Immutable: what the box's response would fill in (whether it is checked) is not read; a tick is a tick.
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
  }

  // ---- Calendar ------------------------------------------------------------------------------------------------------

  private fun calendar(context: Context, wide: Int, tall: Int): RemoteViews {
    val today = HomeScreen.today()
    val now = System.currentTimeMillis()
    val date = SimpleDateFormat(DateFormat.getBestDateTimePattern(locale(context), "EEEMMMd"), locale(context)).format(Date(now))
    val views = frame(context, R.drawable.ghost_w_ic_calendar, "Calendar", date, R.drawable.ghost_w_ic_plus, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    val read = HomeData.calendar(HomeScreen.kept(context, "calendar"))
    if (read == null || !read.on) {
      more(context, views, 0)
      empty(context, views, if (read == null) "Open Ghost.md" else "Turn on Calendar in Ghost.md", if (read == null) "Your calendar shows here once it has opened." else "Settings › Plugins › Calendar")
      return views
    }
    val todos = HomeData.todos(HomeScreen.kept(context, "todos"))
    val days = HomeData.agenda(read.events, todos, today, now)
    val parts = mutableListOf<Any>()
    for (day in days) {
      parts.add(day)
      parts.addAll(day.events)
      parts.addAll(day.todos)
    }
    val heights = parts.map { if (it is HomeData.Day) scaled(context, EYEBROW_DP) else scaled(context, EVENT_DP) }
    var shown = HomeData.fitting(roomFor(context, views, tall, scaled(context, EYEBROW_DP + EVENT_DP)), heights, 0)
    while (shown > 0 && parts[shown - 1] is HomeData.Day) shown -= 1
    for (part in parts.take(shown)) {
      when (part) {
        is HomeData.Day -> views.addView(R.id.ghost_w_col_a, eyebrow(context, HomeData.dayWords(part.day, today) { weekdayOf(context, noonOf(it)) }, part.events.size + part.todos.size))
        is HomeData.Event -> views.addView(R.id.ghost_w_col_a, eventRow(context, part))
        is HomeData.Todo -> views.addView(R.id.ghost_w_col_a, dueRow(context, part, today))
      }
    }
    // Each day's eyebrow counts its own; the room is rows'.
    more(context, views, 0)
    empty(context, views, if (parts.isEmpty()) "Nothing on your calendar" else null, "This week’s events and the to-dos due show here.")
    return views
  }

  private fun eventRow(context: Context, event: HomeData.Event): RemoteViews {
    val row = RemoteViews(context.packageName, R.layout.ghost_w_event_row)
    row.setTextViewText(R.id.ghost_w_event_time, if (event.allDay) "All day" else timeOf(context, event.start))
    row.setTextViewText(R.id.ghost_w_event_until, if (event.allDay) "" else timeOf(context, event.end))
    row.setViewVisibility(R.id.ghost_w_event_until, if (event.allDay) View.GONE else View.VISIBLE)
    row.setImageViewResource(R.id.ghost_w_event_mark, R.drawable.ghost_w_event_ring)
    row.setTextViewText(R.id.ghost_w_event_title, event.title)
    val sub = listOfNotNull(event.calendar.takeIf { it.isNotEmpty() }, event.location).joinToString(" · ")
    row.setTextViewText(R.id.ghost_w_event_sub, sub)
    row.setViewVisibility(R.id.ghost_w_event_sub, if (sub.isEmpty()) View.GONE else View.VISIBLE)
    home(context)?.let { row.setOnClickPendingIntent(R.id.ghost_w_event_row, it) }
    return row
  }

  private fun dueRow(context: Context, todo: HomeData.Todo, today: String): RemoteViews {
    val row = RemoteViews(context.packageName, R.layout.ghost_w_event_row)
    val late = HomeData.groupOf(todo.due, today) == HomeData.Group.OVERDUE
    // Where the time would be: what it is, in the red where it is late (its day is the To-dos widget's to say).
    row.setTextViewText(R.id.ghost_w_event_time, if (late) "Overdue" else "To-do")
    if (late) row.setTextColor(R.id.ghost_w_event_time, ink(context, R.color.ghost_w_light_red_11, R.color.ghost_w_dark_red_11))
    row.setViewVisibility(R.id.ghost_w_event_until, View.GONE)
    row.setImageViewResource(R.id.ghost_w_event_mark, if (late) R.drawable.ghost_w_pip_late else R.drawable.ghost_w_pip)
    row.setTextViewText(R.id.ghost_w_event_title, todo.words)
    row.setTextViewText(R.id.ghost_w_event_sub, if (todo.line == 0) "Ticket" else todo.title)
    row.setOnClickPendingIntent(R.id.ghost_w_event_row, Doors.press(context, Doors.noteAt(todo.note, todo.line, todo.match), "due:${todo.note}:${todo.line}".hashCode()))
    return row
  }

  // ---- Recent notes ----------------------------------------------------------------------------------------------------

  private fun notes(context: Context, wide: Int, tall: Int): RemoteViews {
    val rows = HomeData.notes(HomeScreen.kept(context, "notes"))
    val now = System.currentTimeMillis()
    val views = frame(context, R.drawable.ghost_w_ic_note, "Recent notes", "", R.drawable.ghost_w_ic_pen, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    val each = scaled(context, NOTE_DP)
    val columns = if (tall >= LARGE_DP && wide >= TWO_COLUMNS_DP) 2 else 1
    val room = roomFor(context, views, tall, each + if (rows.size > 1) MORE_DP else 0)
    val perColumn = HomeData.fitting(room, List(rows.size) { each }, if (room(tall) == room) MORE_DP else 0)
    val shown = rows.take(perColumn * columns)
    val first = if (columns == 2) (shown.size + 1) / 2 else shown.size
    for ((index, note) in shown.withIndex()) views.addView(if (index < first) R.id.ghost_w_col_a else R.id.ghost_w_col_b, noteRow(context, note, now))
    views.setViewVisibility(R.id.ghost_w_col_b, if (columns == 2 && shown.size > first) View.VISIBLE else View.GONE)
    // A cell high, no line under the one row: the heading that counted is put away too.
    more(context, views, if (room(tall) == room) rows.size - shown.size else 0)
    empty(context, views, if (rows.isEmpty()) "No notes yet" else null, "The notes you write in show here.", Doors.press(context, Doors.NEW))
    return views
  }

  private fun noteRow(context: Context, note: HomeData.Row, now: Long): RemoteViews {
    val row = RemoteViews(context.packageName, R.layout.ghost_w_note_row)
    row.setImageViewResource(
      R.id.ghost_w_note_mark,
      when (note.kind) {
        "tape" -> R.drawable.ghost_w_ic_tape
        "book" -> R.drawable.ghost_w_ic_book
        "canvas" -> R.drawable.ghost_w_ic_canvas
        else -> R.drawable.ghost_w_ic_note
      },
    )
    row.setTextViewText(R.id.ghost_w_note_title, note.title)
    val line = HomeData.lineOf(note)
    row.setTextViewText(R.id.ghost_w_note_line, line)
    row.setViewVisibility(R.id.ghost_w_note_line, if (line.isEmpty()) View.GONE else View.VISIBLE)
    row.setTextViewText(R.id.ghost_w_note_when, ago(context, note.updated, now))
    row.setOnClickPendingIntent(R.id.ghost_w_note_row, Doors.press(context, Doors.noteAt(note.id), "note:${note.id}".hashCode()))
    return row
  }
}
