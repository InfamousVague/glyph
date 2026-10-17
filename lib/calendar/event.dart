/// An event as the app keeps it, whichever calendar it came from (docs/CALENDAR.md): an iCal address's (ics.dart) or
/// Google's (google.dart). Kept on this device as JSON ([CalendarEvent.toJson]) and read by a query as a
/// [QueryEvent] (lib/core/query/records.dart).
library;

import 'package:flutter/foundation.dart';

import '../core/days.dart' show isoDay;
import '../core/query/records.dart' show QueryEvent;

@immutable
class CalendarEvent {
  const CalendarEvent({required this.id, required this.source, required this.calendar, required this.title, required this.start, required this.end, required this.allDay, this.location});

  /// One instance's key within its source: its UID and its start, or Google's own id.
  final String id;

  /// Where it came from: `ical:<the address's id>` or `google:<the calendar's id>`.
  final String source;

  /// The calendar's name, as it says it.
  final String calendar;
  final String title;

  /// A time's moment; an all-day event's first day at midnight on this device's clock. [end] is where it stops and
  /// not in it.
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;

  /// As a query reads it.
  QueryEvent get query => QueryEvent(id: '$source/$id', title: title, start: start, end: end, allDay: allDay, location: location, calendar: calendar);

  /// The days it is on, on this device's clock: its first and its last.
  String get firstDay => query.startDay;
  String get lastDay => query.endDay;

  /// Whether it is on [day] (`YYYY-MM-DD`).
  bool isOn(String day) => firstDay.compareTo(day) <= 0 && lastDay.compareTo(day) >= 0;

  /// An all-day event's days as `YYYY-MM-DD`, a timed one's moments in UTC.
  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        'calendar': calendar,
        'title': title,
        'allDay': allDay,
        'start': allDay ? isoDay(start) : start.toUtc().toIso8601String(),
        'end': allDay ? isoDay(end) : end.toUtc().toIso8601String(),
        if (location != null) 'location': location,
      };

  /// Null for anything that is not an event as [toJson] writes one.
  static CalendarEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], source = raw['source'], title = raw['title'], start = raw['start'], end = raw['end'];
    if (id is! String || source is! String || title is! String || start is! String || end is! String) return null;
    final allDay = raw['allDay'] == true;
    DateTime? read(String text) {
      final at = DateTime.tryParse(text);
      if (at == null) return null;
      return allDay ? DateTime(at.year, at.month, at.day) : at.toUtc();
    }

    final begins = read(start), ends = read(end);
    if (begins == null || ends == null) return null;
    final calendar = raw['calendar'], location = raw['location'];
    return CalendarEvent(
      id: id,
      source: source,
      calendar: calendar is String ? calendar : '',
      title: title,
      start: begins,
      end: ends,
      allDay: allDay,
      location: location is String && location.isNotEmpty ? location : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.id == id &&
      other.source == source &&
      other.calendar == calendar &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.location == location;

  @override
  int get hashCode => Object.hash(id, source, calendar, title, start, end, allDay, location);

  @override
  String toString() => 'CalendarEvent($source/$id, $title, $start → $end${allDay ? ', all day' : ''})';
}

/// [events] in the order a day lists them: the soonest first, a day's before the day's hours, then by title.
List<CalendarEvent> inDayOrder(Iterable<CalendarEvent> events) {
  final list = [...events];
  list.sort((a, b) {
    final day = a.firstDay.compareTo(b.firstDay);
    if (day != 0) return day;
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final at = a.start.compareTo(b.start);
    return at != 0 ? at : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return list;
}

/// The events on [day], in [inDayOrder].
List<CalendarEvent> eventsOn(Iterable<CalendarEvent> events, String day) => inDayOrder(events.where((event) => event.isOn(day)));
