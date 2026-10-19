import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/route.dart';
import 'package:ghost_md/capture/voice_plan.dart';

/// Checking what the model says against what was said (lib/capture/voice_plan.dart), case for case with the web's
/// `capture/voicePlan.test.ts`.
const movies = Candidate(id: 'movies', title: 'Movies');
const notes = [movies, Candidate(id: 'go', title: 'Go')];

void main() {
  group('checking what the model says against what was said', () {
    final said = wordsOf('okay spider man batman and the fantastic four, parkersburg west virginia');

    test('accepts tidied forms of words that were said', () {
      for (final item in ['Spider-Man', 'Spiderman', 'Batman', 'The Fantastic Four', 'Parkersburg, West Virginia']) {
        expect(grounded(item, said), true, reason: item);
      }
    });

    test('refuses words that were never said', () {
      for (final item in ['Superman', 'Green Lantern', 'Spider-Man 2099', 'Batman 3']) {
        expect(grounded(item, said), false, reason: item);
      }
    });

    test('counts a number said as a word', () {
      expect(grounded('Back to the Future Part 2', wordsOf('back to the future part two')), true);
      expect(grounded('Part two', wordsOf('part 2')), true);
    });

    test('keeps model text literal', () {
      expect(plainText('# Heading'), r'\# Heading');
      expect(plainText('- not a bullet'), r'\- not a bullet');
      expect(plainText('[link](x) <b>'), r'\[link\](x) \<b\>');
      expect(plainText('St. Louis, Spider-Man'), 'St. Louis, Spider-Man');
    });

    test('reads the sort, and only the four kinds', () {
      expect(readSort({'kind': 'mixed'}), 'mixed');
      expect(readSort({'kind': 'delete'}), isNull);
      expect(readSort('add'), isNull);
    });

    test('reads a plan into checked actions and reports what it set aside', () {
      final read = readPlan<Candidate>(
        {
          'actions': [
            {'do': 'append', 'note': 'movies', 'items': ['Heat', 'Alien 3'], 'text': null, 'as': 'list'},
            {'do': 'create', 'title': 'Comic Books', 'items': ['Batman'], 'as': 'tasks'},
            {'do': 'append', 'note': 'Camping', 'items': ['tent'], 'text': null, 'as': 'list'},
          ],
          'note': 'I watched Heat.',
        },
        'I watched Heat and Alien, add them to movies, and make comic books with batman, and a tent for camping',
        notes,
      );
      expect(read?.actions, [
        const VoiceAppend<Candidate>(note: movies, text: 'Heat', placement: Placement(how: PlacementHow.item, task: false, many: false, items: ['Heat'])),
        const VoiceCreate<Candidate>(title: 'Comic Books', items: ['Batman'], tasks: true),
      ]);
      expect(read?.note, 'I watched Heat.');
      expect(read?.problems, ['dropped “Alien 3”: not something you said', 'no note called “Camping”']);
    });

    test('refuses a plan of the wrong shape', () {
      expect(readPlan<Candidate>({'actions': 'Heat'}, 'Heat', notes), isNull);
      expect(readPlan<Candidate>({'actions': [1, 2, 3, 4]}, 'Heat', notes), isNull);
      expect(readPlan<Candidate>(null, 'Heat', notes), isNull);
    });
  });

  group('a new note with words in it', () {
    const said = 'make me a new note called directions and in that note put we go north then east';

    test('is read with its text', () {
      final read = readPlan<Candidate>({
        'actions': [
          {'do': 'create', 'title': 'Directions', 'items': [], 'text': 'We go north, then east.', 'as': 'text'},
        ],
        'note': null,
      }, said, const []);
      expect(read?.actions, [const VoiceCreate<Candidate>(title: 'Directions', items: [], tasks: false, body: 'We go north, then east.')]);
    });

    test('is dropped when the text was not said, or is missing', () {
      final invented = readPlan<Candidate>({
        'actions': [
          {'do': 'create', 'title': 'Directions', 'items': [], 'text': 'Turn left at the lighthouse.', 'as': 'text'},
        ],
        'note': null,
      }, said, const []);
      expect(invented?.actions, isEmpty);
      expect(invented?.problems.first, contains('not what you said'));
      final empty = readPlan<Candidate>({
        'actions': [
          {'do': 'create', 'title': 'Directions', 'items': [], 'text': null, 'as': 'text'},
        ],
        'note': null,
      }, said, const []);
      expect(empty?.actions, isEmpty);
    });
  });

  group('the rest of a recording', () {
    const list = [Candidate(id: 'movies', title: 'Movies')];

    test('is dropped when it is the whole recording said again', () {
      const said = 'Add to the movies list Jaws and Alien. And make a new list called Elements and add copper.';
      final read = readPlan<Candidate>({
        'actions': [
          {'do': 'append', 'note': 'Movies', 'items': ['Jaws', 'Alien'], 'text': null, 'as': 'list'},
          {'do': 'create', 'title': 'Elements', 'items': ['Copper'], 'text': null, 'as': 'list'},
        ],
        'note': said,
      }, said, list);
      expect(read?.actions, hasLength(2));
      expect(read?.note, isNull);
      expect(read?.problems.join(' '), contains('repeats'));
    });

    test('is kept when it is something else that was said', () {
      const said = 'Add to the movies list Jaws. Also I was thinking we should visit the lighthouse in May.';
      final read = readPlan<Candidate>({
        'actions': [
          {'do': 'append', 'note': 'Movies', 'items': ['Jaws'], 'text': null, 'as': 'list'},
        ],
        'note': 'I was thinking we should visit the lighthouse in May.',
      }, said, list);
      expect(read?.note, 'I was thinking we should visit the lighthouse in May.');
    });
  });

  group('the native step and the engine’s diagnostics', () {
    test('a step is sent as the core takes it, and its answers are read', () async {
      Map<String, Object?>? sent;
      final step = voiceStepOver((command, args) async {
        sent = {'command': command, ...args};
        return {'status': 'answer', 'answer': {'kind': 'add'}, 'raw': '{"kind":"add"}', 'model': 'm'};
      }, preferredModel: 'qwen3.5-4b');
      final result = await step('plan', 'add', 'hello', ['Go'], 'draft');
      expect(result, isA<StepAnswer>());
      final request = (sent!['request'] as Map);
      expect(sent!['command'], 'ai_voice_step');
      expect([request['stage'], request['kind'], request['transcript'], request['titles'], request['draft'], request['preferredModel']], ['plan', 'add', 'hello', ['Go'], 'draft', 'qwen3.5-4b']);
      expect(await voiceStepOver((c, a) async => {'status': 'refused', 'reason': 'no'})('sort', null, 'x', const []), isA<StepRefused>());
      expect(await voiceStepOver((c, a) async => 'odd')('sort', null, 'x', const []), isA<StepUnavailable>());
      final thrown = await voiceStepOver((c, a) async => throw Exception('boom'))('sort', null, 'x', const []);
      expect((thrown as StepUnavailable).reason, 'boom');
    });

    test('the diagnostics read as lines, and never throw', () async {
      final lines = await diagnosticsOver((c, a) async => {
        'engineStarted': true,
        'modelLoaded': false,
        'runs': [{'id': 'voice-1', 'what': 'voice sort', 'ageMs': 1500}],
        'events': [{'at': 0, 'line': 'one'}, {'at': 0, 'line': 'two'}],
      })(1);
      expect(lines.first, 'engine: started, model not in memory; running: voice sort voice-1 for 1.5s');
      expect(lines, hasLength(2));
      expect(lines.last, endsWith(': two'));
      expect(await diagnosticsOver(null)(), isEmpty);
      expect((await diagnosticsOver((c, a) async => throw Exception('gone'))()).single, 'engine: could not be read (gone)');
    });
  });
}
