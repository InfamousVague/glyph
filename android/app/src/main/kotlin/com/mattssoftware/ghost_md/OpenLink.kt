package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * An address handed to the phone: its browser, its mail, its dialler, its maps (lib/core/open_link.dart, the
 * phone's half of `ghost_md/open`). What Tauri's opener plugin did for the web app's `openLink`, held to the rule
 * its capability file gave it (`opener:default`, and `geo:*` for a tapped map).
 *
 * - `open {url}` -> true when an app took the address, false when nothing on the phone opens such a one or the
 *   address is not one the phone is handed.
 *
 * THE RULE IS KEPT HERE AS WELL AS IN DART. Dart refuses everything but `http`, `https`, `mailto`, `tel` and `geo`
 * before it asks (`canOpenLink`); this checks again, since an `ACTION_VIEW` is started with whatever arrives and a
 * channel is a door anything in the app can knock on: never `javascript:`, `file:`, `content:` or `intent:`, never
 * an address with a space or a control character in it, and a web address has a host.
 *
 * The intent is a plain `ACTION_VIEW` with `FLAG_ACTIVITY_NEW_TASK`, so the page opens in the browser's own task
 * and Back from it comes home. No chooser and no package named: the phone's default for the address is the
 * person's choice. Nothing is asked of the package manager first (Android 11 hides other apps from it unless the
 * manifest lists what it looks for): the start itself says whether anything took it.
 */
class OpenLink(private val activity: Activity) {
  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "open" -> result.success(open(call.argument<String>("url") ?: ""))
        else -> result.notImplemented()
      }
    }
  }

  /** Starts the phone's app for `url`; false for an address that may not be handed over, or that nothing opens. */
  fun open(url: String): Boolean {
    val address = allowed(url) ?: return false
    return try {
      activity.startActivity(Intent(Intent.ACTION_VIEW, address).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      true
    } catch (error: ActivityNotFoundException) {
      false
    } catch (error: Exception) {
      // A phone whose policy refuses the start (a work profile, a locked-down launcher): quietly, as none.
      Log.w(TAG, "the address was not opened", error)
      false
    }
  }

  companion object {
    const val CHANNEL = "ghost_md/open"
    private const val TAG = "GhostOpenLink"

    /** The schemes the phone is handed (`openableSchemes`). */
    private val SCHEMES = setOf("http", "https", "mailto", "tel", "geo")

    /** `url` as an address the phone may be handed, or null (`canOpenLink`, line for line). */
    internal fun allowed(url: String): Uri? {
      if (url.isEmpty() || url.any { it.code <= 0x20 || it.code == 0x7f }) return null
      val uri = try {
        Uri.parse(url)
      } catch (error: Exception) {
        return null
      }
      val scheme = uri.scheme?.lowercase() ?: return null
      if (scheme !in SCHEMES) return null
      if (scheme == "http" || scheme == "https") return if (uri.host.isNullOrEmpty()) null else uri
      // `mailto:`, `tel:` and `geo:` say something after the colon.
      return if (url.length > scheme.length + 1) uri else null
    }
  }
}
