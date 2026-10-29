/// Notes kept the same on every device (docs/SYNC.md, "Sync"). A port of `src/app/core/sync/notes.ts`.
///
/// AttackFM's change feed, run from both ends. The service keeps each note as a sealed blob with a revision; a device
/// keeps, per note, the revision it last saw and a fingerprint of the note as it was then. So a sync is:
///
/// 1. **Pull** every note written since the cursor. A note unchanged here takes the other device's version; a note
///    changed on both sides keeps both - this device's copy becomes a new note, and the other device's version takes
///    the id. Nothing a person typed is ever thrown away. A deletion only removes a note that was not changed here.
/// 2. **Push** every note whose fingerprint moved, written from the revision last seen. A refusal (409) says what
///    won, which is merged exactly as a pulled note is, and the push is tried again, once.
/// 3. **Settle the pictures** ([settlePictures]): every picture a note here refers to, made whole on both sides.
///
/// A note's recording and pictures travel beside it as sealed files on the `recordings` route: the note says which
/// (by hash, for a recording; by name, for a picture, whose name is never reused), and a device fetches what it
/// lacks. So do the files it links (`file/<name>`, lib/core/attachment_refs.dart), by name as a picture is, when
/// they are no larger than [attachmentSyncLimit], and the words read in its pictures and files (lib/files/
/// read_text.dart), by the thing they were read in: a device that reads a picture after its note was sent owes the
/// note again ([LocalFiles.owed]), so the others hear of the words and fetch them. So does its versions file, by hash, with one difference: two devices that each kept versions are merged,
/// version by version ([sendVersionsOf], [fetchVersionsOf]), and a version kept by hand with no change to the words
/// is sent on its own ([LocalFiles.owed]).
///
/// Three rules keep one tape from stopping the whole sync. A note whose send fails is counted and the loop goes on
/// ([Outcome.unsent], with the first reason); only a lapsed session (401) still ends the pass. A recording over the
/// service's limit ([recordingSyncLimit], a little over two hours) is never sent, decided from its length without
/// reading a byte, and a meeting's recording is not sent while `syncMeetingRecordings` is off (it is on unless the
/// person turned it off: GHST-112). And a tape is hashed only when its length changed ([FileMark.forMs]), through the
/// device's own digest where it has one. A note changed on both sides that differs only by the app's own summary
/// section, or only by the lines of a notebook's index, is not kept twice.
///
/// What differs:
/// - The page's `fetch` and WebCrypto are the [Api] and the [AccountCrypto] the context is given; nothing has a
///   default (docs/STAGE7.md: a development build is given the fake service or a local server).
/// - The state is a class ([SyncState]) with the web's JSON as its kept form, changed in place as the page's object
///   is. The meetings and their switch are read through functions, since the page's context reads them through
///   getters at the moment each recording is decided.
/// - `isSharedLive` (core/live/shared.ts) is the context's [SyncContext.sharedLive]: live typing waits for the CRDT
///   (docs/STAGE7.md, pieces I and K), and whoever builds it hands the function in.
/// - [LocalFiles.digest] answers three things on the page (a hash, `null` for no file, `undefined` for a device
///   that cannot say); here they are a [RecordingDigest] with a hash, one without, and null.
/// - A payload whose note cannot be read is a [FormatException], counted against that note, where the page would
///   apply whatever the blob held.
/// - Which pictures were asked for and not there is kept for the run in one map, as on the page; a test clears it
///   with [forgetPictureAsks].
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../core/attachment_refs.dart';
import '../core/book.dart';
import '../core/bytes.dart';
import '../core/ids.dart';
import '../core/merge_words.dart';
import '../core/note.dart';
import '../core/note_json.dart';
import '../core/note_text.dart';
import '../core/summary_text.dart';
import '../core/versions_file.dart';
import '../meet/meet_note.dart' show ghostLineStart;
import 'sync_marks.dart' show noteSyncMarks;

// --- what this module is given ---------------------------------------------------------------------------------------

/// This device's notes (`LocalNotes`): the library's (lib/sync/local.dart), or a map in the tests.
///
/// [apply] writes a note exactly as given, so it is only ever handed a whole note: one from [get], or one out of
/// another device's payload. A note from [list] has no phrases and no formatted version (docs/STAGE3.md, the first
/// trap), and the pass always asks [get] before it applies one of this device's own.
abstract interface class LocalNotes {
  Future<List<Note>> list();
  Future<Note?> get(String id);
  Future<Note> apply(Note note);
  Future<void> remove(String id);
}

/// Which of a device's files (`FileKind`): a recording or a versions file, by note id, a picture or a file a note
/// links, by name, or the words read in one of those, by `image/<name>` or `file/<name>` (lib/files/read_text.dart).
enum FileKind { recording, image, versions, attachment, text }

/// A recording's fingerprint as the device itself made it: [sha] as [sha] would give it, or null for no file.
@immutable
class RecordingDigest {
  const RecordingDigest(this.sha);

  /// No tape by that name.
  const RecordingDigest.none() : sha = null;

  final String? sha;
}

/// A recording's fingerprint without reading it into the app (`LocalFiles.digest`): a [RecordingDigest], or null
/// where this device cannot say - an older core, a call that failed - and the file is read and hashed here instead.
typedef FileDigest = Future<RecordingDigest?> Function(String name);

/// This device's recordings and versions files (by note id) and pictures (by name) (`LocalFiles`).
abstract interface class LocalFiles {
  Future<Uint8List?> read(FileKind kind, String name);
  Future<void> write(FileKind kind, String name, Uint8List bytes);

  /// How long the file is, in bytes, without reading it; null where this device has none. Asked before a file a
  /// note links is read, so one past [attachmentSyncLimit] is never read into the app to be refused.
  Future<int?> lengthOf(FileKind kind, String name);

  /// Whether this device keeps the files notes link and the words read in them at all: where it does not (an
  /// iPhone, for now), they are neither fetched nor sent.
  bool get keepsMedia;

  /// The notes whose versions file changed here since it was last sent (core/versions/store.ts `unsentVersions`).
  List<String> owed();

  /// Note [name]'s versions file is with the account now.
  void settled(String name);

  /// The device's own digest of a recording, or null where it has none to ask.
  FileDigest? get digest;
}

/// Notes this device keeps that have lately left an organization: the person moved them out, here or on another of
/// their devices, so the team's row went and the note is the account's own again (lib/team/sync.dart
/// `TeamSyncContext.keptOut`). The port's own, against the builds before 2.3.79 (test/team_sync/old_peers_test.dart,
/// 2026-10-29). Such a build removes its copy of a note whose team row goes, wherever it has it filed; and where it
/// had already taken the account's row of it as the person's own, its next push sends the account a deletion, which
/// took the note from every device of the person's, with the words they had written since. So for [leftTeamsKept]
/// after a note leaves a team here:
/// - a deletion of it from the account's feed is not taken: its words here stand and go again, as for a note changed
///   here (`_merge`), which is what the old build's own deletion meets; and
/// - its row is put again every [leftTeamsAgain] ([owed]), so the old build, which skipped the account's row while it
///   had the note filed in the team and then removed its copy, takes it again from the feed as a note it lacks.
/// A note deleted for good on another device within the time is kept, and sent again, here: the price of never
/// losing one to an old build.
abstract interface class LeftTeams {
  /// Whether [id] left a team on this device within [leftTeamsKept].
  bool kept(String id);

  /// Whether [id]'s row is owed to the account again now.
  bool owed(String id);

  /// [id]'s row has just gone to the account.
  void sent(String id);
}

/// How long a note that left a team is kept from the account's deletions and put again ([LeftTeams]): the days an
/// old build may sleep through before it next syncs.
const Duration leftTeamsKept = Duration(days: 14);

/// How often, while kept, its row is put again ([LeftTeams.owed]).
const Duration leftTeamsAgain = Duration(hours: 1);

/// What a pass has found to do and has done, told as it goes (Matt, 2026-10-29: "Also don't spin the progress bar on
/// the sync just make it fill as it's being synced"): rows of the feed to merge, notes to send or delete, a picture or
/// a file to send or fetch. The engine sums the account's pass and every team's into the Syncing job's bar ([SyncCount]).
abstract interface class SyncProgress {
  /// [count] more to do.
  void found(int count);

  /// [count] of them done, however each went.
  void did([int count = 1]);
}

/// The Syncing job's count: what its passes have found to do ([todo]) and done ([done]), and the bar they fill
/// ([fraction]), which never goes back within the job though more is found as it goes, and is 0 before anything is
/// counted. [onChange] hears it as more is found, and as the count goes at most once a whole percent of it (so a pass of
/// a thousand notes is not a thousand changes), and always at the last.
class SyncCount implements SyncProgress {
  SyncCount({this.onChange});

  final void Function(SyncCount count)? onChange;
  int _todo = 0, _done = 0;
  double _fraction = 0;
  int _toldAt = -1;

  int get todo => _todo;
  int get done => _done;
  double get fraction => _fraction;

  /// "12 of 40"; null before anything is counted.
  String? get steps => _todo == 0 ? null : '$_done of $_todo';

