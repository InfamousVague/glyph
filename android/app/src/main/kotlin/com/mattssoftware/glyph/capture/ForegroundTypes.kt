package com.mattssoftware.glyph.capture

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/**
 * Which foreground service types this build may pass, read from its own merged manifest, never assumed.
 *
 * Google Play's build (GHOST_STORE=play; android/app/src/play/AndroidManifest.xml; docs/store/play/forms.md,
 * "Foreground service permissions") keeps one type: `microphone` on MeetingService while a meeting the person started
 * records. Since 2026-11-11 (Play's second look: the write-up "can be deferred") it removes mediaProcessing too, so
 * the write-up their Stop starts is ordinary WorkManager work on every Android version. It removes
 * FOREGROUND_SERVICE_MEDIA_PROCESSING, FOREGROUND_SERVICE_SPECIAL_USE and FOREGROUND_SERVICE_MEDIA_PROJECTION, the job service (BackgroundJobs.kt) and
 * WorkManager's foreground service's types. The sideload APK keeps everything. A type passed to startForeground that
 * the manifest does not declare throws, so every caller asks here first:
 *
 * - [recordingTypes]: microphone, with mediaProjection beside it only where declared (other apps' sound).
 * - [writeUpType]: mediaProcessing on Android 15+, specialUse on 14 only where declared; null is "no foreground
 *   write-up here" (Play on Android 14: the write-up is left to WorkManager's ordinary work).
 * - [workerType]: what RecordingWorker's setForegroundAsync may carry; null is "never foreground" (Play).
 * - [jobServiceDeclared]: whether BackgroundJobService exists at all (Play: no; long jobs run while the app is open).
 *
 * The decisions are pure functions of (SDK level, declared bits) so ForegroundTypesTest pins them on the JVM.
 */
object ForegroundTypes {
  private const val TAG = "GlyphFgsTypes"

  /** No type: below Android 10 types are not asked for, and startForeground(id, notification) is the call. */
  const val UNTYPED = 0

  private const val MEETING_SERVICE = "com.mattssoftware.glyph.capture.MeetingService"
  private const val JOB_SERVICE = "com.mattssoftware.ghost_md.BackgroundJobService"
  private const val WORK_SERVICE = "androidx.work.impl.foreground.SystemForegroundService"

  @Volatile private var permissions: Set<String>? = null
  private val serviceTypes = HashMap<String, Int?>()

  /** Whether the merged manifest asks for [permission]. */
  fun declares(context: Context, permission: String): Boolean {
    val known = permissions ?: try {
      val pm = context.packageManager
      val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        pm.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
      } else {
        @Suppress("DEPRECATION")
        pm.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
      }
      (info.requestedPermissions?.toSet() ?: emptySet()).also { permissions = it }
    } catch (error: Exception) {
      Log.w(TAG, "the manifest's permissions could not be read", error)
      emptySet()
    }
    return permission in known
  }

  /**
   * The `foregroundServiceType` bits [className] is declared with; [UNTYPED] below Android 10 (not readable, not
   * asked for) or with none; null when this build does not declare the service at all.
   */
  fun declaredTypes(context: Context, className: String): Int? = synchronized(serviceTypes) {
    if (serviceTypes.containsKey(className)) return serviceTypes[className]
    val types: Int? = try {
      val pm = context.packageManager
      val component = ComponentName(context.packageName, className)
      val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        pm.getServiceInfo(component, PackageManager.ComponentInfoFlags.of(0L))
      } else {
        @Suppress("DEPRECATION")
        pm.getServiceInfo(component, 0)
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info.foregroundServiceType else UNTYPED
    } catch (_: PackageManager.NameNotFoundException) {
      null
    }
    serviceTypes[className] = types
    types
  }

  /** Whether the long-jobs service is in this build (the sideload APK: yes; Google Play's: no). */
  fun jobServiceDeclared(context: Context): Boolean = declaredTypes(context, JOB_SERVICE) != null

  /** Whether this build may record other apps' sound (mediaProjection declared on MeetingService and as a permission). */
  fun otherAppsAllowed(context: Context): Boolean =
    declares(context, "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION") &&
      hasBit(declaredTypes(context, MEETING_SERVICE), MEDIA_PROJECTION, Build.VERSION.SDK_INT)

  fun recordingTypes(context: Context, projection: Boolean): Int? =
    recordingTypes(Build.VERSION.SDK_INT, declaredTypes(context, MEETING_SERVICE), projection)

  fun writeUpType(context: Context): Int? = writeUpType(Build.VERSION.SDK_INT, declaredTypes(context, MEETING_SERVICE))

  fun workerType(context: Context): Int? =
    workerType(Build.VERSION.SDK_INT, declaredTypes(context, WORK_SERVICE), declares(context, "android.permission.FOREGROUND_SERVICE_SPECIAL_USE"))

  // ---- the decisions, pure ---------------------------------------------------------------------------------------

  // ServiceInfo's values, spelt out so the JVM tests need no Android stubs.
  internal const val MICROPHONE = 128
  internal const val MEDIA_PROJECTION = 32
  internal const val SPECIAL_USE = 1 shl 30
  internal const val MEDIA_PROCESSING = 1 shl 13

  private const val Q = 29
  private const val R = 30
  private const val U = 34
  private const val V = 35

  /** Below Android 10 nothing is declared readably, and nothing is checked: every bit counts as there. */
  internal fun hasBit(declared: Int?, bit: Int, sdk: Int): Boolean = declared != null && (sdk < Q || declared and bit != 0)

  /**
   * The recording's types: microphone (from Android 11; 10 had no such type, the untyped call), with
   * mediaProjection beside it when other apps' sound is wanted and declared. Null where [projection] was asked and
   * cannot be had (the caller then records the microphone alone).
   */
  internal fun recordingTypes(sdk: Int, declared: Int?, projection: Boolean): Int? {
    if (projection) {
      if (sdk < Q || !hasBit(declared, MEDIA_PROJECTION, sdk)) return null
      return if (sdk >= R) MICROPHONE or MEDIA_PROJECTION else MEDIA_PROJECTION
    }
    return if (sdk >= R) MICROPHONE else UNTYPED
  }

  /**
   * The write-up's type: mediaProcessing from Android 15, specialUse on 14 where declared, untyped below 14 (as
   * always). Null: no foreground write-up in this build on this phone (Google Play's on Android 14).
   */
  internal fun writeUpType(sdk: Int, declared: Int?): Int? = when {
    sdk >= V -> if (hasBit(declared, MEDIA_PROCESSING, sdk)) MEDIA_PROCESSING else null
    sdk >= U -> if (hasBit(declared, SPECIAL_USE, sdk)) SPECIAL_USE else null
    // Below 14 the call is untyped, but a build that declares neither write-up type (Google Play's since 2026-11-11,
    // after Play called the write-up deferrable) never keeps the write-up in the foreground: it is ordinary work.
    sdk >= Q && declared != null && declared and (MEDIA_PROCESSING or SPECIAL_USE) == 0 -> null
    else -> UNTYPED
  }

  /**
   * RecordingWorker's foreground type, from what WorkManager's SystemForegroundService is declared with: the same
   * rule as [writeUpType] from Android 14; below that, where types are not asked for, only a build that asks for
   * special use (the sideload APK, untyped as always) is ever foreground, never Google Play's.
   */
  internal fun workerType(sdk: Int, declared: Int?, specialUseDeclared: Boolean): Int? = when {
    declared == null -> null
    sdk >= U -> writeUpType(sdk, declared)
    else -> if (specialUseDeclared) UNTYPED else null
  }
}
