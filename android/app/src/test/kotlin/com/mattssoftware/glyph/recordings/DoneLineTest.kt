package com.mattssoftware.glyph.recordings

import org.junit.Assert.assertEquals
import org.junit.Test

/** The written-up notification's line for each way a write-up can end done (WriteUp.doneLine). */
class DoneLineTest {
  private fun done(line: String?, summary: Boolean, chars: Int) = Outcome.Done("Meeting, 26 Sep 14:05", line, summary, chars)

  @Test
  fun the_summarys_first_sentence_when_there_is_one() {
    assertEquals("What the call settled about the March launch.", WriteUp.doneLine(done("What the call settled about the March launch.", true, 41_230)))
  }

  @Test
  fun the_notes_place_when_there_is_no_sentence_to_show() {
    assertEquals("The summary is in the note.", WriteUp.doneLine(done(null, true, 41_230)))
    assertEquals("The summary is in the note.", WriteUp.doneLine(done("  ", true, 41_230)))
    assertEquals("The transcript is in the note.", WriteUp.doneLine(done(null, false, 41_230)))
  }

  @Test
  fun a_recording_with_no_speech_says_so() {
    assertEquals("Nothing was heard in the recording.", WriteUp.doneLine(done(null, false, 0)))
  }
}
