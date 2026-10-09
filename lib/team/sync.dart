/// A team's notes kept the same on every member's devices (docs/SHARED.md, S1, S4, S5): the organization channel,
/// run after the account's own sync in every full pass (lib/sync/engine.dart, step 5), once for each organization
/// the person has joined and holds the key of (lib/orgs/org_keys.dart). A port of `src/app/core/team/sync.ts`.
///
/// The document of record is the CRDT (doc.dart). The organization's row for a note carries a snapshot of the
/// document - its state, and the note's words and particulars as they stood - and the log beside it carries every
/// update since, so a pass is:
///
/// 1. **Pull** every row written since the cursor: a deletion takes the note and its document; a row is adopted
///    into the document held here (merged, never doubled), its words written to the note, the note filed in the
///    organization's workspace, and its files - the versions file merged, the pictures - fetched where this device
///    lacks them. A note this device had of its own before the team did keeps its words: they are reconciled into
///    the document as a change, so the team gets them.
/// 2. **Updates** since each document's seq, applied, and the words written to the note when they changed.
/// 3. **Push**: words that reached a note without the editor are reconciled into its document; the updates made
///    here are posted to the log; a note new to the team, or one whose particulars changed, or one whose document
///    has gone [snapshotEvery] updates past its last snapshot, is put as a row - with its versions file and
///    pictures sent first - and a row that lost the race is merged and put again. A note no longer here, or no
///    longer filed in the organization's workspace, is deleted from the team.
///
/// Two members who edited apart merge by the CRDT: nothing here keeps a copy. A note's send that fails is counted
/// and the pass goes on, as the account's sync does; a lapsed session ends it, and so does the key turning under
/// this device ([KeyTurned]).
///
/// What differs:
/// - The context is made from what the engine hands the hook ([TeamPass]): [teamNotesPass] is the
///   [TeamNotesPass] an engine is given, one pass of the channel or, after a turn, the re-sealing.
/// - What a pass still owes the notes it took (their versions files and pictures) is the pass's own list, where the
///   page keeps a module's.
/// - A row is put with the note whole, read with `get` first: the list's note has no phrases and no formatted
///   version (docs/STAGE3.md), and a row written from it would take them from every other device. For the same
///   reason a row that says neither, taken over a note here that has them and whose recording has not changed,
///   leaves them.
/// - **A canvas is passed over, both ways.** The web keeps a team canvas as types beside the text
///   (core/team/canvas.ts) and reads its JSON from them; the core here holds text alone, and a canvas merged as
///   words is no canvas at all. So a canvas filed in an organization's workspace is not published from here, and a
///   team's canvas is not taken: it waits for the types (docs/STAGE7.md, piece J's remainder).
/// - An update the core refuses fails that note's step, said as its reason; the others of its batch are applied,
///   and the log is asked again from the same seq next pass. (One from the web that splits a character was such
///   an update, and is not any more: crdt.dart reads it as the web's own Yjs does.)
library;

import 'dart:convert';
import 'dart:typed_data';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../core/bytes.dart';
import '../core/canvas_body.dart';
import '../core/note.dart';
import '../core/note_json.dart';
import '../sync/engine.dart' show TeamNotesPass, TeamOutcome, TeamPass;
import '../sync/notes.dart';
import 'doc.dart';

export '../sync/notes.dart' show KeyTurned;

/// How many updates past its last snapshot a document may go before a pass puts a new one and cuts the log
/// (`SNAPSHOT_EVERY`).
const int snapshotEvery = 200;

/// Updates in one post (server/src/org_notes.rs `UPDATES_PER_POST`).
const int _postAtMost = 100;

/// Per note: the row's revision last seen, and the note's particulars then ([particulars]).
class TeamMark {
  const TeamMark({required this.rev, required this.mark});

  static TeamMark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rev = raw['rev'], mark = raw['mark'];
    return rev is num && mark is String ? TeamMark(rev: rev.toInt(), mark: mark) : null;
  }

  final int rev;
  final String mark;

  Map<String, Object?> toJson() => {'rev': rev, 'mark': mark};

  @override
  bool operator ==(Object other) => other is TeamMark && other.rev == rev && other.mark == mark;

  @override
  int get hashCode => Object.hash(rev, mark);

  @override
  String toString() => 'TeamMark($rev, $mark)';
}

