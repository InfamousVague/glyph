import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/syntax/language.dart';
import 'package:ghost_md/editor/syntax/lines.dart';
import 'package:ghost_md/editor/syntax/syntax.dart';

/// `src/app/editor/syntax.ts` and the text half of `lines.ts`: what a position is inside, and which lines are
/// outside fenced code. The web has no test file of its own for either; these say what their callers lean on
/// (tags.ts, counters.ts, sums.ts for the first, the whole-note readers for the second).
void main() {
  final glyph = glyphMarkdown(const [InlineFormat('Spoiler', '||')]);

  group('inQuietText', () {
    bool quiet(String doc, String needle) => inQuietText(glyph.parse(doc), doc.indexOf(needle));

    test('words in a paragraph, a heading, a list or a quote are not quiet', () {
      expect(quiet('A #tag here', '#tag'), isFalse);
      expect(quiet('# A #tag here', '#tag'), isFalse);
      expect(quiet('- [ ] A #tag here', '#tag'), isFalse);
      expect(quiet('> A #tag here', '#tag'), isFalse);
      expect(quiet('**bold #tag**', '#tag'), isFalse);
      expect(quiet('||hidden #tag||', '#tag'), isFalse);
    });

    test('code is quiet: a span, a fence, an indented block', () {
      expect(quiet('A `#tag` here', '#tag'), isTrue);
      expect(quiet('```\n#tag\n```', '#tag'), isTrue);
      expect(quiet('```js\n#tag\n```', 'js'), isTrue);
      expect(quiet('Words\n\n    #tag', '#tag'), isTrue);
    });

    test('an address is quiet, bare, in a link or in angle brackets', () {
      expect(quiet('See https://ghostmarkdown.com/#tag now', '#tag'), isTrue);
      expect(quiet('See [the page](https://ghostmarkdown.com/#tag) now', '#tag'), isTrue);
      expect(quiet('See <https://ghostmarkdown.com/#tag> now', '#tag'), isTrue);
      // The link's own words are words.
      expect(quiet('See [the #tag page](https://ghostmarkdown.com) now', '#tag'), isFalse);
    });

    test('HTML and a comment are quiet', () {
      expect(quiet('<div>\n#tag\n</div>', '#tag'), isTrue);
      expect(quiet('<!-- a #tag -->', '#tag'), isTrue);
      expect(quiet('Words <!-- a #tag --> more', '#tag'), isTrue);
      expect(quiet('Words <span class="#tag"> more', '#tag'), isTrue);
    });

    test('a position leans into what starts there', () {
      // The backtick opens the code, so the code's first position is already quiet; the one after it closes is not.
      const doc = 'a `b` c';
      final tree = glyph.parse(doc);
      expect(inQuietText(tree, 1), isFalse);
      expect(inQuietText(tree, 2), isTrue);
      expect(inQuietText(tree, 4), isTrue);
      expect(inQuietText(tree, 5), isFalse);
    });
  });

  group('enclosing', () {
    test('finds the nearest node of a kind, walking out, and leans as it is told', () {
      const doc = 'Pack **warm *wool*** things';
      final tree = glyph.parse(doc);
      final at = doc.indexOf('wool');
      expect(enclosing(tree, at, (name) => name == 'Emphasis')!.from, doc.indexOf('*wool'));
      expect(enclosing(tree, at, (name) => name == 'StrongEmphasis')!.from, doc.indexOf('**warm'));
      expect(enclosing(tree, at, (name) => name == 'Blockquote'), isNull);
      // Just after the closing run: leaning back it is still inside the bold, leaning forward it is not.
      final end = doc.indexOf(' things');
      expect(enclosing(tree, end, (name) => name == 'StrongEmphasis'), isNotNull);
      expect(enclosing(tree, end, (name) => name == 'StrongEmphasis', 1), isNull);
    });
  });

  group('the lines outside fenced code', () {
    const doc = 'one\n```js\ntwo\n~~~\nthree\n```\nfour\n  ~~~\nfive\n~~~\n';

    List<String> outside(String text) {
      final seen = <String>[];
      forEachLineOutsideFences(text, (line) => seen.add('${line.number}:${line.text}'));
      return seen;
    }

    test('are every line but the fences and what is between them', () {
      // A fence closes on the marker it opened with, so the `~~~` inside the ``` block is the block's words; an
      // indented fence is a fence; and the last line of a note that ends in a line break is an empty one.
      expect(outside(doc), ['1:one', '7:four', '11:']);
      expect(outside(''), ['1:']);
      expect(outside('```\nnever closed\nstill code'), isEmpty);
    });

    test('inFence says the same of a line by its number', () {
      final skipped = [for (var n = 1; n <= 11; n++) if (inFence(doc, n)) n];
      expect(skipped, [2, 3, 4, 5, 6, 8, 9, 10]);
      expect(inFence(doc, 0), isFalse);
      expect(inFence(doc, 99), isFalse);
    });

    test('a line is where it is in the note, in UTF-16 code units', () {
      final lines = <TextLine>[];
      forEachLine('a🔥\n\nlast', lines.add);
      expect(lines.map((line) => '${line.number} ${line.from}-${line.to} "${line.text}"'), ['1 0-3 "a🔥"', '2 4-4 ""', '3 5-9 "last"']);
      expect(lines.first.length, 3);
      // A visit that answers false stops the walk.
      var visited = 0;
      forEachLine('a\nb\nc', (line) => ++visited < 2);
      expect(visited, 2);
    });
  });
}
