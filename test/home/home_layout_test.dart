import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/home/home_layout.dart';

import '../core/make_note.dart';

/// The home page's rules (lib/home/home_layout.dart): the cases of the web's `home/homeLayout.test.ts`, then the
/// web's own answers over the seeded library (test/core/fixtures/web_library.json, written by running homeLayout.ts).
void main() {
  final trip = makeNote('b', body: bookNoteBody('Trip', ['Packing']), updatedAt: 5);
  final packing = makeNote('p', body: '# Packing\n\n- [ ] Tent', starred: true, updatedAt: 1);
  final route = makeNote('r', body: '# Route\n\nNorth along the coast.', updatedAt: 4);
  final board = makeNote('c', body: '{"nodes":[],"edges":[]}', updatedAt: 3);
  final gone = makeNote('g', body: '# Gone', updatedAt: 9, archivedAt: 10);
  final all = [packing, trip, route, board, gone];

  group('what the home page lists', () {
    test('offers the four layouts, Spotlight, the default, first, then Cards, Timeline and List (docs/DESIGN.md §178)', () {
      expect([for (final l in homeLayouts) l.id.name], ['spotlight', 'cards', 'timeline', 'list']);
      expect({for (final l in homeLayouts) l.id}, HomeLayout.values.toSet());
    });

    test('knows a notebook, a canvas, a voice recording and a note of words', () {
      final spoken = makeNote('v', body: '# Standup', source: NoteSource.capture, recordingMs: 40000);
      final removed = makeNote('x', body: '# Its tape removed', source: NoteSource.capture);
      expect([trip, board, spoken, removed, route].map(kindOf), [HomeKind.book, HomeKind.canvas, HomeKind.tape, HomeKind.note, HomeKind.note]);
    });

    test('lists a voice recording as a note, in every filter a note is in', () {
      final spoken = makeNote('v', body: '# Standup', source: NoteSource.capture, recordingMs: 40000, updatedAt: 6);
      expect(ids(homeLists([spoken, ...all], '', HomeFilter.notes).notes), ['p', 'v', 'r', 'c']);
      final counts = homeCounts([spoken, ...all]);
      expect(counts[HomeFilter.all], 5);
      expect(counts[HomeFilter.notes], 4);
    });

    test('puts the notebooks apart from the notes, pinned first and then newest, and never the archive', () {
      final lists = homeLists(all, '', HomeFilter.all);
      expect(ids(lists.books), ['b']);
      expect(ids(lists.notes), ['p', 'r', 'c']);
    });

    test('filters to notebooks, notes or the pinned, and narrows to the search', () {
      expect(homeLists(all, '', HomeFilter.books).notes, isEmpty);
      expect(homeLists(all, '', HomeFilter.notes).books, isEmpty);
      expect(ids(homeLists(all, '', HomeFilter.pinned).notes), ['p']);
      expect(ids(homeLists(all, 'coast', HomeFilter.all).notes), ['r']);
      expect(homeLists(all, 'gone', HomeFilter.all).notes, isEmpty);
    });

    test('counts each filter, leaving out the archive and never the search', () {
      expect(homeCounts(all), {HomeFilter.all: 4, HomeFilter.books: 1, HomeFilter.notes: 3, HomeFilter.pinned: 1});
    });
  });

  group('how a note starts, on one line', () {
    test('is its first words under the title, the line marks taken off', () {
      expect(firstLine('# Packing\n\n- [ ] **Tent** and `stove`'), 'Tent and stove');
      expect(firstLine('---\ntitle: "Trip"\n---\n# Trip\n\n> Go north'), 'Go north');
      expect(firstLine('# Only a title'), '');
    });

    test('is cut with an ellipsis past the most it may be', () {
      expect(firstLine('# T\n\n${'word ' * 40}', 20), 'word word word word…');
    });
  });

  group('the timeline', () {
    final now = DateTime(2026, 9, 30, 15).millisecondsSinceEpoch;
    int at(int days, [int hour = 9]) => DateTime(2026, 9, 30 - days, hour).millisecondsSinceEpoch;

    test('says which span a moment falls in, by this device’s days', () {
      expect([at(0), at(1, 23), at(3), at(20), at(40)].map((t) => spanOf(t, now)), [Span.today, Span.yesterday, Span.week, Span.month, Span.earlier]);
    });

    test('groups notebooks and notes together, newest first, and leaves out an empty span', () {
      final lists = HomeLists(
        books: [makeNote('b', body: bookNoteBody('Trip'), updatedAt: at(1))],
        notes: [makeNote('n', body: '# Now', updatedAt: at(0)), makeNote('o', body: '# Old', updatedAt: at(40))],
      );
      expect([for (final group in timeline(lists, now)) '${group.span.name}: ${ids(group.notes).join(' ')}'], ['today: n', 'yesterday: b', 'earlier: o']);
    });
  });

  group('each layout’s sections', () {
    final now = DateTime(2026, 9, 30, 15).millisecondsSinceEpoch;
    int at(int days) => now - days * 24 * 60 * 60 * 1000 - 60000;
    final book = makeNote('b', body: bookNoteBody('Trip', ['Packing', 'Route']), updatedAt: at(0));
    final pages = [makeNote('p', body: '# Packing', updatedAt: at(1)), makeNote('r', body: '# Route\n\nAlong the coast.', updatedAt: at(40))];
    final shop = makeNote('s', body: '# Shopping', updatedAt: at(0) - 60000);
    final lists = homeLists([book, ...pages, shop], '', HomeFilter.all);

    /// A plan as its sections' keys, each with how it draws and what, by id.
    List<String> shape(HomePlan plan) => [for (final s in plan.sections) '${s.key} ${s.draw.name}: ${ids(s.notes).join(' ')}'];

    test('lays out Cards and List as the notebooks then the notes', () {
      expect(shape(homePlan(HomeLayout.cards, lists, now: now)), ['books cards: b', 'notes cards: s p r']);
      expect(shape(homePlan(HomeLayout.list, lists, now: now)), ['books rows: b', 'notes rows: s p r']);
    });

    test('lays out the Timeline by when, notebooks and notes together', () {
      expect(shape(homePlan(HomeLayout.timeline, lists, now: now)), ['today rows: b s', 'yesterday rows: p', 'earlier rows: r']);
    });

    test('leads Spotlight with the four touched last, by when alone, and the rest by when', () {
      final plan = homePlan(HomeLayout.spotlight, homeLists([book, ...pages, shop, makeNote('x', body: '# Extra', updatedAt: at(90))], '', HomeFilter.all), now: now);
      expect(shape(plan), ['recent cards: b s p r', 'earlier rows: x']);
      expect(plan.sections[0].heading, 'Recent');
      expect(plan.sections[0].mark, SectionMark.recent);
      expect(plan.sections[0].count, isNull);
      // A pin does not put a note in the lead: the lead is where the person was.
      final pinned = makeNote('old', body: '# Pinned long ago', starred: true, updatedAt: at(300));
      expect(ids(spotlight(homeLists([pinned, book, ...pages, shop], '', HomeFilter.all), 4, now).lead), ['b', 's', 'p', 'r']);
    });

    test('heads Spotlight with the pinned notes as lines, newest first, and draws them nowhere else on it', () {
      final pinnedBook = makeNote('pb', body: bookNoteBody('Recipes'), starred: true, updatedAt: at(5));
      final pinnedNote = makeNote('pn', body: '# Passwords to change', starred: true, updatedAt: at(0));
      final plan = homePlan(HomeLayout.spotlight, homeLists([book, ...pages, shop, pinnedBook, pinnedNote], '', HomeFilter.all), now: now);
      expect(shape(plan), ['pinned lines: pn pb', 'recent cards: b s p r']);
      expect(plan.sections[0].heading, 'Pinned');
      expect(plan.sections[0].mark, SectionMark.pinned);
      expect(plan.sections[0].count, 2);
      // Nothing pinned, no Pinned; only pinned (the Pinned filter), only Pinned.
      expect(shape(homePlan(HomeLayout.spotlight, lists, now: now))[0], 'recent cards: b s p r');
      expect(shape(homePlan(HomeLayout.spotlight, homeLists([book, pinnedBook, pinnedNote], '', HomeFilter.pinned), now: now)), ['pinned lines: pn pb']);
      // Lines are not cards: no line under a title is written for them.
      expect(ids(cardsIn(plan)), ['b', 's', 'p', 'r']);
    });

    test('stops Cards at the most it may draw, and counts what it left for All notes', () {
      expect(homePlan(HomeLayout.cards, lists, now: now, most: 2).cut, 1);
      expect(shape(homePlan(HomeLayout.cards, lists, now: now, most: 2)), ['books cards: b', 'notes cards: s p']);
      // Rows are cheap, and never stop.
      expect(homePlan(HomeLayout.timeline, lists, now: now, most: 2).cut, 0);
      expect(homePlan(HomeLayout.list, lists, now: now, most: 2).cut, 0);
    });

    test('draws no empty section, and names every card in the page’s order', () {
      final books = homeLists([book, ...pages, shop], '', HomeFilter.books);
      expect(shape(homePlan(HomeLayout.cards, books, now: now)), ['books cards: b']);
      expect(ids(cardsIn(homePlan(HomeLayout.cards, lists, now: now))), ['b', 's', 'p', 'r']);
      expect(ids(cardsIn(homePlan(HomeLayout.spotlight, lists, now: now))), ['b', 's', 'p', 'r']);
      expect(cardsIn(homePlan(HomeLayout.list, lists, now: now)), isEmpty);
    });
  });

  group('over the seeded library, as the web app answers (homeLayout.ts run over seed.mjs)', () {
    final web = jsonDecode(File('test/core/fixtures/web_library.json').readAsStringSync()) as Map<String, dynamic>;
    final notes = seedLibrary();
    final today = DateTime(2026, 9, 28).millisecondsSinceEpoch;

    Map<String, dynamic> shape(HomePlan plan) => {
          'cut': plan.cut,
          'sections': [
            for (final s in plan.sections) {'key': s.key, 'heading': s.heading, 'mark': s.mark?.name, 'count': s.count, 'draw': s.draw.name, 'notes': ids(s.notes)},
          ],
        };

    for (final layout in HomeLayout.values) {
      test('plans ${layout.name} as the web does', () {
        expect(shape(homePlan(layout, homeLists(notes, '', HomeFilter.all), now: today)), (web['plans'] as Map)[layout.name]);
      });
    }

    test('plans the Pinned and the Notebooks filters as the web does', () {
      expect(shape(homePlan(HomeLayout.spotlight, homeLists(notes, '', HomeFilter.pinned), now: today)), web['pinnedOnly']);
      expect(shape(homePlan(HomeLayout.cards, homeLists(notes, '', HomeFilter.books), now: today)), web['booksOnly']);
    });

    test('counts each filter as the web does', () {
      expect({for (final entry in homeCounts(notes).entries) entry.key.name: entry.value}, web['counts']);
    });

    test('says each note’s kind and how it starts as the web does', () {
      final read = web['read'] as Map<String, dynamic>;
      for (final note in notes) {
        expect(kindOf(note).name, read[note.id]['kind'], reason: note.id);
        expect(firstLine(note.body), read[note.id]['firstLine'], reason: note.id);
      }
    });
  });
}
