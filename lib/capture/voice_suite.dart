/// The voice test suite (voice-tests/suite.json): a recording per feature, replayed through what the recorder runs
/// and checked against the notes it should leave.
///
/// Two ways in. From the script, each line is one committed phrase with the silence written after it, which checks
/// the rules. From the audio, Whisper on this machine hears the recording exactly as the phone would, which checks
/// the rules against real speech.
///
/// Test infrastructure beside the code it tests: only `test/capture/voice_suite_test.dart` imports it, so it is in
/// no build the app ships. It plays each phrase through the live reader (`live_route.dart`), on the clock the phone
/// would commit it at, and writes what it leaves as the recorder's Done does (`live_take.dart`: `placeTake` into
/// each note, the take's own note rendered from its words). A test can be held back with the reason it is skipped
/// (`skip`); none is now.
///
/// A port of `src/app/capture/voiceSuite.ts`.
///
/// What differs: the suite's types read themselves from the JSON they are stored as (`fromJson`), where the web
/// casts the imported file. A script line is a record `(text, pause)` where the web has a two-element array. Times
/// are whole milliseconds here ([Segment]'s are `int`), where the web's are whatever the arithmetic gives; every
/// pause the suite writes is a tenth of a second, so the two agree.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../core/item_syntax.dart';
import '../core/note_text.dart';
import 'live_route.dart';
import 'live_take.dart';
import 'markdown.dart';
import 'quiet.dart';
import 'spoken/extras.dart';
import 'spoken/numbers.dart';

class SuiteTest {
  const SuiteTest({
    required this.id,
    required this.file,
    required this.group,
    required this.tests,
    required this.setup,
    required this.prefs,
    required this.lines,
    required this.expect,
    this.choose,
    this.skip,
    this.rerecord,
  });

  factory SuiteTest.fromJson(Map<String, Object?> json) => SuiteTest(
    id: json['id']! as String,
    file: json['file']! as String,
    group: json['group']! as String,
    tests: json['tests']! as String,
    setup: json['setup']! as String,
    prefs: (quietStop: (json['prefs'] as Map<String, Object?>?)?['quietStop'] as bool?),
    lines: [
      for (final line in json['lines']! as List<Object?>) ((line! as List<Object?>)[0]! as String, (line as List<Object?>)[1]! as num),
    ],
    expect: Expectation.fromJson(json['expect']! as Map<String, Object?>),
    choose: json['choose'] as String?,
    skip: json['skip'] as String?,
    rerecord: json['rerecord'] as String?,
  );

  final String id;
  final String file;
  final String group;
  final String tests;

  /// "blank", "fixtures", or "continue:<title>".
  final String setup;

  /// "Stop when I go quiet": the one preference a script can switch on.
  final ({bool? quietStop}) prefs;

  /// Each line, and the seconds of silence after it.
  final List<(String, num)> lines;
  final Expectation expect;

  /// A card asking which note, answered as it comes up: a title to tap, "new" for a new note by the name, or "keep".
  final String? choose;

  /// Why the test is not run: what the recorder no longer does, and since when.
  final String? skip;

  /// Why its recording no longer says its script, so the audio pass leaves it until it is made again.
  final String? rerecord;

  SuiteTest _expecting(Expectation expect) =>
      SuiteTest(id: id, file: file, group: group, tests: tests, setup: setup, prefs: prefs, lines: lines, expect: expect, choose: choose, skip: skip, rerecord: rerecord);
}

Map<String, String>? _strings(Object? json) => json == null ? null : {for (final entry in (json as Map<String, Object?>).entries) entry.key: entry.value! as String};

Map<String, List<String>>? _lists(Object? json) =>
    json == null ? null : {for (final entry in (json as Map<String, Object?>).entries) entry.key: (entry.value! as List<Object?>).cast<String>()};

