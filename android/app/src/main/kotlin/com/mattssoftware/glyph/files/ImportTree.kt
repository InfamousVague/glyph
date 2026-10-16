package com.mattssoftware.glyph.files

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.OpenableColumns
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/**
 * What Settings › Import reads, through Android's own pickers (lib/importer/import_sources.dart, over FilesBridge's
 * `ghost_md/files`):
 *
 * - `chooseImportFolder` -> `{tree, name}`: a folder, an Obsidian vault, granted for reading for as long as the
 *   activity lives. Never kept past it: nothing is taken persistable, so LibraryTree's tidy has nothing to let go.
 * - `chooseImportFiles` -> `{files: [{uri, name, size}]}`: one or more files, Evernote's `.enex` exports. Android has
 *   no type for them (a file manager says `application/enex+xml`, `text/xml` or `application/octet-stream`), so any
 *   file can be chosen and the app says what it could not read.
 * - `importList {tree}` -> `{entries: [{path, uri, size, modified}], skipped: [path]}`: every file under the folder,
 *   by its path in it, one DocumentsContract query per folder; a folder whose name starts with a dot (`.obsidian`,
 *   `.trash`, `.git`) is not walked, and is named in `skipped`.
 * - `importRead {uri}` -> the file's bytes. `importCopy {uri, to}` -> null, the file copied to `to`, a path in the
 *   app's own folders, so a large file never crosses the channel.
 *
 * Each picker answers `{cancelled: true}` when closed. The walk, the read and the copy run off the main thread;
 * FilesBridge answers each call when its work is done.
 */
object ImportTree {
  private const val TAG = "GhostImport"
  const val FOLDER = 4110
  const val FILES = 4111

  fun chooseFolder(activity: Activity, tell: (String) -> Unit): String {
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    return start(activity, intent, FOLDER, tell)
  }

  fun chooseFiles(activity: Activity, tell: (String) -> Unit): String {
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
      .addCategory(Intent.CATEGORY_OPENABLE)
      .setType("*/*")
      .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
      .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    return start(activity, intent, FILES, tell)
  }

  private fun start(activity: Activity, intent: Intent, request: Int, tell: (String) -> Unit): String {
    activity.runOnUiThread {
      try {
        activity.startActivityForResult(intent, request)
      } catch (error: ActivityNotFoundException) {
        tell(failed("This phone has no file picker."))
      } catch (error: Exception) {
        Log.w(TAG, "import picker not started", error)
        tell(failed("The picker did not open."))
      }
    }
    return "started"
  }

  /** A picker's answer; whether it was one of these. */
  fun answered(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?, folder: (String) -> Unit, files: (String) -> Unit): Boolean {
    when (requestCode) {
      FOLDER -> {
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) return true.also { folder(CANCELLED) }
        folder(JSONObject().put("tree", uri.toString()).put("name", treeName(activity, uri) ?: "Vault").toString())
        return true
      }
      FILES -> {
        if (resultCode != Activity.RESULT_OK || data == null) return true.also { files(CANCELLED) }
        val uris = ArrayList<Uri>()
        val clip = data.clipData
        if (clip != null) for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { uris.add(it) }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }
        if (uris.isEmpty()) return true.also { files(CANCELLED) }
        val list = JSONArray()
        for (uri in uris) {
          val (name, size) = described(activity, uri)
          list.put(JSONObject().put("uri", uri.toString()).put("name", name).put("size", size))
        }
        files(JSONObject().put("files", list).toString())
        return true
      }
    }
    return false
  }

  /** The folder's files, walked off the main thread. */
  fun list(activity: Activity, tree: String): String =
    try {
      val treeUri = Uri.parse(tree)
      val entries = JSONArray()
      val skipped = JSONArray()
      val folders = ArrayDeque<Pair<String, String>>()
      folders.add("" to DocumentsContract.getTreeDocumentId(treeUri))
      while (folders.isNotEmpty()) {
        val (path, id) = folders.removeFirst()
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, id)
        val found = ArrayList<Array<Any?>>()
        activity.contentResolver.query(children, COLUMNS, null, null, null)?.use { cursor ->
          while (cursor.moveToNext()) {
            val child = cursor.getString(0) ?: continue
            val name = cursor.getString(1) ?: continue
            found.add(arrayOf(child, name, cursor.getString(2) ?: "", if (cursor.isNull(3)) 0L else cursor.getLong(3), if (cursor.isNull(4)) 0L else cursor.getLong(4)))
          }
        }
        found.sortBy { it[1] as String }
        for (row in found) {
          val name = row[1] as String
          val rel = if (path.isEmpty()) name else "$path/$name"
          if (row[2] == Document.MIME_TYPE_DIR) {
            if (name.startsWith(".")) skipped.put(rel) else folders.add(rel to (row[0] as String))
          } else if (!name.startsWith(".")) {
            val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, row[0] as String)
            entries.put(JSONObject().put("path", rel).put("uri", uri.toString()).put("modified", row[3]).put("size", row[4]))
          }
        }
      }
      JSONObject().put("entries", entries).put("skipped", skipped).toString()
    } catch (error: Exception) {
      Log.w(TAG, "folder not walked", error)
      failed("That folder could not be read.")
    }

  fun read(activity: Activity, uri: String): ByteArray? =
    try {
      activity.contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
    } catch (error: Exception) {
      Log.w(TAG, "file not read", error)
      null
    }

  /** Copies `uri` to `to`, whole or not at all. */
  fun copy(activity: Activity, uri: String, to: String): Boolean {
    val target = File(to)
    val part = File(target.parentFile, ".${target.name}.part")
    return try {
      target.parentFile?.mkdirs()
      activity.contentResolver.openInputStream(Uri.parse(uri))?.use { input -> FileOutputStream(part).use { input.copyTo(it, 256 * 1024) } } ?: return false
      part.renameTo(target)
    } catch (error: Exception) {
      Log.w(TAG, "file not copied", error)
      part.delete()
      false
    }
  }

  private fun treeName(activity: Activity, tree: Uri): String? =
    try {
      val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
      activity.contentResolver.query(root, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (error: Exception) {
      null
    }

  private fun described(activity: Activity, uri: Uri): Pair<String, Long> =
    try {
      activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) (cursor.getString(0) ?: "Export.enex") to (if (cursor.isNull(1)) 0L else cursor.getLong(1)) else null
      } ?: ("Export.enex" to 0L)
    } catch (error: Exception) {
      "Export.enex" to 0L
    }

  private val COLUMNS = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_LAST_MODIFIED, Document.COLUMN_SIZE)
  private val CANCELLED = JSONObject().put("cancelled", true).toString()

  private fun failed(message: String) = JSONObject().put("error", message).toString()
}
