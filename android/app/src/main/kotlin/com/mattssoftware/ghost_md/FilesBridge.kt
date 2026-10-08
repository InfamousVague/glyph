package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.Intent
import com.mattssoftware.glyph.files.LibraryTree
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * The system's own pickers, for Dart (`ghost_md/files`): what the Tauri activity's `GlyphHost` and its
 * `window.__glyph` answers were for a folder of the person's (files/LibraryTree.kt; lib/core/library_folder.dart).
 *
 * - `chooseLibraryFolder` -> the picker's answer as JSON, when it answers: `{uri, name}` for a folder granted (the
 *   grant kept across restarts), `{cancelled: true}` for a picker closed, `{error}` in the app's words.
 *
 * ONE CALL, ANSWERED LATER, where the Tauri activity answered "started" at once and said the rest as an event on
 * its page: a method channel's result can wait, so the call that opens a picker is the call its answer comes back
 * on, and there is no event to miss. A picker asked for while one of its kind is still open answers the first
 * `{cancelled: true}`, so no call is ever left unanswered by this side; an activity destroyed under an open picker
 * takes its engine and the waiting Dart with it.
 *
 * Nothing here reads or writes a file: Rust does, through LibraryTree's static methods (native: saf.rs).
 */
class FilesBridge(private val activity: Activity) {
  /** The calls waiting on a picker, by the picker's kind. */
  private val waiting = HashMap<String, MethodChannel.Result>()

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "chooseLibraryFolder" -> asked(FOLDER, result) { LibraryTree.start(activity, tell(FOLDER)) }
        else -> result.notImplemented()
      }
    }
  }

  /** A picker's answer, from the activity. Answers whether the result was one of this bridge's. */
  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (LibraryTree.answered(activity, requestCode, resultCode, data, tell(FOLDER))) return true
    return false
  }

  /** Keeps `result` for `kind`'s answer and starts its picker; a start that says anything but "started" is the answer. */
  private fun asked(kind: String, result: MethodChannel.Result, start: () -> String) {
    waiting.remove(kind)?.success(CANCELLED)
    waiting[kind] = result
    val started = start()
    if (started != "started") tell(kind)(if (started.startsWith("{")) started else JSONObject().put("error", started).toString())
  }

  /** What a picker of `kind` says, handed to the call that waits for it, on the main thread. */
  private fun tell(kind: String): (String) -> Unit = { json ->
    activity.runOnUiThread { waiting.remove(kind)?.success(json) }
  }

  companion object {
    const val CHANNEL = "ghost_md/files"
    private const val FOLDER = "libraryFolder"
    private val CANCELLED = JSONObject().put("cancelled", true).toString()
  }
}
