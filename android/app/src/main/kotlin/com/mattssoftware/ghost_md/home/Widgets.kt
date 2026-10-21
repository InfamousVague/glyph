package com.mattssoftware.ghost_md.home

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.mattssoftware.ghost_md.reminders.GhostBackground

/**
 * The home screen's four widgets (docs/WIDGETS_ANDROID.md): Voice note, To-dos, Calendar and Recent notes, RemoteViews in the
 * app's Glacier look (WidgetViews.kt), no Compose, no collection service, nothing running. Each draws what the app
 * last handed over (HomeScreen.kt) and opens the app by a `ghostmd://` link (Doors.kt).
 *
 * One provider for each, made medium (four cells by two) and resized to large (four by four) or anything between:
 * what it shows is worked out from the size it is, so a widget made taller shows more, and one on its side or on the
 * Fold's other screen is drawn for that screen (Android 12's sizes, WidgetViews.kt). One entry each in the picker
 * rather than a medium and a large: a launcher resizes a widget in place, and two entries would be eight Ghost.md
 * widgets to choose among for four things.
 *
 * The three before them, Quick note, Today and Pinned notes, keep their classes so that a widget already on a home
 * screen keeps working: each is now the new widget it became (Quick note the Voice note, Today the To-dos, Pinned
 * notes the Recent notes), hidden from the picker (res/xml/ghost_widget_quick_note.xml and the others).
 */
enum class WidgetKind(vararg val providers: Class<out AppWidgetProvider>) {
  VOICE(VoiceNoteWidget::class.java, QuickNoteWidget::class.java),
  TODOS(TodosWidget::class.java, TodayWidget::class.java),
  CALENDAR(CalendarWidget::class.java),
  NOTES(RecentNotesWidget::class.java, PinnedWidget::class.java);

  /** Every widget of this kind on any home screen, the old class's among them. */
  fun ids(context: Context): IntArray = providers.flatMap { HomeScreen.ids(context, it).toList() }.toIntArray()

  fun drawAll(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    for (id in ids(context)) WidgetViews.draw(context, manager, id, this)
  }
}

/** A widget of [kind]: drawn when placed, resized, and asked; the clock armed while any is on a home screen. */
abstract class GhostWidget(private val kind: WidgetKind) : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) WidgetViews.draw(context, manager, id, kind)
    HomeScreen.armClock(context)
  }

  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) = WidgetViews.draw(context, manager, id, kind)

  override fun onEnabled(context: Context) = HomeScreen.armClock(context)

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
open class VoiceNoteWidget : GhostWidget(WidgetKind.VOICE)

/** To-dos: the open to-dos from every note, Overdue, Today, Later and Someday, each ticked in place. */
open class TodosWidget : GhostWidget(WidgetKind.TODOS)

/** Calendar: today's and the week's events beside the to-dos due, or where to turn the Calendar plugin on. */
class CalendarWidget : GhostWidget(WidgetKind.CALENDAR)

/** Recent notes: the notes written in last, each a tap from where it was left. */
open class RecentNotesWidget : GhostWidget(WidgetKind.NOTES)

/** Quick note, before the four: placed ones are the Voice note now. Hidden from the picker. */
class QuickNoteWidget : VoiceNoteWidget()

/** Today, before the four: placed ones are the To-dos now. Hidden from the picker. */
class TodayWidget : TodosWidget()

/** Pinned notes, before the four: placed ones are the Recent notes now. Hidden from the picker. */
class PinnedWidget : RecentNotesWidget()

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
