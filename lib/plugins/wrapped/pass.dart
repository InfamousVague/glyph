/// Wrapped's slow pass through the notes (docs/WRAPPED.md, "The pass"; Matt, 2026-11-05: "go through all the notes in
/// the app in the backround slowly with whatever agent is connected"): a few notes an ask, a pause between asks, held
/// while the app is busy, and every answer kept as it comes, so a pass stopped by the app closing goes on from where it
/// was when the app is open again. A note whose words hash as they did when last read is never sent again.
///
/// Two kinds of ask, each to the AI the person has connected (Cleanup's: lib/plugins/cleanup/ai.dart `connectedAis`,
/// the person's own key and spending limit):
/// - **Each note**, a few at a time ([WrappedPacing.notesPerAsk]), its title, folder, dates and first characters: back
///   come a one-line gist, a theme or two, whether it looks stale and why, and whether it is a gem worth finding again.
/// - **The library**, once at the end, from the gists alone (never a note's words): the themes of the period, notes to
///   file in a folder there is or a new one, near-duplicates to merge, and notes that should link.
///
/// Nothing is changed here: what is found is suggestions, for the review (review.dart) and actions.dart.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../claude/claude_spend.dart' show ClaudeUsage, claudeCost, claudeDollars;
import '../../core/background_jobs.dart' show JobEstimate;
import '../cleanup/ai.dart' show CleanupAi, CleanupAsking;
import '../cleanup/plan.dart' show jsonObjectIn;
import '../cleanup/prompts.dart' show notePeek;
import '../note_decay/ai.dart' show stableHash;
import 'state.dart';

/// How gently a pass goes.
@immutable
class WrappedPacing {
  const WrappedPacing({required this.notesPerAsk, required this.charsPerNote, required this.gap, this.summaryNotes = 400, this.busyCheck = const Duration(seconds: 15)});

  /// Notes in one ask, and how much of each is sent.
  final int notesPerAsk;
  final int charsPerNote;

  /// The pause after each ask.
  final Duration gap;

  /// The most gists the library's ask is sent: the most recently edited.
  final int summaryNotes;

  /// How often a pass held for a busy app looks again.
  final Duration busyCheck;

  /// A cloud model's: six notes an ask, 1,200 characters of each, eight seconds between.
  static const WrappedPacing cloud = WrappedPacing(notesPerAsk: 6, charsPerNote: 1200, gap: Duration(seconds: 8));

  /// The device's model's: two notes, 500 characters, twenty seconds between, so the phone stays cool.
  static const WrappedPacing device = WrappedPacing(notesPerAsk: 2, charsPerNote: 500, gap: Duration(seconds: 20), summaryNotes: 60);

  static WrappedPacing of(CleanupAi ai) => ai.local ? device : cloud;
}

/// One note as the pass reads it: only the person's own, out of the Trash.
@immutable
class WrappedNote {
  const WrappedNote({required this.id, required this.title, required this.body, required this.updatedAt, required this.createdAt, this.folder = '', this.folderId});

  final String id;
  final String title;
  final String body;
  final int updatedAt;
  final int createdAt;

  /// Its folder's path ("Work › Clients"), empty for none, and the folder's id.
  final String folder;
  final String? folderId;

  String get hash => stableHash(body);
}

/// A personal folder, for the library's ask.
typedef WrappedFolder = ({String id, String path});

/// The notes a pass still has to read: those with no read, or whose words changed since.
List<WrappedNote> notesToRead(List<WrappedNote> notes, Map<String, WrappedRead> reads) => [
      for (final note in notes)
        if (reads[note.id]?.hash != note.hash) note,
    ];

/// "12k", "1.2M".
String tokenWords(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens < 1000000) return '${(tokens / 1000).round()}k';
  return '${(tokens / 1000000).toStringAsFixed(1)}M';
}

