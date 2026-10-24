package com.mattssoftware.ghost_md

import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Links that open the app: `ghostmd://join/<code>`, `ghostmd://fork#<id>.<key>`, `ghostmd://note/<id>`,
 * `ghostmd://notifications`, `ghostmd://org/<id>` (the manifest's intent filter takes the whole scheme). The phone's
 * half of `ghost_md/links` (lib/core/phone_links.dart), and what `src-tauri/src/links.rs` with the deep-link plugin
 * and the activity's own `pendingLink` were to the Tauri app.
 *
 * A link that starts the app arrives before any Dart is listening, so each one WAITS HERE UNTIL ASKED FOR:
 *
 * - `take` -> every link kept since the last ask, oldest first, and kept no longer. A link opens the app's copy of
 *   it once, however often it is asked.
 * - `arrived` (said TO Dart, with nothing) each time another is kept while the app runs, so it asks again.
 *
 * What a link means is the app's to decide (lib/share/app_links.dart `readAppLink`): here it is only kept, as text.
 * Only the app's own scheme is kept, and nothing longer than an invitation or a share's id and key could be.
 *
 * The links wait in the PROCESS, not in the activity: an activity made again inside a live process (the app swiped
 * away during a write-up, then its notification tapped) hands its link to the same list, which is the gap the Tauri
 * activity's second road (`GlyphHost.takeLink`) closed. An activity brought back from its saved state, or from the
 * recents list, carries the intent it was first opened with: that link was followed then, and is not kept again.
 *
 * EVERY LINK COMES IN BY THE DOOR (LinkDoor.kt, since 2026-10-24): an activity of its own keeps the link here with
 * [hold] and opens the activity with a plain launch carrying `ghost_md.link_waiting`, so the app's task is never made
 * with a link, and a task Android brings back after an update (Matt: "when i restart the app after an update the
 * notifications always opens") has nothing in it to follow again. The activity's part ([onCreate], [onNewIntent];
 * LinkHandoff.arrival says which): the waiting extra at onNewIntent is Dart told; a link handed to the activity itself,
 * as all were before the door (a notification the version before posted, a pinned shortcut), is kept and followed
 * once, as then.
 */
class AppLinks {
  private var channel: MethodChannel? = null

  fun register(messenger: BinaryMessenger) {
    channel = MethodChannel(messenger, CHANNEL).also {
      it.setMethodCallHandler { call, result ->
        when (call.method) {
          "take" -> result.success(take())
          else -> result.notImplemented()
        }
      }
    }
  }

  /**
   * The intent the activity was made with. `restored` is whether it came back from saved state. The door's launch
   * needs nothing here: its link is in the list already, and Dart takes the list as it starts.
   */
  fun onCreate(intent: Intent?, restored: Boolean) {
    if (intent == null) return
    val arrival = arrivalOf(intent, restored)
    if (arrival is LinkHandoff.Arrival.Legacy) hold(arrival.link)
  }

  /** An intent to the running activity: the door's word that a link is waiting, or a link of its own, kept. Dart told. */
  fun onNewIntent(intent: Intent) {
    when (val arrival = arrivalOf(intent, restored = false)) {
      LinkHandoff.Arrival.None -> return
      LinkHandoff.Arrival.Waiting -> Unit
      is LinkHandoff.Arrival.Legacy -> hold(arrival.link)
    }
    channel?.invokeMethod("arrived", null)
  }

  private fun arrivalOf(intent: Intent, restored: Boolean): LinkHandoff.Arrival = LinkHandoff.arrival(
    intent.action,
    intent.getBooleanExtra(LinkHandoff.EXTRA_WAITING, false),
    intent.data?.scheme,
    intent.dataString,
    intent.flags,
    restored,
  )

  private fun take(): List<String> = synchronized(waiting) { ArrayList(waiting).also { waiting.clear() } }

  companion object {
    const val CHANNEL = "ghost_md/links"

    /** Longer than any link the app makes: an invitation's code is 22 letters, a share's id and key 108 at most. */
    private const val LONGEST = 512

    /** The links not yet taken, for the life of the process. */
    private val waiting = ArrayList<String>()

    /** A link kept until Dart asks: the door's (LinkDoor.kt), or one handed to the activity itself. */
    fun hold(link: String) {
      synchronized(waiting) { waiting.add(link) }
    }

    /** The link an intent carries, as text, when it is one of the app's own and no longer than one could be. */
    internal fun linkOf(scheme: String?, text: String?): String? {
      if (scheme?.lowercase() != "ghostmd" || text == null) return null
      return text.takeIf { it.length <= LONGEST }
    }
  }
}
