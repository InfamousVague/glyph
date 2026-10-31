/// Updates: the bell as an inbox (docs/TEAMSPACES.md, "Follow a doc and Updates"; Matt, 2026-10-31: "watching sends
/// that page's changes to your Updates (the bell, as an inbox with filters: Mentions, Tickets, Docs, Team)"). Two
/// kinds of row in one list:
///
/// - **the feed's**, as they were (lib/core/notifications.dart): a mention, a ticket you watch, an invitation, the
///   team's news, what Claude wrote. Each is under one filter by its kind ([filterOf]), or under All alone;
/// - **a change to a page you follow** ([DocUpdate]), under Docs: who changed it, when, how much, the first line it
///   changed. Nothing new arrives for these and the server is not asked anything: a team page keeps versions by
///   default (lib/core/versions_record.dart), each saying who kept it, and every member's device merges the page's
///   versions file as the team's sync brings it (lib/team/sync.dart), so the changes are read from the versions of the
///   pages this account follows ([DocUpdatesFeed], over the audit log's own reader, lib/core/versions_log.dart
///   `ChangesAcross`). A version kept by this account is not an update; nor is one from before this device first saw
///   the account following the page, so following a page with a long history does not fill the inbox with it.
///
/// Read and cleared are this account's bookkeeping on this device ([DocUpdatesFeed] keeps them in its memory, by
/// account), as the feed's own marks are the account's: an update read here is read on this device.
library;

import 'package:flutter/foundation.dart';

import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/notifications.dart';
import '../core/stored.dart';
import '../core/versions_log.dart';
import '../mentions/mention_syntax.dart' show handleKey;
import 'follow.dart';

// ---- the filters ----------------------------------------------------------------------------------------------------

/// The inbox's filters, in the order the chips stand.
enum UpdatesFilter { all, mentions, tickets, docs, team }

/// Each filter's chip.
const Map<UpdatesFilter, String> updatesFilterLabels = {
  UpdatesFilter.all: 'All',
  UpdatesFilter.mentions: 'Mentions',
  UpdatesFilter.tickets: 'Tickets',
  UpdatesFilter.docs: 'Docs',
  UpdatesFilter.team: 'Team',
};

/// The kinds the Tickets filter shows: a ticket you watch, your morning's tickets, a rule's word, an answer filed as one.
const Set<String> ticketKinds = {'ticket', 'ticket-digest', ticketRuleKind, 'form-answer'};

/// The filter a feed row is under besides All, by its kind: a mention under Mentions (someone named you); a ticket's
/// rows under Tickets; a verified page of yours wanting review under Docs, with the changes to the pages you follow;
/// the organization's news (an invitation, who joined or left, a role, a rename) under Team. What Claude wrote, a
/// meeting written up and a note kept twice are under All alone. Null for those.
UpdatesFilter? filterOf(FeedNotification n) {
  final kind = n.kind;
  if (kind == 'mention') return UpdatesFilter.mentions;
  if (kind == 'page-expired') return UpdatesFilter.docs;
  if (ticketKinds.contains(kind)) return UpdatesFilter.tickets;
  if (serverKinds.contains(kind)) return UpdatesFilter.team;
  return null;
}

/// Whether a feed row is shown under [filter].
bool shownUnder(UpdatesFilter filter, FeedNotification n) => filter == UpdatesFilter.all || filterOf(n) == filter;

// ---- changes to followed pages --------------------------------------------------------------------------------------

/// A change to a page this account follows, by someone else.
@immutable
class DocUpdate {
  const DocUpdate({required this.noteId, required this.n, required this.title, required this.by, required this.at, this.added = 0, this.removed = 0, this.first = false, this.peek});

  /// The page, and the version's place in its file.
  final String noteId;
  final int n;

  /// The page's title now.
  final String title;

  /// Who kept the version: their handle.
  final String by;
  final int at;
  final int added;
  final int removed;

  /// The page's first version: it was made.
  final bool first;

  /// The first line it put in or took out.
  final String? peek;

  /// The update's one key, for read and cleared.
  String get key => '$noteId:$n';

  /// The row's sentence: "sam edited Roadmap · 3 lines changed", "sam created Roadmap".
  String get sentence {
    if (first) return '$by created $title';
    final lines = added + removed;
    if (lines == 0) return '$by named a version of $title';
    return '$by edited $title · ${lines == 1 ? '1 line' : '$lines lines'} changed';
  }

  @override
  bool operator ==(Object other) =>
      other is DocUpdate && other.noteId == noteId && other.n == n && other.title == title && other.by == by && other.at == at && other.added == added && other.removed == removed && other.first == first && other.peek == peek;

