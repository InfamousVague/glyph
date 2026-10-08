/// The changes across many notes at once, for an organization's audit log. A port of
/// `src/app/core/versions/log.ts`. (Matt: "an "audit log" for organizations to be able to browse history of changes
/// across all files".)
///
/// Every version kept of every note filed in a workspace, read from each note's versions file (versions_file.dart,
/// versions_record.dart) and held here as a line each - who, when, how much, the first line it changed - rather
/// than as every version's whole text, which the log reads again for the one version it opens.
///
/// What differs: the page's hook `useChangesAcross(ids)` is [ChangesAcross], a [ValueListenable] whose notes are
/// set with [ChangesAcross.watch]; it hears a file change on [VersionsStore.changed] where the hook listens for
/// `VERSIONS_CHANGED` on the window.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'versions_diff.dart';
import 'versions_file.dart';
import 'versions_record.dart';

/// One version of one note, as a line of the log (`Change`).
@immutable
class Change {
  const Change({required this.noteId, required this.n, required this.at, required this.by, this.label, required this.added, required this.removed, required this.peek, required this.first});
  final String noteId;

  /// The version's place in its note's file, from 1.
  final int n;

  /// When it was kept, in ms.
  final int at;

  /// Who kept it: their handle, or `me` without an account.
  final String by;

  /// The name it was given, if any.
  final String? label;

  /// How many lines it put in and took out against the version before.
  final int added;
  final int removed;

  /// The first line it put in or took out (`kind` is `add` or `del`); null for a version of no change to the lines
  /// (a name given).
  final ({String kind, String text})? peek;

  /// Its note's first version: the note created.
  final bool first;

  @override
  bool operator ==(Object other) =>
      other is Change && other.noteId == noteId && other.n == n && other.at == at && other.by == by && other.label == label && other.added == added && other.removed == removed && other.peek == peek && other.first == first;

  @override
  int get hashCode => Object.hash(noteId, n, at, by, label, added, removed, peek, first);

  @override
  String toString() => 'Change($noteId v$n at $at by $by${label == null ? '' : ' "$label"'} +$added -$removed $peek${first ? ' first' : ''})';
}

/// A note's versions as changes, in the file's order (`changesIn`).
List<Change> changesIn(String noteId, List<Version> versions) => [
      for (final (i, version) in versions.indexed)
        Change(
          noteId: noteId,
          n: version.n,
          at: version.at,
          by: version.by,
          label: version.label,
          added: version.added,
          removed: version.removed,
          peek: firstChange(i > 0 ? versions[i - 1].text : null, version.text),
          first: version.n == 1,
        ),
    ];

/// One note's file, read as changes.
typedef FileRead = ({List<Change> changes, int damaged});

/// Note [id]'s changes, from its versions file, and how many of the file's versions could not be read
/// (`changesOf`).
Future<FileRead> changesOf(VersionsRecord record, String id) async {
  final read = await record.versionsOf(id);
  return (changes: changesIn(id, read.versions), damaged: read.damaged);
}

/// Newest first; two kept at the same moment by note, then the later version first, so the order holds from one
/// read to the next (`newestFirst`).
int newestFirst(Change a, Change b) {
  final when = b.at.compareTo(a.at);
  if (when != 0) return when;
  final note = compareAsPage(a.noteId, b.noteId);
  return note != 0 ? note : b.n.compareTo(a.n);
}

/// What the log shows (`ChangesRead`).
@immutable
class ChangesRead {
  const ChangesRead({this.changes = const [], this.damaged = 0, this.read = 0, this.total = 0});

  /// Every change of every note read so far, newest first.
  final List<Change> changes;

  /// How many versions, over every file, could not be read and were left out.
  final int damaged;

  /// How many of the notes have been read, of how many: the log says so while they are coming in.
  final int read;
  final int total;

  @override
  bool operator ==(Object other) => other is ChangesRead && listEquals(other.changes, changes) && other.damaged == damaged && other.read == read && other.total == total;

  @override
  int get hashCode => Object.hash(Object.hashAll(changes), damaged, read, total);
}

/// How many notes' files are read at once: enough to be quick, not so many that a big workspace floods the bridge
/// (`AT_ONCE`).
const int _atOnce = 6;

/// The changes of a set of notes, read from their versions files, a few at a time, and read again - one note at a
/// time - as any of them changes here (a version kept, or sync bringing a file) (`useChangesAcross`). A note that
/// leaves the set is dropped; one that joins is read. A file that cannot be read counts as a note with no changes.
class ChangesAcross extends ValueNotifier<ChangesRead> {
  ChangesAcross(this.record, [List<String> ids = const []]) : super(const ChangesRead()) {
    _changes = record.store.changed.listen((id) {
      if (_wanted.contains(id)) unawaited(_read(id));
    });
    watch(ids);
  }

  final VersionsRecord record;
  late final StreamSubscription<String> _changes;
  final Map<String, FileRead> _files = {};
  List<String> _wanted = const [];
  int _round = 0;
  bool _live = true;

  Future<void> _read(String id) async {
    FileRead got;
    try {
      got = await changesOf(record, id);
    } catch (_) {
      got = (changes: const <Change>[], damaged: 0);
    }
    // A note that left the set while its file was being read is not put back.
    if (!_live || !_wanted.contains(id)) return;
    _files[id] = got;
    _settle();
  }

  void _settle() {
    final changes = <Change>[];
    var damaged = 0;
    var read = 0;
    for (final id in _wanted) {
      final got = _files[id];
      if (got == null) continue;
      read += 1;
      damaged += got.damaged;
      changes.addAll(got.changes);
    }
    // Sorted with the place each came in as the last word, so equal changes keep their order from read to read.
    final placed = changes.indexed.toList()
      ..sort((a, b) {
        final order = newestFirst(a.$2, b.$2);
        return order != 0 ? order : a.$1.compareTo(b.$1);
      });
    value = ChangesRead(changes: [for (final (_, change) in placed) change], damaged: damaged, read: read, total: _wanted.length);
  }

  /// The notes whose changes are wanted, in the order they are listed. The notes no longer here are dropped; those
  /// not read yet are read, a few at a time.
  void watch(List<String> ids) {
    _wanted = List.unmodifiable(ids);
    final round = ++_round;
    final set = ids.toSet();
    _files.removeWhere((id, _) => !set.contains(id));
    _settle();
    final todo = [for (final id in ids) if (!_files.containsKey(id)) id];
    unawaited(() async {
      for (var i = 0; i < todo.length && _live && round == _round; i += _atOnce) {
        await Future.wait([for (final id in todo.skip(i).take(_atOnce)) _read(id)]);
      }
    }());
  }

  @override
  void dispose() {
    _live = false;
    unawaited(_changes.cancel());
    super.dispose();
  }
}
