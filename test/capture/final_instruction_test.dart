import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/final_instruction.dart';
import 'package:ghost_md/capture/list_append.dart' show placeWords;
import 'package:ghost_md/capture/offers.dart' show placingOf;
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/capture/voice_log.dart';
import 'package:ghost_md/capture/voice_plan.dart';

import 'support/shapes.dart';

/// The reader at Done (lib/capture/final_instruction.dart), case for case with the web's
/// `capture/finalInstruction.test.ts` as the voice work after 1.6 left it, and with the cases the Flutter port of the
/// page added after it (a board turned down, a book never written into, House TODOs). Where the reader changed on
/// purpose, the case says so: the model is asked in two steps, and its words must be words the person said.

typedef Named = TakeCandidate<TakeNote>;

Named named(String id, String title, String body) => TakeCandidate(id: id, title: title, note: TakeNote(id: id, body: body));

final notes = [
  named('go', 'Go', '# Go\n'),
  named('todo', 'To-Do', 'To-Do'),
  named('movies', 'Movies', 'Movies\n\n- Jaws\n'),
  named('groceries', 'Groceries', 'Groceries\n\n- Eggs\n'),
];

/// The web's `vi.fn<VoiceStep>`: a model that answers the sort with [sort], the plan with [plan] and the polish with
/// [polish]; unavailable when not given. [calls] are what it was asked, as `[stage, kind, transcript, titles, draft]`.
class Model {
  Model({this.sort, this.plan, this.polish});

  final String? sort;
  final Object? plan;
  final Object? polish;
  final List<List<Object?>> calls = [];

  Future<StepResult> call(String stage, String? kind, String transcript, List<String> titles, [String? draft]) async {
    calls.add([stage, kind, transcript, titles, draft]);
    final Object? value = switch (stage) {
      'sort' => sort == null ? null : {'kind': sort},
      'polish' => polish,
      _ => plan,
    };
    return value == null ? const StepUnavailable(reason: 'no model') : StepAnswer(answer: value, raw: jsonEncode(value), model: 'test');
  }

  /// The sort and plan calls: the rules' own offers make none, only the polish.
  List<List<Object?>> get asked => [
    for (final call in calls)
      if (call[0] != 'polish') call,
  ];
}

Model none() => Model();

Map<String, Object?> append(String note, List<String> items, [String as = 'list']) => {'do': 'append', 'note': note, 'items': items, 'text': null, 'as': as};

/// The web's literal trace: lines, and the decision.
class LineTrace implements VoiceTrace {
  final List<String> lines = [];
  String decided = '';

  @override
  int get at => 1;

  @override
  void step(String line) => lines.add(line);

  @override
  void decide(String outcome) => decided = outcome;
}

const unsupportedReason = 'That command is not supported from a voice capture. Nothing changed.';

