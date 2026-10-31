/// When a ticket's status changed, read from its versions (lib/core/versions_file.dart): what a cycle's burndown counts
/// down by and a stale ticket's days are counted from (Matt, 2026-10-31; docs/TICKETS.md). A small reader of its own,
/// by design: the ticket history another piece of work is building is the person's to read, a list of who changed
/// what; this needs two days and no more, the day a ticket last changed status and the day it was finished, so it
/// reads only each version's `status:` and the moment it was kept.
///
/// A note keeps versions where it is an organization's, unless that is switched off, or where its More sheet has
/// switched them on (lib/core/versions_record.dart), so a team's tickets have them and a person's own may not. Where
/// a ticket has none, what is said falls back on its own words: the `status-since:` and `done:` days written in its
/// front matter as it moved (lib/core/properties.dart `withStatus`; `done:` is also what Obsidian Tasks writes a
/// finished to-do's day under), else the day it was last changed, which a checkout or a restore resets. Each answer says where it came from,
/// so the burndown can say when it is the last change it counted by.
///
/// [TicketHistory] holds what has been read, by note id, and reads the rest when asked: a run of a query asks
/// synchronously, is answered with what is held, and the notes it asked about are read for the next run, which the
/// screen is told of ([TicketHistory.addListener]). Only the tickets a burndown or an aging mark asks about are ever
/// read.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../days.dart' show isIsoDay, isoDay;
import '../front_matter.dart' show frontMatterValue;
import '../item_syntax.dart' show jsTrim;
import '../properties.dart' show StatusCategory, statusCategory, statusSinceKey;

/// One change: from [day] on, the ticket's status was [status] (null for none).
@immutable
class StatusChange {
  const StatusChange({required this.day, required this.status});
  final String day;
  final String? status;

  @override
  bool operator ==(Object other) => other is StatusChange && other.day == day && other.status == status;

  @override
  int get hashCode => Object.hash(day, status);

  @override
  String toString() => 'StatusChange($day: $status)';
}

/// The status in a version's words, as written; null for none.
String? _statusIn(String text) {
  final said = frontMatterValue(text, 'status');
  final clean = said == null ? '' : jsTrim(said);
  return clean.isEmpty ? null : clean;
}

/// Each change of status among [versions] (when each was kept, in ms, and its words), oldest first: the first
/// version's status, then each one that differs from the one before, in any case and spacing.
List<StatusChange> statusChanges(Iterable<({int at, String text})> versions) {
  final ordered = [...versions]..sort((a, b) => a.at.compareTo(b.at));
  final changes = <StatusChange>[];
  String? last;
  var first = true;
  for (final version in ordered) {
    final status = _statusIn(version.text);
    final same = !first && (status ?? '').toLowerCase() == (last ?? '').toLowerCase();
    first = false;
    if (same) continue;
    last = status;
    changes.add(StatusChange(day: isoDay(DateTime.fromMillisecondsSinceEpoch(version.at)), status: status));
  }
  return changes;
}

/// Where a day was read from.
enum HistorySource {
  /// The ticket's versions.
  versions,

  /// A day written in its front matter (`status-since:`, `done:`).
  written,

  /// The day it was last changed, for want of either.
  changed,
}

/// A day, and where it was read from.
typedef HistoryDay = ({String day, HistorySource source});

/// The day [status] began, by [changes]: the day of the last change into it, where the ticket's status now is that.
/// Null where the changes do not end on it (the versions are behind the note).
String? sinceIn(List<StatusChange> changes, String? status) {
  if (changes.isEmpty) return null;
  final last = changes.last;
  return (last.status ?? '').toLowerCase() == (status ?? '').toLowerCase() ? last.day : null;
}

/// The day a ticket was finished, by [changes]: the first day of its last run of finished statuses, where it is
/// finished still. Null where it is not, or the changes say otherwise.
String? doneIn(List<StatusChange> changes, List<String> workflow) {
  String? day;
  for (final change in changes) {
    final done = statusCategory(change.status, workflow) == StatusCategory.done;
    if (done) {
      day ??= change.day;
    } else {
      day = null;
    }
  }
  return day;
}

/// The keys a finished day may be written under, the first that holds one counting.
const List<String> doneKeys = ['done', 'completed', 'resolved', 'closed'];

