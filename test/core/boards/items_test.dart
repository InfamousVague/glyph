import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/boards.dart';
import 'package:ghost_md/core/item_syntax.dart' show wordsEnd;

import 'launch_week.dart';

/// The items a board points at: anchors, words and boxes, choices and counters, and an anchor pointed at from prose.
///
/// lib/core/boards/items.dart, reached as every caller reaches it: through the room's door, lib/core/boards.dart.
/// Case for case with the web's `core/boards/items.test.ts`.

const String note = launchWeek;

const Object _unset = Object();

/// An item's fields by name, for the web's `toMatchObject`: only the names a case gives are compared.
void expectItem(Item? item, {String? id, String? text, Object? done = _unset, int? line}) {
  expect(item, isNotNull);
  if (id != null) expect(item!.id, id);
  if (text != null) expect(item!.text, text);
  if (!identical(done, _unset)) expect(item!.done, done);
  if (line != null) expect(item!.line, line);
}

void main() {
  group('the items a board points at', () {
    test('finds every anchored item, with its words and its box', () {
      final items = itemsIn(note);
      expect(items.map((t) => t.id), ['ship-page', 'email-list', 'fix-login', 'pick-date']);
      expectItem(items[0], text: 'Ship the pricing page', done: false, line: 9);
      expect(items[3].done, true);
    });

    test('anchors any kind of list item, not only a to-do', () {
      final items = itemsIn('- Ask Sam about the copy ^ask-sam\n1. Unplug it ^unplug\n* A star ^star\n- [x] Ticked ^ticked');
      expect(items.map((item) => item.id), ['ask-sam', 'unplug', 'star', 'ticked']);
      // An item with no box has nothing to tick, which is not the same as being unticked.
      expect(items.map((item) => item.done), [null, null, null, true]);
      expect(items[1].text, 'Unplug it');
    });

    test('leaves a superscript alone: an anchor needs a space before it and the line to end after it', () {
      expect(itemOnLine('- E = mc^2^'), isNull);
      expect(itemOnLine('- the 2 ^nd^ of June'), isNull);
      expect(itemOnLine('- a fact ^unsure^ and more'), isNull);
      // The boundary: a closing caret makes it a superscript, and nothing else does.
      expect(itemOnLine('- item ^a^'), isNull);
      expectItem(itemOnLine('- Ship it ^ship-page'), id: 'ship-page', text: 'Ship it');
    });

    test('reads an item whose words are not written yet, which is what the + on a column leaves behind', () {
      expectItem(itemOnLine('- [ ] ^item'), id: 'item', text: '', done: false);
      expect(isItemLine('- [ ] ^item'), true);
      expect(setItemDone('- [ ] ^item', true), '- [x] ^item');
    });

    test('finds an item whose Notion mark was written after its anchor, and keeps the mark with its words', () {
      // Matt: "the last two items show up weird on the board as only their label no title".
      final doc = [
        '```board',
        'To do: add-task-input, make-board-height',
        '```',
        '',
        '- [ ] Add task input and button dont match up ^add-task-input [notion](https://app.notion.com/p/Add-task-input-3dd5)',
        '- [ ] make board height configurable with glacierUI split view ^make-board-height [notion](https://app.notion.com/p/make-board-height-3dd5)',
        '- [ ] ',
      ].join('\n');
      final cards = cardsOf(boardsIn(doc)[0].columns, itemsIn(doc));
      expect(cards.map((card) => card.item?.text), [
        'Add task input and button dont match up [notion](https://app.notion.com/p/Add-task-input-3dd5)',
        'make board height configurable with glacierUI split view [notion](https://app.notion.com/p/make-board-height-3dd5)',
      ]);
      // Ticking it leaves the line as it was written, anchor and mark both where they were.
      expect(
        setItemDone(doc.split('\n')[4], true),
        '- [x] Add task input and button dont match up ^add-task-input [notion](https://app.notion.com/p/Add-task-input-3dd5)',
      );
      // Only a mark may follow the anchor: anything else, and the caret is words.
      expect(itemOnLine('- [ ] Ship ^ship-it and then more'), isNull);
      expect(itemOnLine('- [ ] Ship ^ship-it [a link](not-a-url)'), isNull);
    });

    test('takes the first item of a repeated anchor', () {
      expect(itemsIn('- [ ] One ^a\n- [ ] Two ^a'), hasLength(1));
    });

    test('knows a list item from a line of words, and finds an item by its anchor', () {
      expect(isItemLine('- [ ] Ship it'), true);
      expect(isItemLine('  1. Unplug it'), true);
      expect(isItemLine('Just a line'), false);
      expect(isItemLine('- '), false);
      expectItem(itemAt(note, 'fix-login'), text: 'Fix the login button', line: 11);
      expect(itemAt(note, 'nowhere'), isNull);
    });

    test('reads one line, and ticks or clears it keeping its words and anchor', () {
      expectItem(itemOnLine('  - [ ] Ship it ^ship-page'), id: 'ship-page', text: 'Ship it', done: false);
      expect(itemOnLine('- [ ] no anchor here'), isNull);
      expect(setItemDone('  - [ ] Ship it ^ship-page', true), '  - [x] Ship it ^ship-page');
      expect(setItemDone('- [X] Ship it ^ship-page', false), '- [ ] Ship it ^ship-page');
      expect(setItemDone('- [ ] No anchor', true), '- [x] No anchor');
      // A bullet has no box: ticking it would have to write one, and the note is the person's.
      expect(setItemDone('- Ask Sam ^ask-sam', true), '- Ask Sam ^ask-sam');
    });

    test('gives a line its anchor once', () {
      expect(withAnchor('- Ask Sam  ', 'ask-sam'), '- Ask Sam ^ask-sam');
      expect(withAnchor('- Ask Sam ^mine', 'ask-sam'), '- Ask Sam ^mine');
    });

    test('pairs cards with their items, and says when one is gone', () {
      final board = boardsIn(note)[0];
      final cards = cardsOf(board.columns, itemsIn(note));
      expect(cards, hasLength(4));
      expect(cards[0].id, 'ship-page');
      expect(cards[0].column, 0);
      expect(cards[0].item?.text, 'Ship the pricing page');
      final gone = cardsOf(readBoard('To do: nowhere'), itemsIn(note));
      expect(gone[0].id, 'nowhere');
      expect(gone[0].item, isNull);
    });
  });

  group('an anchor pointed at from the words', () {
    test('is found anywhere in a line, and reads as the item it names', () {
      const line = 'the copy is waiting on [[#^ask-sam]] and [[#^ship-page]]';
      expect(refsIn(line).map((ref) => ref.id), ['ask-sam', 'ship-page']);
      expect(refsIn(line, 10)[0].from, 33);
      expect(refFor('ask-sam'), '[[#^ask-sam]]');
    });

    test('is not a link to another note, and takes only an anchor between the brackets', () {
      expect(refsIn('[[The cabin trip]]'), isEmpty);
      expect(refsIn('[[#^Not An Anchor]]'), isEmpty);
      expect(refsIn('[[#^ok]]'), hasLength(1));
    });

    test('is said by a card as the anchor, not as its brackets', () {
      expect(cardText('waiting on [[#^ask-sam]]'), 'waiting on ^ask-sam');
    });
  });

  group('what a card says', () {
    test('says a link by its words and drops the marks around them', () {
      expect(cardText('Fix the [login button](https://example.com/a/very/long/url) *today*'), 'Fix the login button today');
      expect(cardText('??Fit the washer??(Qwen3.5 4B from memory, 2026-09-28. Asked: the next step)'), 'Fit the washer');
      expect(cardText('{?the next step}'), 'the next step');
      expect(cardText('Read <https://example.com/x>'), 'Read https://example.com/x');
      expect(cardText('  lots   of   room  '), 'lots of room');
    });
  });

  group('an item with fields on a board (docs/DESIGN.md §158)', () {
    test('says its words without its fields, which the card draws as chips', () {
      expect(cardText('Fix the login loop @sam #bug ⏫ 📅 2026-10-03'), 'Fix the login loop #bug');
      expect(cardText('Water the plants 🔁 every week [effort:: 3]'), 'Water the plants');
    });

    test('is named by its words, never by a person or a day', () {
      expect(anchorFor('Call @sam 📅 2026-10-03', []), 'call');
      expect(anchorFor('Fix the login loop ⏫', []), 'fix-login-loop');
    });
  });

  group('choices and counters on a board', () {
    test('reads a choice as an item with no box, its words after the choice’s own', () {
      expect(itemOnLine('- ( ) Pick the red one ^red'), const Item(id: 'red', text: 'Pick the red one', done: null, line: 0));
      expectItem(itemOnLine('- (x) Pick the blue one ^blue'), text: 'Pick the blue one', done: null);
      // Only after a bullet, and only the exact box: a numbered line and a spaced box are words.
      expect(itemOnLine('1. ( ) Not a choice ^one')?.text, '( ) Not a choice');
      expect(itemOnLine('- ( x ) Not a choice ^two')?.text, '( x ) Not a choice');
      // A picked choice is not a done item: dragging it into Done does not touch its line.
      expect(setItemDone('- (x) Pick the blue one ^blue', false), '- (x) Pick the blue one ^blue');
    });

    test('makes a list of choices into cards named after their words', () {
      final made = boardFrom('- ( ) Pick red\n- (x) Pick blue')!;
      expect(made.done, 0);
      expect(made.doc.split('\n').sublist(6), ['- ( ) Pick red ^pick-red', '- (x) Pick blue ^pick-blue']);
    });

    test('finds an item whose counter was typed after its anchor, and keeps the counter with its words', () {
      // Typed at the end of the line, the counter lands after the anchor.
      expectItem(itemOnLine('- [ ] Pack socks ^pack-socks [3/8]'), id: 'pack-socks', text: 'Pack socks [3/8]');
      expectItem(
        itemOnLine('- [ ] Pack socks ^pack-socks [3/8] [notion](https://app.notion.com/p/x)'),
        id: 'pack-socks',
        text: 'Pack socks [3/8] [notion](https://app.notion.com/p/x)',
      );
      expectItem(itemOnLine('- [ ] Pack socks [3/8] ^pack-socks'), id: 'pack-socks', text: 'Pack socks [3/8]');
      // A link after the anchor is still not allowed: only marks and counters.
      expect(itemOnLine('- [ ] Pack ^pack [3/8](https://x.y)'), isNull);
    });

    test('leaves a counter out of an anchor it makes', () {
      expect(anchorFor('Pack socks [3/8]', []), 'pack-socks');
      expect(withAnchor('- [ ] Pack socks [3/8]', 'pack-socks'), '- [ ] Pack socks [3/8] ^pack-socks');
    });
  });

  group('where an item’s words end', () {
    test('is before its mark, counters and anchor, so a caret there types on the words', () {
      const url = 'https://app.notion.com/p/x';
      const line = '- [ ] Pack socks [3/8] [notion]($url) ^pack-socks';
      expect(line.substring(0, wordsEnd(line)), '- [ ] Pack socks');
      expect(wordsEnd('- [ ] Ship it ^ship-it  '), '- [ ] Ship it'.length);
      expect(wordsEnd('- [ ] Old order ^old [notion]($url)'), '- [ ] Old order'.length);
      // A superscript at the end is words, and so is a line that is not an item.
      expect(wordsEnd('- E = mc^2^'), '- E = mc^2^'.length);
      expect(wordsEnd('Just words ^not-an-item'), 'Just words ^not-an-item'.length);
      // An item with no words yet: the caret goes after its box.
      expect(wordsEnd('- [ ] ^item'), '- [ ] '.length);
    });

    test('is before the bookmark too, which no card, anchor or lane match says', () {
      const url = 'https://app.notion.com/p/x';
      const line = '- [ ] Ship it §§ [notion]($url) ^ship-it';
      expect(line.substring(0, wordsEnd(line)), '- [ ] Ship it');
      expect(wordsEnd('- [ ] §§'), '- [ ] '.length);
      expect(itemOnLine(line)?.text, 'Ship it [notion]($url)');
      expect(itemWords('- [ ] Ship it §§ ^ship-it'), 'Ship it');
      expect(cardText('Ship it §§'), 'Ship it');
      expect(anchorFor('Ship the page §§', []), 'ship-page');
      // Two section signs in the middle of words are words.
      expect(itemWords('- See §§12 ^see'), 'See §§12');
    });
  });

  group('a card’s box is the box the note draws (core/itemSyntax.ts)', () {
    test('has no box when the brackets are glued to the words, since the editor draws none there to tick', () {
      expect(itemOnLine('- [ ]Ship it ^ship'), const Item(id: 'ship', text: '[ ]Ship it', done: null, line: 0));
      expect(setItemDone('- [ ]Ship it ^ship', true), '- [ ]Ship it ^ship');
    });

    test('reads a link whose words are "x" as the link it is, not as a ticked box', () {
      expect(itemOnLine('- [x](https://example.com/x) ^x-link'), const Item(id: 'x-link', text: '[x](https://example.com/x)', done: null, line: 0));
    });

    test('is no item at all for an empty choice, as an empty to-do is none', () {
      expect(isItemLine('- ( )'), false);
      expect(isItemLine('- [ ]'), false);
      expect(isItemLine('- ( ) Tent'), true);
    });

    test('puts the caret after an empty choice’s box, as it does after a to-do’s', () {
      expect(wordsEnd('- ( ) ^pick'), '- ( ) '.length);
    });
  });
}