void main() {
  group('the rules: instant for the phrasings they know', () {
    const places = ['Parkersburg, West Virginia', 'Marietta, Ohio', 'Balitmore, Maryland', 'Detroit, Michigan'];

    for (final words in [
      'add to my note labeled go a list with parkersburg west virginia marietta ohio balitmore maryland and detroit michigan',
      'Add to my note labeled Go, a list with Parkersburg, West Virginia, Marietta, Ohio, Balitmore, Maryland and Detroit, Michigan.',
      'Hey Ghost, add to my note labeled Go a list with Parkersburg West Virginia, Marietta Ohio, Balitmore Maryland and Detroit Michigan.',
      'Okay, um, add to my note called “Go” a list of Parkersburg West Virginia Marietta Ohio Balitmore Maryland and Detroit Michigan',
    ]) {
      test('offers the list for Go without the model: $words', () async {
        final step = none();
        final read = await classifyFinalTranscript(words, notes, step.call);
        expect(
          read,
          matchObject({
            'kind': 'offer',
            'conversational': false,
            'actions': [
              {'do': 'append', 'note': {'id': 'go'}, 'placement': {'how': 'item', 'items': places}},
            ],
          }),
        );
        expect(step.asked, isEmpty);
        if (read is! FinalInstructionOffer<Named>) throw StateError('no offer');
        final action = read.actions.first;
        if (action is! VoiceAppend<Named>) throw StateError('no append');
        expect(placeWords('# Go\n', action.text, placingOf(action.placement)).body, '# Go\n\n${places.map((place) => '- $place').join('\n')}\n');
      });
    }

    test('reads a to-do list as tasks', () async {
      expect(
        await classifyFinalTranscript('add to my note labeled Go a to-do list with pack sunscreen, book hotel and fill the tank', notes, none().call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'placement': {'how': 'item', 'task': true, 'items': ['pack sunscreen', 'book hotel', 'fill the tank']}},
          ],
        }),
      );
    });

    test('makes a titled list with its items', () async {
      expect(
        await classifyFinalTranscript('make a new list called comic books and add to the list Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern.', notes, none().call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'comic books', 'items': ['Spider-Man', 'Batman', 'Superman', 'the Fantastic Four', 'the Green Lantern']},
          ],
        }),
      );
    });

    for (final words in [
      'Make a new list called comic books, and add Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern to it.',
      'Create a new list called comic books with Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern.',
      'Okay, make a new list called comic books. Add these: Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern.',
    ]) {
      test('offers one new list titled comic books with its items: $words', () async {
        final step = none();
        expect(
          await classifyFinalTranscript(words, notes, step.call),
          matchObject({
            'kind': 'offer',
            'actions': [
              {'do': 'create', 'title': 'comic books', 'items': ['Spider-Man', 'Batman', 'Superman', 'the Fantastic Four', 'the Green Lantern']},
            ],
          }),
        );
        expect(step.asked, isEmpty);
      });
    }

    test('keeps a title that only contains “with”, and a list said with no items', () async {
      expect(
        await classifyFinalTranscript('make a new list called books with pictures', notes, none().call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'books with pictures', 'items': <String>[]},
          ],
        }),
      );
      expect(
        await classifyFinalTranscript('make a new list called comic books', notes, none().call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'comic books', 'items': <String>[]},
          ],
        }),
      );
    });

    test('fixes the labeled Go regression and excludes command words from the payload', () async {
      expect(
        await classifyFinalTranscript('add to the note labeled Go pack sunscreen', notes, none().call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'append', 'note': {'id': 'go'}, 'text': 'pack sunscreen'},
          ],
        }),
      );
    });

    test('reads a multi-segment utterance once, after it is complete', () async {
      final step = none();
      expect(
        await classifyFinalTranscript(['add to the note', 'labeled Go pack sunscreen'].join(' '), notes, step.call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'text': 'pack sunscreen'},
          ],
        }),
      );
      expect(step.asked, isEmpty);
    });

    test('does not take “list?” after the note’s name, or an echo at the end, for items', () async {
      expect(
        await classifyFinalTranscript('Can you add to my groceries list? Cauliflower, carrots and bread.', notes, none().call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'append', 'note': {'id': 'groceries'}, 'placement': {'items': ['Cauliflower', 'carrots', 'bread']}},
          ],
        }),
      );
      expect(
        await classifyFinalTranscript('Add to Go list? Detroit, Michigan and Marietta, Ohio. Go. Go.', notes, none().call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'append', 'note': {'id': 'go'}, 'placement': {'items': ['Detroit, Michigan', 'Marietta, Ohio']}},
          ],
        }),
      );
    });

    test('finds a request inside talk', () async {
      expect(
        await classifyFinalTranscript('So I was at the store earlier and it was packed. Anyway, can you put oat milk and bread on the groceries list?', notes, none().call),
        matchObject({
          'kind': 'offer',
          'conversational': true,
          'actions': [
            {'do': 'append', 'note': {'id': 'groceries'}, 'placement': {'items': ['oat milk', 'bread']}},
          ],
        }),
      );
    });

    group('lists the rules left as plain words', () {
      final movies = [named('movies', 'Movies', 'Movies\n\n- Jaws\n- Alien\n')];

      test('splits several short things added to a list note by the rules', () async {
        expect(
          await classifyFinalTranscript('add to Movies the Matrix, Heat and Back to the Future', movies, none().call),
          matchObject({
            'kind': 'offer',
            'actions': [
              {'placement': {'how': 'item', 'items': ['the Matrix', 'Heat', 'Back to the Future']}},
            ],
          }),
        );
      });

      test('leaves a sentence a sentence', () async {
        expect(
          await classifyFinalTranscript('add to Movies we should watch these on Friday, after dinner, with Sam and the kids if everyone is free', movies, none().call),
          matchObject({
            'kind': 'offer',
            'actions': [
              {'placement': {'how': 'leave'}},
            ],
          }),
        );
      });
    });
  });

  group('the model: sort, then plan', () {
    test('asks the model when the rules do not know the phrasing, and takes its items as a real list', () async {
      final step = Model(
        sort: 'new',
        plan: {
          'actions': [
            {'do': 'create', 'title': 'Comic Books', 'items': ['Spider-Man', 'Batman', 'The Fantastic Four'], 'as': 'list'},
          ],
          'note': null,
        },
      );
      const said = 'Okay so I was reading last night and honestly I could use something to keep track of comic books, spider man batman the fantastic four';
      expect(
        await classifyFinalTranscript(said, notes, step.call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'Comic Books', 'items': ['Spider-Man', 'Batman', 'The Fantastic Four']},
          ],
        }),
      );
      expect(step.calls[0].sublist(0, 4), ['sort', null, said, ['Go', 'To-Do', 'Movies', 'Groceries']]);
      expect(step.calls[1].sublist(0, 4), ['plan', 'new', said, ['Go', 'To-Do', 'Movies', 'Groceries']]);
    });

    test('carries several changes and keeps the rest as a note', () async {
      final step = Model(
        sort: 'mixed',
        plan: {
          'actions': [
            append('Movies', ['Heat', 'Alien']),
            append('Groceries', ['coffee']),
          ],
          'note': 'Meeting went long today. Sam wants the report by Friday.',
        },
      );
      const said = 'Meeting went long today, Sam wants the report by Friday. Oh and throw Heat and Alien in movies, and coffee in groceries.';
      expect(
        await classifyFinalTranscript(said, notes, step.call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'append', 'note': {'id': 'movies'}, 'placement': {'how': 'item', 'items': ['Heat', 'Alien']}},
            {'do': 'append', 'note': {'id': 'groceries'}, 'placement': {'items': ['coffee']}},
          ],
          'note': 'Meeting went long today. Sam wants the report by Friday.',
        }),
      );
    });

    test('drops what was never said, and a note that does not exist', () async {
      final step = Model(
        sort: 'add',
        plan: {
          'actions': [
            append('Movies', ['Heat', 'Superman III']),
            append('Camping', ['tent']),
          ],
          'note': null,
        },
      );
      final read = await classifyFinalTranscript('I watched stuff, go ahead and throw Heat into movies and a tent on camping', notes, step.call);
      expect(
        read,
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'append', 'note': {'id': 'movies'}, 'placement': {'items': ['Heat']}},
          ],
        }),
      );
      expect((read as FinalInstructionOffer<Named>).actions, hasLength(1));
    });

    test('leaves dictation as a note when the model sorts it as one', () async {
      final step = Model(sort: 'note');
      expect(await classifyFinalTranscript('I need to make dinner and then maybe start on the photo album.', notes, step.call), matchObject({'kind': 'ordinary', 'notice': null}));
      expect(step.calls, hasLength(1));
    });

    test('spends no model time on dictation with no request words', () async {
      final step = Model(sort: 'add');
      expect(await classifyFinalTranscript('It was a long day and the weather was great.', notes, step.call), matchObject({'kind': 'ordinary', 'notice': null}));
      expect(step.calls, isEmpty);
    });

    test('never loses a conversational recording: no model, or nothing usable, keeps it as a note', () async {
      expect(await classifyFinalTranscript('So yeah, maybe throw something on a list somewhere.', notes, none().call), matchObject({'kind': 'ordinary'}));
      final empty = Model(
        sort: 'add',
        plan: {
          'actions': [
            append('Camping', ['tent']),
          ],
          'note': null,
        },
      );
      expect(
        await classifyFinalTranscript('Before I forget, can you add a tent to the camping list?', notes, empty.call),
        matchObject({'kind': 'ordinary', 'notice': matches(RegExp('Saved this recording as a note'))}),
      );
    });

    test('says so when the model could not be reached, even for plain talk', () async {
      expect(
        await classifyFinalTranscript('So yeah, maybe throw something on a list somewhere.', notes, none().call),
        matchObject({'kind': 'ordinary', 'notice': matches(RegExp(r'on-device model was unavailable \(no model\).*saved this recording as a note'))}),
      );
    });

    test('rejects a command the recording began with when its note does not exist', () async {
      expect(await classifyFinalTranscript('add to the note labeled Missing buy milk', notes, none().call), matchObject({'kind': 'rejected'}));
    });

    test('rejects an ambiguous note', () async {
      expect(await classifyFinalTranscript('add to Go buy milk', [...notes, named('go-2', 'GO', 'GO')], none().call), matchObject({'kind': 'rejected'}));
    });

    test('keeps reported speech as a note', () async {
      expect(
        await classifyFinalTranscript('I told Sam, “add to the note labeled Go pack sunscreen,” but I have not done it.', notes, Model(sort: 'note').call),
        matchObject({'kind': 'ordinary'}),
      );
      expect(
        await classifyFinalTranscript('Okay so I told Sam to add to my note labeled Go a list', notes, Model(sort: 'note').call),
        matchObject({'kind': 'ordinary'}),
      );
    });

    test('keeps ordinary speech about adding as a note', () async {
      expect(
        await classifyFinalTranscript('My iPhone commentary: the new camera is excellent and I want to add more tomorrow.', notes, Model(sort: 'note').call),
        matchObject({'kind': 'ordinary', 'notice': null}),
      );
    });

    test('falls back visibly to ordinary content if the model is unavailable', () async {
      final step = none();
      expect(
        await classifyFinalTranscript('add a thought about tomorrow somewhere unusual', notes, step.call),
        matchObject({'kind': 'ordinary', 'notice': matches(RegExp('unavailable'))}),
      );
      expect(step.calls, hasLength(1));
    });

    test('refuses destructive requests without asking the model to plan, and keeps the recording', () async {
      var calls = 0;
      Future<StepResult> refuse(String stage, String? kind, String transcript, List<String> titles, [String? draft]) async {
        calls += 1;
        return const StepRefused(reason: 'Deleting notes by voice is not supported.');
      }

      expect(
        await classifyFinalTranscript('delete everything on my groceries list', notes, refuse),
        matchObject({'kind': 'ordinary', 'notice': matches(RegExp(r'not supported\. Saved this recording as a note'))}),
      );
      expect(calls, 1);
      calls = 0;
      expect(await classifyFinalTranscript('add then delete everything', notes, refuse), matchObject({'kind': 'rejected'}));
      expect(calls, 1);
    });

    test('asks the model before rejecting a name the rules could not match', () async {
      final step = Model(
        sort: 'add',
        plan: {
          'actions': [
            append('Go', ['Parkersburg', 'Detroit']),
          ],
          'note': null,
        },
      );
      expect(
        await classifyFinalTranscript('add to that one I call go the places Parkersburg and Detroit', notes, step.call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'note': {'id': 'go'}, 'placement': {'how': 'item', 'items': ['Parkersburg', 'Detroit']}},
          ],
        }),
      );
      expect(step.asked, hasLength(2));
    });

    test('still fails closed when neither the rules nor the model find the note', () async {
      expect(await classifyFinalTranscript('add to my note labeled Nowhere a list with milk', notes, none().call), matchObject({'kind': 'rejected'}));
      final wrong = Model(
        sort: 'add',
        plan: {
          'actions': [
            append('Nowhere', ['milk']),
          ],
          'note': null,
        },
      );
      expect(await classifyFinalTranscript('add to my note labeled Nowhere a list with milk', notes, wrong.call), matchObject({'kind': 'rejected'}));
    });

    test('keeps only the words the person said: a state the model added is not taken on trust', () async {
      // The one-step reader took the model's states on trust ("Parkersburg" became "Parkersburg, West Virginia"); the
      // plan step's every item must be words that were said, so the whole addition goes and nothing is written.
      final step = Model(
        sort: 'add',
        plan: {
          'actions': [
            append('Go', ['Parkersburg, West Virginia', 'Detroit, Michigan']),
          ],
          'note': null,
        },
      );
      expect(await classifyFinalTranscript('add to that one I call go the places Parkersburg and Detroit', notes, step.call), matchObject({'kind': 'rejected'}));
    });
  });

  group('the voice log', () {
    test('writes each step and the decision', () async {
      final trace = LineTrace();
      await classifyFinalTranscript(
        'go ahead and throw Heat into movies',
        notes,
        Model(
          sort: 'add',
          plan: {
            'actions': [
              append('Movies', ['Heat']),
            ],
            'note': null,
          },
        ).call,
        trace,
      );
      expect(trace.lines.join('\n'), matches(RegExp(r'sort \(test\): \{"kind":"add"\}')));
      expect(trace.lines.join('\n'), matches(RegExp(r'plan \(test\):')));
      expect(trace.decided, matches(RegExp('offer: add to Movies')));
    });

    test('says what the engine was doing when a step fails', () async {
      final trace = LineTrace();
      await classifyFinalTranscript('go ahead and throw Heat into movies', notes, none().call, trace, () async => ['engine: not started yet; running: none']);
      expect(trace.lines.where((line) => line.startsWith('engine:')), isNotEmpty);
    });
  });

  group('the polish: the model as the last editor of what the rules read', () {
    Map<String, Object?> create(String title, List<String> items, [String? text]) => {'do': 'create', 'title': title, 'items': items, 'text': text, 'as': 'list'};
    const comics = 'make a new list called comic books and add to the list Spider-Man, Batman and the Fantastic Four.';

    test('splits a list the rules left in one item, and tidies the title', () async {
      const said = 'Can you make me a new list called games? Add to that list. Zelda. Mario Party. Lego Batman. Stardew Valley. Kirby.';
      final step = Model(
        polish: {
          'actions': [
            create('Games', ['Zelda', 'Mario Party', 'Lego Batman', 'Stardew Valley', 'Kirby']),
          ],
          'note': null,
        },
      );
      final read = await classifyFinalTranscript(said, notes, step.call);
      expect(
        read,
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'Games', 'items': ['Zelda', 'Mario Party', 'Lego Batman', 'Stardew Valley', 'Kirby']},
          ],
        }),
      );
      final polish = step.calls.firstWhere((call) => call[0] == 'polish');
      expect(polish.sublist(0, 4), ['polish', null, said, <String>[]]);
      expect(polish[4], contains('"do":"create"'));
    });

    test('keeps the rules’ draft when the model is unavailable', () async {
      expect(
        await classifyFinalTranscript(comics, notes, none().call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'comic books', 'items': ['Spider-Man', 'Batman', 'the Fantastic Four']},
          ],
        }),
      );
    });

    test('keeps the draft when the model drops what was said, and drops what it invented', () async {
      final lost = await classifyFinalTranscript(
        comics,
        notes,
        Model(
          polish: {
            'actions': [
              create('Comic Books', ['Spider-Man']),
            ],
            'note': null,
          },
        ).call,
      );
      expect(
        lost,
        matchObject({
          'actions': [
            {'items': ['Spider-Man', 'Batman', 'the Fantastic Four']},
          ],
        }),
      );
      final invented = await classifyFinalTranscript(
        comics,
        notes,
        Model(
          polish: {
            'actions': [
              create('Comic Books', ['Spider-Man', 'Batman', 'The Fantastic Four', 'Superman III']),
            ],
            'note': null,
          },
        ).call,
      );
      expect(
        invented,
        matchObject({
          'actions': [
            {'title': 'Comic Books', 'items': ['Spider-Man', 'Batman', 'The Fantastic Four']},
          ],
        }),
      );
    });

    test('keeps the draft when the model returns a different number of actions', () async {
      final twice = {
        'actions': [
          create('Comic Books', ['Spider-Man', 'Batman', 'Fantastic Four']),
          create('Batman', []),
        ],
        'note': null,
      };
      expect(
        await classifyFinalTranscript(comics, notes, Model(polish: twice).call),
        matchObject({
          'actions': [
            {'title': 'comic books'},
          ],
        }),
      );
    });

    test('cleans the words added to a note, leaving where they go as the rules had it', () async {
      const said = 'Add to the Go note. we should um check the ferry times. And book the hotel early.';
      final step = Model(
        polish: {
          'actions': [
            {'do': 'append', 'note': 'Go', 'items': <String>[], 'text': 'We should check the ferry times and book the hotel early.', 'as': 'text'},
          ],
          'note': null,
        },
      );
      expect(
        await classifyFinalTranscript(said, notes, step.call),
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'append', 'note': {'id': 'go'}, 'text': 'We should check the ferry times and book the hotel early.'},
          ],
        }),
      );
    });

    test('is written to the voice log', () async {
      final trace = LineTrace();
      await classifyFinalTranscript(
        comics,
        notes,
        Model(
          polish: {
            'actions': [
              create('Comic Books', ['Spider-Man', 'Batman', 'The Fantastic Four']),
            ],
            'note': null,
          },
        ).call,
        trace,
      );
      expect(trace.lines.join('\n'), matches(RegExp(r'polish \(test\):')));
      expect(trace.lines.join('\n'), matches(RegExp('polish: tidied')));
    });
  });

  group('one recording with several requests', () {
    final lists = [named('elements', 'Elements', '- Hydrogen'), named('posters', 'Posters', '- Jaws'), named('movies', 'Movies', '- Jaws')];

    test('adds to two lists, each with its own items', () async {
      const said = 'Can you add to the elements list? Gold. Carbon. And. . Helium. And then add to the posters list. Genes. Chroma copia. And. On air.';
      final step = none();
      final read = await classifyFinalTranscript(said, lists, step.call);
      expect(step.asked, isEmpty);
      expect(
        read,
        matchObject({
          'kind': 'offer',
          'note': null,
          'actions': [
            {'do': 'append', 'note': {'id': 'elements'}, 'placement': {'items': ['Gold', 'Carbon', 'Helium']}},
            {'do': 'append', 'note': {'id': 'posters'}, 'placement': {'items': ['Genes', 'Chroma copia', 'On air']}},
          ],
        }),
      );
    });

    test('adds to a list and makes a list from the same recording', () async {
      const said = 'Okay. Can you add to the movies list? . Captain America Brave New World. Shawn of the Dead. And can you make a new note called? Elements. And add magnesium, aluminum, titanium, copper, and tungsten.';
      final step = none();
      final read = await classifyFinalTranscript(said, lists, step.call);
      expect(step.asked, isEmpty);
      expect(
        read,
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'append', 'note': {'id': 'movies'}},
            {'do': 'create', 'title': 'Elements', 'items': ['magnesium', 'aluminum', 'titanium', 'copper', 'tungsten']},
          ],
        }),
      );
    });

    test('makes a list and then a note with its text', () async {
      const said =
          'Can you make me a new list called? Tools. And put in that list. Hammer. Screwdriver. Ratchet. And laser level. And then can you make me a new note called? Thoughts for the day. And put in thoughts for the day that I am thinking about. Starting a podcast. End';
      final read = await classifyFinalTranscript(said, lists, none().call);
      expect(
        read,
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'Tools', 'items': ['Hammer', 'Screwdriver', 'Ratchet', 'laser level']},
            {'do': 'create', 'title': 'Thoughts for the day', 'items': <String>[], 'body': matches(RegExp('Starting a podcast'))},
          ],
        }),
      );
    });
  });

  group('making a note with words in it', () {
    test('is a note, not a list, when what was said is not several short things', () async {
      final read = await classifyFinalTranscript('Can you make me a new note called directions and in that note put north-south east-west up down left-right? End', const <Named>[], none().call);
      expect(
        read,
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'directions', 'items': <String>[], 'body': 'North-south east-west up down left-right.'},
          ],
        }),
      );
    });
  });

  group('a new note whose items are said after its name', () {
    test('drops the "?" and the closing "add to list"', () async {
      final read = await classifyFinalTranscript('Can you make me a new note called shopping list and add to the list? Bread, butter, milk, eggs and peanut butter. Add to list.', const <Named>[], none().call);
      expect(
        read,
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'shopping list', 'items': ['Bread', 'butter', 'milk', 'eggs', 'peanut butter']},
          ],
        }),
      );
    });

    test('reads items said as sentences', () async {
      final read = await classifyFinalTranscript('Can you make me a new note called? Chopping list. And add to that list. Milk. Eggs. Butter. Bread. And peanut butter. Add to list.', const <Named>[], none().call);
      expect(
        read,
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'Chopping list', 'items': ['Milk', 'Eggs', 'Butter', 'Bread', 'peanut butter']},
          ],
        }),
      );
    });

    test('makes one note with the list in it, not a note named "…and in the note"', () async {
      final read = await classifyFinalTranscript(
        'Can you make me a new note called dinner steps and in the note, make a list called. Can you make the list have a prep the vegetables, cook the meat. Sauté the vegetables. Add cheese, stuffed mushrooms, baked.',
        const <Named>[],
        none().call,
      );
      expect(
        read,
        matchObject({
          'kind': 'offer',
          'actions': [
            {'do': 'create', 'title': 'dinner steps', 'items': ['a prep the vegetables', 'cook the meat', 'Sauté the vegetables', 'cheese', 'stuffed mushrooms', 'baked']},
          ],
        }),
      );
    });
  });

  // What the Flutter port of the page added after the 1.6 branch, and the reader keeps.
  group('what the reader still turns down without the model', () {
    for (final words in ['Hey Ghost, make this a board.', 'Hey Ghost, make this list a kanban board.']) {
      test('turns a board down without asking the model: $words', () async {
        final step = Model(
          sort: 'add',
          plan: {
            'actions': [
              append('Go', ['a board']),
            ],
            'note': null,
          },
        );
        expect(await classifyFinalTranscript(words, notes, step.call), matchObject({'kind': 'rejected', 'reason': unsupportedReason}));
        expect(step.calls, isEmpty);
      });
    }

    group('a book is never written into', () {
      final guide = named('guide', 'Field guide', '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Birds]]\n');
      final library = [guide, ...notes];

      for (final words in [
        'Hey Ghost, new item for the field guide, Trees.',
        'Hey Ghost, add to the field guide Rivers and lakes.',
        'Hey Ghost, add Trees to the field guide.',
        'Hey Ghost, add this to the field guide.',
        'Hey Ghost, put a list item on the field guide: Trees.',
      ]) {
        test('turns the rules’ reading down: $words', () async {
          final step = none();
          expect(await classifyFinalTranscript(words, library, step.call), matchObject({'kind': 'rejected', 'reason': unsupportedReason}));
          expect(step.calls, isEmpty);
        });
      }

      test('turns the model’s reading down too', () async {
        final step = Model(
          sort: 'add',
          plan: {
            'actions': [
              append('field guide', ['rivers']),
            ],
            'note': null,
          },
        );
        final read = await classifyFinalTranscript('add a thought about rivers somewhere in that guide book of mine', library, step.call);
        expect(read, matchObject({'kind': 'rejected', 'reason': matches(RegExp('book'))}));
        expect(step.asked, hasLength(2));
      });
    });
  });

  // The sentence that came out as a new note, said into a fresh recording with House TODOs in the library. The reader
  // at Done must find the note, leave "The note is" out, and keep one thing to do as one to-do.
  group('adding to House TODOs, read from the finished recording', () {
    final house = named('house', 'House TODOs', '# House TODOs\n\n- [ ] Fix the gutter\n');
    final library = [house, named('todo', 'Todo', '# Todo'), named('tm', 'Task Management', '# Task Management')];

    List<String> placed(VoiceAppend<Named> action) => placeWords(house.note.body, action.text, placingOf(action.placement)).added;

    VoiceAppend<Named> only(FinalInstruction<Named> read) {
      if (read is! FinalInstructionOffer<Named> || read.actions.length != 1 || read.actions.first is! VoiceAppend<Named>) {
        throw StateError('expected one addition, got $read');
      }
      return read.actions.first as VoiceAppend<Named>;
    }

    for (final words in [
      "add a note to house to do's. The note is call an electrician to fix the light sockets.",
      "add a note to house to do's, the note is call an electrician to fix the light sockets.",
      'add a note to house chores, the note is call an electrician to fix the light sockets.',
      'add a note to the house list items: call an electrician to fix the light sockets.',
      'add call an electrician to fix the light sockets to house to-dos.',
      'add to house to-dos, call an electrician to fix the light sockets.',
    ]) {
      test('finds House TODOs and adds one to-do: $words', () async {
        final action = only(await classifyFinalTranscript(words, library, none().call));
        expect(action.note.id, 'house');
        expect(placed(action), ['- [ ] Call an electrician to fix the light sockets']);
      });
    }

    test('keeps a single item whole when the title says to-dos', () async {
      final action = only(await classifyFinalTranscript('Add to House TODOs: fix the gutter.', library, none().call));
      expect(action.note.id, 'house');
      expect(action.text, 'fix the gutter');
      expect(placed(action), ['- [ ] Fix the gutter']);
    });

    test('finds the model’s title as the rules would, and its words are the ones said', () async {
      final step = Model(
        sort: 'add',
        plan: {
          'actions': [
            {'do': 'append', 'note': 'house chores', 'items': <String>[], 'text': 'call an electrician to fix the light sockets', 'as': 'text'},
          ],
          'note': null,
        },
      );
      final action = only(
        await classifyFinalTranscript('add a note for the house jobs thing about the electrician and the light sockets, call an electrician to fix the light sockets', library, step.call),
      );
      expect(action.note.id, 'house');
      expect(placed(action), ['- [ ] Call an electrician to fix the light sockets']);
    });
  });

  group('the voice log itself', () {
    test('keeps each recording with its steps and what was chosen, newest first', () {
      clearVoiceLog();
      final first = traceRecording('add Heat to movies', now: 1000);
      first.step('rules: add to Movies');
      first.decide('offer: add to Movies');
      settleRecording(1000, 'confirmed');
      final second = traceRecording('it was a long day', now: 2000);
      second.decide('note');
      expect(voiceLog().map((entry) => entry.at), [2000, 1000]);
      expect(voiceLogText(), matches(RegExp(r'Said: add Heat to movies\n- \+\d+\.\ds rules: add to Movies\nResult: offer: add to Movies → confirmed')));
      clearVoiceLog();
      expect(voiceLog(), isEmpty);
    });
  });
}
