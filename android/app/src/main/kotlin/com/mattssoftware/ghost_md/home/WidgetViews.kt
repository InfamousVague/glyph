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
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.RemoteViews
import com.mattssoftware.ghost_md.R
import com.mattssoftware.ghost_md.home.HomeData.Fit
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * How the widgets are drawn (docs/WIDGETS_ANDROID.md), in the app's look: the frame (layout/ghost_w_frame.xml), its
 * heading as the home page heads a section, and what each widget has room for at the size it is. This file has the
 * frame, what every widget shares, and the four first; MoreWidgetViews.kt the eight more.
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
 * **Sizes** (HomeData.Fit; Matt, 2026-10-21: "I want to have more 2xN and 1x1 also make sure they take up 100% of
 * avail space"): a cell each way (1×1) draws one thing in the middle of the cell (`tile`: the microphone, a count, the
 * day); a cell high (2×1, 4×1) puts the heading away and gives the cell to one row; two cells across (2×N) draws a
 * column, as many rows as its height holds; four by two and four by four as before. The ground is the frame's root,
 * the whole of what the launcher gives, with the launcher's own corners (drawable-v31/ghost_w_back.xml), and what is
 * in it grows into the room: more rows, a bigger ring, a grid's rows sharing the height. A list fills its height to
 * the bottom (HomeData.fill, [placed]): whole rows while the next fits, then one-line rows (a to-do's tick and words,
 * an event's time and title, a note's name) while they do, then "N more" where it has its room; what is left, less
 * than a row, is shared out between the rows rather than left as a band under the last.
 *
 * From Android 12 the launcher says each size the widget is drawn at (upright and on its side), and a view is made for
 * each (`RemoteViews(Map<SizeF, RemoteViews>)`), so the launcher shows the right one as it turns or resizes with
 * nothing asked of the app. Before 12, the size the widget says it is in this orientation.
 */
object WidgetViews {
  // The frame's padding, in dp (layout/ghost_w_frame.xml), kept off the launcher's edge by a margin you can see (Matt,
  // 2026-10-21: "Add a bit more padding to the widgets stuff is too edge to edge").
  internal const val PAD_START = 20
  internal const val PAD_TOP = 14
  internal const val PAD_END = 16
  internal const val PAD_BOTTOM = 14

  /** What a widget with no heading keeps at its edges besides the room it asks for ([headless]). */
  internal const val INSET = 6

  // The frame's own room, in dp: its padding above and below and its heading.
  internal const val FRAME_DP = PAD_TOP + PAD_BOTTOM + 34
  internal const val MORE_DP = 18
  internal const val EYEBROW_DP = 22
  internal const val TODO_DP = 48
  internal const val NOTE_DP = 52
  internal const val COMPACT_DP = 36
  internal const val EVENT_DP = 46
  internal const val HERO_DP = 76

  /** Two columns of rows from this wide, when large: the Fold opened. */
  internal const val TWO_COLUMNS_DP = 420

  fun draw(context: Context, manager: AppWidgetManager, id: Int, kind: WidgetKind) {
    manager.updateAppWidget(id, views(context, manager.getAppWidgetOptions(id), kind, id))
  }

  fun views(context: Context, options: Bundle?, kind: WidgetKind, id: Int): RemoteViews {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val sizes = sizesOf(options)
      if (sizes.isNotEmpty()) return RemoteViews(sizes.associateWith { build(context, kind, id, it.width.toInt(), it.height.toInt()) })
    }
    // Upright, a widget is its minimum width by its maximum height; on its side, its maximum width by its minimum
    // height (the Fold opened and turned).
    val sideways = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
    val wide = options?.getInt(if (sideways) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)?.takeIf { it > 0 } ?: 250
    val tall = options?.getInt(if (sideways) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)?.takeIf { it > 0 } ?: 160
    return build(context, kind, id, wide, tall)
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

  fun build(context: Context, kind: WidgetKind, id: Int, wide: Int, tall: Int): RemoteViews = when (kind) {
    WidgetKind.VOICE -> voice(context, wide, tall)
    WidgetKind.TODOS -> todos(context, wide, tall)
    WidgetKind.CALENDAR -> calendar(context, wide, tall)
    WidgetKind.NOTES -> notes(context, wide, tall)
    else -> MoreWidgetViews.build(context, kind, id, wide, tall)
  }

  // ---- the frame ---------------------------------------------------------------------------------------------------

