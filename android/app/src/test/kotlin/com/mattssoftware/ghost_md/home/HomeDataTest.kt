package com.mattssoftware.ghost_md.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the four home-screen widgets make of what the app handed over (HomeData.kt, docs/WIDGETS.md): the To-dos
 * view's groups and words, the home page's "20 min ago", the Calendar widget's days, and how a list fills its room.
 */
class HomeDataTest {
  private val todosJson = """
    {"todos":[
      {"note":"b","line":2,"words":"Send the report","match":"Send the report","due":"2026-10-18","title":"Work","priority":"high"},
      {"note":"a","line":2,"words":"Call Bob","match":"Call [[Bob]]","due":"2026-10-20","title":"Errands"},
      {"note":"c","line":0,"words":"Fix the login","match":"Fix the login","due":"2026-10-22","title":"Fix the login"},
      {"note":"a","line":3,"words":"Buy milk","title":"Errands"}
    ]}
  """.trimIndent()

  @Test
  fun `the to-dos in the To-dos view's groups, in the order handed over`() {
    val grouped = HomeData.grouped(HomeData.todos(todosJson), "2026-10-20")
    assertEquals(listOf(HomeData.Group.OVERDUE, HomeData.Group.TODAY, HomeData.Group.LATER, HomeData.Group.SOMEDAY), grouped.map { it.first })
    assertEquals(listOf("Overdue", "Today", "Later", "Someday"), grouped.map { it.first.words })
    assertEquals("Buy milk", grouped.last().second.single().words)
    assertEquals("a to-do with no match is found by its words", "Buy milk", grouped.last().second.single().match)
    assertEquals("High", HomeData.priorityWords(grouped.first().second.single().priority))
    assertNull("no due day for one with none", grouped.last().second.single().due)
  }

  @Test
  fun `the day turns with nothing asked of the app`() {
    val tomorrow = HomeData.grouped(HomeData.todos(todosJson), "2026-10-21")
    assertEquals(listOf(HomeData.Group.OVERDUE, HomeData.Group.LATER, HomeData.Group.SOMEDAY), tomorrow.map { it.first })
    assertEquals(2, tomorrow.first().second.size)
  }

  @Test
  fun `a tick takes the to-do off at once and says which it was`() {
    val (left, gone) = HomeData.without(todosJson, "a", 2)!!
    assertEquals("Call [[Bob]]", gone!!.match)
    assertEquals(3, HomeData.todos(left).size)
    assertTrue(HomeData.todos(left).none { it.note == "a" && it.line == 2 })
    assertNull(HomeData.without(todosJson, "zz", 9)!!.second)
  }

  @Test
  fun `a due day as the To-dos view says it`() {
    val weekday = { day: String -> "Weekday $day" }
    val date = { day: String -> "Date $day" }
    val today = "2026-10-20"
    assertEquals("Today", HomeData.dueWords("2026-10-20", today, weekday, date))
    assertEquals("Tomorrow", HomeData.dueWords("2026-10-21", today, weekday, date))
    assertEquals("Yesterday", HomeData.dueWords("2026-10-19", today, weekday, date))
    assertEquals("Weekday 2026-10-23", HomeData.dueWords("2026-10-23", today, weekday, date))
    assertEquals("3 days ago", HomeData.dueWords("2026-10-17", today, weekday, date))
    assertEquals("Date 2026-11-02", HomeData.dueWords("2026-11-02", today, weekday, date))
    assertEquals("across a month's end", "Tomorrow", HomeData.dueWords("2026-11-01", "2026-10-31", weekday, date))
  }

  @Test
  fun `when a note was touched, as the home page says it`() {
    val now = 1_800_000_000_000L
    val minute = 60_000L
    val weekday = { _: Long -> "Tuesday" }
    val date = { _: Long -> "October 3" }
    assertEquals("Just now", HomeData.ago(now - 20_000, now, weekday, date))
    assertEquals("20 min ago", HomeData.ago(now - 20 * minute, now, weekday, date))
    assertEquals("3 hr ago", HomeData.ago(now - 190 * minute, now, weekday, date))
    assertEquals("Yesterday", HomeData.ago(now - 30 * 60 * minute, now, weekday, date))
    assertEquals("Tuesday", HomeData.ago(now - 4 * 24 * 60 * minute, now, weekday, date))
    assertEquals("October 3", HomeData.ago(now - 20 * 24 * 60 * minute, now, weekday, date))
  }

