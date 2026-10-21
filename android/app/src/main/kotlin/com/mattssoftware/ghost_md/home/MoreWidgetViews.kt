package com.mattssoftware.ghost_md.home

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.Gravity
import android.view.View
import android.widget.RemoteViews
import com.mattssoftware.ghost_md.R
import com.mattssoftware.ghost_md.home.HomeData.Fit
import com.mattssoftware.ghost_md.home.WidgetViews.COMPACT_DP
import com.mattssoftware.ghost_md.home.WidgetViews.EVENT_DP
import com.mattssoftware.ghost_md.home.WidgetViews.EYEBROW_DP
import com.mattssoftware.ghost_md.home.WidgetViews.NOTE_DP
import com.mattssoftware.ghost_md.home.WidgetViews.dayIn
import com.mattssoftware.ghost_md.home.WidgetViews.empty
import com.mattssoftware.ghost_md.home.WidgetViews.eyebrow
import com.mattssoftware.ghost_md.home.WidgetViews.frame
import com.mattssoftware.ghost_md.home.WidgetViews.headless
import com.mattssoftware.ghost_md.home.WidgetViews.home
import com.mattssoftware.ghost_md.home.WidgetViews.ink
import com.mattssoftware.ghost_md.home.WidgetViews.more
import com.mattssoftware.ghost_md.home.WidgetViews.narrowed
import com.mattssoftware.ghost_md.home.WidgetViews.room
import com.mattssoftware.ghost_md.home.WidgetViews.scaled
import com.mattssoftware.ghost_md.home.WidgetViews.tile
import com.mattssoftware.ghost_md.home.WidgetViews.timeOf

/**
 * The eight widgets after the four (docs/WIDGETS_ANDROID.md, "Twelve"; Matt, 2026-10-21: "Please add more widgets and
 * sizes shoot for 12 widgets"), drawn in the four's frame and look (WidgetViews.kt), each for every size it may be
 * (HomeData.Fit):
 *
 * - **Quick capture**: the dock's round buttons for what the app makes: a note, a voice note (the filled Speak), a
 *   checklist ("A checklist", the blank page's card), a scan, and, with room, today's note and Search. A cell: the
 *   pen. A cell high: a row of rings. A column: a stack of them, each with its word. Four by two: a row with words.
 *   Large: the + sheet's rows, each with what it makes.
 * - **Pinned notes**: the pinned notes in Recent notes' rows.
 * - **Today**: today's note (Settings › Daily notes; `ghostmd://today` opens it, or makes it) as its lines, its to-dos
 *   ticked in place; a cell: the day's number, and a dot where it has been written in.
 * - **Search**: the home page's field, which opens the palette, over the notes written in last; a cell: the magnifier.
 * - **A note** and **A folder**: one of each, chosen as the widget is placed (WidgetPick.kt): a note's lines, its
 *   to-dos ticked in place; a folder's notes, its + a new note filed there. Deleted, they say so, and a tap chooses
 *   another.
 * - **Ask AI**: Talk to Claude, the dock's orange-rimmed microphone, and the chat, the orange disc, where the app shows
 *   them (Claude on, and a key on this device); else where to turn it on.
 * - **Next up**: the one next thing (HomeData.nextUp): today's next event, else the to-do most overdue or due today,
 *   and when; then the rest of today with room. A cell: its time, or how many are due.
 */
object MoreWidgetViews {
  private const val LINE_DP = 26
  private const val CHECK_DP = 32

  fun build(context: Context, kind: WidgetKind, id: Int, wide: Int, tall: Int): RemoteViews = when (kind) {
    WidgetKind.QUICK -> quick(context, wide, tall)
    WidgetKind.PINNED -> pinned(context, wide, tall)
    WidgetKind.TODAY -> today(context, wide, tall)
    WidgetKind.SEARCH -> search(context, wide, tall)
    WidgetKind.NOTE -> note(context, id, wide, tall)
    WidgetKind.FOLDER -> folder(context, id, wide, tall)
    WidgetKind.ASK -> ask(context, wide, tall)
    else -> next(context, wide, tall)
  }

  // ---- Quick capture -------------------------------------------------------------------------------------------------

  /** One thing Quick capture makes: its mark, its short word and its row's, what it makes, its link. */
  private class Capture(val icon: Int, val word: String, val name: String, val hint: String, val link: String, val filled: Boolean = false)

