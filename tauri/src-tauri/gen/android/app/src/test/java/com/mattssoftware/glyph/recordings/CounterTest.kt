package com.mattssoftware.glyph.recordings

import org.junit.Assert.assertEquals
import org.junit.Test

/** The notification's counter reads as the tape's does on the page (capture/tape.ts `counter`). */
class CounterTest {
  @Test
  fun minutes_and_seconds_until_an_hour_then_hours_too() {
    assertEquals("0:00", counter(0))
    assertEquals("0:05", counter(5_400))
    assertEquals("12:40", counter(760_000))
    assertEquals("59:59", counter(3_599_999))
    assertEquals("1:00:00", counter(3_600_000))
    assertEquals("1:02:03", counter(3_723_000))
    assertEquals("2:00:00", counter(2 * 60 * 60 * 1000L))
  }

  @Test
  fun a_negative_reading_is_zero() {
    assertEquals("0:00", counter(-1))
  }
}
