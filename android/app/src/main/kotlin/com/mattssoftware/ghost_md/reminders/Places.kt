package com.mattssoftware.ghost_md.reminders

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.lang.ref.WeakReference

/**
 * Place reminders (docs/INTEGRATIONS.md §3; lib/reminders/place_*.dart): the phone's half of `ghost_md/places`
 * (lib/reminders/place_host.dart), a geofence for each open to-do with a `📍`, and the notification arriving rings
 * with.
 *
 * - `set [{id, lat, lon, radius, title, text, place, noteId, line, words}]`: the app's whole set (at most a hundred,
 *   the nearest: Play services' own limit for an app), kept here (SharedPreferences, so a restart and an update can
 *   register it again with the app closed: ReminderRestart) and registered; what was registered before is let go.
 * - `clear`: none.
 * - `access` -> "always", "whileUsing", "whileOpen", "approximate", "ask" or "blocked".
 * - `askForeground`, `askBackground` -> the access once Android's prompt is answered: the precise location while in
 *   use, then "Allow all the time" (a page of the phone's settings from Android 11). The app says why before the
 *   second (lib/reminders/place_access.dart).
 * - `lastKnown` -> `{lat, lon}` or null, for the nearest hundred.
 * - `openSettings` -> true when the app's own page in the phone's settings opened.
 *
 * **The geofences are Google Play services'** (GeofencingClient), 150 m around each place, ENTER only, never
 * expiring, and no ring for a place the phone is already in when they are registered: the set is registered again
 * after every change to it, and a to-do written at the shop must not ring at once. They need the precise location
 * all the time (ACCESS_BACKGROUND_LOCATION from Android 10); without it the set is kept and registered once it is
 * allowed. Play services drops them after a restart and when the app is updated (ReminderRestart registers them again),
 * and when location is turned off for the phone (the next set from the app, as it comes back to the front).
 *
 * **Google Play's build has no "all the time"** (android/app/src/play/AndroidManifest.xml takes
 * ACCESS_BACKGROUND_LOCATION out; docs/store/play/README.md). Without it in the manifest no geofence registers, so the
 * access is "whileOpen", nothing asks for "Allow all the time", and the places are watched only while the app is in
 * front ([resumed], [paused]): the fused location every minute or so, at Play services' balanced power, and a place
 * rings as the phone comes inside it, the way a geofence's ENTER does. What was inside at the last look is kept, so
 * opening the app on arriving rings, and a place first seen with the phone already in it (a to-do written at the shop)
 * does not.
 *
 * **What rings** is a reminder's notification (Reminders.kt): on the "Reminders" channel, "Buy diapers — you're at
 * Target" over the note's title, a tap opening the note at the to-do and Done ticking it (GhostBackground.kt). No
 * Snooze: an hour from now the phone may be anywhere. Its Done lets that to-do's geofence go at once, before the app
 * has read the tick and handed over a set without it.
 */
object Places {
  const val CHANNEL = "ghost_md/places"
  private const val TAG = "GhostPlaces"
  private const val PREFS = "ghost_places"
  private const val KEY_PLAN = "plan"
  private const val KEY_BLOCKED = "blocked"
  private const val KEY_INSIDE = "inside"
  private const val KEY_SEEN = "seen"
  private const val MOST = 100

  /** The prefix a place's notification is known by among the reminders' (Reminders.find). */
  const val PREFIX = "place~"

  /** The request codes the activity answers under. */
  const val REQUEST_FOREGROUND = 4120
  const val REQUEST_BACKGROUND = 4121

  /** The activity, for the prompts; never held past it. */
  private var activity: WeakReference<Activity>? = null

  /** The prompt being answered, and the call waiting for it. */
  private var asking: MethodChannel.Result? = null

  private val main = Handler(Looper.getMainLooper())

  /** Whether the manifest asks for the location all the time: not in Google Play's build. Read once. */
  @Volatile private var declared: Boolean? = null

  /** Whether the app is in front (MainActivity's onResume to onPause). */
  private var front = false

  /** The in-front watch's callback while the app is in front and watching ([look]). */
  private var watch: LocationCallback? = null

  private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  // ---- the channel -------------------------------------------------------------------------------------------------