  /**
   * Whether the widgets are drawn dark: the app's theme (HomeScreen.look; its own default is Dark), the phone's mode
   * where the app follows the phone.
   */
  internal fun dark(context: Context): Boolean = when (HomeScreen.look(context)) {
    "light" -> false
    "system" -> (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    else -> true
  }

  /** A colour set from here (a due chip's words), in the look the widget is drawn in. */
  internal fun ink(context: Context, light: Int, dark: Int): Int = context.getColor(if (dark(context)) dark else light)

  internal fun frame(context: Context, mark: Int, title: String, count: String, action: Int, actionSaid: String, actionLink: String): RemoteViews {
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
    views.setViewVisibility(R.id.ghost_w_action, View.VISIBLE)
    views.setViewVisibility(R.id.ghost_w_col_b, View.GONE)
    views.setViewPadding(R.id.ghost_w_root, dp(context, PAD_START), dp(context, PAD_TOP), dp(context, PAD_END), dp(context, PAD_BOTTOM))
    views.setInt(R.id.ghost_w_root, "setGravity", Gravity.TOP or Gravity.START)
    views.setInt(R.id.ghost_w_body, "setGravity", Gravity.TOP or Gravity.START)
    views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.TOP or Gravity.START)
    views.setInt(R.id.ghost_w_col_b, "setGravity", Gravity.TOP or Gravity.START)
    return views
  }

  /** A narrow widget (two cells across) keeps less room at its sides, so its rows have more. */
  internal fun narrowed(context: Context, views: RemoteViews) {
    views.setViewPadding(R.id.ghost_w_root, dp(context, PAD_START - 6), dp(context, PAD_TOP), dp(context, PAD_END - 6), dp(context, PAD_BOTTOM))
  }

  /** No heading: a widget a cell high, or one whose own top is its heading (Search's field), gives it all to its rows. */
  internal fun headless(context: Context, views: RemoteViews, sides: Int = 12, ends: Int = 4, inset: Int = INSET) {
    views.setViewVisibility(R.id.ghost_w_head, View.GONE)
    views.setViewPadding(R.id.ghost_w_root, dp(context, sides + inset), dp(context, ends + inset), dp(context, sides - 4 + inset), dp(context, ends + inset))
  }

  /** The line under a list for the [left] rows that did not fit (none: gone), a tap [link]: the app, or the note. */
  internal fun more(context: Context, views: RemoteViews, left: Int, link: PendingIntent? = home(context)) {
    views.setViewVisibility(R.id.ghost_w_more, if (left > 0) View.VISIBLE else View.GONE)
    views.setTextViewText(R.id.ghost_w_more, "$left more")
    link?.let { views.setOnClickPendingIntent(R.id.ghost_w_more, it) }
  }

  /** The line under a list as [filled] says: how many did not fit, where they did not and it has its room. */
  internal fun more(context: Context, views: RemoteViews, filled: HomeData.Filled, link: PendingIntent? = home(context)) {
    more(context, views, if (filled.more) filled.left else 0, link)
  }

  /**
   * A list's [rows] (each a row and whether it is a heading) into [column]; where [spread], the room the list leaves
   * shared between them (layout/ghost_w_gap.xml before each row but a heading's first, and before the first where
   * [after] something else is above it in the column), so it is a little more space between the rows rather than a
   * band under the last.
   */
  internal fun placed(context: Context, views: RemoteViews, column: Int, rows: List<Pair<RemoteViews, Boolean>>, spread: Boolean, after: Boolean = false) {
    for ((index, row) in rows.withIndex()) {
      val gap = if (index == 0) after else !rows[index - 1].second
      if (spread && gap) views.addView(column, RemoteViews(context.packageName, R.layout.ghost_w_gap))
      views.addView(column, row.first)
    }
  }

  internal fun empty(context: Context, views: RemoteViews, title: String?, words: String = "", link: PendingIntent? = home(context)) {
    views.setViewVisibility(R.id.ghost_w_empty, if (title == null) View.GONE else View.VISIBLE)
    views.setViewVisibility(R.id.ghost_w_body, if (title == null) View.VISIBLE else View.GONE)
    if (title == null) return
    views.setTextViewText(R.id.ghost_w_empty_title, title)
    views.setTextViewText(R.id.ghost_w_empty_words, words)
    views.setViewVisibility(R.id.ghost_w_empty_words, if (words.isEmpty()) View.GONE else View.VISIBLE)
    link?.let { views.setOnClickPendingIntent(R.id.ghost_w_empty, it) }
  }

  /**
   * A cell each way (1×1): the frame with its heading away and its padding a hair, and in the middle of the cell one
   * round button ([icon] on [ring], tinted [tint]) or one big word ([big]), [label] under it and a dot before the
   * label where [dot]; the whole cell [link].
   */
  internal fun tile(
    context: Context,
    views: RemoteViews,
    icon: Int? = null,
    ring: Int = R.drawable.ghost_w_ring,
    tint: Int? = null,
    big: String? = null,
    bigColour: Int? = null,
    label: String,
    labelColour: Int? = null,
    dot: Boolean = false,
    link: PendingIntent?,
    said: String = label,
  ): RemoteViews {
    headless(context, views, sides = 6, ends = 4, inset = 4)
    val tile = RemoteViews(context.packageName, R.layout.ghost_w_tile)
    tile.setViewVisibility(R.id.ghost_w_tile_ring, if (icon != null) View.VISIBLE else View.GONE)
    if (icon != null) {
      tile.setImageViewResource(R.id.ghost_w_tile_icon, icon)
      tile.setInt(R.id.ghost_w_tile_ring, "setBackgroundResource", ring)
      if (tint != null) tile.setInt(R.id.ghost_w_tile_icon, "setColorFilter", tint)
    }
    tile.setViewVisibility(R.id.ghost_w_tile_big, if (big != null) View.VISIBLE else View.GONE)
    if (big != null) tile.setTextViewText(R.id.ghost_w_tile_big, big)
    if (bigColour != null) tile.setTextColor(R.id.ghost_w_tile_big, bigColour)
    tile.setTextViewText(R.id.ghost_w_tile_label, label)
    if (labelColour != null) tile.setTextColor(R.id.ghost_w_tile_label, labelColour)
    tile.setViewVisibility(R.id.ghost_w_tile_dot, if (dot) View.VISIBLE else View.GONE)
    tile.setContentDescription(R.id.ghost_w_tile, said)
    link?.let { tile.setOnClickPendingIntent(R.id.ghost_w_tile, it) }
    views.addView(R.id.ghost_w_col_a, tile)
    more(context, views, 0)
    empty(context, views, null)
    return views
  }

