import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/boards.dart';

import 'launch_week.dart';

/// Boards and cards made from a note's lists: an item put on its list's board, a card added from the board, and a
/// note or one list made into a board.
///
/// lib/core/boards/make.dart, reached as every caller reaches it: through the room's door, lib/core/boards.dart.
/// Case for case with the web's `core/boards/make.test.ts`.

const String note = launchWeek;

void main() {
  group('putting a list item on a board', () {
    test('names an item that has no anchor, from its own words', () {
      expect(anchorFor('Book the ferry before Friday', []), 'book-ferry-before');
      expect(anchorFor('Book the ferry', ['book-ferry']), 'book-ferry-2');
      expect(anchorFor('!!!', []), 'item');
    });

    test('leaves the filler out, so two items that start alike are not named alike', () {
      expect(anchorFor('Add ability to auto-tag notes', []), 'add-ability-auto');
      expect(anchorFor('Add ability to add tags', []), 'add-ability-add');
      expect(anchorFor('Git icon is messed up', []), 'git-icon-messed');
      expect(anchorFor('The fade in is too slow', []), 'fade-too-slow');
      // Words that are all filler keep them, rather than come out as nothing.
      expect(anchorFor('Is it on', []), 'is-it-on');
    });

    test('adds the card to the first column, and gives the line its anchor', () {
      final added = addToBoard(note, 13)!;
      expect(added.id, 'something-not-board');
      expect(added.line, (number: 13, text: '- [ ] Something not on the board ^something-not-board'));
      expect(added.fence.from, 3);
      expect(added.fence.to, 7);
      expect(added.fence.body.split('\n')[0], 'To do: ship-page, email-list, something-not-board');
      expect(added.column, 'To do');
    });

    test('takes a bullet as readily as a to-do', () {
      final doc = note.replaceFirst('- [ ] Something not on the board', '- Ask Sam about the copy');
      final added = addToBoard(doc, 13)!;
      expect(added.id, 'ask-sam-about');
      expect(added.line?.text, '- Ask Sam about the copy ^ask-sam-about');
      expect(added.column, 'To do');
    });

    test('uses the board its own list is already on, not the nearest one above', () {
      // Two boards: the list at the foot belongs to the second, though the first is also above it.
      final doc = [
        '```board',
        'To do: alpha',
        'Done:',
        '```',
        '',
        '- [ ] Alpha ^alpha',
        '',
        '## Later',
        '',
        '```board',
        'Next: beta',
        'Done:',
        '```',
        '',
        '- [ ] Beta ^beta',
        '- [ ] Gamma',
        '',
      ].join('\n');
      final added = addToBoard(doc, 16)!;
      expect(added.fence.from, 10);
      expect(added.fence.to, 13);
      expect(added.fence.body, 'Next: beta, gamma\nDone:');
      expect(added.column, 'Next');
    });

    test('goes in beside the neighbour it follows in the list, keeping the list’s order', () {
      final doc = ['```board', 'To do: one, three', 'Done:', '```', '', '- [ ] One ^one', '- [ ] Two', '- [ ] Three ^three', ''].join('\n');
      // Two sits between one and three in the list, so its card goes between theirs.
      expect(addToBoard(doc, 7)?.fence.body, 'To do: one, two, three\nDone:');
    });

    test('is not offered for an item already on the board', () {
      expect(addToBoard(note, 9), isNull);
      expect(addToBoard(note, 1), isNull);
    });

    test('puts a ticked item straight in Done, and keeps the anchor it has', () {
      final doc = note.replaceFirst('- [ ] Something not on the board', '- [x] Something not on the board ^later');
      final added = addToBoard(doc, 13)!;
      expect(added.id, 'later');
      expect(added.line, isNull);
      expect(added.column, 'Done');
      expect(added.fence.body, contains('Done: pick-date, later'));
    });

    test('answers nothing for a line that is no list item, a note with no board, or an item already on one', () {
      expect(addToBoard(note, 1), isNull);
      expect(addToBoard('- [ ] Alone in the world', 1), isNull);
      expect(addToBoard(note, 9), isNull);
    });
  });

  group('a card added from the board itself', () {
    test('writes a to-do with its words under the last item the board names, named after them', () {
      final made = newCard(note, 3, 1, 'Rename the weak anchors')!;
      expect(made.id, 'rename-weak-anchors');
      expect(made.at, 13);
      // A real task list item anywhere: a space after the box, the words, then the anchor.
      expect(made.text, '- [ ] Rename the weak anchors ^rename-weak-anchors');
      expect(itemOnLine(made.text), const Item(id: 'rename-weak-anchors', text: 'Rename the weak anchors', done: false, line: 0));
    });

    test('puts the card at the top of the column tapped, or where it is told', () {
      expect(newCard(note, 3, 1, 'Book the ferry')!.fence.body, 'To do: ship-page, email-list\nIn progress: book-ferry, fix-login\nDone: pick-date');
      expect(newCard(note, 3, 0, 'Book the ferry', 99)!.fence.body.split('\n')[0], 'To do: ship-page, email-list, book-ferry');
    });

    test('makes nothing without words, so no card is ever named after nothing', () {
      expect(newCard(note, 3, 0, ''), isNull);
      expect(newCard(note, 3, 0, '   '), isNull);
    });

    test('keeps each name its own, and tidies the words it is given', () {
      final made = newCard(note, 3, 0, '  Ship   the page  ')!;
      expect(made.text, '- [ ] Ship the page ^ship-page-2');
    });

    test('goes under the fence when the board names nothing yet, and answers nothing off a board', () {
      const empty = '```board\nTo do:\nDone:\n```\n';
      final first = newCard(empty, 1, 0, 'First');
      expect(first?.at, 5);
      expect(first?.text, '- [ ] First ^first');
      expect(newCard(note, 9, 0, 'Words'), isNull);
      expect(newCard(note, 3, 7, 'Words'), isNull);
    });
  });

  group('a list made into a board', () {
    final list = ['# Task Management', '', '- [ ] Ship the pricing page', '- [x] Pick a launch date', '- [ ] Email the [beta list](https://example.com/list)', ''].join('\n');

    test('anchors every item and lays the columns out under the title', () {
      final made = boardFrom(list)!;
      expect(made.cards, 3);
      expect(made.done, 1);
      expect(made.doc.split('\n'), [
        '# Task Management',
        '',
        '```board',
        'To do: ship-pricing-page, email-beta-list',
        'Doing:',
        'Done: pick-launch-date',
        '```',
        '',
        '- [ ] Ship the pricing page ^ship-pricing-page',
        '- [x] Pick a launch date ^pick-launch-date',
        '- [ ] Email the [beta list](https://example.com/list) ^email-beta-list',
        '',
      ]);
    });

    test('reads back as the board it looks like', () {
      final made = boardFrom(list)!;
      final board = boardsIn(made.doc)[0];
      final cards = cardsOf(board.columns, itemsIn(made.doc));
      expect(cards.map((card) => card.item?.text), ['Ship the pricing page', 'Email the [beta list](https://example.com/list)', 'Pick a launch date']);
    });

    test('takes a plain list as well, whose cards have no box to tick', () {
      final made = boardFrom('- Oat milk\n- Rye bread')!;
      expect(made.cards, 2);
      expect(made.done, 0);
      expect(made.doc.split('\n').sublist(6), ['- Oat milk ^oat-milk', '- Rye bread ^rye-bread']);
      expect(itemsIn(made.doc).map((item) => item.done), [null, null]);
    });

    test('leaves a list inside a block of code exactly as it is', () {
      final made = boardFrom('- Real item\n\n```md\n- [ ] not a task, an example\n```\n')!;
      expect(made.cards, 1);
      expect(made.doc, contains('- [ ] not a task, an example\n'));
      expect(made.doc, isNot(contains('example ^')));
    });

    test('keeps an anchor an item already has, and leaves the words alone', () {
      final made = boardFrom('- [ ] Already named ^mine\n- [ ] The other one')!;
      expect(made.doc.split('\n').sublist(6), ['- [ ] Already named ^mine', '- [ ] The other one ^other-one']);
      expect(made.doc.split('\n')[1], 'To do: mine, other-one');
    });

    test('takes the columns it is given, and puts what is ticked in the one called Done', () {
      final made = boardFrom('- [x] One\n- [ ] Two', ['Later', 'Done now'])!;
      expect(made.doc.split('\n').sublist(0, 4), ['```board', 'Later: two', 'Done now: one', '```']);
    });

    test('answers nothing for a note with no list, or one that is a board already', () {
      expect(boardFrom('# Notes\n\nJust words.'), isNull);
      expect(boardFrom(note), isNull);
    });
  });

  group('one list made into a board', () {
    // Matt: "add ability to auto list a section of list items into a board".
    final doc = [
      '# Trip',
      '',
      'Packing:',
      '- [ ] Tent',
      '- [x] Stove',
      '  bring the spare gas',
      '',
      '- [ ] Maps',
      '',
      '',
      '- Not this list',
      '',
      '## Errands',
      '1. Post office',
      '2. Bank',
      '',
      '```md',
      '- [ ] an example, not a list',
      '```',
    ].join('\n');

    test('finds the list a line is in, blank line and indented lines included, and stops at two blank lines', () {
      expect(listAround(doc, 4), (from: 4, to: 8));
      expect(listAround(doc, 6), (from: 4, to: 8));
      expect(listAround(doc, 8), (from: 4, to: 8));
      expect(listAround(doc, 11), (from: 11, to: 11));
      expect(listAround(doc, 15), (from: 14, to: 15));
    });

    test('finds no list on a line of words, a heading, a blank line, or inside a block of code', () {
      expect(listAround(doc, 3), isNull);
      expect(listAround(doc, 13), isNull);
      expect(listAround(doc, 9), isNull);
      expect(listAround(doc, 18), isNull);
    });

    test('makes that list a board set in just above it, and leaves everything else alone', () {
      final made = boardFromList(doc, 4, 8)!;
      expect(made.cards, 3);
      expect(made.done, 1);
      expect(made.open, 5);
      expect(made.doc.split('\n').sublist(2, 14), [
        'Packing:',
        '',
        '```board',
        'To do: tent, maps',
        'Doing:',
        'Done: stove',
        '```',
        '',
        '- [ ] Tent ^tent',
        '- [x] Stove ^stove',
        '  bring the spare gas',
        '',
      ]);
      // The other lists are untouched.
      expect(made.doc, contains('- Not this list\n'));
      expect(made.doc, contains('1. Post office\n2. Bank\n'));
    });

    test('says what to change in the note as it was: the item lines, and the fence to put in above the list', () {
      final made = boardFromList(doc, 4, 8)!;
      expect(made.lines, [(number: 4, text: '- [ ] Tent ^tent'), (number: 5, text: '- [x] Stove ^stove'), (number: 8, text: '- [ ] Maps ^maps')]);
      expect(made.fence, (before: 4, text: '\n```board\nTo do: tent, maps\nDoing:\nDone: stove\n```\n\n'));
      // Applied that way round, the note is the one `doc` says.
      final lines = doc.split('\n');
      for (final line in made.lines) {
        lines[line.number - 1] = line.text;
      }
      lines[made.fence.before - 1] = '${made.fence.text}${lines[made.fence.before - 1]}';
      expect(lines.join('\n'), made.doc);
    });

    test('can be done while the note has another board, and not twice to the same list', () {
      final first = boardFromList(doc, 14, 15)!;
      // Straight under a heading, the board keeps a blank line from it.
      expect(first.open, 15);
      expect(first.doc.split('\n').sublist(12, 21), ['## Errands', '', '```board', 'To do: post-office, bank', 'Doing:', 'Done:', '```', '', '1. Post office ^post-office']);
      expect(boardsIn(first.doc), hasLength(1));
      final again = boardFromList(first.doc, 4, 8)!;
      expect(boardsIn(again.doc), hasLength(2));
      // The list under the new board is already a board.
      final list = listAround(first.doc, 21)!;
      expect(list, (from: 21, to: 22));
      expect(boardFromList(first.doc, list.from, list.to), isNull);
    });

    test('keeps anchors an item has, and makes nothing of lines with no items', () {
      final made = boardFromList('- [ ] Tent ^mine\n- Stove', 1, 2)!;
      expect(made.doc, '```board\nTo do: mine, stove\nDoing:\nDone:\n```\n\n- [ ] Tent ^mine\n- Stove ^stove');
      expect(made.lines, [(number: 2, text: '- Stove ^stove')]);
      expect(boardFromList(doc, 1, 3), isNull);
    });
  });
}
