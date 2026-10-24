package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle

/**
 * THE DOOR EVERY `ghostmd://` LINK COMES IN BY (Matt, 2026-10-24, on the Fold: "when i restart the app after an
 * update the notifications always opens"). An activity nobody sees: it hands the link to the process's list
 * (AppLinks.kt), opens the app's one activity with a plain launch, and is gone, in the same moment.
 *
 * Why a door of its own: the link was the INTENT THE APP'S TASK WAS MADE WITH. A notification's tap that started the
 * app (`ghostmd://notifications`), a widget's ring (`ghostmd://voice`), a reminder's note: each became the task's
 * base intent, and stayed it. An update takes the process and the activity, and LEAVES THE TASK, with that intent,
 * in the recents list (seen on the emulator: the drawer's link kept by a task with no activity left in it, beside
 * the new one the launcher made). Made again from that intent by any way that does not say "from the recents list",
 * the activity has no saved state to tell AppLinks the link was followed already: the drawer opened again, or a
 * recording started that nobody asked for. The stock emulator (Android 16) brings such a task back only by the
 * recents list, flagged, which AppLinks has always skipped; whatever brought it back unflagged on the Fold is One
 * UI's own, and was not seen there. Rather than guess every way a phone maker brings a task back, the activity is never made with a link: the task's intent is
 * the launcher's own, and a launcher's intent replayed is just the app opening. (A side gain: that intent is the
 * launcher's, so Android lists one task of the app's in recents, where an update used to leave two.)
 *
 * - **What it keeps**: the link, as AppLinks always kept one (the app's own scheme, no longer than a link could be),
 *   and only from a VIEW that is not a replay itself ([LinkHandoff.handed]).
 * - **What it starts**: the activity, by ACTION_MAIN and CATEGORY_LAUNCHER in a task of its own (FLAG_ACTIVITY_NEW_TASK),
 *   carrying [LinkHandoff.EXTRA_WAITING] when a link was kept ([LinkHandoff.launch]). Running, the activity hears it at
 *   onNewIntent and tells Dart `arrived`; starting, Dart takes the list as it starts, as it always did.
 * - **Where it lives** (AndroidManifest.xml): no window (Theme.NoDisplay, so it finishes in onCreate), no place in the
 *   recents list, no history, and an affinity of none, so its moment is a task of its own that goes with it and
 *   never the app's. The `ghostmd` filter moved here from the activity.
 *
 * ANDROID'S RULES FOR A DOOR LIKE THIS (12 to 16): the trampolines Android 12 stopped are a service's or a receiver's,
 * started by a notification's tap, opening an activity; an activity the tap started may open another, as this does.
 * From Android 14 an activity started from the background needs its caller in front: this one is the top of the
 * focused task while its onCreate runs, which is what lets it (checked on the emulator, Android 16, from a
 * notification and a widget, the app cold and running: the system logs the door's start as allowed for a visible
 * window).
 */
class LinkDoor : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val link = LinkHandoff.handed(intent?.action, intent?.data?.scheme, intent?.dataString, intent?.flags ?: 0, restored = savedInstanceState != null)
    link?.let { AppLinks.hold(it) }
    val launch = LinkHandoff.launch(waiting = link != null)
    val open = Intent(this, MainActivity::class.java).setAction(launch.action).addFlags(launch.flags)
    launch.categories.forEach { open.addCategory(it) }
    if (launch.waiting) open.putExtra(LinkHandoff.EXTRA_WAITING, true)
    startActivity(open)
    finish()
    // No moment of its own on the glass: the app's opening is the only thing seen.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
    } else {
      @Suppress("DEPRECATION")
      overridePendingTransition(0, 0)
    }
  }
}

/**
 * The door's decisions and the activity's, as plain values so a test can hold them (LinkHandoffTest.kt): what the
 * door keeps, what it starts, and what the activity does with each intent it is made with or handed.
 */
object LinkHandoff {
  /** On the activity's launch from [LinkDoor]: a link was kept for Dart to take. */
  const val EXTRA_WAITING = "ghost_md.link_waiting"

  /**
   * The link [LinkDoor] keeps from its intent: a VIEW of the app's own scheme, no longer than a link could be
   * (AppLinks.linkOf), and not a replay (brought back from saved state, or from the recents list). Null keeps
   * nothing; the app opens all the same.
   */
  fun handed(action: String?, scheme: String?, text: String?, flags: Int, restored: Boolean): String? {
    if (restored || flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
    if (action != Intent.ACTION_VIEW) return null
    return AppLinks.linkOf(scheme, text)
  }

  /** The activity's launch, as the launcher's own: [waiting] when a link was kept. */
  data class Launch(val action: String, val categories: Set<String>, val flags: Int, val waiting: Boolean)

  fun launch(waiting: Boolean): Launch = Launch(Intent.ACTION_MAIN, setOf(Intent.CATEGORY_LAUNCHER), Intent.FLAG_ACTIVITY_NEW_TASK, waiting)

  /** What the activity does with an intent ([arrival]). */
  sealed interface Arrival {
    /** Nothing: a plain launch, a replay, or not a link. */
    data object None : Arrival

    /** The door kept a link: running, Dart is told `arrived`; starting, Dart takes the list as it starts. */
    data object Waiting : Arrival

    /**
     * A link handed to the activity itself, as every one was before the door: a notification posted by the version
     * before, a recent note's shortcut not yet set again, a pinned one. Kept, and followed once, as then.
     */
    data class Legacy(val link: String) : Arrival
  }

  /**
   * What the activity does with the intent it is made with ([restored] when from saved state), or one it is handed
   * at onNewIntent ([restored] false). A replay (saved state, or the recents list) is nothing, whatever it carries.
   */
  fun arrival(action: String?, waiting: Boolean, scheme: String?, text: String?, flags: Int, restored: Boolean): Arrival {
    if (restored || flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return Arrival.None
    if (waiting) return Arrival.Waiting
    if (action != Intent.ACTION_VIEW) return Arrival.None
    return AppLinks.linkOf(scheme, text)?.let { Arrival.Legacy(it) } ?: Arrival.None
  }
}
