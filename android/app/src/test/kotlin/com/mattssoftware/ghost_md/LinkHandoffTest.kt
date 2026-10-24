package com.mattssoftware.ghost_md

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The door every `ghostmd://` link comes in by (LinkDoor.kt) and the activity's half (AppLinks.kt), as plain values
 * (LinkHandoff): what the door keeps, the launch it opens the activity with, and what the activity does with each
 * intent it is made with or handed. Matt, 2026-10-24: "when i restart the app after an update the notifications
 * always opens", which was a task made with the drawer's link, made again with it.
 */
class LinkHandoffTest {
  private val view = Intent.ACTION_VIEW
  private val main = Intent.ACTION_MAIN
  private val fromHistory = Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY or Intent.FLAG_ACTIVITY_NEW_TASK

  @Test
  fun the_door_keeps_the_apps_own_links() {
    assertEquals("ghostmd://notifications", LinkHandoff.handed(view, "ghostmd", "ghostmd://notifications", Intent.FLAG_ACTIVITY_NEW_TASK, restored = false))
    assertEquals("ghostmd://voice", LinkHandoff.handed(view, "ghostmd", "ghostmd://voice", 0, restored = false))
    assertEquals("ghostmd://note/abc?line=12", LinkHandoff.handed(view, "ghostmd", "ghostmd://note/abc?line=12", 0, restored = false))
    // The scheme as a browser may write it.
    assertEquals("GHOSTMD://new", LinkHandoff.handed(view, "GHOSTMD", "GHOSTMD://new", 0, restored = false))
  }

  @Test
  fun the_door_keeps_nothing_else() {
    // Another scheme, no address, longer than any link the app makes, not a VIEW.
    assertNull(LinkHandoff.handed(view, "https", "https://ghostmarkdown.com", 0, restored = false))
    assertNull(LinkHandoff.handed(view, null, null, 0, restored = false))
    assertNull(LinkHandoff.handed(view, "ghostmd", "ghostmd://note/" + "x".repeat(600), 0, restored = false))
    assertNull(LinkHandoff.handed(main, "ghostmd", "ghostmd://new", 0, restored = false))
    // A replay: brought back from saved state, or from the recents list.
    assertNull(LinkHandoff.handed(view, "ghostmd", "ghostmd://voice", 0, restored = true))
    assertNull(LinkHandoff.handed(view, "ghostmd", "ghostmd://voice", fromHistory, restored = false))
  }

  @Test
  fun the_door_opens_the_activity_as_the_launcher_does() {
    val kept = LinkHandoff.launch(waiting = true)
    assertEquals(Intent.ACTION_MAIN, kept.action)
    assertEquals(setOf(Intent.CATEGORY_LAUNCHER), kept.categories)
    assertEquals(Intent.FLAG_ACTIVITY_NEW_TASK, kept.flags)
    assertTrue(kept.waiting)
    // Nothing kept, the app opens all the same, with no word that a link waits.
    val none = LinkHandoff.launch(waiting = false)
    assertEquals(Intent.ACTION_MAIN, none.action)
    assertFalse(none.waiting)
    assertEquals("ghost_md.link_waiting", LinkHandoff.EXTRA_WAITING)
  }

  @Test
  fun the_activity_hears_the_door() {
    // Running: told, and Dart asks. Starting: Dart takes the list as it starts, which the same answer says.
    assertEquals(LinkHandoff.Arrival.Waiting, LinkHandoff.arrival(main, waiting = true, null, null, Intent.FLAG_ACTIVITY_NEW_TASK, restored = false))
  }

  @Test
  fun a_plain_launch_and_a_replay_of_one_are_nothing() {
    // The launcher's own launch.
    assertEquals(LinkHandoff.Arrival.None, LinkHandoff.arrival(main, waiting = false, null, null, 0x10200000, restored = false))
    // The task's own intent made again after an update: the door's launch, its link long since taken.
    assertEquals(LinkHandoff.Arrival.None, LinkHandoff.arrival(main, waiting = true, null, null, fromHistory, restored = false))
    assertEquals(LinkHandoff.Arrival.None, LinkHandoff.arrival(main, waiting = true, null, null, Intent.FLAG_ACTIVITY_NEW_TASK, restored = true))
    // Not a link of the app's.
    assertEquals(LinkHandoff.Arrival.None, LinkHandoff.arrival(view, waiting = false, "https", "https://ghostmarkdown.com", 0, restored = false))
    assertEquals(LinkHandoff.Arrival.None, LinkHandoff.arrival(Intent.ACTION_SEND, waiting = false, null, null, 0, restored = false))
  }

  @Test
  fun a_link_handed_to_the_activity_itself_is_followed_once_as_before() {
    // A notification the version before posted, a pinned shortcut not set again: still the activity's.
    assertEquals(LinkHandoff.Arrival.Legacy("ghostmd://notifications"), LinkHandoff.arrival(view, waiting = false, "ghostmd", "ghostmd://notifications", Intent.FLAG_ACTIVITY_NEW_TASK, restored = false))
    // And as before, not again when the activity is brought back with it.
    assertEquals(LinkHandoff.Arrival.None, LinkHandoff.arrival(view, waiting = false, "ghostmd", "ghostmd://notifications", 0, restored = true))
    assertEquals(LinkHandoff.Arrival.None, LinkHandoff.arrival(view, waiting = false, "ghostmd", "ghostmd://notifications", fromHistory, restored = false))
  }
}