  @Test
  fun `a tape's counter and a row's line`() {
    assertEquals("0:07", HomeData.counter(7_400))
    assertEquals("12:40", HomeData.counter(760_000))
    assertEquals("1:02:03", HomeData.counter(3_723_000))
    val notes = HomeData.notes("""{"notes":[{"id":"t","title":"Standup","line":"We talked","updated":5,"kind":"tape","ms":40000,"pinned":true},{"id":"n","title":"Groceries","line":"","updated":3,"kind":"note"}]}""")
    assertEquals("0:40 · We talked", HomeData.lineOf(notes[0]))
    assertEquals("", HomeData.lineOf(notes[1]))
    assertTrue(notes[0].pinned)
    assertEquals(emptyList<HomeData.Row>(), HomeData.notes("not json"))
  }

  @Test
  fun `the calendar off, never handed, and on`() {
    assertNull(HomeData.calendar(null))
    val off = HomeData.calendar("""{"calendar":false,"events":[]}""")!!
    assertEquals(false, off.on)
    val utc = java.util.TimeZone.getTimeZone("UTC")
    val on = HomeData.calendar(
      """{"calendar":true,"events":[
        {"id":"x/1","title":"Standup","calendar":"Work","allDay":false,"start":"2026-10-20T23:30:00.000Z","end":"2026-10-21T00:30:00.000Z"},
        {"id":"x/2","title":"Holiday","calendar":"Home","allDay":true,"start":"2026-10-20","end":"2026-10-23"},
        {"id":"x/3","title":"One day","calendar":"Home","allDay":true,"start":"2026-10-24","end":"2026-10-25"}
      ]}""",
      utc,
    )!!
    assertTrue(on.on)
    assertEquals(3, on.events.size)
    val standup = on.events[0]
    assertEquals("Work", standup.calendar)
    assertEquals("an event past midnight is on both days", "2026-10-20" to "2026-10-21", standup.first to standup.last)
    assertEquals(3_600_000L, standup.end - standup.start)
    assertEquals("the day after an all-day event's last is not in it", "2026-10-20" to "2026-10-22", on.events[1].first to on.events[1].last)
    assertEquals("2026-10-24" to "2026-10-24", on.events[2].first to on.events[2].last)
  }

  @Test
  fun `each day's events, all-day first and a timed one gone once ended, beside the to-dos due that day`() {
    val events = listOf(
      HomeData.Event("1", "Standup", "Work", null, false, "2026-10-20", "2026-10-20", 1_000, 2_000),
      HomeData.Event("2", "Dentist", "Home", "High St", false, "2026-10-20", "2026-10-20", 5_000, 6_000),
      HomeData.Event("3", "Holiday", "Home", null, true, "2026-10-20", "2026-10-22", 0, 0),
    )
    val days = HomeData.agenda(events, HomeData.todos(todosJson), "2026-10-20", now = 3_000)
    assertEquals(listOf("2026-10-20", "2026-10-21", "2026-10-22"), days.map { it.day })
    assertEquals("the ended standup gone, the all-day one first", listOf("Holiday", "Dentist"), days[0].events.map { it.title })
    assertEquals("today's take the overdue ones too", listOf("Send the report", "Call Bob"), days[0].todos.map { it.words })
    assertEquals(listOf("Holiday"), days[1].events.map { it.title })
    assertEquals(listOf("Fix the login"), days[2].todos.map { it.words })
    assertEquals("Today", HomeData.dayWords("2026-10-20", "2026-10-20") { "?" })
    assertEquals("Tomorrow", HomeData.dayWords("2026-10-21", "2026-10-20") { "?" })
    assertEquals("Thursday", HomeData.dayWords("2026-10-22", "2026-10-20") { "Thursday" })
  }

