import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/chapter_number.dart';

/// A chapter number in a title (lib/book/chapter_number.dart), case for case with the web's
/// `book/chapterNumber.test.ts`.
ChapterNumber n(int number, String name) => ChapterNumber(number: number, name: name);

void main() {
  group('a chapter number in a title', () {
    test('reads the standard at the end: Ch. or Chapter, an Arabic or Roman number, after a mark or in brackets', () {
      expect(chapterOf('The risks, and a glossary · Ch. 8'), n(8, 'The risks, and a glossary'));
      expect(chapterOf('The risks (Chapter 8)'), n(8, 'The risks'));
      expect(chapterOf('The risks — chapter VIII'), n(8, 'The risks'));
      expect(chapterOf('The risks, Ch 12'), n(12, 'The risks'));
      expect(chapterOf('The risks [ch. iv]'), n(4, 'The risks'));
    });

    test('reads a number written in front, the way many chapters already are', () {
      expect(chapterOf('08 · The risks, and a glossary'), n(8, 'The risks, and a glossary'));
      expect(chapterOf('Chapter 3: Getting there'), n(3, 'Getting there'));
      expect(chapterOf('Ch. XII · The end'), n(12, 'The end'));
    });

    test('leaves titles alone that only end in a number or a word like one', () {
      expect(chapterOf('Top 10'), isNull);
      expect(chapterOf('Batch 5'), isNull);
      expect(chapterOf('Chapter mix: songs'), isNull);
      expect(chapterOf('Packing (shared 2)'), isNull);
      expect(chapterOf('2026 plans'), isNull);
      expect(chapterOf('Task Management'), isNull);
    });

    test('reads § as the word for a chapter, and numbers to three places, but not four', () {
      expect(chapterOf('Notes § 4'), n(4, 'Notes'));
      expect(chapterOf('§ 3 · Rules'), n(3, 'Rules'));
      expect(chapterOf('The end · Ch. 120'), n(120, 'The end'));
      expect(chapterOf('The end · Chapter C'), n(100, 'The end'));
      expect(chapterOf('The end · Ch. 1200'), isNull);
    });
  });
}
