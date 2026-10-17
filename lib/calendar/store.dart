/// What this device keeps of the calendars (docs/CALENDAR.md): the events each one gave the last time it was read,
/// when that was and what went wrong, Google's access token and calendar list, and a Google sign-in in flight. All of
/// it under `glyph-` keys (lib/core/stored.dart), so a reset forgets it; none of it travels. Which calendars there are
/// is the account's (setup.dart).
library;

import '../core/stored.dart';
import 'event.dart';
import 'google.dart';

const String _eventsKey = 'glyph-calendar-events';
const String _statusKey = 'glyph-calendar-status';
const String _tokenKey = 'glyph-google-token';
const String _calendarsKey = 'glyph-google-calendars';
const String _signInKey = 'glyph-google-signin';

/// How the last read of one calendar went: when it was, and what went wrong, in words, where something did.
class SourceStatus {
  const SourceStatus({required this.at, this.problem});

  /// Milliseconds since the epoch.
  final int at;
  final String? problem;

  Map<String, Object?> toJson() => {'at': at, if (problem != null) 'problem': problem};

  static SourceStatus? fromJson(Object? raw) {
    if (raw is! Map || raw['at'] is! num) return null;
    final problem = raw['problem'];
    return SourceStatus(at: (raw['at'] as num).toInt(), problem: problem is String ? problem : null);
  }
}

/// A Google sign-in started and not yet collected.
typedef GoogleFlight = ({String state, String verifier, int at});

/// This device's calendar memory, over [kept] (the app's [stored] when left out, asked each time, since the root
/// puts the device's in place after launch).
class CalendarKept {
  CalendarKept([Stored Function()? kept]) : _kept = kept ?? (() => stored);

  final Stored Function() _kept;

  /// Every source's events, by source (`ical:<id>`, `google:<id>`).
  Map<String, List<CalendarEvent>> events() {
    final raw = _kept().read<Object?>(_eventsKey, null);
    if (raw is! Map) return {};
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String && value is List) key: [for (final each in value) ?CalendarEvent.fromJson(each)],
    };
  }

  void setEvents(String source, List<CalendarEvent> list) {
    final all = events()..[source] = list;
    _write(all);
  }

  /// Forgets [sources]' events and how their reads went.
  void drop(Iterable<String> sources) {
    final gone = sources.toSet();
    if (gone.isEmpty) return;
    final all = events();
    final status = statuses();
    if (!gone.any((source) => all.containsKey(source) || status.containsKey(source))) return;
    all.removeWhere((source, _) => gone.contains(source));
    status.removeWhere((source, _) => gone.contains(source));
    _write(all);
    _kept().write(_statusKey, {for (final MapEntry(:key, :value) in status.entries) key: value.toJson()});
  }

  void _write(Map<String, List<CalendarEvent>> all) => _kept().write(_eventsKey, {
        for (final MapEntry(:key, :value) in all.entries) key: [for (final event in value) event.toJson()],
      });

  Map<String, SourceStatus> statuses() {
    final raw = _kept().read<Object?>(_statusKey, null);
    if (raw is! Map) return {};
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String && SourceStatus.fromJson(value) != null) key: SourceStatus.fromJson(value)!,
    };
  }

  void setStatus(String source, SourceStatus status) {
    final all = statuses()..[source] = status;
    _kept().write(_statusKey, {for (final MapEntry(:key, :value) in all.entries) key: value.toJson()});
  }

  GoogleTokens? get tokens => GoogleTokens.fromJson(_kept().read<Object?>(_tokenKey, null));
  set tokens(GoogleTokens? next) => _kept().write(_tokenKey, next?.toJson());

  List<GoogleCalendarInfo> get calendars {
    final raw = _kept().read<Object?>(_calendarsKey, null);
    return [
      if (raw is List)
        for (final each in raw) ?GoogleCalendarInfo.fromJson(each),
    ];
  }

  set calendars(List<GoogleCalendarInfo> next) => _kept().write(_calendarsKey, next.isEmpty ? null : [for (final each in next) each.toJson()]);

  GoogleFlight? get flight {
    final raw = _kept().read<Object?>(_signInKey, null);
    if (raw is! Map || raw['state'] is! String || raw['verifier'] is! String || raw['at'] is! num) return null;
    return (state: raw['state'] as String, verifier: raw['verifier'] as String, at: (raw['at'] as num).toInt());
  }

  set flight(GoogleFlight? next) => _kept().write(_signInKey, next == null ? null : {'state': next.state, 'verifier': next.verifier, 'at': next.at});
}