  @override
  void found(int count) {
    if (count <= 0) return;
    _todo += count;
    _tell(found: true);
  }

  @override
  void did([int count = 1]) {
    if (count <= 0) return;
    _done = (_done + count).clamp(0, _todo);
    _tell();
  }

  void _tell({bool found = false}) {
    final now = _todo == 0 ? 0.0 : _done / _todo;
    if (now > _fraction) _fraction = now;
    final percent = (now * 100).floor();
    if (!found && percent == _toldAt && _done < _todo) return;
    _toldAt = percent;
    onChange?.call(this);
  }
}

/// [run], one thing of the pass: told to [SyncContext.progress] as one more to do, and done however it went (a picture
/// or a file sent or fetched: one step of the bar).
Future<T> _oneStep<T>(SyncContext ctx, Future<T> Function() run) async {
  ctx.progress?.found(1);
  try {
    return await run();
  } finally {
    ctx.progress?.did();
  }
}

/// What a pass works with (`SyncContext`).
class SyncContext {
  SyncContext({
    required this.token,
    required this.key,
    required this.notes,
    required this.files,
    required this.state,
    required this.save,
    required this.api,
    required this.crypto,
    this.now,
    this.meetings,
    this.syncMeetingRecordings,
    this.onConflict,
    this.teamNote,
    this.sharedLive,
    this.filesRoute,
    this.generation,
    this.leftTeams,
    this.progress,
  });

  final String token;
  final SealKey key;
  final LocalNotes notes;
  final LocalFiles files;
  final SyncState state;

  /// Called after each page of the feed and each push, so an interrupted sync resumes where it stopped.
  final void Function(SyncState state) save;
  final Api api;
  final AccountCrypto crypto;

  /// The time, in ms: swapped in by the tests.
  final int Function()? now;

  /// Which notes are meetings (`preferences().meetings`), read when each recording is decided, not when the pass
  /// began: their audio stays here when [syncMeetingRecordings] says so. None given, it goes.
  final Map<String, num> Function()? meetings;
  final bool Function()? syncMeetingRecordings;

  /// Told of each copy kept because both sides had changed a note: the copy's id and title (lib/sync/record.dart).
  final void Function(({String noteId, String title}) copy)? onConflict;

  /// Whether a note on this device is a team's (docs/SHARED.md, S1): filed in an organization's workspace, and
  /// synced by the organization channel rather than here. One that was the account's is deleted from the account's
  /// feed, so its other devices take it from the team instead; a row of one in the feed is passed over.
  final bool Function(String id)? teamNote;

  /// Whether a note is live with another device right now (core/live/shared.ts `isSharedLive`): neither pushed nor
  /// merged until the session ends.
  final bool Function(String id)? sharedLive;

  /// Where the files are: the account's `recordings`, or an organization's `orgs/<id>/files`.
  final String? filesRoute;

  /// The organization key's generation the files are sealed under (docs/SHARED.md, S11); none for the account's own.
  final int? generation;

  /// The notes lately out of a team here, kept from an old build's deletion ([LeftTeams]); none, and none are.
  final LeftTeams? leftTeams;

  /// Told what the pass finds to do and does ([SyncProgress]); none, and nothing is told.
  final SyncProgress? progress;

  Map<String, num> get _meetings => meetings?.call() ?? const {};
  bool get _syncMeetings => syncMeetingRecordings?.call() ?? true;
  bool _live(String id) => sharedLive?.call(id) ?? false;
  bool _team(String id) => teamNote?.call(id) ?? false;
  int _clock() => (now ?? () => DateTime.now().millisecondsSinceEpoch)();
  bool _keptOut(String id) => leftTeams?.kept(id) ?? false;
  String get _route => filesRoute ?? 'recordings';

  /// `?base=` and, for a team's files, the generation the bytes are sealed under.
  String _query(int base) => '?base=$base${(generation ?? 0) != 0 ? '&generation=$generation' : ''}';
}

/// The organization key turned under this device (docs/SHARED.md, S11; `KeyTurned`): the service refused a body
/// sealed under a generation that is no longer in force, naming the one that is. The pass for that organization
/// stops; the next reads this account's wrap at the new generation and seals under it.
class KeyTurned implements Exception {
  const KeyTurned(this.generation);
  final int generation;

  @override
  String toString() => 'The organization key has turned: this device reads the new one on its next pass.';
}

/// Whether a failure is the service refusing a stale generation: a 409 naming the generation in force (`turnedKey`).
KeyTurned? turnedKey(Object? failure) {
  if (failure is! ApiError || failure.status != 409) return null;
  final body = failure.body;
  if (body is! Map) return null;
  final generation = body['generation'];
  return body['error'] is String && generation is num ? KeyTurned(generation.toInt()) : null;
}

/// The most a recording may be to travel: the service's own limit (server/src/sync.rs `RECORDING_LIMIT`, and
/// org_notes.rs `FILE_LIMIT` for a team's), 256 MiB, which is two hours and nineteen minutes of 16 kHz PCM, so a
/// two-hour meeting goes (GHST-112; 64 MiB, about 35 minutes, until 2026-10-23) (`RECORDING_SYNC_LIMIT`). The
/// service takes a little more than this, for the sealing's own bytes.
const int recordingSyncLimit = 256 * 1024 * 1024;

/// The bytes a recording of [ms] takes: 16 kHz, 16-bit, mono, and the WAV header (`recordingBytes`).
int recordingBytes(int ms) => ms * 32 + 44;

/// The longest recording that travels, as the Account page says it: `2 h 19 min`, `34 min`.
String get longestSyncedSaid {
  final minutes = (recordingSyncLimit - 44) ~/ 32 ~/ 60000;
  return minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${minutes % 60} min';
}

/// Whether a note's recording stays on this device: too big for the service, or a meeting's while those are kept
/// here (`recordingStaysHere`).
bool recordingStaysHere(String id, int? recordingMs, Map<String, num> meetings, {required bool syncMeetingRecordings}) {
  if (recordingMs == null || recordingMs == 0) return false;
  if (recordingBytes(recordingMs) > recordingSyncLimit) return true;
  return meetings.containsKey(id) && !syncMeetingRecordings;
}

/// How many of the notes have a recording that stays on this device: the Account row's "3 recordings stayed on this
/// phone" (`stayedHere`).
int stayedHere(Iterable<Note> notes, {required Map<String, num> meetings, required bool syncMeetingRecordings}) =>
    notes.where((note) => recordingStaysHere(note.id, note.recordingMs, meetings, syncMeetingRecordings: syncMeetingRecordings)).length;

// --- what a device remembers -----------------------------------------------------------------------------------------

/// Per note: the revision last seen, the note's fingerprint then, and its recording's phrases then ([phrasesMark]).
/// A recording's phrases are not in a list read, so they are not in [mark]: a write-up or a better pass that rewrites
/// them after the note went changes nothing [mark] sees, and their own fingerprint is what tells.
///
/// [before] and [beforeRev] are the words this device and the account last agreed on before a deletion was
/// answered with this device's own words, and the account's revision they were at ([agreedOf]): the account's row of a
/// meeting went because another device filed it in an organization, and this one, a pass behind, put its transcript
/// back as the account's row. The team's row is merged against the words from before that when it lands here
/// (lib/team/sync.dart), not the ones this device has just sent. Kept until this device sends an edit of its own
/// again, or takes the note's words from the account.
@immutable
class NoteMark {
  const NoteMark({required this.rev, required this.mark, this.phrases, this.before, this.beforeRev});

  static NoteMark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rev = raw['rev'], mark = raw['mark'], phrases = raw['phrases'], before = raw['before'], beforeRev = raw['beforeRev'];
    if (rev is! num || mark is! String) return null;
    // The words from before a deletion are only of use with the revision they were at.
    final kept = before is String && beforeRev is num;
    return NoteMark(rev: rev.toInt(), mark: mark, phrases: phrases is String ? phrases : null, before: kept ? before : null, beforeRev: kept ? beforeRev.toInt() : null);
  }

  final int rev;
  final String mark;
  final String? phrases;
  final String? before;
  final int? beforeRev;

  Map<String, Object?> toJson() => {'rev': rev, 'mark': mark, 'phrases': ?phrases, 'before': ?before, 'beforeRev': ?beforeRev};

  @override
  bool operator ==(Object other) => other is NoteMark && other.rev == rev && other.mark == mark && other.phrases == phrases && other.before == before && other.beforeRev == beforeRev;

  @override
  int get hashCode => Object.hash(rev, mark, phrases, before, beforeRev);

  @override
  String toString() => 'NoteMark($rev)';
}

/// A recording's phrases, as a fingerprint: how many, and an FNV-1a hash of their times and words. Null for a note
/// with none, which has nothing of its own to send.
String? phrasesMark(Note note) {
  final segments = note.segments;
  if ((note.recordingMs ?? 0) == 0 || segments == null || segments.isEmpty) return null;
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(jsonEncode([for (final s in segments) [s.startMs, s.endMs, s.text]]))) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return '${segments.length}-${hash.toRadixString(36)}';
}

