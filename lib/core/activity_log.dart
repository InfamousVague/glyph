/// What this device's jobs did, by the day (docs/ACTIVITY.md, Tray: "then **Today** ("3 summaries, 12 banners, 40
/// notes synced, 1 failed"), then **Past 7 days** behind More").
///
/// Kept in the app's own stored settings on this device ([stored], `glyph-activity`), not in the preferences that
/// travel: each device counts what it did itself, and the tray shows another device's work live, never its log. It
/// is small on purpose: the counts of each day, today and the seven before it, and the last few jobs of each day as
/// rows ([ActivityLog.rowsADay]); an older day is let go as a new one begins, and a day keeps at most
/// [ActivityLog.talliesADay] different counts. A store that refuses is a log of this run only, as storage always is
/// (lib/core/stored.dart).
library;

import 'package:flutter/foundation.dart';

import 'background_jobs.dart';
import 'stored.dart';

/// One job as the log keeps it: enough for a row of Today.
@immutable
class LoggedJob {
  const LoggedJob({required this.title, required this.kind, required this.failed, required this.at, this.cause, this.tally, this.plugin});

  static LoggedJob? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'], kind = raw['kind'], at = raw['at'];
    if (title is! String || kind is! String || at is! num) return null;
    final k = JobKind.values.where((v) => v.name == kind).firstOrNull;
    if (k == null) return null;
    return LoggedJob(title: title, kind: k, failed: raw['failed'] == true, at: DateTime.fromMillisecondsSinceEpoch(at.toInt()), cause: raw['cause'] is String ? raw['cause'] as String : null, tally: raw['tally'] is String ? raw['tally'] as String : null, plugin: raw['plugin'] is String ? raw['plugin'] as String : null);
  }

  final String title;
  final JobKind kind;
  final bool failed;
  final DateTime at;
  final String? cause;

  /// What it counted for, in words: "12 banners".
  final String? tally;

  /// The plugin whose work it was ([Job.plugin]): its line in Today wears that plugin's mark.
  final String? plugin;

  Map<String, Object?> toJson() => {'title': title, 'kind': kind.name, if (failed) 'failed': true, 'at': at.millisecondsSinceEpoch, 'cause': ?cause, 'tally': ?tally, 'plugin': ?plugin};
}

/// One day's counts.
@immutable
class ActivityDay {
  const ActivityDay({required this.day, this.counts = const {}, this.failed = 0, this.rows = const []});

  static ActivityDay? fromJson(Object? raw) {
    if (raw is! Map || raw['day'] is! String) return null;
    final counts = <String, int>{};
    final c = raw['counts'];
    if (c is Map) {
      for (final entry in c.entries) {
        if (entry.key is String && entry.value is num) counts[entry.key as String] = (entry.value as num).toInt();
      }
    }
    final rows = raw['rows'] is List ? [for (final r in raw['rows'] as List) ?LoggedJob.fromJson(r)] : const <LoggedJob>[];
    return ActivityDay(day: raw['day'] as String, counts: counts, failed: raw['failed'] is num ? (raw['failed'] as num).toInt() : 0, rows: rows);
  }

  /// The local date, `2026-10-29`.
  final String day;

  /// How many of each thing, by `one|many` ("summary|summaries"), in the order first counted.
  final Map<String, int> counts;
  final int failed;

  /// Its last few jobs, newest first.
  final List<LoggedJob> rows;

  bool get isEmpty => counts.isEmpty && failed == 0 && rows.isEmpty;

  /// "3 summaries, 12 banners, 40 notes synced, 1 failed"; nothing for a quiet day.
  String get words => [
        for (final entry in counts.entries)
          if (entry.value > 0) JobTally(entry.key.split('|').first, entry.key.split('|').last, entry.value).words,
        if (failed > 0) '$failed failed',
      ].join(', ');

  Map<String, Object?> toJson() => {'day': day, if (counts.isNotEmpty) 'counts': counts, if (failed > 0) 'failed': failed, if (rows.isNotEmpty) 'rows': [for (final row in rows) row.toJson()]};
}

/// The local date of [at] as the log keys it.
String activityDayOf(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// This device's log (see the header).
class ActivityLog extends ChangeNotifier {
  ActivityLog({Stored Function()? store, DateTime Function()? clock})
      : _store = store ?? (() => stored),
        _clock = clock ?? DateTime.now;

  /// The key it is kept under.
  static const String key = 'glyph-activity';

  /// Today and the seven days before it.
  static const int days = 8;

  /// At most this many different counts a day, and this many rows.
  static const int talliesADay = 12;
  static const int rowsADay = 20;

  final Stored Function() _store;
  final DateTime Function() _clock;
  List<ActivityDay>? _days;

  List<ActivityDay> _read() => _days ??= _store().read<List<ActivityDay>>(key, const [], (raw) => raw is List ? [for (final d in raw) ?ActivityDay.fromJson(d)] : null);

  /// The kept days, newest first, only those within [days] of today.
  List<ActivityDay> get kept {
    final today = _clock();
    final oldest = activityDayOf(DateTime(today.year, today.month, today.day - (days - 1)));
    return [for (final d in _read()) if (d.day.compareTo(oldest) >= 0) d];
  }

  /// Today's counts.
  ActivityDay get today {
    final key = activityDayOf(_clock());
    return kept.where((d) => d.day == key).firstOrNull ?? ActivityDay(day: key);
  }

  /// The seven days before today that did anything, newest first.
  List<ActivityDay> get past {
    final key = activityDayOf(_clock());
    return [for (final d in kept) if (d.day != key && !d.isEmpty) d];
  }

  /// Counts [job], which has just ended: its tally on the day it ended, a failure as a failure, and a row.
  void record(Job job) {
    if (!job.here) return;
    final at = job.endedAt ?? _clock();
    final key = activityDayOf(at);
    final all = kept;
    final had = all.where((d) => d.day == key).firstOrNull ?? ActivityDay(day: key);
    final counts = {...had.counts};
    final tally = job.tally;
    if (tally != null && tally.count > 0) {
      final name = '${tally.one}|${tally.many}';
      if (counts.containsKey(name) || counts.length < talliesADay) counts[name] = (counts[name] ?? 0) + tally.count;
    }
    final failed = job.state == JobState.failed;
    // A sync pass is a count, never a row: forty of them would push every summary off the day.
    final row = job.kind == JobKind.sync && !failed ? null : LoggedJob(title: job.title, kind: job.kind, failed: failed, at: at, cause: failed ? job.cause : null, tally: tally?.words, plugin: job.plugin);
    final next = ActivityDay(day: key, counts: counts, failed: had.failed + (failed ? 1 : 0), rows: [?row, ...had.rows].take(rowsADay).toList());
    final days = [next, for (final d in all) if (d.day != key) d]..sort((a, b) => b.day.compareTo(a.day));
    _days = days.take(ActivityLog.days).toList();
    _store().write(ActivityLog.key, [for (final d in _days!) d.toJson()]);
    notifyListeners();
  }

  /// Forgets it all.
  void clear() {
    _days = const [];
    _store().write(key, null);
    notifyListeners();
  }
}
