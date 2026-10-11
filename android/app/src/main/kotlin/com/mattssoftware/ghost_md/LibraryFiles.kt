package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.DocumentsContract
import android.util.Log
import com.mattssoftware.glyph.files.LibraryDocuments
import com.mattssoftware.glyph.files.LibraryRoot

/**
 * The notes' folder opened in the phone's Files app, for the sidebar's Browse files (lib/core/library_files.dart,
 * `browseFiles` on `ghost_md/files`; FilesBridge.kt). What the Tauri activity's `GlyphHost.browseFiles` was
 * (../glyph MainActivity.kt, native generation 18), line for line: the Files app shown at the app's place in it
 * (files/LibraryDocuments.kt), or where a phone's Files app won't open a place by itself, the system's file browser
 * starting there.
 *
 * What differs: nothing but who asks. The page called a `@JavascriptInterface` from its own thread; a method
 * channel's call arrives on the main thread already, and `runOnUiThread` runs it there at once.
 */
object LibraryFiles {
  private const val TAG = "GhostFiles"

  fun browse(activity: Activity) {
    // The library in a folder of the person's (files/LibraryTree.kt): that folder, where the notes are, in the
    // system's file browser. The app's own place is not listed then (files/LibraryDocuments.kt).
    val tree = LibraryRoot.chosenTree(activity.applicationContext)
    if (tree != null) {
      activity.runOnUiThread {
        val start = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        try {
          activity.startActivity(
            Intent(Intent.ACTION_OPEN_DOCUMENT)
              .addCategory(Intent.CATEGORY_OPENABLE)
              .setType("*/*")
              .putExtra(DocumentsContract.EXTRA_INITIAL_URI, start),
          )
        } catch (e: ActivityNotFoundException) {
          Log.w(TAG, "no file browser to show the library's folder in", e)
        }
      }
      return
    }
    activity.runOnUiThread {
      val authority = LibraryDocuments.authority(activity.packageName)
      val root = DocumentsContract.buildRootUri(authority, LibraryDocuments.ROOT_ID)
      try {
        activity.startActivity(
          Intent(Intent.ACTION_VIEW)
            .setDataAndType(root, DocumentsContract.Root.MIME_TYPE_ITEM)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
      } catch (notOpened: ActivityNotFoundException) {
        val start = DocumentsContract.buildDocumentUri(authority, LibraryDocuments.rootDocumentId())
        try {
          activity.startActivity(
            Intent(Intent.ACTION_OPEN_DOCUMENT)
              .addCategory(Intent.CATEGORY_OPENABLE)
              .setType("*/*")
              .putExtra(DocumentsContract.EXTRA_INITIAL_URI, start),
          )
        } catch (e: ActivityNotFoundException) {
          Log.w(TAG, "no file browser to show the library in", e)
        }
      }
    }
  }
}
