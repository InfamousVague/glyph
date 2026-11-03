/// A cleanup's look at a folder (docs/CLEANUP.md, "Large folders"): the folder read as it is now ([cleanupScope]), the
/// estimate asked about before a big run ([cleanupEstimate]), and the run itself ([runCleanup]), batch by batch on the
/// Activity tray with Stop, then Tidy's asks for whole notes, the answers read into one [CleanupPlan].
///
/// Nothing is changed here: the plan is only suggestions, for the review (review.dart) and apply.dart.
library;

import 'dart:async';
import 'dart:math' as math;

import '../../core/background_jobs.dart';
import '../../core/library.dart';
import '../../core/link_index.dart' show linksIn;
import '../../core/note_text.dart' show noteTitle;
import '../../core/trash.dart';
import '../../core/workspaces.dart';
import 'ai.dart';
import 'plan.dart';
import 'prompts.dart';
import 'text.dart';

/// The most notes Tidy asks about whole in one run, and the longest note it sends (a cloud model's, then the
/// device's).
const int cleanupMaxTidy = 25;
const int tidyMaxChars = 20000;
const int tidyMaxCharsDevice = 8000;

/// The folder [folderId] and everything in it, read from [workspaces] and [library] now: every folder under it, every
/// note filed in it or under it that is out of the Trash and the Archive, and the titles any note of the library links
/// to. Null for a folder the list does not have.
CleanupScope? cleanupScope({required String folderId, required WorkspaceStore workspaces, required NoteLibrary library, Trash? trash}) {
  final spaces = workspaces.value;
  final list = spaces.list;
  if (!list.any((w) => w.id == folderId)) return null;
  final family = workspaceFamily(list, folderId);
  final byId = {for (final w in list) w.id: w};
  int depthOf(String id) {
    var depth = 0;
    for (var at = byId[id]; at != null && at.id != folderId; at = at.parent == null ? null : byId[at.parent]) {
      depth += 1;
    }
    return depth;
  }

  final folders = [
    for (final id in family)
      CleanupFolder(id: id, name: byId[id]!.name, parent: byId[id]!.parent, path: workspacePathName(list, id), depth: depthOf(id)),
  ];
  final inFamily = family.toSet();
  final held = trash?.value ?? const <String, int>{};
  final notes = <CleanupNote>[];
  final linked = <String>{};
  for (final note in library.value) {
    if (trashedNote(note, held)) continue;
    for (final link in linksIn(note.body)) {
      if (link.path == null) linked.add(link.key);
    }
    final filed = spaces.of[note.id];
    if (filed == null || !inFamily.contains(filed)) continue;
    if (note.archivedAt != null && note.archivedAt != 0) continue;
    notes.add(CleanupNote(id: note.id, title: noteTitle(note.body), body: note.body, revision: note.revision, folderId: filed, updatedAt: note.updatedAt));
  }
  return CleanupScope(rootId: folderId, org: workspaces.orgOf(folderId), folders: folders, notes: notes, linkedTitles: linked);
}

/// The notes in the order they are asked about: copies of one note (one title once its copy marks are off) side by
/// side, so they meet in one batch.
List<CleanupNote> batchOrder(List<CleanupNote> notes) {
  final sorted = [...notes];
  sorted.sort((a, b) {
    final byKey = sameTitleKey(a.title).compareTo(sameTitleKey(b.title));
    return byKey != 0 ? byKey : a.id.compareTo(b.id);
  });
  return sorted;
}

/// The batches [scope]'s notes go in, [CleanupSizes.notesPerAsk] at a time.
List<CleanupBatch> cleanupBatches(CleanupScope scope, CleanupSizes sizes) {
  final order = batchOrder(scope.notes);
  return [
    for (var at = 0; at < order.length; at += sizes.notesPerAsk) CleanupBatch(scope, order.sublist(at, math.min(order.length, at + sizes.notesPerAsk))),
  ];
}

/// What a run will take, said before it starts: the notes, the asks, and about how long.
class CleanupEstimate {
  const CleanupEstimate({required this.notes, required this.asks, required this.tidyAsks, required this.duration, required this.aiName});

  final int notes;

  /// The first pass's asks, and about how many Tidy may add.
  final int asks;
  final int tidyAsks;
  final Duration duration;
  final String aiName;

  /// The Activity tray's estimate: over two minutes it asks first (lib/activity/activity_cost.dart).
  JobEstimate get job => JobEstimate(count: notes, one: 'note', many: 'notes', duration: duration);

  /// "120 notes · 3 asks of Claude · ~1 min".
  String get words => [
        '$notes ${notes == 1 ? 'note' : 'notes'}',
        '${asks + tidyAsks} ${asks + tidyAsks == 1 ? 'ask' : 'asks'} of $aiName',
        '~${durationWords(duration)}',
      ].join(' · ');
}

