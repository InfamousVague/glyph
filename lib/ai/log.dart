/// What the AI did to each note: the run log. A port of `src/app/ai/log.ts`.
///
/// Matt chose a log in the strip over a chat thread: each run, what was asked, which model, how long, what came of
/// it, and Undo for a run that changed the note. Kept on the device under one key, per note, the newest first and at
/// most a handful each (a note is asked about a few times a day, not a few hundred), beside the home page's gists in
/// `glyph-ai-results`. A reset clears the key with every other `glyph-` one.
///
/// A run that changed the note keeps the note as it was before and after, so Undo can put the words back exactly,
/// and only while the note still reads as the run left it, which the screen checks before it does.
///
/// What differs: a record is a [RunRecord] with the web's JSON as its [RunRecord.toJson]; one that does not read as
/// a record (another build's, a half-written store's) is left out of the log rather than handed on as it is. The
/// hook `useRunLog` answers a [ValueListenable] of the note's log, and the count of writes it follows is
/// [runLogWritten].
library;

import 'package:flutter/foundation.dart';

import '../core/stored.dart';
import 'kinds.dart';
import 'support/note_sheet.dart';
import 'support/watched.dart';

/// How a run ended (`RunOutcome`); [name] is the word kept.
enum RunOutcome {
  done,
  stopped,
  failed;

  /// The outcome with this word, or null for one this build does not know.
  static RunOutcome? of(Object? word) {
    for (final outcome in values) {
      if (outcome.name == word) return outcome;
    }
    return null;
  }
}

const Object _keep = Object();

/// One run, as the log keeps it (`RunRecord`).
@immutable
class RunRecord {
  const RunRecord({
    required this.id,
    required this.noteId,
    required this.kind,
    required this.instruction,
    required this.model,
    required this.at,
    required this.ms,
    required this.outputTokens,
    required this.outcome,
    required this.message,
    required this.truncated,
    this.filled,
    this.before,
    this.after,
  });

  /// A record as it was kept, or null for something that is not one.
  static RunRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final noteId = raw['noteId'];
    final kind = RunKind.of(raw['kind']);
    final outcome = RunOutcome.of(raw['outcome']);
    if (id is! String || noteId is! String || kind == null || outcome == null) return null;
    return RunRecord(
      id: id,
      noteId: noteId,
      kind: kind,
      instruction: raw['instruction'] is String ? raw['instruction'] as String : null,
      model: raw['model'] is String ? raw['model'] as String : '',
      at: (raw['at'] is num ? raw['at'] as num : 0).toInt(),
      ms: (raw['ms'] is num ? raw['ms'] as num : 0).toInt(),
      outputTokens: (raw['outputTokens'] is num ? raw['outputTokens'] as num : 0).toInt(),
      outcome: outcome,
      message: raw['message'] is String ? raw['message'] as String : null,
      truncated: raw['truncated'] == true,
      filled: raw['filled'] is num ? (raw['filled'] as num).toInt() : null,
      before: raw['before'] is String ? raw['before'] as String : null,
      after: raw['after'] is String ? raw['after'] as String : null,
    );
  }

  final String id;
  final String noteId;
  final RunKind kind;

  /// The words the person gave, for a kind that takes some; null for the named kinds.
  final String? instruction;
  final String model;

  /// When it started, in ms since the epoch.
  final int at;

  /// How long it took.
  final int ms;
  final int outputTokens;
  final RunOutcome outcome;

  /// Why it failed, for a run that did.
  final String? message;
  final bool truncated;

  /// How many blanks a press of Fill filled, for its one line in the log (docs/DESIGN.md §145, 7.3).
  final int? filled;

  /// The note before the run's words landed, for a run that changed it; null for one that only wrote on the side.
  final String? before;

  /// The note after the run's words landed.
  final String? after;

  /// This record with some of it changed. [filled], [before] and [after] may be given as null to take them off.
  RunRecord copyWith({RunOutcome? outcome, int? ms, int? outputTokens, Object? message = _keep, bool? truncated, Object? filled = _keep, Object? before = _keep, Object? after = _keep}) => RunRecord(
        id: id,
        noteId: noteId,
        kind: kind,
        instruction: instruction,
        model: model,
        at: at,
        ms: ms ?? this.ms,
        outputTokens: outputTokens ?? this.outputTokens,
        outcome: outcome ?? this.outcome,
        message: identical(message, _keep) ? this.message : message as String?,
        truncated: truncated ?? this.truncated,
        filled: identical(filled, _keep) ? this.filled : filled as int?,
        before: identical(before, _keep) ? this.before : before as String?,
        after: identical(after, _keep) ? this.after : after as String?,
      );

  /// As the page kept it, key for key; the three the web's interface marks optional are left out when null.
  Map<String, Object?> toJson() => {
        'id': id,
        'noteId': noteId,
        'kind': kind.id,
        'instruction': instruction,
        'model': model,
        'at': at,
        'ms': ms,
        'outputTokens': outputTokens,
        'outcome': outcome.name,
        'message': message,
        'truncated': truncated,
        'filled': ?filled,
        'before': ?before,
        'after': ?after,
      };

  @override
  bool operator ==(Object other) =>
      other is RunRecord &&
      other.id == id &&
      other.noteId == noteId &&
      other.kind == kind &&
      other.instruction == instruction &&
      other.model == model &&
      other.at == at &&
      other.ms == ms &&
      other.outputTokens == outputTokens &&
      other.outcome == outcome &&
      other.message == message &&
      other.truncated == truncated &&
      other.filled == filled &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(id, noteId, kind, instruction, model, at, ms, outputTokens, outcome, message, truncated, filled, before, after);

  @override
  String toString() => 'RunRecord(${toJson()})';
}