class Expectation {
  const Expectation({this.note, this.match, this.contains, this.lacks, this.notes, this.notesContain, this.notesMatch, this.notesLack, this.newNote, this.stopsWithinMs});

  factory Expectation.fromJson(Map<String, Object?> json) => Expectation(
    note: json['note'] as String?,
    match: json['match'] as String?,
    contains: (json['contains'] as List<Object?>?)?.cast<String>(),
    lacks: (json['lacks'] as List<Object?>?)?.cast<String>(),
    notes: _strings(json['notes']),
    notesContain: _lists(json['notesContain']),
    notesMatch: _lists(json['notesMatch']),
    notesLack: _lists(json['notesLack']),
    newNote: json['newNote'] as bool?,
    stopsWithinMs: json['stopsWithinMs'] as num?,
  );

  /// The recording's own note, exactly ('' when nothing is saved for it).
  final String? note;

  /// A regular expression the recording's own note matches.
  final String? match;
  final List<String>? contains;
  final List<String>? lacks;

  /// Other notes, exactly.
  final Map<String, String>? notes;
  final Map<String, List<String>>? notesContain;
  final Map<String, List<String>>? notesMatch;
  final Map<String, List<String>>? notesLack;
  final bool? newNote;

  /// The recording stops by itself this soon after the last words.
  final num? stopsWithinMs;
}

class Suite {
  const Suite({required this.fixtures, required this.tests});

  factory Suite.fromJson(Map<String, Object?> json) => Suite(
    fixtures: _strings(json['fixtures'])!,
    tests: [for (final test in json['tests']! as List<Object?>) SuiteTest.fromJson(test! as Map<String, Object?>)],
  );

  final Map<String, String> fixtures;
  final List<SuiteTest> tests;
}

class Heard {
  const Heard({required this.segments, required this.audioMs});

  factory Heard.fromJson(Map<String, Object?> json) => Heard(
    segments: [
      for (final segment in (json['segments']! as List<Object?>).cast<Map<String, Object?>>())
        Segment(text: segment['text']! as String, startMs: (segment['startMs']! as num).round(), endMs: (segment['endMs']! as num).round()),
    ],
    audioMs: (json['audioMs']! as num).round(),
  );

  final List<Segment> segments;

  /// The recording's length.
  final int audioMs;
}

final RegExp _spaces = RegExp(r'\s+');

/// A line's length, spoken at an ordinary pace: about a third of a second a word, and never under half a second.
int _spokenMs(String line) => math.max(500, line.split(_spaces).where((word) => word.isNotEmpty).length * 330);

/// The script as the phone's streamer would commit it: a phrase per line, timed the way stream.rs times them. A
/// phrase keeps 300 ms of the quiet after it and the next one starts where it ended, unless two seconds of quiet
/// built up first, which are dropped but for 300 ms: so a pause shows as no gap, or 1.7 s for every two seconds past
/// 300 ms.
Heard scriptHeard(List<(String, num)> lines) {
  final segments = <Segment>[];
  num start = 0;
  num speech = 300;
  for (final (text, pause) in lines) {
    final end = speech + _spokenMs(text) + math.min(300, pause * 1000);
    segments.add(Segment(text: text, startMs: start.round(), endMs: end.round()));
    final quiet = math.max(0, pause * 1000 - 300);
    final drops = (quiet / 2000).floor();
    start = end + drops * 1700;
    speech = end + quiet;
  }
  return Heard(segments: segments, audioMs: speech.round());
}

class Outcome {
  const Outcome({required this.note, required this.notes, required this.newNote, required this.stoppedAtMs, required this.lastWordsMs, required this.log});

  /// The recording's own note when it made one, else null.
  final String? note;

  /// Every note by title, after the recording.
  final Map<String, String> notes;
  final bool newNote;
  final int? stoppedAtMs;
  final int lastWordsMs;
  final List<String> log;

