package com.mattssoftware.glyph.files

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.ConcurrentHashMap

/**
 * A folder of the person's as the notes' library, on the phone (native generation 25; docs/DESIGN.md §185,
 * src-tauri/src/saf.rs, src-tauri/src/library/tree.rs). Matt: "include #6 as a plugin", #6 being "An Obsidian vault,
 * iCloud Drive or Dropbox. Notes are already plain Markdown files. Letting you choose where the library folder lives
 * would make Obsidian, backups and other editors work for free."
 *
 * TWO HALVES.
 *
 * - **The picker.** `start` opens Android's folder picker (ACTION_OPEN_DOCUMENT_TREE); `answered` keeps the grant
 *   across restarts (`takePersistableUriPermission`, read and write) and tells the page
 *   `window.__glyph.libraryFolder({ uri, name })`, `{ cancelled }` or `{ error }`. The page then asks Rust to look
 *   into the folder (`library_inspect`) and, once the person says so, to move the library there (`library_move`).
 * - **The files.** Rust reaches the folder through the static methods below, by relative path, each answering one JSON
 *   string (`{"error"}` for a failure, `{"missing": true}` for a file that is not there). A folder through the Storage
 *   Access Framework has document ids, not paths, so a path is walked from the folder down by display names, one
 *   DocumentsContract query per folder with only the columns needed (never a DocumentFile per file, which is a query
 *   per question), and the ids found are kept, so the next call for the same path asks nothing.
 *
 * Rust calls in from threads it started, where the JVM cannot find this class by name: `install` hands Rust the class
 * itself (`attach`). The activity installs it before Tauri starts, so a launch can open the folder, and the write-up's
 * doors install it before they call Rust. `install` from the activity also lets go of the grants for folders that are
 * not the library any more (one picked and not moved into, or one gone back from), so the phone's list of what Ghost.md
 * may reach stays what it reaches.
 *
 * iCloud Drive has no Android app, so no folder of it can be chosen here. Dropbox and Google Drive reach the picker
 * through their own apps' providers, which may hold a file online only and answer slowly; a folder on the phone
 * itself, which Syncthing keeps, is the reliable case. The page says so.
 *
 * Where the library is lives in `LibraryRoot`, at the end of this file, which loads no Rust.
 */
object LibraryTree {
  init {
    System.loadLibrary("glyph_lib")
  }

  /** The request code the activity answers in onActivityResult: 4101 to 4107 are taken (files/ExportTarget.kt says whose). */
  const val REQUEST = 4108
  private const val TAG = "GlyphLibraryTree"
  private const val NO_PICKER = "This phone has no way to choose a folder."

  /** The app's context, for its content resolver. */
  @Volatile private var context: Context? = null

  /** Per folder, the document id of every path found so far: `""` for the folder itself, `Work/Plan.md`, `Work`. */
  private val ids = ConcurrentHashMap<String, ConcurrentHashMap<String, String>>()

  private val COLUMNS = arrayOf(
    Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_LAST_MODIFIED, Document.COLUMN_SIZE,
  )

  /** Hands Rust the JVM and this class (src-tauri/src/saf.rs `attach`). */
  @JvmStatic private external fun attach()

  /** Ready for Rust's calls; `tidy` (the activity's launch) also lets go of grants the library no longer uses. */
  fun install(context: Context, tidy: Boolean = false) {
    this.context = context.applicationContext
    attach()
    if (tidy) Thread({ releaseUnused(context.applicationContext) }, "glyph-library-grants").start()
  }

  private fun releaseUnused(context: Context) {
    val keep = LibraryRoot.chosenTree(context)
    try {
      for (grant in context.contentResolver.persistedUriPermissions) {
        if (grant.uri == keep || !DocumentsContract.isTreeUri(grant.uri)) continue
        context.contentResolver.releasePersistableUriPermission(grant.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
      }
    } catch (error: Exception) {
      Log.w(TAG, "old folder grants not released", error)
    }
  }

  // ---- the picker ------------------------------------------------------------------------------

  /** Opens the folder picker from the page's call: "started", and the answer arrives later. */
  fun start(activity: Activity, tell: (String) -> Unit): String {
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
      Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
    )
    activity.runOnUiThread {
      try {
        activity.startActivityForResult(intent, REQUEST)
      } catch (error: ActivityNotFoundException) {
        tell(failed(NO_PICKER))
      } catch (error: Exception) {
        Log.w(TAG, "folder picker not started", error)
        tell(failed(NO_PICKER))
      }
    }
    return "started"
  }

