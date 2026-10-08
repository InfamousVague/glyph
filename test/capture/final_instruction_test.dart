import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/final_instruction.dart';
import 'package:ghost_md/capture/instruction_intent.dart';
import 'package:ghost_md/capture/list_append.dart' show placeWords;
import 'package:ghost_md/capture/offers.dart' show placingOf;
import 'package:ghost_md/capture/take_types.dart';

import 'support/shapes.dart';

/// The reader at Done (lib/capture/final_instruction.dart), case for case with the web's
/// `capture/finalInstruction.test.ts`.

typedef Named = TakeCandidate<TakeNote>;

Named named(String id, String title, String body) => TakeCandidate(id: id, title: title, note: TakeNote(id: id, body: body));

final notes = [named('go', 'Go!', 'Go!'), named('todo', 'To-Do', 'To-Do')];

InferenceRun inferred(Map<String, Object?> value) => InferenceRun(done: Future.value(validateInference(value)!), cancel: () {});

/// The web's `vi.fn(() => inferred(value))`: an inference that answers [value], and counts how often it was asked.
class Asked {
  Asked(this.value);

  final Map<String, Object?> value;
  int calls = 0;

  InferenceRun call(String words) {
    calls += 1;
    return inferred(value);
  }
}

Asked never() => Asked({'status': 'unavailable', 'reason': 'not called'});

Map<String, Object?> append(String target, String content, String? placement) => {
  'status': 'intent',
  'model': 'local',
  'intent': {'action': 'append', 'target': target, 'content': content, 'placement': placement},
};

const unsupportedReason = 'That command is not supported from a voice capture. Nothing changed.';