  /** The app's home page: its own launch, no link. */
  internal fun home(context: Context): PendingIntent? {
    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
    return PendingIntent.getActivity(context, 7_200, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
  }

  internal fun dp(context: Context, value: Int): Int = (value * context.resources.displayMetrics.density).toInt()

  /** A view's width and height set to [size] dp, from Android 12 (`setViewLayoutWidth`); before, as its layout says. */
  internal fun sized(views: RemoteViews, id: Int, size: Int) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    views.setViewLayoutWidth(id, size.toFloat(), TypedValue.COMPLEX_UNIT_DIP)
    views.setViewLayoutHeight(id, size.toFloat(), TypedValue.COMPLEX_UNIT_DIP)
  }

  /** The room under the heading for rows, in dp. */
  internal fun room(tall: Int): Int = tall - FRAME_DP

  /**
   * The room for rows where one of [need] dp must fit: under the heading where it does; else (a widget a cell high)
   * the heading put away and the rows in all of it.
   */
  internal fun roomFor(context: Context, views: RemoteViews, tall: Int, need: Int): Int {
    if (room(tall) >= need) return room(tall)
    headless(context, views, sides = 12, ends = 4)
    return tall - 8 - 2 * INSET
  }

  /** A row's height at the phone's text size: its words grow, so it does. */
  internal fun scaled(context: Context, dp: Int): Int = (dp * context.resources.configuration.fontScale.coerceAtLeast(1f)).toInt()

  internal fun eyebrow(context: Context, words: String, count: Int?): RemoteViews = RemoteViews(context.packageName, R.layout.ghost_w_eyebrow).apply {
    setTextViewText(R.id.ghost_w_eyebrow_words, words)
    setTextViewText(R.id.ghost_w_eyebrow_count, count?.toString() ?: "")
  }

  // ---- words, in the phone's own ------------------------------------------------------------------------------------

  internal fun locale(context: Context): Locale = context.resources.configuration.locales[0] ?: Locale.getDefault()

  internal fun weekdayOf(context: Context, ms: Long): String = SimpleDateFormat("EEEE", locale(context)).format(Date(ms))

  internal fun dateOf(context: Context, ms: Long): String = SimpleDateFormat(DateFormat.getBestDateTimePattern(locale(context), "MMMMd"), locale(context)).format(Date(ms))

  /** A date in the phone's words by [skeleton]: "Tue, Oct 21" (`EEEMMMd`), "Tue 21" (`EEEd`), "21" (`d`). */
  internal fun dayIn(context: Context, ms: Long, skeleton: String): String = SimpleDateFormat(DateFormat.getBestDateTimePattern(locale(context), skeleton), locale(context)).format(Date(ms))

  /** A day `2026-10-03` at noon on this phone's clock. */
  internal fun noonOf(day: String): Long {
    val (y, m, d) = day.split('-').map { it.toInt() }
    return Calendar.getInstance().apply {
      clear()
      set(y, m - 1, d, 12, 0)
    }.timeInMillis
  }

  internal fun ago(context: Context, ms: Long, now: Long): String = HomeData.ago(ms, now, { weekdayOf(context, it) }, { dateOf(context, it) })

  internal fun dueWords(context: Context, due: String, today: String): String =
    HomeData.dueWords(due, today, { weekdayOf(context, noonOf(it)) }, { dateOf(context, noonOf(it)) })

  internal fun timeOf(context: Context, ms: Long): String = DateFormat.getTimeFormat(context).format(Date(ms))

  // ---- a microphone, Voice note's and Ask AI's ----------------------------------------------------------------------

  /** A ring and its words: the dock's filled Speak, or Talk to Claude's orange ring with its orange mic. */
  internal class Mic(val ring: Int, val icon: Int, val tint: Int?, val title: String, val line: String, val press: PendingIntent, val wordsPress: PendingIntent, val said: String)

