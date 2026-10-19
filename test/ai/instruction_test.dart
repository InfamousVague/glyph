import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/instruction.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/capture/final_instruction.dart' show VoiceAppend, VoiceCreate;
import 'package:ghost_md/capture/run_of.dart' as recorder;
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/capture/ui/read_instruction.dart' as screen;
import 'package:ghost_md/core/book.dart' show bookNoteBody;

/// The reader of a spoken instruction (lib/ai/instruction.dart), case for case with `src/app/ai/instruction.test.ts`.
///
/// What differs from the web's cases: a note is a [TakeCandidate] over a [TakeNote] (the web's `{ id, title, note }`
/// from `makeNote`); what was read is held by its class and fields, where vitest matched an object; and a last group,
/// of this port's own, holds the recorder's two files to this one.
typedef N = TakeCandidate<TakeNote>;

N noteOf(String id, String title, String body) => TakeCandidate(id: id, title: title, note: TakeNote(id: id, body: body));

final List<N> notes = [
  noteOf('g', 'Groceries', '# Groceries\n- milk\n'),
  noteOf('w', 'Work', '# Work\nplain words\n'),
];

/// Sentences that open with a run's words: each was a run on main, and rewrote the note it was said into.
const sentences = [
  'Fix the spelling of Kowalski on the sign before Friday',
  'Tidy up the garage before the weekend',
  'Organise a meeting with the team',
  'Continue the discussion with Sam tomorrow',
  'Summarise the call with Jo',
  'Keep going with the fence on Saturday',
];

String lowerFirst(String said) => '${said[0].toLowerCase()}${said.substring(1)}';

Future<Read<N>> read(String said, [List<N>? library]) => readInstruction<N>(said, library ?? notes);

/// `{ kind: 'words' }`, with the notice it carries or none.
Matcher wordsWith([String? notice]) => isA<ReadWords<N>>().having((r) => r.notice, 'notice', notice);
Matcher runOfKind(RunKind kind) => isA<ReadRun<N>>().having((r) => r.run, 'run', kind).having((r) => r.instruction, 'instruction', isNull);
Matcher askOf(String instruction) => isA<ReadAsk<N>>().having((r) => r.instruction, 'instruction', instruction);
Matcher placedIn(String id) => isA<ReadCommand<N>>().having((r) => r.actions, 'actions', [isA<VoiceAppend<N>>().having((a) => a.note.id, 'note', id)]);

VoiceAppend<N> theAppend(Read<N> read) => (read as ReadCommand<N>).actions.single as VoiceAppend<N>;