/// What a device remembers of one organization's channel (`TeamSyncState`).
class TeamSyncState {
  TeamSyncState({this.cursor = 0, Map<String, TeamMark>? notes, Map<String, FileMark>? files})
      : notes = notes ?? {},
        files = files ?? {};

  /// A state as kept, forgivingly: what is not there, or not the shape, is empty.
  factory TeamSyncState.fromJson(Object? raw) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final cursor = map['cursor'], notes = map['notes'], files = map['files'];
    final state = TeamSyncState(cursor: cursor is num ? cursor.toInt() : 0);
    if (notes is Map) {
      for (final entry in notes.entries) {
        final mark = TeamMark.fromJson(entry.value);
        if (entry.key is String && mark != null) state.notes[entry.key as String] = mark;
      }
    }
    if (files is Map) {
      for (final entry in files.entries) {
        final mark = FileMark.fromJson(entry.value);
        if (entry.key is String && mark != null) state.files[entry.key as String] = mark;
      }
    }
    return state;
  }

  /// The last revision of the organization's feed this device has read.
  int cursor;

  /// By note id.
  final Map<String, TeamMark> notes;

  /// Per file, as the account's sync keeps them ([SyncState.files]).
  final Map<String, FileMark> files;

  Map<String, Object?> toJson() => {
        'cursor': cursor,
        'notes': {for (final entry in notes.entries) entry.key: entry.value.toJson()},
        'files': {for (final entry in files.entries) entry.key: entry.value.toJson()},
      };
}

/// A device that has read nothing of an organization (`emptyTeamState`).
TeamSyncState emptyTeamState() => TeamSyncState();

/// What one pass of the channel works with (`TeamSyncContext`).
class TeamSyncContext {
  TeamSyncContext({
    required this.token,
    required this.orgId,
    required this.key,
    required this.notes,
    required this.files,
    required this.docs,
    required this.state,
    required this.save,
    required this.api,
    required this.crypto,
    required this.isTeamNote,
    required this.file,
    this.now,
    this.pulled,
    this.generation,
    this.olderKey,
  });

  final String token;
  final String orgId;

  /// The organization key (lib/orgs/org_keys.dart).
  final SealKey key;
  final LocalNotes notes;
  final LocalFiles files;
  final TeamDocs docs;
  final TeamSyncState state;
  final void Function(TeamSyncState state) save;
  final Api api;
  final AccountCrypto crypto;
  final int Function()? now;

  /// Whether a note on this device is filed in this organization's workspace.
  final bool Function(String id) isTeamNote;

  /// A note from the team, filed in the organization's workspace on this device.
  final void Function(String id) file;

  /// The team's notes are on this device as far as the feed goes, their files still to come: the list can be drawn.
  final void Function()? pulled;

  /// The key's generation (docs/SHARED.md, S11), named on every write so one under a turned key is refused, not
  /// kept. None, or 0, for a service from before generations.
  final int? generation;

  /// The key at an older generation, for a row or an update sealed before a turn and not re-sealed yet.
  final Future<SealKey?> Function(int generation)? olderKey;

  /// What this pass still owes the notes it has taken: their versions files and pictures, fetched once the notes
  /// are in.
  final List<Future<void> Function()> _later = [];

  int get _generation => generation ?? 0;
  int _now() => now?.call() ?? DateTime.now().millisecondsSinceEpoch;
  String _route(String tail) => 'orgs/${Uri.encodeComponent(orgId)}/$tail';

  /// A body, naming the key's generation it is sealed under (S11).
  Map<String, Object?> _body(Map<String, Object?> body) => _generation != 0 ? {...body, 'generation': _generation} : body;

  /// The organization's files, as the account's file functions take a context: the same marks, the same key.
  late final SyncContext _files = SyncContext(
    token: token,
    key: key,
    notes: notes,
    files: files,
    state: SyncState(files: state.files),
    save: (_) {},
    api: api,
    crypto: crypto,
    now: now,
    filesRoute: _route('files'),
    generation: _generation != 0 ? _generation : null,
  );
}

class _Tally {
  int changed = 0;
  int sent = 0;
  int unsent = 0;
  String? reason;

  TeamOutcome get outcome => TeamOutcome(changed: changed, sent: sent, unsent: unsent, reason: reason);
}