  @override
  int get hashCode => Object.hash(noteId, n, title, by, at, added, removed, first, peek);

  @override
  String toString() => 'DocUpdate($sentence at $at)';
}

/// How many changes to followed pages the inbox holds, newest first.
const int docUpdatesKept = 100;

/// The updates [changes] make for [me]: those to a page in [followed], kept by someone else (not [me], not `me`, a
/// version kept here without an account), after [since] says the account began following the page (no entry: none
/// yet), and not [hidden]; newest first, at most [docUpdatesKept]. [titles] names each page.
List<DocUpdate> docUpdatesOf({required Iterable<Change> changes, required Set<String> followed, required Map<String, int> since, required String? me, required Map<String, String> titles, Set<String> hidden = const {}}) {
  final mine = me == null ? null : handleKey(me);
  final out = <DocUpdate>[];
  for (final change in changes) {
    if (!followed.contains(change.noteId)) continue;
    final from = since[change.noteId];
    if (from == null || change.at <= from) continue;
    if (change.by == 'me' || (mine != null && handleKey(change.by) == mine)) continue;
    final update = DocUpdate(
      noteId: change.noteId,
      n: change.n,
      title: titles[change.noteId] ?? 'Untitled',
      by: change.by,
      at: change.at,
      added: change.added,
      removed: change.removed,
      first: change.first,
      peek: change.peek?.text,
    );
    if (hidden.contains(update.key)) continue;
    out.add(update);
  }
  out.sort((a, b) => a.at != b.at ? b.at.compareTo(a.at) : (a.noteId != b.noteId ? a.noteId.compareTo(b.noteId) : b.n.compareTo(a.n)));
  return out.length > docUpdatesKept ? out.sublist(0, docUpdatesKept) : out;
}

/// Where the device keeps an account's reading of its doc updates: `glyph-doc-updates:<handle>`.
String docUpdatesKey(String handle) => 'glyph-doc-updates:${handleKey(handle)}';

/// The changes to the pages this account follows, as a [ValueListenable] the inbox and the bell's dot read, with
/// read and cleared kept on the device per account (see the library's doc).
///
/// [notes] are the library's (the followed pages are found in them: a team page whose `watchers:` names the
/// account); [changes] and [watch] are the versions' reader (`ChangesAcross`: its value and its `watch`), told the
/// followed pages as they change; [team] says whether a note is a team's page.
class DocUpdatesFeed extends ChangeNotifier implements ValueListenable<List<DocUpdate>> {
  DocUpdatesFeed({
    required this.notes,
    required this.changes,
    required this.watch,
    required this.me,
    required this.team,
    required this.stored,
    String Function(Note note)? title,
    int Function()? now,
  })  : _title = title ?? ((note) => NoteFacts.of(note).title.trim().isEmpty ? 'Untitled' : NoteFacts.of(note).title.trim()),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    notes.addListener(_notesChanged);
    changes.addListener(_settle);
    _notesChanged();
  }

  final ValueListenable<List<Note>> notes;
  final ValueListenable<ChangesRead> changes;
  final void Function(List<String> ids) watch;
  final String? Function() me;
  final bool Function(String noteId) team;
  final Stored stored;
  final String Function(Note note) _title;
  final int Function() _now;

  List<String> _followed = const [];
  Map<String, String> _titles = const {};
  List<DocUpdate> _value = const [];
  String? _readFor;
  _Reading _reading = _Reading();
  bool _disposed = false;

  @override
  List<DocUpdate> get value => _value;

  /// The pages followed now, by id.
  List<String> get followed => _followed;

  _Reading _readingOf(String handle) {
    if (_readFor == handleKey(handle)) return _reading;
    _readFor = handleKey(handle);
    return _reading = _Reading.read(stored.read<Object?>(docUpdatesKey(handle), null));
  }

  void _keep(String handle) => stored.write(docUpdatesKey(handle), _reading.toJson());

  void _notesChanged() {
    if (_disposed) return;
    final who = me();
    final followed = <String>[];
    final titles = <String, String>{};
    if (who != null && who.isNotEmpty) {
      final reading = _readingOf(who);
      var learnt = false;
      for (final note in notes.value) {
        // Read whole only where the words name a watcher at all: the list is every note, on every change to any.
        if (note.inTrash || !note.body.contains('watchers') || !team(note.id) || !follows(note.body, who)) continue;
        followed.add(note.id);
        titles[note.id] = _title(note);
        // Following from now: what was kept before this device saw it is the page's history, not news.
        if (!reading.since.containsKey(note.id)) {
          reading.since[note.id] = _now();
          learnt = true;
        }
      }
      if (learnt) _keep(who);
    }
    _titles = titles;
    if (!listEquals(followed, _followed)) {
      _followed = List.unmodifiable(followed);
      watch(_followed);
    }
    _settle();
  }

  void _settle() {
    if (_disposed) return;
    final who = me();
    final next = who == null || who.isEmpty
        ? const <DocUpdate>[]
        : docUpdatesOf(changes: changes.value.changes, followed: _followed.toSet(), since: _readingOf(who).since, me: who, titles: _titles, hidden: _readingOf(who).hidden);
    if (listEquals(next, _value)) return;
    _value = List.unmodifiable(next);
    notifyListeners();
  }

  /// Reads the followed pages again: the account signed in is another, or the pages filed in a team are.
  void refresh() => _notesChanged();

  /// Whether [update] has been read on this device.
  bool isRead(DocUpdate update) {
    final who = me();
    if (who == null) return true;
    final reading = _readingOf(who);
    return update.at <= reading.readBefore || reading.read.contains(update.key);
  }

  /// How many updates are unread.
  int get unread => _value.where((update) => !isRead(update)).length;

  /// [update] read.
  void markRead(DocUpdate update) {
    final who = me();
    if (who == null || isRead(update)) return;
    _reading.read.add(update.key);
    _reading.trim();
    _keep(who);
    notifyListeners();
  }

  /// Every update read: up to the newest one now.
  void markAllRead() {
    final who = me();
    if (who == null || _value.isEmpty) return;
    final reading = _readingOf(who);
    reading.readBefore = _value.first.at > reading.readBefore ? _value.first.at : reading.readBefore;
    reading.read.clear();
    _keep(who);
    notifyListeners();
  }

  /// [keys] cleared from the inbox.
  void hide(Iterable<String> keys) {
    final who = me();
    if (who == null) return;
    final reading = _readingOf(who);
    var changed = false;
    for (final key in keys) {
      changed = reading.hidden.add(key) || changed;
    }
    if (!changed) return;
    reading.trim();
    _keep(who);
    _settle();
  }

  @override
  void dispose() {
    _disposed = true;
    notes.removeListener(_notesChanged);
    changes.removeListener(_settle);
    super.dispose();
  }
}