  private val captures = listOf(
    Capture(R.drawable.ghost_w_ic_pen, "Note", "Note", "A page of markdown, typed or said.", Doors.NEW),
    Capture(R.drawable.ghost_w_ic_mic, "Voice", "Voice note", "A new note, in your own words.", Doors.VOICE, filled = true),
    Capture(R.drawable.ghost_w_ic_checklist, "Checklist", "Checklist", "A name to type, then a to-do.", Doors.CHECKLIST),
    Capture(R.drawable.ghost_w_ic_scan, "Scan", "Scan document", "Pages from the camera, kept in a new note.", Doors.SCAN),
    Capture(R.drawable.ghost_w_ic_calendar, "Today", "Today's note", "The note for today, opened, or made the first time.", Doors.TODAY),
    Capture(R.drawable.ghost_w_ic_search, "Search", "Search", "Find a note by its name or its words.", Doors.SEARCH),
  )

  private fun ring(context: Context, views: RemoteViews, capture: Capture) {
    views.setImageViewResource(R.id.ghost_w_cap_icon, capture.icon)
    if (capture.filled) {
      views.setInt(R.id.ghost_w_cap_ring, "setBackgroundResource", R.drawable.ghost_w_ring_ink)
      views.setInt(R.id.ghost_w_cap_icon, "setColorFilter", ink(context, R.color.ghost_w_light_on_ink, R.color.ghost_w_dark_on_ink))
    }
    views.setContentDescription(R.id.ghost_w_cap, capture.name)
    views.setOnClickPendingIntent(R.id.ghost_w_cap, Doors.press(context, capture.link))
  }

  /** A row of [shown] rings sharing the width, with their words where [words]. */
  private fun ringRow(context: Context, shown: List<Capture>, words: Boolean): RemoteViews {
    val row = RemoteViews(context.packageName, R.layout.ghost_w_hrow)
    for (capture in shown) {
      val cell = RemoteViews(context.packageName, R.layout.ghost_w_capture_cell)
      ring(context, cell, capture)
      cell.setTextViewText(R.id.ghost_w_cap_label, capture.word)
      cell.setViewVisibility(R.id.ghost_w_cap_label, if (words) View.VISIBLE else View.GONE)
      row.addView(R.id.ghost_w_hrow, cell)
    }
    return row
  }

  private fun stackRow(context: Context, capture: Capture, hint: Boolean): RemoteViews {
    val row = RemoteViews(context.packageName, R.layout.ghost_w_capture_row)
    ring(context, row, capture)
    // Without its line (a column), the short word where the whole name would not fit beside the ring.
    row.setTextViewText(R.id.ghost_w_cap_label, if (hint || capture.name.length <= 10) capture.name else capture.word)
    row.setTextViewText(R.id.ghost_w_cap_hint, capture.hint)
    row.setViewVisibility(R.id.ghost_w_cap_hint, if (hint) View.VISIBLE else View.GONE)
    return row
  }

  private fun quick(context: Context, wide: Int, tall: Int): RemoteViews {
    val fit = HomeData.fitOf(wide, tall)
    val views = frame(context, R.drawable.ghost_w_ic_pen, "Quick capture", "", R.drawable.ghost_w_ic_plus, "", Doors.NEW)
    // Its buttons are the widget: no round button of its own at the heading's end.
    views.setViewVisibility(R.id.ghost_w_action, View.GONE)
    when (fit) {
      Fit.TINY -> return tile(context, views, icon = R.drawable.ghost_w_ic_pen, label = "New note", link = Doors.press(context, Doors.NEW), said = context.getString(R.string.ghost_shortcut_new_long))
      Fit.SLIM -> {
        // A cell high: as many rings as the width has room for, their words where the height has.
        headless(context, views, sides = 8, ends = 4)
        views.addView(R.id.ghost_w_col_a, ringRow(context, captures.take((wide / 64).coerceIn(2, captures.size)), words = tall >= 100))
      }
      Fit.NARROW -> {
        // A column: the rings stacked, each with its word, sharing the height; the heading where it is tall.
        narrowed(context, views)
        val heading = tall >= 300
        if (!heading) headless(context, views, sides = 10, ends = 6)
        val room = if (heading) room(tall) else tall - 12
        for (capture in captures.take((room / scaled(context, 46)).coerceIn(1, captures.size))) views.addView(R.id.ghost_w_col_a, stackRow(context, capture, hint = false))
      }
      Fit.MEDIUM -> views.addView(R.id.ghost_w_col_a, ringRow(context, captures.take(if (wide >= WidgetViews.TWO_COLUMNS_DP) 6 else 4), words = true))
      Fit.LARGE -> {
        if (wide >= WidgetViews.TWO_COLUMNS_DP) {
          views.addView(R.id.ghost_w_col_a, ringRow(context, captures.take(3), words = true))
          views.addView(R.id.ghost_w_col_a, ringRow(context, captures.drop(3), words = true))
        } else {
          // The + sheet's rows: each with what it makes, as many as the height holds.
          val shown = (room(tall) / scaled(context, 50)).coerceIn(1, captures.size)
          for (capture in captures.take(shown)) views.addView(R.id.ghost_w_col_a, stackRow(context, capture, hint = true))
        }
      }
    }
    more(context, views, 0)
    empty(context, views, null)
    return views
  }

