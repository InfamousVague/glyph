// The gist (lib/format/gist.dart). A port of `src/app/format/gist.test.tsx` and `gistRunner.test.tsx`, case for case.
//
// The page's tests mounted a component that called `useGists`; here a [Gists] is made and handed the notes, which is
// all the hook did. The phone is the AI tests' scripted engine (test/ai/fake_backend.dart).

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/runs.dart' show forgetAllRuns;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/format/body_hash.dart';
import 'package:ghost_md/format/gist.dart';
import 'package:ghost_md/format/results.dart';

import '../ai/fake_backend.dart';

Note makeNote(String id, String body, {int updatedAt = 0}) => Note(id: id, body: body, createdAt: 0, updatedAt: updatedAt, source: NoteSource.editor, revision: 1);

const List<Map<String, Object?>> present = [
  {'id': 'qwen3.5-2b', 'file': 'qwen3.5-2b.gguf', 'bytes': 1, 'present': true, 'path': '/m'},
];

void main() {
  late FakeAiBackend phone;
  final made = <Gists>[];

  /// The page, as far as the runner knows: the notes it has cards for.
  Gists show(List<Note> notes) {
    final gists = Gists()..show(notes);
    made.add(gists);
    return gists;
  }

  setUp(() {
    useStored(MemoryStored());
    forgetGistRunner();
    forgetAllRuns();
    phone = FakeAiBackend();
    useAiBackend(phone);
    phone.answers['ai_models'] = present;
    phone.answers['ai_generate'] = {'text': 'A walk to the square', 'promptTokens': 10, 'outputTokens': 5, 'ms': 100, 'cachedTokens': 0, 'prefillMs': 10, 'loadMs': 10, 'tokensPerSecond': 9, 'truncated': false};
  });

  tearDown(() {
    for (final gists in made) {
      gists.dispose();
    }
    made.clear();
    forgetGistRunner();
  });

  group('the gist as a card line', () {
    test('takes the first line, bare: no heading marks, bullets, quotes, bold or closing punctuation', () {
      expect(tidyGist('# Call the plumber by Thursday.\n\nMore.'), 'Call the plumber by Thursday');
      expect(tidyGist('- "Pick up **eggs** and coffee!"\n'), 'Pick up eggs and coffee');
      expect(tidyGist('```\nPlans for the weekend\n```'), 'Plans for the weekend');
      expect(tidyGist('\n\n   Errands for tomorrow   \n'), 'Errands for tomorrow');
      expect(tidyGist(''), '');
    });

    test('cuts a long answer at a word and says so', () {
      const long = 'A very long line that goes on and on about the plumber and the tap and the eggs and the coffee and the cabin and the ferry';
      final cut = tidyGist(long);
      expect(cut.length, lessThanOrEqualTo(91));
      expect(cut.endsWith('…'), isTrue);
      expect(cut, isNot(matches(RegExp(r'\s…$'))));
    });
  });

  group('what the home page shows', () {
    test('shows a gist while it stands for the note: the same body, or one changed in a small way', () {
      const body = 'things for tomorrow\n- milk and the good coffee from the corner shop\n- call the dentist before ten\n';
      keepGist('n1', Gist(text: 'Plans for tomorrow', forBody: bodyHash(body), model: 'qwen3.5-2b', len: body.length, head: 'things for tomorrow'));
      expect(gistFor('n1', body), 'Plans for tomorrow');
      // A fixed word: still stands.
      expect(gistFor('n1', body.replaceFirst('good coffee', 'nice coffee')), 'Plans for tomorrow');
      // A new paragraph, or a new first line: a meaningful change, asked again.
      expect(gistFor('n1', '$body\nAnd the whole plan for the weekend trip to the cabin with Sam.\n'), isNull);
      expect(gistFor('n1', body.replaceFirst('things for tomorrow', 'plans for the week')), isNull);
      expect(gistFor('n2', 'anything'), isNull);
    });

    test('asks again for a gist kept before lengths were recorded, unless the body is the same', () {
      keepGist('n3', Gist(text: 'Old', forBody: bodyHash('a note'), model: 'qwen3.5-2b'));
      expect(gistStands((forBody: bodyHash('a note'), len: null, head: null), 'n3', 'a note'), isTrue);
      expect(gistStands((forBody: bodyHash('a note'), len: null, head: null), 'n3', 'a note!'), isFalse);
    });
  });

  group('the runner', () {
    test('gives the model the words after the front matter, and keeps the gist against those words', () async {
      const words = '# A walk\n\nDown to the square and back, before the rain.\n';
      const tagged = '---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n$words';
      show([makeNote('n1', tagged, updatedAt: 1)]);
      await runGists();
      expect(phone.requests, hasLength(1));
      expect(phone.requests[0]['prompt'], words);
      expect(phone.requests[0]['prompt'], isNot(contains('location:')));
      final kept = readGist('n1')!;
      expect(kept.text, 'A walk to the square');
      expect((kept.forBody, kept.len, kept.head), (bodyHash(words), words.length, '# A walk'));
      // A place written in changes the note but not its words: the gist still stands.
      expect(gistFor('n1', tagged.replaceFirst('Trafalgar Square, London', 'London')), 'A walk to the square');
      expect(gistFor('n1', words), 'A walk to the square');
    });

    test('gives the model a note’s blanks taken out and its fills as words (docs/DESIGN.md §145)', () async {
      const body = '# Tokyo\n\nCheapest on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day) and {?which airport} too.\n';
      show([makeNote('n2', body, updatedAt: 1)]);
      await runGists();
      expect(phone.requests, hasLength(1));
      expect(phone.requests[0]['prompt'], '# Tokyo\n\nCheapest on midweek and too.\n');
    });
  });

  // gistRunner.test.tsx
  group('the gist runner', () {
    setUp(() {
      phone.answers['ai_models'] = const [
        {'id': 'qwen3.5-2b', 'present': true},
        {'id': 'qwen3.5-4b', 'present': true},
      ];
      phone.answers['ai_generate'] = (Object? args) {
        final prompt = (((args! as Map)['request'] as Map)['prompt'] as String).split('\n').first;
        return {'text': '# Gist of $prompt.\n', 'ms': 5, 'truncated': false, 'outputTokens': 6, 'thinking': false};
      };
    });

    test('writes nothing while the recorder holds the cores, and carries on once it has gone', () async {
      show([makeNote('p1', 'plans for the weekend\n- cabin\n', updatedAt: 3)]);
      pauseGists(true);
      await runGists();
      expect(phone.requests, isEmpty);
      pauseGists(false);
      await runGists();
      expect(phone.requests, hasLength(1));
    });

    test('starts nothing when the recorder comes up while the catalogue is being read', () async {
      show([makeNote('p2', 'plans for the weekend\n- cabin\n', updatedAt: 3)]);
      final release = Completer<Object?>();
      phone.answers['ai_models'] = () => release.future;
      final turn = runGists();
      pauseGists(true);
      release.complete(const [
        {'id': 'qwen3.5-2b', 'present': true},
      ]);
      await turn;
      expect(phone.requests, isEmpty);
      phone.answers['ai_models'] = const [
        {'id': 'qwen3.5-2b', 'present': true},
      ];
      pauseGists(false);
      await runGists();
      expect(phone.requests, hasLength(1));
    });

    test('hands the home page a gist the moment it lands, with the notes as they were', () async {
      final gists = show([makeNote('n3', 'plans for the weekend\n- cabin\n', updatedAt: 3)]);
      var told = 0;
      gists.addListener(() => told += 1);
      expect(gists.value, isEmpty);
      // The whole turn before the page draws again: the runner starting and its landing reach the page together,
      // which is how an answer that comes back quickly arrives; the page must read the gists again for it all the
      // same.
      await runGists();
      expect(told, greaterThan(0));
      expect(gists.value, {'n3': 'Gist of plans for the weekend'});
    });

    // Differs 12 (docs/PARITY.md), the runner's half. The page's turn said it had begun before it knew there was a
    // model, and with none said it had ended and looked again 800 ms on, for as long as the app was open: an ask of
    // the engine and two tellings of every card each time (measured: 39 asks in 30 s). Here a turn asks first, and
    // with no model tells nobody and waits for the models to change.
    testWidgets('with no model on the phone asks once, lights no card, tells no page, and looks again only when the models change', (tester) async {
      phone.answers['ai_models'] = const [
        {'id': 'qwen3.5-2b', 'present': false},
      ];
      final note = makeNote('m1', 'plans for the weekend\n- cabin\n', updatedAt: 3);
      final gists = show([note]);
      var told = 0;
      gists.addListener(() => told += 1);
      final lit = <String?>[];
      void heard() => lit.add(gistWorking.value);
      gistWorking.addListener(heard);
      addTearDown(() => gistWorking.removeListener(heard));
      // The first look comes a second and a half after the page showed its cards; then half a minute of nothing.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 30));
      expect(phone.calls('ai_models'), hasLength(1));
      expect(phone.requests, isEmpty);
      expect(told, 0, reason: 'nothing began, so no page reads its lines again');
      expect(lit, isEmpty, reason: 'no card wore the ring for a line nobody could write');
      // The page showing its cards again (a letter in its search) asks nothing more of a phone with no model.
      gists.show([note]);
      await tester.pump(const Duration(seconds: 30));
      expect(phone.calls('ai_models'), hasLength(1));

      // The catalogue says something that leaves the same models on the phone (a fetch's chunk): still nothing.
      final models = ValueNotifier<int>(0);
      addTearDown(models.dispose);
      var present = const <String>[];
      final stop = wakeGistsOn(models, () => present);
      models.value += 1;
      await tester.pump(const Duration(seconds: 30));
      expect(phone.calls('ai_models'), hasLength(1));
      // A model is there: the runner looks again, and the line is written.
      phone.answers['ai_models'] = const [
        {'id': 'qwen3.5-2b', 'present': true},
      ];
      present = const ['qwen3.5-2b'];
      models.value += 1;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(phone.calls('ai_models'), hasLength(2));
      expect(phone.requests, hasLength(1));
      expect(gists.value, {'m1': 'Gist of plans for the weekend'});
      expect(lit, ['m1', null], reason: 'the card wore the ring while its line was written, and no longer');
      expect(told, greaterThan(0));
      stop();
      // The runner's next look is waiting: let go, as the app's end lets it go.
      forgetGistRunner();
    });

    // The home page is kept under All notes here, so both have handed their cards over: All notes' are worked
    // through first, and the home page's are the runner's again when All notes has gone.
    test('works through the cards of the page that showed its own last, then the other page\'s, and lets go of a page that has gone', () async {
      final home = show([makeNote('h1', 'home page note\n- one\n', updatedAt: 9)]);
      final all = show([makeNote('a1', 'all notes note\n- two\n', updatedAt: 1), makeNote('h1', 'home page note\n- one\n', updatedAt: 9)]);
      await runGists();
      expect([for (final request in phone.requests) (request['prompt'] as String).split('\n').first], ['home page note']);
      // (Newest first within a page: the note both pages have is the newest All notes shows.)
      await runGists();
      expect([for (final request in phone.requests) (request['prompt'] as String).split('\n').first], ['home page note', 'all notes note']);
      // A page that has gone before its cards were reached: they are nobody's.
      final late = show([makeNote('l1', 'a late note\n- three\n', updatedAt: 2)]);
      late.dispose();
      made.remove(late);
      await runGists();
      expect(phone.requests, hasLength(2));
      expect(home.value.keys, ['h1']);
      expect(all.value.keys, unorderedEquals(['a1', 'h1']));
    });

    test('goes on with the cards it was last shown when the page that showed them has gone, as under an open note', () async {
      // The web app's bodies are a module's: the home page taken down under a note leaves them where they were.
      final home = show([makeNote('u1', 'left under a note\n- one\n', updatedAt: 4)]);
      home.dispose();
      made.remove(home);
      await runGists();
      expect([for (final request in phone.requests) (request['prompt'] as String).split('\n').first], ['left under a note']);
      expect(gistFor('u1', 'left under a note\n- one\n'), 'Gist of left under a note');
    });

    test('writes a gist for a note the home page showed, with the smallest model, and keeps it against the body', () async {
      show([makeNote('n1', 'things for tomorrow\n- milk\n', updatedAt: 2), makeNote('n2', '', updatedAt: 1)]);
      await runGists();
      expect(phone.commands, contains('ai_models'));
      expect((phone.requests[0]['model'], phone.requests[0]['maxTokens']), ('qwen3.5-2b', 40));
      final kept = readGist('n1')!;
      expect((kept.text, kept.forBody, kept.model, kept.head), ('Gist of things for tomorrow', bodyHash('things for tomorrow\n- milk\n'), 'qwen3.5-2b', 'things for tomorrow'));
      expect(gistFor('n1', 'things for tomorrow\n- milk\n'), 'Gist of things for tomorrow');
      // The empty note is never asked about, and a note with a gist is not asked twice.
      await runGists();
      expect(phone.requests, hasLength(1));
    });
  });
}
