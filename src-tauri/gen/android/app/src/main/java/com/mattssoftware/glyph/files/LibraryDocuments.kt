package com.mattssoftware.glyph.files

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.webkit.MimeTypeMap
import com.mattssoftware.glyph.R
import java.io.File
import java.io.FileNotFoundException

/**
 * The notes' folder in the phone's Files app (Matt: "maybe just add a browse local files button somewhere to open the
 * folder on the phones file browser"). The library is Markdown files in the app's own storage (docs/LIBRARY.md), at
 * `<data dir>/Library`, where no other app can reach it: this provider is how Android lets an app show a folder of its
 * own there. It lists "Ghost.md" among the Files app's places, with the workspaces as folders and each note as its
 * `.md`, and the sidebar's Browse files button opens it (MainActivity `GlyphHost.browseFiles`).
 *
 * Read-only. A note changed by another app behind the library's back would not reach its index or sync, so the Files
 * app can open, read, copy and share a note, and nothing more. `.glyph/`, the app's own index and recordings, is
 * hidden, as a Mac hides dot folders.
 */
class LibraryDocuments : DocumentsProvider() {
  companion object {
    const val ROOT_ID = "library"
    /** A document's id is its path under the library, after this; the library itself is the prefix alone. */
    private const val PREFIX = "lib:"
    fun authority(packageName: String) = "$packageName.library"
    fun rootDocumentId() = PREFIX

    private val ROOT_COLUMNS = arrayOf(
      Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE, Root.COLUMN_SUMMARY, Root.COLUMN_FLAGS, Root.COLUMN_ICON,
    )
    private val DOCUMENT_COLUMNS = arrayOf(
      Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
      Document.COLUMN_LAST_MODIFIED, Document.COLUMN_SIZE, Document.COLUMN_FLAGS,
    )
  }

  private fun library(): File = File(context!!.dataDir, "Library")

  private fun idOf(file: File): String {
    val base = library().canonicalFile
    val here = file.canonicalFile
    return PREFIX + here.path.removePrefix(base.path).trimStart('/')
  }

  /** The file an id names, and only one inside the library: an id can't walk out of it with `..`. */
  private fun fileOf(id: String): File {
    if (!id.startsWith(PREFIX)) throw FileNotFoundException(id)
    val base = library().canonicalFile
    val file = File(base, id.removePrefix(PREFIX)).canonicalFile
    if (file != base && !file.path.startsWith(base.path + File.separator)) throw FileNotFoundException(id)
    if (!file.exists()) throw FileNotFoundException(id)
    return file
  }

  private fun mimeOf(file: File): String {
    if (file.isDirectory) return Document.MIME_TYPE_DIR
    if (file.extension.equals("md", ignoreCase = true)) return "text/markdown"
    return MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"
  }

  private fun addRow(cursor: MatrixCursor, file: File) {
    cursor.newRow().apply {
      add(Document.COLUMN_DOCUMENT_ID, idOf(file))
      add(Document.COLUMN_DISPLAY_NAME, if (file.canonicalFile == library().canonicalFile) "Ghost.md" else file.name)
      add(Document.COLUMN_MIME_TYPE, mimeOf(file))
      add(Document.COLUMN_LAST_MODIFIED, file.lastModified())
      add(Document.COLUMN_SIZE, if (file.isDirectory) null else file.length())
      // Nothing to write, rename or delete: read-only, as the note above says.
      add(Document.COLUMN_FLAGS, 0)
    }
  }

  override fun onCreate(): Boolean = true

  override fun queryRoots(projection: Array<out String>?): Cursor {
    val cursor = MatrixCursor(projection ?: ROOT_COLUMNS)
    library().mkdirs()
    cursor.newRow().apply {
      add(Root.COLUMN_ROOT_ID, ROOT_ID)
      add(Root.COLUMN_DOCUMENT_ID, rootDocumentId())
      add(Root.COLUMN_TITLE, "Ghost.md")
      add(Root.COLUMN_SUMMARY, "Your notes, as Markdown")
      add(Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_IS_CHILD or Root.FLAG_LOCAL_ONLY)
      add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
    }
    return cursor
  }

  override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
    val cursor = MatrixCursor(projection ?: DOCUMENT_COLUMNS)
    addRow(cursor, fileOf(documentId))
    return cursor
  }

  override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor {
    val cursor = MatrixCursor(projection ?: DOCUMENT_COLUMNS)
    val parent = fileOf(parentDocumentId)
    parent.listFiles()
      ?.filter { !it.name.startsWith(".") }
      ?.sortedWith(compareBy<File>({ !it.isDirectory }, { it.name.lowercase() }))
      ?.forEach { addRow(cursor, it) }
    return cursor
  }

  override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
    if (mode.contains('w') || mode.contains('t')) throw FileNotFoundException("Ghost.md's files are read-only here: edit a note in Ghost.md.")
    return ParcelFileDescriptor.open(fileOf(documentId), ParcelFileDescriptor.MODE_READ_ONLY)
  }

  override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
    val parent = parentDocumentId.removePrefix(PREFIX)
    val child = documentId.removePrefix(PREFIX)
    return documentId.startsWith(PREFIX) && (parent.isEmpty() || child.startsWith("$parent/"))
  }
}