  /** The picker's answer: the grant kept and the folder told to the page. Answers whether it was this one. */
  fun answered(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?, tell: (String) -> Unit): Boolean {
    if (requestCode != REQUEST) return false
    val uri = data?.data
    if (resultCode != Activity.RESULT_OK || uri == null) {
      tell(JSONObject().put("cancelled", true).toString())
      return true
    }
    try {
      activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
      tell(JSONObject().put("uri", uri.toString()).put("name", nameOf(activity, uri) ?: "").toString())
    } catch (error: Exception) {
      Log.w(TAG, "folder grant not kept", error)
      tell(failed("Ghost.md can’t keep that folder. Choose another."))
    }
    return true
  }

  private fun nameOf(context: Context, tree: Uri): String? =
    try {
      val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
      context.contentResolver.query(root, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
      }
    } catch (error: Exception) {
      null
    }

  // ---- the files, for Rust ---------------------------------------------------------------------

  private class Missing(path: String) : Exception(path)

  private fun failed(message: String) = JSONObject().put("error", message).toString()

  /** One of Rust's calls: its answer, a missing file as `{"missing": true}`, anything thrown as `{"error"}`. */
  private inline fun answer(block: () -> JSONObject): String =
    try {
      block().toString()
    } catch (missing: Missing) {
      JSONObject().put("missing", true).toString()
    } catch (missing: FileNotFoundException) {
      JSONObject().put("missing", true).toString()
    } catch (error: Throwable) {
      Log.w(TAG, "folder call failed", error)
      failed(error.message ?: error.toString())
    }

  private fun resolver() = (context ?: throw IllegalStateException("the folder bridge is not installed")).contentResolver

  private fun known(tree: String) = ids.getOrPut(tree) { ConcurrentHashMap() }

  private fun treeUri(tree: String): Uri = Uri.parse(tree)

  private fun documentUri(tree: String, id: String): Uri = DocumentsContract.buildDocumentUriUsingTree(treeUri(tree), id)

  private fun parentOf(path: String) = path.substringBeforeLast('/', "")

  private fun nameIn(path: String) = path.substringAfterLast('/')

  private fun joined(parent: String, name: String) = if (parent.isEmpty()) name else "$parent/$name"

