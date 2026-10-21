package com.mattssoftware.ghost_md.home

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone

/**
 * What the four widgets draw, read from what the app handed over (lib/home_screen/home_data.dart;
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

  fun notes(raw: String?): List<Row> = items(raw, "notes").mapNotNull {
    val id = it.text("id") ?: return@mapNotNull null
    Row(id, it.text("title") ?: "Untitled", it.optString("line"), it.optLong("updated"), it.text("kind") ?: "note", it.optLong("ms"), it.optBoolean("pinned"))
  }

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

  // ---- room ----------------------------------------------------------------------------------------------------------

  /**
   * How many of [heights] (each a row's height, in order) fit in [room]: all where they fit, else as many as fit with
   * [more] under them for the line that says how many did not; one at least.
   */
  fun fitting(room: Int, heights: List<Int>, more: Int): Int {
    if (heights.sum() <= room) return heights.size
    var used = 0
    var shown = 0
    for (height in heights) {
      if (used + height > room - more) break
      used += height
      shown += 1
    }
    return shown.coerceAtLeast(minOf(1, heights.size))
  }
}