  fun register(context: Context, owner: Activity, messenger: BinaryMessenger) {
    val app = context.applicationContext
    activity = WeakReference(owner)
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "set" -> {
          val taken = try {
            keep(app, (call.arguments as? List<*>) ?: emptyList<Any?>())
            arm(app)
            if (front) look(app)
            true
          } catch (error: Throwable) {
            Log.w(TAG, "the places were not taken", error)
            false
          }
          result.success(taken)
        }
        "clear" -> {
          prefs(app).edit().putString(KEY_PLAN, "[]").commit()
          arm(app)
          result.success(true)
        }
        "access" -> result.success(access(app))
        "askForeground" -> ask(app, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), REQUEST_FOREGROUND, result)
        "askBackground" -> {
          // Before Android 10 the precise location is all the time already; without it there is nothing to widen,
          // and a build whose manifest has no ACCESS_BACKGROUND_LOCATION (Google Play's) never asks for it.
          if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !held(app, Manifest.permission.ACCESS_FINE_LOCATION) || !backgroundDeclared(app)) {
            result.success(access(app))
          } else {
            ask(app, arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), REQUEST_BACKGROUND, result)
          }
        }
        "lastKnown" -> lastKnown(app, result)
        "openSettings" -> result.success(openSettings(app))
        else -> result.notImplemented()
      }
    }
  }

  /** The engine is going with its activity [owner]. */
  fun released(owner: Activity) {
    if (activity?.get() !== owner) return
    activity = null
    asking = null
  }

  // ---- what is kept ------------------------------------------------------------------------------------------------

  /** One open to-do with a place, as the app made it. */
  data class Item(val id: String, val lat: Double, val lon: Double, val radius: Float, val title: String, val text: String, val place: String, val note: String, val line: Int, val words: String) {
    fun json(): JSONObject = JSONObject()
      .put("id", id).put("lat", lat).put("lon", lon).put("radius", radius.toDouble()).put("title", title).put("text", text)
      .put("place", place).put("noteId", note).put("line", line).put("words", words)

    /** The notification it rings with, as a reminder's (Reminders.kt). */
    fun reminder(): Reminders.Item = Reminders.Item("$PREFIX$id", Reminders.writtenOf(System.currentTimeMillis()), note, line, words, title, text, true)

    companion object {
      fun of(json: JSONObject): Item? {
        val id = json.optString("id")
        val note = json.optString("noteId")
        val lat = json.optDouble("lat", Double.NaN)
        val lon = json.optDouble("lon", Double.NaN)
        // A request id Play services takes: at most a hundred characters.
        if (id.isEmpty() || id.length > 90 || note.isEmpty() || lat.isNaN() || lon.isNaN() || lat < -90 || lat > 90 || lon < -180 || lon > 180) return null
        val radius = json.optDouble("radius", 150.0).toFloat().coerceIn(50f, 5000f)
        return Item(id, lat, lon, radius, json.optString("title"), json.optString("text"), json.optString("place"), note, json.optInt("line"), json.optString("words"))
      }

      fun of(map: Map<*, *>): Item? = of(JSONObject(map.mapKeys { it.key.toString() }))
    }
  }

  /** The set as it came over the channel, kept. */
  @Synchronized
  private fun keep(context: Context, list: List<*>) {
    val array = JSONArray()
    list.mapNotNull { (it as? Map<*, *>)?.let(Item::of) }.take(MOST).forEach { array.put(it.json()) }
    prefs(context).edit().putString(KEY_PLAN, array.toString()).commit()
  }

  fun held(context: Context): List<Item> = try {
    val array = JSONArray(prefs(context).getString(KEY_PLAN, "[]"))
    (0 until array.length()).mapNotNull { Item.of(array.getJSONObject(it)) }
  } catch (_: Throwable) {
    emptyList()
  }

  /** The reminder a place's notification is known by ([PREFIX] and the geofence's id), or null. */
  fun reminderOf(context: Context, id: String): Reminders.Item? {
    if (!id.startsWith(PREFIX)) return null
    val place = id.removePrefix(PREFIX)
    return held(context).firstOrNull { it.id == place }?.reminder()
  }

  /** A to-do ticked outside the app: its geofence let go at once. */
  @Synchronized
  fun forget(context: Context, note: String, words: String) {
    val items = held(context)
    val kept = items.filter { !(it.note == note && it.words == words) }
    if (kept.size == items.size) return
    val array = JSONArray()
    kept.forEach { array.put(it.json()) }
    prefs(context).edit().putString(KEY_PLAN, array.toString()).commit()
    arm(context)
  }

  // ---- the geofences -----------------------------------------------------------------------------------------------

  private fun fenceIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
    context,
    0,
    Intent(context, PlaceAlarms::class.java).setAction(ACTION_ARRIVED),
    // Mutable: Play services writes which geofence was crossed into it.
    PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0),
  )

  const val ACTION_ARRIVED = "com.mattssoftware.ghost_md.reminders.ARRIVED"

  /** Whether a geofence can be registered: the precise location, all the time. */
  fun canWatch(context: Context): Boolean =
    held(context, Manifest.permission.ACCESS_FINE_LOCATION) &&
      (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || held(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION))

  /**
   * Everything held registered again: what was registered let go first, then the set, where the phone allows it.
   * [done] hears the end, whichever way it went (ReminderRestart waits for it).
   */
  fun arm(context: Context, done: (() -> Unit)? = null) {
    val app = context.applicationContext
    val client = LocationServices.getGeofencingClient(app)
    val pending = fenceIntent(app)
    val items = held(app)
    fun add() {
      if (items.isEmpty() || !canWatch(app)) {
        done?.invoke()
        return
      }
      val fences = items.map {
        Geofence.Builder()
          .setRequestId(it.id)
          .setCircularRegion(it.lat, it.lon, it.radius)
          .setExpirationDuration(Geofence.NEVER_EXPIRE)
          .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
          .build()
      }
      // No initial trigger: a place the phone is in already does not ring as it is registered.
      val request = GeofencingRequest.Builder().setInitialTrigger(0).addGeofences(fences).build()
      try {
        client.addGeofences(request, pending).addOnCompleteListener { task ->
          if (!task.isSuccessful) Log.w(TAG, "the geofences were not registered", task.exception)
          done?.invoke()
        }
      } catch (error: SecurityException) {
        Log.w(TAG, "the location the geofences need is not allowed", error)
        done?.invoke()
      }
    }
    try {
      client.removeGeofences(pending).addOnCompleteListener { add() }
    } catch (error: Throwable) {
      Log.w(TAG, "the geofences were not let go", error)
      add()
    }
  }

  /** Arrived at one or more of the places held: each rings. */
  fun arrived(context: Context, ids: List<String>) {
    val items = held(context)
    for (id in ids) {
      val item = items.firstOrNull { it.id == id } ?: continue
      Reminders.ringPlace(context, item.reminder())
    }
  }

  // ---- in front only: Google Play's build ------------------------------------------------------------------------

  /** Whether this build's manifest asks for ACCESS_BACKGROUND_LOCATION (the sideload APK does, Google Play's not). */
  fun backgroundDeclared(context: Context): Boolean {
    declared?.let { return it }
    val asked = try {
      @Suppress("DEPRECATION")
      context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions
        ?.contains(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == true
    } catch (error: Throwable) {
      Log.w(TAG, "the manifest's permissions were not read", error)
      true
    }
    declared = asked
    return asked
  }

  /** Whether the places are watched in front instead of by geofences: no "all the time" in this build. */
  private fun watchesInFront(context: Context): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !backgroundDeclared(context)

  /** The app came to the front (MainActivity.onResume): the places are watched, where this build watches in front. */
  fun resumed(context: Context) {
    front = true
    look(context)
  }

  /** The app left the front (MainActivity.onPause): the watch stops, and nothing is watched until it is back. */
  fun paused(context: Context) {
    front = false
    stop(context)
  }

  /** Watching as things stand, in front: started where there are places and the precise location, else stopped. */
  private fun look(context: Context) {
    val app = context.applicationContext
    if (!front || !watchesInFront(app) || !held(app, Manifest.permission.ACCESS_FINE_LOCATION) || held(app).isEmpty()) {
      stop(app)
      return
    }
    if (watch != null) return
    val callback = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        result.lastLocation?.let { looked(app, it) }
      }
    }
    val request = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 60_000L).setMinUpdateIntervalMillis(30_000L).build()
    try {
      LocationServices.getFusedLocationProviderClient(app).requestLocationUpdates(request, callback, Looper.getMainLooper())
      watch = callback
    } catch (error: SecurityException) {
      Log.w(TAG, "the location to watch the places is not allowed", error)
    }
  }

  private fun stop(context: Context) {
    val callback = watch ?: return
    watch = null
    try {
      LocationServices.getFusedLocationProviderClient(context.applicationContext).removeLocationUpdates(callback)
    } catch (error: Throwable) {
      Log.w(TAG, "the watch was not stopped", error)
    }
  }

  /** A look at where the phone is, in front: each place it has come inside since the last look rings. */
  @Synchronized
  private fun looked(context: Context, location: Location) {
    // A fix too rough to tell a place's 150 m from the next street is not a look.
    if (location.hasAccuracy() && location.accuracy > 500f) return
    val items = held(context)
    val prefs = prefs(context)
    val seen = prefs.getStringSet(KEY_SEEN, emptySet())!!.toMutableSet()
    val inside = prefs.getStringSet(KEY_INSIDE, emptySet())!!.toMutableSet()
    val ids = items.map { it.id }.toSet()
    seen.retainAll(ids)
    inside.retainAll(ids)
    val distance = FloatArray(1)
    for (item in items) {
      Location.distanceBetween(location.latitude, location.longitude, item.lat, item.lon, distance)
      val now = distance[0] <= item.radius
      val first = seen.add(item.id)
      if (!now) {
        inside.remove(item.id)
      } else if (inside.add(item.id) && !first) {
        Reminders.ringPlace(context, item.reminder())
      }
    }
    prefs.edit().putStringSet(KEY_SEEN, seen).putStringSet(KEY_INSIDE, inside).apply()
  }

  // ---- the permission ----------------------------------------------------------------------------------------------

  private fun held(context: Context, permission: String): Boolean = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

  /** "always", "whileUsing", "approximate", "ask" or "blocked", as the phone stands now. */
  fun access(context: Context): String {
    if (held(context, Manifest.permission.ACCESS_FINE_LOCATION)) {
      prefs(context).edit().remove(KEY_BLOCKED).apply()
      return if (canWatch(context)) "always" else if (watchesInFront(context)) "whileOpen" else "whileUsing"
    }
    if (held(context, Manifest.permission.ACCESS_COARSE_LOCATION)) return "approximate"
    val from = activity?.get()
    val blocked = prefs(context).getBoolean(KEY_BLOCKED, false) && from != null && !from.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION)
    return if (blocked) "blocked" else "ask"
  }

  private fun ask(context: Context, permissions: Array<String>, code: Int, result: MethodChannel.Result) {
    val from = activity?.get()
    if (from == null) {
      result.success(access(context))
      return
    }
    // One prompt at a time: a second ask while the first is up is answered as things stand.
    asking?.success(access(context))
    asking = result
    try {
      from.requestPermissions(permissions, code)
    } catch (error: Exception) {
      Log.w(TAG, "the prompt could not be raised", error)
      asking = null
      result.success(access(context))
    }
  }

  /**
   * A prompt's answer, from the activity's onRequestPermissionsResult. A denial of the location while in use after
   * which Android will not ask again is "blocked". The geofences are registered again, since they may be allowed now.
   * Answers whether the request was one of these.
   */
  fun answered(context: Context, requestCode: Int, grantResults: IntArray): Boolean {
    if (requestCode != REQUEST_FOREGROUND && requestCode != REQUEST_BACKGROUND) return false
    if (requestCode == REQUEST_FOREGROUND) {
      val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
      val denied = grantResults.isNotEmpty() && !granted
      val from = activity?.get()
      val blocked = denied && from != null && !from.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION)
      prefs(context).edit().putBoolean(KEY_BLOCKED, blocked).apply()
    }
    asking?.success(access(context))
    asking = null
    arm(context)
    look(context)
    return true
  }

  // ---- where the phone was -----------------------------------------------------------------------------------------

  private fun lastKnown(context: Context, result: MethodChannel.Result) {
    if (!held(context, Manifest.permission.ACCESS_FINE_LOCATION) && !held(context, Manifest.permission.ACCESS_COARSE_LOCATION)) {
      result.success(null)
      return
    }
    var answered = false
    fun answer(value: Any?) {
      if (answered) return
      answered = true
      result.success(value)
    }
    try {
      LocationServices.getFusedLocationProviderClient(context).lastLocation.addOnCompleteListener { task ->
        val location = if (task.isSuccessful) task.result else null
        answer(if (location == null) null else mapOf("lat" to location.latitude, "lon" to location.longitude))
      }
      // Play services that never answers: the nearest hundred as the notes have them.
      main.postDelayed({ answer(null) }, 5_000)
    } catch (error: SecurityException) {
      answer(null)
    }
  }

  private fun openSettings(context: Context): Boolean {
    val from = activity?.get() ?: return false
    return try {
      from.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
      true
    } catch (error: ActivityNotFoundException) {
      false
    }
  }
}

/**
 * A geofence crossed (Places.kt): Play services' own broadcast, through this app's own PendingIntent. Not exported.
 * Only an arrival rings; an error (location turned off for the phone, which takes the geofences with it) is said in
 * the log, and the app registers them again the next time it hands the set over.
 */
class PlaceAlarms : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val event = GeofencingEvent.fromIntent(intent) ?: return
    if (event.hasError()) {
      Log.w("GhostPlaces", "a geofence said error ${event.errorCode}")
      return
    }
    if (event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return
    val ids = event.triggeringGeofences?.map { it.requestId } ?: return
    Places.arrived(context.applicationContext, ids)
  }
}
