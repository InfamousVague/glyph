import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/canvas_body.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_facts.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/home/home_layout.dart';

import 'front_matter_test.dart' show awkward;
import 'make_note.dart';

/// A note's body read once and kept (lib/core/note_facts.dart): every fact is the answer of the function a caller
/// with only a body asks, each note is read once for the body it has, an edit is a new reading and the old one
/// goes, and no more are kept than the bound. And the answers worked out from every note at once (every page's
/// notebook, every journal's card) are worked out once for the notes they were worked out from.
void main() {
  setUp(NoteFacts.debugForget);
  tearDown(() => NoteFacts.most = 32768);

  const ticket = '---\ntype: ticket\nid: gho-12\nstatus: Building\nassignee: "@Sam"\npriority: high\ndue: 2026-10-03\nestimate: 2.5 days\nblocked-by: "[[GHO-9]], [[GHO-10|the loop]]"\nlabels: [bug, "#ui"]\n---\n# Fix the login loop\n\nIt loops.';
  const notebook = '---\ntitle: "Product"\nbook: true\nkey: GHO\nstatuses: [Ideas, Building, Live]\n---\n# Product\n\n1. [[Fix the login loop]]\n2. [[Pricing page copy]]\n   - [[A page under it]]\n- [[About the book, not in it]]\n';
  const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[2026-09-27 09.15]]\n- [[2026-09-28 14.05]]\n- [[Planned]]\n';
  const canvas = '---\ntitle: "Plans"\n---\n{"nodes":[{"id":"a","type":"text","x":0,"y":0,"width":10,"height":10,"text":"one"},{"id":"b","type":"text","x":20,"y":0,"width":10,"height":10,"text":"two"}],"edges":[]}\n';

  List<String> bodies() => [
        ...awkward,
        ticket,
        notebook,
        journal,
        canvas,
        '---\nbook: true\ntemplates: true\n---\n- [[Meeting]]\n',
        '---\ntemplates: page\n---\n# Meeting\n\n- [ ] Agenda',
        '# Trip packing\n\n- [ ] Passport [^c1]\n- [ ] Charger\n\n```board\nTo do\n```\n\nAfter the board.',
        for (final note in seedLibrary()) note.body,
        for (final note in starterNotes(seedNow)) note.body,
      ];

  group('a note’s facts', () {
    test('are the answers of the functions a body is asked through, for every kind of body', () {
      var at = 0;
      for (final body in bodies()) {
        final facts = NoteFacts.of(makeNote('n${at += 1}', body: body, createdAt: seedNow));
        final reason = body.length > 60 ? body.substring(0, 60) : body;
        expect(facts.body, body, reason: reason);
        expect(facts.front.offset, frontMatterOffset(body), reason: reason);
        for (final key in ['title', 'book', 'type', 'status', 'none']) {
          expect(facts.value(key), frontMatterValue(body, key), reason: '$reason: $key');
        }
        expect(facts.title, noteTitle(body), reason: reason);
        expect(facts.key, titleKey(noteTitle(body)), reason: reason);
        expect(facts.shownTitle, shortenUrls(noteTitle(body)), reason: reason);
        expect(facts.isBook, isBookBody(body), reason: reason);
        expect(facts.isJournal, isJournalBody(body), reason: reason);
        expect(facts.isTemplatesBook, isTemplatesBook(body), reason: reason);
        expect(facts.isTemplatePage, isTemplatePage(body), reason: reason);
        expect(facts.isCanvas, isCanvasBody(body), reason: reason);
        expect(facts.canvasCards, canvasCardCount(body), reason: reason);
        expect(facts.isTicket, isTicket(body), reason: reason);
        expect(facts.ticket, ticketOf(body), reason: reason);
        final chapters = chaptersOf(body);
        expect([for (final c in facts.chapters) (c.title, c.depth, c.line)], [for (final c in chapters) (c.title, c.depth, c.line)], reason: reason);
        expect(facts.chapterKeys, [for (final c in chapters) titleKey(c.title)], reason: reason);
        expect(facts.statuses, statusesOf(body), reason: reason);
        expect(facts.firstLine, firstLine(body), reason: reason);
        expect(facts.peek, isCanvasBody(body) ? '' : peekMarkdown(body), reason: reason);
        expect(facts.stamp(seedNow), stampOf(body, seedNow), reason: reason);
        expect(facts.stamp(12345), stampOf(body, 12345), reason: reason);
      }
    });

    test('place a ticket in a notebook’s workflow as the body’s reading does', () {
      final facts = NoteFacts.read(ticket);
      final workflow = NoteFacts.read(notebook).statuses;
      expect(workflow, ['Ideas', 'Building', 'Live']);
      expect(facts.ticket, ticketOf(ticket));
      expect(facts.ticket!.category, StatusCategory.doing, reason: '"building" is a word the lists know');
      expect(facts.ticketIn(workflow), ticketOf(ticket, workflow));
      expect(facts.ticketIn(null), ticketOf(ticket));
      // A status no list knows is placed by where it stands in the workflow: first not started, last done.
      const odd = '---\ntype: ticket\nstatus: Live\n---\n# Shipped';
      final placed = NoteFacts.read(odd);
      expect(placed.ticket!.category, StatusCategory.todo);
      expect(placed.ticketIn(workflow), ticketOf(odd, workflow));
      expect(placed.ticketIn(workflow)!.category, StatusCategory.done);
      expect(placed.ticketIn(const ['Live', 'Later']), ticketOf(odd, const ['Live', 'Later']));
      expect(placed.ticketIn(workflow)!.category, StatusCategory.done, reason: 'asked again after another workflow');
      expect(NoteFacts.read('# Words').ticketIn(workflow), isNull);
    });

    test('are worked out once: one reading a note, and each fact the first time it is asked for', () {
      final notes = [for (final (i, body) in bodies().indexed) makeNote('n$i', body: body)];
      for (final note in notes) {
        NoteFacts.of(note);
      }
      expect(NoteFacts.debugReadings, notes.length);
      expect(NoteFacts.debugWorkedOut, 0, reason: 'nothing is read until it is asked for');
      void ask() {
        for (final note in notes) {
          final facts = NoteFacts.of(note);
          facts.title;
          facts.key;
          facts.isBook;
          facts.isJournal;
          facts.isCanvas;
          facts.isTicket;
          facts.ticket;
          facts.chapters;
          facts.chapterKeys;
          facts.firstLine;
          facts.peek;
          facts.canvasCards;
        }
      }

      ask();
      final worked = NoteFacts.debugWorkedOut;
      expect(worked, greaterThan(notes.length * 5));
      for (var i = 0; i < 5; i += 1) {
        ask();
      }
      expect(NoteFacts.debugWorkedOut, worked, reason: 'asked again, nothing is worked out again');
      expect(NoteFacts.debugReadings, notes.length, reason: 'and no body is read again');
      expect(identical(NoteFacts.of(notes[3]), NoteFacts.of(notes[3])), isTrue);
      expect(identical(NoteFacts.of(notes[3]).chapters, NoteFacts.of(notes[3]).chapters), isTrue);
    });

    test('are read again for a note that was edited, and the old reading goes', () {
      final note = makeNote('a', body: '# First\n\nWords.');
      expect(NoteFacts.of(note).title, 'First');
      expect(NoteFacts.debugReadings, 1);
      final edited = note.copyWith(body: '# Second\n\nWords.');
      expect(NoteFacts.of(edited).title, 'Second');
      expect(NoteFacts.debugReadings, 2);
      expect(NoteFacts.debugKept, 1, reason: 'one reading a note, for the body it has now');
      // Pinned, archived, touched: the words are the same, and so is the reading.
      final pinned = edited.copyWith(starred: true, updatedAt: 9);
      expect(identical(NoteFacts.of(pinned), NoteFacts.of(edited)), isTrue);
      expect(NoteFacts.debugReadings, 2);
    });

    test('are kept for the same words in a new string, which the reading then holds', () {
      final words = ['# Read', 'again'].join('\n');
      final again = ['# Read', 'again'].join('\n');
      expect(identical(words, again), isFalse);
      final first = NoteFacts.of(makeNote('a', body: words));
      first.title;
      final second = NoteFacts.of(makeNote('a', body: again));
      expect(identical(first, second), isTrue);
      expect(NoteFacts.debugReadings, 1);
      expect(identical(second.body, again), isTrue, reason: 'the newer string is held, so the older can go');
    });

    test('are kept for no more notes than the bound, the longest unasked going first', () {
      NoteFacts.most = 40;
      final notes = [for (var i = 0; i < 100; i += 1) makeNote('n$i', body: '# Note $i')];
      for (final note in notes) {
        NoteFacts.of(note);
        expect(NoteFacts.debugKept, lessThanOrEqualTo(40));
      }
      expect(NoteFacts.debugReadings, 100);
      // The newest are still kept: asking about them reads nothing.
      for (final note in notes.sublist(80)) {
        NoteFacts.of(note);
      }
      expect(NoteFacts.debugReadings, 100);
      // The oldest went, and is read again when asked for, with the same answer.
      expect(NoteFacts.of(notes[0]).title, 'Note 0');
      expect(NoteFacts.debugReadings, 101);
    });

    test('are not kept for a body that is no note’s', () {
      expect(NoteFacts.read('# Loose').title, 'Loose');
      expect(NoteFacts.debugKept, 0);
    });
  });

  group('the same notes', () {
    test('are told by what a list shows of them, whatever list they come in', () {
      final a = [makeNote('a', body: '# A', updatedAt: 1), makeNote('b', body: '# B', updatedAt: 2)];
      expect(sameNotes(a, a), isTrue);
      expect(sameNotes(a, [...a]), isTrue);
      expect(sameNotes(a, [makeNote('a', body: ['# ', 'A'].join(), updatedAt: 1), a[1]]), isTrue, reason: 'read again: new notes that say the same');
      expect(sameNotes(a, [a[1], a[0]]), isFalse);
      expect(sameNotes(a, [a[0]]), isFalse);
      expect(sameNotes(a, [a[0], a[1].copyWith(starred: true)]), isFalse);
      expect(sameNotes(a, [a[0], a[1].copyWith(updatedAt: 3)]), isFalse);
      expect(sameNotes(a, [a[0], a[1].copyWith(archivedAt: () => 5)]), isFalse);
      expect(sameNotes(a, [a[0], a[1].copyWith(body: '# C')]), isFalse);
      expect(sameNotes(a, [a[0], makeNote('b', body: '# B', updatedAt: 2, recordingMs: 4000)]), isFalse);
      expect(sameNotes(a, [a[0], makeNote('c', body: '# B', updatedAt: 2)]), isFalse);
    });
  });

  group('what is worked out from every note at once', () {
    List<Note> library() => [
          makeNote('book', body: notebook, updatedAt: 5),
          makeNote('fix', body: ticket, updatedAt: 4),
          makeNote('copy', body: '# Pricing page copy\n\nWords.', updatedAt: 3),
          makeNote('diary', body: journal, updatedAt: 2),
          makeNote('e1', body: '---\ndate: 2026-09-27T09:15\n---\n# 2026-09-27 09.15\n\nWalked.', createdAt: seedNow, updatedAt: 1),
          makeNote('e2', body: '---\ndate: 2026-09-28T14:05\n---\n# 2026-09-28 14.05\n\nRead.', createdAt: seedNow, updatedAt: 1),
          makeNote('plans', body: canvas, updatedAt: 1),
          makeNote('old', body: '# Archived', archivedAt: 9),
        ];

    test('every page’s notebook is found as before, and found once for the same notes', () {
      final notes = library();
      final index = bookIndex(notes);
      expect(index.keys, ['fix the login loop', 'pricing page copy', 'a page under it', '2026 09 27 09 15', '2026 09 28 14 05', 'planned']);
      expect(placeOf(index, notes[1])!.title, 'Product');
      expect(placeOf(index, notes[1])!.at, 0);
      expect(placeOf(index, notes[2])!.chapters.length, 3);
      expect(placeOf(index, notes[4])!.journal, isTrue);
      expect(placeOf(index, notes[0]), isNull, reason: 'a notebook is in none');
      expect(placeOf(index, notes[6]), isNull);
      // The very same notes, in a new list: the index already made.
      expect(identical(bookIndex([...notes]), index), isTrue);
      expect(identical(bookIndex(notes.toList()), index), isTrue);
      // One note edited: made again, and right.
      final renamed = [...notes]..[2] = notes[2].copyWith(body: '# Another name\n\nWords.');
      final next = bookIndex(renamed);
      expect(identical(next, index), isFalse);
      expect(placeOf(next, renamed[2]), isNull);
      // And the first is still kept beside it: a page asks for one workspace's notes and for all of them.
      expect(identical(bookIndex(notes), index), isTrue);
      // An iterable that is no list is answered too, and not kept.
      expect(bookIndex(notes.where((note) => true)).keys, index.keys);
    });

    test('every journal’s card is made as before, and made once for the same notes', () {
      final notes = library();
      final cards = journalCards(notes);
      expect(cards.keys, ['diary']);
      expect(cards['diary']!.count, 2, reason: 'a page planned and not written is no entry');
      expect([for (final entry in cards['diary']!.newest) entry.title], ['2026-09-28 14.05', '2026-09-27 09.15']);
      expect(identical(journalCards([...notes]), cards), isTrue);
      expect(identical(journalCards(notes, 1), cards), isFalse, reason: 'another count of the newest is another answer');
      expect(journalCards(notes, 1)['diary']!.newest.length, 1);
      final more = [...notes, makeNote('e3', body: '# Planned\n\nNow written.', createdAt: seedNow + 60000)];
      expect(journalCards(more)['diary']!.count, 3);
      expect(journalCards(const []), isEmpty);
    });

    test('the home page’s lists, counts and kinds are read from the kept facts, once a note', () {
      final notes = library();
      NoteFacts.debugForget();
      final lists = homeLists(notes, '', HomeFilter.all);
      expect(ids(lists.books), ['book', 'diary']);
      expect(ids(lists.notes), ['fix', 'copy', 'e1', 'e2', 'plans']);
      expect(homeCounts(notes), {HomeFilter.all: 7, HomeFilter.books: 2, HomeFilter.notes: 5, HomeFilter.pinned: 0});
      expect([for (final note in notes) kindOf(note)], [HomeKind.book, HomeKind.note, HomeKind.note, HomeKind.book, HomeKind.note, HomeKind.note, HomeKind.canvas, HomeKind.note]);
      expect(NoteFacts.debugReadings, notes.length);
      final worked = NoteFacts.debugWorkedOut;
      for (var i = 0; i < 4; i += 1) {
        homeLists(notes, '', HomeFilter.all);
        homeCounts(notes);
        notes.map(kindOf).toList();
        bookIndex(notes);
        journalCards(notes);
      }
      expect(NoteFacts.debugReadings, notes.length, reason: 'no body is read again');
      // The index and the cards ask for a title's key and a chapter's the first time, and nothing after.
      final settled = NoteFacts.debugWorkedOut;
      expect(settled, greaterThanOrEqualTo(worked));
      homeLists(notes, '', HomeFilter.all);
      homeCounts(notes);
      notes.map(kindOf).toList();
      bookIndex([...notes]);
      journalCards([...notes]);
      expect(NoteFacts.debugWorkedOut, settled);
    });
  });
}
