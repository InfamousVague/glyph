import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/aside/aside.dart';
import 'package:ghost_md/core/stored.dart';

import '../core/make_note.dart';

/// What the aside shows (aside/aside.dart): `src/app/aside/aside.test.ts`, case for case.
void main() {
  const bookBody = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Trees]]\n- [[Birds]]\n';
  final notes = [
    makeNote('b', body: bookBody, updatedAt: 5),
    makeNote('t', body: '# Trees\n', updatedAt: 4),
    makeNote('x', body: '# Loose\n', updatedAt: 3),
    makeNote('a', body: '# Archived\n', updatedAt: 9, archivedAt: 1),
  ];

  group('what the aside shows', () {
    test('shows a page’s book with the page marked, and the book’s own index with none', () {
      final page = asideContent(notes, notes[1]) as AsideBook;
      expect(page.place.title, 'Field guide');
      expect([for (final c in page.place.chapters) c.title], ['Trees', 'Birds']);
      expect(page.open, 't');
      final book = asideContent(notes, notes[0]) as AsideBook;
      expect(book.place.at, -1);
      expect(book.open, isNull);
    });

    test('shows nothing for a note in no book and with no number, or for the home page', () {
      expect(asideContent(notes, notes[2]), isNull);
      expect(asideContent(notes, null), isNull);
    });

    // Chapters saved in whatever order, each pointing back at a book that isn't a note marked as one.
    chapter(String id, String title, int updatedAt, [String back = 'HelloTrade — The Book']) =>
        makeNote(id, body: '# $title\n\n« [[$back]] · next: [[09 · Something]]\n\nWords.', updatedAt: updatedAt);
    final run = [
      chapter('c10', '10 · The mount chain', 9),
      chapter('c9', '09 · In one page', 8),
      chapter('c1', '01 · Two things', 7),
      chapter('c8', '08 · The risks, and a glossary', 6),
      chapter('o1', '01 · Another book’s first', 5, 'Another book'),
      makeNote('tm', body: '# Task Management\n', updatedAt: 10),
      makeNote('hb', body: '# HelloTrade — The Book\n\nThe index.', updatedAt: 2),
    ];

    test('lays out a numbered chapter’s run in number order when there is no book, the open one marked', () {
      final shown = asideContent(run, run[3]) as AsideChapters;
      expect(shown.title, 'HelloTrade — The Book');
      expect(shown.titleId, 'hb');
      expect([for (final c in shown.chapters) (c.number, c.name)], [(1, 'Two things'), (8, 'The risks, and a glossary'), (9, 'In one page'), (10, 'The mount chain')]);
      expect(shown.open, 'c8');
    });

    test('keeps a run to the chapters that point at the same note, and shows nothing for a chapter on its own', () {
      expect(asideContent(run, run[4]), isNull);
    });

    test('groups chapters with no link by their folder, named after it', () {
      inFolder(String id, String title, String path) => makeNote(id, body: '# $title\n\nWords.', updatedAt: 1).copyWith(path: () => path);
      final folder = [inFolder('a', 'Arrival · Ch. 2', 'Trip/Arrival.md'), inFolder('b', 'Leaving · Ch. 1', 'Trip/Leaving.md'), inFolder('c', 'Other · Ch. 1', 'Else/Other.md')];
      final shown = asideContent(folder, folder[0]) as AsideChapters;
      expect(shown.title, 'Trip');
      expect([for (final c in shown.chapters) c.id], ['b', 'a']);
    });
  });

  group('whether the aside is shown', () {
    test('is hidden until it has been opened, and kept on this device', () {
      final local = MemoryStored();
      expect(readAsideShown(local), isFalse);
      writeAsideShown(true, local);
      expect(readAsideShown(local), isTrue);
      writeAsideShown(false, local);
      expect(readAsideShown(local), isFalse);
      expect(local.getItem('glyph-aside-shown'), '0');
    });

    test('the tab last looked at is kept, as the page’s own words', () {
      final local = MemoryStored();
      expect(readAsideTab(local), AsideTab.contents);
      writeAsideTab(AsideTab.history, local);
      expect(local.getItem('glyph-aside-tab'), 'history');
      expect(readAsideTab(local), AsideTab.history);
      writeAsideTab(AsideTab.contents, local);
      expect(local.getItem('glyph-aside-tab'), 'index');
    });

    test('the docked sidebar has no answer until it has been toggled, then the one kept', () {
      final local = MemoryStored();
      expect(readSidebarShown(local), isNull);
      writeSidebarShown(true, local);
      expect(readSidebarShown(local), isTrue);
      writeSidebarShown(false, local);
      expect(readSidebarShown(local), isFalse);
      expect(local.getItem('glyph-sidebar-shown'), '0');
    });
  });

  group('a journal’s aside', () {
    entry(String id, String title, String date, String words) => makeNote(id, body: '---\ntitle: "$title"\ndate: $date\n---\n# Day\n\n**${date.substring(11)}** $words');
    const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[2026-08-30 10.00]]\n- [[2026-09-28 14.05]]\n- [[2026-09-27 21.40]]\n';
    final journalNotes = [
      makeNote('j', body: journal),
      entry('aug', '2026-08-30 10.00', '2026-08-30T10:00', 'August.'),
      entry('late', '2026-09-28 14.05', '2026-09-28T14:05', 'Walked.'),
      entry('early', '2026-09-27 21.40', '2026-09-27T21:40', 'Dinner.'),
    ];

    test('lists the journal’s newest month, newest first, for the journal itself', () {
      final shown = asideContent(journalNotes, journalNotes[0]) as AsideBook;
      expect(shown.journal, isTrue);
      expect(shown.month?.label, 'September 2026');
      expect([for (final e in shown.month!.entries) e.id], ['late', 'early']);
    });

    test('lists the open entry’s own month, the entry marked', () {
      final shown = asideContent(journalNotes, journalNotes[1]) as AsideBook;
      expect(shown.open, 'aug');
      expect([for (final e in shown.month!.entries) e.id], ['aug']);
    });

    test('has no month for a journal with nothing written', () {
      final empty = makeNote('e', body: '---\ntitle: "Log"\nbook: true\njournal: true\n---\n# Log\n\n');
      final shown = asideContent([empty], empty) as AsideBook;
      expect(shown.journal, isTrue);
      expect(shown.month, isNull);
    });
  });
}
