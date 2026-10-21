package com.mattssoftware.ghost_md.home

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone

/**
 * What the twelve widgets draw, read from what the app handed over (lib/home_screen/home_data.dart;
 * docs/WIDGETS_ANDROID.md) and put in the app's own words: the To-dos view's groups, a due day as its rows say it
 * ("Tomorrow", "3 days ago"), a note's "20 min ago" as the home page's (lib/notes/when.dart), a tape's "0:40". Pure
 * (no Android), so the words and the groups are held by HomeDataTest; the phone's own names for a weekday and a date
 * are handed in.
 *
 * The shapes are the shared widget snapshot's (the iPhone's lib/home_screen/widget_snapshot.dart), so either can be
 * read: a to-do's `words` (what it says) and `match` (what its line is found by), a note's `updated`, the events'
 * `calendar` switch and each event's days or UTC moments.
 *
 * Every day is `YYYY-MM-DD` on this phone's clock, worked out when a widget is drawn, so the widgets turn their day at
 * midnight and age their "min ago" as they are drawn again, with nothing asked of the app.
 */
object HomeData {
  // ---- To-dos ------------------------------------------------------------------------------------------------------

  /**
   * One open to-do: [words] what the row says, [match] the words its line is found by again to tick it; [line] from 1
   * (0 for a ticket); [due] null for none; [priority] `highest` or `high`, the two worth a word, or null.
   */
  data class Todo(val note: String, val line: Int, val words: String, val match: String, val due: String?, val title: String, val priority: String? = null)

  /** The To-dos view's four groups and their words (lib/simple/todos_groups.dart `todoGroupWords`). */
  enum class Group(val words: String) { OVERDUE("Overdue"), TODAY("Today"), LATER("Later"), SOMEDAY("Someday") }

  private fun items(raw: String?, key: String): List<JSONObject> = try {
    val list = JSONObject(raw ?: return emptyList()).optJSONArray(key) ?: JSONArray()
    (0 until list.length()).mapNotNull { list.optJSONObject(it) }
  } catch (_: Throwable) {
    emptyList()
  }

  private fun JSONObject.text(key: String): String? = if (has(key) && !isNull(key)) optString(key).takeIf { it.isNotEmpty() } else null

  /** The to-dos as handed over (`todosJson`), the dated ones first, soonest due first, then those with no date. */
  fun todos(raw: String?): List<Todo> = items(raw, "todos").mapNotNull(::todoOf)

  private fun todoOf(it: JSONObject): Todo? {
    val note = it.text("note") ?: return null
    val words = it.text("words") ?: "Untitled to-do"
    return Todo(note, it.optInt("line"), words, if (it.has("match")) it.optString("match") else words, it.text("due"), it.text("title") ?: "Untitled", it.text("priority"))
  }

  /** A priority as a row says it after the note's name: "High", "Highest". */
  fun priorityWords(priority: String?): String? = priority?.replaceFirstChar { it.uppercase(Locale.ROOT) }

  fun groupOf(due: String?, today: String): Group {
    val days = due?.let { daysBetween(today, it) } ?: return Group.SOMEDAY
    return when {
      days < 0 -> Group.OVERDUE
      days == 0 -> Group.TODAY
      else -> Group.LATER
    }
  }

  /** The groups in their order, each with its to-dos in the order handed over, empty ones left out. */
  fun grouped(todos: List<Todo>, today: String): List<Pair<Group, List<Todo>>> {
    val by = todos.groupBy { groupOf(it.due, today) }
    return Group.values().mapNotNull { group -> by[group]?.let { group to it } }
  }

  /** [todos] less the one on [line] of [note]: ticked from the widget, gone from it before the app has written it. */
  fun without(raw: String?, note: String, line: Int): Pair<String, Todo?>? {
    val all = try {
      JSONObject(raw ?: return null).optJSONArray("todos") ?: return null
    } catch (_: Throwable) {
      return null
    }
    val kept = JSONArray()
    var gone: Todo? = null
    for (index in 0 until all.length()) {
      val item = all.optJSONObject(index) ?: continue
      if (item.optString("note") == note && item.optInt("line") == line) {
        gone = todoOf(item)
      } else {
        kept.put(item)
      }
    }
    return JSONObject().put("todos", kept).toString() to gone
  }

