package com.mattssoftware.ghost_md.home

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.mattssoftware.ghost_md.reminders.GhostBackground

/**
 * The home screen's twelve widgets (docs/WIDGETS_ANDROID.md), RemoteViews in the app's Glacier look (WidgetViews.kt,
 * MoreWidgetViews.kt), no Compose, no collection service, nothing running. Each draws what the app last handed over
 * (HomeScreen.kt) and opens the app by a `ghostmd://` link (Doors.kt):
 *
 * - the four first: Voice note, To-dos, Calendar and Recent notes;
 * - and eight more (Matt, 2026-10-21: "Please add more widgets and sizes shoot for 12 widgets"): Quick capture,
 *   Pinned notes, Today, Search, A note and A folder (each set to one when placed: WidgetPick.kt), Ask AI and Next up.
 *
 * One provider for each, placed at the size its xml says (res/xml/ghost_widget_*.xml) and resized to any other from
 * two cells by one: what it shows is worked out from the size it is (WidgetViews.Fit: a cell high, two cells across,
 * four by two, four by four, and wide on the opened Fold), so a widget made taller shows more, and one on its side or
 * on the Fold's other screen is drawn for that screen (Android 12's sizes). One entry each in the picker rather than
 * one for each size: a launcher resizes a widget in place, and twelve things in four sizes would be forty-eight.
 *
 * The three before the four, Quick note, Today and Pinned notes, keep their classes so that a widget already on a
 * home screen keeps working, hidden from the picker (res/xml/ghost_widget_quick_note.xml and the others): Quick note
 * is Quick capture now (it was a new note and a voice note), Pinned notes the Pinned notes again, and the old Today
 * (its to-dos due) the To-dos.
 */
enum class WidgetKind(vararg val providers: Class<out AppWidgetProvider>) {
  VOICE(VoiceNoteWidget::class.java),
  TODOS(TodosWidget::class.java, TodayWidget::class.java),
  CALENDAR(CalendarWidget::class.java),
  NOTES(RecentNotesWidget::class.java),
  QUICK(QuickCaptureWidget::class.java, QuickNoteWidget::class.java),
  PINNED(PinnedNotesWidget::class.java, PinnedWidget::class.java),
  TODAY(TodayNoteWidget::class.java),
  SEARCH(SearchWidget::class.java),
  NOTE(NoteWidget::class.java),
  FOLDER(FolderWidget::class.java),
  ASK(AskWidget::class.java),
  NEXT(NextUpWidget::class.java);

  /** Every widget of this kind on any home screen, the old class's among them. */
  fun ids(context: Context): IntArray = providers.flatMap { HomeScreen.ids(context, it).toList() }.toIntArray()

  fun drawAll(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    for (id in ids(context)) WidgetViews.draw(context, manager, id, this)
    if (this == NEXT) HomeScreen.armNext(context)
  }

  companion object {
    /** The kind a placed widget is, by its provider's class; null for one of another app's. */
    fun of(context: Context, id: Int): WidgetKind? {
      val provider = AppWidgetManager.getInstance(context).getAppWidgetInfo(id)?.provider?.className ?: return null
      return values().firstOrNull { kind -> kind.providers.any { it.name == provider } }
    }
  }
}

/** A widget of [kind]: drawn when placed, resized, and asked; the clock armed while any is on a home screen. */
abstract class GhostWidget(private val kind: WidgetKind) : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) WidgetViews.draw(context, manager, id, kind)
    HomeScreen.armClock(context)
    if (kind == WidgetKind.NEXT) HomeScreen.armNext(context)
  }

  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) = WidgetViews.draw(context, manager, id, kind)

  override fun onEnabled(context: Context) = HomeScreen.armClock(context)

  /** A widget taken off the home screen: what it was set to (A note's note, A folder's folder) goes with it. */
  override fun onDeleted(context: Context, ids: IntArray) {
    for (id in ids) HomeScreen.unchoose(context, id)
  }

  override fun onDisabled(context: Context) {
    if (!HomeScreen.anyPlaced(context)) HomeScreen.disarmClock(context)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    // The midnight the Today widget armed to itself before the four: it comes once more, to its class.
    if (intent.action == HomeScreen.ACTION_MIDNIGHT) WidgetClock.tick(context.applicationContext, midnight = true)
  }
}

