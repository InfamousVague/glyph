package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * A new version of the app, handed to Android's installer (lib/core/updates.dart, the phone's half of
 * `ghost_md/updates`). What `GlyphHost.installApk` did for the web app (../glyph's MainActivity.kt), and the two
 * things its page asked Rust: which app this is, and where a download is kept.
 *
 * - `installed` -> `{version, versionCode, dir}`: the app as the package manager has it, and `<cacheDir>/updates`,
 *   the one directory a file is ever handed to the installer from (`UPDATES` in ../glyph's paths.rs).
 * - `install {path}` -> "started" when Android's own screen was asked for, "permission" when the person must first
 *   let this app install apps (their page for exactly that is opened; pressing Install again afterwards carries
 *   on), or a reason.
 *
 * NOTHING HERE DECIDES WHETHER A FILE IS AN UPDATE. Dart downloads it and the Rust core checks it against a
 * description a trusted key signed (native/src/kept/updates.rs) before this is asked; what this holds is the door:
 * only a `.apk` that is directly inside the updates directory is ever given to the installer, whatever path
 * arrives. And Android holds the last rule itself: an APK signed by another certificate than the installed app's
 * is refused on its own screen.
 *
 * The installer's confirmation screen is the one step no app can skip. The file reaches it through this app's
 * FileProvider (`<applicationId>.updates`, res/xml/ghost_update_paths.xml), which exposes that one directory and
 * grants the read for this one intent.
 */
class UpdateInstaller(private val activity: Activity) {
  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "installed" -> result.success(installed())
        "install" -> result.success(install(call.argument<String>("path") ?: ""))
        else -> result.notImplemented()
      }
    }
  }

  private fun updatesDir(): File = File(activity.cacheDir, "updates")

  private fun installed(): Map<String, Any> {
    val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
    val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else {
      @Suppress("DEPRECATION")
      info.versionCode.toLong()
    }
    return mapOf("version" to (info.versionName ?: ""), "versionCode" to code, "dir" to updatesDir().absolutePath)
  }

  private fun install(path: String): String {
    val updates = updatesDir().canonicalFile
    val apk = File(path).canonicalFile
    if (apk.parentFile != updates || !apk.name.endsWith(".apk") || !apk.isFile) return "not an update"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
      return try {
        activity.startActivity(
          Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        "permission"
      } catch (error: Exception) {
        Log.w(TAG, "the install permission's page did not open", error)
        error.javaClass.simpleName
      }
    }
    return try {
      val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
      val intent = Intent(Intent.ACTION_VIEW)
        .setDataAndType(uri, "application/vnd.android.package-archive")
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
      activity.startActivity(intent)
      "started"
    } catch (error: Exception) {
      Log.w(TAG, "the installer did not start", error)
      error.javaClass.simpleName
    }
  }

  companion object {
    const val CHANNEL = "ghost_md/updates"
    private const val TAG = "GhostUpdates"
  }
}