  // ---- notes and recordings ----------------------------------------------------------------------------------------

  /** A note as Recent notes and Voice note list it (`notesJson`). [kind] is `note`, `tape`, `book` or `canvas`. */
  data class Row(val id: String, val title: String, val line: String, val updated: Long, val kind: String, val ms: Long, val pinned: Boolean)

  fun notes(raw: String?): List<Row> = items(raw, "notes").mapNotNull(::rowOf)

  /** What a row says under its name: a tape's length first, "0:40 · …", then how the note starts. */
  fun lineOf(row: Row): String = when {
    row.ms > 0 && row.line.isNotEmpty() -> "${counter(row.ms)} · ${row.line}"
    row.ms > 0 -> counter(row.ms)
    else -> row.line
  }

  // ---- the calendars -----------------------------------------------------------------------------------------------

  /** An event: [first] and [last] are the days it is on; [start] and [end] its moments. */
  data class Event(val id: String, val title: String, val calendar: String, val location: String?, val allDay: Boolean, val first: String, val last: String, val start: Long, val end: Long)

  /** Whether the Calendar plugin is on, and the events; null where the app has handed nothing over yet. */
  data class Events(val on: Boolean, val events: List<Event>)

  /**
   * The calendar as handed over (`calendarJson`, the snapshot's `calendar` and `events`): an all-day event's `start`
   * and `end` are its first day and the day after its last; a timed one's are moments in UTC, its days this phone's.
   */
  fun calendar(raw: String?, zone: TimeZone = TimeZone.getDefault()): Events? {
    if (raw == null) return null
    return try {
      val read = JSONObject(raw)
      Events(
        read.optBoolean("calendar"),
        items(raw, "events").mapNotNull {
          val start = it.text("start") ?: return@mapNotNull null
          val end = it.text("end") ?: start
          val title = it.text("title") ?: "Untitled event"
          if (it.optBoolean("allDay")) {
            val days = daysBetween(start, end) ?: return@mapNotNull null
            Event(it.optString("id"), title, it.optString("calendar"), it.text("location"), true, start, if (days > 0) dayAfter(end, -1)!! else start, 0, 0)
          } else {
            val from = moment(start) ?: return@mapNotNull null
            val to = moment(end) ?: from
            Event(it.optString("id"), title, it.optString("calendar"), it.text("location"), false, dayOf(from, zone), dayOf(maxOf(from, to - 1), zone), from, to)
          }
        },
      )
    } catch (_: Throwable) {
      null
    }
  }

  private val iso = Regex("""^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|[+-]\d{2}:?\d{2})?$""")

  /** An ISO 8601 moment, as Dart's `toIso8601String` writes one in UTC: milliseconds since the epoch. */
  fun moment(text: String): Long? {
    val g = iso.matchEntire(text.trim())?.groupValues ?: return null
    val at = GregorianCalendar(utc).apply {
      clear()
      set(g[1].toInt(), g[2].toInt() - 1, g[3].toInt(), g[4].toInt(), g[5].toInt(), g[6].ifEmpty { "0" }.toInt())
    }.timeInMillis
    val millis = g[7].take(3).padEnd(3, '0').toLong()
    val zone = g[8]
    val offset = if (zone.isEmpty() || zone == "Z") 0L else {
      val digits = zone.substring(1).replace(":", "")
      val minutes = digits.substring(0, 2).toLong() * 60 + digits.substring(2, 4).toLong()
      (if (zone[0] == '-') -minutes else minutes) * 60_000
    }
    return at + millis - offset
  }

  /**
   * The shared snapshot (`widgets`: `todos`, `notes`, `calendar`, `events`) as the three this side keeps, each the
   * shape [todos], [notes] and [calendar] read; null where it is not one.
   */
  fun split(raw: String): Triple<String, String, String>? = try {
    val read = JSONObject(raw)
    Triple(
      JSONObject().put("todos", read.optJSONArray("todos") ?: JSONArray()).toString(),
      JSONObject().put("notes", read.optJSONArray("notes") ?: JSONArray()).toString(),
      JSONObject().put("calendar", read.optBoolean("calendar")).put("events", read.optJSONArray("events") ?: JSONArray()).toString(),
    )
  } catch (_: Throwable) {
    null
  }