  /**
   * [mic] drawn for the size: a cell high, at the dock's own size beside its words; two cells across, in the middle of
   * the column and as big as its room, its words under it; else big beside its words. [square] draws it the
   * column's way at any size (Ask AI, large), leaving [reserve] dp under it for what follows. The heading goes where
   * the ring would want its room. Answers the dp it takes.
   */
  internal fun micInto(context: Context, views: RemoteViews, fit: Fit, wide: Int, tall: Int, mic: Mic, reserve: Int = 0, square: Boolean = fit == Fit.NARROW): Int {
    val layout = when {
      fit == Fit.SLIM -> R.layout.ghost_w_voice_small
      square -> R.layout.ghost_w_voice_square
      else -> R.layout.ghost_w_voice_hero
    }
    val hero = RemoteViews(context.packageName, layout)
    hero.setInt(R.id.ghost_w_voice_ring, "setBackgroundResource", mic.ring)
    hero.setImageViewResource(R.id.ghost_w_voice_icon, mic.icon)
    mic.tint?.let { hero.setInt(R.id.ghost_w_voice_icon, "setColorFilter", it) }
    hero.setContentDescription(R.id.ghost_w_voice_ring, mic.said)
    hero.setOnClickPendingIntent(R.id.ghost_w_voice_ring, mic.press)
    hero.setTextViewText(R.id.ghost_w_voice_title, mic.title)
    hero.setTextViewText(R.id.ghost_w_voice_line, mic.line)
    hero.setViewVisibility(R.id.ghost_w_voice_line, if (mic.line.isEmpty()) View.GONE else View.VISIBLE)
    hero.setOnClickPendingIntent(R.id.ghost_w_voice_words, mic.wordsPress)
    var used = HERO_DP
    when {
      fit == Fit.SLIM -> {
        headless(context, views, sides = 10, ends = 4)
        views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.CENTER_VERTICAL)
      }
      square -> {
        if (fit == Fit.NARROW) narrowed(context, views)
        // The ring as big as the column and its height leave, with room for two lines of words under it; the heading
        // only where it still leaves the ring the dock's size and more.
        val words = scaled(context, if (mic.line.isEmpty()) 30 else 44) + reserve
        if (room(tall) - words < 72) headless(context, views, sides = 12, ends = 6)
        val left = (if (room(tall) - words < 72) tall - 12 - 2 * INSET else room(tall)) - words
        val ring = minOf(wide - 44, left - 8, 136).coerceAtLeast(44)
        sized(hero, R.id.ghost_w_voice_ring, ring)
        sized(hero, R.id.ghost_w_voice_icon, ring * 7 / 16)
        used = ring + words + 8
        views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.CENTER)
      }
      else -> views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.CENTER_VERTICAL)
    }
    views.addView(R.id.ghost_w_col_a, hero)
    return used
  }

  // ---- Voice note ----------------------------------------------------------------------------------------------------

  private fun voice(context: Context, wide: Int, tall: Int): RemoteViews {
    val takes = HomeData.notes(HomeScreen.kept(context, "voice"))
    val now = System.currentTimeMillis()
    val fit = HomeData.fitOf(wide, tall)
    val views = frame(context, R.drawable.ghost_w_ic_mic, "Voice note", "", R.drawable.ghost_w_ic_pen, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    val record = Doors.press(context, Doors.VOICE)
    if (fit == Fit.TINY) {
      return tile(context, views, icon = R.drawable.ghost_w_ic_mic, ring = R.drawable.ghost_w_ring_ink, tint = ink(context, R.color.ghost_w_light_on_ink, R.color.ghost_w_dark_on_ink), label = "Record", link = record, said = context.getString(R.string.ghost_shortcut_voice_long))
    }
    val large = fit == Fit.LARGE || (fit == Fit.NARROW && tall >= 260)
    val last = takes.firstOrNull()
    val fresh = large || last == null
    val mic = Mic(
      R.drawable.ghost_w_ring_ink,
      R.drawable.ghost_w_ic_mic,
      null,
      if (fresh) "Tap to record" else last!!.title,
      when {
        fresh && fit == Fit.NARROW -> ""
        fresh -> "A new note, in your own words"
        else -> "${HomeData.counter(last!!.ms)} · ${ago(context, last.updated, now)}"
      },
      record,
      if (fresh) record else Doors.press(context, Doors.noteAt(last!!.id), "voice:${last.id}".hashCode()),
      context.getString(R.string.ghost_shortcut_voice_long),
    )
    val used = micInto(context, views, fit, wide, tall, mic)
    // Large (and a tall column): the recordings under the microphone, from the top.
    var filled: HomeData.Filled? = null
    if (large && takes.isNotEmpty()) {
      views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.TOP or Gravity.CENTER_HORIZONTAL)
      val small = scaled(context, COMPACT_DP)
      val each = HomeData.Part(if (fit == Fit.NARROW) small else scaled(context, NOTE_DP), small)
      val fill = HomeData.fill(room(tall) - used, listOf(HomeData.Part(scaled(context, EYEBROW_DP), heading = true)) + takes.map { each }, scaled(context, MORE_DP))
      if (fill.shown > 1) {
        filled = fill
        val rows = takes.take(fill.shown - 1).mapIndexed { index, take -> (if (fit == Fit.NARROW || fill.compact(index + 1)) compactRow(context, take) else noteRow(context, take, now)) to false }
        placed(context, views, R.id.ghost_w_col_a, listOf(eyebrow(context, "Recordings", null) to true) + rows, fill.spread, after = true)
      }
    }
    if (filled != null) more(context, views, filled) else more(context, views, 0)
    empty(context, views, null)
    return views
  }

  // ---- To-dos --------------------------------------------------------------------------------------------------------

  private fun todos(context: Context, wide: Int, tall: Int): RemoteViews {
    val today = HomeScreen.today()
    val todos = HomeData.todos(HomeScreen.kept(context, "todos"))
    val fit = HomeData.fitOf(wide, tall)
    val views = frame(context, R.drawable.ghost_w_ic_todos, "To-dos", if (todos.isEmpty()) "" else "${todos.size}", R.drawable.ghost_w_ic_plus, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    if (fit == Fit.TINY) {
      // How many are open, and under it how many are overdue, in the red, where any are.
      val late = todos.count { HomeData.groupOf(it.due, today) == HomeData.Group.OVERDUE }
      return tile(
        context,
        views,
        big = "${todos.size}",
        label = if (late > 0) "$late overdue" else "To do",
        labelColour = if (late > 0) ink(context, R.color.ghost_w_light_red_11, R.color.ghost_w_dark_red_11) else null,
        link = home(context),
        said = "${todos.size} to-dos open",
      )
    }
    if (fit == Fit.NARROW) narrowed(context, views)
    // Each group's eyebrow, then its rows, in as many as fit (HomeData.fill): whole rows, then one-line rows for the
    // room under them, a group's eyebrow only with a row under it; where an eyebrow and a row do not both fit, the
    // rows alone.
    val room = roomFor(context, views, tall, scaled(context, TODO_DP))
    val eyebrows = room >= scaled(context, EYEBROW_DP + TODO_DP)
    val parts = mutableListOf<Any>()
    for ((group, items) in HomeData.grouped(todos, today)) {
      if (eyebrows) parts.add(group to items.size)
      parts.addAll(items)
    }
    // In a column a to-do's words take two lines where they need them, and its row the room they make.
    val perRow = ((wide - 76) / (16.2f * 0.47f * context.resources.configuration.fontScale.coerceAtLeast(1f))).toInt().coerceAtLeast(8)
    val small = scaled(context, COMPACT_DP)
    val filled = HomeData.fill(
      room,
      parts.map {
        when {
          it !is HomeData.Todo -> HomeData.Part(scaled(context, EYEBROW_DP), heading = true)
          fit == Fit.NARROW -> HomeData.Part(maxOf(TODO_DP, scaled(context, 8 + 21 * HomeData.rowsFor(it.words.length, perRow, 2) + 20)), small)
          else -> HomeData.Part(scaled(context, TODO_DP), small)
        }
      },
      if (room(tall) == room) scaled(context, MORE_DP) else 0,
    )
    val rows = parts.take(filled.shown).mapIndexed { index, part ->
      if (part is HomeData.Todo) {
        todoRow(context, part, today, narrow = fit == Fit.NARROW, compact = filled.compact(index)) to false
      } else {
        val (group, count) = part as Pair<*, *>
        eyebrow(context, (group as HomeData.Group).words, count as Int) to true
      }
    }
    placed(context, views, R.id.ghost_w_col_a, rows, filled.spread)
    // The heading counts them all; a line says how many did not fit only where the rows leave it its room.
    more(context, views, filled)
    empty(context, views, if (todos.isEmpty()) "Nothing to do." else null, if (fit == Fit.SLIM) "" else "To-dos you write in any note show here.")
    return views
  }

  /**
   * A to-do's row; [narrow] (two cells across), the due day's chip alone under the words where it has one; [compact],
   * one line, its tick and its words alone (layout/ghost_w_todo_row_compact.xml), for the room under the whole rows.
   */
  internal fun todoRow(context: Context, todo: HomeData.Todo, today: String, narrow: Boolean = false, compact: Boolean = false): RemoteViews {
    val row = RemoteViews(
      context.packageName,
      when {
        compact -> R.layout.ghost_w_todo_row_compact
        narrow -> R.layout.ghost_w_todo_row_tall
        else -> R.layout.ghost_w_todo_row
      },
    )
    val code = "${todo.note}:${todo.line}".hashCode()
    val group = HomeData.groupOf(todo.due, today)
    val overdue = group == HomeData.Group.OVERDUE
    row.setTextViewText(R.id.ghost_w_todo_words, todo.words)
    row.setOnClickPendingIntent(R.id.ghost_w_todo_text, Doors.press(context, Doors.noteAt(todo.note, todo.line, todo.match), code))
    tickInto(context, row, todo, overdue, code)
    if (compact) return row
    // A ticket is its whole note, whose title is its words already; a priority worth a word after the note's name.
    row.setTextViewText(R.id.ghost_w_todo_note, listOfNotNull(if (todo.line == 0) "Ticket" else todo.title, HomeData.priorityWords(todo.priority)).joinToString(" · "))
    row.setViewVisibility(R.id.ghost_w_todo_note, if (narrow && todo.due != null) View.GONE else View.VISIBLE)
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
    return row
  }

  /** A to-do row's tick: from Android 12 its real box (the red one where [overdue]), before it the ring to press. */
  private fun tickInto(context: Context, row: RemoteViews, todo: HomeData.Todo, overdue: Boolean, code: Int) {
    val tick = tickOf(context, todo.note, todo.line, todo.match, code)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val box = if (overdue) R.id.ghost_w_check_late else R.id.ghost_w_check
      row.setViewVisibility(R.id.ghost_w_check, if (overdue) View.GONE else View.VISIBLE)
      row.setViewVisibility(R.id.ghost_w_check_late, if (overdue) View.VISIBLE else View.GONE)
      row.setCompoundButtonChecked(box, false)
      row.setOnCheckedChangeResponse(box, RemoteViews.RemoteResponse.fromPendingIntent(tick))
    } else {
      row.setImageViewResource(R.id.ghost_w_tick_ring, if (overdue) R.drawable.ghost_w_tick_late else R.drawable.ghost_w_tick_off)
      row.setOnClickPendingIntent(R.id.ghost_w_tick, tick)
    }
  }

  /** The tick of [line] of [note] (said as [words]): the app's own broadcast, which ticks it without opening the app. */
  internal fun tickOf(context: Context, note: String, line: Int, words: String, code: Int): PendingIntent {
    return PendingIntent.getBroadcast(
      context,
      code,
      Intent(context, WidgetTicks::class.java)
        .setAction(WidgetTicks.ACTION_TICK)
        .setData(Uri.Builder().scheme("ghostmd-widget").authority("tick").appendPath(note).appendPath(line.toString()).build())
        .putExtra("words", words),
      // Immutable: what the box's response would fill in (whether it is checked) is not read; a tick is a tick.
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
  }

  // ---- Calendar ------------------------------------------------------------------------------------------------------

  private fun calendar(context: Context, wide: Int, tall: Int): RemoteViews {
    val today = HomeScreen.today()
    val now = System.currentTimeMillis()
    val fit = HomeData.fitOf(wide, tall)
    // Two cells across, the date alone is the heading ("Tue 21"); wider, "Calendar" and the date beside it.
    val narrow = fit == Fit.NARROW
    val views = frame(
      context,
      R.drawable.ghost_w_ic_calendar,
      if (narrow) dayIn(context, now, "MMMd") else "Calendar",
      if (narrow) "" else dayIn(context, now, "EEEMMMd"),
      R.drawable.ghost_w_ic_plus,
      context.getString(R.string.ghost_shortcut_new_long),
      Doors.NEW,
    )
    if (narrow) narrowed(context, views)
    val read = HomeData.calendar(HomeScreen.kept(context, "calendar"))
    val todos = HomeData.todos(HomeScreen.kept(context, "todos"))
    val days = if (read?.on == true) HomeData.agenda(read.events, todos, today, now) else emptyList()
    if (fit == Fit.TINY) {
      // The day, as a desk calendar's page, and how many things are on it.
      val on = days.firstOrNull { it.day == today }?.let { it.events.size + it.todos.size } ?: 0
      return tile(context, views, big = dayIn(context, now, "d"), label = dayIn(context, now, "EEE") + if (on > 0) " · $on" else "", dot = false, link = home(context), said = dayIn(context, now, "EEEEMMMMd"))
    }
    if (read == null || !read.on) {
      if (fit == Fit.SLIM) headless(context, views)
      more(context, views, 0)
      empty(context, views, if (read == null) "Open Ghost.md" else "Turn on Calendar in Ghost.md", if (read == null) "Your calendar shows here once it has opened." else "Settings › Plugins › Calendar")
      return views
    }
    val parts = mutableListOf<Any>()
    for (day in days) {
      // A cell high, the next things without the days' eyebrows: the room is one row's.
      if (fit != Fit.SLIM) parts.add(day)
      parts.addAll(day.events)
      parts.addAll(day.todos)
    }
    // As To-dos fills its room: whole rows, then one-line ones (the time and the words), a day's eyebrow only with a
    // row under it.
    val room = roomFor(context, views, tall, scaled(context, if (fit == Fit.SLIM) EVENT_DP else EYEBROW_DP + EVENT_DP))
    val each = HomeData.Part(scaled(context, EVENT_DP), scaled(context, COMPACT_DP))
    val filled = HomeData.fill(room, parts.map { if (it is HomeData.Day) HomeData.Part(scaled(context, EYEBROW_DP), heading = true) else each }, if (room(tall) == room) scaled(context, MORE_DP) else 0)
    val narrowRows = wide < HomeData.NARROW_DP
    val rows = parts.take(filled.shown).mapIndexed { index, part ->
      when (part) {
        is HomeData.Day -> eyebrow(context, HomeData.dayWords(part.day, today) { weekdayOf(context, noonOf(it)) }, part.events.size + part.todos.size) to true
        is HomeData.Event -> eventRow(context, part, narrow = narrowRows, compact = filled.compact(index)) to false
        else -> dueRow(context, part as HomeData.Todo, today, narrow = narrowRows, compact = filled.compact(index)) to false
      }
    }
    placed(context, views, R.id.ghost_w_col_a, rows, filled.spread)
    if (fit == Fit.SLIM) views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.CENTER_VERTICAL)
    // Each day's eyebrow counts its own; a line says how many did not fit only where the rows leave it its room.
    more(context, views, filled)
    empty(context, views, if (parts.isEmpty()) "Nothing on your calendar" else null, if (fit == Fit.SLIM) "" else "This week’s events and the to-dos due show here.")
    return views
  }

  /** An event's or a due to-do's row: [compact], one line, when and the words (ghost_w_event_row_compact*.xml). */
  private fun eventLayout(narrow: Boolean, compact: Boolean): Int = when {
    compact && narrow -> R.layout.ghost_w_event_row_compact_narrow
    compact -> R.layout.ghost_w_event_row_compact
    narrow -> R.layout.ghost_w_event_row_narrow
    else -> R.layout.ghost_w_event_row
  }

  /**
   * An event's row; [narrow] (two cells across), when it runs under its words, its calendar left out for the room;
   * [compact], one line, the time it starts and its words, for the room under the whole rows.
   */
  internal fun eventRow(context: Context, event: HomeData.Event, narrow: Boolean = false, compact: Boolean = false): RemoteViews {
    val row = RemoteViews(context.packageName, eventLayout(narrow, compact))
    row.setImageViewResource(R.id.ghost_w_event_mark, R.drawable.ghost_w_event_ring)
    row.setTextViewText(R.id.ghost_w_event_title, event.title)
    home(context)?.let { row.setOnClickPendingIntent(R.id.ghost_w_event_row, it) }
    if (compact) {
      row.setTextViewText(R.id.ghost_w_event_time, if (event.allDay) "All day" else timeOf(context, event.start))
      return row
    }
    if (narrow) {
      row.setTextViewText(R.id.ghost_w_event_time, if (event.allDay) "All day" else "${timeOf(context, event.start)} – ${timeOf(context, event.end)}")
      return row
    }
    row.setTextViewText(R.id.ghost_w_event_time, if (event.allDay) "All day" else timeOf(context, event.start))
    row.setTextViewText(R.id.ghost_w_event_until, if (event.allDay) "" else timeOf(context, event.end))
    row.setViewVisibility(R.id.ghost_w_event_until, if (event.allDay) View.GONE else View.VISIBLE)
    val sub = listOfNotNull(event.calendar.takeIf { it.isNotEmpty() }, event.location).joinToString(" · ")
    row.setTextViewText(R.id.ghost_w_event_sub, sub)
    row.setViewVisibility(R.id.ghost_w_event_sub, if (sub.isEmpty()) View.GONE else View.VISIBLE)
    return row
  }

  /** A to-do due on a day, as the calendar shows one; [narrow] and [compact], as [eventRow] is. */
  internal fun dueRow(context: Context, todo: HomeData.Todo, today: String, narrow: Boolean = false, compact: Boolean = false): RemoteViews {
    val row = RemoteViews(context.packageName, eventLayout(narrow, compact))
    val late = HomeData.groupOf(todo.due, today) == HomeData.Group.OVERDUE
    // Where the time would be: what it is, in the red where it is late (its day is the To-dos widget's to say).
    row.setTextViewText(R.id.ghost_w_event_time, if (late) "Overdue" else "To-do")
    if (late) row.setTextColor(R.id.ghost_w_event_time, ink(context, R.color.ghost_w_light_red_11, R.color.ghost_w_dark_red_11))
    row.setImageViewResource(R.id.ghost_w_event_mark, if (late) R.drawable.ghost_w_pip_late else R.drawable.ghost_w_pip)
    row.setTextViewText(R.id.ghost_w_event_title, todo.words)
    row.setOnClickPendingIntent(R.id.ghost_w_event_row, Doors.press(context, Doors.noteAt(todo.note, todo.line, todo.match), "due:${todo.note}:${todo.line}".hashCode()))
    if (compact) return row
    row.setViewVisibility(R.id.ghost_w_event_until, View.GONE)
    row.setTextViewText(R.id.ghost_w_event_sub, if (todo.line == 0) "Ticket" else todo.title)
    if (narrow) row.setViewVisibility(R.id.ghost_w_event_sub, View.GONE)
    return row
  }

  // ---- Recent notes ----------------------------------------------------------------------------------------------------

  private fun notes(context: Context, wide: Int, tall: Int): RemoteViews {
    val views = frame(context, R.drawable.ghost_w_ic_note, if (wide < HomeData.NARROW_DP) "Recent" else "Recent notes", "", R.drawable.ghost_w_ic_pen, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    return noteList(context, views, HomeData.notes(HomeScreen.kept(context, "notes")), wide, tall, "No notes yet", "The notes you write in show here.", Doors.press(context, Doors.NEW))
  }

  /**
   * Notes as the home page's rows, as many as the size holds (Recent notes, Pinned notes, A folder): a cell high, one;
   * two cells across, a column of their names (and how each starts, where the column is tall); large and wide, two
   * columns; a line for how many did not fit. [none] and [noneWords] where there are none, a tap [noneLink].
   */
  internal fun noteList(context: Context, views: RemoteViews, rows: List<HomeData.Row>, wide: Int, tall: Int, none: String, noneWords: String, noneLink: PendingIntent?): RemoteViews {
    val now = System.currentTimeMillis()
    val fit = HomeData.fitOf(wide, tall)
    if (fit == Fit.TINY) {
      // A cell (not offered by the lists' providers, whose least is two by one; a launcher may make one anyway): the
      // first note, its mark and name, a tap from it; none, the pen.
      val first = rows.firstOrNull() ?: return tile(context, views, icon = R.drawable.ghost_w_ic_pen, label = "New note", link = noneLink)
      return tile(context, views, icon = markOf(first.kind), label = first.title, link = Doors.press(context, Doors.noteAt(first.id), "note:${first.id}".hashCode()))
    }
    val narrow = wide < HomeData.NARROW_DP
    if (fit == Fit.NARROW) narrowed(context, views)
    // A narrow row is as tall as a wide one (layout/ghost_w_note_row.xml, 52dp): only its when is put away.
    val each = HomeData.Part(scaled(context, NOTE_DP), scaled(context, COMPACT_DP))
    val columns = if (fit == Fit.LARGE && wide >= TWO_COLUMNS_DP) 2 else 1
    val room = roomFor(context, views, tall, each.full + if (rows.size > 1) MORE_DP else 0)
    // Whole rows, then names alone (compactRow) for the room under them, then the line for the rest where it has its
    // room (HomeData.fill). A cell high, no line under the one row: the heading that counted is put away too.
    val one = HomeData.fill(room, List(rows.size) { each }, if (room(tall) == room) scaled(context, MORE_DP) else 0)
    val shown = rows.take(one.shown * columns)
    val first = if (columns == 2) (shown.size + 1) / 2 else shown.size
    // Two columns with room for them all, each as a column of the first's rows would be.
    val filled = if (columns == 2 && shown.size == rows.size) HomeData.fill(room, List(first) { each }, 0) else one
    fun rowOf(index: Int, note: HomeData.Row) = (if (filled.compact(index)) compactRow(context, note) else noteRow(context, note, now, narrow = narrow)) to false
    placed(context, views, R.id.ghost_w_col_a, shown.take(first).mapIndexed(::rowOf), filled.spread)
    placed(context, views, R.id.ghost_w_col_b, shown.drop(first).mapIndexed(::rowOf), filled.spread)
    views.setViewVisibility(R.id.ghost_w_col_b, if (columns == 2 && shown.size > first) View.VISIBLE else View.GONE)
    if (fit == Fit.SLIM) views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.CENTER_VERTICAL)
    more(context, views, if (one.more) rows.size - shown.size else 0)
    empty(context, views, if (rows.isEmpty()) none else null, if (fit == Fit.SLIM) "" else noneWords, noneLink)
    return views
  }

  internal fun markOf(kind: String): Int = when (kind) {
    "tape" -> R.drawable.ghost_w_ic_tape
    "book" -> R.drawable.ghost_w_ic_book
    "canvas" -> R.drawable.ghost_w_ic_canvas
    else -> R.drawable.ghost_w_ic_note
  }

  /** A note's row; [narrow] (two cells across), when it was touched put away so its name has the width. */
  internal fun noteRow(context: Context, note: HomeData.Row, now: Long, narrow: Boolean = false): RemoteViews {
    val row = RemoteViews(context.packageName, R.layout.ghost_w_note_row)
    row.setImageViewResource(R.id.ghost_w_note_mark, markOf(note.kind))
    row.setTextViewText(R.id.ghost_w_note_title, note.title)
    val line = if (narrow) HomeData.lineOf(note).ifEmpty { ago(context, note.updated, now) } else HomeData.lineOf(note)
    row.setTextViewText(R.id.ghost_w_note_line, line)
    row.setViewVisibility(R.id.ghost_w_note_line, if (line.isEmpty()) View.GONE else View.VISIBLE)
    row.setTextViewText(R.id.ghost_w_note_when, ago(context, note.updated, now))
    row.setViewVisibility(R.id.ghost_w_note_when, if (narrow) View.GONE else View.VISIBLE)
    row.setOnClickPendingIntent(R.id.ghost_w_note_row, Doors.press(context, Doors.noteAt(note.id), "note:${note.id}".hashCode()))
    return row
  }

  /** A note's name and mark alone, 36dp: under Search's field, and a column's recordings. */
  internal fun compactRow(context: Context, note: HomeData.Row): RemoteViews {
    val row = RemoteViews(context.packageName, R.layout.ghost_w_compact_row)
    row.setImageViewResource(R.id.ghost_w_note_mark, markOf(note.kind))
    row.setTextViewText(R.id.ghost_w_note_title, note.title)
    row.setOnClickPendingIntent(R.id.ghost_w_note_row, Doors.press(context, Doors.noteAt(note.id), "note:${note.id}".hashCode()))
    return row
  }
}
