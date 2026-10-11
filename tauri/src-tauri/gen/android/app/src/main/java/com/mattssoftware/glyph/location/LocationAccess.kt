package com.mattssoftware.glyph.location

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Looper
import android.provider.Settings
import android.webkit.GeolocationPermissions
import android.webkit.WebView
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Whether Ghost.md may know where the phone is, and the ask (core/location.ts on the page; native generation 20).
 *
 * The page's own `getCurrentPosition` would raise Android's prompt through the generated RustWebChromeClient, and the
 * manifest now declares the permission that client asks for. But that client lets a position through silently only
 * when both FINE and COARSE are held, and otherwise launches its one shared permission launcher, whose listener the
 * microphone's prompt also uses and a second prompt overwrites: after an "Approximate" answer it would raise a second
 * dialog ("change to precise?") on every launch, over a locked phone too. So the page asks here, through the
 * activity's own request code, and once the app holds either permission the WebView is told the page's origin may
 * have a position (`GeolocationPermissions.allow`), so the chrome client's prompt is never reached. When neither is
 * held any more, that is taken back.
 *
 * What the WebView cannot tell the page either is why a fix did not come: a permission denied twice, or turned off
 * for the app in Settings, is refused by Android with no dialog at all, and the page would ask again into silence.
 * So this answers "blocked" for that case, which the page turns into "Open settings". "Blocked" is decided from the
 * answer itself (`answered`): a denial after which Android will not show the dialog again. A dialog dismissed without
 * an answer, or an "Only this time" grant that has lapsed, is not a denial, and leaves the state at "ask".
 */
object LocationAccess {
  /**
   * The request code the activity answers in onRequestPermissionsResult: 4101 is update alerts' notifications, 4102 a
   * picked picture, and 4103 and 4104 the meetings' notifications and microphone.
   */
  const val REQUEST = 4105
  private const val PREFS = "glyph_location"
  private const val KEY_BLOCKED = "blocked"
  /** Where the page runs (the OTA page too), as the WebView keys its geolocation grants. */
  private const val PAGE_ORIGIN = "http://tauri.localhost"
  private val PERMISSIONS = arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

  private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  private fun held(context: Context, permission: String): Boolean =
    context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

  /**
   * "granted" (a precise fix), "approximate" (coarse only), "ask" (never asked, or may be asked again), or "blocked".
   * Read by the page before every fix, so the WebView's grant for the page is brought in line here too.
   */
  fun state(activity: Activity): String {
    val answer = when {
      held(activity, Manifest.permission.ACCESS_FINE_LOCATION) -> "granted"
      held(activity, Manifest.permission.ACCESS_COARSE_LOCATION) -> "approximate"
      prefs(activity).getBoolean(KEY_BLOCKED, false) &&
        !activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION) -> "blocked"
      else -> "ask"
    }
    // Allowed in the phone's settings since: no longer blocked.
    if (answer == "granted" || answer == "approximate") prefs(activity).edit().remove(KEY_BLOCKED).apply()
    allowPage(activity, answer == "granted" || answer == "approximate")
    return answer
  }

  /** Raises the prompt; the answer arrives in the activity's onRequestPermissionsResult under REQUEST (`answered`). */
  fun request(activity: Activity) {
    activity.requestPermissions(PERMISSIONS, REQUEST)
  }

  /**
   * The prompt's answer. A denial after which Android will not ask again (the second, or one turned off in Settings) is
   * "blocked"; a grant, or a dialog dismissed without an answer (empty results), is not. Then the page reads the state
   * again. Answers whether the request was this one.
   */
  fun answered(activity: Activity, requestCode: Int, grantResults: IntArray, webView: WebView?): Boolean {
    if (requestCode != REQUEST) return false
    val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
    val denied = grantResults.isNotEmpty() && !granted
    val blocked = denied && !activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION)
    prefs(activity).edit().putBoolean(KEY_BLOCKED, blocked).apply()
    webView?.let { wv ->
      activity.runOnUiThread { wv.evaluateJavascript("window.__glyph && window.__glyph.location && window.__glyph.location()", null) }
    }
    return true
  }

  /**
   * Tells the WebView the page may (or may no longer) have a position, on the main thread, and waits for it: the page
   * asks for its fix straight after reading the state, and the grant must be in place before the WebView looks.
   */
  private fun allowPage(activity: Activity, allowed: Boolean) {
    val apply = {
      val grants = GeolocationPermissions.getInstance()
      if (allowed) grants.allow(PAGE_ORIGIN) else grants.clear(PAGE_ORIGIN)
    }
    if (Looper.myLooper() == Looper.getMainLooper()) {
      apply()
      return
    }
    val done = CountDownLatch(1)
    activity.runOnUiThread {
      try {
        apply()
      } finally {
        done.countDown()
      }
    }
    done.await(2, TimeUnit.SECONDS)
  }

  /**
   * Opens the app's own page in the phone's settings, where a blocked location is allowed again; false if nothing took
   * it. Started on the main thread with the bridge thread waiting for the answer, as openAssistantSettings does.
   */
  fun openSettings(activity: Activity): Boolean {
    val opened = AtomicBoolean(false)
    val done = CountDownLatch(1)
    activity.runOnUiThread {
      try {
        activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
        opened.set(true)
      } catch (error: ActivityNotFoundException) {
        opened.set(false)
      } finally {
        done.countDown()
      }
    }
    return done.await(2, TimeUnit.SECONDS) && opened.get()
  }
}