  /** One day of the Calendar widget: its events, all-day ones first, then the to-dos due on it. */
  data class Day(val day: String, val events: List<Event>, val todos: List<Todo>)

  /**
   * The days from [today], [days] of them, that have anything on them: each day's events (a timed one gone once it
   * has ended at [now]) and the to-dos due that day, as the app's calendar of to-dos shows them beside each other.
   * Today's take the overdue ones too, so nothing late goes unseen.
   */
  fun agenda(events: List<Event>, todos: List<Todo>, today: String, now: Long, days: Int = 7): List<Day> {
    val out = mutableListOf<Day>()
    for (step in 0 until days) {
      val day = dayAfter(today, step) ?: break
      val on = events.filter { it.first <= day && it.last >= day && (it.allDay || it.end > now) }.sortedWith(compareBy({ !it.allDay }, { it.start }, { it.title.lowercase(Locale.ROOT) }))
      val due = todos.filter { val d = it.due ?: return@filter false; if (step == 0) d <= day else d == day }
      if (on.isNotEmpty() || due.isNotEmpty()) out.add(Day(day, on, due))
    }
    return out
  }

  // ---- words -------------------------------------------------------------------------------------------------------

  /** The tape counter: "0:07", "12:40", "1:02:03" (lib/tapes/tape.dart `counter`). */
  fun counter(ms: Long): String {
    val total = maxOf(0L, ms / 1000)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = (total % 60).toString().padStart(2, '0')
    return if (h > 0) "$h:${m.toString().padStart(2, '0')}:$s" else "$m:$s"
  }

  /**
   * When a note was touched, as the home page says it (lib/notes/when.dart): "Just now", "20 min ago", "3 hr ago",
   * "Yesterday", the weekday within a week, then the date. [weekday] and [date] are the phone's own words for them.
   */
  fun ago(ms: Long, now: Long, weekday: (Long) -> String, date: (Long) -> String): String {
    val delta = now - ms
    val minute = 60_000L
    val hour = 60 * minute
    val day = 24 * hour
    return when {
      delta < minute -> "Just now"
      delta < hour -> "${delta / minute} min ago"
      delta < day -> "${delta / hour} hr ago"
      delta < 2 * day -> "Yesterday"
      delta < 7 * day -> weekday(ms)
      else -> date(ms)
    }
  }

  /**
   * A due day as the To-dos view says it, counted from [today] (lib/simple/todos_groups.dart `dueWords`): "Today",
   * "Tomorrow", "Yesterday", the weekday within a week ahead, "3 days ago" within a week back, then the date.
   */
  fun dueWords(due: String, today: String, weekday: (String) -> String, date: (String) -> String): String {
    val days = daysBetween(today, due) ?: return due
    return when {
      days == 0 -> "Today"
      days == 1 -> "Tomorrow"
      days == -1 -> "Yesterday"
      days in 2..6 -> weekday(due)
      days in -6..-2 -> "${-days} days ago"
      else -> date(due)
    }
  }

  /** A Calendar widget's day heading: Today, Tomorrow, then the weekday. */
  fun dayWords(day: String, today: String, weekday: (String) -> String): String = when (daysBetween(today, day)) {
    0 -> "Today"
    1 -> "Tomorrow"
    else -> weekday(day)
  }

  // ---- days --------------------------------------------------------------------------------------------------------

  private val utc: TimeZone = TimeZone.getTimeZone("UTC")

  private fun read(day: String): GregorianCalendar? {
    val parts = day.split('-')
    if (parts.size != 3) return null
    val (y, m, d) = parts.map { it.toIntOrNull() ?: return null }
    return GregorianCalendar(utc).apply {
      clear()
      set(y, m - 1, d)
    }
  }

  fun written(at: Calendar): String = String.format(Locale.US, "%04d-%02d-%02d", at.get(Calendar.YEAR), at.get(Calendar.MONTH) + 1, at.get(Calendar.DAY_OF_MONTH))

