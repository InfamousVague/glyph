/// Today's events on the home page (docs/CALENDAR.md, "Where events show"): the calendars' events on today's date, at
/// the head of the page under one heading, Today, each a line of its hours (or All day), its title, and where it is.
/// Drawn only when there are any; the port's own, 2026-10-17.
///
/// The events are the calendars' (lib/calendar/calendar.dart), handed in as they change. An event is the calendar's, so
/// a line opens nothing of its own; but a meeting that has its notes here (a meeting Ghost was in, filed by lib/meet,
/// or a note made in it and named after it) opens them: [meetingNoteOf] finds the note, and the line wears a mark
/// (Matt, 2026-10-19: "at the top of the app there are voice recordings for meetings from today but I cant click any
/// of them to open the meeting notes").
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../calendar/event.dart';
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle;
import 'home_organizations.dart' show HomeHeading;
import 'home_text.dart';

/// What an event's line says first: its hours on this device's clock, `09:30–10:00`, or All day.
String eventHours(CalendarEvent event) => event.query.hours ?? 'All day';

/// How long before an event starts, and after it ends, a note made then can still be its notes: Ghost joins two
/// minutes early, and a note is often started a little before or finished after.
const Duration meetingNoteSlack = Duration(minutes: 30);

/// The note that is [event]'s meeting notes, or null: one named as the event is (its title, any case), made while
/// it ran or within [meetingNoteSlack] of it; the one with a recording first, then the newest. An all-day event has
/// none: a day is no meeting.
Note? meetingNoteOf(CalendarEvent event, Iterable<Note> notes) {
  if (event.allDay) return null;
  final name = event.title.trim().toLowerCase();
  if (name.isEmpty) return null;
  final from = event.start.subtract(meetingNoteSlack).millisecondsSinceEpoch;
  final to = event.end.add(meetingNoteSlack).millisecondsSinceEpoch;
  Note? best;
  for (final note in notes) {
    if (note.createdAt < from || note.createdAt > to) continue;
    if (noteTitle(note.body).trim().toLowerCase() != name) continue;
    final taped = (note.recordingMs ?? 0) > 0, bestTaped = (best?.recordingMs ?? 0) > 0;
    if (best == null || (taped && !bestTaped) || (taped == bestTaped && note.createdAt > best.createdAt)) best = note;
  }
  return best;
}

class HomeTodayEvents extends StatelessWidget {
  const HomeTodayEvents({super.key, required this.events, this.notes = const [], this.onOpen});

  /// Today's, in the order a day lists them (lib/calendar/event.dart `eventsOn`).
  final List<CalendarEvent> events;

  /// The notes a meeting's notes are looked for in ([meetingNoteOf]), and what opens one; without [onOpen] no line
  /// opens anything.
  final List<Note> notes;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    final rule = BorderSide(color: t.color('app-rule'), width: 1 / MediaQuery.devicePixelRatioOf(context));
    return Padding(
      // As the organizations' block stands under the search.
      padding: EdgeInsets.only(top: t.space(3)),
      child: Column(
        key: const ValueKey('home-today-events'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeHeading(
            mark: AppIcon(Lucide.calendarDays, size: 15, color: t.color('app-ink-2')),
            words: 'Today',
            count: events.length,
          ),
          SizedBox(height: t.space(2)),
          for (final (index, event) in events.indexed)
            _line(context, index, event, onOpen == null ? null : meetingNoteOf(event, notes), rule),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, int index, CalendarEvent event, Note? notesOf, BorderSide rule) {
    final t = context.tokens;
    final sm = t.fontSize('sm'), md = t.fontSize('md');
    final said = [eventHours(event), event.title, ?event.location, if (notesOf != null) 'open its notes'].join(', ');
    final Widget line = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: index == 0 ? rule : BorderSide.none, bottom: rule),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space(2)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: 7.5 * sm,
              child: Text(
                eventHours(event),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: tabular(pageText(t, sm, color: t.color('app-ink-3'))),
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: event.title,
                      style: pageText(t, md, color: t.color('app-ink')),
                    ),
                    if (event.location != null)
                      TextSpan(
                        text: '  ${event.location}',
                        style: pageText(t, sm, color: t.color('app-ink-3')),
                      ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // A meeting with its notes here: the notes' mark at the line's end, and the line opens them.
            if (notesOf != null) ...[
              SizedBox(width: t.space(2)),
              AppIcon(Lucide.fileText, size: 14, color: t.color('app-ink-3')),
            ],
          ],
        ),
      ),
    );
    if (notesOf == null) return Semantics(label: said, excludeSemantics: true, child: line);
    return GlacierPressable(
      key: ValueKey('home-event-notes-${notesOf.id}'),
      onPressed: () => onOpen!(notesOf.id),
      semanticLabel: said,
      builder: (context, state) => GlacierFocusRing(visible: state.focused, radius: 0, child: line),
    );
  }
}
