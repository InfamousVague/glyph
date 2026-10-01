package com.mattssoftware.glyph.files

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import org.json.JSONObject

/**
 * Where an export of everything goes (native generation 22; docs/DESIGN.md §167, src-tauri/src/export_commands.rs).
 *
 * Matt: "Please add a feature that allows me to plug in a USB drive and export the entire app onto a folder or zip
 * file". The system's picker makes the file (ACTION_CREATE_DOCUMENT, a zip named as the page proposes): a USB drive
 * plugged in is one of its places, beside the phone's own Downloads. No permission is asked, since the picker hands
 * over the one file the person made.
 *
 * The file is opened for writing here and its descriptor detached and handed to the page as
 * `window.__glyph.exportTarget({ fd, name })`; the page passes it to Rust (`export_fd`), which writes the archive
 * straight into it and closes it. So nothing is built in the phone's own storage first. A closed picker answers
 * `{ cancelled: true }`, a picker that would not open or a file that would not open `{ error }`.
 *
 * The page says how it ended: `discard` when the export failed or was stopped, which deletes the half-written file so
 * the drive holds only an archive that opens, and `done` when it is whole.
 */
object ExportTarget {
  /**
   * The request code the activity answers in onActivityResult: 4101 to 4104 are the activity's own, 4105 is
   * location's (location/LocationAccess.kt) and 4106 a film's (media/VideoPick.kt).
   */
  const val REQUEST = 4107
  private const val TAG = "GlyphExport"

  const val NO_PICKER = "This phone has no way to choose where to save."
  const val UNWRITABLE = "That place can’t be written to."

  /** The document the picker made, until the page says the export into it is done or is to go. */
  @Volatile private var made: Uri? = null

  /** Opens the picker from the page's call, on the bridge's thread: "started", and the answer arrives later. */
  fun start(activity: Activity, name: String, tell: (String) -> Unit): String {
    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
      .addCategory(Intent.CATEGORY_OPENABLE)
      .setType("application/zip")
      .putExtra(Intent.EXTRA_TITLE, name)
    activity.runOnUiThread {
      try {
        activity.startActivityForResult(intent, REQUEST)
      } catch (error: ActivityNotFoundException) {
        tell(failed(NO_PICKER))
      } catch (error: Exception) {
        Log.w(TAG, "save picker not started", error)
        tell(failed(NO_PICKER))
      }
    }
    return "started"
  }

  /** The picker's answer: the made file opened and its descriptor told to the page. Answers whether it was this one. */
  fun answered(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?, tell: (String) -> Unit): Boolean {
    if (requestCode != REQUEST) return false
    val uri = data?.data
    if (resultCode != Activity.RESULT_OK || uri == null) {
      tell(JSONObject().put("cancelled", true).toString())
      return true
    }
    made = uri
    try {
      val opened = activity.contentResolver.openFileDescriptor(uri, "w") ?: throw IllegalStateException("no descriptor")
      // Detached: the descriptor is Rust's from here, which closes it when the archive is written.
      val fd = opened.detachFd()
      tell(JSONObject().put("fd", fd).put("name", nameOf(activity, uri) ?: "").toString())
    } catch (error: Exception) {
      Log.w(TAG, "export target not opened", error)
      discard(activity)
      tell(failed(UNWRITABLE))
    }
    return true
  }

  /** The export failed or was stopped: the half-written file goes. */
  fun discard(context: Context) {
    val uri = made ?: return
    made = null
    try {
      DocumentsContract.deleteDocument(context.contentResolver, uri)
    } catch (error: Exception) {
      Log.w(TAG, "half an export not removed", error)
    }
  }

  /** The export is whole: the file stays. */
  fun done() {
    made = null
  }

  private fun nameOf(context: Context, uri: Uri): String? =
    try {
      context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
      }
    } catch (error: Exception) {
      null
    }

  private fun failed(message: String) = JSONObject().put("error", message).toString()
}
