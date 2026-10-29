/// A team's notes kept the same on every member's devices (docs/SHARED.md, S1, S4, S5): the organization channel,
/// run after the account's own sync in every full pass (lib/sync/engine.dart, step 5), once for each organization
/// the person has joined and holds the key of (lib/orgs/org_keys.dart). A port of `src/app/core/team/sync.ts`.
///
/// The document of record is the CRDT (doc.dart). The organization's row for a note carries a snapshot of the
/// document - its state, and the note's words and particulars as they stood - and the log beside it carries every
/// update since, so a pass is:
///
/// 1. **Pull** every row written since the cursor: a deletion takes the note and its document (the document only,
///    for a note this device has filed outside the organization: the person moved it out); a row is adopted
///    into the document held here (merged, never doubled), its words written to the note, the note filed in the
///    organization's workspace, and its files - the versions file merged, the pictures, the recording - fetched
///    where this device lacks them. A note this device had of its own before the team did keeps its words: they
///    are reconciled into the document as a change, so the team gets them. Filed, that is, by the path its row
///    carries: in the folder of the organization's it names, found or made here (lib/team/folders.dart; GHST-107),
///    or in the organization's workspace itself for a note at its own folder.
/// 2. **Updates** since each document's seq, applied, and the words written to the note when they changed.
/// 3. **Push**: words that reached a note without the editor are reconciled into its document; the updates made
///    here are posted to the log; a note new to the team, or one whose particulars changed, or one whose document
///    has gone [snapshotEvery] updates past its last snapshot, is put as a row - with its versions file, pictures
///    and recording sent first - and a row that lost the race is merged and put again. A note no longer here, or no
///    longer filed in the organization's workspace or a folder under it, is deleted from the team. A folder
///    the pass emptied, named by no team note's path any more, is dropped at the end ([TeamFolders.prune]).
///
/// Two members who edited apart merge by the CRDT: nothing here keeps a copy. A note's send that fails is counted
/// and the pass goes on, as the account's sync does; a lapsed session ends it, and so does the key turning under
/// this device ([KeyTurned]).
///
/// **A note's recording travels with it** (GHST-112, Matt 2026-10-23: "even shared notes so people can listen
/// back"): sealed under the organization key as `r-<note id>` in its files, beside the pictures, and named in the
/// row by its fingerprint as the account's payload names it (lib/sync/notes.dart). It is sent before the row, only
/// when it changed ([sendRecordingOf], hashed once per length), and not while the sender's meeting recordings stay
/// on the device; every member's device fetches it when the row lands and it has none or an older one
/// ([_settleRecordings]), and the tape plays there. A device that has not fetched it yet still names it when it
/// puts the row, so no member's put takes it off the others ([_recordingFor]).
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
/// - A canvas is a team's note like any other here, as on the page: its document holds its types beside the text
///   (lib/team/doc.dart), its words are read from them once they are seeded, and words that reach it without its
///   view are read into them.
/// - **A note open in an editor bound to its document is the editor's** ([TeamDoc.editing]): a pass still posts
///   what was typed and applies what the log brings (which the binding puts on the page), but does not read the
///   library's words into the document or write the document's into the library. The page's pass does both from
///   the saved note, which is a save's delay behind its editor.
/// - An update the core refuses fails that note's step, said as its reason; the others of its batch are applied,
///   and the log is asked again from the same seq next pass. (One from the web that splits a character was such
///   an update, and is not any more: crdt.dart reads it as the web's own Yjs does.)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../core/attachment_refs.dart' show attachmentNames;
import '../core/bytes.dart';
import '../core/merge_words.dart';
import '../core/note.dart';
import '../core/note_folders.dart' show orgFolderNames;
import '../core/note_json.dart';
import '../sync/engine.dart' show TeamNotesPass, TeamOutcome, TeamPass;
import '../sync/notes.dart';
import 'doc.dart';
import 'folders.dart';

export '../sync/notes.dart' show KeyTurned;

/// How many updates past its last snapshot a document may go before a pass puts a new one and cuts the log
/// (`SNAPSHOT_EVERY`).
const int snapshotEvery = 200;

/// Updates in one post (server/src/org_notes.rs `UPDATES_PER_POST`).
const int _postAtMost = 100;

