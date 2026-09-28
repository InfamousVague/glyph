package com.mattssoftware.glyph.location

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings

/**
 * Whether Ghost.md may know where the phone is, and the ask (core/location.ts on the page; native generation 20).
 *
 * The page's own `getCurrentPosition` already raises Android's prompt through the generated RustWebChromeClient,
 * and the manifest now declares the permission that client asks for. What the WebView cannot tell the page is why
 * a fix did not come: a permission denied twice, or turned off for the app in Settings, is refused by Android with
 * no dialog at all, and the page would ask again into silence. So this answers "blocked" for that case, which the
 * page turns into "Open settings", and asks ahead of any fix through the activity's own request code rather than
 * the chrome client's one shared launcher (which the microphone's prompt also uses, and whose listener a second
 * prompt overwrites). Both permissions are asked so Android 12+ can offer Approximate; either is enough.
 *
 * "Asked before" is a SharedPreferences flag, the UpdateAlerts shape: `shouldShowRequestPermissionRationale` is
 * false both before the first ask and after the final refusal, and only the flag tells the two apart.
 */
object LocationAccess {
  /**
   * The request code the activity answers in onRequestPermissionsResult: 4101 is update alerts' notifications, 4102 a
   * picked picture, and 4103 and 4104 the meetings' notifications and microphone.
   */
  const val REQUEST = 4105
  private const val PREFS = "glyph_location"
  private const val KEY_ASKED = "asked"
  private val PERMISSIONS = arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

  private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  private fun held(context: Context, permission: String): Boolean =
    context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

  /** "granted" (a precise fix), "approximate" (coarse only), "ask" (never asked, or may be asked again), or "blocked". */
  fun state(activity: Activity): String = when {
    held(activity, Manifest.permission.ACCESS_FINE_LOCATION) -> "granted"
    held(activity, Manifest.permission.ACCESS_COARSE_LOCATION) -> "approximate"
    prefs(activity).getBoolean(KEY_ASKED, false) &&
      !activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION) -> "blocked"
    else -> "ask"
  }

  /** Raises the prompt; the answer arrives in the activity's onRequestPermissionsResult under REQUEST. */
  fun request(activity: Activity) {
    prefs(activity).edit().putBoolean(KEY_ASKED, true).apply()
    activity.requestPermissions(PERMISSIONS, REQUEST)
  }

  /** Opens the app's own page in the phone's settings, where a blocked location is allowed again; false if nothing took it. */
  fun openSettings(activity: Activity): Boolean = try {
    activity.startActivity(
      Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
    true
  } catch (error: ActivityNotFoundException) {
    false
  }
}