/// How long after a note's last edit its phrases are still looked at for a change made since it went: a write-up
/// or a better pass comes within hours of the take, and the take was an edit. Older notes are not read whole on
/// every pass.
const Duration phrasesWindow = Duration(days: 14);

/// Whether [note]'s phrases may have changed since it went with [known]: a recording, edited within [phrasesWindow].
bool phrasesMayMove(Note note, int now) => (note.recordingMs ?? 0) > 0 && now - note.updatedAt < phrasesWindow.inMilliseconds;

/// [theirs] with the phrases to apply it with, over [whole] (this device's note, read whole), and whether those are
/// this device's own: theirs, unless they have none for the same recording, or this device rewrote its own since
/// they last went ([known]) and theirs are not those, when this device's stand and the push sends them. None is an
/// empty list as much as no list (Matt, 2026-10-24: "when clicking on meetings it doesn't load the transcript"): a
/// Meet note is filed with `[]` while its write-up is to come, and a device that saved it so, with a summary or an
/// edit, sent `[]` over the phrases the write-up had made elsewhere and took them from every device.
({Note note, bool mine}) withPhrases(Note theirs, Note? whole, String? known) {
  if (whole == null || whole.recordingMs != theirs.recordingMs || whole.segments == null) return (note: theirs, mine: false);
  final mine = phrasesMark(whole), their = phrasesMark(theirs);
  final keep = (theirs.segments?.isEmpty ?? true) || (mine != null && known != null && mine != known && their != mine);
  if (!keep || listEquals(theirs.segments, whole.segments)) return (note: theirs, mine: false);
  return (note: theirs.copyWith(segments: whole.segments), mine: true);
}

/// Per synced file: its revision, and for a recording the hash of what it held and the length it was hashed at
/// ([forMs]), so a tape whose length has not moved is not read again; [stayed] marks a recording this device chose
/// to keep (a meeting's, or one over the limit), so it is sent once that choice changes. A revision of 0 is what an
/// older app wrote for a picture it found on this device and never sent: settled like a picture with no entry at
/// all.
@immutable
class FileMark {
  const FileMark({required this.rev, this.sha, this.forMs, this.stayed = false});

  static FileMark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rev = raw['rev'], sha = raw['sha'], forMs = raw['forMs'];
    if (rev is! num) return null;
    return FileMark(rev: rev.toInt(), sha: sha is String ? sha : null, forMs: forMs is num ? forMs.toInt() : null, stayed: raw['stayed'] == true);
  }

  final int rev;
  final String? sha;
  final int? forMs;
  final bool stayed;

  Map<String, Object?> toJson() => {'rev': rev, if (sha != null) 'sha': sha, if (forMs != null) 'forMs': forMs, if (stayed) 'stayed': true};

  @override
  bool operator ==(Object other) => other is FileMark && other.rev == rev && other.sha == sha && other.forMs == forMs && other.stayed == stayed;

  @override
  int get hashCode => Object.hash(rev, sha, forMs, stayed);

  @override
  String toString() => 'FileMark(${jsonEncode(toJson())})';
}

/// What a device remembers of the account's feed (`SyncState`).
class SyncState {
  SyncState({this.cursor = 0, Map<String, NoteMark>? notes, Map<String, FileMark>? files, Map<String, TeamLeft>? teams})
      : notes = notes ?? {},
        files = files ?? {},
        teams = teams ?? {};

  /// A state as kept, forgivingly (`{ ...fallback, ...raw }`): what is not there, or not the shape, is empty.
  factory SyncState.fromJson(Object? raw) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final cursor = map['cursor'], notes = map['notes'], files = map['files'], teams = map['teams'];
    final state = SyncState(cursor: cursor is num ? cursor.toInt() : 0);
    if (teams is Map) {
      for (final entry in teams.entries) {
        final left = TeamLeft.fromJson(entry.value);
        if (entry.key is String && left != null) state.teams[entry.key as String] = left;
      }
    }
    if (notes is Map) {
      for (final entry in notes.entries) {
        final mark = NoteMark.fromJson(entry.value);
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

  /// The last revision of the account's feed this device has read.
  int cursor;

  /// By note id.
  final Map<String, NoteMark> notes;

  /// By the service's file id ([fileId]).
  final Map<String, FileMark> files;

  /// The notes this device took out of the account's feed as they became a team's, by note id ([TeamLeft]): the
  /// revision their words were at then, which the team's row carries, and the words themselves, which this device's
  /// own team's channel merges from when the row first lands here a pass or more later. Kept while the note is a
  /// team's on this device, and for [teamLeftKeptMs].
  final Map<String, TeamLeft> teams;

  /// The same state, with another cursor, notes or files where given.
  SyncState copyWith({int? cursor, Map<String, NoteMark>? notes, Map<String, FileMark>? files}) =>
      SyncState(cursor: cursor ?? this.cursor, notes: notes ?? {...this.notes}, files: files ?? {...this.files}, teams: {...teams});

  Map<String, Object?> toJson() => {
        'cursor': cursor,
        'notes': {for (final entry in notes.entries) entry.key: entry.value.toJson()},
        'files': {for (final entry in files.entries) entry.key: entry.value.toJson()},
        if (teams.isNotEmpty) 'teams': {for (final entry in teams.entries) entry.key: entry.value.toJson()},
      };
}

/// How long this device keeps what it knew of a note's words as it left the account's feed for a team ([TeamLeft]):
/// the team's row lands within a pass or two, and long after that its document is this device's to merge with.
const int teamLeftKeptMs = 14 * 24 * 3600000;

/// A note this device took out of the account's feed as it became a team's ([SyncState.teams]): the account's
/// revision its words were at ([rev]), the words themselves where this device had them ([words]), and when ([at]).
@immutable
class TeamLeft {
  const TeamLeft({required this.rev, this.words, required this.at});

  static TeamLeft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rev = raw['rev'], words = raw['words'], at = raw['at'];
    return rev is num ? TeamLeft(rev: rev.toInt(), words: words is String ? words : null, at: at is num ? at.toInt() : 0) : null;
  }

  final int rev;
  final String? words;
  final int at;

  /// The words and their revision, as [agreedOf] answers them; null where this device did not have them.
  ({String words, int rev})? get agreed {
    final had = words;
    return had == null ? null : (words: had, rev: rev);
  }

  Map<String, Object?> toJson() => {'rev': rev, 'words': ?words, 'at': at};
}

/// A device that has never synced (`emptyState`).
SyncState emptyState() => SyncState();

// --- what travels ----------------------------------------------------------------------------------------------------

/// A note as it is sealed: the note, and the files it needs (`NotePayload`).
class NotePayload {
  const NotePayload({required this.note, this.recording, this.images = const [], this.versions, this.files = const [], this.texts = const []});

  /// A payload as opened, or a [FormatException] for one with no note in it.
  factory NotePayload.fromJson(Object? raw, String id) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final note = noteFromJson(map['note']);
    if (note == null) throw const FormatException('That note could not be read.');
    final images = map['images'], recording = map['recording'], versions = map['versions'], files = map['files'], texts = map['texts'];
    return NotePayload(
      note: withId(note, id),
      recording: recording is String && recording.isNotEmpty ? recording : null,
      images: images is List ? images.whereType<String>().toList() : const [],
      versions: versions is String && versions.isNotEmpty ? versions : null,
      files: files is List ? files.whereType<String>().toList() : const [],
      texts: texts is List ? texts.whereType<String>().toList() : const [],
    );
  }

  final Note note;

  /// The recording's fingerprint, where the note has one that travels.
  final String? recording;
  final List<String> images;

  /// The hash of the note's versions file as sent, where it keeps one.
  final String? versions;

  /// The files the note links, by name: the ones the account holds and those that stay on the device they were
  /// added on alike, so a device knows which to fetch.
  final List<String> files;

  /// The things whose words were read and sent (`image/<name>`, `file/<name>`).
  final List<String> texts;

  Map<String, Object?> toJson() => {
        'v': 1,
        'note': noteToJson(note),
        if (recording != null) 'recording': recording,
        if (images.isNotEmpty) 'images': images,
        if (versions != null) 'versions': versions,
        if (files.isNotEmpty) 'files': files,
        if (texts.isNotEmpty) 'texts': texts,
      };
}

/// One note in the service's change feed, and what a refused write answers with (`FeedItem`).
@immutable
class FeedItem {
  const FeedItem({required this.id, required this.rev, required this.deleted, required this.blob});

  static FeedItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], rev = raw['rev'], blob = raw['blob'];
    if (id is! String || rev is! num) return null;
    return FeedItem(id: id, rev: rev.toInt(), deleted: raw['deleted'] == true, blob: blob is String ? blob : null);
  }

  final String id;
  final int rev;
  final bool deleted;
  final String? blob;
}