/// Per note: the row's revision last seen, the note's particulars then ([particulars]), the fingerprint of the
/// recording the row named, where it named one (GHST-112), and the recording's phrases then ([phrasesMark]): a
/// write-up made after the row went moves no particular, and the row is put again for it. And [from]: the account's
/// revision the note left this account's feed at as it became the team's, as its row said it ([_ownWords]), carried
/// into every row this device puts.
class TeamMark {
  const TeamMark({required this.rev, required this.mark, this.recording, this.phrases, this.from});

  static TeamMark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rev = raw['rev'], mark = raw['mark'], recording = raw['recording'], phrases = raw['phrases'], from = raw['from'];
    if (rev is! num || mark is! String) return null;
    return TeamMark(rev: rev.toInt(), mark: mark, recording: recording is String && recording.isNotEmpty ? recording : null, phrases: phrases is String ? phrases : null, from: from is num ? from.toInt() : null);
  }

  final int rev;
  final String mark;
  final String? recording;
  final String? phrases;
  final int? from;

  Map<String, Object?> toJson() => {'rev': rev, 'mark': mark, 'recording': ?recording, 'phrases': ?phrases, 'from': ?from};

  @override
  bool operator ==(Object other) => other is TeamMark && other.rev == rev && other.mark == mark && other.recording == recording && other.phrases == phrases && other.from == from;

  @override
  int get hashCode => Object.hash(rev, mark, recording, phrases, from);

  @override
  String toString() => 'TeamMark($rev, $mark${recording == null ? '' : ', $recording'})';
}

/// What this build takes of a team's rows, kept with a channel's state ([TeamSyncState.toJson]'s `reads`). 1, or
/// nothing said: words alone, every canvas passed over with no mark kept for it (the builds before 2026-10-09). 2:
/// canvases too.
const int teamReadsNow = 2;

/// What a device remembers of one organization's channel (`TeamSyncState`).
class TeamSyncState {
  TeamSyncState({this.cursor = 0, Map<String, TeamMark>? notes, Map<String, FileMark>? files})
      : notes = notes ?? {},
        files = files ?? {};

  /// A state as kept, forgivingly: what is not there, or not the shape, is empty.
  ///
  /// **A state kept by a build that took less is read from the start once.** The cursor is how far the feed was
  /// read, not what was taken from it: the builds that passed a canvas over went on past its row and kept no mark
  /// for it, so the build that reads canvases never asked for them again and a team's canvases stayed off the
  /// device for good (seen on the Fold, 2026-10-09: nine of a hundred and eight team notes, every one a canvas).
  /// Such a state's cursor is 0 here; the rows already taken are known by their revision and passed over in a
  /// pull, and the ones with no mark are taken.
  factory TeamSyncState.fromJson(Object? raw) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final cursor = map['cursor'], notes = map['notes'], files = map['files'], reads = map['reads'];
    final current = reads is num && reads >= teamReadsNow;
    final state = TeamSyncState(cursor: current && cursor is num ? cursor.toInt() : 0);
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
        'reads': teamReadsNow,
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
    this.leftTeam,
    this.keptOut,
    this.agreed,
    this.leftAt,
    this.account,
    required this.file,
    this.folders,
    this.now,
    this.pulled,
    this.generation,
    this.olderKey,
    this.meetings,
    this.syncMeetingRecordings,
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

  /// Whether a note on this device is filed in this organization's workspace, or in a folder under it.
  final bool Function(String id) isTeamNote;

  /// Whether a note still on this device has left the team, by positive evidence: filed in a workspace this device
  /// knows, outside the organization. Without it, or answering false, a note that is no longer a team note here but
  /// is still on the device keeps its row: the team's notes are never taken from every member because this device
  /// could not place a folder.
  final bool Function(String id)? leftTeam;

  /// Told of a note that stays on this device as its team's row goes: the person moved it out of the organization,
  /// here or on another of their devices. The account's own sync keeps it from an old build's deletion for a while
  /// after (lib/sync/notes.dart [LeftTeams]).
  final void Function(String id)? keptOut;

  /// The words this device and the account last both acknowledged for a note, with the account's revision they were
  /// at (lib/sync/notes.dart `agreedOf`); null where it has none. A note this device had of its own when the team's
  /// row first lands is merged from them, where they can be trusted: only what changed here since is this device's
  /// change ([_ownWords]).
  final ({String words, int rev})? Function(String id)? agreed;