  /** The children of the folder `id`, as (display name, id, mime, modified, size); every one is remembered by path. */
  private fun children(tree: String, parentPath: String, id: String): List<Child> {
    val uri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri(tree), id)
    val found = ArrayList<Child>()
    resolver().query(uri, COLUMNS, null, null, null)?.use { cursor ->
      while (cursor.moveToNext()) {
        val child = Child(
          id = cursor.getString(0) ?: continue,
          name = cursor.getString(1) ?: continue,
          mime = cursor.getString(2) ?: "",
          modified = if (cursor.isNull(3)) 0L else cursor.getLong(3),
          size = if (cursor.isNull(4)) 0L else cursor.getLong(4),
        )
        found.add(child)
        known(tree)[joined(parentPath, child.name)] = child.id
      }
    }
    return found
  }

  private data class Child(val id: String, val name: String, val mime: String, val modified: Long, val size: Long) {
    val isDir get() = mime == Document.MIME_TYPE_DIR
  }

  /** The document id of `path` in the folder, or null; asked of the provider only for what is not remembered. */
  private fun find(tree: String, path: String): String? {
    if (path.isEmpty()) return known(tree).getOrPut("") { DocumentsContract.getTreeDocumentId(treeUri(tree)) }
    known(tree)[path]?.let { return it }
    val parent = find(tree, parentOf(path)) ?: return null
    children(tree, parentOf(path), parent)
    return known(tree)[path]
  }

  /** `path`'s time and size, by its document id, or null when the provider no longer has it. */
  private fun entryOf(tree: String, path: String, id: String): JSONArray? =
    try {
      resolver().query(documentUri(tree, id), COLUMNS, null, null, null)?.use { cursor ->
        if (!cursor.moveToFirst()) {
          null
        } else {
          JSONArray().put(path).put(if (cursor.isNull(3)) 0L else cursor.getLong(3)).put(if (cursor.isNull(4)) 0L else cursor.getLong(4))
        }
      }
    } catch (error: FileNotFoundException) {
      null
    } catch (error: IllegalArgumentException) {
      null
    }

  /** `path`'s id, checked against the provider: a remembered id another app made stale is looked up again once. */
  private fun live(tree: String, path: String): Pair<String, JSONArray>? {
    val remembered = find(tree, path) ?: return null
    entryOf(tree, path, remembered)?.let { return remembered to it }
    forget(tree, path)
    val again = find(tree, path) ?: return null
    return entryOf(tree, path, again)?.let { again to it }
  }

  /** Every remembered id at `path` and under it. */
  private fun forget(tree: String, path: String) {
    val map = known(tree)
    map.keys.filter { it == path || it.startsWith("$path/") }.forEach { map.remove(it) }
  }

  /** Whether Ghost.md still holds its grant to read and write the folder. */
  @JvmStatic
  fun granted(tree: String): String = answer {
    val uri = treeUri(tree)
    val held = resolver().persistedUriPermissions.any { it.uri == uri && it.isReadPermission && it.isWritePermission }
    if (!held) throw IllegalStateException("Ghost.md no longer has that folder. Choose it again.")
    JSONObject()
  }

  /** The folder's name, how many Markdown files are in it, and whether Obsidian keeps it: nothing is written. */
  @JvmStatic
  fun inspect(tree: String): String = answer {
    val root = find(tree, "") ?: throw Missing(tree)
    val obsidian = children(tree, "", root).any { it.isDir && it.name == ".obsidian" }
    val count = entries(tree).length()
    JSONObject().put("name", nameOf(context!!, treeUri(tree)) ?: "").put("markdown", count).put("obsidian", obsidian)
  }

  /** Every `.md` under the folder, at any depth, but none with a dot name or in a dot folder: `[path, modified, size]`. */
  @JvmStatic
  fun list(tree: String): String = answer { JSONObject().put("entries", entries(tree)) }

  private fun entries(tree: String): JSONArray {
    val out = JSONArray()
    val root = find(tree, "") ?: throw Missing(tree)
    val pending = ArrayDeque<Pair<String, String>>()
    pending.add("" to root)
    while (pending.isNotEmpty()) {
      val (path, id) = pending.removeFirst()
      for (child in children(tree, path, id)) {
        if (child.name.startsWith(".")) continue
        val at = joined(path, child.name)
        if (child.isDir) {
          pending.add(at to child.id)
        } else if (child.name.lowercase().endsWith(".md")) {
          out.put(JSONArray().put(at).put(child.modified).put(child.size))
        }
      }
    }
    return out
  }

  @JvmStatic
  fun read(tree: String, path: String): String = answer {
    val (id, _) = live(tree, path) ?: throw Missing(path)
    val text = resolver().openInputStream(documentUri(tree, id))?.use { it.readBytes().toString(Charsets.UTF_8) } ?: throw Missing(path)
    JSONObject().put("text", text)
  }

  /** The whole file, written in place ("wt": truncated first, which "w" alone does not do on every Android). */
  @JvmStatic
  fun write(tree: String, path: String, text: String): String = answer {
    val id = live(tree, path)?.first ?: create(tree, path)
    resolver().openOutputStream(documentUri(tree, id), "wt")?.use { it.write(text.toByteArray(Charsets.UTF_8)) } ?: throw IllegalStateException("$path could not be written")
    JSONObject().put("entry", entryOf(tree, path, id) ?: throw Missing(path))
  }

  /** The folders `path` is in, made where they are not, and the file itself, by its name. */
  private fun create(tree: String, path: String): String {
    val parent = folder(tree, parentOf(path))
    val name = nameIn(path)
    val mime = if (name.lowercase().endsWith(".md")) "text/markdown" else "application/octet-stream"
    var made = DocumentsContract.createDocument(resolver(), documentUri(tree, parent), mime, name) ?: throw IllegalStateException("$path could not be made")
    // A provider may change the name it was given (an extension for the type, a number for a clash): put it back.
    val given = nameOf(made)
    if (given != null && given != name) {
      made = DocumentsContract.renameDocument(resolver(), made, name) ?: made
    }
    val id = DocumentsContract.getDocumentId(made)
    known(tree)[path] = id
    return id
  }

  private fun nameOf(document: Uri): String? =
    resolver().query(document, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }

  /** The folder at `path`, made (and its parents) where it is not. */
  private fun folder(tree: String, path: String): String {
    if (path.isEmpty()) return find(tree, "") ?: throw Missing(tree)
    find(tree, path)?.let { return it }
    val parent = folder(tree, parentOf(path))
    val made = DocumentsContract.createDocument(resolver(), documentUri(tree, parent), Document.MIME_TYPE_DIR, nameIn(path))
      ?: throw IllegalStateException("$path could not be made")
    val id = DocumentsContract.getDocumentId(made)
    known(tree)[path] = id
    return id
  }

  /**
   * A file moved and renamed: moved by the provider where it can (`moveDocument`), and otherwise copied and the first
   * removed, then renamed in place.
   */
  @JvmStatic
  fun rename(tree: String, from: String, to: String): String = answer {
    val (id, _) = live(tree, from) ?: throw Missing(from)
    var uri = documentUri(tree, id)
    if (parentOf(from) != parentOf(to)) {
      val source = folder(tree, parentOf(from))
      val target = folder(tree, parentOf(to))
      val moved = try {
        DocumentsContract.moveDocument(resolver(), uri, documentUri(tree, source), documentUri(tree, target))
      } catch (error: Exception) {
        null
      }
      if (moved == null) {
        // No move here: the words are written at the new path and the old file goes.
        val text = resolver().openInputStream(uri)?.use { it.readBytes() } ?: throw Missing(from)
        val made = create(tree, to)
        resolver().openOutputStream(documentUri(tree, made), "wt")?.use { it.write(text) }
        DocumentsContract.deleteDocument(resolver(), uri)
        forget(tree, from)
        return@answer JSONObject()
      }
      uri = moved
    }
    if (nameIn(from) != nameIn(to)) {
      uri = DocumentsContract.renameDocument(resolver(), uri, nameIn(to)) ?: uri
    }
    forget(tree, from)
    forget(tree, to)
    known(tree)[to] = DocumentsContract.getDocumentId(uri)
    JSONObject()
  }

  @JvmStatic
  fun remove(tree: String, path: String): String = answer {
    val (id, _) = live(tree, path) ?: return@answer JSONObject()
    DocumentsContract.deleteDocument(resolver(), documentUri(tree, id))
    forget(tree, path)
    JSONObject()
  }

  @JvmStatic
  fun stat(tree: String, path: String): String = answer {
    val (_, entry) = live(tree, path) ?: throw Missing(path)
    JSONObject().put("entry", entry)
  }
}

/**
 * Where the library is, as Rust keeps it, read without loading Rust: the Files app's provider (LibraryDocuments.kt)
 * asks on every listing, in a process that may have started for nothing else.
 */
object LibraryRoot {
  private const val TAG = "GlyphLibraryRoot"

  // The library's setting, as Rust writes it: `ROOT_FILE` in src-tauri/src/library/root.rs (src-tauri/src/paths.rs's
  // test holds the two names together). Absent for the app's own folder.
  private fun file(context: Context): File = File(context.dataDir, "library-root.json")

  /** The folder the library is in when it is one chosen on this phone, as its tree URI; null for the app's own. */
  fun chosenTree(context: Context): Uri? =
    try {
      val file = file(context)
      if (!file.exists()) {
        null
      } else {
        val root = JSONObject(file.readText())
        if (root.optString("kind") == "tree" && root.optString("uri").isNotEmpty()) Uri.parse(root.optString("uri")) else null
      }
    } catch (error: Exception) {
      Log.w(TAG, "library-root.json not read", error)
      null
    }
}