/// [note] under another id, everything else as it is.
Note withId(Note note, String id) => note.id == id
    ? note
    : Note(
        id: id,
        body: note.body,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        source: note.source,
        sourceName: note.sourceName,
        starred: note.starred,
        archivedAt: note.archivedAt,
        recordingMs: note.recordingMs,
        segments: note.segments,
        formatted: note.formatted,
        formattedFor: note.formattedFor,
        formattedModel: note.formattedModel,
        path: note.path,
        revision: note.revision,
      );

/// The words a [mark] was taken of (its first field), or null for none: no mark, or `''`, which marks a deletion
/// answered with this device's words.
String? wordsOfMark(String? mark) {
  if (mark == null || mark.isEmpty) return null;
  try {
    final said = jsonDecode(mark);
    return said is List && said.isNotEmpty && said.first is String ? said.first as String : null;
  } on FormatException {
    return null;
  }
}

/// The words this device and the account last both acknowledged for a note, and the account's revision they were at,
/// by its [known] mark: what the team's row is merged from when it first lands over a note this device had
/// (lib/team/sync.dart `_ownWords`, which trusts it only at or before the revision the team's note left the account
/// at). The words from before a deletion this device answered with its own ([NoteMark.before]), else the words of its
/// fingerprint, which are the account's at [NoteMark.rev] (it was sent there, or taken from there); null where it has
/// neither.
({String words, int rev})? agreedOf(NoteMark? known) {
  if (known == null) return null;
  final before = known.before, beforeRev = known.beforeRev;
  if (before != null && beforeRev != null) return (words: before, rev: beforeRev);
  final words = wordsOfMark(known.mark);
  return words == null ? null : (words: words, rev: known.rev);
}

/// The base a row of the account's at revision [rev] is merged against here: the words of [known]'s fingerprint, the
/// account's own at [NoteMark.rev], and only for a later revision, which the account's history then runs through (each
/// put is made from the revision before it, or refused). Null otherwise, and the merge is not tried.
String? _baseFor(NoteMark? known, int rev) {
  if (known == null || known.rev >= rev) return null;
  return wordsOfMark(known.mark);
}

/// What a note is, for telling whether it changed: everything a list read carries (`mark`). A recording's phrases
/// and the formatted text are not in a list read, and move with `recordingMs` and `formattedFor`, which are.
String mark(Note note) => jsonEncode([
      note.body,
      note.createdAt,
      note.updatedAt,
      note.sourceWord,
      note.starred,
      note.archivedAt,
      note.recordingMs,
      note.formattedFor,
      note.formattedModel,
      note.path,
    ]);

final RegExp _plainId = RegExp(r'^[A-Za-z0-9_-]{1,62}$');
final RegExp _pictureName = RegExp(r'^([A-Za-z0-9_-]+)\.([A-Za-z]+)$');
final RegExp _keptName = RegExp(r'^([A-Za-z0-9_-]+)\.([a-z0-9]{1,10})$');

/// The service's name for a file: `r-<note id>` for a recording, `v-<note id>` for a versions file,
/// `i-<ext>-<stem>` for a picture, `a-<ext>-<stem>` for a file a note links, and `t-i-<ext>-<stem>` or
/// `t-a-<ext>-<stem>` for the words read in a picture or a file (named `image/<name>` or `file/<name>`); null for a
/// name it would not take (`fileId`).
String? fileId(FileKind kind, String name) {
  if (kind == FileKind.recording) return _plainId.hasMatch(name) ? 'r-$name' : null;
  if (kind == FileKind.versions) return _plainId.hasMatch(name) ? 'v-$name' : null;
  String? short(String id) => id.length <= 64 ? id : null;
  if (kind == FileKind.attachment) {
    final match = _keptName.firstMatch(name);
    return match == null ? null : short('a-${match.group(2)!}-${match.group(1)!}');
  }
  if (kind == FileKind.text) {
    final picture = name.startsWith('image/');
    if (!picture && !name.startsWith('file/')) return null;
    final inner = name.substring(picture ? 6 : 5);
    final match = (picture ? _pictureName : _keptName).firstMatch(inner);
    return match == null ? null : short('t-${picture ? 'i' : 'a'}-${match.group(2)!.toLowerCase()}-${match.group(1)!}');
  }
  final match = _pictureName.firstMatch(name);
  if (match == null) return null;
  return short('i-${match.group(2)!.toLowerCase()}-${match.group(1)!}');
}

/// A file's fingerprint: the first sixteen bytes of its SHA-256, as hex (`sha`).
Future<String> sha(AccountCrypto crypto, Uint8List bytes) async => toHex((await crypto.sha256(bytes)).sublist(0, 16));

/// A picture's reference in a body: the caption, then the name (core/imageRefs.ts `IMAGE_REF`).
final RegExp imageRef = RegExp(r'!\[([^\]]*)\]\(image/([A-Za-z0-9_.-]+)\)');

/// Every picture a note refers to (core/imageRefs.ts `imageNames`).
List<String> imageNames(String body) => [
      for (final m in imageRef.allMatches(body))
        if ((m.group(2) ?? '').isNotEmpty) m.group(2)!,
    ];

bool _blank(Note note) => note.body.trim().isEmpty && !note.starred && note.archivedAt == null && (note.recordingMs ?? 0) == 0;

/// Whether [note] is opened and left empty, which is not a note yet and is not sent until it has words (the push's
/// rule; the sync marks' too, lib/sync/sync_marks.dart).
bool isBlankNote(Note note) => _blank(note);

/// A caught thing, as words a person can read (core/failure.ts `failureText`).
String failureText(Object failure) {
  if (failure is ApiError) return failure.message;
  if (failure is FormatException) return failure.message;
  final text = '$failure';
  return text.startsWith('Exception: ') ? text.substring('Exception: '.length) : text;
}

// --- files -----------------------------------------------------------------------------------------------------------

const Duration _fileWait = Duration(seconds: 300);

/// How long a file of [bytes] may take to go or come: five minutes, and a second more for every 128 KiB, so a
/// two-hour meeting (230 MB) is not given up on over a megabit a second (`fileWaitFor`).
Duration fileWaitFor(int bytes) => _fileWait + Duration(seconds: bytes ~/ (128 * 1024));

int _revOf(Object? answer) {
  final rev = answer is Map ? answer['rev'] : null;
  return rev is num ? rev.toInt() : 0;
}

Future<int> _putFile(SyncContext ctx, String id, Uint8List sealed, int base) async =>
    _revOf(await ctx.api.call('PUT', '${ctx._route}/$id${ctx._query(base)}', token: ctx.token, bytes: sealed, timeout: fileWaitFor(sealed.length)));

/// One file sealed and sent from the revision this device last saw (`sendFile`).
Future<void> sendFile(SyncContext ctx, FileKind kind, String name, Uint8List bytes, [String? digest]) async {
  final id = fileId(kind, name);
  if (id == null) return;
  final known = ctx.state.files[id];
  final sealed = await ctx.crypto.sealBytes(ctx.key, bytes, 'file:$id');
  int rev;
  // A thin bar where the picture or the recording is drawn while it goes (lib/sync/sync_marks.dart).
  final gone = noteSyncMarks.sending(kind, name);
  try {
    try {
      rev = await _putFile(ctx, id, sealed, known?.rev ?? 0);
    } catch (failure) {
      final turned = turnedKey(failure);
      if (turned != null) throw turned;
      if (failure is! ApiError || failure.status != 409) rethrow;
      // A picture's name is never reused, so one already there is this one, and so is a linked file's; words read in
      // one on two devices are the same words. A recording taken again on two devices: the note that carries it
      // decides which is meant, and this device's note is the one being sent.
      final winner = _revOf(failure.body);
      if (kind == FileKind.image || kind == FileKind.attachment || kind == FileKind.text) {
        ctx.state.files[id] = FileMark(rev: winner);
        return;
      }
      rev = await _putFile(ctx, id, sealed, winner);
    }
  } finally {
    gone();
  }
  ctx.state.files[id] = FileMark(rev: rev, sha: digest != null && digest.isNotEmpty ? digest : null);
}

/// A file sent again whatever the service holds: sealed afresh under the context's key, over the revision there
/// (docs/SHARED.md, S11: a team's files re-sealed after the key turns; `resendFile`).
Future<void> resendFile(SyncContext ctx, FileKind kind, String name, Uint8List bytes) async {
  final id = fileId(kind, name);
  if (id == null) return;
  final sealed = await ctx.crypto.sealBytes(ctx.key, bytes, 'file:$id');
  int rev;
  try {
    rev = await _putFile(ctx, id, sealed, ctx.state.files[id]?.rev ?? 0);
  } catch (failure) {
    final turned = turnedKey(failure);
    if (turned != null) throw turned;
    if (failure is! ApiError || failure.status != 409) rethrow;
    rev = await _putFile(ctx, id, sealed, _revOf(failure.body));
  }
  final was = ctx.state.files[id];
  ctx.state.files[id] = FileMark(rev: rev, sha: was?.sha, forMs: was?.forMs, stayed: was?.stayed ?? false);
}

