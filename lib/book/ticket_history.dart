/// A ticket's history: who changed what and when (Matt, 2026-10-31: "A timeline in the ticket panel of who changed
/// what and when: status, assignee, due, priority, labels, estimate"). Read from the note's versions
/// (lib/core/versions_file.dart), which a team's note keeps by default and a note of one's own once it is switched on:
/// each version's front matter set beside its predecessor's, the change put down to whoever kept the version (its
/// head line's handle; a team's note is kept by the member whose edit it was).
///
///     Sam moved it In progress → In review · 2 hr ago
///     Matt assigned it to sam · Yesterday
///     Matt created it · Tuesday
///
/// **Fast.** The changes between two versions depend on nothing but their two texts, so each pair is read once and
/// kept by the versions' hashes ([TicketTimeline]); a file that grew by a version is read for that version alone, and
/// one merged from another device (a version kept in the middle) reads only the pairs it has not seen.
///
/// **For others to use.** [ticketHistory] answers a ticket's changes, oldest first, from whatever the app registered
/// ([registerTicketHistory]): what a burndown can read, a status's moves by day, by who. The cycles' own reader of
/// statuses (lib/core/planning/history.dart `TicketHistory`) is apart from this one, hence [TicketTimeline]'s name.
/// Pure apart from that, so each sequence of versions is a test (test/book_core/ticket_history_test.dart).
library;

import 'package:flutter/foundation.dart';

import '../core/properties.dart';
import '../core/task_fields.dart' show priorityOf;
import '../core/versions_file.dart' show Version;

/// The keys a ticket's history follows, in the order a version's changes are listed.
const List<String> historyKeys = ['type', 'status', 'assignee', 'due', 'priority', 'labels', 'estimate'];

/// One change to a ticket: when, who, which key, and what it was and became (null for not set). `type` from nothing
/// to `ticket` is the ticket made.
@immutable
class TicketChange {
  const TicketChange({required this.at, required this.by, required this.key, required this.from, required this.to});

  /// When, in ms: the version's time.
  final int at;

  /// Who: the handle the version was kept by, or `me` written without an account.
  final String by;
  final String key;
  final String? from;
  final String? to;

  /// Whether it is the ticket being made.
  bool get created => key == 'type';

  Map<String, Object?> toJson() => {'at': at, 'by': by, 'key': key, 'from': from, 'to': to};

  @override
  bool operator ==(Object other) => other is TicketChange && other.at == at && other.by == by && other.key == key && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(at, by, key, from, to);

  @override
  String toString() => 'TicketChange(${toJson()})';
}

/// A text's followed keys, as the history compares them: trimmed, a list's items joined by `, `, a type lower case;
/// a key not set, or set to nothing, is absent.
Map<String, String> _followed(String text) {
  final out = <String, String>{};
  for (final property in propertiesOf(text)) {
    final key = property.key.toLowerCase();
    if (!historyKeys.contains(key) || out.containsKey(key)) continue;
    final value = key == 'labels' ? propertyList(property.value).join(', ') : property.value.trim();
    if (value.isEmpty) continue;
    out[key] = key == 'type' ? value.toLowerCase() : value;
  }
  return out;
}

/// What changed from [before] (null: there was nothing before it) to [after], at [at] by [by]. A note that is no
/// ticket on either side changed nothing a ticket's history tells; one that became a ticket says so first.
List<TicketChange> changesBetween(String? before, String after, {required int at, required String by}) {
  final was = before == null ? const <String, String>{} : _followed(before), now = _followed(after);
  final ticketNow = now['type'] == ticketType, ticketWas = was['type'] == ticketType;
  if (!ticketNow && !ticketWas) return const [];
  final out = <TicketChange>[];
  for (final key in historyKeys) {
    final from = was[key], to = now[key];
    if (from == to) continue;
    if (key == 'type') {
      // Made a ticket, or no longer one: only the first is told.
      if (ticketNow && !ticketWas) out.add(TicketChange(at: at, by: by, key: key, from: null, to: ticketType));
      continue;
    }
    // A ticket made with its keys set is made, not changed: its first values are not changes.
    if (ticketNow && !ticketWas) continue;
    out.add(TicketChange(at: at, by: by, key: key, from: from, to: to));
  }
  return out;
}