  /// The outcome as the web's object, for holding it against what the web's own run left.
  Map<String, Object?> toJson() => {'note': note, 'notes': notes, 'newNote': newNote, 'stoppedAtMs': stoppedAtMs, 'lastWordsMs': lastWordsMs, 'log': log};
}

/// How long after the audio of a phrase ends the phone commits it.
const int _commitLagMs = 400;
const int _tickMs = 250;
const int _quietStopMs = 4000;

/// A test's `choose`, as the card's answer.
CardChoice _answerFor(String choose, LiveCard<MemoryNote> card) {
  if (choose == 'keep') return const CardChoiceKeep();
  if (choose == 'new') return const CardChoiceNew();
  for (final candidate in card.candidates) {
    if (candidate.title.toLowerCase() == choose.toLowerCase()) return CardChoiceNote(id: candidate.id);
  }
  return const CardChoiceKeep();
}

/// One recording, played through the live reader with the suite's notes, and what came of it.
Outcome runTest(SuiteTest test, Map<String, String> fixtures, Heard heard) {
  final withFixtures = test.setup != 'blank';
  final titles = withFixtures ? fixtures.keys.toList() : <String>[];
  final notes = [for (var n = 0; n < titles.length; n += 1) MemoryNote(id: 'fixture-$n', body: fixtures[titles[n]]!)];
  // The recorder gives spoken note links the titles it knows, as the capture screen does.
  setLinkTitles(titles);
  final continuing = test.setup.startsWith('continue:') ? test.setup.substring('continue:'.length) : null;
  final at = continuing != null ? titles.indexOf(continuing) : -1;
  final own = at >= 0 ? notes[at] : null;
  final take = LiveTake(notes, LiveTakeOptions(own: own));

  final quiet = test.prefs.quietStop == true ? QuietWatch(_quietStopMs) : null;
  final commits = [for (final segment in heard.segments) (at: segment.endMs + _commitLagMs, segment: segment)];
  final end = heard.audioMs + _commitLagMs;
  int? stoppedAtMs;
  var next = 0;
  for (var now = 0; now <= end; now += _tickMs) {
    while (next < commits.length && commits[next].at <= now) {
      final segment = commits[next++].segment;
      quiet?.words(now);
      take.phrase(segment, now);
      final card = take.card;
      final choose = test.choose;
      if (card != null && choose != null && choose.isNotEmpty) take.answer(_answerFor(choose, card));
    }
    final commanding = take.live.holding;
    take.tick(now);
    if (!commanding && quiet != null && quiet.due(now)) {
      stoppedAtMs = now;
      break;
    }
  }
  take.close(stoppedAtMs ?? heard.audioMs);

  final bodies = take.result().bodies;
  // The take's own note: a new one, titled by its words, or one a card made by name ("New note “Moon base”").
  final ownNote = take.aim == null ? take.page() : '';
  final byTitle = <String, String>{};
  for (final entry in bodies.entries) {
    final index = notes.indexWhere((note) => note.id == entry.key);
    byTitle[index >= 0 && index < titles.length ? titles[index] : noteTitle(entry.value)] = entry.value;
  }
  final lastWordsMs = heard.segments.isNotEmpty ? heard.segments.last.endMs : 0;
  return Outcome(note: ownNote.trim().isNotEmpty ? ownNote : null, notes: byTitle, newNote: take.parts.isNotEmpty, stoppedAtMs: stoppedAtMs, lastWordsMs: lastWordsMs, log: take.log);
}

/// A run of number words, "and" allowed between them, as Whisper may spell a number out.
final RegExp _numberRun = RegExp('\\b(?:(?:$numberWord)(?:[\\s-]+(?:and[\\s-]+)?(?=\\w)|\\b))+', caseSensitive: false);
final RegExp _thousands = RegExp(r'(\d),(?=\d{3}\b)');

/// A number as JavaScript prints it: a whole one without a decimal point.
String _printed(num value) => value == value.truncate() ? '${value.truncate()}' : '$value';

