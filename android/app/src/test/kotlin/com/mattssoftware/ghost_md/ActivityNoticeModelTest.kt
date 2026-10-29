package com.mattssoftware.ghost_md

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A job as the app tells it (lib/activity/activity_surfaces.dart `surfaceJob`, the maps its test checks) and what its
 * notification says (ActivityNoticeModel.kt; ActivityNotices.kt draws it).
 */
class ActivityNoticeModelTest {
  private fun told(vararg pairs: Pair<String, Any?>): Map<String, Any?> = mapOf(
    "id" to "lovart-banners",
    "kind" to "images",
    "look" to "images",
    "state" to "running",
    "title" to "Making header images",
    "line" to "Making header images",
    "colour" to 0xFFD6336CL,
    "colourDark" to 0xFFFF7AA8L,
    "stoppable" to true,
    "openable" to true,
    "here" to true,
    "startedAt" to 1_790_000_000_000L,
  ) + pairs

  @Test
  fun a_job_is_read_as_the_app_tells_it() {
    val job = NoticeJob.from(told("fraction" to 0.4, "steps" to "40 of 100", "line" to "Making header images, 40 of 100"))!!
    assertEquals("lovart-banners", job.id)
    assertEquals("images", job.glyph)
    assertTrue(job.live)
    assertTrue(job.stoppable)
    assertEquals(0xFFD6336C.toInt(), job.colour)
    assertEquals(400, job.progress)
    assertFalse(job.indeterminate)
    assertEquals("40%", job.chipText)
    assertEquals("Making header images, 40 of 100", job.text)
    assertEquals(1_790_000_000_000L, job.startedAt)
  }

  @Test
  fun one_that_cannot_say_how_far_goes_round_and_its_chip_is_the_glyph_alone() {
    val job = NoticeJob.from(told())!!
    assertNull(job.progress)
    assertTrue(job.indeterminate)
    assertNull(job.chipText)
    // Its line is its title: nothing more under it.
    assertEquals("", job.text)
  }

  @Test
  fun waiting_and_failed_wear_their_own_looks() {
    val waiting = NoticeJob.from(told("state" to "waiting", "look" to "waiting", "line" to "Waiting for Wi-Fi", "colour" to 0xFF747474L))!!
    assertTrue(waiting.live)
    assertEquals("Wait", waiting.chipText)
    assertEquals("Waiting for Wi-Fi", waiting.text)
    assertEquals("images", waiting.glyph)
    val failed = NoticeJob.from(told("state" to "failed", "look" to "needsYou", "cause" to "Lovart is out of credits", "stoppable" to false))!!
    assertFalse(failed.live)
    assertTrue(failed.failed)
    assertEquals("needs_you", failed.glyph)
    assertEquals("Lovart is out of credits", failed.cause)
    assertNull(failed.chipText)
  }

  @Test
  fun calm_and_a_kind_from_a_later_build_are_read_too() {
    val calm = NoticeJob.from(told() - "colour" - "colourDark")!!
    assertNull(calm.colour)
    assertEquals("ring", NoticeJob.from(told("kind" to "teleport", "look" to "teleport"))!!.glyph)
    assertNull(NoticeJob.from(mapOf("title" to "No id")))
    assertNull(NoticeJob.from(null))
  }

  @Test
  fun a_fraction_out_of_bounds_is_held_to_the_bar() {
    assertEquals(NoticeJob.MAX, NoticeJob.from(told("fraction" to 1.7))!!.progress)
    assertEquals(0, NoticeJob.from(told("fraction" to -0.2))!!.progress)
    assertEquals("100%", NoticeJob.from(told("fraction" to 1.7))!!.chipText)
  }

  @Test
  fun each_job_keeps_its_notification_id_while_it_shows() {
    val ids = NoticeIds()
    val a = ids.of("lovart-banners")
    val b = ids.of("share-audio:n1")
    assertEquals(NoticeIds.FIRST, a)
    assertNotEquals(a, b)
    assertEquals(a, ids.of("lovart-banners"))
    assertEquals(a, ids.release("lovart-banners"))
    assertFalse(ids.has("lovart-banners"))
    assertNull(ids.release("lovart-banners"))
    // Never the recordings' (4201-4203), the job service's (4301) or the summary's (4400).
    assertTrue(ids.of("model:gemma") in NoticeIds.FIRST..NoticeIds.LAST)
  }

  @Test
  fun what_the_app_no_longer_says_goes_and_two_or_more_have_a_summary() {
    assertEquals(listOf("b"), noticesGone(listOf("a", "b", "c"), listOf("a", "c", "d")))
    assertEquals(emptyList<String>(), noticesGone(emptyList(), listOf("a")))
    assertNull(summaryTitle(0))
    assertNull(summaryTitle(1))
    assertEquals("2 jobs running", summaryTitle(2))
  }
}
