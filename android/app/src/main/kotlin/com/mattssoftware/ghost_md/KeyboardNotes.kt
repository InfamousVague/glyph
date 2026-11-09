package com.mattssoftware.ghost_md

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.provider.DocumentsContract
import com.mattssoftware.glyph.files.LibraryRoot
import java.io.File
import java.security.MessageDigest

/**
 * Ghost Keyboard asking about the notes (Matt, 2026-11-09: "integrate with Ghost so it can search ghostmarkdown for
 * context"): its Ghostwriter fills `<<posthog updates we made>>` in any app, and asks here for the notes that match,
 * on the phone, with nothing sent anywhere by this app.
 *
 * `content://<this app's id>.keyboard/`:
 * - `search?q=posthog waitlist&limit=6`: the best matching notes, as `title`, `path`, `updated` (ms), `snippet` (the
 *   lines round the first match) and `body` (the start of the note, front matter left out).
 * - `titles`: every note's title, for the keyboard's [[link]] completion.
 * - `tags`: empty for now (the keyboard learns tags as they are typed).
 *
 * Who may ask: Ghost Keyboard alone, known by its package and its release certificate ([KEYBOARDS]); a debug build of
 * this app also lets a debug build of the keyboard in, for trying it on an emulator. And only while Settings > AI >
 * Ghost Keyboard is on ([on], on by default): off, every answer is empty. Read-only; the notes are read where the
 * library keeps them, its own folder or the folder chosen for it (files/LibraryTree.kt `LibraryRoot`), `.glyph/` and
 * other dot folders left out.
 */
class KeyboardNotes : ContentProvider() {
    companion object {
        private const val PREFS = "ghost_keyboard"
        private const val KEY = "share"

        /** Ghost Keyboard's package and the SHA-256 of its release certificate (~/.config/devkeyboard/cert.sha256). */
        private val KEYBOARDS = mapOf(
            "com.infamousvague.devkeyboard" to "92d8d1984e60c634fa5874ccb1770ed1fe63da8fb42135b69bb16849ccf0610a",
        )

        private const val MAX_FILES = 4000
        private const val MAX_READ = 96 * 1024
        private const val BUDGET_MS = 2500L

        fun on(context: Context): Boolean = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY, true)

