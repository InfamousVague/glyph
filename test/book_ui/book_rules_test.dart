import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/journal.dart';
import 'package:ghost_md/book/book_nav.dart' show bookOf;
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/core/book.dart';

import '../core/make_note.dart';

/// The index's writers and readers that came with the notebook's own screen (lib/book/book_view.dart,
/// lib/book/book_nav.dart `bookOf`): the web's `book/book.test.ts`, the cases of those functions, case for case.
const String book = '''---
title: "Field guide"
book: true
---
# Field guide

What to know before the walk.

- [[Introduction]]
- [[Trees]]
  - [[Oaks]]
  - [[Pines]]
- [[Birds]]
''';

List<String> titles(String body) => [for (final c in chaptersOf(body)) c.title];
List<List<Object>> depths(String body) => [for (final c in chaptersOf(body)) [c.title, c.depth]];

void main() {
  group('a book note', () {
    test('reads its chapters in order with their depth, and numbers them as an index does', () {
      expect(depths(book), [['Introduction', 0], ['Trees', 0], ['Oaks', 1], ['Pines', 1], ['Birds', 0]]);
      expect(numbered(chaptersOf(book)), ['1', '2', '2.1', '2.2', '3']);
      // A link with a heading or an alias is the note's title alone; a numbered list and a to-do count too.
      expect(titles('---\nbook: true\n---\n1. [[Trees#Oaks|the oaks]]\n2. [ ] [[Birds]]\n'), ['Trees', 'Birds']);
    });

    test('keeps its own words apart from the index', () {
      // Less the front matter and the heading that names the book, which the header says.
      expect(bookWords(book), (before: 'What to know before the walk.', after: ''));
      expect(bookWords(bookNoteBody('Trip')), (before: '', after: ''));
    });
  });

  group('changing the index', () {
    test('takes a chapter out of the index and leaves the note it names alone', () {
      final fewer = withoutChapter(book, 'Oaks');
      expect(titles(fewer), ['Introduction', 'Trees', 'Pines', 'Birds']);
      expect(fewer, contains('What to know before the walk.'));
      expect(withoutChapter(book, 'Nope'), book);
    });

    test('moves a chapter to a place, taking that row’s depth, and lands past the end as last', () {
      expect(titles(withChapterAt(book, 'Birds', 0)), ['Birds', 'Introduction', 'Trees', 'Oaks', 'Pines']);
      expect(titles(withChapterAt(book, 'Introduction', 4)), ['Trees', 'Oaks', 'Pines', 'Birds', 'Introduction']);
      // Dropped among a part's chapters, it becomes one; pulled out, it stands on its own.
      expect(depths(withChapterAt(book, 'Birds', 2)), [['Introduction', 0], ['Trees', 0], ['Birds', 1], ['Oaks', 1], ['Pines', 1]]);
      expect(depths(withChapterAt(book, 'Oaks', 0)).first, ['Oaks', 0]);
      expect(withChapterAt(book, 'Trees', 1), book);
      expect(withChapterAt(book, 'Nope', 0), book);
      expect(titles(withChapterAt(book, 'Introduction', 99)).last, 'Introduction');
    });

    test('moves a chapter up or down one place, and not past the ends', () {
      expect(titles(withChapterMoved(book, 'Birds', -1)), ['Introduction', 'Trees', 'Oaks', 'Birds', 'Pines']);
      expect(titles(withChapterMoved(book, 'Introduction', 1)), ['Trees', 'Introduction', 'Oaks', 'Pines', 'Birds']);
      expect(withChapterMoved(book, 'Introduction', -1), book);
      expect(withChapterMoved(book, 'Birds', 1), book);
    });

    test('writes the Markdown the page writes, line for line', () {
      // The strings themselves, as `book/book.ts` leaves them: a move swaps two lines whole, a drag re-indents the
      // line it carries, and a line taken out leaves no gap.
      expect(withChapterMoved(book, 'Birds', -1), book.replaceFirst('  - [[Pines]]\n- [[Birds]]', '- [[Birds]]\n  - [[Pines]]'));
      expect(withChapterAt(book, 'Birds', 2), book.replaceFirst('  - [[Oaks]]\n  - [[Pines]]\n- [[Birds]]', '  - [[Birds]]\n  - [[Oaks]]\n  - [[Pines]]'));
      expect(withChapterAt(book, 'Oaks', 0), book.replaceFirst('- [[Introduction]]\n- [[Trees]]\n  - [[Oaks]]', '- [[Oaks]]\n- [[Introduction]]\n- [[Trees]]'));
      expect(withoutChapter(book, 'Trees'), book.replaceFirst('- [[Trees]]\n', ''));
    });
  });

  group('a picker’s ticks', () {
    test('ticks a title by putting it last, and unticks it however it is typed', () {
      expect(toggledTitle(['Trees'], 'Birds'), ['Trees', 'Birds']);
      expect(toggledTitle(['Trees', 'Birds'], 'trees!'), ['Birds']);
      final was = ['Trees'];
      toggledTitle(was, 'Birds');
      expect(was, ['Trees']);
    });
  });

  group('the book a note is in', () {
    final notes = [makeNote('b', body: book), makeNote('t', body: '# Trees\n\nTall.'), makeNote('o', body: '# Oaks\n'), makeNote('x', body: '# Loose\n')];

    test('is found from any chapter, with its place, and not from a note that is in no book', () {
      final place = bookOf(notes, 'Oaks');
      expect(place?.book.id, 'b');
      expect(place?.title, 'Field guide');
      expect(place?.at, 2);
      expect(bookOf(notes, 'trees')?.at, 1);
      expect(bookOf(notes, 'Loose'), isNull);
      expect(bookOf(notes, ''), isNull);
    });

    test('is not the book itself', () {
      final selfish = makeNote('s', body: '---\nbook: true\n---\n# Self\n\n- [[Self]]\n');
      expect(bookOf([selfish], 'Self'), isNull);
    });
  });

  group('a chapter read straight through', () {
    test('drops the front matter and the heading that is its own title, and keeps the rest with its marks', () {
      expect(bodyWithoutTitle('---\ntitle: "Oaks"\n---\n# Oaks\n\nTall, and *old*.\n\n- [ ] count them\n', 'Oaks'), 'Tall, and *old*.\n\n- [ ] count them\n');
      // A heading that is not the title stays: it is the chapter's own first section.
      expect(bodyWithoutTitle('# Where they grow\n\nHere.', 'Oaks'), '# Where they grow\n\nHere.');
      expect(bodyWithoutTitle('\n\nNo heading.', 'Oaks'), 'No heading.');
    });
  });

  group('what counts as a chapter', () {
    // The shape of Matt's HelloTrade book: a numbered index in parts, then a bullet list of canvases, then prose
    // bullets that link chapters in passing.
    final hello = [
      '---',
      'title: Hello.Trade: The Book',
      'book: true',
      '---',
      '# Hello.Trade: The Book',
      '',
      '_Everything known, in short chapters._',
      '',
      '## Part I',
      '',
      '1. [[The two things you can trade]]',
      '2. [[Leverage, and what it costs you]] — worth reading twice',
      '',
      '## Part II',
      '',
      '3. [[HelloTrade in one page]]',
      '   - [[A page inside it]]',
      '',
      '## The canvases',
      '',
      '- [[Canvas · The tick path]] — embedded in a chapter.',
      '',
      '## Five things worth knowing',
      '',
      '- A **market order** is a limit order ([[HelloTrade in one page]]).',
      '- **The key is never on the device** ([[Leverage, and what it costs you]]).',
    ].join('\n');

    test('keeps the words before the index over it, and the side lists and prose bullets after it under it', () {
      final words = bookWords(hello);
      // The lead, with the part heading that only introduces the list left to the list.
      expect(words.before, '_Everything known, in short chapters._');
      expect(words.after, contains('- [[Canvas · The tick path]] — embedded in a chapter.'));
      expect(words.after, contains('- A **market order** is a limit order ([[HelloTrade in one page]]).'));
      expect(words.after.startsWith('## The canvases'), isTrue);
      // Between the chapters, a part's heading is the list's: in neither.
      expect(words.before + words.after, isNot(contains('## Part II')));
      expect(words.before + words.after, isNot(contains('[[The two things you can trade]]')));
    });
  });

  group('held to the page’s own module', () {
    // test/book_ui/fixtures/rules.json is `book/book.ts` and `book/journal.ts` themselves, run in Chromium by
    // tool/book_reference.mjs over a notebook, a keyed one, a journal, a numbered index in parts and a book of
    // words alone: every writer's answer, for every chapter and every place.
    final rules = jsonDecode(File('test/book_ui/fixtures/rules.json').readAsStringSync()) as Map<String, dynamic>;

    test('every writer of the index writes the same Markdown, string for string', () {
      var checked = 0;
      for (final one in (rules['books'] as List).cast<Map<String, dynamic>>()) {
        final body = one['body'] as String;
        final chapters = chaptersOf(body);
        expect(numbered(chapters), one['numbered']);
        final words = bookWords(body);
        expect({'before': words.before, 'after': words.after}, one['words']);
        expect(withChapter(body, 'A new page'), one['added']);
        if (one['addedAfter'] != null) expect(withChapter(body, 'A new page', chapters.first.title), one['addedAfter']);
        expect(withEntry(body, '2026-10-08 15.30'), one['entry']);
        for (final chapter in chapters) {
          final title = chapter.title;
          expect(withoutChapter(body, title), (one['without'] as Map)[title], reason: 'without $title');
          expect([withChapterMoved(body, title, -1), withChapterMoved(body, title, 1)], (one['moved'] as Map)[title], reason: 'moved $title');
          expect([for (var to = 0; to < chapters.length; to += 1) withChapterAt(body, title, to), withChapterAt(body, title, 99)], (one['at'] as Map)[title], reason: 'at $title');
          checked += chapters.length + 4;
        }
      }
      expect(checked, greaterThan(100));
    });

    test('a new notebook, a new journal and a chapter read through are the page’s own strings', () {
      final made = rules['made'] as Map<String, dynamic>;
      expect(bookNoteBody('Cabin trip', ['Packing', 'Days']), made['book']);
      expect(bookNoteBody('  '), made['empty']);
      expect(journalNoteBody('Diary', entryPresets[3].text, true), made['journal']);
      expect(journalNoteBody('Log: "the" one', 'Dear {{journal}},\n', false), made['journalPlain']);
      for (final each in (made['read'] as List).cast<List<dynamic>>()) {
        expect(bodyWithoutTitle(each[0] as String, each[1] as String), each[2]);
      }
    });
  });
}
