/// Today's events on the home page (docs/CALENDAR.md, "Where events show"): the calendars' events on today's date, at
/// the head of the page under one heading, Today, each a line of its hours (or All day), its title, and where it is.
/// Drawn only when there are any; the port's own, 2026-10-17.
///
/// The events are the calendars' (lib/calendar/calendar.dart), handed in as they change; an event is the calendar's,
/// so a line opens nothing.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../calendar/event.dart';
import 'home_organizations.dart' show HomeHeading;
import 'home_text.dart';

/// What an event's line says first: its hours on this device's clock, `09:30–10:00`, or All day.
String eventHours(CalendarEvent event) => event.query.hours ?? 'All day';

class HomeTodayEvents extends StatelessWidget {
  const HomeTodayEvents({super.key, required this.events});

  /// Today's, in the order a day lists them (lib/calendar/event.dart `eventsOn`).
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    final sm = t.fontSize('sm'), md = t.fontSize('md');
    final rule = BorderSide(color: t.color('app-rule'), width: 1 / MediaQuery.devicePixelRatioOf(context));
    return Padding(
      // As the organizations' block stands under the search.
      padding: EdgeInsets.only(top: t.space(3)),
      child: Column(
        key: const ValueKey('home-today-events'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeHeading(mark: AppIcon(Lucide.calendarDays, size: 15, color: t.color('app-ink-2')), words: 'Today', count: events.length),
          SizedBox(height: t.space(2)),
          for (final (index, event) in events.indexed)
            Semantics(
              label: [eventHours(event), event.title, ?event.location].join(', '),
              excludeSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border(top: index == 0 ? rule : BorderSide.none, bottom: rule)),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: t.space(2)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SizedBox(
                        width: 7.5 * sm,
                        child: Text(eventHours(event), maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: tabular(pageText(t, sm, color: t.color('app-ink-3')))),
                      ),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: event.title, style: pageText(t, md, color: t.color('app-ink'))),
                              if (event.location != null) TextSpan(text: '  ${event.location}', style: pageText(t, sm, color: t.color('app-ink-3'))),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