/// A row's blob, opened (`TeamPayload`): the note as it stood, the document's whole state then, the seq it covered,
/// and the files.
class _Payload {
  const _Payload({required this.note, required this.state, required this.seq, this.images = const [], this.versions});

  factory _Payload.fromJson(Object? raw, String id) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final note = noteFromJson(map['note']);
    final state = map['state'], seq = map['seq'], images = map['images'], versions = map['versions'];
    if (note == null || state is! String) throw const FormatException('That note of the team’s could not be read.');
    return _Payload(
      note: withId(note, id),
      state: fromBase64Url(state),
      seq: seq is num ? seq.toInt() : 0,
      images: images is List ? images.whereType<String>().toList() : const [],
      versions: versions is String && versions.isNotEmpty ? versions : null,
    );
  }

  final Note note;
  final Uint8List state;
  final int seq;
  final List<String> images;
  final String? versions;
}

/// A row in the organization's feed, and what a refused write answers with (`TeamFeedItem`).
class _Row {
  const _Row({required this.id, required this.rev, required this.deleted, required this.blob});

  static _Row? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], rev = raw['rev'], blob = raw['blob'];
    if (id is! String || rev is! num) return null;
    return _Row(id: id, rev: rev.toInt(), deleted: raw['deleted'] == true, blob: blob is String && blob.isNotEmpty ? blob : null);
  }

  final String id;
  final int rev;
  final bool deleted;
  final String? blob;
}

/// A note's particulars, for telling whether its row needs putting again (`particulars`): everything but the words,
/// which the document carries, and `updatedAt`, which every keystroke moves.
String particulars(Note note) => jsonEncode([note.createdAt, note.sourceWord, note.starred, note.archivedAt, note.path, note.recordingMs]);

String _noteContext(String orgId, String id) => 'org:$orgId:note:$id';
String _updateContext(String orgId, String id) => 'org:$orgId:note:$id:update';

int _numOf(Object? answer, String field) {
  final value = answer is Map ? answer[field] : null;
  return value is num ? value.toInt() : 0;
}

/// Whether a note is a canvas, which this channel passes over (see the header).
bool _canvas(Note note) => (note.path ?? '').toLowerCase().endsWith('.canvas') || isCanvasBody(note.body);

/// [note] with other words, everything else as it is.
Note _withWords(Note note, String words, {int? updatedAt}) => note.body == words && updatedAt == null ? note : note.copyWith(body: words, updatedAt: updatedAt);

/// A team's note as its row says it, with what the row does not say left as this device has it: the phrases of a
/// recording that has not changed, and the formatted version of the same words.
Note _over(Note theirs, Note? whole) {
  if (whole == null) return theirs;
  final segments = theirs.segments == null && whole.segments != null && whole.recordingMs == theirs.recordingMs ? whole.segments : theirs.segments;
  final keepFormatted = theirs.formatted == null && whole.formatted != null && whole.formattedFor == theirs.formattedFor;
  if (identical(segments, theirs.segments) && !keepFormatted) return theirs;
  return Note(
    id: theirs.id,
    body: theirs.body,
    createdAt: theirs.createdAt,
    updatedAt: theirs.updatedAt,
    source: theirs.source,
    sourceName: theirs.sourceName,
    starred: theirs.starred,
    archivedAt: theirs.archivedAt,
    recordingMs: theirs.recordingMs,
    segments: segments,
    formatted: keepFormatted ? whole.formatted : theirs.formatted,
    formattedFor: theirs.formattedFor,
    formattedModel: keepFormatted ? whole.formattedModel : theirs.formattedModel,
    path: theirs.path,
    revision: theirs.revision,
  );
}

/// Sealed bytes opened under the key in force, or, failing that, under the generations before it (S11; `opened`): a
/// row or an update sealed before a turn by a device that had not yet heard of it, or not yet re-sealed. Answers
/// what opened and whether an older key did it, so a row read that way is put again under the key in force.
Future<({T value, bool older})> _opened<T>(TeamSyncContext ctx, Future<T> Function(SealKey key) open) async {
  try {
    return (value: await open(ctx.key), older: false);
  } catch (_) {
    final olderKey = ctx.olderKey;
    if (olderKey == null || ctx._generation == 0) rethrow;
    for (var generation = ctx._generation - 1; generation >= 1; generation -= 1) {
      final SealKey? key;
      try {
        key = await olderKey(generation);
      } catch (_) {
        continue;
      }
      if (key == null) continue;
      try {
        return (value: await open(key), older: true);
      } catch (_) {
        // Not that one either.
      }
    }
    rethrow;
  }
}

