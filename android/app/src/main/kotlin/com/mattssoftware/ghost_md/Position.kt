package com.mattssoftware.ghost_md

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Where the phone is, and whether Ghost.md may know (lib/core/phone_position.dart, the phone's half of
 * `ghost_md/location`). Ported from the Tauri app's `location/LocationAccess.kt`, whose page asked the WebView for the
 * position itself; here there is no WebView, so the fix is this file's too.
 *
 * - `access` -> "granted" (a precise fix), "approximate" (coarse only), "ask" (never asked, or may be asked
 *   again), or "blocked".
 * - `request` -> raises Android's prompt and answers the state as it stands once the prompt is answered.
 * - `fix {maxAgeMs, timeoutMs}` -> `{lat, lon, accuracy, at}`, or an error whose code is "refused" (no permission
 *   held), "timeout" or "unavailable" (location is off for the phone, or no provider answered).
 * - `openSettings` -> true when the app's own page in the phone's settings opened.
 *
 * "Blocked" is decided from the prompt's answer itself (`answered`): a denial after which Android will not show the
 * dialog again. A dialog dismissed without an answer, or an "Only this time" grant that has lapsed, is not a
 * denial, and leaves the state at "ask".
 *
 * THE FIX IS THE PLATFORM'S OWN `LocationManager`, since the app links no Play services: a last known position no
 * older than `maxAgeMs` is taken as it is (a person does not move far in two minutes), else every provider that is
 * on is asked at once (the fused one from Android 12, the network's, and the satellites' with the precise
 * permission) and the first to answer is the fix. Nothing here asks unless Dart does, and Dart asks only from a
 * press, or for a new note with tagging on (lib/core/place_tags.dart).
 */
class Position(private val activity: Activity) {
  private val main = Handler(Looper.getMainLooper())
  private var asking: MethodChannel.Result? = null

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "access" -> result.success(state())
        "request" -> request(result)
        "fix" -> fix(call.argument<Number>("maxAgeMs")?.toLong() ?: 120_000L, call.argument<Number>("timeoutMs")?.toLong() ?: 15_000L, result)
        "openSettings" -> result.success(openSettings())
        else -> result.notImplemented()
      }
    }
  }

  private fun prefs() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  private fun held(permission: String): Boolean = activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

  /** "granted", "approximate", "ask" or "blocked", as the phone stands now. */
  fun state(): String {
    val answer = when {
      held(Manifest.permission.ACCESS_FINE_LOCATION) -> "granted"
      held(Manifest.permission.ACCESS_COARSE_LOCATION) -> "approximate"
      prefs().getBoolean(KEY_BLOCKED, false) &&
        !activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION) -> "blocked"
      else -> "ask"
    }
    // Allowed in the phone's settings since: no longer blocked.
    if (answer == "granted" || answer == "approximate") prefs().edit().remove(KEY_BLOCKED).apply()
    return answer
  }

  /** Raises the prompt; the answer arrives in the activity's onRequestPermissionsResult under REQUEST (`answered`). */
  private fun request(result: MethodChannel.Result) {
    // One prompt at a time: a second ask while the first is up is answered with the first.
    asking?.success(state())
    asking = result
    try {
      activity.requestPermissions(PERMISSIONS, REQUEST)
    } catch (error: Exception) {
      Log.w(TAG, "the prompt could not be raised", error)
      asking = null
      result.success(state())
    }
  }

  /**
   * The prompt's answer. A denial after which Android will not ask again (the second, or one turned off in
   * Settings) is "blocked"; a grant, or a dialog dismissed without an answer (empty results), is not. Answers
   * whether the request was this one.
   */
  fun answered(requestCode: Int, grantResults: IntArray): Boolean {
    if (requestCode != REQUEST) return false
    val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
    val denied = grantResults.isNotEmpty() && !granted
    val blocked = denied && !activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION)
    prefs().edit().putBoolean(KEY_BLOCKED, blocked).apply()
    asking?.success(state())
    asking = null
    return true
  }

  /** The providers that are on and that the permission held may ask, the fused one first. */
  private fun providers(manager: LocationManager): List<String> {
    val fine = held(Manifest.permission.ACCESS_FINE_LOCATION)
    val wanted = mutableListOf<String>()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) wanted.add(LocationManager.FUSED_PROVIDER)
    wanted.add(LocationManager.NETWORK_PROVIDER)
    // The satellites answer a coarse permission only from Android 12; before it they want the precise one.
    if (fine || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) wanted.add(LocationManager.GPS_PROVIDER)
    return wanted.filter { name ->
      try {
        manager.allProviders.contains(name) && manager.isProviderEnabled(name)
      } catch (error: Exception) {
        false
      }
    }
  }

  private fun answerOf(location: Location): Map<String, Any> = mapOf(
    "lat" to location.latitude,
    "lon" to location.longitude,
    "accuracy" to (if (location.hasAccuracy()) location.accuracy.toDouble() else 0.0),
    "at" to location.time,
  )

  private fun fix(maxAgeMs: Long, timeoutMs: Long, result: MethodChannel.Result) {
    if (!held(Manifest.permission.ACCESS_FINE_LOCATION) && !held(Manifest.permission.ACCESS_COARSE_LOCATION)) {
      result.error("refused", "Location is not allowed.", null)
      return
    }
    val manager = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
    val names = manager?.let { providers(it) } ?: emptyList()
    if (manager == null || names.isEmpty()) {
      result.error("unavailable", "Location is off for this phone.", null)
      return
    }
    try {
      // A position this recent is taken as it is.
      val recent = names.mapNotNull { manager.getLastKnownLocation(it) }
        .filter { (SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos) / 1_000_000L <= maxAgeMs }
        .maxByOrNull { it.elapsedRealtimeNanos }
      if (recent != null) {
        result.success(answerOf(recent))
        return
      }
      var done = false
      val stops = mutableListOf<() -> Unit>()
      fun finish(location: Location?) {
        if (done) return
        done = true
        stops.forEach { stop -> try { stop() } catch (error: Exception) { /* already let go */ } }
        if (location != null) result.success(answerOf(location)) else result.error("timeout", "No position came in time.", null)
      }
      main.postDelayed({ finish(null) }, timeoutMs)
      for (name in names) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
          val cancel = CancellationSignal()
          stops.add { cancel.cancel() }
          // A provider with nothing to say answers null: the others, or the clock, decide.
          manager.getCurrentLocation(name, cancel, activity.mainExecutor) { location -> if (location != null) finish(location) }
        } else {
          val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) = finish(location)
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
          }
          stops.add { manager.removeUpdates(listener) }
          @Suppress("DEPRECATION")
          manager.requestSingleUpdate(name, listener, Looper.getMainLooper())
        }
      }
    } catch (error: SecurityException) {
      result.error("refused", "Location is not allowed.", null)
    } catch (error: Exception) {
      Log.w(TAG, "no position", error)
      result.error("unavailable", error.message ?: "No position.", null)
    }
  }

  /** Opens the app's own page in the phone's settings, where a blocked location is allowed again. */
  private fun openSettings(): Boolean = try {
    activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
    true
  } catch (error: ActivityNotFoundException) {
    false
  }

  companion object {
    const val CHANNEL = "ghost_md/location"
    private const val TAG = "GhostPosition"

    /** The request code the activity answers under: the Tauri app's own for location. */
    const val REQUEST = 4105
    private const val PREFS = "glyph_location"
    private const val KEY_BLOCKED = "blocked"
    private val PERMISSIONS = arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
  }
}
