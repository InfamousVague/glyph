import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/boards.dart';

import 'launch_week.dart';

/// The ```board fence: columns read and written, ids read against the note's anchors, the lanes' height, and a board
/// taken away as words.
///
/// lib/core/boards/fence.dart, reached as every caller reaches it: through the room's door, lib/core/boards.dart.
/// Case for case with the web's `core/boards/fence.test.ts`.

const String note = launchWeek;

void main() {
  group('a board in markdown', () {
    test('reads the columns and the cards in them', () {
      final columns = readBoard('To do: ship-page, email-list\nIn progress: fix-login\nDone: pick-date');
      expect(columns.map((c) => c.name), ['To do', 'In progress', 'Done']);
      expect(columns[0].cards, ['ship-page', 'email-list']);
      expect(columns[2].cards, ['pick-date']);
    });

    test('gives an id in two lanes to the first of them, so a card is never drawn twice', () {
      const doc = '```board\nTo do: alpha, beta\nDoing: alpha\nDone:\n```\n\n- [ ] Alpha ^alpha\n- [ ] Beta ^beta\n';
      final columns = boardsIn(doc)[0].columns;
      expect(columns.map((column) => column.cards), [
        ['alpha', 'beta'],
        <String>[],
        <String>[],
      ]);
      // Written back, the note says what the board shows: the second mention is gone, not drawn in a lane of its own.
      expect(writeBoard(columns), 'To do: alpha, beta\nDoing:\nDone:');
    });

    test('reads a lane id written as words when the note has that anchor, and leaves other words alone', () {
      const doc =
          '```board\nTo do: Fix Login, ^Add Controls To\nDoing: Sam to reply\n```\n\n- [ ] Fix login ^fix-login\n- [ ] Add controls ^add-controls-to\n';
      final columns = boardsIn(doc)[0].columns;
      expect(columns.map((column) => column.cards), [
        ['fix-login', 'add-controls-to'],
        <String>[],
      ]);
      // An id no item answers is not made up out of words after the colon; a plain anchor still is, and shows as missing.
      expect(boardsIn('```board\nTo do: ship-page\n```\n')[0].columns[0].cards, ['ship-page']);
    });

    test('keeps an empty column, joins a name said twice, and ignores what is not an anchor', () {
      final columns = readBoard('Blocked:\nTo do: a, Not An Anchor, b\nto do: c\n\n   \n: nothing');
      expect(columns.map((c) => c.name), ['Blocked', 'To do']);
      expect(columns[0].cards, isEmpty);
      expect(columns[1].cards, ['a', 'b', 'c']);
    });

    test('takes an anchor written with its caret, and drops a card named twice', () {
      expect(readBoard('To do: ^a, a, ^b')[0].cards, ['a', 'b']);
    });

    test('writes the columns back the way a person types them', () {
      final columns = readBoard('To do: a, b\nBlocked:\nDone: c');
      expect(writeBoard(columns), 'To do: a, b\nBlocked:\nDone: c');
    });

    test('finds the boards in a note, with the lines their fences are on', () {
      final boards = boardsIn(note);
      expect(boards, hasLength(1));
      expect(boards[0].from, 3);
      expect(boards[0].to, 7);
      expect(boards[0].columns, hasLength(3));
    });

    test('reads an unclosed fence as a board that has not been finished', () {
      final boards = boardsIn('```board\nTo do: a\n');
      expect(boards[0].from, 1);
      expect(boards[0].to, 1);
      expect(boards[0].columns, isEmpty);
    });
  });

  group('a board taken away as words', () {
    test('gives the fence and the items it names, in the order the note has them', () {
      expect(
        boardCopy(note, 4),
        [
          '```board',
          'To do: ship-page, email-list',
          'In progress: fix-login',
          'Done: pick-date',
          '```',
          '',
          '- [ ] Ship the pricing page ^ship-page',
          '- [ ] Email the beta list ^email-list',
          '- [ ] Fix the login button ^fix-login',
          '- [x] Pick a launch date ^pick-date',
          '',
        ].join('\n'),
      );
    });

    test('is the same board again when it is pasted into an empty note', () {
      final again = boardCopy(note, 3)!;
      expect(boardsIn(again)[0].columns, boardsIn(note)[0].columns);
      expect(itemsIn(again).map((item) => item.id), ['ship-page', 'email-list', 'fix-login', 'pick-date']);
    });

    test('takes a board with no items yet, and answers nothing off a board', () {
      expect(boardCopy('```board\nTo do:\n```', 2), '```board\nTo do:\n```\n');
      expect(boardCopy(note, 9), isNull);
      expect(boardCopy('- [ ] Alone', 1), isNull);
    });
  });

  group('how tall a board is', () {
    test('is read from the fence, and is the board’s own height when the fence says nothing', () {
      expect(boardsIn(note)[0].height, isNull);
      final set = boardsIn('```board height=18\nTo do: a\n```')[0];
      expect(set.height, 18);
      expect(set.columns, [
        const BoardColumn(name: 'To do', cards: ['a']),
      ]);
      expect(boardsIn('~~~ board height=12.5em\nTo do:\n~~~')[0].height, 12.5);
      // Junk after the word is a setting nobody reads, and the board is still a board.
      final wide = boardsIn('```board wide\nTo do:\n```')[0];
      expect(wide.height, isNull);
      expect(wide.columns, [const BoardColumn(name: 'To do', cards: [])]);
      // A word that only starts with "board" is not a board.
      expect(boardsIn('```boards\nTo do:\n```'), isEmpty);
    });

    test('is kept between a card and a half and a long screen, to the half em', () {
      expect(boardsIn('```board height=1\nTo do:\n```')[0].height, boardHeight.min);
      expect(boardsIn('```board height=900\nTo do:\n```')[0].height, boardHeight.max);
      expect(clampHeight(17.3), 17.5);
    });

    test('is written into the fence and taken out again, the rest of the line as it was', () {
      expect(withBoardHeight('```board', 18), '```board height=18');
      expect(withBoardHeight('```board height=18', 24.2), '```board height=24');
      expect(withBoardHeight('  ~~~~ Board wide height=18 ', 9), '  ~~~~ Board height=9 wide');
      expect(withBoardHeight('```board height=18 wide', null), '```board wide');
      expect(withBoardHeight('```board height=18', null), '```board');
      expect(withBoardHeight('```js', 18), '```js');
      // What it writes, it reads back.
      expect(boardsIn('${withBoardHeight('```board', 21.5)}\nTo do:\n```')[0].height, 21.5);
    });
  });
}