/// What a pass of [toRead] notes (of [all]) with [ai] should cost and take (the page's estimate, and the question
/// before the first run: lib/activity/activity_cost.dart).
@immutable
class WrappedEstimate {
  const WrappedEstimate({required this.notes, required this.all, required this.asks, required this.input, required this.output, required this.duration, required this.aiName, this.dollars});

  /// Notes to send now, and notes in all.
  final int notes;
  final int all;
  final int asks;

  /// Tokens in and out, about.
  final int input;
  final int output;
  final Duration duration;
  final String aiName;

  /// About what it costs where the price is known (Claude's table), else null.
  final double? dollars;

  int get tokens => input + output;

  /// "~48k tokens · about $0.21", or "~48k tokens on your OpenAI key", or "on this device, nothing sent".
  String get costWords {
    if (aiName == 'On this device') return 'on this device, nothing sent';
    final money = dollars == null ? 'on your $aiName key' : '· about ${claudeDollars(math.max(0.01, dollars!))}';
    return '~${tokenWords(tokens)} tokens $money';
  }

  /// The page's line: "312 notes to read · 53 asks of Claude · ~48k tokens · about $0.21 · ~9 min".
  String get words => [
        '$notes ${notes == 1 ? 'note' : 'notes'} to read',
        '$asks ${asks == 1 ? 'ask' : 'asks'} of $aiName',
        costWords,
        '~${_duration(duration)}',
      ].join(' · ');

  /// The Activity tray's estimate, always asked about the first time: it spends the person's own key.
  JobEstimate job({required bool first}) => JobEstimate(count: notes, one: 'note', many: 'notes', duration: duration, cost: costWords, asksAlways: first);
}

String _duration(Duration d) => d.inMinutes < 1 ? '${math.max(1, d.inSeconds)} s' : (d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} h ${d.inMinutes % 60} min');

/// The estimate for reading [toRead] with [ai] and [pacing], of [all] notes in all.
WrappedEstimate wrappedEstimate(List<WrappedNote> toRead, int all, CleanupAi ai, {WrappedPacing? pacing}) {
  final pace = pacing ?? WrappedPacing.of(ai);
  final asks = (toRead.length / pace.notesPerAsk).ceil();
  var input = 0;
  for (final note in toRead) {
    input += (math.min(note.body.length, pace.charsPerNote) / 4).ceil() + 40;
  }
  input += asks * 380;
  final output = toRead.length * 60;
  // The library's ask: a line of each gist, and its answer.
  final summary = math.min(all, pace.summaryNotes);
  final sumIn = summary * 35 + 500, sumOut = 1500;
  final perAsk = ai.local ? const Duration(seconds: 30) : const Duration(seconds: 6);
  final duration = (perAsk + pace.gap) * asks + perAsk * 2;
  final usage = ClaudeUsage(input: input + sumIn, output: output + sumOut);
  return WrappedEstimate(
    notes: toRead.length,
    all: all,
    asks: asks + 1,
    input: input + sumIn,
    output: output + sumOut,
    duration: duration,
    aiName: ai.name,
    dollars: ai.id == 'claude' && ai.model != null ? claudeCost(ai.model!, usage) : null,
  );
}

// ---- the asks ------------------------------------------------------------------------------------------------------

const String readSystem = '''You read a few of someone's notes to make their "Wrapped", a year-in-review of their notes. For each note you are shown its ref (n1, n2, …), title, folder, when it was written and last edited, and its first words.
For each note answer:
- "gist": one plain line, at most 12 words, of what the note is about. No quotes, no "This note".
- "themes": one or two short themes it belongs to, lower case, a word or two each ("travel", "work hiring").
- "stale": true only when it clearly looks abandoned or out of date: an empty draft, plans for a date long past with nothing done, a list nobody came back to. With "why": a few words.
- "gem": true only for a note worth finding again: an idea, a recipe, advice, a memory. Most notes are not.
Refer to notes only by their refs. Answer with one JSON object and nothing else:
{"notes": [{"ref": "n1", "gist": "…", "themes": ["…"], "stale": false, "why": "", "gem": false}]}''';