/// The note's words from the document, written to the note here when they differ (`writeWords`).
Future<void> _writeWords(TeamSyncContext ctx, String id, String words, _Tally tally) async {
  final local = await ctx.notes.get(id);
  if (local == null || local.body == words) return;
  await ctx.notes.apply(local.copyWith(body: words, updatedAt: ctx._now()));
  tally.changed += 1;
}

// --- pull ------------------------------------------------------------------------------------------------------------

Future<void> _takeRow(TeamSyncContext ctx, _Row item, Note? local, _Tally tally) async {
  final blob = item.blob;
  if (item.deleted || blob == null) {
    if (local != null) {
      await ctx.notes.remove(item.id);
      tally.changed += 1;
    }
    await ctx.docs.drop(item.id);
    ctx.state.notes.remove(item.id);
    return;
  }
  final (value: payload, :older) = await _opened(ctx, (key) async => _Payload.fromJson(await ctx.crypto.open(key, blob, _noteContext(ctx.orgId, item.id)), item.id));
  // A canvas waits for its types (see the header): not taken, and asked about again when its row next changes.
  if (_canvas(payload.note) || (local != null && _canvas(local))) return;
  final held = await ctx.docs.doc(item.id);
  // Words typed here since the document was last written are a change of this device's, reconciled before the row's
  // state comes in, so the merge is the CRDT's and nothing typed is written over.
  if (held != null && local != null) await held.reconcile(local.body);
  final doc = await ctx.docs.adopt(item.id, payload.state, payload.seq);
  // This device's own words, from before the team had the note: a change for the team, not words to lose.
  if (held == null && local != null && local.body != doc.words) await doc.reconcile(local.body);
  // The note first, its history and pictures after every note of the feed is here: a member who has just joined
  // reads the team's words in the time the rows take, not the time sixty files take.
  ctx._later.add(() async {
    final versions = payload.versions;
    if (versions != null) await fetchVersionsOf(ctx._files, item.id, versions);
    for (final name in payload.images) {
      final id = fileId(FileKind.image, name);
      if (id == null || ctx.state.files.containsKey(id)) continue;
      if (await ctx.files.read(FileKind.image, name) != null) continue;
      await fetchFile(ctx._files, FileKind.image, name);
    }
  });
  var theirs = _withWords(payload.note, doc.words);
  if (local == null || local.body != theirs.body || particulars(local) != particulars(theirs)) {
    theirs = _over(theirs, local == null ? null : await ctx.notes.get(item.id));
    await ctx.notes.apply(theirs);
    tally.changed += 1;
  }
  ctx.file(item.id);
  ctx.state.notes[item.id] = TeamMark(rev: item.rev, mark: particulars(theirs));
  // Read under a generation before the turn: put again under the one in force, so every member can read it.
  if (older) await _putRow(ctx, await ctx.notes.get(item.id) ?? theirs, doc, tally);
}

Future<void> _pull(TeamSyncContext ctx, _Tally tally) async {
  for (;;) {
    final page = await ctx.api.callMap('GET', ctx._route('notes?since=${ctx.state.cursor}'), token: ctx.token);
    final items = [for (final raw in page['items'] is List ? page['items'] as List : const <Object?>[]) ?_Row.fromJson(raw)];
    if (items.isNotEmpty) {
      final here = {for (final note in await ctx.notes.list()) note.id: note};
      for (final item in items) {
        if (ctx.state.notes[item.id]?.rev == item.rev) continue;
        // A row that will not be read - sealed under a key this device lacks, or cut short - is counted and passed
        // over, so one bad row does not hold every other note of the team's back; it is tried again when it next
        // changes.
        await _counted(tally, () => _takeRow(ctx, item, here[item.id], tally));
      }
    }
    final rev = _numOf(page, 'rev');
    if (rev > ctx.state.cursor) ctx.state.cursor = rev;
    ctx.save(ctx.state);
    if (page['more'] != true) return;
  }
}

// --- updates ---------------------------------------------------------------------------------------------------------