/// A ticket's changes through [versions], oldest first, as [changesBetween] reads each beside the one before.
List<TicketChange> historyOf(List<Version> versions) {
  final out = <TicketChange>[];
  String? before;
  for (final version in versions) {
    out.addAll(changesBetween(before, version.text, at: version.at, by: version.by));
    before = version.text;
  }
  return out;
}

/// Each note's history, kept per pair of versions so it is read once (see the header).
class TicketTimeline {
  TicketTimeline(this._versions);

  /// A note's versions, oldest first (lib/core/versions_record.dart `versionsOf`).
  final Future<List<Version>> Function(String noteId) _versions;

  /// The changes between two versions, by their hashes, times and keepers.
  final Map<String, List<TicketChange>> _pairs = {};

  /// How many pairs were read, rather than found kept: for a test, and a bench.
  int read = 0;

  static String _pairKey(Version? before, Version after) => '${before?.hash ?? '-'}>${after.hash}|${after.at}|${after.by}';

  /// The changes in [versions], oldest first, each pair read at most once over this history's life.
  List<TicketChange> changesIn(List<Version> versions) {
    final out = <TicketChange>[];
    Version? before;
    for (final version in versions) {
      final key = _pairKey(before, version);
      final kept = _pairs[key];
      if (kept != null) {
        out.addAll(kept);
      } else {
        read += 1;
        final made = changesBetween(before?.text, version.text, at: version.at, by: version.by);
        _pairs[key] = made;
        out.addAll(made);
      }
      before = version;
    }
    return out;
  }

  /// Note [noteId]'s changes, oldest first; none where it keeps no versions or none could be read.
  Future<List<TicketChange>> of(String noteId) async {
    final List<Version> versions;
    try {
      versions = await _versions(noteId);
    } catch (_) {
      return const [];
    }
    return changesIn(versions);
  }
}

TicketTimeline? _registered;

/// The app's history, given where the versions are (lib/root/ghost_root.dart): what [ticketHistory] reads.
void registerTicketHistory(TicketTimeline? history) => _registered = history;

/// A ticket's changes, oldest first: status, assignee, due, priority, labels and estimate, and the ticket being
/// made, each with when and who (see the header). None before the app has registered its history.
Future<List<TicketChange>> ticketHistory(String noteId) => _registered?.of(noteId) ?? Future<List<TicketChange>>.value(const []);

/// Who a change is put down to: "You" for the person reading, else the handle.
String _who(String by, String? me) => me != null && me.isNotEmpty && by.toLowerCase() == me.toLowerCase() || by == 'me' ? 'You' : by;

/// A change in the timeline's words, without its time: "Sam moved it In progress → In review".
String changeWords(TicketChange change, {String? me}) {
  final who = _who(change.by, me);
  final from = change.from, to = change.to;
  switch (change.key) {
    case 'type':
      return '$who created it';
    case 'status':
      return from == null ? '$who set the status to $to' : (to == null ? '$who took the status off' : '$who moved it $from → $to');
    case 'assignee':
      return to == null ? '$who unassigned $from' : '$who assigned it to $to';
    case 'due':
      return to == null ? '$who took the due date off' : (from == null ? '$who set the due date to $to' : '$who moved the due date to $to');
    case 'priority':
      final label = priorityOf(to)?.label ?? to;
      return to == null ? '$who took the priority off' : '$who set the priority to $label';
    case 'labels':
      final had = propertyList(from), has = propertyList(to);
      final added = [for (final label in has) if (!had.contains(label)) label], removed = [for (final label in had) if (!has.contains(label)) label];
      final parts = <String>[
        if (added.isNotEmpty) 'added ${added.length == 1 ? 'the label' : 'the labels'} ${added.join(', ')}',
        if (removed.isNotEmpty) 'took off ${removed.length == 1 ? 'the label' : 'the labels'} ${removed.join(', ')}',
      ];
      return parts.isEmpty ? '$who changed the labels' : '$who ${parts.join(' and ')}';
    case 'estimate':
      return to == null ? '$who took the estimate off' : '$who estimated it at $to';
  }
  return '$who changed ${change.key}';
}