  // ---- Pinned notes --------------------------------------------------------------------------------------------------

  private fun pinned(context: Context, wide: Int, tall: Int): RemoteViews {
    val rows = HomeData.notes(HomeScreen.kept(context, "pins"))
    val views = frame(context, R.drawable.ghost_w_ic_pin, "Pinned", if (rows.isEmpty()) "" else "${rows.size}", R.drawable.ghost_w_ic_pen, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    if (HomeData.fitOf(wide, tall) == Fit.TINY) {
      // Not offered a cell (its provider's least is two by one); where a launcher makes it one anyway, the first pin.
      val first = rows.firstOrNull()
      return tile(context, views, icon = R.drawable.ghost_w_ic_pin, label = first?.title ?: "Pinned", link = first?.let { Doors.press(context, Doors.noteAt(it.id), "note:${it.id}".hashCode()) } ?: home(context))
    }
    return WidgetViews.noteList(context, views, rows, wide, tall, "Nothing pinned", "Notes you pin to the top show here.", home(context))
  }

  // ---- a note's lines (A note, Today) ------------------------------------------------------------------------------

  /** About how many characters of the md words a row of [wide] dp holds: the face's average letter is near 0.47em. */
  private fun perRow(context: Context, wide: Int): Int = ((wide / (16.2f * 0.5f * context.resources.configuration.fontScale.coerceAtLeast(1f)))).toInt().coerceAtLeast(8)

  private fun heightOf(context: Context, line: HomeData.Line, wide: Int): Int {
    val rows = HomeData.rowsFor(line.words.length + if (line.kind == "bullet") 2 else 0, perRow(context, wide - 30 - line.depth * 14), 2)
    return when (line.kind) {
      "heading" -> scaled(context, 26)
      "todo", "done" -> maxOf(CHECK_DP, scaled(context, rows * 18 + 10))
      else -> maxOf(LINE_DP, scaled(context, rows * 18 + 6))
    }
  }

  private fun lineRow(context: Context, page: HomeData.Page, line: HomeData.Line): RemoteViews {
    val note = page.row.id
    val code = "line:$note:${line.line}".hashCode()
    val open = Doors.press(context, Doors.noteAt(note, line.line, line.match ?: ""), code)
    val indent = WidgetViews.dp(context, 2 + line.depth * 14)
    return when (line.kind) {
      "todo", "done" -> RemoteViews(context.packageName, R.layout.ghost_w_check_row).apply {
        setTextViewText(R.id.ghost_w_line, line.words)
        setOnClickPendingIntent(R.id.ghost_w_line, open)
        setViewPadding(R.id.ghost_w_line_row, indent - WidgetViews.dp(context, 2), 0, 0, 0)
        if (line.done) setTextColor(R.id.ghost_w_line, ink(context, R.color.ghost_w_light_ink_3, R.color.ghost_w_dark_ink_3))
        val tick = if (line.todo) WidgetViews.tickOf(context, note, line.line, line.match ?: line.words, code) else null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
          setCompoundButtonChecked(R.id.ghost_w_check, line.done)
          setBoolean(R.id.ghost_w_check, "setEnabled", tick != null)
          if (tick != null) setOnCheckedChangeResponse(R.id.ghost_w_check, RemoteViews.RemoteResponse.fromPendingIntent(tick))
        } else {
          setImageViewResource(R.id.ghost_w_tick_ring, if (line.done) R.drawable.ghost_w_tick_on else R.drawable.ghost_w_tick_off)
          if (tick != null) setOnClickPendingIntent(R.id.ghost_w_tick, tick)
        }
      }
      "heading" -> RemoteViews(context.packageName, R.layout.ghost_w_line_heading).apply {
        setTextViewText(R.id.ghost_w_line, line.words)
        setOnClickPendingIntent(R.id.ghost_w_line, open)
      }
      "quote" -> RemoteViews(context.packageName, R.layout.ghost_w_line_quote).apply {
        setTextViewText(R.id.ghost_w_line, line.words)
        setOnClickPendingIntent(R.id.ghost_w_line_row, open)
      }
      else -> RemoteViews(context.packageName, R.layout.ghost_w_line_text).apply {
        setTextViewText(R.id.ghost_w_line, if (line.kind == "bullet") "•  ${line.words}" else line.words)
        setViewPadding(R.id.ghost_w_line, indent, WidgetViews.dp(context, 2), WidgetViews.dp(context, 2), WidgetViews.dp(context, 2))
        setOnClickPendingIntent(R.id.ghost_w_line, open)
      }
    }
  }