/// Fetches a file into this device; false when the account has none by that id yet (`fetchFile`).
Future<bool> fetchFile(SyncContext ctx, FileKind kind, String name, [String? digest]) async {
  final id = fileId(kind, name);
  if (id == null) return false;
  try {
    // A recording may be a two-hour meeting's: given the time the largest takes.
    final wait = kind == FileKind.recording ? fileWaitFor(recordingSyncLimit) : _fileWait;
    final fetched = await ctx.api.callBytes('GET', '${ctx._route}/$id', token: ctx.token, timeout: wait);
    await ctx.files.write(kind, name, await ctx.crypto.openBytes(ctx.key, fetched.bytes, 'file:$id'));
    ctx.state.files[id] = FileMark(rev: fetched.rev, sha: digest != null && digest.isNotEmpty ? digest : null);
    return true;
  } on ApiError catch (failure) {
    // Not there yet (the other device is still sending it): the pictures are settled again on a later pass.
    if (failure.status == 404) return false;
    rethrow;
  }
}

/// Whether the account holds a file: its revision; 0 where it has none; null where the question could not be asked
/// (no answer to a HEAD at all), and sending is the way to find out (`heldRev`).
Future<int?> _heldRev(SyncContext ctx, String id) async {
  try {
    final answer = await ctx.api.callBytes('HEAD', '${ctx._route}/$id', token: ctx.token);
    // A picture's revision only says the account has it: pictures are never sent against a base.
    return answer.rev > 1 ? answer.rev : 1;
  } on ApiError catch (failure) {
    if (failure.status == 404) return 0;
    if (failure.status == 0) return null;
    rethrow;
  }
}

/// A note's recording sent where the service lacks it, and its fingerprint for the note to carry: read and hashed
/// only when the tape's length has moved since it was last hashed, through the device's own digest where there is
/// one, and never for a recording that stays on this device (`sendRecordingOf`). A team's note's goes the same way,
/// under the organization's context (lib/team/sync.dart).
Future<String?> sendRecordingOf(SyncContext ctx, Note note) async {
  final id = fileId(FileKind.recording, note.id);
  final ms = note.recordingMs ?? 0;
  if (ms == 0 || id == null) return null;
  final known = ctx.state.files[id];
  if (recordingStaysHere(note.id, ms, ctx._meetings, syncMeetingRecordings: ctx._syncMeetings)) {
    // Kept here on purpose, and remembered as such: once the choice changes it is owed, and hashed afresh then.
    ctx.state.files[id] = FileMark(rev: known?.rev ?? 0, stayed: true);
    return null;
  }
  // Hashed at this length already: nothing is read, and a tape that was not there is not asked about again.
  if (known?.forMs == ms) return known?.sha;
  Uint8List? bytes;
  String? digest;
  var said = false;
  final ask = ctx.files.digest;
  if (ask != null) {
    final answer = await ask(note.id);
    if (answer != null) {
      said = true;
      digest = answer.sha;
    }
  }
  if (!said) {
    bytes = await ctx.files.read(FileKind.recording, note.id);
    digest = bytes != null ? await sha(ctx.crypto, bytes) : null;
  }
  if (digest == null) {
    ctx.state.files[id] = FileMark(rev: known?.rev ?? 0, forMs: ms);
    return null;
  }
  if (known?.sha != digest) {
    bytes ??= await ctx.files.read(FileKind.recording, note.id);
    if (bytes != null) await sendFile(ctx, FileKind.recording, note.id, bytes, digest);
  }
  final sent = ctx.state.files[id];
  ctx.state.files[id] = FileMark(rev: sent?.rev ?? known?.rev ?? 0, sha: digest, forMs: ms);
  return digest;
}

Uint8List _asBytes(String text) => utf8.encode(text);

/// A note's versions file sent where the account's differs, answering its hash for the note to carry
/// (`sendVersionsOf`). Where another device wrote the account's since this one last saw it (a 409), theirs is
/// fetched and merged with this one's, the merge is kept here, and the merge is what is sent.
Future<String?> sendVersionsOf(SyncContext ctx, String noteId) async {
  final id = fileId(FileKind.versions, noteId);
  if (id == null) return null;
  final bytes = await ctx.files.read(FileKind.versions, noteId);
  if (bytes == null) return null;
  var text = utf8.decode(bytes, allowMalformed: true);
  var digest = await sha(ctx.crypto, bytes);
  final known = ctx.state.files[id];
  if (known?.sha == digest) {
    ctx.files.settled(noteId);
    return digest;
  }
  Future<int> put(int base, String body) async => _putFile(ctx, id, await ctx.crypto.sealBytes(ctx.key, _asBytes(body), 'file:$id'), base);
  int rev;
  try {
    rev = await put(known?.rev ?? 0, text);
  } catch (failure) {
    final turned = turnedKey(failure);
    if (turned != null) throw turned;
    if (failure is! ApiError || failure.status != 409) rethrow;
    // Another device kept versions too: both sides' versions, once each, are what goes.
    final theirs = await ctx.api.callBytes('GET', '${ctx._route}/$id', token: ctx.token, timeout: _fileWait);
    final merged = mergeFiles(text, utf8.decode(await ctx.crypto.openBytes(ctx.key, theirs.bytes, 'file:$id'), allowMalformed: true), noteId);
    if (merged != null && merged != text) {
      // Kept here and sent at once below; the others hear of it by the note this file goes with.
      text = merged;
      await ctx.files.write(FileKind.versions, noteId, _asBytes(text));
    }
    digest = await sha(ctx.crypto, _asBytes(text));
    rev = await put(theirs.rev, text);
  }
  ctx.state.files[id] = FileMark(rev: rev, sha: digest);
  ctx.files.settled(noteId);
  return digest;
}

/// A note's versions file from another device, merged into this one's: theirs as it is where this device has none,
/// and every version of both where it has one (`fetchVersionsOf`). Remembered at their hash, so a merge that holds
/// versions they lack is sent.
Future<void> fetchVersionsOf(SyncContext ctx, String noteId, String digest) async {
  final id = fileId(FileKind.versions, noteId);
  if (id == null || ctx.state.files[id]?.sha == digest) return;
  final ({Uint8List bytes, int rev}) fetched;
  try {
    fetched = await ctx.api.callBytes('GET', '${ctx._route}/$id', token: ctx.token, timeout: _fileWait);
  } on ApiError catch (failure) {
    if (failure.status == 404) return;
    rethrow;
  }
  final theirs = utf8.decode(await ctx.crypto.openBytes(ctx.key, fetched.bytes, 'file:$id'), allowMalformed: true);
  final here = await ctx.files.read(FileKind.versions, noteId);
  final mine = here == null ? null : utf8.decode(here, allowMalformed: true);
  final merged = mine != null ? mergeFiles(mine, theirs, noteId) : theirs;
  if (merged != null && (mine == null || merged != mine)) await ctx.files.write(FileKind.versions, noteId, _asBytes(merged));
  ctx.state.files[id] = FileMark(rev: fetched.rev, sha: await sha(ctx.crypto, _asBytes(theirs)));
}

/// What a note needs sent before it: its recording, pictures and versions, where the service lacks them
/// (`sendFilesOf`). Answers the payload that names them.
Future<NotePayload> _sendFilesOf(SyncContext ctx, Note note) async {
  final recording = await sendRecordingOf(ctx, note);
  final versions = await sendVersionsOf(ctx, note.id);
  final images = imageNames(note.body);
  for (final name in images) {
    final id = fileId(FileKind.image, name);
    if (id == null || ctx.state.files.containsKey(id)) continue;
    final bytes = await ctx.files.read(FileKind.image, name);
    if (bytes != null) await sendFile(ctx, FileKind.image, name, bytes);
  }
  final files = <String>[
    for (final name in attachmentNames(note.body))
      if (await sendAttachment(ctx, name)) name,
  ];
  final texts = await sendTextsOf(ctx, note.body);
  // Whatever this device owed of the note's files has gone with it: its versions (sent above) and its words.
  ctx.files.settled(note.id);
  return NotePayload(note: note, recording: recording, images: images, versions: versions, files: files, texts: texts);
}

/// A file a note links, sent where the account lacks it and it is no larger than [attachmentSyncLimit]; one
/// larger stays on the device it was added on. Its length is asked first, so a large one is never read. Answers
/// whether the file travels, for the payload to name it: false only for one here that is too large.
Future<bool> sendAttachment(SyncContext ctx, String name) async {
  final id = fileId(FileKind.attachment, name);
  if (id == null) return false;
  if (ctx.state.files.containsKey(id)) return true;
  final length = await ctx.files.lengthOf(FileKind.attachment, name);
  if (length == null) return true;
  if (length > attachmentSyncLimit) return false;
  final bytes = await ctx.files.read(FileKind.attachment, name);
  if (bytes != null) await sendFile(ctx, FileKind.attachment, name, bytes);
  return true;
}

/// The words read in the pictures and files of [body], sent where the account lacks them; answers the things
/// whose words this device holds, for the note's payload to name.
Future<List<String>> sendTextsOf(SyncContext ctx, String body) async {
  final held = <String>[];
  for (final key in readKeysIn(body)) {
    final id = fileId(FileKind.text, key);
    if (id == null) continue;
    if ((ctx.state.files[id]?.rev ?? 0) > 0) {
      held.add(key);
      continue;
    }
    final bytes = await ctx.files.read(FileKind.text, key);
    if (bytes == null) continue;
    await sendFile(ctx, FileKind.text, key, bytes);
    held.add(key);
  }
  return held;
}