  /** Whole days from [from] to [to]: negative before it. */
  fun daysBetween(from: String, to: String): Int? {
    val a = read(from) ?: return null
    val b = read(to) ?: return null
    return Math.round((b.timeInMillis - a.timeInMillis) / 86_400_000.0).toInt()
  }

  fun dayAfter(day: String, days: Int): String? = read(day)?.apply { add(Calendar.DAY_OF_MONTH, days) }?.let(::written)

  /** The day [ms] is on, on this phone's clock. */
  fun dayOf(ms: Long, zone: TimeZone = TimeZone.getDefault()): String = written(Calendar.getInstance(zone).apply { timeInMillis = ms })

  // ---- a note's lines (A note, Today) ------------------------------------------------------------------------------

  /** What a line is (lib/home_screen/home_data.dart `PageLineKind`): `text`, `heading`, `bullet`, `quote`, `todo`, `done`. */
  data class Line(val line: Int, val kind: String, val words: String, val match: String?, val depth: Int) {
    val todo: Boolean get() = kind == "todo"
    val done: Boolean get() = kind == "done"
  }

  /** A note as A note and Today draw it: its row and its first lines after its name (`HomePage`). */
  data class Page(val row: Row, val lines: List<Line>)

  private fun rowOf(it: JSONObject): Row? {
    val id = it.text("id") ?: return null
    return Row(id, it.text("title") ?: "Untitled", it.optString("line"), it.optLong("updated"), it.text("kind") ?: "note", it.optLong("ms"), it.optBoolean("pinned"))
  }

  private fun pageOf(it: JSONObject?): Page? {
    val row = rowOf(it ?: return null) ?: return null
    val lines = it.optJSONArray("lines") ?: JSONArray()
    return Page(
      row,
      (0 until lines.length()).mapNotNull { index ->
        val line = lines.optJSONObject(index) ?: return@mapNotNull null
        val words = line.text("words") ?: return@mapNotNull null
        Line(line.optInt("line"), line.text("kind") ?: "text", words, line.text("match"), line.optInt("depth").coerceIn(0, 3))
      },
    )
  }

  /** The notes the A note widgets were set to (`pagesJson`), by id, and those deleted or in the Trash. */
  data class Pages(val pages: Map<String, Page>, val gone: Set<String>)

  fun pages(raw: String?): Pages? {
    if (raw == null) return null
    return try {
      val read = JSONObject(raw)
      val gone = read.optJSONArray("gone") ?: JSONArray()
      Pages(items(raw, "pages").mapNotNull(::pageOf).associateBy { it.row.id }, (0 until gone.length()).map { gone.optString(it) }.filter { it.isNotEmpty() }.toSet())
    } catch (_: Throwable) {
      null
    }
  }

  /** Today's note as Today draws it (`dailyJson`): the day it was handed for, and that day's note, if there is one. */
  data class Daily(val day: String, val page: Page?)

  fun daily(raw: String?): Daily? = try {
    val read = JSONObject(raw ?: return null)
    read.text("day")?.let { Daily(it, pageOf(read.optJSONObject("note"))) }
  } catch (_: Throwable) {
    null
  }

  /**
   * [raw] (`pages` or `daily`) with [line] of [note] drawn ticked: a to-do ticked on A note or Today, ticked there at
   * once, before the app has written it (HomeScreen.ticked). Null where nothing changed.
   */
  fun tickedIn(raw: String?, note: String, line: Int): String? {
    val read = try {
      JSONObject(raw ?: return null)
    } catch (_: Throwable) {
      return null
    }
    var changed = false
    fun tick(page: JSONObject?) {
      if (page == null || page.optString("id") != note) return
      val lines = page.optJSONArray("lines") ?: return
      for (index in 0 until lines.length()) {
        val each = lines.optJSONObject(index) ?: continue
        if (each.optInt("line") == line && each.optString("kind") == "todo") {
          each.put("kind", "done")
          changed = true
        }
      }
    }
    read.optJSONArray("pages")?.let { all -> for (index in 0 until all.length()) tick(all.optJSONObject(index)) }
    tick(read.optJSONObject("note"))
    return if (changed) read.toString() else null
  }