  /** [page]'s lines into the first column, as many as [room] holds at [wide]; how many were shown. */
  private fun linesInto(context: Context, views: RemoteViews, page: HomeData.Page, room: Int, wide: Int): Int {
    var used = 0
    var shown = 0
    for ((index, line) in page.lines.withIndex()) {
      val height = heightOf(context, line, wide)
      if (used + height > room) break
      // A heading is never the last thing shown: the line under it fits too, or neither is drawn.
      val under = page.lines.getOrNull(index + 1)
      if (line.kind == "heading" && under != null && used + height + heightOf(context, under, wide) > room) break
      views.addView(R.id.ghost_w_col_a, lineRow(context, page, line))
      used += height
      shown += 1
    }
    return shown
  }

  // ---- Today ---------------------------------------------------------------------------------------------------------

  private fun today(context: Context, wide: Int, tall: Int): RemoteViews {
    val fit = HomeData.fitOf(wide, tall)
    val now = System.currentTimeMillis()
    val day = HomeScreen.today()
    val read = HomeData.daily(HomeScreen.kept(context, "daily"))
    // The note handed over for another day (the app last ran yesterday) is not today's: nothing is written today yet.
    val page = read?.page?.takeIf { read.day == day }
    val open = Doors.press(context, Doors.TODAY)
    val narrow = wide < HomeData.NARROW_DP
    val views = frame(context, R.drawable.ghost_w_ic_calendar, if (narrow) dayIn(context, now, "MMMd") else "Today", if (narrow) "" else dayIn(context, now, "EEEMMMd"), R.drawable.ghost_w_ic_pen, context.getString(R.string.ghost_shortcut_today_long), Doors.TODAY)
    views.setOnClickPendingIntent(R.id.ghost_w_head, open)
    when (fit) {
      Fit.TINY -> return tile(context, views, big = dayIn(context, now, "d"), label = dayIn(context, now, "EEE"), dot = page != null, link = open, said = context.getString(R.string.ghost_shortcut_today_long))
      Fit.SLIM -> {
        // A cell high: the pen's ring and the day, and how today's note starts.
        val mic = WidgetViews.Mic(R.drawable.ghost_w_ring, R.drawable.ghost_w_ic_pen, ink(context, R.color.ghost_w_light_ink, R.color.ghost_w_dark_ink), dayIn(context, now, if (narrow) "EEEMMMd" else "EEEEMMMMd"), page?.lines?.firstOrNull()?.words ?: page?.row?.line?.takeIf { it.isNotEmpty() } ?: "Nothing written yet", open, open, context.getString(R.string.ghost_shortcut_today_long))
        WidgetViews.micInto(context, views, fit, wide, tall, mic)
        more(context, views, 0)
        empty(context, views, null)
        return views
      }
      Fit.NARROW -> narrowed(context, views)
      else -> {}
    }
    if (read != null && page != null) linesInto(context, views, page, room(tall), wide)
    more(context, views, 0)
    empty(
      context,
      views,
      when {
        read == null -> "Open Ghost.md"
        page == null -> "Nothing written today"
        page.lines.isEmpty() -> "Today’s note is open"
        else -> null
      },
      if (read == null) "Today’s note shows here once it has opened." else "Tap to write in today’s note.",
      open,
    )
    return views
  }

  // ---- Search --------------------------------------------------------------------------------------------------------