        fun set(context: Context, on: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY, on).apply()
        }
    }

    override fun onCreate() = true

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        val context = context ?: return null
        val columns = arrayOf("title", "path", "updated", "snippet", "body")
        val empty = MatrixCursor(columns)
        if (!allowed(context) || !on(context)) return empty
        return when (uri.lastPathSegment) {
            "search" -> search(context, uri.getQueryParameter("q").orEmpty(), (uri.getQueryParameter("limit")?.toIntOrNull() ?: 6).coerceIn(1, 20), columns)
            "titles" -> MatrixCursor(arrayOf("title")).also { c -> notes(context).take(MAX_FILES).forEach { c.addRow(arrayOf(titleOf(it.name, null))) } }
            "tags" -> MatrixCursor(arrayOf("tag"))
            else -> empty
        }
    }

    /** The caller is Ghost Keyboard, signed with its own key (or, in a debug build of this app, any build of it). */
    private fun allowed(context: Context): Boolean {
        val pm = context.packageManager
        val debug = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        val packages = pm.getPackagesForUid(Binder.getCallingUid()) ?: return false
        return packages.any { pkg ->
            val pin = KEYBOARDS[pkg] ?: return@any false
            debug || certificates(pm, pkg).any { it == pin }
        }
    }

    @Suppress("DEPRECATION")
    private fun certificates(pm: PackageManager, pkg: String): List<String> = runCatching {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES).signingInfo ?: return emptyList()
            if (info.hasMultipleSigners()) info.apkContentsSigners else info.signingCertificateHistory
        } else {
            pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES).signatures
        }
        signatures.orEmpty().map { sig -> MessageDigest.getInstance("SHA-256").digest(sig.toByteArray()).joinToString("") { "%02x".format(it) } }
    }.getOrDefault(emptyList())

    // --- the notes -------------------------------------------------------------------------------------------------

    /** A note as found: its name (the file's, without .md), its path in the library, when it changed, and a reader. */
    private class Note(val name: String, val path: String, val updated: Long, val read: () -> String)

    private fun notes(context: Context): List<Note> {
        val tree = LibraryRoot.chosenTree(context)
        return if (tree == null) ownFolder(File(context.dataDir, "Library")) else chosenFolder(context, tree)
    }

    private fun ownFolder(root: File): List<Note> {
        if (!root.isDirectory) return emptyList()
        val out = ArrayList<Note>()
        root.walkTopDown().onEnter { it == root || !it.name.startsWith(".") }.forEach { f ->
            if (out.size < MAX_FILES && f.isFile && f.name.endsWith(".md")) {
                out += Note(f.name.removeSuffix(".md"), f.relativeTo(root).path, f.lastModified()) {
                    f.inputStream().use { s -> head(s) }
                }
            }
        }
        return out
    }

    private fun chosenFolder(context: Context, tree: Uri): List<Note> {
        val resolver = context.contentResolver
        val out = ArrayList<Note>()
        val started = System.currentTimeMillis()
        fun walk(parentId: String, prefix: String) {
            if (out.size >= MAX_FILES || System.currentTimeMillis() - started > BUDGET_MS) return
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
            val cols = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val folders = ArrayList<Pair<String, String>>()
            runCatching {
                resolver.query(children, cols, null, null, null)?.use { c ->
                    while (c.moveToNext()) {
                        val id = c.getString(0) ?: continue
                        val name = c.getString(1) ?: continue
                        if (name.startsWith(".")) continue
                        if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) folders += id to "$prefix$name/"
                        else if (name.endsWith(".md") && out.size < MAX_FILES) {
                            val doc = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                            out += Note(name.removeSuffix(".md"), "$prefix$name", c.getLong(3)) {
                                resolver.openInputStream(doc)?.use { s -> head(s) }.orEmpty()
                            }
                        }
                    }
                }
            }
            folders.forEach { (id, path) -> walk(id, path) }
        }
        runCatching { walk(DocumentsContract.getTreeDocumentId(tree), "") }
        return out
    }

    /** The first [MAX_READ] bytes as text (readNBytes is Android 13's; this app runs from 7). */
    private fun head(s: java.io.InputStream): String {
        val buf = ByteArray(MAX_READ)
        var n = 0
        while (n < buf.size) { val r = s.read(buf, n, buf.size - n); if (r < 0) break; n += r }
        return String(buf, 0, n)
    }

    private val FRONT_MATTER = Regex("\\A---\\n.*?\\n---\\n", RegexOption.DOT_MATCHES_ALL)

    private fun titleOf(name: String, text: String?): String {
        val fm = text?.let { FRONT_MATTER.find(it)?.value }
        fm?.lines()?.firstOrNull { it.startsWith("title:") }?.substringAfter("title:")?.trim()?.trim('"', '\'')?.takeIf { it.isNotEmpty() }?.let { return it }
        // A note's title is its first line, a `# heading` as the app writes it.
        val first = text?.replaceFirst(FRONT_MATTER, "")?.lineSequence()?.map { it.trim() }?.firstOrNull { it.isNotEmpty() }
        if (first != null && first.startsWith("#")) first.trimStart('#').trim().takeIf { it.isNotEmpty() }?.let { return it }
        return name
    }

    private val STOP = setOf("the", "and", "for", "you", "with", "that", "this", "from", "what", "why", "how", "our", "about", "into", "not")

    /**
     * The notes that best match [query]: each word found in the title counts five, in the text one a time (up to five),
     * newer notes a little ahead. The words are the query's, lower-cased, two letters or more.
     */
    private fun search(context: Context, query: String, limit: Int, columns: Array<String>): Cursor {
        val words = query.lowercase().split(Regex("[^\\p{L}\\p{N}_-]+")).filter { it.length >= 2 && it !in STOP }.distinct()
        val cursor = MatrixCursor(columns)
        if (words.isEmpty()) return cursor
        val started = System.currentTimeMillis()
        val now = System.currentTimeMillis()
        data class Hit(val note: Note, val text: String, val score: Double)
        val hits = ArrayList<Hit>()
        for (note in notes(context).sortedByDescending { it.updated }) {
            if (System.currentTimeMillis() - started > BUDGET_MS) break
            val nameHit = words.count { note.name.lowercase().contains(it) }
            val text = runCatching { note.read() }.getOrDefault("")
            val lower = text.lowercase()
            var score = nameHit * 5.0
            for (w in words) {
                var i = lower.indexOf(w); var n = 0
                while (i >= 0 && n < 5) { n++; i = lower.indexOf(w, i + w.length) }
                score += n
            }
            if (score <= 0) continue
            // Every word present counts for more than one word many times over.
            score *= 1 + words.count { lower.contains(it) || note.name.lowercase().contains(it) }.toDouble() / words.size
            val ageDays = (now - note.updated) / 86_400_000.0
            hits += Hit(note, text, score / (1 + ageDays / 60))
        }
        for (h in hits.sortedByDescending { it.score }.take(limit)) {
            val body = h.text.replaceFirst(FRONT_MATTER, "").trim()
            val lower = body.lowercase()
            val at = words.map { lower.indexOf(it) }.filter { it >= 0 }.minOrNull() ?: 0
            val start = body.lastIndexOf('\n', at - 1).let { if (it < 0) 0 else it + 1 }.coerceAtLeast(at - 300).coerceAtLeast(0)
            val snippet = body.substring(start, (at + 500).coerceAtMost(body.length)).trim()
            cursor.addRow(arrayOf<Any?>(titleOf(h.note.name, h.text), h.note.path, h.note.updated, snippet, body.take(3000)))
        }
        return cursor
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
