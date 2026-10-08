// How a finished line finds its place (lib/ai/landing.dart). A port of `src/app/ai/landing.test.ts`, case for case.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/landing.dart';

void main() {
  group('a line as words', () {
    test('keeps the space before each word and leaves trailing space to nobody', () {
      expect(tokens('  a  bc '), const [Token(lead: '  ', word: 'a'), Token(lead: '  ', word: 'bc')]);
      expect(tokens(''), isEmpty);
    });
  });

  group('two lines word by word', () {
    test('marks only the words that differ, and joins the rest back to the new line', () {
      final segments = wordDiff('- call the plumber thursday', '- [ ] Call the plumber on **Thursday**.');
      expect(segments.where((s) => s.kind != SegmentKind.removed).map((s) => s.text).join(), '- [ ] Call the plumber on **Thursday**.');
      expect([for (final s in segments) if (s.kind == SegmentKind.removed) s.text.trim()], ['call', 'thursday']);
      expect([for (final s in segments) if (s.kind == SegmentKind.added) s.text.trim()], ['[ ] Call', 'on **Thursday**.']);
    });

    test('is all the same for the same line, and all added for a line from nothing', () {
      expect(wordDiff('a b c', 'a b c'), const [DiffSegment(kind: SegmentKind.same, text: 'a b c')]);
      expect(wordDiff('', 'a b'), const [DiffSegment(kind: SegmentKind.added, text: 'a b')]);
      expect(wordDiff('a b', ''), const [DiffSegment(kind: SegmentKind.removed, text: 'a b')]);
    });

    test('rides the new line’s trailing space on its last piece', () {
      expect(wordDiff('a b', 'a b  '), const [DiffSegment(kind: SegmentKind.same, text: 'a b  ')]);
    });
  });

  group('whether a line is another rewritten', () {
    test('is, with half the words shared and at least two', () {
      expect(similar('call the plumber about the tap', '- [ ] Call the plumber about the leaking tap.'), isTrue);
      expect(similar('eggs and coffee', 'Pick up eggs and coffee on the way home.'), isFalse);
      expect(similar('trip', '# Trip'), isTrue);
      expect(similar('# Trip', '# Trip to Bath'), isFalse);
      expect(similar('line 0', 'line 11'), isFalse);
      expect(similar('# Trip', '# Plans'), isFalse);
      expect(similar('', 'words'), isFalse);
    });
  });

  group('where a finished line belongs', () {
    const old = ['# trip', '', 'call the plumber', 'eggs and coffee', '', 'notes'];

    test('keeps an old line that is the same, dropping the ones before it', () {
      expect(matchLine(old, '# trip'), const LineMatch.keep(0));
      expect(matchLine(old, 'eggs and coffee'), const LineMatch.keep(3));
      expect(matchLine(old, 'notes  '), const LineMatch.keep(5));
    });

    test('rewrites a line that is nearly the same, and adds one that is new', () {
      expect(matchLine(old, '- [ ] Call the plumber.'), const LineMatch.replace(2));
      expect(matchLine(old, '## Errands'), const LineMatch.insert());
    });

    test('looks for a blank line only at the very next line', () {
      expect(matchLine(old, ''), const LineMatch.insert());
      expect(matchLine(old.sublist(1), ''), const LineMatch.keep(0));
    });

    test('does not look too far ahead', () {
      final far = [for (var i = 0; i < 12; i += 1) 'line $i'];
      expect(matchLine(far, 'line 11'), const LineMatch.insert());
      expect(matchLine(far, 'line 7'), const LineMatch.keep(7));
    });
  });
}