/// Every picture and file of [body] words could be read in, as the words are named: `image/<name>`, `file/<name>`.
List<String> readKeysIn(String body) => <String>{
      for (final name in imageNames(body)) 'image/$name',
      for (final name in attachmentNames(body)) 'file/$name',
    }.toList();

/// Note [noteId]'s recording fetched where this device has none, or another than the one with fingerprint [digest]
/// (`fetchRecordingOf`); false where it was not fetched, there already or not on the service yet.
Future<bool> fetchRecordingOf(SyncContext ctx, String noteId, String digest) async {
  final id = fileId(FileKind.recording, noteId);
  if (id == null || ctx.state.files[id]?.sha == digest) return false;
  return fetchFile(ctx, FileKind.recording, noteId, digest);
}

/// What a note from another device needs fetched: its recording, pictures and versions, where this device lacks
/// them (`fetchFilesOf`).
Future<void> _fetchFilesOf(SyncContext ctx, NotePayload payload) async {
  final versions = payload.versions;
  if (versions != null) await fetchVersionsOf(ctx, payload.note.id, versions);
  final recording = payload.recording;
  if (recording != null) await fetchRecordingOf(ctx, payload.note.id, recording);
  for (final name in payload.images) {
    final id = fileId(FileKind.image, name);
    if (id == null || ctx.state.files.containsKey(id)) continue;
    // Here already, by some other road than sync: whether the account has it too is the settling's to find out.
    if (await ctx.files.read(FileKind.image, name) != null) continue;
    await fetchFile(ctx, FileKind.image, name);
  }
  await fetchFilesNamed(ctx, payload.files, payload.texts);
}

/// The files a note links and the words read in its things, fetched where this device lacks them: what a note's
/// payload names beside its pictures (never a file too large to travel, which the device that has it leaves out).
/// A file still on its way is not in the account yet (a 404), and is asked for again by the settling.
Future<void> fetchFilesNamed(SyncContext ctx, List<String> files, List<String> texts) async {
  if (!ctx.files.keepsMedia) return;
  for (final name in files) {
    final id = fileId(FileKind.attachment, name);
    if (id == null || ctx.state.files.containsKey(id)) continue;
    if (await ctx.files.lengthOf(FileKind.attachment, name) != null) continue;
    await fetchFile(ctx, FileKind.attachment, name);
  }
  for (final key in texts) {
    final id = fileId(FileKind.text, key);
    if (id == null || ctx.state.files.containsKey(id)) continue;
    if (await ctx.files.lengthOf(FileKind.text, key) != null) continue;
    await fetchFile(ctx, FileKind.text, key);
  }
}

/// A picture the account did not have when last asked, by id, and when: not asked for again for a while.
final Map<String, int> _unsent = {};

/// Less than the five minutes between passes, so every timed pass asks, and the passes a keystroke sets off don't
/// (`ASK_AGAIN_MS`).
const int askAgainMs = 4 * 60000;

/// Forgets which pictures were asked for and not there: for a test that starts another device's life.
@visibleForTesting
void forgetPictureAsks() => _unsent.clear();

/// Every picture a note on this device refers to, made whole on both sides: one this device holds and the account
/// lacks is sent, one the account holds and this device lacks is fetched (`settlePictures`). A picture settled once
/// is not looked at again. Runs at the end of every pass, after the notes, so a picture is never sent ahead of a note
/// that names it.
///
/// Sending a picture only with its note's push missed a picture that reached a device some other way than the app:
/// a note written through the MCP names pictures another program dropped into the Mac's picture folder, the Mac pulls
/// the note, finds the files, and nothing sends them. And a device that asked for a picture before it was sent only
/// asked when the note arrived, never again.
Future<void> settlePictures(SyncContext ctx) async {
  final now = ctx.now ?? () => DateTime.now().millisecondsSinceEpoch;
  final seen = <String>{};
  for (final note in await ctx.notes.list()) {
    await _settleAttachmentsOf(ctx, note.body, seen, now);
    for (final name in imageNames(note.body)) {
      final id = fileId(FileKind.image, name);
      if (id == null || !seen.add(id)) continue;
      if ((ctx.state.files[id]?.rev ?? 0) > 0) continue;
      final bytes = await ctx.files.read(FileKind.image, name);
      if (bytes != null) {
        final held = await _heldRev(ctx, id);
        if (held != null && held > 0) {
          ctx.state.files[id] = FileMark(rev: held);
        } else {
          await _oneStep(ctx, () => sendFile(ctx, FileKind.image, name, bytes));
        }
        continue;
      }
      final asked = _unsent[id];
      if (asked != null && now() - asked < askAgainMs) continue;
      if (await _oneStep(ctx, () => fetchFile(ctx, FileKind.image, name))) {
        _unsent.remove(id);
      } else {
        _unsent[id] = now();
      }
    }
  }
  ctx.save(ctx.state);
}

/// The files a note links, made whole on both sides as its pictures are ([settlePictures]): one this device holds
/// and the account lacks is sent (when it is no larger than [attachmentSyncLimit]), one the account holds and this
/// device lacks is fetched, and one its line says is larger is not asked for. Then the words read in its things
/// that this device holds and the account lacks are sent; the others fetch them by the note that names them.
Future<void> _settleAttachmentsOf(SyncContext ctx, String body, Set<String> seen, int Function() now) async {
  if (!ctx.files.keepsMedia) return;
  if (body.contains('](file/')) {
    for (final match in attachmentRef.allMatches(body)) {
      final name = match.group(2)!;
      final id = fileId(FileKind.attachment, name);
      if (id == null || !seen.add(id)) continue;
      if ((ctx.state.files[id]?.rev ?? 0) > 0) continue;
      final length = await ctx.files.lengthOf(FileKind.attachment, name);
      if (length != null) {
        if (length > attachmentSyncLimit) continue;
        final held = await _heldRev(ctx, id);
        if (held != null && held > 0) {
          ctx.state.files[id] = FileMark(rev: held);
        } else {
          final bytes = await ctx.files.read(FileKind.attachment, name);
          if (bytes != null) await _oneStep(ctx, () => sendFile(ctx, FileKind.attachment, name, bytes));
        }
        continue;
      }
      // Larger than travels, as the line that links it says: it stays where it was added, and nobody asks.
      if ((bytesOfSize(match.group(3)) ?? 0) > attachmentSyncLimit) continue;
      final asked = _unsent[id];
      if (asked != null && now() - asked < askAgainMs) continue;
      if (await _oneStep(ctx, () => fetchFile(ctx, FileKind.attachment, name))) {
        _unsent.remove(id);
      } else {
        _unsent[id] = now();
      }
    }
  }
  if (!body.contains('](image/') && !body.contains('](file/')) return;
  for (final key in readKeysIn(body)) {
    final id = fileId(FileKind.text, key);
    if (id == null || !seen.add(id)) continue;
    if ((ctx.state.files[id]?.rev ?? 0) > 0) continue;
    if (await ctx.files.lengthOf(FileKind.text, key) == null) continue;
    final bytes = await ctx.files.read(FileKind.text, key);
    if (bytes != null) await _oneStep(ctx, () => sendFile(ctx, FileKind.text, key, bytes));
  }
}

// --- merging one note ------------------------------------------------------------------------------------------------

/// How a pass went (`Outcome`).
class Outcome {
  Outcome({this.changed = 0, this.conflicts = 0, this.unsent = 0, this.reason});

  /// Notes written, removed or copied on this device.
  int changed;

  /// Notes kept twice because both sides changed them.
  int conflicts;

  /// Notes whose send failed this pass, and the first reason: sent again next pass.
  int unsent;
  String? reason;

  @override
  bool operator ==(Object other) => other is Outcome && other.changed == changed && other.conflicts == conflicts && other.unsent == unsent && other.reason == reason;

  @override
  int get hashCode => Object.hash(changed, conflicts, unsent, reason);

  @override
  String toString() => 'Outcome(changed: $changed, conflicts: $conflicts, unsent: $unsent, reason: $reason)';
}

final RegExp _blankRun = RegExp(r'\n{3,}');

/// A notebook's body with the lines of its index taken out, and its blank lines as one: what two copies must agree
/// on (`besideIndex`).
String _besideIndex(String body) {
  final index = {for (final chapter in chaptersOf(body)) chapter.line};
  final lines = body.split('\n');
  final kept = [
    for (var line = 0; line < lines.length; line += 1)
      if (!index.contains(line)) lines[line],
  ];
  return kept.join('\n').replaceAll(_blankRun, '\n\n').trimRight();
}

