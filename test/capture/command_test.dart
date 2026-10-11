import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/route.dart';
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/core/book.dart' show bookNoteBody;

import 'support/shapes.dart';

/// The keyword and the plan a command's words make (lib/capture/command.dart), case for case with the web's
/// `capture/command.test.ts`.

const notes = [
  Candidate(id: 'b', title: 'AttackFM Bugbash'),
  Candidate(id: 'h', title: 'HelloTrade'),
  Candidate(id: 'g', title: 'Ghost Notes'),
  Candidate(id: 'p', title: 'Places to Go'),
  Candidate(id: 'w', title: 'Work'),
];
Plan<Candidate>? plan(String words) => planCommand(words, notes: notes);
Candidate at(String id) => notes.firstWhere((n) => n.id == id);

/// A candidate that carries its note's body, as the web's `{ id, title, note: { body } }`.
TakeCandidate<TakeNote> withBody(String id, String title, String body) => TakeCandidate(id: id, title: title, note: TakeNote(id: id, body: body));

void main() {
  group('hearing the keyword', () {
    test('finds "hey Ghost" and splits the words around it', () {
      expect(findKeyword('Hey Ghost, add buy milk to hello trade.'), (before: '', after: 'add buy milk to hello trade.'));
      expect(findKeyword('Pick up the parcel. Hey Ghost add that to work'), (before: 'Pick up the parcel.', after: 'add that to work'));
      expect(findKeyword('Okay, glyph.'), (before: '', after: ''));
    });

    test('takes the spellings speech recognition writes for it', () {
      expect(findKeyword('Glif, new note.')?.after, 'new note.');
      expect(findKeyword('Gliff add eggs to work')?.after, 'add eggs to work');
    });

    test('takes "ghost" only after hey, hi, OK or so - a common word - and "glyph" as it always did', () {
      // A note that begins with the word is a note, not a command with nothing in it (Matt: "require hey Ghost").
      expect(findKeyword('Ghost, add buy milk to hello trade.'), isNull);
      expect(findKeyword('Ghost stories at the cabin. Bring a torch.'), isNull);
      expect(findKeyword('OK Ghost, add buy milk to hello trade.')?.after, 'add buy milk to hello trade.');
      expect(findKeyword('so ghost add eggs to the list')?.after, 'add eggs to the list');
      expect(findKeyword('Glyph, add buy milk to hello trade.')?.after, 'add buy milk to hello trade.');
      expect(findKeyword('Hey glyph, new note')?.after, 'new note');
    });

    test('knows the word as a note’s name when a preposition leads and "note" follows', () {
      // No keyword said: the phrase is words, and nothing is lost.
      expect(findKeyword('add a note to the Ghost note saying testing if this works'), isNull);
      expect(findKeyword('put that on the glyph page'), isNull);
      // Said first, it is the keyword, and the note called Glyph can still be named after it.
      expect(
        findKeyword('OK Ghost, add a note to the Ghost note saying testing if this works'),
        (before: '', after: 'add a note to the Ghost note saying testing if this works'),
      );
      // Later in the phrase, on its own, it is the keyword.
      expect(findKeyword('call the dentist. Hey Ghost, add that to the Ghost note')?.after, 'add that to the Ghost note');
    });

    test('takes the other spellings base.en wrote for it across voices', () {
      for (final heard in ['Gliv. Add eggs to work.', 'Glive, new note.', 'Glit. Add eggs to work.', 'Clith. Add a table to work.', 'Hey Bliff. Put call Sam on work.', 'Glyth, new note.']) {
        expect(findKeyword(heard), isNotNull, reason: heard);
      }
    });

    test('takes a sound-alike word at the start only when a command follows', () {
      bool reads(String words) => (plan(words)?.kind ?? 'no-note') != 'no-note';
      expect(findSoundAlike('Life. Add eggs to work.', reads), (before: '', after: 'Add eggs to work.'));
      expect(findSoundAlike('Live, new notes.', reads)?.after, 'new notes.');
      expect(findSoundAlike('Head life. Put call Sam on the work list.', reads)?.after, 'Put call Sam on the work list.');
      expect(findSoundAlike('Add life, add eggs to work.', reads)?.after, 'add eggs to work.');
      // Words, not a command.
      expect(findSoundAlike('Life is short.', reads), isNull);
      expect(findSoundAlike('Live. Laugh. Love.', reads), isNull);
      expect(findSoundAlike('We climbed the cliff. Add it to the story.', reads), isNull);
      expect(findSoundAlike('Cliff, add eggs to the moon list.', reads), isNull);
    });

    test('is not fooled by words that contain it or sound near it', () {
      expect(findKeyword('The hieroglyphs were beautiful.'), isNull);
      expect(findKeyword('We climbed the cliff at dawn.'), isNull);
    });
  });

  group('what a command asks for', () {
    test('adds a thing to a note named after it, the way people say it', () {
      expect(plan('add buy milk to the hello trade.'), PlanPlace<Candidate>(note: at('h'), text: 'buy milk', how: PlacementHow.leave, task: false, many: false));
      expect(plan('put call Sam on the work list'), matchObject({'kind': 'place', 'note': at('w'), 'text': 'call Sam'}));
      expect(plan('add to work: call Sam'), matchObject({'kind': 'place', 'note': at('w'), 'text': 'call Sam'}));
    });

    test('uses an actual titled prefix for labeled, called, and short bare targets', () {
      final go = [withBody('go', 'Go', 'Go')];
      for (final words in ['add to the note labeled Go pack the charger', 'add to the note called go: pack the charger', 'add to GO, pack the charger']) {
        expect(planCommand(words, notes: go), matchObject({'kind': 'place', 'note': {'id': 'go'}, 'text': 'pack the charger'}), reason: words);
      }
    });

    test('adds a list item when one is asked for, and waits for it when it is not said yet', () {
      expect(plan('add a list item to the hello trade'), PlanAwait<Candidate>(note: at('h'), how: PlacementHow.item, task: false, many: false));
      expect(plan('add a task buy stamps to work'), matchObject({'kind': 'place', 'note': at('w'), 'text': 'buy stamps', 'how': 'item', 'task': true}));
      expect(plan('new item for hello trade, fix the login'), matchObject({'kind': 'place', 'note': at('h'), 'text': 'fix the login', 'how': 'item'}));
    });

    test('waits for what to add when a note is named alone', () {
      expect(plan('add a note to hello trade'), matchObject({'kind': 'await', 'note': at('h'), 'how': 'leave'}));
      expect(
        plan('leave a note for places to go that says the lake by the cabin'),
        matchObject({'kind': 'place', 'note': at('p'), 'text': 'the lake by the cabin'}),
      );
    });

    test('moves the take, or starts a new note', () {
      expect(plan('switch to work'), PlanMove<Candidate>(note: at('w')));
      expect(plan('move this to the hello trade note'), PlanMove<Candidate>(note: at('h')));
      expect(plan('new note'), const PlanNew<Candidate>());
    });

    test('says so when the note named does not exist, and waits when nothing is a command yet', () {
      expect(plan('add eggs to the shopping list'), isNull);
      expect(plan('new item for groceries, eggs'), const PlanNoNote<Candidate>(name: 'groceries'));
      expect(plan('add'), isNull);
      expect(plan(''), isNull);
    });
  });

  group('asking for a table', () {
    test('names the note, or means this one', () {
      expect(plan('add a table to the attackfm bugbash note'), PlanTable<Candidate>(note: at('b'), columns: const []));
      expect(plan('make a new table.'), const PlanTable<Candidate>(note: null, columns: []));
    });

    test('takes column labels said up front', () {
      expect(
        plan('add a table to hello trade with columns bug, owner and status'),
        PlanTable<Candidate>(note: at('h'), columns: const ['Bug', 'Owner', 'Status']),
      );
    });

    test('says so for a note that is not there, and is not fooled by other tables', () {
      expect(plan('add a table to the groceries note'), const PlanNoNote<Candidate>(name: 'groceries'));
      expect(plan('add a table of contents'), isNull);
    });

    test('hears the labels the way lists are said', () {
      expect(cellsOf('Bug, owner and status.'), ['Bug', 'Owner', 'Status']);
      expect(cellsOf('seek bar drift, Matt, open'), ['Seek bar drift', 'Matt', 'Open']);
      expect(cellsOf('name and email'), ['Name', 'Email']);
      expect(cellsOf('Column one, bug, column two, owner.'), ['Bug', 'Owner']);
      expect(cellsOf(''), <String>[]);
    });
  });

  group('books by voice', () {
    // A book is a note whose body is an index (docs/BOOKS.md); the planner sees bodies through `note`.
    final guide = withBody('f', 'Field guide', bookNoteBody('Field guide', ['Trees']));
    final library = <Candidate>[...notes, guide];
    Plan<Candidate>? read(String words) => planCommand(words, notes: library);

    test('makes a book by name, the notes named after "with" as its pages', () {
      expect(read('make a book called Field notes'), const PlanBook<Candidate>(title: 'Field notes', pages: []));
      expect(read('New book called trip, with trees, birds and the work note.'), const PlanBook<Candidate>(title: 'Trip', pages: ['Trees', 'Birds', 'Work']));
      expect(read('start a book, Packing.'), const PlanBook<Candidate>(title: 'Packing', pages: []));
    });

    test('waits for a name, and is not fooled by a book for a list', () {
      expect(read('make a book'), isNull);
      expect(read('new book.'), isNull);
      expect(read('add a book to work'), matchObject({'kind': 'place', 'note': at('w'), 'text': 'a book'}));
    });

    test('adds a notebook said as a thing whole, not a note and the word book (docs/DESIGN.md §142)', () {
      expect(read('Add a notebook to work.'), matchObject({'kind': 'place', 'note': at('w'), 'text': 'a notebook'}));
      expect(read('Add a bugfix for login to work.'), matchObject({'kind': 'place', 'note': at('w'), 'text': 'a bugfix for login'}));
      // The kind of thing is still taken off where it is the whole word.
      expect(read('Add a note: call Sam to work.'), matchObject({'kind': 'place', 'note': at('w')}));
      expect(read('Add a note: call Sam to work.'), isNot(matchObject({'text': matches(RegExp(r'^a note', caseSensitive: false))})));
    });

    test("knows no notebook by name: a new one said is a note's words, as it would be said", () {
      expect(read('New notebook for school, pens and paper.'), isNull);
      expect(read('Make a notebook called Field notes.'), isNull);
    });

    test('adds a chapter to a book named: by title, this note, or the title in the next phrase', () {
      expect(read('add a chapter called Rivers to the field guide'), PlanChapter<Candidate>(note: guide, title: 'Rivers'));
      expect(read('put the rivers in the field guide.'), PlanChapter<Candidate>(note: guide, title: 'The rivers'));
      expect(read('add this to the field guide'), PlanChapter<Candidate>(note: guide, title: null));
      expect(read('move this to the field guide'), PlanChapter<Candidate>(note: guide, title: null));
      expect(read('switch to the field guide'), PlanChapter<Candidate>(note: guide, title: null));
      expect(read('add a chapter to the field guide'), matchObject({'kind': 'await', 'note': guide, 'how': 'leave'}));
    });
  });

  group('what is added, and what only introduced it', () {
    final house = [withBody('house', 'House TODOs', '# House TODOs\n\n- [ ] Fix the gutter\n')];

    test('leaves “The note is” and its like out of what is added', () {
      for (final words in [
        "add a note to house to do's. The note is call an electrician to fix the light sockets.",
        "add a note to house to do's, the note says call an electrician to fix the light sockets",
        'add a note to house to-dos: it says call an electrician to fix the light sockets',
      ]) {
        expect(
          planCommand(words, notes: house),
          matchObject({'kind': 'place', 'note': {'id': 'house'}, 'text': 'call an electrician to fix the light sockets'}),
          reason: words,
        );
      }
      expect(withoutPayloadLead('The note is: call Sam'), 'call Sam');
      // Words that only look like one stay: a note about a note.
      expect(withoutPayloadLead('The note from Sam is on the fridge'), 'The note from Sam is on the fridge');
    });

    test('finds a note named at the start of “add to …” by its words, up to a comma or the best few words', () {
      expect(
        planCommand('add to house to-dos, call an electrician', notes: house),
        matchObject({'kind': 'place', 'note': {'id': 'house'}, 'text': 'call an electrician'}),
      );
      expect(
        planCommand('add to my house chores call an electrician', notes: house),
        matchObject({'kind': 'place', 'note': {'id': 'house'}, 'text': 'call an electrician'}),
      );
    });
  });

  group('the keyword misheard', () {
    bool reads(String words) => (plan(words)?.kind ?? 'no-note') != 'no-note';

    test('takes “hey, like” and “hey goes” at the start when a command follows, and not otherwise', () {
      expect(findMisheard('Hey, like add eggs to work.', reads), (before: '', after: 'add eggs to work.'));
      expect(findMisheard('Hey goes add eggs to work', reads)?.after, 'add eggs to work');
      expect(findMisheard('Hi coast, new note.', reads)?.after, 'new note.');
      expect(findMisheard('Hey, like, the weather is lovely.', reads), isNull);
      expect(findMisheard('Hey goes the saying.', reads), isNull);
      expect(findMisheard('I said hey goes add eggs to work', reads), isNull);
      // How people talk, whatever follows: "okay, like", "hey, go", "hey, most", "hey, post".
      expect(findMisheard('Okay, like, add some salt to work.', reads), isNull);
      expect(findMisheard('Hey, go add eggs to work.', reads), isNull);
      expect(findMisheard('Hey, post the eggs to work.', reads), isNull);
      expect(findMisheard('Hey most of it goes to work.', reads), isNull);
    });

    test('reads a finished recording that opened with one, or with filler before the keyword', () {
      expect(finalCommandWords('Hey, like add eggs to work.'), 'add eggs to work.');
      expect(finalCommandWords('Um, hey Ghost, add eggs to work.'), 'add eggs to work.');
      expect(finalCommandWords('Hey Ghost, I want to add eggs to work.'), 'add eggs to work.');
      expect(finalCommandWords('Hey Ghost, let’s add eggs to work.'), 'add eggs to work.');
      // Without the keyword, only what never starts a sentence of its own goes: "Just put…" is a sentence.
      expect(finalCommandWords('Just put the parcel in the post.'), isNull);
      expect(finalCommandWords('Like, add some salt next time.'), isNull);
      expect(finalCommandWords('Okay, add eggs to work.'), 'add eggs to work.');
      expect(onlyFiller('Um,'), true);
      expect(onlyFiller('Pick up the parcel.'), false);
    });
  });
}