/// The log since the document's seq, applied; the words written when they changed (`takeUpdates`).
Future<void> _takeUpdates(TeamSyncContext ctx, TeamDoc doc, _Tally tally) async {
  for (;;) {
    final Map<String, Object?> page;
    try {
      page = await ctx.api.callMap('GET', ctx._route('notes/${Uri.encodeComponent(doc.noteId)}/updates?since=${doc.seq}'), token: ctx.token);
    } on ApiError catch (failure) {
      // The row is gone (deleted by another member, not yet pulled here): the next pull takes it.
      if (failure.status == 404) return;
      rethrow;
    }
    final items = [
      for (final raw in page['items'] is List ? page['items'] as List : const <Object?>[])
        if (raw is Map && raw['blob'] is String && raw['seq'] is num) (seq: (raw['seq'] as num).toInt(), blob: raw['blob'] as String),
    ];
    if (items.isNotEmpty) {
      final updates = <Uint8List>[];
      for (final item in items) {
        try {
          updates.add((await _opened(ctx, (key) => ctx.crypto.openBytes(key, fromBase64Url(item.blob), _updateContext(ctx.orgId, doc.noteId)))).value);
        } catch (_) {
          // An update that will not open - sealed under a generation this device lacks - is passed over; the row's
          // next snapshot carries what it did.
        }
      }
      final before = doc.words;
      try {
        await doc.applyRemote(updates, items.last.seq);
      } catch (_) {
        // One of them the core will not hold: the rest applied one at a time, the words written, and the refusal
        // said. The seq stays, so the log is asked again from here.
        Object? refused;
        for (final update in updates) {
          try {
            await doc.applyRemote([update]);
          } catch (failure) {
            refused ??= failure;
          }
        }
        if (doc.words != before) await _writeWords(ctx, doc.noteId, doc.words, tally);
        if (refused != null) throw refused;
      }
      if (doc.words != before) await _writeWords(ctx, doc.noteId, doc.words, tally);
    } else {
      final seq = _numOf(page, 'seq');
      if (seq > doc.seq) doc.seq = seq;
    }
    if (page['more'] != true) return;
  }
}

// --- push ------------------------------------------------------------------------------------------------------------

/// The updates made here, posted in order; the document's seq follows them when nobody else wrote in between
/// (`postPending`).
Future<void> _postPending(TeamSyncContext ctx, Note note, TeamDoc doc, _Tally tally) async {
  for (;;) {
    final all = await doc.pending();
    final pending = all.length > _postAtMost ? all.sublist(0, _postAtMost) : all;
    if (pending.isEmpty) return;
    final blobs = <String>[for (final update in pending) toBase64Url(await ctx.crypto.sealBytes(ctx.key, update, _updateContext(ctx.orgId, doc.noteId)))];
    final int seq;
    try {
      seq = _numOf(await ctx.api.call('POST', ctx._route('notes/${Uri.encodeComponent(doc.noteId)}/updates'), token: ctx.token, body: ctx._body({'blobs': blobs})), 'seq');
    } catch (failure) {
      final turned = turnedKey(failure);
      if (turned != null) throw turned;
      // The log is as long as the service keeps one (S11): a snapshot cuts it, and carries these updates with it.
      final body = failure is ApiError ? failure.body : null;
      if (failure is ApiError && failure.status == 409 && body is Map && body['error'] == 'snapshot') {
        await _putRow(ctx, note, doc, tally);
        continue;
      }
      rethrow;
    }
    await doc.posted(pending.length);
    tally.sent += 1;
    // Exactly these went on at the end of the log: nothing of the team's between, so there is nothing to read back.
    if (seq - pending.length == doc.seq) doc.seq = seq;
  }
}

