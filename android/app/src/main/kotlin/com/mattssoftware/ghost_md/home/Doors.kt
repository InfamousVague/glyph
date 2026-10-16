package com.mattssoftware.ghost_md.home

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.mattssoftware.ghost_md.MainActivity

/**
 * The ways into the app from outside its window, each a `ghostmd://` link handed to the one activity, which keeps it
 * until the app asks (AppLinks.kt) and the app follows (lib/home_screen/phone_entries.dart):
 *
 * - `ghostmd://new`, a new note with the keyboard up: the icon's New note, Quick note's pen, the tile;
 * - `ghostmd://voice`, a new note being recorded: the microphone opens on that tap and not before;
 * - `ghostmd://today`, `ghostmd://search`: the icon's Today's note and Search;
 * - `ghostmd://note/<id>?line=12&find=…`, a note at a line: a reminder, a Today or Pinned row, a recent note.
 *
 * Every intent names the activity, so a phone with the Tauri app on it too (which takes the same scheme) is never
 * asked which app opens it.
 */
object Doors {
  const val NEW = "ghostmd://new"
  const val VOICE = "ghostmd://voice"
  const val TODAY = "ghostmd://today"
  const val SEARCH = "ghostmd://search"

  /** A note, at [line] (counting from 1; 0 where it was left) with the item's first words to find it by. */
  fun noteAt(note: String, line: Int = 0, find: String = ""): String {
    val built = Uri.Builder().scheme("ghostmd").authority("note").appendPath(note).appendQueryParameter("line", line.toString())
    if (find.isNotEmpty()) built.appendQueryParameter("find", find.take(80))
    return built.build().toString()
  }

  /** The activity, opened at [link]. */
  fun intent(context: Context, link: String): Intent = Intent(Intent.ACTION_VIEW, Uri.parse(link), context, MainActivity::class.java)
    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

  /** [intent] as a press: a widget's, a notification's, the tile's. [code] tells two of one link apart. */
  fun press(context: Context, link: String, code: Int = link.hashCode()): PendingIntent =
    PendingIntent.getActivity(context, code, intent(context, link), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
}