const String _key = 'glyph-ai-log';

/// The most runs kept per note.
const int _most = 8;

final ValueNotifier<int> _written = ValueNotifier<int>(0);

/// Counts the writes, so a screen showing a note's log reads it again after each (`written`).
ValueListenable<int> get runLogWritten => _written;

List<RunRecord>? _recordsOf(Object? raw) {
  if (raw is! List) return null;
  return List<RunRecord>.unmodifiable([
    for (final one in raw) ?RunRecord.fromJson(one),
  ]);
}

/// Per note, its runs newest first. Read shared (core/stored.dart `readShared`), so a read parses only when the text
/// has changed, which is also what keeps a note's log the same list between writes.
final NoteSheet<List<RunRecord>> _sheet = NoteSheet<List<RunRecord>>(
  () => stored.readShared<Sheet<List<RunRecord>>>(_key, const {}, (raw) => sheetOf<List<RunRecord>>(raw, _recordsOf)),
  (value) {
    stored.write(_key, value);
    _written.value += 1;
  },
);

/// A run's record kept, newest first; the same id again replaces its earlier record (`recordRun`).
void recordRun(RunRecord record) {
  _sheet.update(record.noteId, (mine) => [record, ...?mine?.where((r) => r.id != record.id)].take(_most).toList());
}

/// One run's record changed, if the note's log has it; otherwise nothing is written.
void _changeRecord(String noteId, String runId, RunRecord Function(RunRecord record) fn) {
  _sheet.update(noteId, (mine) => mine != null && mine.any((r) => r.id == runId) ? [for (final r in mine) r.id == runId ? fn(r) : r] : mine);
}

/// The run changed the note: the words before and after go on its record, for Undo (`recordChange`).
void recordChange(String noteId, String runId, String before, String after) {
  _changeRecord(noteId, runId, (r) => r.copyWith(before: before, after: after));
}

/// A run's change was undone: its record no longer offers it (`recordUndone`).
void recordUndone(String noteId, String runId) {
  _changeRecord(noteId, runId, (r) => r.copyWith(before: null, after: null));
}

/// No runs, the one list.
const List<RunRecord> _none = [];

/// A note's runs, newest first (`runsOf`). The list is shared between readers and is not to be changed.
List<RunRecord> runsOf(String noteId) => _sheet.read()[noteId] ?? _none;

/// A note is gone: so is its log (`forgetRuns`).
void forgetRuns(String noteId) => _sheet.forget(noteId);

/// A note's log as the screen sees it, following every record written (`useRunLog`).
ValueListenable<List<RunRecord>> useRunLog(String noteId) => Watched<List<RunRecord>>(() => runsOf(noteId), (listener) {
      _written.addListener(listener);
      return () => _written.removeListener(listener);
    });
