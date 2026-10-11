import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/item_links.dart';

/// List items and their marks (lib/core/item_links.dart), case for case with the web's `core/itemLinks.test.ts`.
void main() {
  group('list items for Notion', () {
    final body = [
      '# AttackFM',
      '',
      '- [ ] Fix the login bug',
      '- [x] Ship 0.6.9',
      '- [ ] Pins in the list [notion](https://www.notion.so/attackfm/Pins-1a2b3c)',
      '- [ ] [Old style link](https://www.notion.so/attackfm/Old-4d5e6f)',
      '- Radio idea',
      '1. First step',
      'Not an item.',
      '- ![](image/a.jpg)',
    ].join('\n');

    test('finds the items that are not sent yet, skipping done and linked ones of either form', () {
      expect(unsentItems(body), [
        const Item(line: 3, text: 'Fix the login bug'),
        const Item(line: 7, text: 'Radio idea'),
        const Item(line: 8, text: 'First step'),
      ]);
    });

    test('marks an item at its end and keeps its marker and its words', () {
      expect(linkedLine('- [ ] Fix the login bug', 'https://www.notion.so/x-1'), '- [ ] Fix the login bug [notion](https://www.notion.so/x-1)');
      expect(linkedLine('  2) Brackets [out]', 'https://n.so/y'), '  2) Brackets [out] [notion](https://n.so/y)');
      registerMarkName('github');
      expect(linkedLine('- Call Sam', 'https://github.com/i/1', 'github'), '- Call Sam [github](https://github.com/i/1)');
      // Marking a marked item replaces the mark rather than stacking two.
      expect(linkedLine('- [ ] Buy milk [notion](https://n.so/a)', 'https://n.so/b'), '- [ ] Buy milk [notion](https://n.so/b)');
    });

    test('reads a mark back, and the words without it', () {
      expect(markOf('Buy milk [notion](https://n.so/a)'), const ItemMark(name: 'notion', url: 'https://n.so/a'));
      expect(markOf('Buy milk'), isNull);
      expect(markOf('[Buy milk](https://n.so/a)'), isNull);
      // A one-word link at the end is only a mark when the word is a plugin's name.
      expect(markOf('read the [docs](https://n.so/d)'), isNull);
      expect(unmarked('read the [docs](https://n.so/d)'), 'read the [docs](https://n.so/d)');
      expect(unmarked('Buy milk [notion](https://n.so/a)  '), 'Buy milk');
      expect(itemWords('- [ ] Buy milk [notion](https://n.so/a)'), 'Buy milk');
      expect(itemWords('Just words'), isNull);
    });

    test('answers for one line', () {
      expect(itemAt('- [ ] Call Sam', 4), const Item(line: 4, text: 'Call Sam'));
      expect(itemAt('Just words', 4), isNull);
      expect(itemAt('- [ ] Call Sam [notion](https://n.so/a)', 4), isNull);
    });

    test('links one line of a note, leaving the rest as it was', () {
      // plugins/sendItems.ts links each sent item's line this way.
      const noteBody = '# Trip\n\n- [ ] Book the cabin\n- [ ] Pack snacks\n';
      const line = '- [ ] Book the cabin';
      expect(noteBody.replaceFirst(line, linkedLine(line, 'https://n.so/a')), '# Trip\n\n- [ ] Book the cabin [notion](https://n.so/a)\n- [ ] Pack snacks\n');
    });
  });

  group('an item a board names', () {
    const url = 'https://app.notion.com/p/Add-task-input-3dd5';

    test('sends what the item says, never the anchor', () {
      const body = '- [ ] Add task input and button dont match up ^add-task-input\n- ^only-a-name';
      expect(unsentItems(body), [const Item(line: 1, text: 'Add task input and button dont match up')]);
      expect(itemWords('- [ ] Add task input ^add-task-input'), 'Add task input');
      expect(itemAt('- [ ] Add task input ^add-task-input', 4), const Item(line: 4, text: 'Add task input'));
    });

    test('writes the mark before the anchor, so the anchor still ends the line', () {
      expect(linkedLine('- [ ] Add task input ^add-task-input', url), '- [ ] Add task input [notion]($url) ^add-task-input');
      expect(linkedLine('  - Ask Sam ^ask-sam', url, 'github'), '  - Ask Sam [github]($url) ^ask-sam');
      // Linked again, the old mark is replaced and the anchor stays last.
      expect(linkedLine('- [ ] Add task input [notion]($url) ^add-task-input', 'https://app.notion.com/p/new'), 
        '- [ ] Add task input [notion](https://app.notion.com/p/new) ^add-task-input',
      );
    });

    test('reads the mark with an anchor after it, and keeps the anchor when the mark comes off', () {
      const line = 'Add task input [notion]($url) ^add-task-input';
      expect(markOf(line), const ItemMark(name: 'notion', url: url));
      expect(unmarked(line), 'Add task input ^add-task-input');
      expect(itemWords('- [ ] $line'), 'Add task input');
      // A caret that is a superscript is not an anchor, and does not hide a mark before it.
      expect(markOf('E = mc^2^ [notion]($url)'), const ItemMark(name: 'notion', url: url));
      expect(unmarked('E = mc^2^'), 'E = mc^2^');
    });

    test('is not linked twice when its mark sits before its anchor', () {
      expect(unsentItems('- [ ] Add task input [notion]($url) ^add-task-input'), isEmpty);
    });

    test('puts a mark back before the anchor', () {
      expect(withMark('- [ ] Ship it ^ship-it', '[notion]($url)'), '- [ ] Ship it [notion]($url) ^ship-it');
      expect(withMark('- [ ] Ship it', '[notion]($url)'), '- [ ] Ship it [notion]($url)');
    });
  });

  group('a choice or a counter on an item', () {
    const url = 'https://app.notion.com/p/Pack-3dd5';

    test('sends what the item says: no choice box, no counter', () {
      expect(itemWords('- ( ) Pick the red one'), 'Pick the red one');
      expect(itemWords('- (x) Pick the blue one ^blue'), 'Pick the blue one');
      expect(itemWords('- [ ] Pack socks [3/8] ^pack-socks'), 'Pack socks');
      expect(itemWords('1. ( ) Numbered, so words'), '( ) Numbered, so words');
      expect(unsentItems('- ( ) Pick red\n- [ ] Pack socks [3/8]'), [
        const Item(line: 1, text: 'Pick red'),
        const Item(line: 2, text: 'Pack socks'),
      ]);
    });

    test('keeps the box and the counter in the line when the mark goes on, and the mark before them at the end', () {
      expect(linkedLine('- ( ) Pick red', url), '- ( ) Pick red [notion]($url)');
      expect(linkedLine('- [ ] Pack socks ^pack-socks [3/8]', url), '- [ ] Pack socks [notion]($url) ^pack-socks [3/8]');
      // The sent item is found again by what it says, box and counter aside.
      expect(itemAt('- [ ] Pack socks [3/8]', 5), const Item(line: 5, text: 'Pack socks'));
    });

    test('reads the mark with a counter typed after it, and does not send the item again', () {
      const line = '- [ ] Pack socks [notion]($url) [4/8]';
      expect(markOf(line), const ItemMark(name: 'notion', url: url));
      expect(unmarked('Pack socks [notion]($url) [4/8] ^pack-socks'), 'Pack socks [4/8] ^pack-socks');
      expect(unsentItems(line), isEmpty);
      expect(withMark('- [ ] Pack socks [4/8]', '[notion]($url)'), '- [ ] Pack socks [notion]($url) [4/8]');
    });

    test('never sends the bookmark as part of a title, and puts the mark after it', () {
      expect(itemWords('- [ ] Pack socks §§ ^pack-socks'), 'Pack socks');
      expect(unsentItems('- [ ] Pack socks §§'), [const Item(line: 1, text: 'Pack socks')]);
      expect(linkedLine('- [ ] Pack socks §§ ^pack-socks', url), '- [ ] Pack socks §§ [notion]($url) ^pack-socks');
      expect(markOf('- [ ] Pack socks §§ [notion]($url) ^pack-socks'), const ItemMark(name: 'notion', url: url));
    });
  });

  group('the same line read the same way everywhere (core/itemSyntax.ts)', () {
    test('leaves a ticked to-do alone after any marker, not only after a dash', () {
      // It was offered to Notion as a task called "[x] Done thing": the box was read only after '- '.
      expect(unsentItems('* [x] Done thing\n+ [X] Also done\n1. [x] Done step\n- [x] Done'), isEmpty);
      expect(itemWords('* [x] Done thing'), 'Done thing');
      expect(itemWords('1. [ ] Call the plumber'), 'Call the plumber');
    });

    test('sends a starred or numbered to-do by its words, box off', () {
      expect(unsentItems('* [ ] Buy milk\n2) [ ] Book the cabin'), [
        const Item(line: 1, text: 'Buy milk'),
        const Item(line: 2, text: 'Book the cabin'),
      ]);
      expect(linkedLine('* [ ] Buy milk', 'https://n.so/m'), '* [ ] Buy milk [notion](https://n.so/m)');
    });

    test('takes the space after a marker as any run of spaces', () {
      expect(unsentItems('-  [ ] Two spaces\n-\tA tab'), [
        const Item(line: 1, text: 'Two spaces'),
        const Item(line: 2, text: 'A tab'),
      ]);
    });

    test('never sends an empty box as a task called "[ ]"', () {
      expect(unsentItems('- [ ]\n- [x]'), isEmpty);
    });

    test('reads a list numbered past 999, as the editor does', () {
      expect(unsentItems('1000. The thousandth thing'), [const Item(line: 1, text: 'The thousandth thing')]);
    });

    test('puts one space before the mark on an item with no words yet', () {
      expect(linkedLine('- ^only-a-name', 'https://n.so/a'), '- [notion](https://n.so/a) ^only-a-name');
      expect(linkedLine('- ( ) ^pick', 'https://n.so/a'), '- ( ) [notion](https://n.so/a) ^pick');
    });
  });

  group('an item with fields (core/taskFields.ts, docs/DESIGN.md §158)', () {
    const line = '- [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03';

    test('is sent by its words, without its person, priority or day, and keeps its tags', () {
      expect(unsentItems(line), [const Item(line: 1, text: 'Fix the login loop #bug')]);
      expect(itemWords('$line [notion](https://n.so/a) ^login'), 'Fix the login loop #bug');
    });

    test('keeps every field in the line when the mark goes on, the mark after them', () {
      expect(linkedLine(line, 'https://n.so/a'), '$line [notion](https://n.so/a)');
      expect(markOf('$line [notion](https://n.so/a)'), const ItemMark(name: 'notion', url: 'https://n.so/a'));
    });

    test('is not a task while it is only fields', () {
      expect(unsentItems('- [ ] 📅 2026-10-03 @sam'), isEmpty);
    });
  });

  group('an item the AI filled, or one still asking (docs/DESIGN.md §145)', () {
    const filled = '- [ ] ??Turn off the water and fit the new washer??(Qwen3.5 4B from memory, 2026-09-28. Asked: the next step)';

    test('is sent as its answer’s words, never the bracket', () {
      expect(unsentItems(filled), [const Item(line: 1, text: 'Turn off the water and fit the new washer')]);
      expect(itemWords(filled), 'Turn off the water and fit the new washer');
    });

    test('is not sent while it holds a blank, and reads as its question', () {
      expect(unsentItems('- [ ] {?the next step}\n- [ ] Call Sam'), [const Item(line: 2, text: 'Call Sam')]);
      expect(itemWords('- [ ] {?the next step}'), 'the next step');
    });

    test('keeps a person’s own note on a doubt, as written', () {
      expect(itemWords('- [ ] Pay ??400??(check with Sam)'), 'Pay ??400??(check with Sam)');
    });
  });
}
