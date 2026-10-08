/// The grammar of taking back what was just said (`lib/capture/take_back.dart`): which phrases are one, and what
/// each holds. A port of `src/app/capture/takeBack.test.ts`, case for case.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/take_back.dart';

/// The web's `toMatchObject`: the fields named, and no others.
void expectMatches(TakeBack? read, Map<String, Object?> fields) {
  expect(read, isNotNull);
  final all = <String, Object?>{
    'head': read!.head,
    'headBeforeKeyword': read.headBeforeKeyword,
    'opener': read.opener,
    'said': read.said,
    'risky': read.risky,
    'rest': read.rest,
    'send': read.send,
    'keyed': read.keyed,
    'afterComma': read.afterComma,
  };
  expect({for (final key in fields.keys) key: all[key]}, fields);
}

void main() {
  group('a safe opener', () {
    for (final said in ['Scratch that.', 'Strike that.', 'Take that back.', 'Forget that.', 'Delete that.', 'Never mind.', 'Cancel that.', 'Ignore that.', 'No wait.', 'No, wait.', 'Wait no.', 'Wait, no.']) {
      test('is read alone: $said', () {
        expectMatches(readTakeBack(said), {'head': '', 'risky': false, 'rest': '', 'send': null, 'keyed': false, 'afterComma': false});
      });
    }

    test('takes its rest after a pause, a colon or “and”, as said', () {
      expectMatches(readTakeBack('Scratch that, call the plumber.'), {'opener': 'Scratch that', 'rest': 'call the plumber.', 'said': 'Scratch that, call the plumber.'});
      // After a stop Whisper capitalises whatever comes next, so the first letter comes down: "Tomorrow" is no name.
      expectMatches(readTakeBack('Scratch that. Call the plumber.'), {'rest': 'call the plumber.'});
      expectMatches(readTakeBack('Scratch that. Tomorrow.'), {'rest': 'tomorrow.'});
      expectMatches(readTakeBack('Scratch that. TODOs first.'), {'rest': 'TODOs first.'});
      expectMatches(readTakeBack('Scratch that, Sarah.'), {'rest': 'Sarah.'});
      expectMatches(readTakeBack('Scratch that: call the plumber.'), {'rest': 'call the plumber.'});
      expectMatches(readTakeBack('Scratch that and call the plumber.'), {'rest': 'call the plumber.'});
      // Lead-ins after the opener stay: they may be written.
      expectMatches(readTakeBack('Scratch that, um, call the plumber.'), {'rest': 'um, call the plumber.'});
    });

    for (final said in ['Take that back to the shop.', 'Scratch that off the list.', 'Strike that pose.', 'Forget that we spoke.', 'Delete that file.', 'Never mind the cost.', 'Cancel that order.', 'Ignore that noise.']) {
      test('needs a pause after it, so prose is words: $said', () {
        expect(readTakeBack(said), isNull);
      });
    }

    test('is “no wait” only bare: with words after it, it is a risky opener', () {
      expectMatches(readTakeBack('No wait.'), {'risky': false, 'rest': ''});
      expectMatches(readTakeBack('No wait, four.'), {'risky': true, 'rest': 'four.'});
      expectMatches(readTakeBack('No wait four.'), {'risky': true, 'rest': 'four.'});
      expectMatches(readTakeBack('Should we cancel the order? No wait, that is fine.'), {'head': 'Should we cancel the order?', 'risky': true, 'rest': 'that is fine.'});
      expect(readTakeBack('No waiter came.'), isNull);
    });

    test('reads a send said straight after it, with no pause', () {
      expectMatches(readTakeBack('scratch that add it to groceries'), {'rest': 'add it to groceries', 'send': 'groceries'});
    });
  });

  group('a risky opener', () {
    test('counts only with words after it, with or without a comma', () {
      expectMatches(readTakeBack('Actually, the meeting is at four.'), {'risky': true, 'opener': 'Actually', 'rest': 'the meeting is at four.'});
      expectMatches(readTakeBack('Actually the meeting is at four.'), {'risky': true, 'rest': 'the meeting is at four.'});
      expect(readTakeBack('Actually.'), isNull);
      expectMatches(readTakeBack('I mean the meeting is at four.'), {'risky': true, 'rest': 'the meeting is at four.'});
      expectMatches(readTakeBack('Or rather, the meeting is at four.'), {'risky': true});
    });

    test('needs the comma after “sorry” and “no”, and takes repeated no’s', () {
      expectMatches(readTakeBack('Sorry, the meeting is at four.'), {'risky': true, 'rest': 'the meeting is at four.'});
      expect(readTakeBack('Sorry I am late.'), isNull);
      expect(readTakeBack('Sorry.'), isNull);
      expectMatches(readTakeBack('No, the meeting is at four.'), {'risky': true, 'opener': 'No', 'rest': 'the meeting is at four.'});
      expectMatches(readTakeBack('No no, four.'), {'risky': true, 'rest': 'four.'});
      expectMatches(readTakeBack('No, no, no, four.'), {'risky': true, 'rest': 'four.'});
      expect(readTakeBack('No one came.'), isNull);
      expect(readTakeBack('No parking on Sunday.'), isNull);
      expect(readTakeBack('No.'), isNull);
    });
  });

  group('where an opener stands', () {
    test('after the lead-ins and the keyword, which sets keyed', () {
      expectMatches(readTakeBack('Okay, scratch that.'), {'head': '', 'keyed': false, 'said': 'scratch that.'});
      expectMatches(readTakeBack('um, actually, the meeting is at four.'), {'head': '', 'risky': true, 'rest': 'the meeting is at four.'});
      expectMatches(readTakeBack('Hey, like, scratch that.'), {'head': '', 'keyed': false});
      expectMatches(readTakeBack('Hey Ghost, scratch that.'), {'head': '', 'keyed': true, 'headBeforeKeyword': false, 'said': 'scratch that.'});
      expectMatches(readTakeBack('Hey Ghost, actually, call Sarah.'), {'keyed': true, 'risky': true, 'rest': 'call Sarah.'});
      expectMatches(readTakeBack('Um, hey Ghost, scratch that.'), {'head': '', 'keyed': true});
    });

    test('after a stop, in either case, with what came before as the head', () {
      expectMatches(readTakeBack('We need eggs. Scratch that.'), {'head': 'We need eggs.', 'rest': '', 'said': 'Scratch that.', 'keyed': false});
      expectMatches(readTakeBack('We need eggs. scratch that.'), {'head': 'We need eggs.'});
      expectMatches(readTakeBack('We need eggs. Actually, we need bread.'), {'head': 'We need eggs.', 'risky': true, 'rest': 'we need bread.'});
      expectMatches(readTakeBack('We need eggs! Never mind.'), {'head': 'We need eggs!'});
      expectMatches(readTakeBack('Kevin owns it. Scratch that, hey Ghost, add it to Work.'), {'head': 'Kevin owns it.', 'keyed': false, 'send': 'Work'});
    });

    test('after the keyword said after the head, which is marked as words then the keyword', () {
      expectMatches(readTakeBack('The heating is fixed, hey Ghost, scratch that.'), {'head': 'The heating is fixed', 'headBeforeKeyword': true, 'keyed': true, 'said': 'scratch that.'});
      // The keyword before a command head stays in the head, so the head is read as the command it was, and the opener
      // after it is not keyed: the keyword was the command's, not the opener's.
      expectMatches(readTakeBack('Hey Ghost, add call Sam to Work. Actually, call Sarah.'), {'head': 'Hey Ghost, add call Sam to Work.', 'headBeforeKeyword': false, 'keyed': false, 'rest': 'call Sarah.'});
      expectMatches(readTakeBack('Hey Ghost, add call Sam to Work. Actually, we should go for a walk.'), {'keyed': false, 'risky': true});
      expectMatches(readTakeBack('Hey Ghost, add a note to house, scratch that.'), {'head': 'Hey Ghost, add a note to house', 'afterComma': true, 'keyed': false});
    });

    test('after a comma inside a sentence, for a drop, a send or a change of one word, and not for a fragment', () {
      expectMatches(readTakeBack('The meeting is at three, scratch that.'), {'head': 'The meeting is at three', 'afterComma': true, 'rest': ''});
      expectMatches(readTakeBack('Oat milk, scratch that, add it to groceries instead.'), {'head': 'Oat milk', 'afterComma': true, 'send': 'groceries'});
      expectMatches(readTakeBack('The meeting is at three, no wait, four.'), {'head': 'The meeting is at three', 'afterComma': true, 'risky': true, 'rest': 'four.'});
      expectMatches(readTakeBack('The meeting is at three, actually, the meeting is at four.'), {'head': 'The meeting is at three', 'afterComma': true, 'rest': 'the meeting is at four.'});
      expect(readTakeBack('The meeting is at three, no wait for me at the station.'), isNull);
      expect(readTakeBack('The meeting is at three, scratch that, call Sam.'), isNull);
      expect(readTakeBack('Milk, eggs, actually, bread.'), isNull);
    });

    test('is words anywhere else', () {
      expect(readTakeBack('The heating is fixed.'), isNull);
      expect(readTakeBack('I actually think we should go.'), isNull);
      expect(readTakeBack('Hey Ghost, add a note to house to-dos.'), isNull);
      expect(readTakeBack(''), isNull);
    });
  });

  group('a send', () {
    for (final (said, name) in [
      ('Scratch that, add it to Groceries instead.', 'Groceries'),
      ('Scratch that, add it to Groceries.', 'Groceries'),
      ('Scratch that, put that in the house list.', 'house list'),
      ('Scratch that, put that in the list.', 'the list'),
      ('Scratch that, put that in my note.', 'my note'),
      ('Scratch that, that goes in Groceries.', 'Groceries'),
      ('Scratch that, it belongs in House TODOs.', 'House TODOs'),
      ('Scratch that, move it to House TODOs instead.', 'House TODOs'),
      ('Scratch that, this goes in House TODOs.', 'House TODOs'),
      ('Actually, put that in House TODOs.', 'House TODOs'),
      ('No wait, that goes in Groceries.', 'Groceries'),
      ('Scratch that, hey Ghost, add it to Groceries.', 'Groceries'),
      ('Scratch that, send those to my Work list instead.', 'Work list'),
    ]) {
      test('reads the note named in the rest: $said', () {
        expect(readTakeBack(said)?.send, name);
      });
    }

    test('is not a send when the thing is words, or the name is none', () {
      expectMatches(readTakeBack('Scratch that, add milk to Groceries.'), {'send': null, 'rest': 'add milk to Groceries.'});
      expectMatches(readTakeBack('Scratch that, add it to the top.'), {'send': null});
      expectMatches(readTakeBack('Scratch that, put it to a table.'), {'send': null});
      // "This" is the take's own word: "move this to X" moves the recording.
      expectMatches(readTakeBack('Scratch that, move this to Groceries.'), {'send': null});
    });

    test('is read over a whole phrase said in a breath of its own', () {
      expect(readSend('Add it to Groceries instead.'), 'Groceries');
      expect(readSend('Put that in the list.'), 'the list');
      expect(readSend('Hey Ghost, put that in house to-dos.'), 'house to-dos');
      expect(readSend('Okay, that goes in Groceries.'), 'Groceries');
      expect(readSend('Add milk to Groceries.'), isNull);
      expect(readSend('Add it to Groceries. Then call Sam.'), isNull);
      expect(readSend('Call the plumber.'), isNull);
    });
  });

  group('a sentence said again with a change', () {
    for (final (before, after) in [
      ('The meeting is at three', 'the meeting is at four'),
      ('Call Sam about the invoice', 'call Sarah about the invoice'),
      ('Call Sam', 'call Sarah'),
      ('Oat milk', 'almond milk'),
      ('Bullet point: eggs', 'eggs and milk'),
      ("It's on Tuesday", "it's on Thursday"),
    ]) {
      test('corrects: $before → $after', () {
        expect(corrects(before, after), true);
      });
    }

    for (final (before, after) in [
      ('The heating is fixed', 'I think we should go'),
      ('We need eggs', 'the meeting is on Friday'),
      ('The meeting is at three', 'at four'),
      ('Eggs', 'eggs, milk, bread and butter for the weekend'),
      ('The meeting is at three', 'so'),
      ('Eggs', 'milk'),
      ('Call Sam', 'ring Sarah'),
      ("It's on Tuesday", "it's for Sam"),
      // One word of two shared is a new sentence about the same thing.
      ('Call Sam', 'Sam is away'),
      ('Ring the bank', 'the bank is shut'),
      ('It is', 'so'),
    ]) {
      test('is a new sentence: $before → $after', () {
        expect(corrects(before, after), false);
      });
    }

    // Accepted: one of two words shared, and the item becomes what was said.
    test('takes an item said again with more', () {
      expect(corrects('Bullet point: eggs', 'eggs are in the fridge'), true);
    });

    test('reads the content words with the cue prefix off and contractions to their base', () {
      expect(contentWords("Check box: call Sam's mum, don't forget."), ['call', 'sam', 'mum', 'forget']);
    });
  });

  group('a change of one word', () {
    test('swaps the one word of the fragment’s kind, case and punctuation kept', () {
      expect(swapWord('The meeting is at three.', 'four'), (text: 'The meeting is at four.', from: 'three', to: 'four'));
      expect(swapWord('The meeting is at three.', 'Four.'), (text: 'The meeting is at four.', from: 'three', to: 'four'));
      expect(swapWord('The meeting is on Tuesday.', 'Thursday'), (text: 'The meeting is on Thursday.', from: 'Tuesday', to: 'Thursday'));
      expect(swapWord('Rent is due in March.', 'April')?.text, 'Rent is due in April.');
      expect(swapWord('Call Sam.', 'Sarah'), (text: 'Call Sarah.', from: 'Sam', to: 'Sarah'));
      expect(swapWord('Check box: call Sam.', 'Sarah')?.text, 'Check box: call Sarah.');
      expect(swapWord('It starts at 3.', '4')?.text, 'It starts at 4.');
      expect(swapWord('It starts at 3pm.', '4pm')?.text, 'It starts at 4pm.');
      expect(swapWord('Meet at three.', 'um, four')?.text, 'Meet at four.');
    });

    test('is null for two words of the kind, none, or a fragment of no kind', () {
      expect(swapWord('From three to four.', 'five'), isNull);
      expect(swapWord('We need eggs.', 'milk'), isNull);
      expect(swapWord('The meeting is at three.', 'at four'), isNull);
      expect(swapWord('Call Sam and Jo.', 'Sarah'), isNull);
      // The first word is capitalised whatever it is, so it is never a name.
      expect(swapWord('Sam owns it.', 'Sarah'), isNull);
      expect(swapWord('The meeting is at three.', 'three'), isNull);
    });
  });

  group('what a person would quote', () {
    test('leaves the cue prefix, the keyword and the stop off', () {
      expect(quoted('Check box: call Sam.'), 'call Sam');
      expect(quoted('Bullet point: eggs.'), 'eggs');
      expect(quoted('The meeting is at three.'), 'The meeting is at three');
      expect(quoted('Hey Ghost, fix the spelling.'), 'fix the spelling');
      expect(quoted('The heating is fixed, hey Ghost, fix the spelling.'), 'The heating is fixed, hey Ghost, fix the spelling');
    });
  });

  group('a command said with a risky opener', () {
    test('is the command, the opener off, and words otherwise', () {
      expect(commandAfterOpener('actually, add a note to House TODOs'), 'add a note to House TODOs');
      expect(commandAfterOpener('Actually add milk to groceries.'), 'add milk to groceries.');
      expect(commandAfterOpener('I mean, new item for groceries'), 'new item for groceries');
      expect(commandAfterOpener('sorry, add it to'), 'add it to');
      expect(commandAfterOpener('no wait, move this to groceries'), 'move this to groceries');
      expect(commandAfterOpener('actually, we should call the plumber'), 'actually, we should call the plumber');
      expect(commandAfterOpener('actually'), 'actually');
      expect(commandAfterOpener('add a note to House TODOs'), 'add a note to House TODOs');
    });
  });

  group('a partial starting a take-back', () {
    for (final partial in ['Scratch', 'scratch tha', 'Scratch that', 'Strike', 'no w', 'No wait', 'wait n', 'take that b', 'forget t', 'delete t', 'never m', 'cancel t', 'ignore t', 'Okay scratch']) {
      test('is for the chip: $partial', () {
        expect(opensTakeBack(partial), true);
      });
    }

    for (final partial in ['no', 'No', 'wait', 'take', 'take that', 'forget', 'delete', 'never', 'cancel', 'ignore', 'Actually', 'I mean', 'The meeting', 'scr', '']) {
      test('is for the page: $partial', () {
        expect(opensTakeBack(partial), false);
      });
    }

    test('is found after a stop or a comma inside the partial, the words before it left for the page', () {
      expect(takeBackAt('Scratch tha'), 0);
      expect(takeBackAt('The meeting is at three, no w'), 25);
      expect(takeBackAt('We need eggs. Call Sam. Scratch that'), 24);
      expect(takeBackAt('The meeting is at three, no'), -1);
      expect(takeBackAt('The meeting is at three'), -1);
      expect(takeBackAt(''), -1);
    });

    test('knows a send that is starting, keyword and lead-ins off', () {
      expect(opensSend('Add it to'), true);
      expect(opensSend('Hey Ghost, put that in gro'), true);
      expect(opensSend('That goes'), true);
      expect(opensSend("It's in"), true);
      expect(opensSend('Add milk to'), false);
      expect(opensSend('Addition'), false);
      expect(opensSend('That'), false);
      expect(opensSend(''), false);
    });
  });
}
