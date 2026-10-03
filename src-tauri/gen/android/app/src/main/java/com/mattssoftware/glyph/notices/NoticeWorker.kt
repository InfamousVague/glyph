package com.mattssoftware.glyph.notices

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.mattssoftware.glyph.MainActivity
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * One look at the notifications feed while the app is closed (NoticeAlerts.kt), and a phone notification for each new
 * row the person asked to see: unread, not hidden, its category's switch on and its organization not muted, as the
 * bell counts them (core/notifications/feed.ts `isWanted`). A meeting written up has its own notification already
 * (recordings/RecordingAlerts.kt), and a note kept twice is this device's business, so only team news, invitations
 * and Claude's changes come here.
 *
 * With the app in front it does nothing: the page is syncing and the bell is in view. A sealed row (Claude's) is
 * worded by its kind alone - "Claude edited a note" - since the account key never leaves the page.
 *
 * The session is the page's, handed over with the watch, and refreshed here when it has under two days left: a
 * refresh hands back a new week and leaves the old token good, so the page's own is never disturbed. A refused one
 * (401) ends the watch until the page hands a new session; anything else waits for the next run.
 */
class NoticeWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
  override fun doWork(): Result {
    val context = applicationContext
    if (MainActivity.isInFront()) return Result.success()
    val watch = NoticeAlerts.watched(context) ?: return Result.success()
    if (!NoticeAlerts.canNotify(context)) return Result.success()
    val api = watch.optString("api").trimEnd('/')
    try {
      var token = watch.optString("token")
      if (expiresWithin(token, REFRESH_WITHIN_SECS)) {
        val fresh = request("POST", "$api/v1/refresh", token)
        if (fresh.status == 401) return stopped(context)
        fresh.body?.optString("token")?.takeIf { it.isNotEmpty() }?.let {
          token = it
          NoticeAlerts.keepToken(context, it)
        }
      }
      var cursor = NoticeAlerts.cursor(context)
      for (page in 0 until MAX_PAGES) {
        val answer = request("GET", "$api/v1/notifications?since=$cursor&limit=100", token)
        if (answer.status == 401) return stopped(context)
        val body = answer.body ?: return Result.success()
        val items = body.optJSONArray("items")
        for (i in 0 until (items?.length() ?: 0)) {
          val item = items!!.optJSONObject(i) ?: continue
          if (!wanted(item, watch)) continue
          NoticeAlerts.post(context, item.optString("id"), sentence(item), item.optJSONObject("org")?.optString("name"), linkOf(item))
        }
        cursor = maxOf(cursor, body.optLong("rev", cursor))
        NoticeAlerts.keepCursor(context, cursor)
        if (!body.optBoolean("more")) break
      }
    } catch (error: Throwable) {
      Log.i(TAG, "notices look failed: ${error.message}")
    }
    return Result.success()
  }

  private fun stopped(context: Context): Result {
    Log.i(TAG, "session refused; waiting for the app to hand a new one")
    NoticeAlerts.unwatch(context)
    return Result.success()
  }

  private class Answer(val status: Int, val body: JSONObject?)

  private fun request(method: String, url: String, token: String): Answer {
    val connection = URL(url).openConnection() as HttpURLConnection
    return try {
      connection.requestMethod = method
      connection.connectTimeout = 15_000
      connection.readTimeout = 20_000
      connection.setRequestProperty("Authorization", "Bearer $token")
      connection.setRequestProperty("Accept", "application/json")
      if (method == "POST") {
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        connection.outputStream.use { it.write("{}".toByteArray()) }
      }
      val status = connection.responseCode
      val text = if (status in 200..299) connection.inputStream.bufferedReader().use { it.readText() } else null
      Answer(status, text?.let { JSONObject(it) })
    } finally {
      connection.disconnect()
    }
  }

  companion object {
    private const val TAG = "GlyphNotices"
    private const val REFRESH_WITHIN_SECS = 2 * 24 * 3600L
    /** Pages of a hundred rows one run reads at most: a phone off for a month does not read its whole year. */
    private const val MAX_PAGES = 5

    private val TEAM = setOf("invite-accepted", "invite-declined", "member-joined", "member-left", "member-removed", "role-changed", "org-renamed", "org-deleted")
    private val CLAUDE = setOf("note-created", "note-edited", "note-appended", "journal-entry", "rule-added")

    /**
     * Whether the token's `exp` is under `secs` away from `now` (unix seconds), read from its payload; true for one
     * that will not read, which a refresh then settles.
     */
    internal fun expiresWithin(token: String, secs: Long, now: Long = System.currentTimeMillis() / 1000): Boolean = try {
      val json = JSONObject(String(base64Url(token.split('.')[1]), Charsets.UTF_8))
      json.getLong("exp") - now < secs
    } catch (_: Throwable) {
      true
    }

    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    /**
     * Base64url without padding, decoded by hand: java.util.Base64 arrives at API 26 and the app runs from 24, and
     * android.util.Base64 is a stub in the JVM tests that read the token here.
     */
    internal fun base64Url(text: String): ByteArray {
      val out = java.io.ByteArrayOutputStream()
      var buffer = 0
      var bits = 0
      for (char in text.trimEnd('=')) {
        val value = ALPHABET.indexOf(char)
        require(value >= 0) { "not base64url" }
        buffer = (buffer shl 6) or value
        bits += 6
        if (bits >= 8) {
          bits -= 8
          out.write((buffer shr bits) and 0xff)
        }
      }
      return out.toByteArray()
    }

    /** As the bell counts it, from plaintext fields only, for the kinds that come to the phone. */
    internal fun wanted(item: JSONObject, watch: JSONObject): Boolean {
      if (!item.isNull("readAt") || item.optBoolean("hidden")) return false
      val kind = item.optString("kind")
      if (kind == "invite") return item.optString("state", "pending") == "pending"
      val on = when (kind) {
        in TEAM -> watch.optBoolean("team", true)
        in CLAUDE -> watch.optBoolean("claude", true)
        else -> false
      }
      if (!on) return false
      val org = item.optJSONObject("org")?.optString("id") ?: return true
      val muted = watch.optJSONArray("mutedOrgs") ?: return true
      return (0 until muted.length()).none { muted.optString(it) == org }
    }

    /** Where tapping it goes: an organization's dashboard while it is yours to read, else the notifications drawer. */
    internal fun linkOf(item: JSONObject): String {
      val org = item.optJSONObject("org")?.optString("id")
      val kind = item.optString("kind")
      val gone = kind == "org-deleted" || kind == "invite" || (kind == "member-removed" && !item.optJSONObject("body").let { it != null && it.has("handle") })
      return if (org.isNullOrEmpty() || gone || kind in CLAUDE) "ghostmd://notifications" else "ghostmd://org/$org"
    }

    /** The sentence the bell reads it as (core/notifications/kinds.ts `sentenceOf`), sealed rows by their kind alone. */
    internal fun sentence(item: JSONObject): String {
      val from = item.optString("from").takeIf { !item.isNull("from") && it.isNotEmpty() } ?: "Someone"
      val body = item.optJSONObject("body")
      val org = item.optJSONObject("org")?.optString("name")?.takeIf { it.isNotEmpty() }
        ?: body?.optString("name")?.takeIf { it.isNotEmpty() }
        ?: "an organization"
      return when (item.optString("kind")) {
        "invite" -> "$from invited you to $org"
        "invite-accepted" -> "$from accepted your invitation to $org"
        "invite-declined" -> "$from declined your invitation to $org"
        "member-joined" -> "$from joined $org"
        "member-left" -> "$from left $org"
        "member-removed" -> body?.optString("handle")?.takeIf { it.isNotEmpty() }?.let { "$from removed $it from $org" } ?: "$from removed you from $org"
        "role-changed" -> "$from made you ${when (body?.optString("role")) { "owner" -> "the owner"; "admin" -> "an admin"; else -> "a member" }} of $org"
        "org-renamed" -> "$from renamed ${body?.optString("was")?.takeIf { it.isNotEmpty() } ?: "an organization"} to $org"
        "org-deleted" -> "$from deleted $org"
        "note-created" -> "Claude created a note"
        "note-edited" -> "Claude edited a note"
        "note-appended" -> "Claude added to a note"
        "journal-entry" -> "Claude wrote a journal entry"
        "rule-added" -> "Claude added a rule"
        else -> "Something new in Ghost.md"
      }
    }
  }
}
