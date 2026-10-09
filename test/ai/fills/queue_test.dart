// The fills' queue (lib/ai/fills/queue.dart). A port of src/app/ai/fills/queue.test.ts, case for case, and after it a
// few cases of the port's own for what the web's left to the shots.
//
// A model the test answers: `simulateRuns` is the seam, as in runs_test.dart. The web's test wrote a closed note
// through the real store; here the store is the three functions `startFills` is given, over a map. No test touches
// the network: the queue's fetch is a fake from the first line of every case.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/fills/edits.dart';
import 'package:ghost_md/ai/fills/queue.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/log.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/core/blanks.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';

Object? recordedJson(String name) => jsonDecode(File('test/ai/fixtures/recorded/$name.json').readAsStringSync());

final Object? forecast = recordedJson('forecast-lisbon');
final Object? geocode = recordedJson('geocode-lisbon');
final Object? wikiCup = recordedJson('wiki-world-cup');

/// A model the test answers: each generation waits until the test finishes it.
class Fake {
  Fake(this.options);

  final RunOptions options;
  final Completer<Output> _done = Completer<Output>();

  Run get run => Run(
        done: _done.future,
        cancel: () {
          if (!_done.isCompleted) _done.completeError(StateError('cancelled'));
        },
      );

  void finish(String text, {bool truncated = false}) =>
      _done.complete(Output(text: text, promptTokens: 900, outputTokens: 12, ms: 1500, cachedTokens: 800, prefillMs: 100, loadMs: 0, tokensPerSecond: 20, truncated: truncated));

  void fail(String message) => _done.completeError(StateError(message));
}

final List<Fake> fakes = [];
final List<FillToast> toasts = [];
final List<String> opened = [];
void Function() stop = () {};

/// The store, as the queue is given it: notes by id, a write refused unless it names the revision kept.
final Map<String, Note> notes = {};
int syncs = 0;

Note createNote(String id, String body) => notes[id] = Note(id: id, body: body, createdAt: 0, updatedAt: 0);
Future<Note?> getNote(String id) async => notes[id];
Future<Note> updateNote(String id, String body, int expectedRevision) async {
  final now = notes[id];
  if (now == null) throw StateError('The note was deleted.');
  if (now.revision != expectedRevision) throw StateError('The note changed on another device.');
  return notes[id] = now.copyWith(body: body, revision: now.revision + 1);
}

Future<({int status, Object? json})> noNetwork(String url) async => throw StateError('offline');

