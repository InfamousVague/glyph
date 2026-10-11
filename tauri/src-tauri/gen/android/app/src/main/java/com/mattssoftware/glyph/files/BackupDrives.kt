package com.mattssoftware.glyph.files

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.provider.DocumentsContract
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * The removable drives a backup can go to on Android, and the grant to write one (docs/DESIGN.md §204; native
 * generation 26). Matt: "it should prompt the user to plugin a removable drive to backup all the notes in the app to
 * workspace folders and such under a Ghost.md folder on the root of the drive".
 *
 * A drive is a `StorageVolume` the phone calls removable and has mounted for writing: a USB stick on a cable, an SD
 * card. Ghost.md asks for no storage permission (none would be granted for a drive on a modern Android, and Google
 * Play asks for a declaration of them): the system's own folder picker is opened on the drive's root
 * (`createOpenDocumentTreeIntent`, Android 10 and up; the plain picker before), the person allows it once, and the grant
 * is kept by the drive's id, so the next backup to the same drive asks nothing. The writing is Rust's, through
 * LibraryTree.kt's calls on that tree (src-tauri/src/saf.rs `TreeTarget`), the same doors a library folder uses.
 *
 * The grant must be to the drive itself, so the backup's `Ghost.md` folder lands on its root: a folder chosen inside
 * the drive is refused with a sentence that says so.
 */
object BackupDrives {
  const val REQUEST = 4109
  private const val TAG = "GlyphBackupDrives"
  private const val PREFS = "glyph-backup-drives"
  private const val NO_PICKER = "This phone has no way to choose a drive."

  /** The drive the picker is open for, by its id, until it answers. */
  @Volatile private var asking: String? = null

  private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  /** Every drive's tree Ghost.md was let write to, for LibraryTree's tidy at launch to keep. */
  fun trees(context: Context): Set<Uri> =
    prefs(context).all.values.mapNotNull { (it as? String)?.let(Uri::parse) }.toSet()

  private fun removable(context: Context): List<StorageVolume> {
    val storage = context.getSystemService(StorageManager::class.java) ?: return emptyList()
    return storage.storageVolumes.filter { it.isRemovable && it.state == Environment.MEDIA_MOUNTED && it.uuid != null }
  }

  /** Whether Ghost.md still holds a write grant on `tree`. */
  private fun held(context: Context, tree: Uri): Boolean =
    context.contentResolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission && it.isWritePermission }

  /**
   * The drives plugged in now, as JSON: `[{ id, name, tree?, free?, total? }]`, `tree` where Ghost.md may already
   * write it. A grant the person took back in the system's settings is forgotten here.
   */
  fun drives(context: Context): String {
    val out = JSONArray()
    val kept = prefs(context)
    for (volume in removable(context)) {
      val id = volume.uuid ?: continue
      val drive = JSONObject().put("id", id).put("name", volume.getDescription(context) ?: id)
      kept.getString(id, null)?.let { tree ->
        if (held(context, Uri.parse(tree))) drive.put("tree", tree) else kept.edit().remove(id).apply()
      }
      // The room on it, where the phone shows the drive's folder (Android 11 and up); a stat needs no permission.
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        try {
          volume.directory?.let { dir ->
            val stat = StatFs(dir.path)
            drive.put("free", stat.availableBytes).put("total", stat.totalBytes)
          }
        } catch (error: Exception) {
          // No room to say: the backup's own write will tell if it is full.
        }
      }
      out.put(drive)
    }
    return out.toString()
  }

  /** Opens the picker on drive `id`'s root, for the person to allow: "started", and the answer arrives later. */
  fun ask(activity: Activity, id: String, tell: (String) -> Unit): String {
    val volume = removable(activity).firstOrNull { it.uuid == id } ?: return failed("That drive isn’t plugged in any more.")
    val intent = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) volume.createOpenDocumentTreeIntent() else Intent(Intent.ACTION_OPEN_DOCUMENT_TREE))
      .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
    asking = id
    activity.runOnUiThread {
      try {
        activity.startActivityForResult(intent, REQUEST)
      } catch (error: ActivityNotFoundException) {
        asking = null
        tell(failed(NO_PICKER))
      } catch (error: Exception) {
        Log.w(TAG, "drive picker not started", error)
        asking = null
        tell(failed(NO_PICKER))
      }
    }
    return "started"
  }

  /** The picker's answer: the drive's root kept and told to the page, or why not. Answers whether it was this one. */
  fun answered(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?, tell: (String) -> Unit): Boolean {
    if (requestCode != REQUEST) return false
    val id = asking
    asking = null
    val uri = data?.data
    if (resultCode != Activity.RESULT_OK || uri == null || id == null) {
      tell(JSONObject().put("cancelled", true).toString())
      return true
    }
    // The drive's root is the tree whose document id is the drive's id and a colon: "1A2B-3C4D:".
    val root = try { DocumentsContract.getTreeDocumentId(uri) } catch (error: Exception) { "" }
    if (root != "$id:") {
      tell(failed("Choose the drive itself, not a folder on it, so the backup goes on its top level."))
      return true
    }
    try {
      activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
      prefs(activity).edit().putString(id, uri.toString()).apply()
      tell(JSONObject().put("id", id).put("tree", uri.toString()).toString())
    } catch (error: Exception) {
      Log.w(TAG, "drive grant not kept", error)
      tell(failed("Ghost.md can’t keep that drive. Try again."))
    }
    return true
  }

  private fun failed(message: String) = JSONObject().put("error", message).toString()
}