  /// The account's revision a note's words were at when this device took it out of the account's feed as it became
  /// this team's (lib/sync/notes.dart `SyncState.teams`): put in the note's row with [account], so the account's other
  /// devices know which of their own words the team's note grew from.
  final int? Function(String id)? leftAt;

  /// The account this device is signed in to, as the service numbers it: whose revisions [leftAt] and a row's are.
  final int? account;

  /// A note from the team, filed in the organization's workspace on this device: one at the organization's own
  /// folder, or any, where this device has no [folders].
  final void Function(String id) file;

  /// The organization's folders on this device (GHST-107): a note from the team filed by the path its row
  /// carries, and the folders the pass emptied dropped at its end. None, and every note is filed by [file].
  final TeamFolders? folders;

  /// The team's notes are on this device as far as the feed goes, their files still to come: the list can be drawn.
  final void Function()? pulled;

  /// The key's generation (docs/SHARED.md, S11), named on every write so one under a turned key is refused, not
  /// kept. None, or 0, for a service from before generations.
  final int? generation;

  /// The key at an older generation, for a row or an update sealed before a turn and not re-sealed yet.
  final Future<SealKey?> Function(int generation)? olderKey;

  /// Which notes are meetings, and whether their recordings go (the person's Sync meeting recordings), read as the
  /// account's pass reads them: a meeting's recording on a team's note stays here while that is off. None given, it
  /// goes.
  final Map<String, num> Function()? meetings;
  final bool Function()? syncMeetingRecordings;

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
    meetings: meetings,
    syncMeetingRecordings: syncMeetingRecordings,
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
  const _Payload({required this.note, required this.state, required this.seq, this.images = const [], this.versions, this.recording, this.files = const [], this.texts = const [], this.account, this.from});

  factory _Payload.fromJson(Object? raw, String id) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final note = noteFromJson(map['note']);
    final state = map['state'], seq = map['seq'], images = map['images'], versions = map['versions'], files = map['files'], texts = map['texts'];
    final recording = map['recording'];
    final left = map['from'] is Map ? map['from'] as Map : const <Object?, Object?>{};
    if (note == null || state is! String) throw const FormatException('That note of the team’s could not be read.');
    return _Payload(
      note: withId(note, id),
      state: fromBase64Url(state),
      seq: seq is num ? seq.toInt() : 0,
      images: images is List ? images.whereType<String>().toList() : const [],
      versions: versions is String && versions.isNotEmpty ? versions : null,
      recording: recording is String && recording.isNotEmpty ? recording : null,
      files: files is List ? files.whereType<String>().toList() : const [],
      texts: texts is List ? texts.whereType<String>().toList() : const [],
      account: left['account'] is num ? (left['account'] as num).toInt() : null,
      from: left['rev'] is num ? (left['rev'] as num).toInt() : null,
    );
  }

  final Note note;
  final Uint8List state;
  final int seq;
  final List<String> images;
  final String? versions;

  /// The recording's fingerprint, where the note has one that travels.
  final String? recording;

  /// The files the note links, and the things whose words were read (lib/sync/notes.dart's payload has the same).
  final List<String> files;
  final List<String> texts;

  /// Which account's feed the note left, and at which of its revisions, as it became the team's ([TeamMark.from]);
  /// null from a row put by a build that does not say, or for a note that was never an account's.
  final int? account;
  final int? from;
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

/// The recording's length a mark of [particulars] was taken at; null for a mark that does not say.
int? _recordingMsIn(String mark) {
  try {
    final said = jsonDecode(mark);
    return said is List && said.isNotEmpty && said.last is num ? (said.last as num).toInt() : null;
  } on FormatException {
    return null;
  }
}

/// The recording a row of [note] names (GHST-112): the one the row last named, while the note's tape is the length
/// it was then, whichever member puts it, so a device that has not fetched it yet does not take it off the row for
/// everyone; otherwise this device's own, sent first where the organization lacks it, or none where it stays here.
Future<String?> _recordingFor(TeamSyncContext ctx, Note note, TeamMark? known) async {
  final ms = note.recordingMs ?? 0;
  if (ms == 0) return null;
  final named = known?.recording;
  if (named != null && _recordingMsIn(known!.mark) == ms) return named;
  return sendRecordingOf(ctx._files, note);
}

