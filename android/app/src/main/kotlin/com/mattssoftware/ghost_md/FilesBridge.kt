package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.Intent
import android.util.Log
import com.mattssoftware.glyph.files.BackupDrives
import com.mattssoftware.glyph.files.ExportTarget
import com.mattssoftware.glyph.files.ImportTree
import com.mattssoftware.glyph.files.LibraryTree
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * The system's own pickers, for Dart (`ghost_md/files`): what the Tauri activity's `GlyphHost` and its
 * `window.__glyph` answers were for a folder of the person's (files/LibraryTree.kt; lib/core/library_folder.dart)
 * for a removable drive to back up to (files/BackupDrives.kt; lib/core/backup.dart), and for where an export of
 * everything goes (files/ExportTarget.kt; lib/core/export_all.dart).
 *
 * - `chooseLibraryFolder` -> the picker's answer as JSON, when it answers: `{uri, name}` for a folder granted (the
 *   grant kept across restarts), `{cancelled: true}` for a picker closed, `{error}` in the app's words.
 * - `backupDrives` -> the removable drives plugged in now, as JSON: `[{id, name, tree?, free?, total?}]`, `tree`
 *   where the app may already write the drive. Asked every two seconds while Settings › Backup is open.
 * - `chooseBackupDrive {id}` -> the picker opened on that drive's root, for the person to allow it once:
 *   `{id, tree}`, `{cancelled: true}`, or `{error}` (a drive pulled out, or a folder on it chosen in its place).
 * - `chooseExport {name}` -> the system's picker making a zip of that name, a USB drive among its places: `{fd, name}`
 *   for the file made, opened for writing and its descriptor detached (the core's `export_fd` writes the archive
 *   into it and closes it), `{cancelled: true}`, or `{error}`.
 * - `exportDone` -> null: the export is whole, and the file stays. `discardExport` -> null: it failed or was
 *   stopped, and the half-written file goes, so the drive holds only an archive that opens.
 * - `canBrowseFiles` -> true: this activity can show the notes' folder (the page asked whether its `GlyphHost` had
 *   `browseFiles`). `browseFiles` -> null: the phone's Files app opened at the notes (LibraryFiles.kt, over
 *   files/LibraryDocuments.kt; lib/core/library_files.dart). Not a picker: nothing is answered later.
 * - `chooseImportFolder`, `chooseImportFiles`, `importList`, `importRead`, `importCopy`: what Settings › Import reads,
 *   a vault's folder or some Evernote exports, granted for the run only (files/ImportTree.kt says each).
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
        "backupDrives" -> result.success(
          try {
            BackupDrives.drives(activity)
          } catch (error: Exception) {
            Log.w(TAG, "backupDrives failed", error)
            "[]"
          },
        )
        "chooseExport" -> asked(EXPORT, result) { ExportTarget.start(activity, call.argument<String>("name") ?: "", tell(EXPORT)) }
        "exportDone" -> {
          ExportTarget.done()
          result.success(null)
        }
        "discardExport" -> {
          ExportTarget.discard(activity)
          result.success(null)
        }
        "chooseBackupDrive" -> asked(DRIVE, result) { BackupDrives.ask(activity, call.argument<String>("id") ?: "", tell(DRIVE)) }
        // Settings › Import (files/ImportTree.kt; lib/importer/import_sources.dart): a vault's folder or some
        // exports chosen, then walked, read and copied off the main thread.
        "chooseImportFolder" -> asked(IMPORT_FOLDER, result) { ImportTree.chooseFolder(activity, tell(IMPORT_FOLDER)) }
        "chooseImportFiles" -> asked(IMPORT_FILES, result) { ImportTree.chooseFiles(activity, tell(IMPORT_FILES)) }
        "importList" -> away(result) { ImportTree.list(activity, call.argument<String>("tree") ?: "") }
        "importRead" -> away(result) { ImportTree.read(activity, call.argument<String>("uri") ?: "") }
        "importCopy" -> away(result) {
          if (!ImportTree.copy(activity, call.argument<String>("uri") ?: "", call.argument<String>("to") ?: "")) throw IllegalStateException("That file could not be copied.")
          null
        }
        "canBrowseFiles" -> result.success(true)
        "browseFiles" -> {
          LibraryFiles.browse(activity)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  /** A picker's answer, from the activity. Answers whether the result was one of this bridge's. */
  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (LibraryTree.answered(activity, requestCode, resultCode, data, tell(FOLDER))) return true
    if (BackupDrives.answered(activity, requestCode, resultCode, data, tell(DRIVE))) return true
    if (ExportTarget.answered(activity, requestCode, resultCode, data, tell(EXPORT))) return true
    if (ImportTree.answered(activity, requestCode, resultCode, data, tell(IMPORT_FOLDER), tell(IMPORT_FILES))) return true
    return false
  }

  /** `work` off the main thread, its answer (or its failure, as the error's words) back on it. */
  private fun away(result: MethodChannel.Result, work: () -> Any?) {
    Thread {
      try {
        val answer = work()
        activity.runOnUiThread { result.success(answer) }
      } catch (error: Exception) {
        activity.runOnUiThread { result.error("failed", error.message ?: "That did not work.", null) }
      }
    }.start()
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
    private const val TAG = "GhostFiles"
    private const val FOLDER = "libraryFolder"
    private const val DRIVE = "backupDrive"
    private const val EXPORT = "exportTarget"
    private const val IMPORT_FOLDER = "importFolder"
    private const val IMPORT_FILES = "importFiles"
    private val CANCELLED = JSONObject().put("cancelled", true).toString()
  }
}
