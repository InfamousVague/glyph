import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/item_syntax.dart';

/// A list item's grammar (lib/core/item_syntax.dart), case for case with the web's `core/itemSyntax.test.ts`.
///
/// "One grammar means a line is a to-do everywhere or nowhere" (itemSyntax.ts). These are the lines the copies used
/// to disagree about, read once, so a change to the grammar shows up here before it shows up as a box that stopped
/// ticking.

/// A lead's fields by name, for the web's `toMatchObject`: only the names a case gives are compared.
void expectLead(String line, {String? indent, String? marker, Object? done = _unset, Object? picked = _unset, int? boxAt, int? wordsAt}) {
  final lead = listLead(line);
  expect(lead, isNotNull, reason: line);
  if (indent != null) expect(lead!.indent, indent, reason: line);
  if (marker != null) expect(lead!.marker, marker, reason: line);
  if (!identical(done, _unset)) expect(lead!.done, done, reason: line);
  if (!identical(picked, _unset)) expect(lead!.picked, picked, reason: line);
  if (boxAt != null) expect(lead!.boxAt, boxAt, reason: line);
  if (wordsAt != null) expect(lead!.wordsAt, wordsAt, reason: line);
}

const Object _unset = Object();

void main() {
  group('what opens a list item', () {
    test('reads every marker: a dash, a star, a plus, a number with a dot or a bracket', () {
      for (final (line, marker) in [('- Milk', '-'), ('* Milk', '*'), ('+ Milk', '+'), ('1. Milk', '1.'), ('12) Milk', '12)'), ('1234. Milk', '1234.')]) {
        expectLead(line, marker: marker, done: null, picked: null, boxAt: -1, wordsAt: marker.length + 1);
      }
    });

    test('takes any run of spaces or tabs after the marker, and the indent before it', () {
      expectLead('-  Milk', indent: '', wordsAt: 3);
      expectLead('-\tMilk', wordsAt: 2);
      expectLead('    * Milk', indent: '    ', marker: '*', wordsAt: 6);
      expectLead('\t1. Milk', indent: '\t', marker: '1.');
    });

    test('is not fooled by what only looks like a list', () {
      for (final line in ['Milk', '-Milk', '1.Milk', '#1. Milk', '-', '', '[ ] Milk', '(x) Milk', '1.5 litres']) {
        expect(listLead(line), isNull, reason: line);
      }
    });

    test('reads a to-do box after any marker, ticked or not, and the words after it', () {
      expectLead('- [ ] Milk', done: false, boxAt: 2, wordsAt: 6);
      expectLead('* [x] Milk', done: true, boxAt: 2, wordsAt: 6);
      expectLead('+ [X] Milk', done: true);
      expectLead('3. [x] Milk', done: true, boxAt: 3, wordsAt: 7);
      expectLead('-  [ ]  Milk', done: false, boxAt: 3, wordsAt: 7);
      // An empty to-do is still one: the box is what is being typed.
      expectLead('- [ ]', done: false, wordsAt: 5);
    });

    test('takes a box glued to its words, or a link whose words are x, as words: the editor draws no box there', () {
      expectLead('- [ ]Milk', done: null, boxAt: -1, wordsAt: 2);
      expectLead('- [x](https://example.com/x)', done: null, wordsAt: 2);
      expectLead('- [xx] Milk', done: null);
    });

    test('reads a choice after a bullet, never after a number, and never as a tick', () {
      expectLead('- ( ) Tent', done: null, picked: false, boxAt: 2, wordsAt: 6);
      expectLead('*  (X) Cabin', picked: true, boxAt: 3, wordsAt: 7);
      expectLead('- ( )', picked: false, wordsAt: 5);
      expectLead('1. ( ) Tent', done: null, picked: null, boxAt: -1, wordsAt: 3);
      expectLead('- ( )Tent', picked: null, wordsAt: 2);
      // A box and then a choice is a to-do whose words start with brackets.
      expectLead('- [ ] ( ) Tent', done: false, picked: null, wordsAt: 6);
    });

    test('says where the box is and whether it is ticked, for the lines that have one', () {
      expect(taskBox('  1. [x] Bins'), (at: 5, done: true));
      expect(taskBox('- [ ] Milk'), (at: 2, done: false));
      expect(taskBox('- ( ) Tent'), isNull);
      expect(taskBox('- Milk'), isNull);
      expect(taskBox('- [ ]Milk'), isNull);
    });

    test('says a line back without its lead, and any other line as it is', () {
      expect(withoutLead('- [ ] Buy milk'), 'Buy milk');
      expect(withoutLead('* [x] Buy milk'), 'Buy milk');
      expect(withoutLead('1. [ ] Buy milk'), 'Buy milk');
      expect(withoutLead('  -  Buy milk'), 'Buy milk');
      expect(withoutLead('- ( ) Tent'), 'Tent');
      expect(withoutLead('The login is broken.'), 'The login is broken.');
    });
  });

  group('what ends an item line', () {
    test('finds the anchor last on the line, or with marks and counters after it', () {
      expect(anchorSpan('- [ ] Ship it ^ship-it'), (id: 'ship-it', from: 14, to: 22));
      expect(anchorSpan('- [ ] Ship it ^ship [notion](https://n.so/a)'), (id: 'ship', from: 14, to: 19));
      expect(anchorSpan('- Water [3/8] ^water [1/2]  '), (id: 'water', from: 14, to: 20));
      expect(anchorSpan('^first'), (id: 'first', from: 0, to: 6));
    });

    test('leaves superscripts, glued carets and anchors with words after them alone', () {
      for (final text in ['- E = mc^2^', '- the 2 ^nd^ of June', '- Ship it^ship', '- ^ship then words', '- Ship ^Ship', '- Ship ^-ship']) {
        expect(anchorSpan(text), isNull, reason: text);
      }
    });

    test('takes the anchor and the one space before it off, and nothing else', () {
      expect(withoutAnchor('- [ ] Ship it ^ship'), '- [ ] Ship it');
      expect(withoutAnchor('- [ ] Ship it ^ship [notion](https://n.so/a)'), '- [ ] Ship it [notion](https://n.so/a)');
      expect(withoutAnchor('- [ ] Ship it ^ship   '), '- [ ] Ship it');
      expect(withoutAnchor('^ship'), '');
      expect(withoutAnchor('- E = mc^2^'), '- E = mc^2^');
    });

    test('takes the bookmark out only where it stands as a word', () {
      expect(withoutBookmark('- [ ] Ship it §§ [notion](https://n.so/a) ^ship'), '- [ ] Ship it [notion](https://n.so/a) ^ship');
      expect(withoutBookmark('The deposit is four hundred. §§'), 'The deposit is four hundred.');
      expect(withoutBookmark('section §§5'), 'section §§5');
    });

    test('knows where the words end: before the bookmark, the mark, the counters and the anchor', () {
      const line = '- [ ] Ship it §§ [notion](https://n.so/a) [3/8] ^ship';
      expect(line.substring(0, wordsEnd(line)), '- [ ] Ship it');
      expect(wordsEnd('Just a line  '), 11);
      // An empty to-do or choice ends after its box, where the words would start.
      expect(wordsEnd('- [ ] ^ship'), 6);
      expect(wordsEnd('- ( ) ^pick'), 6);
    });

    test('knows what may follow a mark: nothing, or anchors and counters', () {
      expect(afterMark.hasMatch(''), isTrue);
      expect(afterMark.hasMatch(' ^ship [3/8]  '), isTrue);
      expect(afterMark.hasMatch(' and more words'), isFalse);
      expect(afterMark.hasMatch('^ship'), isFalse);
    });

    test('finds a counter in words, never a link, a picture or a footnote', () {
      List<String> counters(String text) => [for (final found in RegExp(counterInWordsPattern).allMatches(text)) found.group(0)!];
      expect(counters('Water [3/8] and push-ups [0/50]'), ['[3/8]', '[0/50]']);
      expect(counters('see [3/8](https://a.b) or ![1/2] or note[1/2]'), isEmpty);
    });
  });

  group('the words on a line', () {
    test('are nothing on a line that is only a lead: a bullet, a number, a box, a choice or a quote', () {
      for (final line in ['', '   ', '- ', '* ', '- [ ] ', '- [ ]', '- [x] ', '3. ', '12) ', '- ( ) ', '> ', '>', '> > ', '> - [ ] ', '  - [ ] ']) {
        expect(lineWords(line), '', reason: '"$line"');
      }
    });

    test('are nothing on a lead that carries only the bookmark, or only an anchor', () {
      expect(lineWords('- §§'), '');
      expect(lineWords('- [ ] §§'), '');
      expect(lineWords('- [ ] ^anchor'), '');
    });

    test('are the words, without the lead, the bookmark or the anchor', () {
      expect(lineWords('- [ ] Buy milk ^milk'), 'Buy milk');
      expect(lineWords('> - [ ] Buy milk §§'), 'Buy milk');
      expect(lineWords('Lunch at the harbour'), 'Lunch at the harbour');
      expect(lineWords('3. Unplug it'), 'Unplug it');
    });

    test('keep what is not a lead: a heading’s mark, a dash with no space, a callout', () {
      expect(lineWords('# '), '#');
      expect(lineWords('-'), '-');
      expect(lineWords('> [!NOTE]'), '[!NOTE]');
    });
  });

  group('the lane a tick belongs in', () {
    test('is a lane whose name starts or ends with Done, in any case', () {
      for (final name in ['Done', 'done', ' DONE ', 'Done this week', 'All done']) {
        expect(isDoneName(name), isTrue, reason: name);
      }
      for (final name in ['Doing', 'Undone work', 'Donut', 'Finished', '']) {
        expect(isDoneName(name), isFalse, reason: name);
      }
    });
  });
}
