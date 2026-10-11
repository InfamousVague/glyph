// A port of src/app/format/links.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/format/links.dart';

const notion = 'https://www.notion.so/attackfm/Buy-milk-1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d';

void main() {
  group('links through the model', () {
    test('swaps a Notion link in a list item for a token and puts it back when the token is copied', () {
      const note = '- [ ] [Buy milk]($notion) on the way home\n- [ ] Call the plumber\n';
      final guarded = protectLinks(note);
      expect(guarded.text, '- [ ] [Buy milk](link-1) on the way home\n- [ ] Call the plumber\n');
      expect(guarded.links, hasLength(1));
      expect((guarded.links[0].token, guarded.links[0].text, guarded.links[0].url), ('link-1', 'Buy milk', notion));

      const rewrite = '# Errands\n\n- [ ] [Buy milk](link-1) on the way home.\n- [ ] Call the plumber.\n';
      expect(restoreLinks(rewrite, guarded.links), '# Errands\n\n- [ ] [Buy milk]($notion) on the way home.\n- [ ] Call the plumber.\n');
    });

    test('keeps the words the model chose around a token, and takes a token written loosely', () {
      final links = protectLinks('see [the task]($notion)').links;
      expect(restoreLinks('See [the Notion task] (link 1).', links), 'See [the Notion task]($notion).');
      expect(restoreLinks('See <link-1>.', links), 'See [the task]($notion).');
      expect(restoreLinks('See link-1.', links), 'See [the task]($notion).');
    });

    test('makes the words the link again when the token was dropped but the words survived', () {
      final links = protectLinks('- [ ] [Buy milk]($notion) today').links;
      expect(restoreLinks('- [ ] Buy milk today.\n', links), '- [ ] [Buy milk]($notion) today.\n');
      // Case is the model's; the words are still found.
      expect(restoreLinks('- [ ] buy milk today.\n', links), '- [ ] [buy milk]($notion) today.\n');
    });

    test('adds a link whose token and words both vanished at the end of the note', () {
      const note = 'Ring the dentist. Details at https://example.com/dentist, and [the board]($notion).';
      final guarded = protectLinks(note);
      expect(guarded.text, 'Ring the dentist. Details at <link-2>, and [the board](link-1).');
      expect(restoreLinks('# Dentist\n\n- [ ] Ring the dentist.\n', guarded.links), '# Dentist\n\n- [ ] Ring the dentist.\n\n[the board]($notion)\nhttps://example.com/dentist\n');
    });

    test('keeps an autolink and a bare address as they were written', () {
      final guarded = protectLinks('Read <https://a.example/x> then https://b.example/y.');
      expect(guarded.text, 'Read <link-1> then <link-2>.');
      expect(restoreLinks('Read <link-1>, then <link-2>.', guarded.links), 'Read <https://a.example/x>, then https://b.example/y.');
    });

    test('tells link-1 from link-10', () {
      final many = List.generate(10, (i) => 'https://example.com/${i + 1}').join(' ');
      final guarded = protectLinks(many);
      expect(guarded.text.endsWith('<link-10>'), isTrue);
      final back = restoreLinks(guarded.text, guarded.links);
      expect(back, many);
    });

    test('leaves pictures alone', () {
      const note = '![](image/abc.jpg)\n\nA picture of the sign.';
      expect(protectLinks(note), const Protected(text: note, links: []));
    });

    test('only substitutes while the rewrite is still streaming', () {
      final links = protectLinks('[the board]($notion) and https://example.com/more').links;
      expect(restoreLinks('# Board\n\n- The board and', links, isFinal: false), '# Board\n\n- The board and');
      expect(restoreLinks('- [the board](link-1) and <link-2>', links, isFinal: false), '- [the board]($notion) and https://example.com/more');
    });
  });

  group('item marks through the model', () {
    const url = 'https://www.notion.so/attackfm/Buy-milk-1a2b3c4d';
    const note = '# Errands\n\n- [ ] Buy milk on the way home [notion]($url)\n- [ ] Call the plumber\n';

    test('remembers the item a mark belongs to, and keeps a mark the model copied', () {
      final guarded = protectLinks(note);
      expect(guarded.text, '# Errands\n\n- [ ] Buy milk on the way home [notion](link-1)\n- [ ] Call the plumber\n');
      expect((guarded.links[0].token, guarded.links[0].text, guarded.links[0].item), ('link-1', 'notion', 'Buy milk on the way home'));
      expect(
        restoreLinks('# Errands\n\n- [ ] Buy milk on the way home. [notion](link-1)\n- [ ] Call the plumber.\n', guarded.links),
        '# Errands\n\n- [ ] Buy milk on the way home. [notion]($url)\n- [ ] Call the plumber.\n',
      );
    });

    test('puts a lost mark back on the item it came from, found by its words', () {
      final links = protectLinks(note).links;
      const rewrite = '# Errands\n\n- [ ] Call the plumber about the tap.\n- [ ] **Buy milk** on the way home.\n';
      expect(restoreLinks(rewrite, links), '# Errands\n\n- [ ] Call the plumber about the tap.\n- [ ] **Buy milk** on the way home. [notion]($url)\n');
    });

    test('adds a lost mark at the end when no item is left that matches its words', () {
      final links = protectLinks(note).links;
      expect(restoreLinks('# Errands\n\n- [ ] Call the plumber.\n', links), '# Errands\n\n- [ ] Call the plumber.\n\n[notion]($url)\n');
    });

    test('does not take an ordinary link at the end of an item for a mark', () {
      final links = protectLinks('- [ ] read [the board](https://www.notion.so/b)\n').links;
      expect(links[0].item, isNull);
    });
  });

  group('a mark on an item a board names', () {
    test('counts as the item’s mark with the anchor after it, and goes back in before the anchor when lost', () {
      const note = '- [ ] Buy milk [notion]($notion) ^buy-milk\n';
      final links = protectLinks(note).links;
      expect(links[0].item, 'Buy milk');
      // The model dropped the mark and kept the rest: it goes back where a mark goes, before the anchor.
      expect(restoreLinks('- [ ] Buy milk ^buy-milk\n', links, isFinal: true), '- [ ] Buy milk [notion]($notion) ^buy-milk\n');
    });
  });

  group('blanks and their answers through a rewrite (docs/DESIGN.md §145)', () {
    const fill = '??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)';
    const note = 'flights are cheapest on $fill and the capital is {?which city}\n';

    test('go in as tokens and come back whole, whatever words the model gave them', () {
      final guarded = protectLinks(note);
      expect(guarded.text, 'flights are cheapest on [midweek](link-1) and the capital is [which city](link-2)\n');
      expect(guarded.links.map((l) => l.kind), [LinkKind.filled, LinkKind.blank]);
      const rewritten = 'Flights are cheapest on [Tuesday](link-1), and the capital is [Canberra](link-2).\n';
      expect(restoreLinks(rewritten, guarded.links), 'Flights are cheapest on $fill, and the capital is {?which city}.\n');
    });

    test('put a lost one at the end on its own line, and let a summary leave it out', () {
      final links = protectLinks(note).links;
      expect(restoreLinks('Flights are cheapest midweek.\n', links), 'Flights are cheapest midweek.\n\n$fill\n{?which city}\n');
      expect(restoreLinks('Flights are cheapest midweek.\n', links, isFinal: true, lostBlanks: false), 'Flights are cheapest midweek.\n');
    });

    test('stay as they are for the fill’s own message, which turns this off', () {
      expect(protectLinks(note, blanks: false).text, note);
    });
  });
}