/// Two copies of one notebook that differ only by the lines of their index (lib/core/book.dart), merged: theirs,
/// with each line this device has and theirs lacks put after the line it followed here (`mergedIndex`). Null where
/// they differ in anything else, or either is not a notebook. Two devices each adding a page, or a journal's entry,
/// between syncs is the common case, and a copy of "Diary" for it would be "Diary 2". A line taken out on one side
/// and kept on the other comes back: the lesser harm.
String? mergedIndex(String mine, String theirs) {
  if (!isBookBody(mine) || !isBookBody(theirs) || _besideIndex(mine) != _besideIndex(theirs)) return null;
  final here = chaptersOf(mine);
  var merged = theirs;
  for (var at = 0; at < here.length; at += 1) {
    final chapter = here[at];
    if (chaptersOf(merged).any((there) => sameTitle(there.title, chapter.title))) continue;
    merged = withChapter(merged, chapter.title, at > 0 ? here[at - 1].title : null);
  }
  return merged;
}

Note _withBody(Note note, String body) => note.copyWith(body: body);

/// This device's side of a conflict: the words, under a new id, with no file of its own yet and no recording (the
/// recording is filed under the note's id, which the other version keeps).
Note _copyOf(Note full) => Note(
      id: randomId('n'),
      body: full.body,
      createdAt: full.createdAt,
      updatedAt: full.updatedAt,
      source: full.source,
      sourceName: full.sourceName,
      starred: full.starred,
      archivedAt: full.archivedAt,
      formatted: full.formatted,
      formattedFor: full.formattedFor,
      formattedModel: full.formattedModel,
      revision: full.revision,
    );

/// Whether the note [id] is a meeting: one this account keeps as a meeting, or one Ghost was in.
bool _isMeeting(SyncContext ctx, String id, Note local, Note theirs) =>
    ctx._meetings.containsKey(id) || local.body.contains(ghostLineStart) || theirs.body.contains(ghostLineStart);

/// One note from the service, merged into this device (`merge`). [local] is the note here as the list has it, or
/// null when there is none. A note left differing from its recorded fingerprint is sent by the push that follows.
Future<void> _merge(SyncContext ctx, FeedItem item, Note? local, Outcome outcome) async {
  final known = ctx.state.notes[item.id];
  final changedHere = local != null ? known == null || known.mark != mark(local) : known != null;

  final blob = item.blob;
  if (item.deleted || blob == null || blob.isEmpty) {
    // Lately out of a team here, it is not taken either: an old build's removal of its copy said as a deletion
    // ([LeftTeams]).
    if (local != null && (changedHere || ctx._keptOut(item.id))) {
      // Deleted there, changed here: this device's words stand, and are sent again from the deletion's revision. The
      // words both had before are kept with it: the deletion may be the note going to a team, whose row is merged
      // against them when it lands here ([NoteMark.before]).
      final agreed = agreedOf(known);
      ctx.state.notes[item.id] = NoteMark(rev: item.rev, mark: '', before: agreed?.words, beforeRev: agreed?.rev);
      return;
    }
    if (local != null) {
      await ctx.notes.remove(item.id);
      outcome.changed += 1;
    }
    ctx.state.notes.remove(item.id);
    return;
  }

  final payload = NotePayload.fromJson(await ctx.crypto.open(ctx.key, blob, 'note:${item.id}'), item.id);
  final theirs = payload.note;
  // This device's note read whole, for its phrases, where either side has a recording: the list's has none.
  final whole = local != null && ((theirs.recordingMs ?? 0) > 0 || (local.recordingMs ?? 0) > 0) ? await ctx.notes.get(item.id) : null;
  // Only the words are worth keeping twice: a pin, the archive or a folder changed on both sides takes theirs.
  if (local != null && changedHere && local.body != theirs.body) {
    if (withoutSummary(local.body) == withoutSummary(theirs.body)) {
      // The two differ only by the app's own summary section: theirs, with this device's section on it, and no copy.
      // The mark kept is theirs as the service has it, so the push that follows sends the merged note.
      final mine = summarySection(local.body);
      final merged = _withBody(theirs, mine != null ? withSummary(theirs.body, mine.text, kept: summarySection(theirs.body)?.text) : withoutSummary(theirs.body));
      await _fetchFilesOf(ctx, payload);
      await ctx.notes.apply(withPhrases(merged, whole, known?.phrases).note);
      outcome.changed += 1;
      ctx.state.notes[item.id] = NoteMark(rev: item.rev, mark: mark(theirs), phrases: phrasesMark(theirs));
      return;
    }
    final index = mergedIndex(local.body, theirs.body);
    if (index != null) {
      // Two copies of one notebook that differ only by their index's lines: theirs, with the lines only this device
      // has, and no copy. As with the summary above, the mark kept is theirs, so the push that follows sends the
      // merge.
      await _fetchFilesOf(ctx, payload);
      await ctx.notes.apply(withPhrases(_withBody(theirs, index), whole, known?.phrases).note);
      outcome.changed += 1;
      ctx.state.notes[item.id] = NoteMark(rev: item.rev, mark: mark(theirs), phrases: phrasesMark(theirs));
      return;
    }
    // A meeting changed on both sides at different lines: both changes, in one note (lib/core/merge_words.dart; Matt,
    // 2026-10-29: "make it so the transcripts and meeting summaries are shown in one file"). Its summary written on one
    // device and its transcript landed on another, over the words from before the summary, are such a pair, and were
    // kept as two notes. As above, the mark kept is theirs, so the push that follows sends the merge. Any other note
    // changed on both sides is kept twice as it always was.
    final base = _isMeeting(ctx, item.id, local, theirs) ? _baseFor(known, item.rev) : null;
    final both = base == null ? null : mergedWords(base, local.body, theirs.body);
    if (both != null) {
      await _fetchFilesOf(ctx, payload);
      await ctx.notes.apply(withPhrases(_withBody(theirs, both), whole, known?.phrases).note);
      outcome.changed += 1;
      ctx.state.notes[item.id] = NoteMark(rev: item.rev, mark: mark(theirs), phrases: phrasesMark(theirs));
      return;
    }
    // Changed on both sides and not the same: this device's version is kept as a note of its own.
    final full = await ctx.notes.get(item.id) ?? local;
    final copy = await ctx.notes.apply(_copyOf(full));
    outcome.conflicts += 1;
    outcome.changed += 1;
    final title = noteTitle(copy.body);
    ctx.onConflict?.call((noteId: copy.id, title: title.isEmpty ? 'Untitled' : title));
  }
  await _fetchFilesOf(ctx, payload);
  // Their phrases too where only those moved: a write-up or a better pass made on another device after the words
  // went (GHST-112). This device's own stand where it rewrote them since, and go with the push that follows.
  final phrased = withPhrases(theirs, whole, known?.phrases);
  final same = local != null && mark(local) == mark(theirs) && (whole == null || listEquals(phrased.note.segments, whole.segments));
  final applied = same ? local : await ctx.notes.apply(phrased.note);
  if (!same) outcome.changed += 1;
  // Theirs are what the service has: where this device's own stood over them, the push that follows sends them, and
  // a device that summarized a meeting it never had the phrases of gets them back.
  ctx.state.notes[item.id] = NoteMark(rev: item.rev, mark: mark(applied), phrases: phrasesMark(theirs));
}

// --- the two halves --------------------------------------------------------------------------------------------------

Future<void> _pull(SyncContext ctx, Outcome outcome) async {
  for (;;) {
    final page = await ctx.api.callMap('GET', 'notes?since=${ctx.state.cursor}', token: ctx.token);
    final raw = page['items'];
    final items = [
      if (raw is List)
        for (final each in raw) ?FeedItem.fromJson(each),
    ];
    if (items.isNotEmpty) {
      final here = {for (final note in await ctx.notes.list()) note.id: note};
      final taken = [
        for (final item in items)
          // A revision already seen is this device's own write coming back.
          if (ctx.state.notes[item.id]?.rev != item.rev &&
              // A team's note now (docs/SHARED.md, S1): the organization channel has it, and the account's row is
              // stale.
              !ctx._team(item.id) &&
              // Live with another device right now: its words are arriving a keystroke at a time already, and a merge
              // made mid-sentence would take the few characters still in flight for a conflict. Its revision stays
              // unrecorded, so once the session ends the push meets it as a 409 and finds the same words
              // (docs/LIVE.md).
              !ctx._live(item.id))
            item,
      ];
      // The page's rows to take, each one step of the bar.
      ctx.progress?.found(taken.length);
      for (final item in taken) {
        await _merge(ctx, item, here[item.id], outcome);
        ctx.progress?.did();
      }
    }
    final rev = page['rev'];
    if (rev is num && rev > ctx.state.cursor) ctx.state.cursor = rev.toInt();
    ctx.save(ctx.state);
    if (page['more'] != true) return;
  }
}

Future<Note?> _listed(SyncContext ctx, String id) async {
  for (final note in await ctx.notes.list()) {
    if (note.id == id) return note;
  }
  return null;
}