/// The keys a day of a ticket's past may be written under: [doneKeys] and the day its status was taken
/// (`status-since:`, lib/core/properties.dart `withStatus`), which a query's record carries for history.dart to read.
const List<String> historyKeys = [statusSinceKey, ...doneKeys];

/// The day a ticket's status was taken, written in its front matter by `withStatus`: `status-since: 2026-11-04`.
String? writtenSince(String body) {
  final said = jsTrim(frontMatterValue(body, statusSinceKey) ?? '');
  return isIsoDay(said) ? said : null;
}

/// A finished day written in a ticket's front matter: `done: 2026-11-04`.
String? writtenDone(String body) {
  for (final key in doneKeys) {
    final said = jsTrim(frontMatterValue(body, key) ?? '');
    if (isIsoDay(said)) return said;
  }
  return null;
}

/// What a planning question asks of a ticket's past.
abstract interface class StatusPast {
  /// The changes read for note [id]; null where none are held yet (or none can be).
  List<StatusChange>? changesOf(String id);
}

/// No past at all: every answer falls back on the ticket's words.
class NoPast implements StatusPast {
  const NoPast();
  @override
  List<StatusChange>? changesOf(String id) => null;
}

/// The day a ticket of [body], with status [status] where it now stands, took that status: its versions' last change,
/// else its `status-since:` (written when it moved, lib/core/properties.dart `withStatus`), else the day it was last
/// changed ([updated]).
HistoryDay statusSince(StatusPast past, String id, String? status, {required String updated, String body = ''}) {
  final changes = past.changesOf(id);
  final day = changes == null ? null : sinceIn(changes, status);
  if (day != null) return (day: day, source: HistorySource.versions);
  final written = writtenSince(body);
  if (written != null) return (day: written, source: HistorySource.written);
  return (day: updated, source: HistorySource.changed);
}

/// The day a finished ticket was finished: its versions', else its `done:`, else the day it was last changed. Null
/// for a ticket not finished.
HistoryDay? finishedOn(StatusPast past, String id, String body, String? status, List<String> workflow, {required String updated}) {
  if (statusCategory(status, workflow) != StatusCategory.done) return null;
  final changes = past.changesOf(id);
  final read = changes == null ? null : doneIn(changes, workflow);
  if (read != null) return (day: read, source: HistorySource.versions);
  final written = writtenDone(body);
  if (written != null) return (day: written, source: HistorySource.written);
  return (day: updated, source: HistorySource.changed);
}

/// A note's versions, as the screen reads them: when each was kept and its words, oldest or newest first.
typedef VersionsReader = Future<List<({int at, String text})>> Function(String id);

/// The tickets' changes of status read so far, by note id, and the reading of the rest as they are asked about.
class TicketHistory extends ChangeNotifier implements StatusPast {
  TicketHistory(this._read, {this.batch = 8});

  final VersionsReader _read;

  /// How many notes are read at once.
  final int batch;

  final Map<String, List<StatusChange>> _held = {};
  final Set<String> _asked = {};
  final List<String> _queue = [];
  bool _reading = false;

  /// What is held for [id]; asking for one not held reads it, and the listeners are told once it is.
  @override
  List<StatusChange>? changesOf(String id) {
    final held = _held[id];
    if (held != null || id.isEmpty) return held;
    if (_asked.add(id)) {
      _queue.add(id);
      if (!_reading) scheduleMicrotask(_readQueue);
    }
    return null;
  }

  /// Note [id]'s versions changed (a version kept, or sync brought some): read again when next asked.
  void forget(String id) {
    _held.remove(id);
    _asked.remove(id);
  }

  /// Held for a test, or read elsewhere.
  @visibleForTesting
  void hold(String id, List<StatusChange> changes) {
    _held[id] = changes;
    _asked.add(id);
  }

  Future<void> _readQueue() async {
    if (_reading) return;
    _reading = true;
    var read = false;
    try {
      while (_queue.isNotEmpty) {
        final ids = _queue.take(batch).toList();
        _queue.removeRange(0, ids.length);
        await Future.wait([
          for (final id in ids)
            _read(id).then((versions) {
              _held[id] = statusChanges(versions);
              read = true;
            }, onError: (Object _) {
              _held[id] = const <StatusChange>[];
            }),
        ]);
      }
    } finally {
      _reading = false;
    }
    if (read) notifyListeners();
  }
}