String _day(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// What one ask about [batch] is sent.
String readPrompt(List<WrappedNote> batch, WrappedPacing pacing) => [
      'Notes (${batch.length}):',
      for (var i = 0; i < batch.length; i += 1) ...[
        '',
        '[n${i + 1}] ${batch[i].title.trim().isEmpty ? '(no title)' : '“${batch[i].title.trim()}”'} · ${batch[i].folder.isEmpty ? 'no folder' : batch[i].folder} · written ${_day(batch[i].createdAt)} · edited ${_day(batch[i].updatedAt)}',
        notePeek(batch[i].body, pacing.charsPerNote),
      ],
    ].join('\n');

String _clean(Object? text, int most) {
  if (text is! String) return '';
  final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.length > most ? '${one.substring(0, most - 1)}…' : one;
}

/// The reads [output] gives [batch]'s notes, by id; a note the answer leaves out has none. Never throws.
Map<String, WrappedRead> readAnswer(String output, List<WrappedNote> batch, {required int at}) {
  final answer = jsonObjectIn(output);
  final list = answer?['notes'];
  if (list is! List) return const {};
  final out = <String, WrappedRead>{};
  for (final entry in list) {
    if (entry is! Map) continue;
    final ref = entry['ref'];
    final i = ref is String ? int.tryParse(ref.trim().toLowerCase().replaceFirst('n', '')) : null;
    if (i == null || i < 1 || i > batch.length) continue;
    final note = batch[i - 1];
    final themes = entry['themes'];
    out[note.id] = WrappedRead(
      hash: note.hash,
      gist: _clean(entry['gist'], 120),
      themes: [if (themes is List) for (final t in themes.take(2)) if (_clean(t, 30).isNotEmpty) _clean(t, 30).toLowerCase()],
      stale: entry['stale'] == true,
      staleWhy: entry['stale'] == true ? _clean(entry['why'], 100) : '',
      gem: entry['gem'] == true,
      at: at,
    );
  }
  return out;
}

const String librarySystem = '''You are making someone's "Wrapped", a year-in-review of their notes, from a one-line gist of each. You are shown each note's ref (n1, …), title, folder and gist, and their folders (f1, …).
Answer with:
- "themes": the 3 to 5 themes of their notes, each two or three words, most written about first.
- "moves": up to 10 notes clearly in the wrong folder or in none, and the folder there is that fits ({"note": "n3", "to": "f2", "why": "…"}).
- "folders": up to 3 new folders for notes that belong together and have no folder that fits ({"name": "Short name", "parent": "f1" or null, "notes": ["n4", "n5"], "why": "…"}).
- "merges": up to 5 groups of notes that are the same note twice, or nearly ({"keep": "n1", "others": ["n2"], "why": "…"}). Not notes merely on one subject.
- "links": up to 10 pairs of notes that should link to each other and do not ({"from": "n1", "to": "n2", "why": "…"}).
- "gems": up to 3 refs of notes worth finding again that they may have forgotten.
Suggest little and only what clearly helps; the person reviews every suggestion. Refer to notes and folders only by their refs; never invent one. Leave out any list you have nothing for. Answer with one JSON object and nothing else.''';

/// What the library's ask is sent: the folders, then a line for each of [notes] with its gist.
String libraryPrompt(List<WrappedNote> notes, Map<String, WrappedRead> reads, List<WrappedFolder> folders) => [
      'Folders:',
      if (folders.isEmpty) '(none)',
      for (var i = 0; i < folders.length; i += 1) '- f${i + 1}: ${folders[i].path}',
      '',
      'Notes (${notes.length}):',
      for (var i = 0; i < notes.length; i += 1)
        '[n${i + 1}] ${notes[i].title.trim().isEmpty ? '(no title)' : '“${notes[i].title.trim()}”'} · ${notes[i].folder.isEmpty ? 'no folder' : notes[i].folder} · ${reads[notes[i].id]?.gist ?? ''}',
    ].join('\n');

/// What the library's ask came to.
@immutable
class LibraryRead {
  const LibraryRead({this.themes = const [], this.suggestions = const [], this.gems = const []});
  final List<String> themes;
  final List<WrappedSuggestion> suggestions;
  final List<String> gems;
}

/// The library's answer read, every ref checked against [notes] and [folders]. Never throws.
LibraryRead readLibrary(String output, List<WrappedNote> notes, List<WrappedFolder> folders) {
  final answer = jsonObjectIn(output);
  if (answer == null) return const LibraryRead();
  WrappedNote? note(Object? ref) {
    final i = ref is String ? int.tryParse(ref.trim().toLowerCase().replaceFirst('n', '')) : null;
    return i == null || i < 1 || i > notes.length ? null : notes[i - 1];
  }

  WrappedFolder? folder(Object? ref) {
    final i = ref is String ? int.tryParse(ref.trim().toLowerCase().replaceFirst('f', '')) : null;
    return i == null || i < 1 || i > folders.length ? null : folders[i - 1];
  }

  List<Map> entries(String key, int most) => [
        if (answer[key] case final List list)
          for (final e in list.take(most)) if (e is Map) e,
      ];
  final themes = answer['themes'];
  final out = <WrappedSuggestion>[];
  final used = <String>{};
  for (final e in entries('moves', 10)) {
    final n = note(e['note']), to = folder(e['to']);
    if (n == null || to == null || n.folderId == to.id || !used.add('move:${n.id}')) continue;
    out.add(WrappedSuggestion(kind: SuggestionKind.move, notes: [n.id], folderId: to.id, why: _clean(e['why'], 140)));
  }
  for (final e in entries('folders', 3)) {
    final name = _clean(e['name'], 40);
    final ids = [
      if (e['notes'] case final List refs)
        for (final r in refs)
          if (note(r) case final n? when used.add('move:${n.id}')) n.id,
    ];
    if (name.isEmpty || name.contains('/') || name.startsWith('.') || ids.isEmpty) continue;
    final parent = e['parent'] == null ? null : folder(e['parent']);
    if (e['parent'] != null && parent == null) continue;
    out.add(WrappedSuggestion(kind: SuggestionKind.newFolder, notes: ids, folderName: name, parentId: parent?.id, why: _clean(e['why'], 140)));
  }
  for (final e in entries('merges', 5)) {
    final keep = note(e['keep']);
    final others = <String>{
      if (e['others'] case final List refs)
        for (final r in refs)
          if (note(r) case final n? when n.id != keep?.id) n.id,
    }.toList();
    if (keep == null || others.isEmpty || !used.add('merge:${keep.id}') || others.any((o) => !used.add('merge:$o'))) continue;
    out.add(WrappedSuggestion(kind: SuggestionKind.merge, notes: [keep.id, ...others], why: _clean(e['why'], 140)));
  }
  for (final e in entries('links', 10)) {
    final from = note(e['from']), to = note(e['to']);
    if (from == null || to == null || from.id == to.id || to.title.trim().isEmpty || !used.add('link:${from.id}>${to.id}')) continue;
    if (from.body.toLowerCase().contains('[[${to.title.trim().toLowerCase()}')) continue;
    out.add(WrappedSuggestion(kind: SuggestionKind.link, notes: [from.id, to.id], why: _clean(e['why'], 140)));
  }
  return LibraryRead(
    themes: [if (themes is List) for (final t in themes.take(5)) if (_clean(t, 40).isNotEmpty) _clean(t, 40)],
    suggestions: out,
    gems: [
      if (answer['gems'] case final List refs)
        for (final r in refs.take(3)) ?note(r)?.id,
    ],
  );
}

// ---- the run -------------------------------------------------------------------------------------------------------

/// The way a pass is stopped from outside: the tray's Stop, the page's, the plugin switched off.
class WrappedStop {
  bool _stopped = false;
  CleanupAsking? _asking;
  Completer<void>? _resting;

  bool get stopped => _stopped;

  void stop() {
    _stopped = true;
    _asking?.cancel();
    if (_resting case final rest? when !rest.isCompleted) rest.complete();
  }
}

/// How a pass ended.
enum PassEnd { done, stopped, failed }

/// Reads every note of [toRead] with [ai], [pacing]'s few at a time, handing each batch's reads to [kept] as they
/// come (so a pass cut off keeps what it read), with [pacing]'s gap after each ask and held while [busy] says so.
/// [progress] is told how far it is and whether it is held. [wait] is the clock's, a test's own where given; [now]
/// stamps the reads. An ask that fails is counted in [failures]: three in a row end the pass as failed.
Future<({PassEnd end, int read, String? problem})> readNotes({
  required List<WrappedNote> toRead,
  required CleanupAi ai,
  required void Function(Map<String, WrappedRead> reads) kept,
  WrappedPacing? pacing,
  bool Function()? busy,
  void Function(int done, int total, {bool held})? progress,
  WrappedStop? stop,
  Future<void> Function(Duration wait)? wait,
  DateTime Function()? now,
}) async {
  final pace = pacing ?? WrappedPacing.of(ai);
  final stopped = stop ?? WrappedStop();
  final clock = now ?? DateTime.now;
  Future<void> rest(Duration d) async {
    if (wait != null) return wait(d);
    final resting = stopped._resting = Completer<void>();
    final timer = Timer(d, () {
      if (!resting.isCompleted) resting.complete();
    });
    await resting.future;
    timer.cancel();
  }

  var done = 0, failedInARow = 0;
  String? problem;
  for (var at = 0; at < toRead.length; at += pace.notesPerAsk) {
    // Held while the app is busy: a recording, a sync, another job.
    var held = false;
    while (!stopped.stopped && (busy?.call() ?? false)) {
      if (!held) progress?.call(done, toRead.length, held: true);
      held = true;
      await rest(pace.busyCheck);
    }
    if (stopped.stopped) break;
    if (held) progress?.call(done, toRead.length);
    final batch = toRead.sublist(at, math.min(toRead.length, at + pace.notesPerAsk));
    final asking = stopped._asking = ai.ask(readSystem, readPrompt(batch, pace), maxTokens: 120 * batch.length + 200);
    try {
      final reads = readAnswer(await asking.done, batch, at: clock().millisecondsSinceEpoch);
      // A note the answer left out is read as having nothing to say, so it is not asked again until it changes.
      kept({for (final note in batch) note.id: reads[note.id] ?? WrappedRead(hash: note.hash, at: clock().millisecondsSinceEpoch)});
      failedInARow = 0;
    } catch (failure) {
      if (stopped.stopped) break;
      problem = '$failure'.replaceFirst('Exception: ', '');
      failedInARow += 1;
      if (failedInARow >= 3) return (end: PassEnd.failed, read: done, problem: problem);
    } finally {
      stopped._asking = null;
    }
    done += batch.length;
    progress?.call(done, toRead.length);
    if (done < toRead.length && !stopped.stopped) await rest(pace.gap);
  }
  return (end: stopped.stopped ? PassEnd.stopped : PassEnd.done, read: done, problem: problem);
}

/// The library's ask (see the library doc), over the most recently edited of [notes] that have a gist.
Future<LibraryRead> readLibraryWith(CleanupAi ai, List<WrappedNote> notes, Map<String, WrappedRead> reads, List<WrappedFolder> folders, {WrappedPacing? pacing, WrappedStop? stop}) async {
  final pace = pacing ?? WrappedPacing.of(ai);
  final sent = ([for (final n in notes) if ((reads[n.id]?.gist ?? '').isNotEmpty) n]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt))).take(pace.summaryNotes).toList();
  if (sent.isEmpty) return const LibraryRead();
  final asking = ai.ask(librarySystem, libraryPrompt(sent, reads, folders), maxTokens: 2500);
  if (stop != null) stop._asking = asking;
  try {
    return readLibrary(await asking.done, sent, folders);
  } finally {
    if (stop != null) stop._asking = null;
  }
}
