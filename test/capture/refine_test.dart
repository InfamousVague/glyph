import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart' show CaptureEventRefineProgress;
import 'package:ghost_md/capture/refine.dart';
import 'package:ghost_md/capture/refine_text.dart' show refinedBody;
import 'package:ghost_md/capture/take_types.dart' show Span;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/stored.dart';

import 'support/capture_backend_fake.dart';

/// The pass after a recording (lib/capture/refine.dart): the queue it keeps on the phone, when it runs and when it
/// waits, and what it writes. Case for case with the web's `capture/refine.test.ts`. The bridge is a stand-in that
/// answers as Rust would, the note store among its answers (`get_note`, `update_note`, `set_note_recording`, as the
/// web's store reaches them), and the clock is the widget tester's fake one, so "twenty seconds later" is a thing a
/// test can say.

bool native = true;
int generation = 7;
final Map<String, Note> notes = {};
final backend = FakeCaptureBackend();
Preferences prefs = Preferences.defaults;
Stored stored = MemoryStored();

/// The summary sections the app wrote (`ai/summaryKeep.ts`), by note.
final Map<String, String> summaries = {};
bool writingUp = false;
int changed = 0;

const queueKey = 'glyph-refine-queue';
List<Map<String, Object?>> queued() => (jsonDecode(stored.readText(queueKey) ?? '[]') as List).cast<Map<String, Object?>>();
List<Map<String, Object?>> calls(String command) => backend.calls(command);

Note note(String id, String body, int revision) => Note(id: id, body: body, createdAt: 0, updatedAt: 0, revision: revision);

RefineJob job({
  String id = 'n1',
  int fromMs = 0,
  int recordingMs = 2400,
  String baseBody = '',
  String savedBody = '# Grocery run\n\nOat milk and legs.',
  bool titled = true,
  String promptTail = '',
  List<Span>? skip,
}) =>
    RefineJob(id: id, fromMs: fromMs, recordingMs: recordingMs, baseBody: baseBody, savedBody: savedBody, titled: titled, priorSegments: const [], promptTail: promptTail, skip: skip);

const better = [
  Segment(text: 'Grocery run.', startMs: 0, endMs: 900),
  Segment(text: 'Oat milk and eggs.', startMs: 1200, endMs: 2400),
];

late Refining refining;
void Function()? stop;

Refining make() => Refining(
      backend: native ? backend : null,
      hasNativeGeneration: (wanted) async => native && generation >= wanted,
      preferences: () => prefs,
      stored: stored,
      getNote: (id) async => await backend.answers['get_note']!({'id': id}) as Note?,
      updateNote: (id, body, expectedRevision) async {
        final args = {'id': id, 'body': body, 'expectedRevision': expectedRevision};
        backend.invoked.add({'command': 'update_note', 'args': args});
        return await backend.answers['update_note']!(args) as Note;
      },
      setNoteRecording: (id, recordingMs, segments) async {
        final args = {'id': id, 'recordingMs': recordingMs, 'segments': segments};
        backend.invoked.add({'command': 'set_note_recording', 'args': args});
        return await backend.answers['set_note_recording']!(args) as Note?;
      },
      keptText: (id) => summaries[id],
      summaryUnchanged: (id, text) => summaries[id] == text,
      writeUpRunning: () => writingUp,
      warn: (_) {},
    );

/// The web's `beforeEach`, inside the tester's fake time.
void begin() {
  stored = MemoryStored();
  native = true;
  generation = 7;
  notes.clear();
  backend.reset();
  summaries.clear();
  writingUp = false;
  prefs = Preferences.defaults.copyWith(refine: true, localOnly: false);
  notes['n1'] = note('n1', '# Grocery run\n\nOat milk and legs.', 1);
  backend.answers['get_note'] = (args) => notes[args!['id']];
  backend.answers['update_note'] = (args) {
    final next = note(args!['id']! as String, args['body']! as String, (args['expectedRevision']! as int) + 1);
    notes[next.id] = next;
    return next;
  };
  backend.answers['set_note_recording'] = (args) => notes[args!['id']];
  backend.answers['capture_refine_model_status'] = (_) => (present: true, bytes: 190000000);
  backend.answers['capture_refine'] = (_) => better;
  changed = 0;
  refining = make();
  stop = refining.startRefining(() => changed += 1);
}

/// The web's `afterEach`: the runner stopped, the recorder gone, and no timer left on the clock.
void end() {
  refining.setRecorderLive(false);
  stop?.call();
}

