package com.mattssoftware.ghost_md

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which of a pattern's letters are fields (Dates.kt `fieldsOf`): the phone is asked for a day's finer periods only
 * where a pattern writes them (`B`), and a letter between quotes is a word of the pattern, not a field. The
 * names themselves are Android's ICU's, which a JVM test has none of.
 */
class DatesTest {
  @Test
  fun a_run_of_the_letter_is_a_field_and_quoted_words_are_not() {
    // Taiwan's medium date and short time.
    assertEquals(setOf("B"), Dates.fieldsOf("y年M月d日 Bh:mm", 'B'))
    assertEquals(setOf("B", "BBBB"), Dates.fieldsOf("BBBB h:mm, B", 'B'))
    assertEquals(emptySet<String>(), Dates.fieldsOf("h:mm a", 'B'))
    // "B" as a word of the pattern, and an apostrophe that is not a quote's end.
    assertEquals(emptySet<String>(), Dates.fieldsOf("h 'B' mm", 'B'))
    assertEquals(setOf("BB"), Dates.fieldsOf("h 'o''clock B' BB", 'B'))
    assertEquals(setOf("B"), Dates.fieldsOf("''B", 'B'))
  }
}