  /** How many rows of [chars] characters a line of words takes at [perRow] characters a row, [most] at most. */
  fun rowsFor(chars: Int, perRow: Int, most: Int): Int = ((chars + perRow - 1) / maxOf(1, perRow)).coerceIn(1, most)

  // ---- folders (A folder) ------------------------------------------------------------------------------------------

  /** A workspace or a folder (`HomeFolder`): [path] its name with its parents' ("Acme › Design"), [org] in one. */
  data class Folder(val id: String, val name: String, val path: String, val org: Boolean, val hue: String?, val count: Int, val notes: List<Row>)

  fun folders(raw: String?): List<Folder>? {
    if (raw == null) return null
    return items(raw, "folders").mapNotNull {
      val id = it.text("id") ?: return@mapNotNull null
      val name = it.text("name") ?: "Untitled"
      val notes = it.optJSONArray("notes") ?: JSONArray()
      Folder(id, name, it.text("path") ?: name, it.optBoolean("org"), it.text("hue"), it.optInt("count"), (0 until notes.length()).mapNotNull { index -> notes.optJSONObject(index)?.let(::rowOf) })
    }
  }

  // ---- the assistant (Ask AI) --------------------------------------------------------------------------------------

  /** Whether Claude is on and a key entered (`assistantJson`): shown, as the dock shows it, only with both. */
  data class Assistant(val on: Boolean, val key: Boolean) {
    val shown: Boolean get() = on && key
  }

  fun assistant(raw: String?): Assistant? = try {
    val read = JSONObject(raw ?: return null)
    Assistant(read.optBoolean("on"), read.optBoolean("key"))
  } catch (_: Throwable) {
    null
  }

  // ---- Next up -------------------------------------------------------------------------------------------------------

  /**
   * What Next up shows, the first the most pressing: today's timed events not yet over (the one on now first, then the
   * soonest), else the to-dos overdue (the longest overdue first) and those due today; then the rest of those, and
   * today's all-day events last. A list of [Event] and [Todo].
   */
  fun nextUp(events: List<Event>, todos: List<Todo>, today: String, now: Long): List<Any> {
    val timed = events.filter { !it.allDay && it.first <= today && it.last >= today && it.end > now }.sortedWith(compareBy({ it.start }, { it.title.lowercase(Locale.ROOT) }))
    val allDay = events.filter { it.allDay && it.first <= today && it.last >= today }.sortedBy { it.title.lowercase(Locale.ROOT) }
    val due = todos.filter { val d = it.due ?: return@filter false; d <= today }.sortedWith(compareBy({ it.due }, { it.title.lowercase(Locale.ROOT) }, { it.line }))
    return timed + due + allDay
  }

  /**
   * When the next thing is, as Next up's eyebrow says it: "Now" for an event on, "In 25 min", "In 2 hr", "In 1 hr 20
   * min" for one to come; for a to-do, "Overdue · 3 days", "Overdue · Yesterday", "Due today".
   */
  fun whenNext(item: Any, today: String, now: Long): String = when (item) {
    is Event -> when {
      item.allDay -> "All day"
      item.start <= now -> "Now"
      else -> {
        val minutes = ((item.start - now + 59_999) / 60_000).toInt()
        val hours = minutes / 60
        val rest = minutes % 60
        when {
          minutes < 60 -> "In $minutes min"
          rest == 0 -> "In $hours hr"
          else -> "In $hours hr $rest min"
        }
      }
    }
    is Todo -> {
      val days = item.due?.let { daysBetween(it, today) } ?: 0
      when {
        days <= 0 -> "Due today"
        days == 1 -> "Overdue · Yesterday"
        else -> "Overdue · $days days"
      }
    }
    else -> ""
  }

  /** The next moment Next up says something else of its first: its event's start where it is to come, else its end. */
  fun nextChange(items: List<Any>, now: Long): Long? {
    val first = items.firstOrNull() as? Event ?: return null
    if (first.allDay) return null
    return if (first.start > now) first.start else first.end
  }

  // ---- sizes ---------------------------------------------------------------------------------------------------------