  private fun search(context: Context, wide: Int, tall: Int): RemoteViews {
    val fit = HomeData.fitOf(wide, tall)
    val now = System.currentTimeMillis()
    val find = Doors.press(context, Doors.SEARCH)
    val views = frame(context, R.drawable.ghost_w_ic_search, "Search", "", R.drawable.ghost_w_ic_pen, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    if (fit == Fit.TINY) return tile(context, views, icon = R.drawable.ghost_w_ic_search, label = "Search", link = find, said = context.getString(R.string.ghost_shortcut_search_long))
    // The field is its heading: the home page's, at the top, with the notes written in last under it.
    headless(context, views, sides = if (fit == Fit.NARROW) 10 else 12, ends = if (fit == Fit.SLIM) 4 else 10)
    val field = RemoteViews(context.packageName, R.layout.ghost_w_search_field)
    field.setOnClickPendingIntent(R.id.ghost_w_field, find)
    if (wide < HomeData.NARROW_DP) field.setTextViewText(R.id.ghost_w_field_words, "Search")
    views.addView(R.id.ghost_w_col_a, field)
    if (fit == Fit.SLIM) {
      views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.CENTER_VERTICAL)
    } else {
      val rows = HomeData.notes(HomeScreen.kept(context, "notes"))
      val compact = fit == Fit.NARROW || fit == Fit.MEDIUM
      val each = scaled(context, if (compact) COMPACT_DP else NOTE_DP)
      val left = tall - 20 - 44 - scaled(context, EYEBROW_DP)
      val shown = if (left >= each) HomeData.fitting(left, rows.map { each }, 0) else 0
      if (shown > 0) {
        views.addView(R.id.ghost_w_col_a, eyebrow(context, "Recent", null))
        for (row in rows.take(shown)) views.addView(R.id.ghost_w_col_a, if (compact) WidgetViews.compactRow(context, row) else WidgetViews.noteRow(context, row, now))
      }
    }
    more(context, views, 0)
    empty(context, views, null)
    return views
  }

  // ---- A note --------------------------------------------------------------------------------------------------------

  /** The configuration of the widget [id] (WidgetPick.kt), opened again: to choose another note or folder. */
  fun pick(context: Context, id: Int): PendingIntent = PendingIntent.getActivity(
    context,
    7_400 + id,
    Intent(context, WidgetPick::class.java)
      .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
      .setData(Uri.parse("ghostmd-widget://pick/$id"))
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
  )

