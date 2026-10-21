package com.mattssoftware.ghost_md.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the four home-screen widgets make of what the app handed over (HomeData.kt, docs/WIDGETS.md): the To-dos
 * view's groups and words, the home page's "20 min ago", the Calendar widget's days, and how many rows fit.
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

  @Test
  fun `as many rows as fit, with room for the line that says how many did not`() {
    assertEquals(3, HomeData.fitting(160, listOf(50, 50, 50), 18))
    assertEquals(2, HomeData.fitting(140, listOf(50, 50, 50), 18))
    assertEquals("one at least", 1, HomeData.fitting(20, listOf(50, 50), 18))
    assertEquals(0, HomeData.fitting(100, emptyList(), 18))
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

  @Test
  fun `days counted on the calendar, not the clock`() {
    assertEquals(1, HomeData.daysBetween("2026-03-28", "2026-03-29"))
    assertEquals(-31, HomeData.daysBetween("2026-11-01", "2026-10-01"))
    assertEquals("2027-01-01", HomeData.dayAfter("2026-12-31", 1))
    assertNull(HomeData.daysBetween("soon", "2026-10-01"))
  }
}
