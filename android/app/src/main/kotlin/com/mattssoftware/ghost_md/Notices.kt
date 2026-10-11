package com.mattssoftware.ghost_md

import android.content.Context
import android.util.Log
import com.mattssoftware.glyph.notices.NoticeAlerts
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The bell's rows as the phone's own notifications, as the app asks for them: the phone's half of `ghost_md/notices`
 * (lib/core/phone_notices.dart), and what `GlyphHost.watchNotices`, `postNotice` and `noticesState` were to the Tauri
 * app's page (tauri/src-tauri/gen/android/…/MainActivity.kt), method for method, with the same words answered.
 * What is watched, posted and said is NoticeAlerts' and NoticeWorker's (glyph/notices), ported line for line.
 *
 * - `watch {json}` -> "off" | "on" | "blocked". The session and switches the worker needs while the app is closed
 *   (`{ api, token, accountId, cursor, team, claude, mutedOrgs }`), or "" to stop watching: signed out, or the
 *   switch turned off.
 * - `post {json}` -> "posted" | "seen" | "blocked" | a reason. One row, from the app while it runs in the background:
 *   `{ id, title, text?, link }`.
 * - `state` -> "off" | "on" | "blocked": whether anything is watched, and whether Android would show it (the
 *   permission, the app's switch and the channel, read now). This is the phone's real answer.
 * - `allow` -> "allowed" | "asked" | "blocked": Android asked to let the app notify, for Settings › Notifications'
 *   Allow (`GlyphHost.requestNotifications`, which the page's NotificationsPane calls). The one asking the activity
 *   has ([ask], MeetingBridge's `requestNotifications`, as it was the Tauri activity's one method for the meeting
 *   screen and this page alike), reached here so that the page needs nothing of the meeting's channel: it is there
 *   as soon as the engine is, whether or not Dart has made its recorder. The prompt's answer is read by `state`.
 *
 * The Tauri bridge answered on the WebView's own thread; a channel answers on the main one, so the two that write
 * (the preferences, WorkManager's queue, the notification) go through one thread of their own, in the order asked.
 */
class Notices(private val context: Context, private val ask: () -> String) {
  fun register(messenger: BinaryMessenger) {
    val main = android.os.Handler(android.os.Looper.getMainLooper())
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "watch" -> {
          val json = call.argument<String>("json") ?: ""
          door.execute {
            val state = watch(json)
            main.post { result.success(state) }
          }
        }
        "post" -> {
          val json = call.argument<String>("json") ?: ""
          door.execute {
            val answer = post(json)
            main.post { result.success(answer) }
          }
        }
        "state" -> result.success(NoticeAlerts.state(context))
        // On the main thread, as a channel answers: only an activity can raise the dialog.
        "allow" -> result.success(try { ask() } catch (error: Throwable) { "blocked" })
        else -> result.notImplemented()
      }
    }
  }

  private fun watch(json: String): String {
    try {
      if (json.isBlank()) NoticeAlerts.unwatch(context) else NoticeAlerts.watch(context, json)
    } catch (error: Throwable) {
      Log.w(TAG, "notices watch refused", error)
    }
    return NoticeAlerts.state(context)
  }

  private fun post(json: String): String = try {
    val notice = JSONObject(json)
    // `optString` reads a JSON null as "null": absent or null is no text.
    val text = if (notice.isNull("text")) null else notice.optString("text").ifEmpty { null }
    NoticeAlerts.post(context, notice.getString("id"), notice.getString("title"), text, notice.optString("link"))
  } catch (error: Throwable) {
    "could not read the notice"
  }

  companion object {
    const val CHANNEL = "ghost_md/notices"
    private const val TAG = "GhostNotices"

    /** The watch and the posts, one after the other in the order the app made them. */
    private val door: ExecutorService by lazy { Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "glyph-notices-door") } }
  }
}
