package com.mattssoftware.ghost_md.home

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.LayoutInflater
import android.view.View
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.mattssoftware.ghost_md.R
import java.util.Locale

/**
 * Choosing what A note or A folder shows (docs/WIDGETS_ANDROID.md, "Twelve"): the widget's configuration, opened by
 * the launcher as the widget is placed, from Android 12 by its Reconfigure, and by a tap on one whose note or folder
 * is gone. A plain list in the widgets' own look (layout/ghost_w_pick.xml, the home page's rows): for A note, the
 * notes the app last handed over (`picks`: the pinned first, then the ones written in last), with a field to find one
 * by its name; for A folder, every workspace and folder, an organization's under its name ("Acme › Design", as the
 * app lists them). A tap keeps the choice (HomeScreen.choose), draws the widget, and closes.
 *
 * Exported, as the launcher must reach it; what it can do is choose which of the person's own notes their own widget
 * shows, which is nothing to anyone else. Nothing is written to a note.
 */
class WidgetPick : Activity() {
  private var id = AppWidgetManager.INVALID_APPWIDGET_ID
  private var folders = false

  override fun onCreate(saved: Bundle?) {
    val dark = when (HomeScreen.look(this)) {
      "light" -> false
      "system" -> (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES
      else -> true
    }
    // The window in the look the widgets are drawn in: its plain side, then the look's colours over it.
    setTheme(if (dark) android.R.style.Theme_Material_NoActionBar else android.R.style.Theme_Material_Light_NoActionBar)
    theme.applyStyle(if (dark) R.style.GhostW_Theme_Dark else R.style.GhostW_Theme_Light, true)
    super.onCreate(saved)
    id = intent?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID) ?: AppWidgetManager.INVALID_APPWIDGET_ID
    // Left without a choice, the launcher takes a newly placed widget away again.
    setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
    if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return finish()
    folders = WidgetKind.of(this, id) == WidgetKind.FOLDER
    val paper = colour(R.attr.ghost_w_paper)
    window.setBackgroundDrawable(ColorDrawable(paper))
    @Suppress("DEPRECATION")
    window.statusBarColor = paper
    @Suppress("DEPRECATION")
    window.navigationBarColor = paper
    if (!dark) window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
    setContentView(R.layout.ghost_w_pick)
    findViewById<TextView>(R.id.ghost_w_pick_title).setText(if (folders) R.string.ghost_widget_pick_folder else R.string.ghost_widget_pick_note)
    findViewById<TextView>(R.id.ghost_w_pick_words).text = if (folders) "The widget shows its notes, and its + files a new note there." else "The widget shows its name and first lines, and ticks its to-dos."
    val find = findViewById<EditText>(R.id.ghost_w_pick_find)
    find.visibility = if (folders) View.GONE else View.VISIBLE
    find.addTextChangedListener(object : TextWatcher {
      override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
      override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
      override fun afterTextChanged(s: Editable?) = list(s?.toString() ?: "")
    })
    list("")
  }

  private fun colour(attr: Int): Int {
    val value = TypedValue()
    theme.resolveAttribute(attr, value, true)
    return value.data
  }

  /** The rows, those whose name has [words] in it; the one chosen now first marked by the second ink's name. */
  private fun list(words: String) {
    val into = findViewById<LinearLayout>(R.id.ghost_w_pick_list)
    into.removeAllViews()
    val now = System.currentTimeMillis()
    val chosen = HomeScreen.chosenFor(this, id)
    val wanted = words.trim().lowercase(Locale.ROOT)
    val rows: List<Triple<String, Pair<String, String>, Int>> = if (folders) {
      HomeData.folders(HomeScreen.kept(this, "folders")).orEmpty().map { Triple(it.id, it.path to if (it.count == 1) "1 note" else "${it.count} notes", R.drawable.ghost_w_ic_folder) }
    } else {
      HomeData.notes(HomeScreen.kept(this, "picks")).map { note ->
        Triple(note.id, note.title to listOf(if (note.pinned) "Pinned" else "", WidgetViews.ago(this, note.updated, now)).filter { it.isNotEmpty() }.joinToString(" · "), WidgetViews.markOf(note.kind))
      }
    }.filter { wanted.isEmpty() || it.second.first.lowercase(Locale.ROOT).contains(wanted) }
    if (rows.isEmpty()) {
      val none = LayoutInflater.from(this).inflate(R.layout.ghost_w_eyebrow, into, false)
      none.findViewById<TextView>(R.id.ghost_w_eyebrow_words).text = when {
        wanted.isNotEmpty() -> "No note by that name"
        folders -> "No folders yet: open Ghost.md first"
        else -> "No notes yet: open Ghost.md first"
      }
      into.addView(none)
      return
    }
    for ((what, named, mark) in rows) {
      val row = LayoutInflater.from(this).inflate(R.layout.ghost_w_note_row, into, false)
      row.findViewById<ImageView>(R.id.ghost_w_note_mark).setImageResource(mark)
      row.findViewById<TextView>(R.id.ghost_w_note_title).text = named.first
      row.findViewById<TextView>(R.id.ghost_w_note_line).text = named.second
      row.findViewById<TextView>(R.id.ghost_w_note_when).text = if (what == chosen) "Shown" else ""
      row.contentDescription = named.first
      row.setOnClickListener { choose(what) }
      into.addView(row)
    }
  }

  private fun choose(what: String) {
    HomeScreen.choose(applicationContext, id, what)
    setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
    finish()
  }
}