  // The To-dos widget's parts: a group's eyebrow (22dp), a whole row (48dp, or as tall as a column's words make it)
  // and a one-line row (36dp).
  private val eyebrow = HomeData.Part(22, heading = true)
  private fun row(full: Int = 48) = HomeData.Part(full, 36)

  @Test
  fun `the room under the whole rows goes to one-line rows, a group's eyebrow only with one under it`() {
    // Four by three (414×280, 232dp of room) with Overdue 2, Today 2, Later 1, Someday 2: "Send the Q4 report" missed
    // a whole row by 4dp and left 44dp blank under "Call the plumber"; it is a one-line row now, and Later's eyebrow,
    // which would need 58dp with a one-line row under it, is not drawn in the 8dp left.
    val wide = listOf(eyebrow, row(), row(), eyebrow, row(), row(), eyebrow, row(), eyebrow, row(), row())
    val large = HomeData.fill(232, wide, 18)
    assertEquals(6, large.shown)
    assertEquals(5, large.compactFrom)
    assertEquals(listOf(false, false, false, false, false, true), (0 until large.shown).map(large::compact))
    assertEquals(3, large.left)
    assertEquals("no room for the line under them", false, large.more)
    assertEquals(8, large.spare)
    assertTrue("cut, so the 8dp is shared between the rows", large.spread)

    // Two by three (159×280), each to-do's words over two lines (70dp): Overdue's two whole, then Today's eyebrow and
    // "Call the plumber" on one line where its whole row would not fit, 12dp left rather than 70.
    val column = listOf(eyebrow, row(70), row(70), eyebrow, row(70), row(70), eyebrow, row(70), eyebrow, row(70), row(70))
    val tall = HomeData.fill(232, column, 18)
    assertEquals(5, tall.shown)
    assertEquals("the eyebrow drawn as it is, the row under it on one line", 4, tall.compactFrom)
    assertEquals(4, tall.left)
    assertEquals(false, tall.more)
    assertEquals(12, tall.spare)
    assertTrue(tall.spread)

    // Once on one line, the rest stay so: a short row after a tall one is not drawn whole again, though it would fit.
    val mixed = HomeData.fill(150, listOf(row(70), row(90), HomeData.Part(40, 36)), 0)
    assertEquals(3, mixed.shown)
    assertEquals(1, mixed.compactFrom)
    assertEquals(150 - 70 - 36 - 36, mixed.spare)
  }

  @Test
  fun `the line that says how many did not fit, where the rows leave it its room, and what is left shared`() {
    // Four whole rows (192dp) in 220: a fifth on one line would need 228, so the 28dp left holds the line (18dp).
    val cut = HomeData.fill(220, List(10) { row() }, 18)
    assertEquals(4, cut.shown)
    assertEquals(6, cut.left)
    assertTrue(cut.more)
    assertEquals(10, cut.spare)
    assertTrue(cut.spread)
    // No line asked for (a cell high): the room left is the rows'.
    assertEquals(false, HomeData.fill(220, List(10) { row() }, 0).more)
    // Every row whole with room to spare: no line, and the list ends where it ends, at the top.
    val short = HomeData.fill(300, List(3) { row() }, 18)
    assertEquals(3, short.shown)
    assertEquals(0, short.left)
    assertEquals(false, short.more)
    assertEquals(false, short.spread)
    // All of them, with less than a one-line row left: shared between them rather than a band under the last.
    assertTrue(HomeData.fill(170, List(3) { row() }, 18).spread)
    // A heading with nothing under it (a note's last line) is drawn where it fits alone.
    assertEquals(2, HomeData.fill(100, listOf(row(), eyebrow), 0).shown)
    assertEquals("one at least", 1, HomeData.fill(20, listOf(row(), row()), 18).shown)
    assertEquals("but never a heading alone", 0, HomeData.fill(30, listOf(eyebrow, row()), 0).shown)
    assertEquals(0, HomeData.fill(100, emptyList(), 18).shown)
  }