/** Voice note: the big microphone, which records a voice note at once, and the last recordings. */
class VoiceNoteWidget : GhostWidget(WidgetKind.VOICE)

/** To-dos: the open to-dos from every note, Overdue, Today, Later and Someday, each ticked in place. */
open class TodosWidget : GhostWidget(WidgetKind.TODOS)

/** Calendar: today's and the week's events beside the to-dos due, or where to turn the Calendar plugin on. */
class CalendarWidget : GhostWidget(WidgetKind.CALENDAR)

/** Recent notes: the notes written in last, each a tap from where it was left. */
class RecentNotesWidget : GhostWidget(WidgetKind.NOTES)

/** Quick capture: the dock's round buttons for a new note, a voice note, a checklist and a scan, and more as it grows. */
open class QuickCaptureWidget : GhostWidget(WidgetKind.QUICK)

/** Pinned notes: the notes pinned to the top, in Recent notes' rows. */
open class PinnedNotesWidget : GhostWidget(WidgetKind.PINNED)

/** Today: today's note (Settings › Daily notes), its first lines, its to-dos ticked in place, and a pen to write in it. */
class TodayNoteWidget : GhostWidget(WidgetKind.TODAY)

/** Search: the home page's field, which opens the palette, over the notes written in last. */
class SearchWidget : GhostWidget(WidgetKind.SEARCH)

/** A note: one note, chosen as it is placed, its name and first lines, its to-dos ticked in place. */
class NoteWidget : GhostWidget(WidgetKind.NOTE)

/** A folder: one workspace or folder, chosen as it is placed, its notes, and a + that files a new note there. */
class FolderWidget : GhostWidget(WidgetKind.FOLDER)

/** Ask AI: Talk to Claude, the dock's orange microphone, and the chat; where Claude is off, where to turn it on. */
class AskWidget : GhostWidget(WidgetKind.ASK)

/** Next up: the one next thing, today's next event or the most pressing to-do, and when. */
class NextUpWidget : GhostWidget(WidgetKind.NEXT)

/** Quick note, before the four (a new note and a voice note): placed ones are Quick capture now. Hidden from the picker. */
class QuickNoteWidget : QuickCaptureWidget()

/** Today, before the four (the to-dos due): placed ones are the To-dos now. Hidden from the picker. */
class TodayWidget : TodosWidget()

/** Pinned notes, before the four: placed ones are the Pinned notes again. Hidden from the picker. */
class PinnedWidget : PinnedNotesWidget()


/**
 * The widgets' own clock (HomeScreen.armClock): at midnight every widget drawn again for the new day and the next
 * midnight armed; about every quarter hour, as the phone wakes, drawn again so the times they say are right. Not
 * exported: only this app's alarms reach it.
 */
class WidgetClock : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      HomeScreen.ACTION_MIDNIGHT -> tick(context.applicationContext, midnight = true)
      HomeScreen.ACTION_FRESHEN -> tick(context.applicationContext, midnight = false)
      HomeScreen.ACTION_NEXT -> WidgetKind.NEXT.drawAll(context.applicationContext)
    }
  }

  companion object {
    fun tick(context: Context, midnight: Boolean) {
      if (!HomeScreen.anyPlaced(context)) return HomeScreen.disarmClock(context)
      HomeScreen.redraw(context)
      if (midnight) HomeScreen.armClock(context)
    }
  }
}

/**
 * A to-do ticked on the To-dos widget: off the widgets at once (HomeScreen.ticked), then written into its note through
 * the app's library (GhostBackground.kt). Not exported: only the widget's own PendingIntent reaches it.
 */
class WidgetTicks : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != ACTION_TICK) return
    val parts = intent.data?.pathSegments ?: return
    if (parts.size != 2) return
    val note = parts[0]
    val line = parts[1].toIntOrNull() ?: return
    val words = intent.getStringExtra("words") ?: ""
    val app = context.applicationContext
    HomeScreen.ticked(app, note, line)
    GhostBackground.tick(app, note, line, words)
  }

  companion object {
    const val ACTION_TICK = "com.mattssoftware.ghost_md.home.TICK"
  }
}