  private fun note(context: Context, id: Int, wide: Int, tall: Int): RemoteViews {
    val fit = HomeData.fitOf(wide, tall)
    val now = System.currentTimeMillis()
    val chosen = HomeScreen.chosenFor(context, id)
    val pages = HomeData.pages(HomeScreen.kept(context, "pages"))
    val page = chosen?.let { pages?.pages?.get(it) }
    // Not handed over yet (chosen while the app was closed): its row from the notes it was chosen among.
    val row = page?.row ?: chosen?.let { want -> HomeData.notes(HomeScreen.kept(context, "picks")).firstOrNull { it.id == want } }
    val gone = chosen != null && pages?.gone?.contains(chosen) == true
    val again = pick(context, id)
    val opened = row?.let { Doors.press(context, Doors.noteAt(it.id), "note:${it.id}".hashCode()) }
    val views = frame(context, row?.let { WidgetViews.markOf(it.kind) } ?: R.drawable.ghost_w_ic_note, row?.title ?: "A note", "", R.drawable.ghost_w_ic_pen, "Write in it", row?.let { Doors.noteAt(it.id) } ?: Doors.NEW)
    opened?.let { views.setOnClickPendingIntent(R.id.ghost_w_head, it) }
    if (gone || row == null) {
      // Nothing to show: say why, and a tap chooses one.
      views.setViewVisibility(R.id.ghost_w_action, View.GONE)
      if (fit == Fit.TINY) return tile(context, views, icon = R.drawable.ghost_w_ic_note, label = if (gone) "Deleted" else "Choose", link = again)
      if (fit == Fit.SLIM) headless(context, views)
      more(context, views, 0)
      empty(context, views, if (gone) "This note was deleted" else "Choose a note", if (fit == Fit.SLIM) "" else if (gone) "Tap to choose another." else "Tap to choose one.", again)
      return views
    }
    when (fit) {
      Fit.TINY -> return tile(context, views, icon = WidgetViews.markOf(row.kind), label = row.title, link = opened)
      Fit.SLIM -> {
        // A cell high: the note as a home page's row, its name and how it starts.
        headless(context, views)
        views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.CENTER_VERTICAL)
        views.addView(R.id.ghost_w_col_a, WidgetViews.noteRow(context, row, now, narrow = wide < HomeData.NARROW_DP))
        more(context, views, 0)
        empty(context, views, null)
        return views
      }
      Fit.NARROW -> narrowed(context, views)
      else -> {}
    }
    if (page != null) linesInto(context, views, page, room(tall), if (fit == Fit.NARROW) wide - 20 else wide - 26) else 0
    more(context, views, 0)
    empty(
      context,
      views,
      when {
        page == null -> "Open Ghost.md"
        page.lines.isEmpty() -> "Nothing under its name yet"
        else -> null
      },
      if (page == null) "Its lines show once Ghost.md has opened." else "Tap to write in it.",
      opened,
    )
    return views
  }

  // ---- A folder ------------------------------------------------------------------------------------------------------

  private fun folder(context: Context, id: Int, wide: Int, tall: Int): RemoteViews {
    val fit = HomeData.fitOf(wide, tall)
    val chosen = HomeScreen.chosenFor(context, id)
    val folders = HomeData.folders(HomeScreen.kept(context, "folders"))
    val folder = chosen?.let { want -> folders?.firstOrNull { it.id == want } }
    val gone = chosen != null && folders != null && folder == null
    val again = pick(context, id)
    if (folder == null) {
      val views = frame(context, R.drawable.ghost_w_ic_folder, "A folder", "", R.drawable.ghost_w_ic_plus, "", Doors.NEW)
      views.setViewVisibility(R.id.ghost_w_action, View.GONE)
      if (fit == Fit.TINY) return tile(context, views, icon = R.drawable.ghost_w_ic_folder, label = if (gone) "Gone" else "Choose", link = again)
      if (fit == Fit.SLIM) headless(context, views)
      more(context, views, 0)
      empty(
        context,
        views,
        when {
          gone -> "This folder is gone"
          chosen != null -> "Open Ghost.md"
          else -> "Choose a folder"
        },
        when {
          fit == Fit.SLIM -> ""
          gone -> "Tap to choose another."
          chosen != null -> "Its notes show once Ghost.md has opened."
          else -> "Tap to choose one."
        },
        if (chosen != null && !gone) home(context) else again,
      )
      return views
    }
    val make = Doors.newIn(folder.id)
    val said = "New note in ${folder.name}"
    // Two cells across, its own name; wider, its parents' before it ("Acme › Design"), as the app lists folders.
    val views = frame(context, R.drawable.ghost_w_ic_folder, if (fit == Fit.NARROW) folder.name else folder.path, if (folder.count > 0) "${folder.count}" else "", R.drawable.ghost_w_ic_plus, said, make)
    if (fit == Fit.TINY) return tile(context, views, icon = R.drawable.ghost_w_ic_plus, label = folder.name, link = Doors.press(context, make), said = said)
    return WidgetViews.noteList(context, views, folder.notes, wide, tall, "Nothing in ${folder.name} yet", "Tap to write the first note here.", Doors.press(context, make))
  }

  // ---- Ask AI --------------------------------------------------------------------------------------------------------

  private fun ask(context: Context, wide: Int, tall: Int): RemoteViews {
    val fit = HomeData.fitOf(wide, tall)
    val read = HomeData.assistant(HomeScreen.kept(context, "assistant"))
    val orange = context.getColor(R.color.ghost_w_claude)
    val talk = Doors.press(context, Doors.TALK)
    val chat = Doors.press(context, Doors.CHAT)
    val views = frame(context, R.drawable.ghost_w_ic_claude, "Claude", "", R.drawable.ghost_w_ic_claude, "Chat with Claude", Doors.CHAT)
    views.setOnClickPendingIntent(R.id.ghost_w_head, chat)
    if (read?.shown != true) {
      // Claude is not shown in the app: where to turn it on (the chat's link opens Claude's settings then).
      views.setViewVisibility(R.id.ghost_w_action, View.GONE)
      if (fit == Fit.TINY) return tile(context, views, icon = R.drawable.ghost_w_ic_claude, tint = ink(context, R.color.ghost_w_light_ink_3, R.color.ghost_w_dark_ink_3), label = "Claude off", link = chat)
      if (fit == Fit.SLIM) headless(context, views)
      more(context, views, 0)
      empty(
        context,
        views,
        when {
          read == null -> "Open Ghost.md"
          !read.on -> "Turn on Claude in Ghost.md"
          else -> "Add your Claude API key"
        },
        if (fit == Fit.SLIM) "" else if (read == null) "Claude shows here once it has opened." else "Settings › Plugins › Claude",
        if (read == null) home(context) else chat,
      )
      return views
    }
    // Claude's own: the mark in its orange, the chat its orange disc at the heading's end, as the dock draws them.
    views.setInt(R.id.ghost_w_mark, "setColorFilter", orange)
    views.setInt(R.id.ghost_w_action, "setBackgroundResource", R.drawable.ghost_w_disc_claude)
    views.setInt(R.id.ghost_w_action_icon, "setColorFilter", context.getColor(R.color.ghost_w_claude_ivory))
    views.setOnClickPendingIntent(R.id.ghost_w_action, chat)
    if (fit == Fit.TINY) return tile(context, views, icon = R.drawable.ghost_w_ic_mic, ring = R.drawable.ghost_w_ring_claude, tint = orange, label = "Talk", link = talk, said = "Talk to Claude")
    val mic = WidgetViews.Mic(R.drawable.ghost_w_ring_claude, R.drawable.ghost_w_ic_mic, orange, "Talk to Claude", if (fit == Fit.NARROW || fit == Fit.LARGE) "" else "Ask about your notes, aloud", talk, talk, "Talk to Claude")
    WidgetViews.micInto(context, views, fit, wide, tall, mic, reserve = if (fit == Fit.LARGE) scaled(context, 60) else 0, square = fit == Fit.NARROW || fit == Fit.LARGE)
    if (fit == Fit.LARGE) {
      // Large: the microphone as big as the room, and under it the chat as a home page's row, Claude's mark in its
      // orange.
      val row = RemoteViews(context.packageName, R.layout.ghost_w_note_row)
      row.setImageViewResource(R.id.ghost_w_note_mark, R.drawable.ghost_w_ic_claude)
      row.setInt(R.id.ghost_w_note_mark, "setColorFilter", orange)
      row.setTextViewText(R.id.ghost_w_note_title, "Chat with Claude")
      row.setTextViewText(R.id.ghost_w_note_line, "Type a question about your notes.")
      row.setViewVisibility(R.id.ghost_w_note_when, View.GONE)
      row.setContentDescription(R.id.ghost_w_note_row, "Chat with Claude")
      row.setOnClickPendingIntent(R.id.ghost_w_note_row, chat)
      views.addView(R.id.ghost_w_col_a, row)
    }
    more(context, views, 0)
    empty(context, views, null)
    return views
  }

  // ---- Next up -------------------------------------------------------------------------------------------------------

  private fun pressOf(context: Context, item: Any): PendingIntent? = when (item) {
    is HomeData.Todo -> Doors.press(context, Doors.noteAt(item.note, item.line, item.match), "next:${item.note}:${item.line}".hashCode())
    else -> home(context)
  }

  private fun hero(context: Context, item: Any, today: String, now: Long, slim: Boolean): RemoteViews {
    val hero = RemoteViews(context.packageName, R.layout.ghost_w_next_hero)
    val whenWords = HomeData.whenNext(item, today, now)
    hero.setTextViewText(R.id.ghost_w_next_when, whenWords)
    when {
      whenWords.startsWith("Overdue") -> hero.setTextColor(R.id.ghost_w_next_when, ink(context, R.color.ghost_w_light_red_11, R.color.ghost_w_dark_red_11))
      whenWords == "Due today" -> hero.setTextColor(R.id.ghost_w_next_when, ink(context, R.color.ghost_w_light_amber_11, R.color.ghost_w_dark_amber_11))
      whenWords == "Now" -> hero.setTextColor(R.id.ghost_w_next_when, ink(context, R.color.ghost_w_light_ink, R.color.ghost_w_dark_ink))
    }
    val (title, sub) = when (item) {
      is HomeData.Event -> item.title to listOfNotNull(if (item.allDay) null else "${timeOf(context, item.start)} – ${timeOf(context, item.end)}", item.calendar.takeIf { it.isNotEmpty() }, item.location).joinToString(" · ")
      is HomeData.Todo -> item.words to (if (item.line == 0) "Ticket" else item.title)
      else -> "" to ""
    }
    hero.setTextViewText(R.id.ghost_w_next_title, title)
    hero.setTextViewText(R.id.ghost_w_next_sub, sub)
    if (slim) {
      hero.setInt(R.id.ghost_w_next_title, "setMaxLines", 1)
      hero.setViewVisibility(R.id.ghost_w_next_sub, View.GONE)
    }
    pressOf(context, item)?.let { hero.setOnClickPendingIntent(R.id.ghost_w_next, it) }
    return hero
  }

  /** One of the rest in a column: its mark (the clock for an event, the to-dos' for a to-do) and its time and words. */
  private fun thenRow(context: Context, item: Any): RemoteViews {
    val row = RemoteViews(context.packageName, R.layout.ghost_w_compact_row)
    row.setImageViewResource(R.id.ghost_w_note_mark, if (item is HomeData.Event) R.drawable.ghost_w_ic_clock else R.drawable.ghost_w_ic_todos)
    row.setTextViewText(R.id.ghost_w_note_title, if (item is HomeData.Event) item.title else (item as HomeData.Todo).words)
    pressOf(context, item)?.let { row.setOnClickPendingIntent(R.id.ghost_w_note_row, it) }
    return row
  }

  private fun next(context: Context, wide: Int, tall: Int): RemoteViews {
    val fit = HomeData.fitOf(wide, tall)
    val today = HomeScreen.today()
    val now = System.currentTimeMillis()
    val read = HomeData.calendar(HomeScreen.kept(context, "calendar"))
    val todos = HomeData.todos(HomeScreen.kept(context, "todos"))
    val items = HomeData.nextUp(if (read?.on == true) read.events else emptyList(), todos, today, now)
    val views = frame(context, R.drawable.ghost_w_ic_clock, "Next up", "", R.drawable.ghost_w_ic_plus, context.getString(R.string.ghost_shortcut_new_long), Doors.NEW)
    val first = items.firstOrNull()
    if (fit == Fit.TINY) {
      if (first is HomeData.Event && !first.allDay) {
        return tile(context, views, big = if (first.start <= now) "Now" else timeOf(context, first.start), label = first.title, link = home(context), said = "${HomeData.whenNext(first, today, now)}: ${first.title}")
      }
      // No event to come: how many to-dos are due by today, red where any is overdue.
      val due = items.filterIsInstance<HomeData.Todo>()
      val late = due.count { HomeData.groupOf(it.due, today) == HomeData.Group.OVERDUE }
      if (due.isEmpty()) return tile(context, views, icon = R.drawable.ghost_w_ic_clock, label = "All clear", link = home(context))
      return tile(
        context,
        views,
        big = "${due.size}",
        bigColour = if (late > 0) ink(context, R.color.ghost_w_light_red_11, R.color.ghost_w_dark_red_11) else null,
        label = if (late > 0) "Overdue" else "Due today",
        link = pressOf(context, due.first()),
        said = "${due.size} to-dos due",
      )
    }
    if (first == null) {
      if (fit == Fit.SLIM) headless(context, views)
      more(context, views, 0)
      empty(context, views, "Nothing next", if (fit == Fit.SLIM) "" else "Today’s events and the to-dos due show here.")
      return views
    }
    val heroDp = scaled(context, 92)
    when (fit) {
      Fit.SLIM -> {
        headless(context, views, sides = 14, ends = 4)
        views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.CENTER_VERTICAL)
        views.addView(R.id.ghost_w_col_a, hero(context, first, today, now, slim = true))
      }
      else -> {
        if (fit == Fit.NARROW) narrowed(context, views)
        views.addView(R.id.ghost_w_col_a, hero(context, first, today, now, slim = false))
        val rest = items.drop(1)
        val wideOne = fit != Fit.NARROW && wide >= WidgetViews.TWO_COLUMNS_DP
        if (wideOne) {
          // Wide: the rest beside it, in a column of their own.
          val shown = HomeData.fitting(room(tall), rest.map { scaled(context, EVENT_DP) }, 0).takeIf { rest.isNotEmpty() } ?: 0
          for (item in rest.take(shown)) views.addView(R.id.ghost_w_col_b, if (item is HomeData.Event) WidgetViews.eventRow(context, item) else WidgetViews.dueRow(context, item as HomeData.Todo, today))
          views.setViewVisibility(R.id.ghost_w_col_b, if (shown > 0) View.VISIBLE else View.GONE)
        } else {
          val each = scaled(context, if (fit == Fit.NARROW) COMPACT_DP else EVENT_DP)
          val left = room(tall) - heroDp - scaled(context, EYEBROW_DP)
          val shown = if (rest.isNotEmpty() && left >= each + scaled(context, 4)) HomeData.fitting(left, rest.map { each }, 0) else 0
          if (shown > 0) {
            views.addView(R.id.ghost_w_col_a, eyebrow(context, "Then", null))
            for (item in rest.take(shown)) {
              views.addView(
                R.id.ghost_w_col_a,
                when {
                  fit == Fit.NARROW -> thenRow(context, item)
                  item is HomeData.Event -> WidgetViews.eventRow(context, item)
                  else -> WidgetViews.dueRow(context, item as HomeData.Todo, today)
                },
              )
            }
          } else {
            // Nothing after it: the one thing in the middle of the room.
            views.setInt(R.id.ghost_w_col_a, "setGravity", Gravity.CENTER_VERTICAL)
          }
        }
      }
    }
    more(context, views, 0)
    empty(context, views, null)
    return views
  }
}