  @Test
  fun `a moment as Dart writes one, and the shared snapshot kept as three`() {
    assertEquals(1_792_539_000_000L, HomeData.moment("2026-10-20T23:30:00.000Z"))
    assertEquals(1_792_539_000_123L, HomeData.moment("2026-10-20T23:30:00.123456Z"))
    assertEquals(1_792_539_000_000L, HomeData.moment("2026-10-21T01:30:00+02:00"))
    assertNull(HomeData.moment("soon"))
    val (todos, notes, calendar) = HomeData.split("""{"v":1,"todos":[{"note":"a","line":2,"words":"Call","match":"Call","title":"Errands"}],"notes":[{"id":"n","title":"Groceries","line":"Eggs","updated":5}],"calendar":true,"events":[]}""")!!
    assertEquals("Call", HomeData.todos(todos).single().words)
    assertEquals("Groceries", HomeData.notes(notes).single().title)
    assertTrue(HomeData.calendar(calendar)!!.on)
  }

  // ---- the eight more ------------------------------------------------------------------------------------------------

  private val pagesJson = """
    {"pages":[
      {"id":"g","title":"Groceries","line":"Eggs","updated":5,"kind":"note","lines":[
        {"line":3,"kind":"heading","words":"Fruit"},
        {"line":4,"kind":"todo","words":"Apples","match":"Apples"},
        {"line":5,"kind":"done","words":"Pears","match":"Pears","depth":1},
        {"line":6,"kind":"bullet","words":"Bread","depth":9}
      ]}
    ],"gone":["old"]}
  """.trimIndent()

  @Test
  fun `A note's lines as handed over, and the notes gone`() {
    val read = HomeData.pages(pagesJson)!!
    assertEquals(setOf("old"), read.gone)
    val page = read.pages.getValue("g")
    assertEquals("Groceries", page.row.title)
    assertEquals(listOf("heading", "todo", "done", "bullet"), page.lines.map { it.kind })
    assertTrue(page.lines[1].todo)
    assertTrue(page.lines[2].done)
    assertEquals("a depth is three at most", 3, page.lines[3].depth)
    assertNull(HomeData.pages(null))
    assertNull("not JSON", HomeData.pages("soon"))
  }

  @Test
  fun `a to-do ticked on A note or Today drawn ticked at once, the rest left as they were`() {
    val ticked = HomeData.tickedIn(pagesJson, "g", 4)!!
    assertEquals(listOf("heading", "done", "done", "bullet"), HomeData.pages(ticked)!!.pages.getValue("g").lines.map { it.kind })
    assertNull("a line that is no to-do is nothing to tick", HomeData.tickedIn(pagesJson, "g", 3))
    assertNull("another note's line", HomeData.tickedIn(pagesJson, "x", 4))
    val daily = """{"day":"2026-10-21","note":{"id":"d","title":"2026-10-21","line":"","updated":1,"kind":"note","lines":[{"line":3,"kind":"todo","words":"Call Mum","match":"Call Mum"}]}}"""
    val read = HomeData.daily(HomeData.tickedIn(daily, "d", 3))!!
    assertEquals("2026-10-21", read.day)
    assertTrue(read.page!!.lines.single().done)
    assertNull("no note today", HomeData.daily("""{"day":"2026-10-21"}""")!!.page)
  }

  @Test
  fun `A folder's folders, an organization's labelled under it, each with its notes`() {
    val folders = HomeData.folders("""{"folders":[{"id":"org-a","name":"Acme","path":"Acme","org":true,"count":1,"notes":[{"id":"c","title":"Logo","line":"","updated":3,"kind":"note"}]},{"id":"w-2","name":"Clients","path":"Work › Clients","count":0,"notes":[]}]}""")!!
    assertEquals(listOf("Acme", "Work › Clients"), folders.map { it.path })
    assertTrue(folders.first().org)
    assertEquals("Logo", folders.first().notes.single().title)
    assertNull(HomeData.folders(null))
  }

  @Test
  fun `Ask AI shows Claude only with it on and a key, as the dock does`() {
    assertTrue(HomeData.assistant("""{"on":true,"key":true}""")!!.shown)
    assertEquals(false, HomeData.assistant("""{"on":true,"key":false}""")!!.shown)
    assertEquals(false, HomeData.assistant("""{"on":false,"key":true}""")!!.shown)
    assertNull(HomeData.assistant(null))
  }

