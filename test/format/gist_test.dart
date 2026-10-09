// The gist (lib/format/gist.dart). A port of `src/app/format/gist.test.tsx` and `gistRunner.test.tsx`, case for case.
//
// The page's tests mounted a component that called `useGists`; here a [Gists] is made and handed the notes, which is
// all the hook did. The phone is the AI tests' scripted engine (test/ai/fake_backend.dart).

import 'dart:async';

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
