import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/boards.dart';

/// Columns as data: a card moved, dropped and taken off, and a card whose anchor slipped still finding its item.
///
/// lib/core/boards/columns.dart, reached as every caller reaches it: through the room's door, lib/core/boards.dart.
/// Case for case with the web's `core/boards/columns.test.ts`.

void main() {
  group('moving a card', () {
    final columns = readBoard('To do: a, b\nDoing: c\nDone: d');

    test('goes one column along, and stops at either end', () {
      expect(writeBoard(moveCard(columns, 'a', 1)), 'To do: b\nDoing: c, a\nDone: d');
      expect(writeBoard(moveCard(columns, 'a', -1)), 'To do: a, b\nDoing: c\nDone: d');
      expect(writeBoard(moveCard(columns, 'd', 1)), 'To do: a, b\nDoing: c\nDone: d');
      expect(writeBoard(moveCard(columns, 'nothing', 1)), writeBoard(columns));
    });

    test('is put in a column outright, and leaves the one it was in', () {
      expect(writeBoard(putCard(columns, 'a', 2)), 'To do: b\nDoing: c\nDone: d, a');
      expect(writeBoard(putCard(columns, 'a', 0)), 'To do: b, a\nDoing: c\nDone: d');
      expect(writeBoard(putCard(columns, 'a', 9)), writeBoard(columns));
    });

    test('is dropped between two cards, at the place the gap was shown', () {
      expect(writeBoard(putCardAt(columns, 'c', 0, 0)), 'To do: c, a, b\nDoing:\nDone: d');
      expect(writeBoard(putCardAt(columns, 'c', 0, 1)), 'To do: a, c, b\nDoing:\nDone: d');
      expect(writeBoard(putCardAt(columns, 'c', 0, 99)), 'To do: a, b, c\nDoing:\nDone: d');
    });

    test('is reordered inside its own column, counting the places without itself', () {
      expect(writeBoard(putCardAt(columns, 'a', 0, 1)), 'To do: b, a\nDoing: c\nDone: d');
      expect(writeBoard(putCardAt(columns, 'b', 0, 0)), 'To do: b, a\nDoing: c\nDone: d');
      expect(writeBoard(putCardAt(columns, 'a', 0, 0)), writeBoard(columns));
      // The columns given are never changed, only answered anew.
      expect(columns[0].cards, ['a', 'b']);
    });

    test('knows which column is Done, and where a ticked item belongs', () {
      expect(doneColumn(columns), 2);
      expect(doneColumn(readBoard('To do: a\nWaiting: b')), -1);
      expect(columnOf(columns, 'c'), 1);
      expect(columnFor(columns, const Item(id: 'a', text: 'A', done: true, line: 1)), 2);
      expect(columnFor(columns, const Item(id: 'a', text: 'A', done: false, line: 1)), 0);
      // An item with no box is wherever the board has it, ticks being nothing to do with it.
      expect(columnFor(columns, const Item(id: 'c', text: 'C', done: null, line: 1)), 1);
      // With no Done column, a ticked item stays where the board has it.
      final plain = readBoard('To do: a\nWaiting: b');
      expect(columnFor(plain, const Item(id: 'a', text: 'A', done: true, line: 1)), 0);
    });
  });

  group('a card whose anchor has slipped', () {
    // Matt's board named `blur-bottom-swimlanes`, and the line had become `^blur-bottom-swimlaness`.
    const url = 'https://app.notion.com/p/the-blur-3de5';
    final doc = [
      '```board height=19',
      'To do: we-should-show, blur-bottom-swimlanes',
      'Done: switching',
      '```',
      '',
      '- [x] Switching workspaces scrolls smoothly ^switching',
      '- [ ] we should show the bookmark as a physical symbol ^we-should-show',
      '- [ ] the blur at the bottom of the swimlanes should be the wisp effect [notion]($url) ^blur-bottom-swimlaness',
    ].join('\n');

    test('shows the item it meant, when exactly one item no board names is a slip of it', () {
      final board = boardsIn(doc)[0];
      final cards = cardsOf(board.columns, itemsIn(doc));
      expect(cards.map((card) => [card.id, card.item?.id]), [
        ['we-should-show', 'we-should-show'],
        ['blur-bottom-swimlanes', 'blur-bottom-swimlaness'],
        ['switching', 'switching'],
      ]);
      expect(cards[1].item?.text, 'the blur at the bottom of the swimlanes should be the wisp effect [notion]($url)');
    });

    test('takes nothing a board already names, nothing when two items could be it, and nothing for a short anchor', () {
      final named = doc.replaceFirst('Done: switching', 'Done: switching, blur-bottom-swimlaness');
      final board = boardsIn(named)[0];
      final meant = cardsOf(board.columns, itemsIn(named)).where((card) => card.id == 'blur-bottom-swimlanes').toList();
      expect(meant, hasLength(1));
      expect(meant[0].item, isNull);

      final twice = '$doc\n- [ ] another ^blur-bottom-swimlanez';
      expect(cardsOf(boardsIn(twice)[0].columns, itemsIn(twice))[1].item, isNull);

      const short = '```board\nTo do: abc\n```\n\n- [ ] Thing ^abcd';
      expect(cardsOf(boardsIn(short)[0].columns, itemsIn(short))[0].item, isNull);
    });

    test('counts one letter added, dropped or changed, or up to two more at the end, as a slip', () {
      expect(nearAnchor('blur-bottom-swimlanes', 'blur-bottom-swimlaness'), true);
      expect(nearAnchor('ship-page', 'ship-pages-'), true);
      expect(nearAnchor('ship-page', 'shp-page'), true);
      expect(nearAnchor('ship-page', 'ship-paje'), true);
      expect(nearAnchor('ship-page', 'ship-page'), false);
      expect(nearAnchor('ship-page', 'ship-pages-now'), false);
      expect(nearAnchor('ship-page', 'shop-paje'), false);
    });
  });

  group('a card taken off the board', () {
    test('goes from every lane and leaves the item where it is', () {
      const doc = '```board\nTo do: milk, eggs\nDone:\n```\n\n- [ ] Milk ^milk\n- [ ] Eggs ^eggs\n';
      final columns = boardsIn(doc)[0].columns;
      expect(writeBoard(withoutCard(columns, 'milk')), 'To do: eggs\nDone:');
      // An id the board does not have changes nothing.
      expect(writeBoard(withoutCard(columns, 'bread')), writeBoard(columns));
      expect(itemsIn(doc).map((item) => item.id), ['milk', 'eggs']);
    });
  });
}
