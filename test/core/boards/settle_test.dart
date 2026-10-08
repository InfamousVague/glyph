import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/boards.dart';

/// A tick carried to the fences: ticked cards into Done, cleared ones out, and an unanchored item joining its list's
/// board.
///
/// lib/core/boards/settle.dart, reached as every caller reaches it: through the room's door, lib/core/boards.dart.
/// Case for case with the web's `core/boards/settle.test.ts`.

/// The web's `toEqual({ fences: [], lines: [] })`.
void expectNothing(SettledTicks settled) {
  expect(settled.fences, isEmpty);
  expect(settled.lines, isEmpty);
}

void main() {
  group('ticking an item that is not a card', () {
    final note = [
      '```board',
      'To do: milk, eggs',
      'Done:',
      '```',
      '',
      '- [ ] Milk ^milk',
      '- [ ] Eggs ^eggs',
      '- [ ] Bread',
      '',
      '## Later',
      '',
      '- [ ] Something else entirely',
      '',
    ].join('\n');

    test('puts it on its list’s board, in Done, and names its line', () {
      // From Matt's note: three ticked items had no anchor, so ticking them moved nothing while 57 others worked.
      final settled = settleTicks(note, {8: true});
      expect(settled.lines, [(number: 8, anchor: 'bread')]);
      expect(settled.fences[0].body, 'To do: milk, eggs\nDone: bread');
      // The fence's own lines, counting from 1, which is what the editor's caller writes over.
      expect(settled.fences, [const FenceEdit(from: 1, to: 4, body: 'To do: milk, eggs\nDone: bread')]);
    });

    test('leaves a list that is not on a board alone', () {
      // The item under a heading of its own belongs to no board: a board never has to hold every item in the note.
      expectNothing(settleTicks(note, {12: true}));
    });

    test('still just moves an item that is already a card', () {
      final settled = settleTicks(note, {6: true});
      expect(settled.lines, isEmpty);
      expect(settled.fences[0].body, 'To do: eggs\nDone: milk');
    });

    test('takes a batch, as a set of tasks arriving from Notion does', () {
      final settled = settleTicks(note, {6: true, 8: true});
      expect(settled.lines, [(number: 8, anchor: 'bread')]);
      expect(settled.fences[0].body, 'To do: eggs\nDone: milk, bread');
    });

    test('does nothing for a box being cleared, or a line that is not an item', () {
      expectNothing(settleTicks(note, {8: false}));
      expectNothing(settleTicks(note, {10: true}));
    });
  });

  group('the ticks and the lanes', () {
    final note = ['```board', 'To do: milk, eggs, bread', 'Doing:', 'Done:', '```', '', '- [ ] Milk ^milk', '- [x] Eggs ^eggs', '- [x] Bread ^bread', ''].join('\n');

    test('writes the ticked cards where the board draws them: in Done', () {
      expect(settleBoards(note), [const FenceEdit(from: 1, to: 5, body: 'To do: milk\nDoing:\nDone: eggs, bread')]);
    });

    test('moves a box being ticked, and takes a box being cleared out of Done', () {
      expect(settleBoards(note, {7: true})[0].body, 'To do:\nDoing:\nDone: milk, eggs, bread');
      const settled = '```board\nTo do: milk\nDoing:\nDone: eggs, bread\n```\n\n- [ ] Milk ^milk\n- [x] Eggs ^eggs\n- [x] Bread ^bread\n';
      expect(settleBoards(settled, {8: false})[0].body, 'To do: milk, eggs\nDoing:\nDone: bread');
      // A batch, the way a set of tasks arrives from Notion at once.
      expect(settleBoards(settled, {8: false, 9: false})[0].body, 'To do: milk, eggs, bread\nDoing:\nDone:');
    });

    test('says nothing when there is nothing to move, and leaves a board with no Done lane alone', () {
      const settled = '```board\nTo do: milk\nDone: eggs\n```\n\n- [ ] Milk ^milk\n- [x] Eggs ^eggs\n';
      expect(settleBoards(settled), isEmpty);
      expect(settleBoards('```board\nTo do: milk\nNext: eggs\n```\n\n- [ ] Milk ^milk\n- [x] Eggs ^eggs\n'), isEmpty);
    });

    test('leaves the card a person has just moved where they put it', () {
      final board = boardsIn(note)[0];
      final items = itemsIn(note);
      // Bread dragged into Doing: it stays there, and the other ticked card still settles into Done.
      final moved = putCard(board.columns, 'bread', 1);
      expect(writeBoard(settleColumns(moved, items, 'bread')), 'To do: milk\nDoing: bread\nDone: eggs');
      expect(writeBoard(settleColumns(moved, items)), 'To do: milk\nDoing:\nDone: eggs, bread');
    });
  });
}