  @Test
  fun `Next up, the event on now or soonest today, else the to-do most overdue, then today's, and when`() {
    val today = "2026-10-21"
    val now = 1_000_000_000_000L
    val minute = 60_000L
    fun event(id: String, start: Long, end: Long, allDay: Boolean = false) = HomeData.Event(id, id, "Home", null, allDay, today, today, start, end)
    val todos = HomeData.todos(
      """{"todos":[
        {"note":"a","line":2,"words":"Today's","due":"2026-10-21","title":"A"},
        {"note":"b","line":2,"words":"Late","due":"2026-10-18","title":"B"},
        {"note":"c","line":2,"words":"Tomorrow's","due":"2026-10-22","title":"C"},
        {"note":"d","line":2,"words":"Someday","title":"D"}
      ]}""",
    )
    val ended = event("ended", now - 90 * minute, now - 30 * minute)
    val later = event("later", now + 130 * minute, now + 160 * minute)
    val soon = event("soon", now + 25 * minute, now + 55 * minute)
    val holiday = event("holiday", 0, 0, allDay = true)
    val items = HomeData.nextUp(listOf(later, ended, holiday, soon), todos, today, now)
    assertEquals(listOf("soon", "later", "Late", "Today's", "holiday"), items.map { if (it is HomeData.Event) it.id else (it as HomeData.Todo).words })
    assertEquals("In 25 min", HomeData.whenNext(soon, today, now))
    assertEquals("In 2 hr 10 min", HomeData.whenNext(later, today, now))
    assertEquals("In 2 hr", HomeData.whenNext(event("x", now + 120 * minute, now + 130 * minute), today, now))
    assertEquals("Now", HomeData.whenNext(event("on", now - minute, now + minute), today, now))
    assertEquals("Overdue · 3 days", HomeData.whenNext(items[2], today, now))
    assertEquals("Due today", HomeData.whenNext(items[3], today, now))
    assertEquals("the next change is the first one's start", soon.start, HomeData.nextChange(items, now))
    assertEquals("one on now changes as it ends", now + minute, HomeData.nextChange(listOf(event("on", now - minute, now + minute)), now))
    assertNull("a to-do first changes with the day", HomeData.nextChange(items.drop(2), now))
    val none = HomeData.nextUp(emptyList(), todos, today, now)
    assertEquals("no events: the to-dos due by today, the most overdue first", listOf("Late", "Today's"), none.map { (it as HomeData.Todo).words })
  }

  @Test
  fun `the size a widget is drawn at, by the room the launcher gives it`() {
    assertEquals(HomeData.Fit.TINY, HomeData.fitOf(75, 82))
    assertEquals(HomeData.Fit.SLIM, HomeData.fitOf(159, 82))
    assertEquals(HomeData.Fit.SLIM, HomeData.fitOf(330, 82))
    assertEquals(HomeData.Fit.NARROW, HomeData.fitOf(159, 181))
    assertEquals(HomeData.Fit.NARROW, HomeData.fitOf(159, 380))
    assertEquals(HomeData.Fit.NARROW, HomeData.fitOf(75, 280))
    assertEquals(HomeData.Fit.MEDIUM, HomeData.fitOf(330, 181))
    assertEquals(HomeData.Fit.LARGE, HomeData.fitOf(330, 280))
    assertEquals(HomeData.Fit.LARGE, HomeData.fitOf(600, 380))
    assertEquals(2, HomeData.rowsFor(30, 20, 2))
    assertEquals(1, HomeData.rowsFor(0, 20, 2))
    assertEquals(2, HomeData.rowsFor(300, 20, 2))
  }

  @Test
  fun `days counted on the calendar, not the clock`() {
    assertEquals(1, HomeData.daysBetween("2026-03-28", "2026-03-29"))
    assertEquals(-31, HomeData.daysBetween("2026-11-01", "2026-10-01"))
    assertEquals("2027-01-01", HomeData.dayAfter("2026-12-31", 1))
    assertNull(HomeData.daysBetween("soon", "2026-10-01"))
  }
}