/// About how long [scope] takes with [ai] (a cloud model's ask about 15 seconds, the device's about 50; Tidy's a
/// little less, for about one note in six).
CleanupEstimate cleanupEstimate(CleanupScope scope, CleanupAi ai, CleanupOptions options) {
  final sizes = ai.sizes;
  final asks = (scope.notes.length / sizes.notesPerAsk).ceil();
  final tidy = options.has(CleanupPass.tidy) ? math.min(cleanupMaxTidy, (scope.notes.length / 6).ceil()) : 0;
  final per = ai.local ? 50 : 15, perTidy = ai.local ? 35 : 10;
  return CleanupEstimate(notes: scope.notes.length, asks: asks, tidyAsks: tidy, duration: Duration(seconds: asks * per + tidy * perTidy), aiName: ai.name);
}

/// The way a run is stopped from outside: the tray's Stop, the page's.
class CleanupStop {
  bool _stopped = false;
  CleanupAsking? _asking;

  bool get stopped => _stopped;

  void stop() {
    _stopped = true;
    _asking?.cancel();
  }
}

/// The job a cleanup of [folderId] is on the Activity tray as.
String cleanupJobId(String folderId) => 'cleanup:$folderId';

/// Asks [ai] about every note of [scope] and reads the answers into one plan (see the library doc). [progress] is told
/// how far it is (the Activity tray's job and the page); [stop] ends it after the ask in flight, keeping what the finished asks found. Never throws for an ask
/// that failed: its words are in [CleanupPlan.failures]. [now] is today's date for the prompt.
Future<CleanupPlan> runCleanup({required CleanupScope scope, required CleanupAi ai, required CleanupOptions options, void Function(int done, int total, String line)? progress, CleanupStop? stop, DateTime Function()? now}) async {
  // An organization's folders are never asked about duplicates ([optionsFor]).
  options = optionsFor(scope, options);
  final sizes = ai.sizes;
  final batches = cleanupBatches(scope, sizes);
  final system = cleanupSystem(options);
  final read = <BatchPlan>[];
  final tidyAsks = <TidyAsk>[];
  var asks = 0;
  var done = 0;
  final total = scope.notes.length;
  final stopped = stop ?? CleanupStop();

  if (options.passes.isNotEmpty) {
    for (final batch in batches) {
      if (stopped.stopped) break;
      progress?.call(done, total, 'Reading with ${ai.name}');
      final asking = stopped._asking = ai.ask(system, cleanupBatchPrompt(batch, sizes, now: now), maxTokens: ai.local ? 1500 : 4000);
      asks += 1;
      try {
        read.add(readBatch(await asking.done, batch, options));
      } catch (failure) {
        if (stopped.stopped) break;
        read.add(BatchPlan(failed: _said(failure)));
      } finally {
        stopped._asking = null;
      }
      done += batch.notes.length;
      progress?.call(done, total, 'Reading with ${ai.name}');
      for (final b in read.last.tidy) {
        if (!tidyAsks.any((t) => t.noteId == b.noteId)) tidyAsks.add(b);
      }
    }
  }

  // Tidy: each note it named, whole, one at a time.
  final tidied = <EditItem>[];
  final dropped = <String>[];
  if (options.has(CleanupPass.tidy) && !stopped.stopped) {
    final most = ai.local ? tidyMaxCharsDevice : tidyMaxChars;
    final asked = tidyAsks.take(cleanupMaxTidy).toList();
    if (tidyAsks.length > asked.length) dropped.add('${tidyAsks.length - asked.length} more notes to tidy: at most $cleanupMaxTidy a run');
    final tidySys = tidySystem(rewrite: options.rewrite);
    for (var i = 0; i < asked.length; i += 1) {
      if (stopped.stopped) break;
      final note = scope.note(asked[i].noteId);
      if (note == null) continue;
      if (note.body.length > most) {
        dropped.add('a tidy of “${note.title}”: too long to send whole here');
        continue;
      }
      progress?.call(i, asked.length, 'Tidying with ${ai.name}');
      final asking = stopped._asking = ai.ask(tidySys, tidyPrompt(note, asked[i].why), maxTokens: math.min(16000, (note.body.length / 2).ceil() + 1000));
      asks += 1;
      try {
        final answer = readTidy(await asking.done, note, options, why: asked[i].why);
        if (answer.item != null) tidied.add(answer.item!);
        if (answer.dropped != null) dropped.add(answer.dropped!);
      } catch (failure) {
        if (stopped.stopped) break;
        dropped.add('a tidy of “${note.title}”: ${_said(failure)}');
      } finally {
        stopped._asking = null;
      }
    }
  }

  final found = options.has(CleanupPass.duplicates)
      ? duplicateGroups([for (final n in scope.notes) (id: n.id, title: n.title, body: n.body, updatedAt: n.updatedAt)])
      : const <List<String>>[];
  return CleanupPlan.join(scope: scope, options: options, batches: read, tidied: tidied, found: found, moreDropped: dropped, asks: asks, stopped: stopped.stopped);
}

/// A failure in plain words.
String _said(Object failure) {
  final text = failure.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}
