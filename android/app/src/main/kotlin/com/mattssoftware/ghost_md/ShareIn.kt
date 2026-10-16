package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/**
 * Something shared into Ghost.md from another app's share sheet (the manifest's SEND and SEND_MULTIPLE filters, for
 * text, links, pictures and any file): the phone's half of `ghost_md/share` (lib/share/share_in.dart), in the pattern
 * of AppLinks.kt.
 *
 * A share that starts the app arrives before any Dart is listening, so each one WAITS HERE UNTIL ASKED FOR, in the
 * process, as a link does:
 *
 * - `take` -> every share made ready since the last ask, oldest first, each as JSON:
 *   `{id, text?, subject?, title?, mime, items: [{kind, path, name, mime, size}], unread}`. Kept no longer.
 * - `arrived` (said TO Dart) each time another is ready while the app runs.
 * - `done` -> null: the sheet is finished with, and the person goes back to the app they shared from (the task is
 *   put behind it, as a share target in its own task is left; nothing is closed).
 *
 * What is shared is READ AT ONCE, off the main thread, while the sharing app's grant on its addresses holds: a
 * picture is shrunk and turned the right way up into `cacheDir/picked/` as the chooser's are (Pictures.kt), for the
 * core to adopt among the library's pictures (`kind: picture`); any other file is copied whole into
 * `cacheDir/shared/<uuid>/<its name>` (`kind: file`). `unread` counts what could not be read. Only then is the share
 * ready. Text, a subject and a page's title are carried as they came; nothing is fetched.
 *
 * An activity brought back from its saved state, or from the recents list, carries the intent it was first opened
 * with: that share was taken then, and is not kept again.
 */
class ShareIn(private val activity: Activity, private val pictures: Pictures) {
  private var channel: MethodChannel? = null

  fun register(messenger: BinaryMessenger) {
    channel = MethodChannel(messenger, CHANNEL).also {
      it.setMethodCallHandler { call, result ->
        when (call.method) {
          "take" -> result.success(take())
          "done" -> {
            activity.moveTaskToBack(true)
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
    }
  }

  /** The intent the activity was made with. `restored` is whether it came back from saved state. */
  fun onCreate(intent: Intent?, restored: Boolean) {
    if (restored || intent == null || intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
    keep(intent)
  }

  /** An intent to the running activity: kept, and Dart told once it is read. */
  fun onNewIntent(intent: Intent) {
    keep(intent)
  }

  private fun keep(intent: Intent) {
    if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return
    val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
    val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
    val title = intent.getStringExtra(Intent.EXTRA_TITLE)
    val mime = intent.type ?: ""
    val uris = streams(intent)
    if (text.isNullOrBlank() && uris.isEmpty()) return
    // The grant on the addresses is the activity's, so they are read now, on a thread of their own.
    Thread {
      val items = JSONArray()
      var unread = 0
      for (uri in uris) {
        val item = try {
          read(uri, mime)
        } catch (error: Throwable) {
          Log.w(TAG, "shared item not read", error)
          null
        }
        if (item == null) unread += 1 else items.put(item)
      }
      val share = JSONObject()
        .put("id", UUID.randomUUID().toString())
        .put("mime", mime)
        .put("items", items)
        .put("unread", unread)
      if (!text.isNullOrBlank()) share.put("text", text.take(LONGEST_TEXT))
      if (!subject.isNullOrBlank()) share.put("subject", subject.take(LONGEST_LINE))
      if (!title.isNullOrBlank()) share.put("title", title.take(LONGEST_LINE))
      synchronized(waiting) { waiting.add(share.toString()) }
      activity.runOnUiThread { channel?.invokeMethod("arrived", null) }
    }.start()
  }

  /** The addresses a share carries: EXTRA_STREAM, one or a list, and its clip's, each once. */
  private fun streams(intent: Intent): List<Uri> {
    val found = LinkedHashSet<Uri>()
    if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
      val list = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java) else @Suppress("DEPRECATION") intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
      list?.let { found.addAll(it) }
    } else {
      val one = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java) else @Suppress("DEPRECATION") intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
      one?.let { found.add(it) }
    }
    val clip = intent.clipData
    if (clip != null) for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { found.add(it) }
    return found.take(MOST_ITEMS)
  }

  /** One address, read: a picture shrunk among the picked, anything else copied whole. */
  private fun read(uri: Uri, shared: String): JSONObject? {
    val resolver = activity.contentResolver
    val type = resolver.getType(uri) ?: shared
    val (name, size) = described(uri)
    if (type.startsWith("image/") && !type.contains("gif") && !type.contains("svg")) {
      try {
        val file = pictures.shrink(uri)
        return JSONObject().put("kind", "picture").put("path", file.absolutePath).put("name", name).put("mime", "image/jpeg").put("size", file.length())
      } catch (error: Throwable) {
        // A picture Android cannot draw (a RAW, a HEIC on an older phone) is kept as the file it is.
        Log.w(TAG, "shared picture not drawn, kept as a file", error)
      }
    }
    val dir = File(activity.cacheDir, "shared/${UUID.randomUUID()}").apply { mkdirs() }
    val out = File(dir, name.replace('/', '_').ifBlank { "Shared file" })
    resolver.openInputStream(uri)?.use { input -> FileOutputStream(out).use { input.copyTo(it, 256 * 1024) } } ?: return null
    return JSONObject().put("kind", "file").put("path", out.absolutePath).put("name", out.name).put("mime", type).put("size", if (size > 0) size else out.length())
  }

  private fun described(uri: Uri): Pair<String, Long> =
    try {
      activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) (cursor.getString(0) ?: fallbackName(uri)) to (if (cursor.isNull(1)) 0L else cursor.getLong(1)) else null
      } ?: (fallbackName(uri) to 0L)
    } catch (error: Exception) {
      fallbackName(uri) to 0L
    }

  private fun fallbackName(uri: Uri) = uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() } ?: "Shared file"

  private fun take(): List<String> = synchronized(waiting) { ArrayList(waiting).also { waiting.clear() } }

  companion object {
    const val CHANNEL = "ghost_md/share"
    private const val TAG = "GhostShareIn"

    /** A share's words, cut here: a whole book pasted is still a note, not a phone out of memory. */
    private const val LONGEST_TEXT = 2_000_000
    private const val LONGEST_LINE = 1_000
    private const val MOST_ITEMS = 100

    /** The shares read and not yet taken, for the life of the process. */
    private val waiting = ArrayList<String>()
  }
}