/// A case, between the web's `beforeEach` and `afterEach`.
void refineTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    begin();
    try {
      await body(tester);
    } finally {
      end();
    }
  });
}

extension on WidgetTester {
  /// The web's `vi.advanceTimersByTimeAsync`.
  Future<void> advance(int ms) => pump(Duration(milliseconds: ms));
}

void main() {
  group('the better words', () {
    refineTest('replace the words of a note that still reads as Done left it, and the phrases on its tape', (tester) async {
      refining.enqueueRefine(job());
      expect(queued(), hasLength(1));
      await tester.advance(0);
      expect(calls('capture_refine')[0]['args'], {'id': 'n1', 'fromMs': 0, 'promptTail': ''});
      expect(notes['n1']?.body, '# Grocery run\n\nOat milk and eggs.');
      expect(calls('set_note_recording')[0]['args'], {'id': 'n1', 'recordingMs': 2400, 'segments': better});
      expect(queued(), isEmpty);
      expect(changed, 1);
    });

    refineTest('leave a note someone changed since Done as they left it, and still put the better phrases on its tape', (tester) async {
      notes['n1'] = note('n1', '# Grocery run\n\nOat milk and legs. And bread.', 2);
      refining.enqueueRefine(job());
      await tester.advance(0);
      expect(calls('update_note'), isEmpty);
      expect(notes['n1']?.body, '# Grocery run\n\nOat milk and legs. And bread.');
      expect(calls('set_note_recording'), hasLength(1));
      expect(queued(), isEmpty);
    });

    refineTest('are asked for once per take: a take queued again replaces its own job, another take joins the queue', (tester) async {
      refining.enqueueRefine(job(promptTail: 'first'));
      refining.enqueueRefine(job(promptTail: 'second'));
      refining.enqueueRefine(job(fromMs: 5000));
      expect(queued().map((j) => [j['fromMs'], j['promptTail'], j['tries']]), [
        [0, 'second', 0],
        [5000, '', 0],
      ]);
    });

    refineTest('are not asked for with better words switched off, or in a browser', (tester) async {
      prefs = prefs.copyWith(refine: false);
      refining.enqueueRefine(job());
      prefs = prefs.copyWith(refine: true);
      native = false;
      // The module reads `isTauri()` at each call; an object made with no backend is that answer.
      make().enqueueRefine(job());
      expect(queued(), isEmpty);
    });

    refineTest('wait on a binary without the larger model’s pass', (tester) async {
      generation = 6;
      refining.enqueueRefine(job());
      await tester.advance(60000);
      expect(backend.invoked, isEmpty);
      expect(queued(), hasLength(1));
    });
  });

  group('when the pass runs', () {
    refineTest('replaces the words of a note whose only change since Done is the summary the app wrote, and keeps that summary', (tester) async {
      const section = '## Summary\nThe run, in a line.\n\n- [ ] Oat milk.';
      summaries['n1'] = section;
      notes['n1'] = note('n1', '# Grocery run\n\n$section\n\nOat milk and legs.', 2);
      refining.enqueueRefine(job());
      await tester.advance(0);
      expect(notes['n1']?.body, '# Grocery run\n\n$section\n\nOat milk and eggs.');
      // The same where the title ran straight into its words, and where the editor landed it with a newline after.
      for (final (saved, body) in [
        ('# Grocery run\nOat milk and legs.', '# Grocery run\n\n$section\n\nOat milk and legs.'),
        ('# Grocery run\n\nOat milk and legs.', '# Grocery run\n\n$section\n\nOat milk and legs.\n'),
      ]) {
        notes['n1'] = note('n1', body, 3);
        refining.enqueueRefine(job(savedBody: saved));
        await tester.advance(0);
        expect(notes['n1']?.body, '# Grocery run\n\n$section\n\nOat milk and eggs.');
      }
    });

    refineTest('leaves a `## Summary` the person typed where it is, and stops for one of the app’s the person edited', (tester) async {
      // Typed before the take: in what Done saved, and in the better words already, so nothing is moved under the title.
      final typedInto = job(baseBody: '## Summary\nMy own first line.\nMy own second line.', titled: true);
      const live = [
        Segment(text: 'Grocery run.', startMs: 0, endMs: 900),
        Segment(text: 'Oat milk and legs.', startMs: 1200, endMs: 2400),
      ];
      final saved = refinedBody(typedInto.copyWith(tries: 0), live);
      expect(saved.startsWith('## Summary\nMy own first line.\nMy own second line.'), true);
      notes['n1'] = note('n1', saved, 2);
      refining.enqueueRefine(typedInto.copyWith(savedBody: saved));
      await tester.advance(0);
      expect(notes['n1']?.body, refinedBody(typedInto.copyWith(tries: 0), better));
      expect(notes['n1']?.body.startsWith('## Summary\nMy own first line.\nMy own second line.'), true);
      expect(notes['n1']?.body, contains('Oat milk and eggs.'));
      // The app's section, edited since: the person's, and their edit wins over the better words.
      summaries['n1'] = '## Summary\nThe run, in a line.';
      const edited = '# Grocery run\n\n## Summary\nMy words now.\n\nOat milk and legs.';
      notes['n1'] = note('n1', edited, 3);
      refining.enqueueRefine(job());
      await tester.advance(0);
      expect(notes['n1']?.body, edited);
      expect(queued(), isEmpty);
    });

    refineTest('marks a job started while its pass runs, and counts one found started at launch as a try', (tester) async {
      final release = Completer<List<Segment>>();
      backend.answers['capture_refine'] = (_) => release.future;
      refining.enqueueRefine(job());
      await tester.advance(0);
      expect(queued()[0]['started'], true);
      expect(refining.refinePending('n1'), true);
      release.complete(better);
      await tester.advance(0);
      expect(queued(), isEmpty);
      expect(refining.refinePending('n1'), false);
      // Left started by a pass that killed the app: the next launch counts it, and drops a job on its third.
      stored.writeText(
        queueKey,
        jsonEncode([
          {...job().toJson(), 'tries': 0, 'started': true},
          {...job(id: 'n2').toJson(), 'tries': 2, 'started': true},
        ]),
      );
      stop?.call();
      stop = refining.startRefining(() => changed += 1);
      expect(queued().map((j) => [j['id'], j['tries'], j['started']]), [
        ['n1', 1, false],
      ]);
    });

    refineTest('tells who follows the hold when the recorder or a review comes and goes', (tester) async {
      final heard = <bool>[];
      final off = refining.onRefineHold(heard.add);
      refining.setRecorderLive(true);
      expect(refining.refineHeld(), true);
      refining.setRecorderLive(true);
      refining.setRecorderLive(false);
      expect(refining.refineHeld(), false);
      off();
      refining.setRecorderLive(true);
      refining.setRecorderLive(false);
      expect(heard, [true, false]);
    });

    refineTest('never while the recorder is on screen, and soon after it goes', (tester) async {
      refining.setRecorderLive(true);
      refining.enqueueRefine(job());
      await tester.advance(30000);
      expect(calls('capture_refine'), isEmpty);
      refining.setRecorderLive(false);
      await tester.advance(1499);
      expect(calls('capture_refine'), isEmpty);
      await tester.advance(1);
      expect(calls('capture_refine'), hasLength(1));
    });

    refineTest('tries again twenty seconds after the phone was busy, not sooner, and the job keeps its tries', (tester) async {
      var busy = true;
      backend.answers['capture_refine'] = (_) {
        if (busy) {
          busy = false;
          // Rust's rejection reaches the page as the string it returned.
          // ignore: only_throw_errors
          throw 'the voice model is busy';
        }
        return better;
      };
      refining.enqueueRefine(job());
      await tester.advance(0);
      expect(calls('capture_refine'), hasLength(1));
      expect(queued()[0]['tries'], 0);
      await tester.advance(19999);
      expect(calls('capture_refine'), hasLength(1));
      await tester.advance(1);
      expect(calls('capture_refine'), hasLength(2));
      expect(queued(), isEmpty);
    });

    refineTest('gives a pass up after three failures, twenty seconds apart', (tester) async {
      backend.answers['capture_refine'] = (_) => throw Exception('the recording could not be read');
      refining.enqueueRefine(job());
      await tester.advance(0);
      expect(queued()[0]['tries'], 1);
      await tester.advance(20000);
      expect(queued()[0]['tries'], 2);
      await tester.advance(20000);
      expect(queued(), isEmpty);
      await tester.advance(120000);
      expect(calls('capture_refine'), hasLength(3));
    });

    refineTest('waits a minute for a larger model it cannot get, rather than asking for it again at once', (tester) async {
      prefs = prefs.copyWith(localOnly: true);
      backend.answers['capture_refine_model_status'] = (_) => (present: false, bytes: 190000000);
      refining.enqueueRefine(job());
      await tester.advance(0);
      expect(calls('capture_refine_model_status'), hasLength(1));
      await tester.advance(59999);
      expect(calls('capture_refine_model_status'), hasLength(1));
      await tester.advance(1);
      expect(calls('capture_refine_model_status'), hasLength(2));
      expect(calls('capture_fetch_refine_model'), isEmpty);
      expect(calls('capture_refine'), isEmpty);
    });

    refineTest('runs the next take’s pass half a second after one finishes', (tester) async {
      refining.enqueueRefine(job());
      refining.enqueueRefine(job(fromMs: 5000, savedBody: 'something else'));
      await tester.advance(0);
      expect(calls('capture_refine'), hasLength(1));
      await tester.advance(500);
      expect(calls('capture_refine'), hasLength(2));
      expect(queued(), isEmpty);
    });
  });

  group('a meeting’s take (the Mac)', () {
    const meeting = '# Meeting, 26 Sep 14:05\n\n## Transcript\n\nOat milk and legs.';

    refineTest('is known by its preference wherever it was queued, and its better phrases are its transcript again', (tester) async {
      prefs = prefs.copyWith(meetings: {'n1': 1});
      notes['n1'] = note('n1', meeting, 1);
      refining.enqueueRefine(job(savedBody: meeting, titled: false));
      expect(queued()[0]['meeting'], true);
      await tester.advance(0);
      // Rendered as a transcript under the date title: no title from the first sentence, no dictated shape.
      expect(notes['n1']?.body, '# Meeting, 26 Sep 14:05\n\n## Transcript\n\nGrocery run. Oat milk and eggs.');
      prefs = prefs.copyWith(meetings: {});
    });

    refineTest('waits while the phone’s write-up has the speech model', (tester) async {
      writingUp = true;
      refining.enqueueRefine(job());
      await tester.advance(0);
      expect(calls('capture_refine'), isEmpty);
      writingUp = false;
      await tester.advance(20000);
      expect(calls('capture_refine'), hasLength(1));
    });
  });

  group('the review’s own pass', () {
    refineTest('listens again now, telling its progress for this note only', (tester) async {
      final percent = <num>[];
      backend.answers['capture_refine'] = (_) {
        backend.say(const CaptureEventRefineProgress(id: 'other', percent: 10));
        backend.say(const CaptureEventRefineProgress(id: 'n1', percent: 50));
        return better;
      };
      expect(await refining.listenAgain(job(), percent.add), better);
      expect(percent, [50]);
      // Nobody is left listening for the progress.
      expect(backend.listening, 0);
    });

    refineTest('cannot listen again on a binary without the pass', (tester) async {
      generation = 6;
      expect(await refining.listenAgain(job(), (_) {}), isNull);
    });

    refineTest('keeps the better phrases on the tape with the commands left out', (tester) async {
      final phrases = [...better, const Segment(text: 'Hey Ghost, add bread to work.', startMs: 2500, endMs: 3800)];
      await refining.keepBetterPhrases(job(recordingMs: 4000, skip: const [Span(startMs: 2500, endMs: 3800)]), phrases);
      expect(calls('set_note_recording')[0]['args'], {'id': 'n1', 'recordingMs': 4000, 'segments': better});
    });
  });

  group('an open note', () {
    refineTest('has its pass wait until it is left, while the next note’s runs', (tester) async {
      notes['n2'] = note('n2', '# Grocery run\n\nOat milk and legs.', 1);
      refining.holdNote('n1', true);
      refining.enqueueRefine(job());
      refining.enqueueRefine(job(id: 'n2'));
      await tester.advance(0);
      expect(calls('capture_refine').map((call) => (call['args'] as Map)['id']), ['n2']);
      await tester.advance(30000);
      expect(calls('capture_refine'), hasLength(1));
      refining.holdNote('n1', false);
      await tester.advance(1500);
      expect(calls('capture_refine').map((call) => (call['args'] as Map)['id']), ['n2', 'n1']);
    });

    refineTest('can have a take’s pass taken out, so undone words are never written back', (tester) async {
      refining.holdNote('n1', true);
      refining.enqueueRefine(job());
      refining.dropRefine('n1', 0);
      refining.holdNote('n1', false);
      await tester.advance(5000);
      expect(calls('capture_refine'), isEmpty);
      expect(queued(), isEmpty);
    });
  });
}
