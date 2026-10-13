import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/route.dart';
import 'package:ghost_md/capture/voice_log.dart';
import 'package:ghost_md/capture/voice_plan.dart';
import 'package:ghost_md/capture/voice_polish.dart';

/// The last editor (lib/capture/voice_polish.dart), case for case with the web's `capture/voicePolish.test.ts`.
class _Trace implements VoiceTrace {
  final List<String> lines = [];

  @override
  int get at => 1;

  @override
  void step(String line) => lines.add(line);

  @override
  void decide(String outcome) {}
}

const note = Candidate(id: 'go', title: 'Go');
const notes = [note];
const said = 'make a new list called games and add to the list Zelda Mario Party Lego Batman Stardew Valley and Kirby';

const List<VoiceAction<Candidate>> created = [VoiceCreate<Candidate>(title: 'games?', items: ['Zelda Mario Party Lego Batman Stardew Valley and Kirby'], tasks: false)];
final split = {
  'actions': [
    {'do': 'create', 'title': 'Games', 'items': ['Zelda', 'Mario Party', 'Lego Batman', 'Stardew Valley', 'Kirby'], 'text': null, 'as': 'list'},
  ],
  'note': null,
};

Future<StepResult> unavailable(String stage, String? kind, String transcript, List<String> titles, [String? draft]) async => const StepUnavailable(reason: 'no model');

void main() {
  group('draftOf', () {
    test('writes a list, a note, and an addition as the plan’s JSON', () {
      const actions = <VoiceAction<Candidate>>[
        ...created,
        VoiceCreate<Candidate>(title: 'Directions', items: [], tasks: false, body: 'We go north.'),
        VoiceAppend<Candidate>(note: note, text: 'Zelda, Kirby', placement: Placement(how: PlacementHow.item, task: true, many: true, items: ['Zelda', 'Kirby'])),
        VoiceAppend<Candidate>(note: note, text: 'More words.', placement: Placement(how: PlacementHow.leave, task: false, many: false)),
      ];
      expect(jsonDecode(draftOf(actions)), {
        'actions': [
          {'do': 'create', 'title': 'games?', 'items': ['Zelda Mario Party Lego Batman Stardew Valley and Kirby'], 'text': null, 'as': 'list'},
          {'do': 'create', 'title': 'Directions', 'items': [], 'text': 'We go north.', 'as': 'text'},
          {'do': 'append', 'note': 'Go', 'items': ['Zelda', 'Kirby'], 'text': null, 'as': 'tasks'},
          {'do': 'append', 'note': 'Go', 'items': [], 'text': 'More words.', 'as': 'text'},
        ],
        'note': null,
      });
    });
  });

  group('keepsWords', () {
    test('allows small joiners and filler to go, not what was said', () {
      expect(keepsWords('Zelda and Mario Party um', 'Zelda, Mario Party'), true);
      expect(keepsWords('Zelda Mario Party Kirby', 'Zelda'), false);
    });
  });

  group('mergePolished', () {
    test('lays the polished words over the draft', () {
      expect(mergePolished<Candidate>(created, split, said, notes), [
        const VoiceCreate<Candidate>(title: 'Games', items: ['Zelda', 'Mario Party', 'Lego Batman', 'Stardew Valley', 'Kirby'], tasks: false),
      ]);
    });

    test('refuses an unreadable answer, a different action count, and lost words', () {
      expect(mergePolished<Candidate>(created, 'nope', said, notes), isNull);
      expect(mergePolished<Candidate>(created, {'actions': [], 'note': null}, said, notes), isNull);
      expect(
        mergePolished<Candidate>(created, {
          'actions': [
            {'do': 'create', 'title': 'Games', 'items': ['Zelda'], 'text': null, 'as': 'list'},
          ],
          'note': null,
        }, said, notes),
        isNull,
      );
    });

    test('keeps an addition on its own note, whatever note the model names', () {
      const draft = <VoiceAction<Candidate>>[
        VoiceAppend<Candidate>(note: note, text: 'Zelda', placement: Placement(how: PlacementHow.item, task: false, many: false, items: ['Zelda'])),
      ];
      const other = Candidate(id: 'x', title: 'Other');
      final answer = {
        'actions': [
          {'do': 'append', 'note': 'Other', 'items': ['Zelda'], 'text': null, 'as': 'list'},
        ],
        'note': null,
      };
      expect(mergePolished<Candidate>(draft, answer, 'add Zelda to Other', [note, other]), draft);
    });

    test('does not turn a list into text or the reverse', () {
      const draft = <VoiceAction<Candidate>>[
        VoiceAppend<Candidate>(note: note, text: 'We go north', placement: Placement(how: PlacementHow.leave, task: false, many: false)),
      ];
      final answer = {
        'actions': [
          {'do': 'append', 'note': 'Go', 'items': ['We go north'], 'text': null, 'as': 'list'},
        ],
        'note': null,
      };
      expect(mergePolished<Candidate>(draft, answer, 'add we go north to go', notes), draft);
    });
  });

  group('polishActions', () {
    test('keeps the draft, and says why, when the model cannot help', () async {
      final trace = _Trace();
      expect(identical(await polishActions<Candidate>(created, said, notes, unavailable, trace), created), true);
      expect(trace.lines, contains(predicate<String>((line) => line.contains('polish unavailable: no model'))));
    });

    test('keeps the draft when the step throws', () async {
      final trace = _Trace();
      Future<StepResult> boom(String s, String? k, String t, List<String> ti, [String? d]) async => throw Exception('boom');
      expect(identical(await polishActions<Candidate>(created, said, notes, boom, trace), created), true);
      expect(trace.lines, contains(predicate<String>((line) => line.contains('polish failed: boom'))));
    });

    test('asks the model once, with the recording and the draft', () async {
      final calls = <List<Object?>>[];
      Future<StepResult> step(String s, String? k, String t, List<String> ti, [String? d]) async {
        calls.add([s, k, t, ti, d]);
        return StepAnswer(answer: split, raw: jsonEncode(split), model: 'test');
      }

      final out = await polishActions<Candidate>(created, said, notes, step, _Trace());
      expect(calls, [['polish', null, said, <String>[], draftOf(created)]]);
      expect(out, [const VoiceCreate<Candidate>(title: 'Games', items: ['Zelda', 'Mario Party', 'Lego Batman', 'Stardew Valley', 'Kirby'], tasks: false)]);
    });

    test('asks nothing for no actions', () async {
      var asked = false;
      Future<StepResult> step(String s, String? k, String t, List<String> ti, [String? d]) async {
        asked = true;
        return const StepUnavailable(reason: 'x');
      }

      await polishActions<Candidate>(const [], said, notes, step, _Trace());
      expect(asked, false);
    });
  });
}