  /**
   * The size a widget is drawn at, by the room the launcher gives it (docs/WIDGETS_ANDROID.md, "Sizes"): [TINY] a cell
   * each way (1×1), [SLIM] a cell high and wider (2×1, 4×1), [NARROW] two cells across or one and taller (1×N, 2×N),
   * [MEDIUM] three cells across or more and two high (4×2), [LARGE] three high or more (4×3, 4×4). Measured on the
   * Pixel launcher at 420dpi (a cell 75dp across and 82dp high, two 159 by 181, four 330 by 380) and the Fold's
   * cover screen, whose cells are a little larger.
   */
  enum class Fit { TINY, SLIM, NARROW, MEDIUM, LARGE }

  /** Narrower or shorter than this, a widget is a cell that way. */
  const val ONE_CELL_DP = 120

  /** Narrower than this, a widget is two cells across at most: a column. */
  const val NARROW_DP = 215

  /** This tall or more, a widget is large. */
  const val LARGE_DP = 230

  fun fitOf(wide: Int, tall: Int): Fit = when {
    tall < ONE_CELL_DP && wide < ONE_CELL_DP -> Fit.TINY
    tall < ONE_CELL_DP -> Fit.SLIM
    wide < NARROW_DP -> Fit.NARROW
    tall >= LARGE_DP -> Fit.LARGE
    else -> Fit.MEDIUM
  }

  // ---- room ----------------------------------------------------------------------------------------------------------

  /**
   * One thing in a widget's list, for [fill], in dp: [full] its row's height, [compact] its one-line row's (a to-do's
   * tick and words, an event's time and title, a note's name). A [heading] (a group's eyebrow, a note's heading) is
   * drawn the same either way and never last: it shows only with the row under it.
   */
  data class Part(val full: Int, val compact: Int = full, val heading: Boolean = false)

  /**
   * How a list is drawn in its room ([fill]): its first [shown] parts, those from [compactFrom] on as one-line rows;
   * [left] the rows not shown (headings not counted), and [more] whether the line that says so is drawn under them;
   * [spare] the dp left after it all, and [spread] whether that is shared out between the rows rather than left as a
   * band under the last (where the list was cut, or what is left is less than a row).
   */
  data class Filled(val shown: Int, val compactFrom: Int, val left: Int, val more: Boolean, val spare: Int, val spread: Boolean) {
    fun compact(index: Int): Boolean = index >= compactFrom
  }

  /**
   * [parts] in [room] (Matt, 2026-10-21: "make sure they take up 100% of avail space"): whole rows while the next
   * fits; then, where it does not, one-line rows while they fit, a heading only where it and a one-line row under it
   * do; then, with rows still left and [more] dp to spare, the line that says how many (0: no line). A row at least,
   * where the first is one. Once rows go to one line they stay so, the rest of the list alike.
   */
  fun fill(room: Int, parts: List<Part>, more: Int = 0): Filled {
    var used = 0
    var shown = 0
    var compactFrom = parts.size
    while (shown < parts.size) {
      val part = parts[shown]
      // A heading's room is its own and its first row's; one with nothing under it (a note's last line), its own.
      val under = if (part.heading) parts.getOrNull(shown + 1) else null
      val compacting = shown >= compactFrom
      when {
        !compacting && used + part.full + (under?.full ?: 0) <= room -> used += part.full
        used + (if (part.heading) part.full else part.compact) + (under?.compact ?: 0) <= room -> {
          if (!compacting) compactFrom = if (part.heading) shown + 1 else shown
          used += if (part.heading) part.full else part.compact
        }
        else -> break
      }
      shown += 1
    }
    if (shown == 0 && parts.isNotEmpty() && !parts[0].heading) {
      // Not even one line fits (a launcher's odd size): the first row anyway, as small as it is drawn.
      shown = 1
      compactFrom = 0
      used = parts[0].compact
    }
    val left = parts.drop(shown).count { !it.heading }
    val line = more > 0 && left > 0 && room - used >= more
    val spare = room - used - if (line) more else 0
    val least = parts.filter { !it.heading }.minOfOrNull { it.compact } ?: 0
    return Filled(shown, compactFrom, left, line, spare, left > 0 || spare < least)
  }
}