/// Text as it is compared for recorded audio: a number said is a number however Whisper wrote it ("four thousand",
/// "4,000", "4000"). The rules decide the marks; the spelling of a number is the recogniser's.
String heardForm(String text) => text
    .replaceAllMapped(_numberRun, (found) {
      final run = found.group(0)!;
      final trimmed = run.trim();
      final value = spokenNumber(trimmed);
      return value == null ? run : '${_printed(value)}${run.endsWith(' ') ? ' ' : ''}';
    })
    .replaceAllMapped(_thousands, (found) => found.group(1)!);

/// A line's block mark, as the recorder writes it: a heading, a list item with its box or choice
/// (core/item_syntax.dart), a numbered step, a hidden line, a quote or callout, a sum, a rule.
final RegExp _blockLead = RegExp('^\\s*(?:#{1,6} |$bulletPattern (?:$boxPattern |$choicePattern )?|$numberPattern |>\\| ?|> (?:\\[![A-Z]+\\])?|= |---\$)?');
final RegExp _inlineMarks = RegExp(r'\*\*|~~|==|%%|\?\?|@@|\^\^|\+\+|\|\||`|\[\[|\]\]|\[\d+\/\d+\]|#[a-z][\w/-]*');
final RegExp _box = RegExp('[xX]');

/// A line's shape: its block mark, and the inline marks in it, in order.
String _shapeOf(String line) {
  final lead = _blockLead.firstMatch(line)?.group(0) ?? '';
  final marks = _inlineMarks.allMatches(line).map((found) => found.group(0)!);
  return '${lead.replaceFirst(_box, 'x')}${marks.join(' ')}';
}

final RegExp _notLetters = RegExp('[^a-z0-9 ]+');

String _lettersOf(String line) => line.toLowerCase().replaceAll(_notLetters, '').replaceAll(_spaces, ' ').trim();

/// How alike two lines' words are, 0 to 1, by edit distance over their letters.
double _wordLikeness(String a, String b) {
  final x = _lettersOf(a);
  final y = _lettersOf(b);
  if (x.isEmpty && y.isEmpty) return 1;
  final row = List<int>.generate(y.length + 1, (j) => j);
  for (var i = 1; i <= x.length; i += 1) {
    var diagonal = row[0];
    row[0] = i;
    for (var j = 1; j <= y.length; j += 1) {
      final above = row[j];
      row[j] = math.min(math.min(row[j] + 1, row[j - 1] + 1), diagonal + (x[i - 1] == y[j - 1] ? 0 : 1));
      diagonal = above;
    }
  }
  return 1 - row[y.length] / math.max(x.length, y.length);
}

/// Whether a note heard from audio is the note expected, allowing for Whisper mishearing a word or two: every line
/// has the same marks in the same places, and most of its words. The rules are what is tested; the recogniser's
/// vocabulary is not.
bool sameShape(String expected, String actual) {
  final want = expected.split('\n');
  final got = actual.split('\n');
  if (want.length != got.length) return false;
  for (var i = 0; i < want.length; i += 1) {
    if (_shapeOf(want[i]) != _shapeOf(got[i]) || _wordLikeness(want[i], got[i]) < 0.6) return false;
  }
  return true;
}

String _show(String text) => jsonEncode(text);

Map<String, List<String>>? _heardLists(Map<String, List<String>>? lists) => lists == null ? null : {for (final entry in lists.entries) entry.key: entry.value.map(heardForm).toList()};