String _noteContext(String orgId, String id) => 'org:$orgId:note:$id';
String _updateContext(String orgId, String id) => 'org:$orgId:note:$id:update';

int _numOf(Object? answer, String field) {
  final value = answer is Map ? answer[field] : null;
  return value is num ? value.toInt() : 0;
}

/// [note] with other words, everything else as it is.
Note _withWords(Note note, String words, {int? updatedAt}) => note.body == words && updatedAt == null ? note : note.copyWith(body: words, updatedAt: updatedAt);

/// A team's note as its row says it, with what the row does not say left as this device has it: the phrases of a
/// recording that has not changed, where the row has none (no list, or an empty one: lib/sync/notes.dart
/// `withPhrases`), and the formatted version of the same words.
Note _over(Note theirs, Note? whole) {
  if (whole == null) return theirs;
  final segments = (theirs.segments?.isEmpty ?? true) && (whole.segments?.isNotEmpty ?? false) && whole.recordingMs == theirs.recordingMs ? whole.segments : theirs.segments;
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
Future<void> _writeWords(TeamSyncContext ctx, TeamDoc doc, _Tally tally) async {
  // Open in an editor bound to it: the words are on the page already, and the editor saves them.
  if (doc.editing) return;
  final id = doc.noteId, words = doc.words;
  final local = await ctx.notes.get(id);
  if (local == null || local.body == words) return;
  await ctx.notes.apply(local.copyWith(body: words, updatedAt: ctx._now()));
  tally.changed += 1;
}

// --- pull ------------------------------------------------------------------------------------------------------------

/// What a note this device had of its own makes of the team's words ([theirs]) as the team's row first lands here:
/// its own words ([mine]) were reconciled into the document whole, as the change they were, which took out of the
/// team's note whatever this device had not had yet. So a meeting lost its summary for every device (Matt's
/// standup, 2026-10-29: the device holding the recording landed its transcript over the words from before the
/// summary, while the device that wrote the summary filed the meeting in HelloTrade › Meetings; the transcript's words
/// took the summary out, and it went from every device). Now, from the words this device last agreed on with the
/// account ([TeamSyncContext.agreed]):
/// - none known, or none to trust, this device's words as before, with the team's summary where they have none;
/// - unchanged here since, the team's: there is nothing of this device's to add;
/// - changed on both sides, both changes, merged by their lines (lib/core/merge_words.dart);
/// - changed at the same lines, this device's words, with the team's summary where they have none.
///
/// THE BASE MUST BE ONE BOTH SIDES GREW FROM (the Testing session, 2026-10-29): merged from words the team's note never
/// had, an addition both have at different places is doubled, and a line one side took out comes back; and "unchanged
/// here since" would take the team's words over whatever this device wrote after them. So the words are trusted only
/// where the team's row says which of the account's revisions the note left the account at ([from]: put there by the
/// device that took it out of the account's feed, [TeamSyncContext.leftAt]) and this device's are at that revision or
/// before it: the account's history runs through every revision up to the one the note left at, which the team's
/// note grew from. Words of a later revision were written after the note went to the team (a device a pass behind
/// put them back as the account's row, and wrote on), and the team's note never had them.
String _ownWords(TeamSyncContext ctx, String id, String mine, String theirs, int? from) {
  final agreed = ctx.agreed?.call(id);
  if (agreed == null || from == null || agreed.rev > from) return withSummaryOf(mine, theirs);
  assert(agreed.rev <= from, 'the base is at or before the revision the team’s note left the account at');
  if (agreed.words == mine) return theirs;
  return mergedWords(agreed.words, mine, theirs) ?? withSummaryOf(mine, theirs);
}

Future<void> _takeRow(TeamSyncContext ctx, _Row item, Note? local, _Tally tally) async {
  final blob = item.blob;
  if (item.deleted || blob == null) {
    // Kept where this device has it filed outside the organization ([TeamSyncContext.leftTeam]): the person moved it
    // out, on this device or on another of theirs whose settings have reached this one, and the deletion is the
    // team's row going, not the note (Matt, 2026-10-29, a note dragged out of an organization; the Workspace picker
    // also moves one into another). Read as gone, the note left the person's own devices too
    // (test/team_sync/move_across_test.dart), and one moved into another organization whose row this pass had just
    // taken was then deleted from that team as well, by the next push here.
    if (local != null && !(ctx.leftTeam?.call(item.id) ?? false)) {
      await ctx.notes.remove(item.id);
      tally.changed += 1;
    } else if (local != null) {
      ctx.keptOut?.call(item.id);
    }
    await ctx.docs.drop(item.id);
    ctx.state.notes.remove(item.id);
    _forgetRecording(ctx, item.id);
    return;
  }
  final (value: payload, :older) = await _opened(ctx, (key) async => _Payload.fromJson(await ctx.crypto.open(key, blob, _noteContext(ctx.orgId, item.id)), item.id));
  final held = await ctx.docs.doc(item.id);
  // Words typed here since the document was last written are a change of this device's, reconciled before the row's
  // state comes in, so the merge is the CRDT's and nothing typed is written over.
  if (held != null && local != null) await held.reconcileKept(local.body);
  final doc = await ctx.docs.adopt(item.id, payload.state, payload.seq);
  // This device's own words, from before the team had the note: a change for the team, not words to lose. Only what
  // changed here is (Matt's standup, 2026-10-29): see [_ownWords].
  // Which of this account's revisions the team's note left the account at: the row's, where it is this account's,
  // else what an earlier row said (a row put again by a build that does not carry it).
  final known = ctx.state.notes[item.id];
  final from = (payload.account != null && payload.account == ctx.account ? payload.from : null) ?? known?.from;
  if (held == null && local != null && local.body != doc.words) {
    final words = _ownWords(ctx, item.id, local.body, doc.words, from);
    if (words != doc.words) await doc.reconcile(words);
  }
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
    await fetchFilesNamed(ctx._files, payload.files, payload.texts);
  });
  // The words are the document's; or, open in an editor bound to it, the ones the editor last saved.
  var theirs = _withWords(payload.note, doc.editing && local != null ? local.body : doc.words);
  // Moved out of the organization here ([TeamSyncContext.leftTeam]) and the row put again by a member before this
  // pass's push takes it away: their words are merged in, but the note stays where the person put it, its file
  // where its filing says. Filed back by the row, and its path the row's, a move out of the team or into another
  // was undone by any edit that crossed it, and one into another organization's folder landed at that
  // organization's top (Matt, 2026-10-29, a note dragged out of an organization).
  final movedOut = local != null && (ctx.leftTeam?.call(item.id) ?? false);
  if (movedOut) theirs = theirs.copyWith(path: () => local.path);
  // The phrases too, where only those moved: a write-up made on another member's device after the row last went.
  final whole = local == null ? null : await ctx.notes.get(item.id);
  final phrased = withPhrases(theirs, whole, known?.phrases);
  final phrasesMoved = whole != null && phrased.note.segments != null && !listEquals(phrased.note.segments, whole.segments);
  if (local == null || local.body != theirs.body || particulars(local) != particulars(theirs) || phrasesMoved) {
    theirs = _over(phrased.note, whole);
    await ctx.notes.apply(theirs);
    tally.changed += 1;
  }
  // Filed where its path says: the file is already there, so the folders only catch up with it.
  final folders = ctx.folders, inFolders = orgFolderNames(theirs.path);
  if (movedOut) {
    // Where the person put it.
  } else if (folders != null && inFolders.isNotEmpty) {
    folders.fileAt(item.id, inFolders);
  } else {
    ctx.file(item.id);
  }
  ctx.state.notes[item.id] = TeamMark(rev: item.rev, mark: particulars(theirs), recording: payload.recording, phrases: phrasesMark(payload.note), from: from);
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
        if (doc.words != before) await _writeWords(ctx, doc, tally);
        if (refused != null) throw refused;
      }
      if (doc.words != before) await _writeWords(ctx, doc, tally);
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
  final recording = await _recordingFor(ctx, note, known);
  final images = imageNames(note.body);
  for (final name in images) {
    final id = fileId(FileKind.image, name);
    if (id == null || ctx.state.files.containsKey(id)) continue;
    final bytes = await ctx.files.read(FileKind.image, name);
    if (bytes != null) await sendFile(files, FileKind.image, name, bytes);
  }
  // The files it links and the words read in its things, as the account's own notes carry them (lib/sync/notes.dart).
  final linked = <String>[
    for (final name in attachmentNames(note.body))
      if (await sendAttachment(files, name)) name,
  ];
  final texts = await sendTextsOf(files, note.body);
  // Owed for its words read since it last went (KeptFiles.owed): going now.
  ctx.files.settled(note.id);
  final covered = (await doc.pending()).length;
  // The note whole, as its file has it: the list's has no phrases and no formatted version.
  final whole = await ctx.notes.get(note.id) ?? note;
  // Which of this account's revisions the note left the account at: this device's own word, else the row's.
  final from = ctx.leftAt?.call(note.id) ?? known?.from;
  final payload = {
    'v': 1,
    'note': noteToJson(_withWords(whole, doc.words)),
    'state': toBase64Url(await doc.snapshot()),
    'seq': doc.seq,
    if (images.isNotEmpty) 'images': images,
    'versions': ?versions,
    'recording': ?recording,
    if (linked.isNotEmpty) 'files': linked,
    if (texts.isNotEmpty) 'texts': texts,
    if (from != null && ctx.account != null) 'from': {'account': ctx.account, 'rev': from},
  };
  final blob = await ctx.crypto.seal(ctx.key, payload, _noteContext(ctx.orgId, note.id));
  try {
    final answer = await ctx.api.call('PUT', ctx._route('notes/${Uri.encodeComponent(note.id)}'), token: ctx.token, body: ctx._body({'base': known?.rev ?? 0, 'blob': blob, 'upTo': doc.seq}));
    ctx.state.notes[note.id] = TeamMark(rev: _numOf(answer, 'rev'), mark: particulars(note), recording: recording, phrases: phrasesMark(whole), from: from);
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

/// Whether a recording on this device is owed to a row that names none (GHST-112): a team's note from before
/// recordings travelled, or a meeting's whose recordings were kept here until the switch said otherwise. Hashed once
/// per length ([sendRecordingOf]), and sent here where the organization lacks it; a device without the tape owes
/// nothing.
Future<bool> _recordingOwed(TeamSyncContext ctx, Note note, TeamMark known) async {
  if ((note.recordingMs ?? 0) == 0 || known.recording != null) return false;
  return await sendRecordingOf(ctx._files, note) != null;
}

/// Whether the note's phrases changed here since its row went (GHST-112): a meeting's write-up or a better pass,
/// which moves none of its particulars.
Future<bool> _phrasesOwed(TeamSyncContext ctx, Note note, TeamMark known) async {
  if (!phrasesMayMove(note, (ctx.now ?? () => DateTime.now().millisecondsSinceEpoch)())) return false;
  final whole = await ctx.notes.get(note.id);
  final phrases = whole == null ? null : phrasesMark(whole);
  return phrases != null && phrases != known.phrases;
}

/// What this device remembers of a note's recording, let go with the note (a team's deletion leaves the sealed
/// file on the service, as it leaves the pictures): the same note filed again sends it again.
void _forgetRecording(TeamSyncContext ctx, String noteId) {
  final id = fileId(FileKind.recording, noteId);
  if (id != null) ctx.state.files.remove(id);
}

/// Every team note's recording this device lacks, or holds an older one of, fetched (GHST-112): the one its row
/// names, once the rows are in. Not over a recording made here since the row (the note's particulars moved): that
/// one is this device's, and the push sends it.
Future<void> _settleRecordings(TeamSyncContext ctx, List<Note> team, _Tally tally) async {
  for (final note in team) {
    final known = ctx.state.notes[note.id];
    final digest = known?.recording;
    if (known == null || digest == null || (note.recordingMs ?? 0) == 0 || known.mark != particulars(note)) continue;
    await _counted(tally, () => fetchRecordingOf(ctx._files, note.id, digest));
  }
}

Future<void> _pushOne(TeamSyncContext ctx, Note note, _Tally tally) async {
  final doc = (await ctx.docs.doc(note.id, seedWords: note.body))!;
  await doc.reconcileKept(note.body);
  final known = ctx.state.notes[note.id];
  if (known != null) await _postPending(ctx, note, doc, tally);
  final due = known == null ||
      known.mark != particulars(note) ||
      doc.seq - doc.snapshotSeq >= snapshotEvery ||
      ctx.files.owed().contains(note.id) ||
      await _recordingOwed(ctx, note, known) ||
      await _phrasesOwed(ctx, note, known);
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
  final all = await ctx.notes.list();
  final here = [
    for (final note in all)
      if (ctx.isTeamNote(note.id)) note,
  ];
  final onDevice = {for (final note in all) note.id};
  final present = <String>{};
  for (final note in here) {
    present.add(note.id);
    await _counted(tally, () => _pushOne(ctx, note, tally));
  }
  // Gone from here, or taken out of the organization's workspace: gone from the team. Only on evidence (2026-10-26:
  // 108 team notes were deleted for every member by a build that read the organizations' folders as personal): a
  // note deleted on this device, or one filed in a workspace this device knows outside the organization
  // ([TeamSyncContext.leftTeam]). One that is here but not placed in the team - unfiled, or in a folder this device
  // cannot place - keeps its row. And a library that reads as empty while the team has notes deletes nothing: that
  // is a library not read, not every note deleted.
  if (all.isEmpty && ctx.state.notes.isNotEmpty) {
    ctx.save(ctx.state);
    return;
  }
  for (final id in ctx.state.notes.keys.toList()) {
    if (present.contains(id)) continue;
    if (onDevice.contains(id) && !(ctx.leftTeam?.call(id) ?? false)) continue;
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
      _forgetRecording(ctx, id);
      await ctx.docs.drop(id);
      // Still here, the person's own note now: its team's row gone by this device's hand.
      if (onDevice.contains(id)) ctx.keptOut?.call(id);
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
/// `turnOrgKey`; `resealTeamNotes`): the row with the document's whole state, its log cut to it, its versions file,
/// its pictures and its recording sent again sealed afresh. Run by the engine right after the turn, on the device
/// that made it, with the team's notes pulled first under the old key so nothing a member wrote is left behind. The
/// service refuses what is still sealed under the old generation, so a device that slept through the turn re-seals
/// its own next.
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
      // The recording the row names, where this device holds it (GHST-112).
      if (ctx.state.notes[id]?.recording != null && (note.recordingMs ?? 0) > 0) {
        final tape = await ctx.files.read(FileKind.recording, id);
        if (tape != null) await resendFile(ctx._files, FileKind.recording, id, tape);
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
  // The folders holding a note as the pass begins: one of them empty at the end was emptied by the team.
  final folders = ctx.folders;
  final filled = folders == null ? const <String>{} : folders.filled(await ctx.notes.list());
  await _pull(ctx, tally);
  if (tally.changed > 0) ctx.pulled?.call();
  final later = ctx._later.toList();
  ctx._later.clear();
  for (final fetch in later) {
    await _counted(tally, fetch);
  }
  final team = [
    for (final note in await ctx.notes.list())
      if (ctx.isTeamNote(note.id)) note,
  ];
  await _settleRecordings(ctx, team, tally);
  final moved = team.isNotEmpty ? await _heads(ctx) : null;
  for (final note in team) {
    final doc = await ctx.docs.doc(note.id);
    if (doc == null || !ctx.state.notes.containsKey(note.id)) continue;
    // Words that reached the note without the editor go into the document first, so what the log brings merges with
    // them.
    await doc.reconcileKept(note.body);
    // A log that has not moved past what this device applied is not read: one request for the organization, not one
    // a note.
    if (moved != null && (moved[note.id] ?? 0) <= doc.seq) continue;
    await _counted(tally, () => _takeUpdates(ctx, doc, tally));
  }
  await _push(ctx, tally);
  ctx.save(ctx.state);
  if (folders != null && filled.isNotEmpty) folders.prune(filled, await ctx.notes.list());
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
      leftTeam: pass.leftTeam,
      keptOut: pass.keptOut,
      agreed: pass.agreed,
      leftAt: pass.leftAt,
      account: pass.accountId,
      file: pass.file,
      folders: pass.folders,
      pulled: pass.pulled,
      generation: pass.generation,
      olderKey: pass.olderKey,
      meetings: pass.meetings,
      syncMeetingRecordings: pass.syncMeetingRecordings,
    );

/// The engine's step-5 hook (lib/sync/engine.dart `teamNotes`): one pass of an organization's channel, or, when the
/// key has just turned, every note of the team's sealed again under the new one. [docs] is this device's documents;
/// give the engine `forgetTeams: docs.forget` beside it, so signing out lets them go.
TeamNotesPass teamNotesPass(TeamDocs docs, {int Function()? now}) => (pass) {
      final ctx = teamContext(pass, docs, now: now);
      return pass.reseal ? resealTeamNotes(ctx) : syncTeamNotes(ctx);
    };