/// The note's row put (`putRow`): a snapshot of the document, its particulars, and its files sent first.
Future<void> _putRow(TeamSyncContext ctx, Note note, TeamDoc doc, _Tally tally, {bool retry = true}) async {
  final known = ctx.state.notes[note.id];
  final files = ctx._files;
  final versions = await sendVersionsOf(files, note.id);
  final images = imageNames(note.body);
  for (final name in images) {
    final id = fileId(FileKind.image, name);
    if (id == null || ctx.state.files.containsKey(id)) continue;
    final bytes = await ctx.files.read(FileKind.image, name);
    if (bytes != null) await sendFile(files, FileKind.image, name, bytes);
  }
  final covered = (await doc.pending()).length;
  // The note whole, as its file has it: the list's has no phrases and no formatted version.
  final whole = await ctx.notes.get(note.id) ?? note;
  final payload = {
    'v': 1,
    'note': noteToJson(_withWords(whole, doc.words)),
    'state': toBase64Url(await doc.snapshot()),
    'seq': doc.seq,
    if (images.isNotEmpty) 'images': images,
    'versions': ?versions,
  };
  final blob = await ctx.crypto.seal(ctx.key, payload, _noteContext(ctx.orgId, note.id));
  try {
    final answer = await ctx.api.call('PUT', ctx._route('notes/${Uri.encodeComponent(note.id)}'), token: ctx.token, body: ctx._body({'base': known?.rev ?? 0, 'blob': blob, 'upTo': doc.seq}));
    ctx.state.notes[note.id] = TeamMark(rev: _numOf(answer, 'rev'), mark: particulars(note));
    tally.sent += 1;
    doc.snapshotSeq = doc.seq;
    // The snapshot carried the updates pending when it was taken; what was typed since is still pending.
    await doc.posted(covered);
    await doc.flush();
  } catch (failure) {
    final turned = turnedKey(failure);
    if (turned != null) throw turned;
    final winner = failure is ApiError && failure.status == 409 ? _Row.fromJson(failure.body) : null;
    if (winner == null) rethrow;
    // Another member put the row first: theirs merged into the document here, and this one put again from their
    // revision.
    final local = await ctx.notes.get(note.id) ?? note;
    await _takeRow(ctx, winner, local, tally);
    if (retry) await _putRow(ctx, await ctx.notes.get(note.id) ?? note, doc, tally, retry: false);
  }
}

Future<void> _pushOne(TeamSyncContext ctx, Note note, _Tally tally) async {
  final doc = (await ctx.docs.doc(note.id, seedWords: note.body))!;
  await doc.reconcile(note.body);
  final known = ctx.state.notes[note.id];
  if (known != null) await _postPending(ctx, note, doc, tally);
  final due = known == null || known.mark != particulars(note) || doc.seq - doc.snapshotSeq >= snapshotEvery || ctx.files.owed().contains(note.id);
  if (due) {
    await _putRow(ctx, note, doc, tally);
  } else {
    await doc.flush();
  }
}

/// One note's step, its failure counted rather than ending the pass; a lapsed session and a turned key still do
/// (`counted`).
Future<void> _counted(_Tally tally, Future<void> Function() work) async {
  try {
    await work();
  } catch (failure) {
    if ((failure is ApiError && failure.status == 401) || failure is KeyTurned) rethrow;
    tally.unsent += 1;
    tally.reason ??= failureText(failure);
  }
}

Future<void> _push(TeamSyncContext ctx, _Tally tally) async {
  final here = [
    for (final note in await ctx.notes.list())
      if (ctx.isTeamNote(note.id)) note,
  ];
  final present = <String>{};
  for (final note in here) {
    present.add(note.id);
    // A canvas waits for its types (see the header): neither published nor, being here, taken for gone.
    if (_canvas(note)) continue;
    await _counted(tally, () => _pushOne(ctx, note, tally));
  }
  // Gone from here, or taken out of the organization's workspace: gone from the team.
  for (final id in ctx.state.notes.keys.toList()) {
    if (present.contains(id)) continue;
    await _counted(tally, () async {
      final known = ctx.state.notes[id]!;
      final path = ctx._route('notes/${Uri.encodeComponent(id)}');
      try {
        await ctx.api.call('DELETE', path, token: ctx.token, body: ctx._body({'base': known.rev}));
      } on ApiError catch (failure) {
        final winner = failure.status == 409 ? _Row.fromJson(failure.body) : null;
        if (winner == null) rethrow;
        if (!winner.deleted) await ctx.api.call('DELETE', path, token: ctx.token, body: ctx._body({'base': winner.rev}));
      }
      ctx.state.notes.remove(id);
      await ctx.docs.drop(id);
    });
  }
  ctx.save(ctx.state);
}

/// Each live note's log head, in one read, so only the logs that moved are fetched; null from a service without the
/// route yet, which means every log is looked at as before (`heads`).
Future<Map<String, int>?> _heads(TeamSyncContext ctx) async {
  try {
    final answer = await ctx.api.callMap('GET', ctx._route('heads'), token: ctx.token);
    final heads = answer['heads'];
    return {
      if (heads is Map)
        for (final entry in heads.entries)
          if (entry.key is String && entry.value is num) entry.key as String: (entry.value as num).toInt(),
    };
  } catch (failure) {
    if (notYet(failure)) return null;
    rethrow;
  }
}