/// What an outcome gets wrong against its test's expectation, as sentences; empty when it passes.
List<String> problems(SuiteTest test, Outcome outcome, {bool heard = false}) {
  if (heard) {
    final said = test.expect;
    final expectNote = said.note == null ? null : heardForm(said.note!);
    final expectNotes = said.notes == null ? null : {for (final entry in said.notes!.entries) entry.key: heardForm(entry.value)};
    final note = outcome.note == null ? null : heardForm(outcome.note!);
    final notes = {for (final entry in outcome.notes.entries) entry.key: heardForm(entry.value)};
    // Whole notes are compared by shape; a misheard word in one is Whisper's, not the rules'.
    final out = <String>[];
    if (expectNote != null && !(expectNote == '' ? (note ?? '') == '' : sameShape(expectNote, note ?? ''))) {
      out.add('the note is ${_show(note ?? '')}, not the shape of ${_show(expectNote)}');
    }
    for (final entry in (expectNotes ?? const <String, String>{}).entries) {
      if (!sameShape(entry.value, notes[entry.key] ?? '')) out.add('"${entry.key}" is ${_show(notes[entry.key] ?? '(missing)')}, not the shape of ${_show(entry.value)}');
    }
    final rest = test._expecting(
      Expectation(
        match: said.match,
        contains: said.contains?.map(heardForm).toList(),
        lacks: said.lacks?.map(heardForm).toList(),
        notesContain: _heardLists(said.notesContain),
        notesMatch: _heardLists(said.notesMatch),
        notesLack: _heardLists(said.notesLack),
        newNote: said.newNote,
        stopsWithinMs: said.stopsWithinMs,
      ),
    );
    return [...out, ...problems(rest, Outcome(note: note, notes: notes, newNote: outcome.newNote, stoppedAtMs: outcome.stoppedAtMs, lastWordsMs: outcome.lastWordsMs, log: outcome.log))];
  }
  final out = <String>[];
  final expect = test.expect;
  final own = outcome.note ?? '';
  final match = expect.match;
  if (expect.note != null && own != expect.note) out.add('the note is ${_show(own)}, not ${_show(expect.note!)}');
  if (match != null && match.isNotEmpty && !RegExp(match).hasMatch(own)) out.add("the note ${_show(own)} doesn't match /$match/");
  for (final part in expect.contains ?? const <String>[]) {
    if (!own.contains(part)) out.add('the note ${_show(own)} lacks ${_show(part)}');
  }
  for (final part in expect.lacks ?? const <String>[]) {
    if (own.contains(part)) out.add('the note ${_show(own)} has ${_show(part)}');
  }
  for (final entry in (expect.notes ?? const <String, String>{}).entries) {
    if (outcome.notes[entry.key] != entry.value) out.add('"${entry.key}" is ${_show(outcome.notes[entry.key] ?? '(missing)')}, not ${_show(entry.value)}');
  }
  for (final entry in (expect.notesContain ?? const <String, List<String>>{}).entries) {
    for (final part in entry.value) {
      if (!(outcome.notes[entry.key] ?? '').contains(part)) out.add('"${entry.key}" ${_show(outcome.notes[entry.key] ?? '')} lacks ${_show(part)}');
    }
  }
  for (final entry in (expect.notesMatch ?? const <String, List<String>>{}).entries) {
    for (final part in entry.value) {
      if (!RegExp(part).hasMatch(outcome.notes[entry.key] ?? '')) out.add('"${entry.key}" ${_show(outcome.notes[entry.key] ?? '')} doesn\'t match /$part/');
    }
  }
  for (final entry in (expect.notesLack ?? const <String, List<String>>{}).entries) {
    for (final part in entry.value) {
      if ((outcome.notes[entry.key] ?? '').contains(part)) out.add('"${entry.key}" still has ${_show(part)}');
    }
  }
  if (expect.newNote == false && outcome.note != null) out.add('a new note was made: ${_show(own)}');
  final within = expect.stopsWithinMs;
  if (within != null) {
    final stopped = outcome.stoppedAtMs;
    if (stopped == null) {
      out.add('the recording never stopped by itself');
    } else if (stopped - outcome.lastWordsMs > within) {
      out.add('it stopped ${stopped - outcome.lastWordsMs} ms after the words');
    }
  }
  return out;
}
