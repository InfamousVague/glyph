import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/route.dart';

import 'support/shapes.dart';

/// "Add to Weekend trip" (lib/capture/route.dart), case for case with the web's `capture/route.test.ts`.

const notes = [
  Candidate(id: 'a', title: 'Weekend trip'),
  Candidate(id: 'b', title: 'Shopping list'),
  Candidate(id: 'c', title: 'Work'),
  Candidate(id: 'd', title: 'Ideas for the garden'),
  Candidate(id: 'e', title: 'Weekend trip to the lake'),
];

void main() {
  group('hearing "add to <note>"', () {
    test('finds the command at the start and keeps what follows', () {
      expect(parseRoute('Add to shopping list, oat milk and eggs.'), const RouteCommandNote(name: 'shopping', rest: 'oat milk and eggs.'));
      expect(parseRoute('Put this in my work note. Email Sam about Friday.'), const RouteCommandNote(name: 'work', rest: 'Email Sam about Friday.'));
    });

    test('finds the command at the end and keeps what came before', () {
      expect(parseRoute('Oat milk and eggs, add that to the shopping list.'), const RouteCommandNote(name: 'shopping', rest: 'Oat milk and eggs'));
      expect(parseRoute('Add to weekend trip.'), const RouteCommandNote(name: 'weekend trip', rest: ''));
      expect(parseRoute('Switch to ideas for the garden'), const RouteCommandNote(name: 'ideas for the garden', rest: ''));
    });

    test('hears "new note" only on its own', () {
      expect(parseRoute('New note.'), const RouteCommandNew(rest: ''));
      expect(parseRoute('I need a new notebook for school.'), isNull);
    });

    test('leaves ordinary sentences alone', () {
      expect(parseRoute('We should add salt to the soup.'), isNull);
      expect(parseRoute('I went to the shops.'), isNull);
      expect(parseRoute('Remember to ask Sam about the dog.'), isNull);
    });

    test('does not take a name of a letter or two for a note', () {
      expect(parseRoute('add to we'), isNull);
    });
  });

  group('hearing "new item for <note>"', () {
    test('takes the note name and an item said in the same phrase', () {
      expect(parseRoute('New item for AttackFM, fix the login bug.'), const RouteCommandItem(name: 'AttackFM', rest: 'fix the login bug.', task: false, many: false));
      expect(parseRoute('Add a task to the backlog: dark mode.'), const RouteCommandItem(name: 'backlog', rest: 'dark mode.', task: true, many: false));
    });

    test('hears the command on its own, the item to follow', () {
      expect(parseRoute('New item for AttackFM.'), const RouteCommandItem(name: 'AttackFM', rest: '', task: false, many: false));
      expect(parseRoute('New to-dos for work.'), matchObject({'kind': 'item', 'name': 'work', 'task': true, 'many': true}));
    });

    test('waits for the phrase to end, or the item to follow, before the name counts', () {
      expect(parseRoute('new item for attack'), isNull);
    });

    test('leaves sentences about new items alone', () {
      expect(parseRoute('The new item for AttackFM is great.'), isNull);
      expect(parseRoute('I bought a new thing for the kitchen yesterday and it broke.'), isNull);
    });
  });

  group('an item command with another word after the name', () {
    // Changed on purpose (docs/DESIGN.md §127): no plugin takes a word off a note's name any more ("…in Notion").
    test('leaves the word in the name', () {
      expect(parseRoute('New task for AttackFM in Notion, fix the login bug.'), matchObject({'name': 'AttackFM in Notion'}));
    });
  });

  group('matching a spoken name to a note', () {
    test('forgives how speech recognition spells titles', () {
      expect(similarity('week end trip', 'Weekend trip'), 1);
      expect(similarity('weekend trips', 'Weekend trip'), greaterThan(0.9));
      expect(matchNote('the shopping', notes)?.note.id, 'b');
      expect(matchNote('shopping list', notes)?.note.id, 'b');
    });

    test('prefers the exact title over a longer one it starts', () {
      expect(matchNote('weekend trip', notes)?.note.id, 'a');
      expect(matchNote('weekend trip to the lake', notes)?.note.id, 'e');
    });

    test('refuses a name that fits nothing, or fits two notes equally', () {
      expect(matchNote('the oven', notes), isNull);
      expect(matchNote('weekend', const [Candidate(id: 'x', title: 'Weekend trip'), Candidate(id: 'y', title: 'Weekend plans')]), isNull);
    });
  });

  group('hearing "leave a note for <note> that says …"', () {
    test('takes the note’s name and what the note says', () {
      expect(
        parseRoute('Leave a note on the page for AttackFM that says the login is broken on Android.'),
        const RouteCommandLeave(name: 'AttackFM', rest: 'the login is broken on Android'),
      );
      expect(parseRoute('Add a note to shopping list saying we are out of eggs'), const RouteCommandLeave(name: 'shopping', rest: 'we are out of eggs'));
      expect(parseRoute('Write a quick note in my work note: call Sam about Friday.'), const RouteCommandLeave(name: 'work', rest: 'call Sam about Friday'));
      expect(parseRoute('Can you leave a note for the weekend trip, book the cabin'), const RouteCommandLeave(name: 'weekend trip', rest: 'book the cabin'));
      expect(
        parseRoute('Leave a note on the page called ideas for the garden that we need more mulch.'),
        const RouteCommandLeave(name: 'ideas for the garden', rest: 'we need more mulch'),
      );
    });

    test('waits for the note when the phrase stops at the name', () {
      expect(parseRoute('Leave a note for weekend trip.'), const RouteCommandLeave(name: 'weekend trip', rest: ''));
      // A finished phrase with no stop could still be growing: not yet.
      expect(parseRoute('Leave a note for weekend trip'), isNull);
    });

    test('leaves ordinary sentences alone', () {
      expect(parseRoute('I left a note on the fridge.'), isNull);
      expect(parseRoute('We should make a note of that.'), isNull);
    });
  });
}