/// An account's reading of its doc updates, as kept.
class _Reading {
  _Reading();

  factory _Reading.read(Object? raw) {
    final reading = _Reading();
    if (raw is! Map) return reading;
    final since = raw['since'], read = raw['read'], hidden = raw['hidden'], before = raw['readBefore'];
    if (since is Map) {
      for (final MapEntry(:key, :value) in since.entries) {
        if (key is String && value is num) reading.since[key] = value.toInt();
      }
    }
    if (read is List) reading.read.addAll(read.whereType<String>());
    if (hidden is List) reading.hidden.addAll(hidden.whereType<String>());
    if (before is num) reading.readBefore = before.toInt();
    return reading;
  }

  final Map<String, int> since = {};
  final Set<String> read = {};
  final Set<String> hidden = {};
  int readBefore = 0;

  /// The read and the cleared held to a few hundred each, the oldest forgotten first.
  void trim() {
    for (final set in [read, hidden]) {
      if (set.length > 500) {
        final keep = set.skip(set.length - 500).toList();
        set
          ..clear()
          ..addAll(keep);
      }
    }
  }

  Map<String, Object?> toJson() => {'since': since, 'read': read.toList(), 'hidden': hidden.toList(), 'readBefore': readBefore};
}

/// The inbox's chips for [rows] (the feed's, as wanted) and [docs]: All, then each filter with a row, in their order;
/// All alone (no chips drawn) until there is something of the person's own to filter to, a mention, a ticket or a
/// followed page's change, so a drawer of the team's news and Claude's writes is as it always was.
List<UpdatesFilter> inboxFilters(Iterable<FeedNotification> rows, List<DocUpdate> docs) {
  final has = <UpdatesFilter>{for (final n in rows) ?filterOf(n), if (docs.isNotEmpty) UpdatesFilter.docs};
  if (!has.contains(UpdatesFilter.mentions) && !has.contains(UpdatesFilter.tickets) && !has.contains(UpdatesFilter.docs)) return const [UpdatesFilter.all];
  return [UpdatesFilter.all, for (final each in const [UpdatesFilter.mentions, UpdatesFilter.tickets, UpdatesFilter.docs, UpdatesFilter.team]) if (has.contains(each)) each];
}