void main() {
  group('the words themselves', () {
    test('drops the keyword at the start and the lead-ins, and says whether the keyword was said', () {
      expect(bareWords('Hey Ghost, please fix the spelling.'), (words: 'fix the spelling', keyed: true, misheard: false));
      expect(bareWords('okay um, summarise it'), (words: 'summarise it', keyed: false, misheard: false));
      expect(bareWords('I told Sam, hey Ghost, add eggs'), isNull);
    });
  });

  group('a run said in words', () {
    test('reads the phrasings that mean one kind', () {
      expect(runOf('fix the spelling'), RunKind.fix);
      expect(runOf('check my grammar'), RunKind.fix);
      expect(runOf('summarise this'), RunKind.summarize);
      expect(runOf('tidy it up'), RunKind.format);
      expect(runOf('expand on this'), RunKind.enhance);
      expect(runOf('carry on'), RunKind.continueWriting);
      expect(runOf('make this a list'), RunKind.shape);
      expect(runOf('turn it into a table'), RunKind.shape);
    });

    test('leaves a new list by name, and anything else, to the other readers', () {
      expect(runOf('make a list called comic books'), isNull);
      expect(runOf('add eggs to groceries'), isNull);
      expect(runOf('add a heading about the budget'), isNull);
    });

    // The rules are anchored at the front, so without the keyword a run is the whole phrase and its object, and
    // nothing more (docs/DESIGN.md §136).
    test('is the whole phrase, with `whole`, so a sentence that opens with a run’s words is not the run', () {
      for (final said in ['fix the spelling', 'tidy it up', 'carry on', 'summarise it for me', 'summarize this', 'make this a list', 'tidy this up', 'flesh it out please', 'summarise that', 'summarise the note', 'summarise this note', 'tidy up everything', 'carry on now']) {
        expect(runOf(said, whole: true), isNotNull, reason: said);
      }
      for (final said in sentences) {
        expect(runOf(said, whole: true), isNull, reason: said);
        expect(runOf(said), isNotNull, reason: said);
      }
    });
  });

  group('reading an instruction', () {
    test('is a run for a run’s words, with the keyword or without', () async {
      expect(await read('hey ghost fix the spelling'), runOfKind(RunKind.fix));
      expect(await read('Make this a list'), runOfKind(RunKind.shape));
    });

    test('is a command, to be confirmed, when a note is named', () async {
      final placed = await read('add eggs to groceries');
      expect(placed.kind, 'command');
      final plan = theAppend(placed);
      expect(plan.note.id, 'g');
      expect(plan.text, 'eggs');
      final made = await read('make a new list called comic books and add Batman and Superman');
      expect(made, isA<ReadCommand<N>>().having((r) => r.actions, 'actions', [isA<VoiceCreate<N>>().having((p) => p.title, 'title', 'comic books').having((p) => p.items, 'items', ['Batman', 'Superman'])]));
    });

    test('refuses a command that named a note there is no note for after the keyword, and without it saves the words with the reason', () async {
      final keyed = await read('hey ghost, add to the camping list eggs and milk');
      expect(keyed, isA<ReadReject<N>>().having((r) => r.reason, 'reason', 'No unambiguous note matches “camping”. Nothing changed.'));
      // Without the keyword, the person never said it was a command: the words are the note's, and the chip says why.
      expect(await read('add to the camping list eggs and milk'), wordsWith('No note called “camping”, so the words are saved as a note.'));
      // The name as said, up to its comma, where the rules at Done carried the words after it too.
      expect(await read('Add to shopping, oat milk.'), wordsWith('No note called “shopping”, so the words are saved as a note.'));
      expect(await read('Hey Ghost, add to shopping, oat milk.'), isA<ReadReject<N>>());
      // A name the rules cannot read at all is an ask after the keyword, not a refusal.
      expect(await read('hey ghost, add eggs to the camping list'), askOf('add eggs to the camping list'));
    });

    test('reads a run without the keyword only as the whole phrase; with it, a sentence that opens with one is the run', () async {
      for (final said in sentences) {
        expect(await read('$said.'), wordsWith(), reason: said);
        expect((await read('Hey Ghost, ${lowerFirst(said)}.')).kind, 'run', reason: said);
      }
      for (final said in ['Fix the spelling.', 'Tidy it up.', 'Carry on.', 'Summarise it for me.']) {
        expect((await read(said)).kind, 'run', reason: said);
      }
    });

    test('is an ask about the note only after the keyword; without it, the words are the note’s', () async {
      expect(await read('hey ghost, add a heading about the budget'), askOf('add a heading about the budget'));
      expect(await read('hey ghost, shorten the second paragraph'), askOf('shorten the second paragraph'));
      expect(await read('shorten the second paragraph'), isA<ReadWords<N>>());
      expect(await read('we should shorten the second paragraph'), wordsWith());
    });
  });

  // What the live reader's gate kept as words, read again at Done from a transcript with no keyword (docs/DESIGN.md
  // §136): words here too, never a card whose Cancel lets the recording go. The keyword still makes each a card.
  group('the reader at Done, without the keyword', () {
    final library = [
      ...notes,
      noteOf('h', 'House TODOs', '# House TODOs\n\n- [ ] Fix the gutter\n'),
      noteOf('b', 'Bowl', '# Bowl\n\nBlue.\n'),
      noteOf('c', 'Car insurance', '# Car insurance\n\n- Renew\n'),
      noteOf('t', 'Weekend trip', '# Weekend trip\n\nThe cabin.\n'),
      noteOf('p', 'Porch light', '# Porch light\n\n- Bulb\n'),
      noteOf('o', 'Post', '# Post\n\nLetters.\n'),
      noteOf('m', 'Team', '# Team\n\n- Kevin\n'),
      noteOf('go', 'Go', '# Go\n'),
    ];

    for (final said in [
      'Add call the plumber to work.',
      'Add the flour to the bowl. Then stir it for a minute.',
      'Put this in the car, then drive.',
      'Put the spare key under the mat on the porch. Then lock up.',
      'Add a note to the weekend, book the ferry.',
      'Put this in the weekend trip, book the ferry.',
      'Put the parcel in the post.',
      'Add Kevin to the team.',
      'Put the washing in the house.',
    ]) {
      test('keeps what the live reader kept as words: $said', () async {
        expect(await read(said, library), wordsWith());
        expect((await read('Hey Ghost, ${lowerFirst(said)}', library)).kind, 'command', reason: said);
      });
    }

    test('still offers what the live reader carries out, a note labelled by name, and a new list', () async {
      expect(await read('Add oat milk to groceries.', library), placedIn('g'));
      expect(await read('Add call Sam to House TODOs.', library), placedIn('h'));
      // "Go" starts with a verb, so the live reader has no bare reading of it to turn down: the card is the second
      // chance.
      expect(await read('add to the note labeled Go pack sunscreen', library), placedIn('go'));
      expect(await read('Make a list called Comic books.', library), isA<ReadCommand<N>>().having((r) => r.actions, 'actions', [isA<VoiceCreate<N>>().having((p) => p.title, 'title', 'Comic books')]));
    });
  });

  group('the keyword as Whisper hears it', () {
    final house = [...notes, noteOf('h', 'House TODOs', '# House TODOs\n\n- [ ] Fix the gutter\n')];

    test('takes filler before the keyword, and the mishearings of it when a command follows', () {
      expect(bareWords('Um, hey Ghost, add call Sam to house to-dos.'), (words: 'add call Sam to house to-dos', keyed: true, misheard: false));
      expect(bareWords("Hey, like add a note to house to do's"), (words: "add a note to house to do's", keyed: false, misheard: true));
      expect(bareWords('Hey goes add a note to house to-dos'), (words: 'add a note to house to-dos', keyed: false, misheard: true));
      // Not followed by a command, they are words: "Hey, like, the weather" is a note.
      for (final said in ['Hey, like, the weather is lovely', 'Hey goes the dog']) {
        final bare = bareWords(said)!;
        expect((bare.keyed, bare.misheard), (false, false), reason: said);
      }
      // Without the keyword, what a sentence starts with is its own: "And carry on tomorrow" is no run.
      expect(bareWords('And continue the story tomorrow.'), (words: 'And continue the story tomorrow', keyed: false, misheard: false));
    });

    for (final said in [
      'Okay, like, make sure the door is locked.',
      'Hey, go add some colour to the living room walls, it would look nice.',
      'Hey, like, make sure the door is locked.',
      'Hey, like, fix the spelling on the sign.',
      'Hey goes, add a bit more salt next time.',
      // The gate is the bare gate, shared with the live reader: a note called Sam with a bullet is no evidence.
      'Hey, like, put this in Sam, the deposit is due.',
      // A book is never written into by voice, so a mishearing before its name is words, never a card.
      'Hey, like, add a note to field guide, call Sam.',
    ]) {
      test('keeps how people talk as words, never an ask or a run: $said', () async {
        final sam = [...house, noteOf('s', 'Sam', '# Sam\n\n- Owes me a tenner\n'), noteOf('f', 'Field guide', bookNoteBody('Field guide', ['Trees']))];
        expect(await read(said, sam), isA<ReadWords<N>>());
      });
    }

    for (final said in [
      "Hey, like add a note to house to do's, the note is call an electrician to fix the light sockets.",
      'Hey goes add a note to house to-dos. Call an electrician to fix the light sockets.',
      'Okay, hey Ghost, I want to add call an electrician to fix the light sockets to house to-dos.',
      'Hey Ghost, like, add a note to house chores. The note is call an electrician to fix the light sockets.',
    ]) {
      test('is Matt’s command on House TODOs, however it opened: $said', () async {
        final got = await read(said, house);
        expect(got, placedIn('h'));
        expect(theAppend(got).text, matches(RegExp(r'^call an electrician to fix the light sockets$', caseSensitive: false)));
      });
    }
  });

  // Not on the page: the recorder keeps a run's kind as the web's word, through two files that ask this one.
  group('the recorder’s own two files', () {
    test('say the same run, as the web’s word for it', () {
      for (final said in ['fix the spelling', 'summarise this', 'tidy it up', 'expand on this', 'carry on', 'make this a list', 'add eggs to groceries', ...sentences]) {
        expect(recorder.runOf(said), runOf(said)?.id, reason: said);
        expect(recorder.runOf(said, whole: true), runOf(said, whole: true)?.id, reason: said);
      }
      expect(recorder.runOf('carry on'), 'continue');
    });

    test('read an instruction as this file does, class for class', () async {
      for (final said in ['hey ghost fix the spelling', 'add eggs to groceries', 'hey ghost, add to the camping list eggs and milk', 'add to the camping list eggs and milk', 'hey ghost, shorten the second paragraph', 'we should shorten the second paragraph']) {
        final ours = await read(said);
        final theirs = await screen.readInstruction<N>(said, notes);
        expect(theirs.kind, ours.kind, reason: said);
        switch ((ours, theirs)) {
          case (ReadRun<N>(:final run), screen.ReadRun<N>(run: final word)):
            expect(word, run.id);
          case (ReadCommand<N>(:final actions, :final note), screen.ReadCommand<N>(actions: final same, note: final sameNote)):
            expect(same, actions);
            expect(sameNote, note);
          case (ReadReject<N>(:final reason), screen.ReadReject<N>(reason: final same)):
            expect(same, reason);
          case (ReadAsk<N>(:final instruction), screen.ReadAsk<N>(instruction: final same)):
            expect(same, instruction);
          case (ReadWords<N>(:final notice), screen.ReadWords<N>(notice: final same)):
            expect(same, notice);
          default:
            fail('$said: ${ours.runtimeType} against ${theirs.runtimeType}');
        }
      }
      expect(identical(screen.bareWords, bareWords), isTrue);
    });
  });
}