/// The account's words for a note that is a team's on this device, written by another of the person's devices after
/// this one last agreed with the account ([known]): merged into the note here ([mergedWords]), which the team's
/// channel then carries to everyone, and never written over it. Where the two changed the same lines, the note keeps
/// its words, with the summary the account's words have where it has none: a meeting's summary is never lost to its
/// transcript's side (Matt's standup, 2026-10-29).
/// Answers the account's words, or null where there were none to take.
Future<String?> _mergeIntoTeams(SyncContext ctx, FeedItem winner, NoteMark? known, Outcome outcome) async {
  final blob = winner.blob;
  if (winner.deleted || blob == null || blob.isEmpty) return null;
  final local = await ctx.notes.get(winner.id);
  if (local == null) return null;
  final payload = NotePayload.fromJson(await ctx.crypto.open(ctx.key, blob, 'note:${winner.id}'), winner.id);
  final theirs = payload.note.body;
  if (theirs == local.body) return theirs;
  final base = _baseFor(known, winner.rev);
  final words = (base == null ? null : mergedWords(base, local.body, theirs)) ?? withSummaryOf(local.body, theirs);
  if (words == local.body) return theirs;
  await _fetchFilesOf(ctx, payload);
  await ctx.notes.apply(local.copyWith(body: words, updatedAt: ctx._clock()));
  outcome.changed += 1;
  return theirs;
}

/// Writes one note (or its deletion), merging and trying once more if another device got there first (`send`).
Future<void> _send(SyncContext ctx, String id, Note? note, Outcome outcome, {bool retry = true}) async {
  final known = ctx.state.notes[id];
  try {
    if (note != null) {
      // The note whole, as its file has it: the list's has no phrases and no formatted version.
      final full = await ctx.notes.get(id) ?? note;
      final payload = await _sendFilesOf(ctx, full);
      final blob = await ctx.crypto.seal(ctx.key, payload.toJson(), 'note:$id');
      final answer = await ctx.api.call('PUT', 'notes/${Uri.encodeComponent(id)}', token: ctx.token, body: {'base': known?.rev ?? 0, 'blob': blob});
      // The words from before a deletion this send answers stay known until an edit of this device's goes after it.
      ctx.state.notes[id] = NoteMark(rev: _revOf(answer), mark: mark(note), phrases: phrasesMark(full), before: known != null && known.mark.isEmpty ? known.before : null, beforeRev: known != null && known.mark.isEmpty ? known.beforeRev : null);
      // Its title's tick (lib/sync/sync_marks.dart).
      noteSyncMarks.sent(id);
    } else {
      await ctx.api.call('DELETE', 'notes/${Uri.encodeComponent(id)}', token: ctx.token, body: {'base': known?.rev ?? 0});
      ctx.state.notes.remove(id);
      // Taken from the account as it became a team's: the words both last acknowledged, and their revision, for the
      // team's row and for this device's own channel.
      final agreed = agreedOf(known);
      if (ctx._team(id) && agreed != null) ctx.state.teams.putIfAbsent(id, () => TeamLeft(rev: agreed.rev, words: agreed.words, at: ctx._clock()));
    }
  } on ApiError catch (failure) {
    final winner = failure.status == 409 ? FeedItem.fromJson(failure.body) : null;
    if (winner == null) rethrow;
    // The account's row of a note that is a team's here now, taken away and found changed by another of the
    // person's devices since: those words are merged into the team's note, never written over it, and the row goes
    // from where the other device left it.
    if (note == null && ctx._team(id)) {
      final theirs = await _mergeIntoTeams(ctx, winner, known, outcome);
      if (winner.deleted) {
        ctx.state.notes.remove(id);
      } else {
        // Asked again from its revision; one more refusal is left for the next pass, the mark saying the row is owed.
        ctx.state.notes[id] = NoteMark(rev: winner.rev, mark: '');
        // The note's words here are merged with the account's at that revision now: what the team's row left the
        // account at.
        ctx.state.teams[id] = TeamLeft(rev: winner.rev, words: theirs, at: ctx._clock());
        if (retry) await _send(ctx, id, null, outcome, retry: false);
      }
      ctx.save(ctx.state);
      return;
    }
    final local = note != null ? await _listed(ctx, id) : null;
    await _merge(ctx, winner, local, outcome);
    if (!retry) return;
    final now = await _listed(ctx, id);
    final after = ctx.state.notes[id];
    final stillMine = now != null ? after == null || after.mark != mark(now) : after != null && !winner.deleted;
    if (stillMine) await _send(ctx, id, now, outcome, retry: false);
  }
  ctx.save(ctx.state);
}

/// One note's send, or its deletion, with its failure counted rather than ending the pass; a lapsed session still
/// does (`sendCounted`).
Future<void> _sendCounted(SyncContext ctx, String id, Note? note, Outcome outcome) async {
  try {
    await _send(ctx, id, note, outcome);
  } catch (failure) {
    if (failure is ApiError && failure.status == 401) rethrow;
    outcome.unsent += 1;
    outcome.reason ??= failureText(failure);
    // Its title red, with the reason, until it goes (lib/sync/sync_marks.dart).
    if (note != null) noteSyncMarks.failed(id, failureText(failure));
  }
}

/// Whether a recording this device chose to keep may go now: a meeting's, once the setting says so
/// (`recordingOwed`).
bool _recordingOwed(SyncContext ctx, Note note) {
  final id = fileId(FileKind.recording, note.id);
  final ms = note.recordingMs ?? 0;
  if (id == null || ms == 0 || !(ctx.state.files[id]?.stayed ?? false)) return false;
  return !recordingStaysHere(note.id, ms, ctx._meetings, syncMeetingRecordings: ctx._syncMeetings);
}

/// Whether the note's phrases changed here since it went: a meeting's write-up or a better pass rewrites them after
/// the words were sent, and nothing in its [mark] moves (GHST-112; Matt, 2026-10-24: "tapes that have been
/// transcribed on another device and summarized it should show the transcript still across all devices").
Future<bool> _phrasesOwed(SyncContext ctx, Note note, NoteMark known) async {
  if (!phrasesMayMove(note, (ctx.now ?? () => DateTime.now().millisecondsSinceEpoch)())) return false;
  final whole = await ctx.notes.get(note.id);
  final phrases = whole == null ? null : phrasesMark(whole);
  return phrases != null && phrases != known.phrases;
}

Future<void> _push(SyncContext ctx, Outcome outcome) async {
  final here = await ctx.notes.list();
  final present = <String>{};
  // What goes, found before any of it is sent, so the bar knows how much there is: each note sent or deleted is one
  // step of it.
  final sends = <(String, Note?)>[];
  for (final note in here) {
    present.add(note.id);
    final known = ctx.state.notes[note.id];
    // Filed in an organization's workspace, the note is the team's (docs/SHARED.md, S1): the organization channel
    // carries it from here on, and the account's own row goes, so the account's other devices take it from the team.
    if (ctx._team(note.id)) {
      if (known != null) sends.add((note.id, null));
      continue;
    }
    // The account's own again: the revision it once left for a team is no longer what its words are at.
    ctx.state.teams.remove(note.id);
    if (known != null && known.mark == mark(note) && !_recordingOwed(ctx, note) && !await _phrasesOwed(ctx, note, known)) continue;
    // Live with another device: sent once the session ends, when both hold the same words (docs/LIVE.md).
    if (ctx._live(note.id)) continue;
    // A note opened and left empty is not a note yet: it is sent once it has words.
    if (known == null && _blank(note)) continue;
    sends.add((note.id, note));
  }
  for (final id in ctx.state.notes.keys.toList()) {
    if (!present.contains(id)) sends.add((id, null));
  }
  ctx.progress?.found(sends.length);
  for (final (id, note) in sends) {
    await _sendCounted(ctx, id, note, outcome);
    ctx.progress?.did();
  }
  ctx.state.teams.removeWhere((id, left) => !present.contains(id) || ctx._clock() - left.at > teamLeftKeptMs);
  // Versions kept with no change to a note's words (one named by hand, or merged with another device's here): the
  // note goes again with its file, so the other devices hear of the file by the note's new revision, as they would
  // of an edit, and fetch it.
  final notes = {for (final note in here) note.id: note};
  for (final id in ctx.files.owed()) {
    final note = notes[id];
    if (note == null || ctx._live(id) || ctx._team(id)) continue;
    await _oneStep(ctx, () => _sendCounted(ctx, id, note, outcome));
  }
  // Lately out of a team, and its row due again ([LeftTeams.owed]): put again as it is, for an old build that removed
  // its copy to take it back.
  final left = ctx.leftTeams;
  if (left != null) {
    for (final note in here) {
      if (ctx._team(note.id) || ctx._live(note.id) || ctx.state.notes[note.id] == null || !left.owed(note.id)) continue;
      await _oneStep(ctx, () => _sendCounted(ctx, note.id, note, outcome));
      left.sent(note.id);
    }
  }
  ctx.save(ctx.state);
}

/// One whole sync of the notes: what changed elsewhere first, then what changed here, then their pictures
/// (`syncNotes`).
Future<Outcome> syncNotes(SyncContext ctx) async {
  final outcome = Outcome();
  await _pull(ctx, outcome);
  await _push(ctx, outcome);
  await settlePictures(ctx);
  return outcome;
}