void main() {
  group('final transcript instruction scan', () {
    test('fixes Kevin’s labeled Go regression and excludes command words from payload', () async {
      expect(
        await classifyFinalTranscript('add to the note labeled Go pack sunscreen', notes),
        matchObject({'kind': 'offer', 'plan': {'kind': 'place', 'note': {'id': 'go'}, 'text': 'pack sunscreen'}}),
      );
    });

    test('classifies a multi-segment utterance once after it is complete', () async {
      var called = 0;
      InferenceRun run(String words) {
        called += 1;
        return inferred(append('Go', words, null));
      }

      expect(
        await classifyFinalTranscript(['add to the note', 'labeled Go pack sunscreen'].join(' '), notes, run),
        matchObject({'kind': 'offer', 'plan': {'kind': 'place', 'text': 'pack sunscreen'}}),
      );
      expect(called, 0);
    });

    for (final words in [
      'My iPhone commentary: the new camera is excellent and I want to add more tomorrow.',
      'I told Sam, “add to the note labeled Go pack sunscreen,” but I have not done it.',
    ]) {
      test('keeps ordinary and reported speech ordinary: $words', () async {
        expect(await classifyFinalTranscript(words, notes), const FinalInstructionOrdinary<Named>(notice: null));
      });
    }

    test('rejects missing and ambiguous targets without an action', () async {
      expect(await classifyFinalTranscript('add to the note labeled Missing buy milk', notes), matchObject({'kind': 'rejected'}));
      expect(await classifyFinalTranscript('add to Go buy milk', [...notes, named('go-2', 'GO', 'GO')]), matchObject({'kind': 'rejected'}));
    });

    test('falls back visibly to ordinary content if inference is unavailable', () async {
      final run = Asked({'status': 'unavailable', 'reason': 'model unavailable'});
      expect(
        await classifyFinalTranscript('add a thought about tomorrow somewhere unusual', notes, run.call),
        matchObject({'kind': 'ordinary', 'notice': matches(RegExp('unavailable'))}),
      );
      expect(run.calls, 1);
    });

    test('fails destructive and compound inference closed', () async {
      InferenceRun run(String _) => inferred({
        'status': 'intent',
        'model': 'local',
        'intent': {'action': 'none', 'reason': 'destructive'},
      });
      expect(await classifyFinalTranscript('add then delete everything', notes, run), matchObject({'kind': 'rejected'}));
    });

    group('“add to my note labeled Go a list with…”', () {
      final go = [named('go', 'Go', '# Go\n'), ...notes.sublist(1)];
      const places = ['Parkersburg, West Virginia', 'Marietta, Ohio', 'Balitmore, Maryland', 'Detroit, Michigan'];
      final never = Asked({'status': 'unavailable', 'reason': 'not called'});

      for (final words in [
        'add to my note labeled go a list with parkersburg west virginia marietta ohio balitmore maryland and detroit michigan',
        'Add to my note labeled Go, a list with Parkersburg, West Virginia, Marietta, Ohio, Balitmore, Maryland and Detroit, Michigan.',
        'Hey Ghost, add to my note labeled Go a list with Parkersburg West Virginia, Marietta Ohio, Balitmore Maryland and Detroit Michigan.',
        'Okay, um, add to my note called “Go” a list of Parkersburg West Virginia Marietta Ohio Balitmore Maryland and Detroit Michigan',
      ]) {
        test('offers the list for Go, one item per place: $words', () async {
          final decision = await classifyFinalTranscript(words, go, never.call);
          expect(decision, matchObject({'kind': 'offer', 'plan': {'kind': 'place', 'note': {'id': 'go'}, 'how': 'item', 'many': true, 'items': places}}));
          expect(never.calls, 0);
          if (decision is! FinalInstructionOffer<Named>) throw StateError('no offer');
          final plan = decision.plan;
          if (plan is! PlanPlace<Named>) throw StateError('no offer');
          expect(placeWords('# Go\n', plan.text, placingOf(plan.placement)).body, '# Go\n\n${places.map((place) => '- $place').join('\n')}\n');
        });
      }

      test('reads a to-do list as tasks', () async {
        expect(
          await classifyFinalTranscript('add to my note labeled Go a to-do list with pack sunscreen, book hotel and fill the tank', go, never.call),
          matchObject({'kind': 'offer', 'plan': {'how': 'item', 'task': true, 'items': ['pack sunscreen', 'book hotel', 'fill the tank']}}),
        );
      });

      test('asks the on-device model before rejecting a name the rules could not match', () async {
        final run = Asked(append('Go', 'Parkersburg, West Virginia; Detroit, Michigan', 'list'));
        expect(
          await classifyFinalTranscript('add to that one I call go the places Parkersburg and Detroit', go, run.call),
          matchObject({'kind': 'offer', 'plan': {'note': {'id': 'go'}, 'how': 'item', 'items': ['Parkersburg, West Virginia', 'Detroit, Michigan']}}),
        );
        expect(run.calls, 1);
      });

      test('still fails closed when neither the rules nor the model find the note', () async {
        final unavailable = Asked({'status': 'unavailable', 'reason': 'no model'});
        expect(await classifyFinalTranscript('add to my note labeled Nowhere a list with milk', go, unavailable.call), matchObject({'kind': 'rejected'}));
        final wrong = Asked(append('Nowhere', 'milk', 'list'));
        expect(await classifyFinalTranscript('add to my note labeled Nowhere a list with milk', go, wrong.call), matchObject({'kind': 'rejected'}));
      });

      test('keeps a command said inside a sentence as words', () async {
        expect(
          await classifyFinalTranscript('Okay so I told Sam to add to my note labeled Go a list', go, never.call),
          const FinalInstructionOrdinary<Named>(notice: null),
        );
      });
    });

    group('“make a new list called … and add …”', () {
      final never = Asked({'status': 'unavailable', 'reason': 'not called'});
      const heroes = ['Spider-Man', 'Batman', 'Superman', 'the Fantastic Four', 'the Green Lantern'];

      for (final words in [
        'make a new list called comic books and add to the list Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern.',
        'Make a new list called comic books, and add Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern to it.',
        'Create a new list called comic books with Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern.',
        'Okay, make a new list called comic books. Add these: Spider-Man, Batman, Superman, the Fantastic Four and the Green Lantern.',
      ]) {
        test('offers one new list titled Comic books with its items: $words', () async {
          expect(
            await classifyFinalTranscript(words, notes, never.call),
            const FinalInstructionOffer<Named>(plan: PlanCreateList(title: 'comic books', items: heroes)),
          );
          expect(never.calls, 0);
        });
      }

      test('keeps a title that only contains “with”, and a list said with no items', () async {
        expect(
          await classifyFinalTranscript('make a new list called books with pictures', notes, never.call),
          const FinalInstructionOffer<Named>(plan: PlanCreateList(title: 'books with pictures')),
        );
        expect(
          await classifyFinalTranscript('make a new list called comic books', notes, never.call),
          const FinalInstructionOffer<Named>(plan: PlanCreateList(title: 'comic books')),
        );
      });
    });

    for (final words in ['Hey Ghost, make this a board.', 'Hey Ghost, make this list a kanban board.']) {
      test('turns a board down without asking the model: $words', () async {
        final run = Asked(append('Go', 'a board', null));
        expect(await classifyFinalTranscript(words, notes, run.call), const FinalInstructionRejected<Named>(reason: unsupportedReason));
        expect(run.calls, 0);
      });
    }

    group('a book is never written into', () {
      final guide = named('guide', 'Field guide', '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Birds]]\n');
      final library = [guide, ...notes];
      const unsupported = FinalInstructionRejected<Named>(reason: unsupportedReason);

      for (final words in [
        'Hey Ghost, new item for the field guide, Trees.',
        'Hey Ghost, add to the field guide Rivers and lakes.',
        'Hey Ghost, add Trees to the field guide.',
        'Hey Ghost, add this to the field guide.',
        'Hey Ghost, put a list item on the field guide: Trees.',
      ]) {
        test('turns the rules’ reading down: $words', () async {
          final run = never();
          expect(await classifyFinalTranscript(words, library, run.call), unsupported);
          expect(run.calls, 0);
        });
      }

      test('turns the model’s reading down too', () async {
        final run = Asked(append('field guide', 'Rivers', 'notes'));
        expect(await classifyFinalTranscript('add a thought about rivers somewhere in that guide book of mine', library, run.call), unsupported);
        expect(run.calls, 1);
      });
    });

    group('lists the model or the rules left as plain words', () {
      final movies = [named('movies', 'Movies', 'Movies\n\n- Jaws\n- Alien\n')];
      const films = ['The Matrix', 'Heat', 'Back to the Future'];

      test('keeps a list when the model returns no placement', () async {
        final run = Asked(append('Movies', 'The Matrix, Heat and Back to the Future', null));
        final decision = await classifyFinalTranscript('add to that one I call movies the Matrix, Heat and Back to the Future', movies, run.call);
        expect(decision, matchObject({'kind': 'offer', 'plan': {'how': 'item', 'many': true, 'items': films}}));
        if (decision is! FinalInstructionOffer<Named>) throw StateError('no offer');
        final plan = decision.plan;
        if (plan is! PlanPlace<Named>) throw StateError('no offer');
        expect(placeWords(movies[0].note.body, plan.text, placingOf(plan.placement)).body, 'Movies\n\n- Jaws\n- Alien\n- The Matrix\n- Heat\n- Back to the Future\n');
      });

      test('keeps a list when the command says “list” even if the model says paragraph-less null and the note is empty', () async {
        final empty = [named('movies', 'Movies', 'Movies')];
        final run = Asked(append('Movies', 'The Matrix; Heat; Back to the Future', null));
        expect(
          await classifyFinalTranscript('add these to that movie list thing: the Matrix, Heat, Back to the Future', empty, run.call),
          matchObject({'kind': 'offer', 'plan': {'how': 'item', 'items': films}}),
        );
      });

      test('splits several short things added to a list note by the rules', () async {
        expect(
          await classifyFinalTranscript('add to Movies the Matrix, Heat and Back to the Future', movies, never().call),
          matchObject({'kind': 'offer', 'plan': {'how': 'item', 'items': ['the Matrix', 'Heat', 'Back to the Future']}}),
        );
      });

      test('leaves a sentence a sentence', () async {
        final decision = await classifyFinalTranscript(
          'add to Movies we should watch these on Friday, after dinner, with Sam and the kids if everyone is free',
          movies,
          never().call,
        );
        expect(decision, matchObject({'kind': 'offer', 'plan': {'how': 'leave'}}));
      });
    });
  });

  // Matt's sentence, and the ways it came out as a new note: said into a fresh recording with House TODOs in the
  // library. The reader at Done must find the note, leave "The note is" out, and keep one thing to do as one to-do.
  group('adding to House TODOs, read from the finished recording', () {
    final house = named('house', 'House TODOs', '# House TODOs\n\n- [ ] Fix the gutter\n');
    final library = [house, named('todo', 'Todo', '# Todo'), named('tm', 'Task Management', '# Task Management')];
    List<String> placed(PlanPlace<Named> plan) => placeWords(house.note.body, plan.text, placingOf(plan.placement)).added;

    for (final words in [
      "add a note to house to do's. The note is call an electrician to fix the light sockets.",
      "add a note to house to do's, the note is call an electrician to fix the light sockets.",
      'add a note to house chores, the note is call an electrician to fix the light sockets.',
      'add a note to the house list items: call an electrician to fix the light sockets.',
      'add call an electrician to fix the light sockets to house to-dos.',
      'add to house to-dos, call an electrician to fix the light sockets.',
    ]) {
      test('finds House TODOs and adds one to-do: $words', () async {
        final decision = await classifyFinalTranscript(words, library, never().call);
        if (decision is! FinalInstructionOffer<Named>) throw StateError('expected an offer, got $decision');
        final plan = decision.plan;
        if (plan is! PlanPlace<Named>) throw StateError('expected an offer, got $decision');
        expect(plan.note.id, 'house');
        expect(placed(plan), ['- [ ] Call an electrician to fix the light sockets']);
      });
    }

    test('keeps a single item whole when the title says to-dos', () async {
      final decision = await classifyFinalTranscript('Add to House TODOs: fix the gutter.', library, never().call);
      expect(decision, matchObject({'kind': 'offer', 'plan': {'note': {'id': 'house'}, 'text': 'fix the gutter'}}));
      if (decision is FinalInstructionOffer<Named>) {
        final plan = decision.plan;
        if (plan is PlanPlace<Named>) expect(placed(plan), ['- [ ] Fix the gutter']);
      }
    });

    test('finds the model’s title as the rules would, and leaves no backslash on its words', () async {
      final run = Asked(append('house chores', 'The note is call an electrician to fix the light-sockets.', null));
      final decision = await classifyFinalTranscript('add a note for the house jobs thing about the electrician and the light sockets', library, run.call);
      if (decision is! FinalInstructionOffer<Named>) throw StateError('expected an offer, got $decision');
      final plan = decision.plan;
      if (plan is! PlanPlace<Named>) throw StateError('expected an offer, got $decision');
      expect(plan.note.id, 'house');
      expect(placed(plan), [r'- [ ] Call an electrician to fix the light\-sockets']);
    });
  });
}
