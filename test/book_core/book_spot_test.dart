import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_spot.dart';
import 'package:ghost_md/core/book.dart' show bookNoteBody;
import 'package:ghost_md/core/stored.dart';

import '../core/make_note.dart';

/// Where a book was left: kept and read back, what opening the book from outside goes to, and the read-through's
/// place as the chapter at the top of the page and how far into it. Case for case with the web's
/// `book/bookSpot.test.ts`; the read-through's cases are the same layouts given as the numbers the page measured
/// (lib/book/book_spot.dart says why).
final book = makeNote('book', body: bookNoteBody('Field guide', ['Introduction', 'Trees', 'Birds']));
final trees = makeNote('trees', body: '# Trees\n\nOaks and pines.');
final intro = makeNote('intro', body: '# Introduction\n\nWelcome.');
final notes = [book, intro, trees];

void main() {
  setUp(() => useStored(MemoryStored()));

  group('the spot a book was left at', () {
    test('is kept per book and read back, and a shape it does not know is no spot', () {
      expect(readBookSpot('book'), isNull);
      writeBookSpot('book', const ChapterSpot('Trees'));
      writeBookSpot('other', const ReadingSpot('Oaks', 120));
      expect(readBookSpot('book'), const ChapterSpot('Trees'));
      expect(readBookSpot('other'), const ReadingSpot('Oaks', 120));
      stored.setItem('glyph-book-spots', jsonEncode({'book': {'kind': 'chapter'}, 'other': 'nonsense'}));
      expect(readBookSpot('book'), isNull);
      expect(readBookSpot('other'), isNull);
      stored.setItem('glyph-book-spots', 'not json');
      expect(readBookSpot('book'), isNull);
    });

    test('forgets the least recently read books past a hundred', () {
      for (var i = 0; i < 101; i += 1) {
        writeBookSpot('b$i', const IndexSpot(), now: 1000 + i);
      }
      expect(readBookSpot('b0'), isNull);
      expect(readBookSpot('b1'), const IndexSpot());
      expect(readBookSpot('b100'), const IndexSpot());
    });

    test('is kept as the page keeps it, under the page’s key', () {
      // Not a web case: the shape on the device is the web app's own, so one build reads the other's.
      writeBookSpot('book', const ReadingSpot('Trees', 40), now: 7);
      expect(jsonDecode(stored.getItem(bookSpotsKey)!), {
        'book': {'kind': 'reading', 'title': 'Trees', 'offset': 40, 'at': 7},
      });
    });
  });

  group('opening a book from outside it', () {
    test('goes to the chapter it was left in', () {
      writeBookSpot('book', const ChapterSpot('trees'));
      expect(whereLeft(book, notes, null), same(trees));
    });

    test('opens the book itself when it was left at its index or reading straight through, or never opened', () {
      expect(whereLeft(book, notes, null), same(book));
      writeBookSpot('book', const IndexSpot());
      expect(whereLeft(book, notes, null), same(book));
      writeBookSpot('book', const ReadingSpot('Trees', 40));
      expect(whereLeft(book, notes, null), same(book));
    });

    test('opens a journal on itself, where New entry is, whatever entry it was left at', () {
      final journal = makeNote('diary', body: '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[Trees]]\n');
      writeBookSpot('diary', const ChapterSpot('Trees'));
      expect(whereLeft(journal, [journal, trees], null), same(journal));
    });

    test('opens the index when the chapter is already on screen, since that is asking for the book', () {
      writeBookSpot('book', const ChapterSpot('Trees'));
      expect(whereLeft(book, notes, 'trees'), same(book));
      expect(whereLeft(book, notes, 'intro'), same(trees));
    });

    test('opens the index when the chapter has left the book, or its note is gone or archived', () {
      writeBookSpot('book', const ChapterSpot('Pines'));
      expect(whereLeft(book, [...notes, makeNote('pines', body: '# Pines')], null), same(book));
      writeBookSpot('book', const ChapterSpot('Birds'));
      expect(whereLeft(book, notes, null), same(book));
      writeBookSpot('book', const ChapterSpot('Trees'));
      expect(whereLeft(book, [book, trees.copyWith(archivedAt: () => 5)], null), same(book));
    });

    test('leaves a note that is not a book as it is', () {
      writeBookSpot('trees', const ChapterSpot('Introduction'));
      expect(whereLeft(trees, notes, null), same(trees));
    });
  });

  group('the read-through place', () {
    // A page whose top is at 100, over sections whose tops are where `tops` says, which move as it scrolls.
    const pageTop = 100.0;
    const tops = [150.0, 700.0, 1400.0];
    List<double> at(double scrollTop) => [for (final top in tops) top - scrollTop];
    const titles = ['Introduction', 'Trees', 'Birds'];

    test('is the chapter at the top of the page and how far into it', () {
      expect(readingPlaceOf(pageTop, at(0), titles), const ReadingSpot('Introduction', 0));
      expect(readingPlaceOf(pageTop, at(800), titles), const ReadingSpot('Trees', 200));
      expect(readingPlaceOf(pageTop, at(1300), titles), const ReadingSpot('Birds', 0));
    });

    test('scrolls back to the chapter by its title, the same distance into it', () {
      final by = readingScroll(pageTop, at(0), titles, 'trees', 200);
      expect(by, 800);
      expect(readingPlaceOf(pageTop, at(by!), titles), const ReadingSpot('Trees', 200));
      // A chapter the book no longer has is not somewhere to go.
      expect(readingScroll(pageTop, at(0), titles, 'Pines', 0), isNull);
    });
  });
}