/// Every team note put again under the key in force, after a turn (docs/SHARED.md, S11; lib/orgs/org_keys.dart
/// `turnOrgKey`; `resealTeamNotes`): the row with the document's whole state, its log cut to it, its versions file
/// and its pictures sent again sealed afresh. Run by the engine right after the turn, on the device that made it,
/// with the team's notes pulled first under the old key so nothing a member wrote is left behind. The service
/// refuses what is still sealed under the old generation, so a device that slept through the turn re-seals its own
/// next.
Future<TeamOutcome> resealTeamNotes(TeamSyncContext ctx) async {
  final tally = _Tally();
  for (final id in ctx.state.notes.keys.toList()) {
    final note = await ctx.notes.get(id);
    final doc = await ctx.docs.doc(id);
    if (note == null || doc == null) continue;
    await _counted(tally, () async {
      for (final name in imageNames(note.body)) {
        final bytes = await ctx.files.read(FileKind.image, name);
        if (bytes != null) await resendFile(ctx._files, FileKind.image, name, bytes);
      }
      // The versions file goes with the row, sent again since its digest is forgotten here.
      final versions = fileId(FileKind.versions, id);
      final kept = versions == null ? null : ctx.state.files[versions];
      if (versions != null && kept != null) ctx.state.files[versions] = FileMark(rev: kept.rev);
      await _putRow(ctx, note, doc, tally);
    });
  }
  ctx.save(ctx.state);
  return tally.outcome;
}

/// One whole sync of a team's notes (`syncTeamNotes`): what changed elsewhere first, then the logs that moved, then
/// what changed here.
Future<TeamOutcome> syncTeamNotes(TeamSyncContext ctx) async {
  final tally = _Tally();
  ctx._later.clear();
  await _pull(ctx, tally);
  if (tally.changed > 0) ctx.pulled?.call();
  final later = ctx._later.toList();
  ctx._later.clear();
  for (final fetch in later) {
    await _counted(tally, fetch);
  }
  final team = [
    for (final note in await ctx.notes.list())
      if (ctx.isTeamNote(note.id) && !_canvas(note)) note,
  ];
  final moved = team.isNotEmpty ? await _heads(ctx) : null;
  for (final note in team) {
    final doc = await ctx.docs.doc(note.id);
    if (doc == null || !ctx.state.notes.containsKey(note.id)) continue;
    // Words that reached the note without the editor go into the document first, so what the log brings merges with
    // them.
    await doc.reconcile(note.body);
    // A log that has not moved past what this device applied is not read: one request for the organization, not one
    // a note.
    if (moved != null && (moved[note.id] ?? 0) <= doc.seq) continue;
    await _counted(tally, () => _takeUpdates(ctx, doc, tally));
  }
  await _push(ctx, tally);
  ctx.save(ctx.state);
  return tally.outcome;
}

/// The channel's context for what the engine hands its hook: this organization's state read from where the engine
/// keeps it, and saved back there.
TeamSyncContext teamContext(TeamPass pass, TeamDocs docs, {int Function()? now}) => TeamSyncContext(
      token: pass.token,
      orgId: pass.org.id,
      key: pass.key,
      notes: pass.notes,
      files: pass.files,
      docs: docs,
      state: TeamSyncState.fromJson(pass.loadState()),
      save: (state) => pass.saveState(state.toJson()),
      api: pass.api,
      crypto: pass.crypto,
      now: now,
      isTeamNote: pass.isTeamNote,
      file: pass.file,
      pulled: pass.pulled,
      generation: pass.generation,
      olderKey: pass.olderKey,
    );

/// The engine's step-5 hook (lib/sync/engine.dart `teamNotes`): one pass of an organization's channel, or, when the
/// key has just turned, every note of the team's sealed again under the new one. [docs] is this device's documents;
/// give the engine `forgetTeams: docs.forget` beside it, so signing out lets them go.
TeamNotesPass teamNotesPass(TeamDocs docs, {int Function()? now}) => (pass) {
      final ctx = teamContext(pass, docs, now: now);
      return pass.reseal ? resealTeamNotes(ctx) : syncTeamNotes(ctx);
    };