/// Waits for the queue to reach a state: every step of it is a future.
Future<void> until(bool Function() test) async {
  for (var i = 0; i < 200 && !test(); i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(test(), isTrue);
}

/// An open note's editor, as a string: its ranges tracked by their start, its landings applied.
class Host implements FillHost {
  Host(this.body);

  String body;
  int lands = 0;
  final Map<String, ({int from, int to})> ranges = {};

  @override
  String text() => body;

  @override
  ({int from, int to})? rangeOf(String key) => ranges[key];

  @override
  void track(List<({String key, int from, int to})> targets) {
    for (final t in targets) {
      ranges[t.key] = (from: t.from, to: t.to);
    }
  }

  @override
  String? land(List<TextChange> changes, TextChange? sign) {
    lands += 1;
    body = applyChanges(body, [...changes, ?sign]);
    return body;
  }
}

/// Every blank of [text] as a press's targets.
List<FillTarget> targets(String text) {
  final blanks = blanksIn(text);
  return [
    for (final b in blanks)
      () {
        final order = blanks.where((o) => o.question == b.question && o.from < b.from).length;
        return FillTarget(key: blankKey(b.question, order), question: b.question, order: order);
      }(),
  ];
}

List<String> get said => [for (final t in toasts) t.message];

const String tokyo = '# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}\n\nThe capital of Australia is {?}.';

void main() {
  setUp(() {
    fakes.clear();
    toasts.clear();
    opened.clear();
    notes.clear();
    syncs = 0;
    useStored(MemoryStored());
    preferences.update((p) => p.copyWith(localOnly: false, lookUpBlanks: true));
    simulateRuns((options) {
      final fake = Fake(options);
      fakes.add(fake);
      return fake.run;
    });
    setFillWorld(now: () => DateTime(2026, 9, 28, 12), fetch: noNetwork);
    stop = startFills(toasts.add, opened.add, getNote: getNote, updateNote: updateNote, syncNow: () async => syncs += 1);
  });

  tearDown(() {
    stop();
    simulateRuns(null);
    forgetAllRuns();
    forgetFills();
    preferences.update((p) => p.copyWith(localOnly: false, lookUpBlanks: true));
  });

  group('a press of Fill in an open note', () {
    test('asks every blank in one generation and lands the answers in one change, signed, with one line in the log', () async {
      final note = Host(tokyo);
      openForFills('n1', note);
      pressFill('n1', targets(tokyo), 'qwen3.5-4b');
      expect(fillStatus('n1', blankKey('', 0)), const FillStatus.waiting());
      await until(() => fakes.length == 1);
      expect(fakes[0].options.prompt, contains('{?1 what day / time?}'));
      expect(fakes[0].options.prompt, contains('{?2 }'));
      expect(fakes[0].options.temperature, 0);
      fakes[0].finish('[1] midweek\n[2] Canberra');
      await until(() => note.lands == 1);
      expect(note.body, contains('Flights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)'));
      expect(note.body, contains('The capital of Australia is ??Canberra??(Qwen3.5 4B from memory, 2026-09-28).'));
      expect(note.body, matches(RegExp(r'^---\nauthors: Ghost\n---')));
      await until(() => runsOf('n1').length == 1);
      final record = runsOf('n1').first;
      expect(record.kind, RunKind.fill);
      expect(record.filled, 2);
      expect(record.before, tokyo);
      expect(record.after, note.body);
      expect(fillStatus('n1', blankKey('', 0)), isNull);
      expect(said, contains('The model’s answers have a dotted line. Tap one to see where it came from.'));
      openForFills('n1', null);
    });

    test('says what did not fill, and keeps it after the blank for the session', () async {
      final note = Host(tokyo);
      openForFills('n1', note);
      pressFill('n1', targets(tokyo), 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      fakes[0].finish('[1] midweek\n[2] UNKNOWN');
      await until(() => said.contains('1 filled. 1 not known.'));
      expect(fillOutcome('n1', blankKey('', 0))?.why, FillWhy.unknown);
      openForFills('n1', null);
    });

    test('lets a summary say what the same press wrote beside it, and nothing else the note lacks', () async {
      // Found by the shots: "In one line" was refused for naming Lisbon, which the capital blank had just written.
      const trip = '# Trip prep\n\nThe capital of Portugal is {?}.\n\n- Passport\n\nIn one line: {?summary}';
      final note = Host(trip);
      openForFills('n8', note);
      pressFill('n8', targets(trip), 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      fakes[0].finish('[1] Lisbon\n[2] A trip to Lisbon, with a passport packed.');
      await until(() => note.lands == 1);
      expect(note.body, contains('In one line: ??A trip to Lisbon, with a passport packed.??'));
      openForFills('n8', null);
      final again = Host(trip);
      openForFills('n9', again);
      pressFill('n9', targets(trip), 'qwen3.5-4b');
      await until(() => fakes.length == 2);
      fakes[1].finish('[1] Lisbon\n[2] A trip to Porto, with a passport packed.');
      await until(() => said.contains("1 filled. 1 didn't fit."));
      openForFills('n9', null);
    });

    test('drops an answer whose question changed while it ran, and says so', () async {
      final note = Host(tokyo);
      openForFills('n1', note);
      pressFill('n1', targets(tokyo), 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      note.body = note.body.replaceFirst('{?}', '{?which city}');
      note.ranges.clear();
      fakes[0].finish('[1] midweek\n[2] Canberra');
      await until(() => said.contains('1 answer was not written. Its question had changed.'));
      expect(note.body, contains('??midweek??'));
      expect(note.body, contains('{?which city}'));
      openForFills('n1', null);
    });
  });

  group('the queue', () {
    test('runs a second press after the first, never beside it', () async {
      final note = Host('# A\n\nThe capital of France is {?}.\n\nThe capital of Peru is {?which city}.');
      openForFills('n2', note);
      final [france, peru] = targets(note.body);
      pressFill('n2', [france], 'qwen3.5-4b');
      pressFill('n2', [peru], 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      expect(fillStatus('n2', peru.key), const FillStatus.waiting());
      fakes[0].finish('[1] Paris');
      await until(() => fakes.length == 2);
      fakes[1].finish('[1] Lima');
      await until(() => note.body.contains('??Lima??'));
      expect(runsOf('n2'), hasLength(2));
      openForFills('n2', null);
    });

    test('waits while Format runs on the note, and a Format asked while it fills stops it', () async {
      final note = Host(tokyo);
      openForFills('n3', note);
      final format = startRun(const RunRequest(noteId: 'n3', kind: RunKind.format, model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 10));
      await until(() => fakes.length == 1);
      pressFill('n3', targets(tokyo), 'qwen3.5-4b');
      // Pressed and waiting its turn behind the Format: no generation of its own has started.
      await until(() => fillStatus('n3', blankKey('', 0))?.phase == FillPhase.waiting);
      expect(fakes, hasLength(1));
      fakes[0].finish('formatted');
      await format.done;
      await until(() => fakes.length == 2);
      startRun(const RunRequest(noteId: 'n3', kind: RunKind.format, model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 10));
      await until(() => said.contains('Format stopped the fill. 2 blanks are still questions.'));
      expect(note.lands, 0);
      openForFills('n3', null);
    });

    test('asks one blank a generation for a model at the second rung, and writes one line in the log', () async {
      final note = Host(tokyo);
      openForFills('n4', note);
      pressFill('n4', targets(tokyo), 'qwen3.5-model-nobody-measured');
      await until(() => fakes.length == 1);
      expect(fakes[0].options.prompt, isNot(contains('{?2')));
      fakes[0].finish('midweek');
      await until(() => fakes.length == 2);
      fakes[1].finish('Canberra');
      await until(() => runsOf('n4').length == 1);
      expect(runsOf('n4')[0].filled, 2);
      expect(runsOf('n4')[0].before, tokyo);
      expect(runsOf('n4')[0].after, note.body);
      expect(note.lands, 2);
      openForFills('n4', null);
    });
  });

  group('a note closed while it fills', () {
    test('lands its answers in the store, with the revision it was read at, and says so with Open', () async {
      final made = createNote('n5', tokyo);
      final note = Host(tokyo);
      openForFills('n5', note);
      pressFill('n5', targets(tokyo), 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      openForFills('n5', null);
      fakes[0].finish('[1] midweek\n[2] Canberra');
      await until(() => said.any((m) => m.startsWith('Filled 2 blanks in Tokyo trip.')));
      final stored = await getNote('n5');
      expect(stored!.body, contains('??Canberra??(Qwen3.5 4B from memory, 2026-09-28)'));
      expect(stored.revision, made.revision + 1);
      final toast = toasts.firstWhere((t) => t.message.startsWith('Filled 2'));
      expect(toast.action?.label, 'Open');
      expect(runsOf('n5')[0].filled, 2);
      expect(runsOf('n5')[0].before, tokyo);
    });
  });

  group('a live blank, looked up by the phone', () {
    const weather = '# Lisbon\n\nWeather in Lisbon tomorrow: {?weather}';

    test('waits for a connection offline, then asks Open-Meteo and writes the answer from what came back', () async {
      setFillWorld(fetch: (url) async => throw StateError('offline'));
      final note = Host(weather);
      openForFills('n6', note);
      pressFill('n6', targets(weather), 'qwen3.5-4b');
      await until(() => fillStatus('n6', blankKey('weather', 0))?.phase == FillPhase.paused);
      expect(fillStatus('n6', blankKey('weather', 0)), const FillStatus.paused(why: PausedWhy.offline));
      expect(fakes, isEmpty);
      // The press says what it did with the blank, where it used to say nothing at all (found by the shots).
      await until(() => toasts.length == 1);
      expect(toasts[0].message, 'Waiting for a connection. The phone looks it up once it is online.');
      final asked = <String>[];
      setFillWorld(fetch: (url) async {
        asked.add(url);
        return (status: 200, json: url.contains('geocoding') ? geocode : forecast);
      });
      resumeParked();
      await until(() => note.lands == 1);
      expect(asked[0], contains('name=Lisbon'));
      // The forecast is the app's own sentence from Open-Meteo's data: no model writes it, and the bracket says so.
      expect(fakes, isEmpty);
      expect(note.body, matches(RegExp(r'\?\?[A-Z][^?]* to \d+ °C\?\?\(Ghost\.md from Open-Meteo, 2026-09-28\. Asked: weather\)')));
      openForFills('n6', null);
    });

    test('says so when the source had nothing', () async {
      setFillWorld(fetch: (url) async => (status: 200, json: <String, Object?>{'results': <Object?>[]}));
      final note = Host('# Nowhere\n\nWeather in Qqqzzxxy today: {?weather}');
      openForFills('n7', note);
      pressFill('n7', targets(note.body), 'qwen3.5-4b');
      await until(() => fillOutcome('n7', blankKey('weather', 0)) != null);
      final outcome = fillOutcome('n7', blankKey('weather', 0))!;
      expect(outcome.why, FillWhy.nothing);
      expect(outcome.words, 'Open-Meteo doesn’t know a place called Qqqzzxxy.');
      expect(fakes, isEmpty);
      openForFills('n7', null);
    });
  });

  // ---- the port's own ------------------------------------------------------------------------------------------------

  group('the port’s own cases', () {
    const weather = '# Lisbon\n\nWeather in Lisbon tomorrow: {?weather}';
    const cup = '# Football\n\nThe 2026 World Cup was won by {?}';

    test('holds a live blank once Local only is on, asks nothing more, and goes on when it is off', () async {
      final asked = <String>[];
      setFillWorld(fetch: (url) async {
        asked.add(url);
        return (status: 200, json: url.contains('geocoding') ? geocode : forecast);
      });
      final note = Host(weather);
      openForFills('p1', note);
      // Pressed with lookups on, and Local only turned on while the place's name was being asked: the switch is read
      // again before every request, so the coordinates never go.
      pressFill('p1', targets(weather), 'qwen3.5-4b');
      expect(asked, hasLength(1));
      preferences.update((p) => p.copyWith(localOnly: true));
      await until(() => fillStatus('p1', blankKey('weather', 0)) == const FillStatus.paused(why: PausedWhy.localOnly));
      await until(() => said.contains('Local only is on, so the phone looks nothing up.'));
      expect(asked, hasLength(1));
      resumeParked();
      await Future<void>.delayed(Duration.zero);
      expect(asked, hasLength(1));
      preferences.update((p) => p.copyWith(localOnly: false));
      resumeParked();
      await until(() => note.lands == 1);
      expect(note.body, contains('Ghost.md from Open-Meteo'));
      openForFills('p1', null);
    });

    test('lands a model’s answer as the web’s only when what came back holds it', () async {
      setFillWorld(fetch: (url) async => url.contains('en.wikipedia.org') ? (status: 200, json: wikiCup) : (status: 404, json: null));
      final note = Host(cup);
      openForFills('p2', note);
      pressFill('p2', targets(cup), 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      expect(fakes[0].options.prompt, contains('What Wikipedia returned:\n'));
      expect(fakes[0].options.prompt, endsWith('\n\nAnswer blank 1.'));
      fakes[0].finish('[1] Brazil');
      await until(() => fillOutcome('p2', blankKey('', 0)) != null);
      expect(fillOutcome('p2', blankKey('', 0)), const FillOutcome(why: FillWhy.nothing, words: 'The answer wasn’t in what Wikipedia returned.', model: 'qwen3.5-4b'));
      await until(() => said.contains('Nothing filled. 1 not found online.'));
      expect(note.lands, 0);
      pressFill('p2', targets(cup), 'qwen3.5-4b');
      await until(() => fakes.length == 2);
      fakes[1].finish('[1] Spain');
      await until(() => note.lands == 1);
      expect(note.body, contains('??Spain??(Qwen3.5 4B from Wikipedia, 2026-09-28)'));
      openForFills('p2', null);
    });

    test('asks an answer again, and keeps the old one when the same comes back', () async {
      const mark = '??France??(Qwen3.5 4B from memory, 2026-09-28)';
      const body = '# Football\n\nThe 2022 World Cup was won by $mark';
      final note = Host(body);
      openForFills('p3', note);
      FillTarget again() => FillTarget(key: blankKey('', 0), question: '', order: 0, again: const FillAgain(mark: mark, words: 'France'));
      pressFill('p3', [again()], 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      expect(fakes[0].options.prompt, contains('It is not: France'));
      fakes[0].finish('[1] France');
      await until(() => said.contains('The same answer came back.'));
      expect(note.body, body);
      pressFill('p3', [again()], 'qwen3.5-4b');
      await until(() => fakes.length == 2);
      fakes[1].finish('[1] Argentina');
      await until(() => note.lands == 1);
      expect(note.body, endsWith('The 2022 World Cup was won by ??Argentina??(Qwen3.5 4B from memory, 2026-09-28)'));
      openForFills('p3', null);
    });

    test('keeps a closed note’s answers when the write will not go through, and lands them when it is next opened', () async {
      createNote('p4', tokyo);
      final first = Host(tokyo);
      openForFills('p4', first);
      pressFill('p4', targets(tokyo), 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      openForFills('p4', null);
      stop();
      stop = startFills(toasts.add, opened.add, getNote: getNote, updateNote: (id, body, revision) async => throw StateError('The disk is full.'));
      fakes[0].finish('[1] midweek\n[2] Canberra');
      await until(() => fillStatus('p4', blankKey('', 0)) == null);
      await Future<void>.delayed(Duration.zero);
      expect(notes['p4']!.body, tokyo);
      expect(runsOf('p4'), isEmpty);
      final reopened = Host(tokyo);
      openForFills('p4', reopened);
      expect(reopened.lands, 1);
      expect(reopened.body, contains('??Canberra??'));
      expect(runsOf('p4').single.filled, 2);
      openForFills('p4', null);
    });

    test('reads a closed note again once when it changed under the write, and syncs either side', () async {
      createNote('p5', tokyo);
      final note = Host(tokyo);
      openForFills('p5', note);
      pressFill('p5', targets(tokyo), 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      openForFills('p5', null);
      var writes = 0;
      stop();
      stop = startFills(toasts.add, opened.add, getNote: getNote, syncNow: () async => syncs += 1, updateNote: (id, body, revision) {
        writes += 1;
        // Another device's edit lands between the read and the first write.
        if (writes == 1) notes[id] = notes[id]!.copyWith(body: '${notes[id]!.body}\n\nAdded elsewhere.', revision: notes[id]!.revision + 1);
        return updateNote(id, body, revision);
      });
      fakes[0].finish('[1] midweek\n[2] Canberra');
      await until(() => said.any((m) => m.startsWith('Filled 2 blanks in Tokyo trip.')));
      expect(writes, 2);
      expect(notes['p5']!.body, contains('??Canberra??'));
      expect(notes['p5']!.body, endsWith('Added elsewhere.'));
      expect(notes['p5']!.revision, 3);
      expect(syncs, 2);
      toasts.firstWhere((t) => t.action != null).action!.onPress();
      expect(opened, ['p5']);
    });

    test('says a failure in the model’s own words, and a note too long in the app’s', () async {
      final note = Host(tokyo);
      openForFills('p6', note);
      pressFill('p6', targets(tokyo), 'qwen3.5-4b');
      await until(() => fakes.length == 1);
      fakes[0].fail('The prompt is too long for the context.');
      await until(() => said.contains('This part of the note is too long for the model. Try a shorter section.'));
      expect(fillStatus('p6', blankKey('', 0)), isNull);
      expect(note.lands, 0);
      openForFills('p6', null);
    });

    test('builds the toast from a press’s counts', () {
      FillBatch press({int landed = 0, FillCounts? counts, int parked = 0, FillStopped? stopped, String? failed, int blanks = 3}) => FillBatch(
            noteId: 'n',
            targets: [for (var i = 0; i < blanks; i += 1) FillTarget(key: blankKey('', i), question: '', order: i)],
            landed: landed,
            counts: counts,
            parked: parked,
            stopped: stopped,
            failed: failed,
          );
      expect(pressToast(press(landed: 3)), isNull);
      expect(pressToast(press(counts: FillCounts(none: 2)))?.message, 'Nothing filled. No answer came.');
      expect(pressToast(press(landed: 1, counts: FillCounts(none: 2)))?.message, '1 filled. 2 had no answer.');
      expect(pressToast(press(counts: FillCounts(unknown: 1, didntFit: 1, none: 1, nothing: 1)))?.message, "Nothing filled. 1 not known, 1 didn't fit, 1 had no answer, 1 not found online.");
      expect(pressToast(press(parked: 2))?.message, 'Waiting for a connection. The phone looks them up once it is online.');
      expect(pressToast(press(landed: 1, parked: 1))?.message, '1 filled. 1 waiting for a connection.');
      expect(pressToast(press(counts: FillCounts(changed: 2)))?.message, '2 answers were not written. Their questions had changed.');
      expect(pressToast(press(landed: 1, counts: FillCounts(unknown: 1, changed: 1)))?.message, '1 filled. 1 not known. 1 answer was not written. Its question had changed.');
      expect(pressToast(press(stopped: const FillStopped())), isNull);
      expect(pressToast(press(landed: 2, stopped: const FillStopped.byKind(RunKind.summarize)))?.message, 'Summarize stopped the fill. 1 blank is still a question.');
      expect(pressToast(press(stopped: const FillStopped.byKind(RunKind.continueWriting)))?.message, 'Continue stopped the fill. 3 blanks are still questions.');
      expect(pressToast(press(failed: 'The model stopped.'))?.message, 'The model stopped.');
      preferences.update((p) => p.copyWith(localOnly: true));
      expect(pressToast(press(parked: 1))?.message, 'Local only is on, so the phone looks nothing up.');
      expect(pressToast(press(landed: 1, parked: 1))?.message, '1 filled. 1 held by Local only.');
      expect(lookupsHere().id, 'local-only');
    });
  });
}
