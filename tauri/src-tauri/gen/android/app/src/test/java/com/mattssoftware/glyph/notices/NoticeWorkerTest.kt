package com.mattssoftware.glyph.notices

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the closed app's worker makes of a feed row (NoticeWorker): the sentence the bell reads it as, whether it is
 * one the phone posts, where tapping it goes, and when the session it reads with needs refreshing.
 */
class NoticeWorkerTest {
  private fun row(kind: String, extra: String = "") =
    JSONObject("""{ "id": "n1", "rev": 3, "kind": "$kind", "at": 1, "readAt": null, "hidden": false, "from": "sam", "org": { "id": "org1", "name": "Ghost" }, "body": { "name": "Ghost" } $extra }""")

  private val watch = JSONObject("""{ "team": true, "claude": true, "mutedOrgs": [] }""")

  @Test
  fun words_a_row_as_the_bell_does() {
    assertEquals("sam invited you to Ghost", NoticeWorker.sentence(row("invite")))
    assertEquals("sam joined Ghost", NoticeWorker.sentence(row("member-joined")))
    assertEquals("sam made you an admin of Ghost", NoticeWorker.sentence(JSONObject(row("role-changed").toString()).put("body", JSONObject("""{ "name": "Ghost", "role": "admin" }"""))))
    assertEquals("sam removed kim from Ghost", NoticeWorker.sentence(row("member-removed").put("body", JSONObject("""{ "name": "Ghost", "handle": "kim" }"""))))
    assertEquals("sam removed you from Ghost", NoticeWorker.sentence(row("member-removed")))
    assertEquals("sam renamed Old to Ghost", NoticeWorker.sentence(row("org-renamed").put("body", JSONObject("""{ "name": "Ghost", "was": "Old" }"""))))
    // An account that is gone, and a row whose organization the reader can no longer see.
    assertEquals("Someone left Lost", NoticeWorker.sentence(row("member-left").put("from", JSONObject.NULL).put("body", JSONObject("""{ "name": "Lost" }""")).apply { remove("org") }))
    // A name that is JSON null is no name: never the word "null".
    assertEquals("sam joined an organization", NoticeWorker.sentence(row("member-joined").put("org", JSONObject("""{ "id": "org1", "name": null }""")).put("body", JSONObject("""{ "name": null }"""))))
    // Claude's rows are sealed: worded by their kind alone.
    assertEquals("Claude edited a note", NoticeWorker.sentence(row("note-edited")))
    assertEquals("Claude added a rule", NoticeWorker.sentence(row("rule-added")))
  }

  @Test
  fun posts_what_the_bell_counts_and_nothing_else() {
    assertTrue(NoticeWorker.wanted(row("member-joined"), watch))
    assertTrue(NoticeWorker.wanted(row("note-edited"), watch))
    assertTrue(NoticeWorker.wanted(row("invite", """, "state": "pending" """), watch))
    assertFalse("an invitation answered", NoticeWorker.wanted(row("invite", """, "state": "accepted" """), watch))
    assertFalse("read", NoticeWorker.wanted(row("member-joined").put("readAt", 5), watch))
    assertFalse("hidden", NoticeWorker.wanted(row("member-joined").put("hidden", true), watch))
    assertFalse("a meeting has its own", NoticeWorker.wanted(row("summary-written"), watch))
    assertFalse("this device's own", NoticeWorker.wanted(row("sync-conflict"), watch))
    assertFalse("team news off", NoticeWorker.wanted(row("member-joined"), JSONObject(watch.toString()).put("team", false)))
    assertFalse("Claude off", NoticeWorker.wanted(row("note-edited"), JSONObject(watch.toString()).put("claude", false)))
    assertFalse("muted", NoticeWorker.wanted(row("member-joined"), JSONObject(watch.toString()).put("mutedOrgs", JSONArray(listOf("org1")))))
    assertTrue("an invitation is never muted", NoticeWorker.wanted(row("invite"), JSONObject(watch.toString()).put("mutedOrgs", JSONArray(listOf("org1")))))
  }

  @Test
  fun opens_the_organization_while_it_is_yours_and_the_drawer_otherwise() {
    assertEquals("ghostmd://org/org1", NoticeWorker.linkOf(row("member-joined")))
    assertEquals("ghostmd://notifications", NoticeWorker.linkOf(row("invite")))
    assertEquals("ghostmd://notifications", NoticeWorker.linkOf(row("org-deleted")))
    assertEquals("ghostmd://notifications", NoticeWorker.linkOf(row("member-removed")))
    assertEquals("ghostmd://org/org1", NoticeWorker.linkOf(row("member-removed").put("body", JSONObject("""{ "handle": "kim" }"""))))
    assertEquals("ghostmd://notifications", NoticeWorker.linkOf(row("note-edited")))
  }

  @Test
  fun refreshes_a_session_with_under_two_days_left() {
    fun token(exp: Long): String {
      val payload = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString("""{"sub":1,"handle":"matt","iat":0,"exp":$exp}""".toByteArray())
      return "eyJhbGciOiJFUzI1NiJ9.$payload.sig"
    }
    val now = 1_000_000L
    val twoDays = 2 * 24 * 3600L
    assertFalse(NoticeWorker.expiresWithin(token(now + 6 * 24 * 3600), twoDays, now))
    assertTrue(NoticeWorker.expiresWithin(token(now + 3600), twoDays, now))
    assertTrue("one that will not read", NoticeWorker.expiresWithin("not.a.token!", twoDays, now))
    assertEquals("hello?", String(NoticeWorker.base64Url("aGVsbG8_")))
  }
}
