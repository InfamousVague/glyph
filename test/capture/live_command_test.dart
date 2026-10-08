import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/live_command.dart';

import 'support/shapes.dart';

/// Hearing a command in one committed phrase (lib/capture/live_command.dart), case for case with the web's
/// `capture/liveCommand.test.ts`.

/// The first reading of each shape, as the grammar gives them: name, payload, and the flags a test is about.
List<Map<String, Object?>> read(String text) => [
  for (final r in readRoute(commandWords(text))) {'shape': r.shape, 'name': r.name, 'payload': r.payload, 'stopped': r.stopped, 'split': r.split},
];
List<List<Object?>> named(String text) => [
  for (final r in read(text))
    if (r['split'] != true) [r['name'], r['payload']],
];

Reading? firstWhere(List<Reading> readings, bool Function(Reading) test) {
  for (final r in readings) {
    if (test(r)) return r;
  }
  return null;
}

void main() {
  group('hearing the keyword in a phrase', () {
    bool always(String _) => true;
    bool never(String _) => false;

    test('hears it anywhere, with the words before it kept apart', () {
      expect(
        hearKeyword('Hey Ghost, add a note to house to do’s.', never),
        const HeardKeyword(before: '', after: 'add a note to house to do’s.', misheard: false),
      );
      expect(
        hearKeyword('Kevin owns the release, hey Ghost, add call Sam to work.', never),
        matchObject({'before': 'Kevin owns the release', 'after': 'add call Sam to work.'}),
      );
    });

    test('hears its mishearings at the start only when a command follows, with or without a comma', () {
      expect(
        hearKeyword('Hey, like, add a note to house to do’s, the note is call Sam.', always),
        matchObject({'misheard': true, 'after': 'add a note to house to do’s, the note is call Sam.'}),
      );
      expect(hearKeyword('Hey goes add a note to house to-dos. Call an electrician.', always), matchObject({'misheard': true}));
      expect(hearKeyword('Hey, like, the weather is lovely.', never), isNull);
      expect(hearKeyword('Okay, like, add a note to house to-dos.', always), isNull);
      expect(hearKeyword('Hey, go add a note to house to-dos.', always), isNull);
    });

    test('counts a mishearing only before a command for a note, by its shape, and a note named clearly', () {
      bool clear(Reading _) => true;
      for (final words in ['add a note to house to-dos, call Sam', 'add call Sam to house to-dos', 'add this to weekend trip: book the ferry', 'move this to daily life', 'new item for groceries, eggs']) {
        expect(misheardShape(commandWords(words), clear), true, reason: words);
      }
      for (final words in ['I need to call my mum', 'I have to get this finished by Friday', 'new note', 'remind me to book the MOT', 'go to work', 'for groceries, eggs']) {
        expect(misheardShape(commandWords(words), clear), false, reason: words);
      }
      expect(misheardShape('add a note to house to-dos, call Sam', (_) => false), false);
    });
  });

  // The gate a phrase passes with no keyword (docs/DESIGN.md §136), by its words alone and then by the note it names.
  // Each sentence that stays out was a mis-fire the review of the design found.
  group('the shapes a bare command may have', () {
    List<Reading> shapes(String text) => readRoute(commandWords(text)).where(bareShape).toList();
    List<String> names(String text) => shapes(text).map((r) => r.name).toList();

    test('takes a note or an item said for a note, a stopped “put this in”, “add X to Y”, a heading, and “move this”', () {
      expect(names('add a note to house to-dos, call Sam'), ['house to-dos']);
      expect(names('new item for groceries, eggs'), ['groceries']);
      expect(names('put this in the house list, call Sam'), ['house list']);
      expect(names('add call Sam to house to-dos'), contains('house to-dos'));
      expect(names('add fix the tap under kitchen in home jobs'), contains('home jobs'));
      expect(names('move this to the garage'), ['garage']);
      expect(names('switch this to work'), ['work']);
    });

    // Each moved a whole recording, or filed a message, in review: how people talk about boxes, days and messages.
    test('never takes “move everything”, “move these”, a move to a day, or a note sent or raised rather than filed without a list', () {
      for (final words in ['move everything to the garage', 'move these to the kitchen', 'move this to Tuesday', 'move this to next week', 'switch this to tomorrow']) {
        expect(names(words), <String>[], reason: words);
      }
      bool? filed(String text) => firstWhere(readRoute(commandWords(text)), (r) => r.shape == 1 || r.shape == 2)?.filed;
      for (final words in ['add a note to work, call Sam', 'put an item in groceries, eggs', 'new item for groceries, eggs', 'add a to-do to work, call Sam', 'another item for the agenda, we need to hire']) {
        expect(filed(words), true, reason: words);
      }
      for (final words in [
        'leave a note for Mum, dinner is in the oven',
        'send a note to Sam, the deposit is due',
        'drop a line to the team, the office is shut',
        'write a note to Sam, thanks for the flowers',
        'jot down a note for the kids, pizza is in the freezer',
        'another point for the agenda, we need to hire',
        'another thing for the kitchen, we need new tiles',
        'add a comment to the work, it needs another pass',
      ]) {
        expect(filed(words), false, reason: words);
      }
    });

    test('never takes a name from a split the grammar chose, a to-do for here, a name said first, or an unstopped “put this in”', () {
      // "Another item on the agenda is the budget": the only name is the whole tail, never "agenda" with "is the
      // budget" after it.
      final agenda = readRoute(commandWords('another item on the agenda is the budget'));
      expect(firstWhere(agenda, (r) => r.name == 'agenda'), matchObject({'shape': 2, 'split': true, 'payload': 'is the budget'}));
      expect(names('another item on the agenda is the budget'), ['agenda is the budget']);
      expect(names('add a note to house to-dos call Sam'), ['house to-dos call Sam']);
      for (final words in [
        'remind me to book the MOT',
        'make a note to call the electrician',
        'new note',
        'for groceries, eggs',
        'put this in weekend trip',
        'add a note to call log',
        'go to work',
        'continue in the garage',
        'move it to the garage',
        'carry on in work',
      ]) {
        expect(names(words), <String>[], reason: words);
      }
    });

    test('marks a move said plainly: “move this” or “switch this”, never “go to” or “move it”', () {
      bool? plain(String text) => firstWhere(readRoute(text), (r) => r.shape == 5)?.plainMove;
      expect(plain('go to work'), false);
      expect(plain('move this to work'), true);
      expect(plain('move it to work'), false);
      expect(plain('switch this to work'), true);
      expect(plain('switch everything to work'), false);
      expect(plain('move these to work'), false);
      expect(plain('continue this in work'), false);
      expect(plain('switch to weekend trip'), false);
      expect(plain('carry on in the garage'), false);
    });

    test('wants the name to say what kind of list it is for “put this in”, “add X to Y”, a heading and a note sent, and the heading to exist', () {
      Reading one(String text) => shapes(text).first;
      const sam = (title: 'Sam', body: '# Sam\n\n- Owes me a tenner\n');
      const groceries = (title: 'Groceries', body: '# Groceries\n\n- Eggs\n');
      const work = (title: 'Work', body: '# Work\n\nNotes.\n');
      const jobs = (title: 'Home jobs', body: '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n');
      expect(bareEvidence(one('send this to Sam, the deposit is due'), sam), false);
      expect(bareEvidence(one('put this in the house list, call Sam'), work), true);
      expect(bareEvidence(one('add oat milk to groceries'), groceries), true);
      expect(bareEvidence(one('add call the plumber to work'), work), false);
      expect(bareEvidence(one('add call the plumber to the work list'), work), true);
      expect(bareEvidence(one('add fix the tap under kitchen in home jobs'), jobs), true);
      expect(bareEvidence(one('add the key under the mat in home jobs'), jobs), false);
      // The heading reading itself: "Kitchens" is Kitchen, "Kitchen sink" is not a heading Home jobs has.
      Reading heading(String text) => shapes(text).firstWhere((r) => r.shape == 8);
      expect(bareEvidence(heading('add fix the tap under kitchens in home jobs'), jobs), true);
      expect(bareEvidence(heading('add fix the tap under kitchen sink in home jobs'), jobs), false);
      expect(
        bareEvidence(heading('add fix the tap under the sink in home jobs'), (title: 'Home jobs', body: '# Home jobs\n\n## Upstairs kitchen sink drains\n- [ ] Fix tap\n')),
        false,
      );
      // A heading the note has is not enough when the name does not say it is a list.
      expect(bareEvidence(heading('add fix the tap under kitchen in the house'), (title: 'House', body: jobs.body)), false);
      // A title that says it is a list is not enough when the name does not: "house" is a place, and "garden" is.
      const house = (title: 'House TODOs', body: '# House TODOs\n\n- [ ] Fix the gutter\n');
      const garden = (title: 'Garden jobs', body: '# Garden jobs\n\n- Weed\n');
      expect(bareEvidence(one('put the washing in the house'), house), false);
      expect(bareEvidence(one('put this in the garden, next to the shed'), garden), false);
      expect(bareEvidence(one('add call Sam to house to-dos'), house), true);
      // "A note" filed is its own evidence, whatever the title; one sent or left for someone is not.
      expect(bareEvidence(one('add a note to work, call Sam'), work), true);
      expect(bareEvidence(one('send a note to Sam, the deposit is due'), sam), false);
      expect(bareEvidence(one('send a note to the house list, call Sam'), work), true);
      expect(bareEvidence(one('move this to work'), work), true);
    });

    test('knows a phrase that is only the keyword’s lead, only filler, or Whisper’s line for a silence', () {
      expect(onlyLead('Hey.'), true);
      expect(onlyLead('Hey Sam.'), false);
      expect(onlyFillerPhrase('Okay.'), true);
      expect(onlyFillerPhrase('Okay, the budget.'), false);
      expect(silenceLine('Thank you.'), true);
      expect(silenceLine('Thank you for coming.'), false);
    });

    test('takes the lead-ins off the command, never the words', () {
      expect(commandWords('like, add a note to house to-dos'), 'add a note to house to-dos');
      expect(commandWords('can you add call Sam to work'), 'add call Sam to work');
      expect(commandWords('I want to add call Sam to work'), 'add call Sam to work');
      expect(commandWords('I want to go home'), 'I want to go home');
      expect(payloadOf('The note is call an electrician.'), 'call an electrician.');
    });
  });

  group('the shapes of a command for a note', () {
    test('reads Matt’s sentence with a stop, a comma, or nothing between the name and the note', () {
      expect(named("add a note to house to do's. The note is call an electrician to fix the light sockets."), [
        ["house to do's", 'The note is call an electrician to fix the light sockets'],
      ]);
      expect(named("add a note to house to do's, the note is call an electrician"), [
        ["house to do's", 'the note is call an electrician'],
      ]);
      expect(named("add a note to house to do's."), [
        ["house to do's", ''],
      ]);
      final bare = read("add a note to house to do's the note is call an electrician");
      expect(bare, contains(equals({'shape': 1, 'name': "house to do's", 'payload': 'the note is call an electrician', 'stopped': false, 'split': true})));
    });

    test('reads the thing, then the note, at every “to”, “in” or “on”', () {
      final readings = read('add call an electrician to fix the light sockets to house to-dos.');
      expect(readings, contains(equals({'shape': 4, 'name': 'house to-dos', 'payload': 'call an electrician to fix the light sockets', 'stopped': false, 'split': false})));
      // A "name" that starts with a thing to do is no name.
      expect(firstWhere(readRoute('add call an electrician to fix the light sockets to house to-dos'), (r) => r.name.startsWith('fix'))?.verb, true);
    });

    test('keeps what follows a stop after a shape-four name as the take’s words, and what follows a comma as more of the thing', () {
      expect(
        firstWhere(readRoute('add call Sam to house to-dos. Next, the budget review is Friday'), (r) => r.shape == 4),
        matchObject({'name': 'house to-dos', 'payload': 'call Sam', 'trailing': 'Next, the budget review is Friday'}),
      );
      expect(firstWhere(readRoute('add milk to groceries, eggs'), (r) => r.shape == 4), matchObject({'name': 'groceries', 'payload': 'milk, eggs'}));
      expect(readRoute('add milk to groceries and eggs'), contains(objectContaining({'name': 'groceries', 'payload': 'milk, eggs', 'split': true})));
    });

    test('keeps what was said after the verb, for a name that finds nothing to give back', () {
      expect(
        firstWhere(readRoute('add a note to moon base pack sunscreen'), (r) => !r.split),
        matchObject({'name': 'moon base pack sunscreen', 'tail': 'moon base pack sunscreen'}),
      );
      expect(
        firstWhere(readRoute('add eggs to the moon base'), (r) => r.shape == 4),
        matchObject({'name': 'moon base', 'payload': 'eggs', 'tail': 'eggs to the moon base'}),
      );
    });

    // A take-back's send, said in a breath of its own after "scratch that" (take_back.dart): "instead" is not the
    // name's.
    test('leaves “instead” off the end of a name', () {
      expect(firstWhere(readRoute('add it to Groceries instead.'), (r) => r.shape == 4), matchObject({'name': 'Groceries', 'payload': ''}));
      expect(firstWhere(readRoute('put that in house to-dos instead'), (r) => r.shape == 4), matchObject({'name': 'house to-dos', 'payload': ''}));
      expect(firstWhere(readRoute('add milk to groceries instead'), (r) => r.shape == 4), matchObject({'name': 'groceries', 'payload': 'milk'}));
    });

    test('ends a thing’s name at “that says”, and reads a paragraph asked for as the kind of words, not the words', () {
      expect(
        firstWhere(readRoute('add a paragraph to Groceries that says we are out of bread'), (r) => r.shape == 4),
        matchObject({'name': 'Groceries', 'payload': 'we are out of bread', 'placing': 'paragraph', 'stopped': true}),
      );
      expect(
        firstWhere(readRoute('add milk to groceries saying it is urgent'), (r) => r.shape == 4),
        matchObject({'name': 'groceries', 'payload': 'milk, it is urgent'}),
      );
    });

    test('reads the other openings', () {
      expect(
        readRoute('new item for house to-dos, call Sam')[0],
        matchObject({'shape': 2, 'name': 'house to-dos', 'payload': 'call Sam', 'placing': 'item', 'noun': true}),
      );
      expect(readRoute('add to house to-dos, call Sam')[0], matchObject({'shape': 3, 'name': 'house to-dos', 'payload': 'call Sam'}));
      expect(readRoute('add a to-do to house to-dos')[0], matchObject({'shape': 1, 'placing': 'task'}));
      expect(readRoute('switch to weekend trip'), contains(objectContaining({'shape': 5, 'name': 'weekend trip', 'move': true})));
      expect(readRoute('move this to the weekend trip'), contains(objectContaining({'shape': 5, 'name': 'weekend trip', 'move': true})));
      expect(
        readRoute('put this under kitchen in house to-dos'),
        contains(objectContaining({'shape': 8, 'name': 'house to-dos', 'heading': 'kitchen', 'payload': ''})),
      );
      expect(readRoute('new note.'), [objectContaining({'newNote': true})]);
      expect(readNameFirst('for groceries, eggs and milk'), [objectContaining({'name': 'groceries', 'payload': 'eggs and milk', 'nameFirst': true})]);
      expect(readNameFirst('House TODOs: call Sam'), [objectContaining({'name': 'House TODOs', 'payload': 'call Sam'})]);
    });

    test('reads a to-do for the note being written to', () {
      expect(readRoute('remind me to book the MOT'), [objectContaining({'self': true, 'payload': 'book the MOT', 'placing': 'task'})]);
      expect(
        readRoute('make a note to call the electrician'),
        contains(objectContaining({'self': true, 'payload': 'call the electrician', 'placing': 'task'})),
      );
      expect(readRoute('add a to-do: call Sam'), [objectContaining({'self': true, 'payload': 'call Sam'})]);
      expect(readRoute('add eggs here'), [objectContaining({'self': true, 'payload': 'eggs', 'placing': 'item'})]);
    });

    test('reads nothing for a note where there is no note', () {
      for (final words in [
        'put the dates in a table',
        'add a summary to the top',
        'fix the spelling',
        'make a list called packing',
        'add a table to this note',
        'add a chapter to the field guide',
        'make this a board',
        'make a book called trips',
      ]) {
        expect(readRoute(words).where((r) => !r.verb).toList(), <Reading>[], reason: words);
      }
      expect(nameable('a table'), Nameable.not);
      expect(nameable('the bottom'), Nameable.not);
      expect(nameable('call the bank'), Nameable.verb);
      expect(nameable('house to-dos'), Nameable.name);
    });

    test('knows a command still waiting for its name', () {
      for (final words in ['', 'add a note to', 'add eggs to', 'new item for', 'move this to', 'for', 'add']) {
        expect(isOpener(words), true, reason: words);
      }
      for (final words in ['add a note to house', 'fix the spelling', 'call Sam']) {
        expect(isOpener(words), false, reason: words);
      }
    });
  });
}
