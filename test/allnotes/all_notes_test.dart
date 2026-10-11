import 'package:flutter_test/flutter_test.dart' hide matches;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show plainFills;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/task_fields.dart' show FieldKind, fieldsIn;
import 'package:ghost_md/home/home_layout.dart' show HomeFilter, homeLists;
import 'package:ghost_md/notes/all_notes.dart';

import '../core/make_note.dart';

/// The rules behind the All notes page (lib/notes/all_notes.dart), case for case with the web's
/// `notes/allNotes.test.ts`.
void main() {
  group('what the search finds', () {
    test('finds every word typed, anywhere in the note, whatever the case', () {
      final packing = makeNote('a', body: '# Trip\n\nPacking: tent, stove');
      expect(matches(packing, 'trip packing'), isTrue);
      expect(matches(packing, 'TENT'), isTrue);
      expect(matches(packing, 'tent kettle'), isFalse);
    });

    test('finds a filled answer by its words and a blank by its question, never by the hidden bracket (docs/DESIGN.md §145)', () {
      final filled = makeNote('a', body: '# Tokyo trip\n\nFlights are cheapest on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)\n\nWeather: {?weather today}');
      expect(matches(filled, 'midweek'), isTrue);
      expect(matches(filled, 'weather today'), isTrue);
      expect(matches(filled, 'memory'), isFalse);
      expect(matches(filled, 'asked'), isFalse);
      expect(matches(filled, 'qwen3.5'), isFalse);
      expect(matches(makeNote('b', body: 'A ??doubt??(check with Sam)'), 'sam'), isTrue);
    });

    test('finds a to-do’s priority by its name, and its person and day as written (docs/DESIGN.md §158)', () {
      final sprint = makeNote('a', body: '# Sprint\n\n- [ ] Fix the login loop @sam ⏫ 📅 2026-10-03\n- [ ] Tidy up 🔽');
      expect(matches(sprint, 'high priority'), isTrue);
      expect(matches(sprint, 'login high'), isTrue);
      expect(matches(sprint, 'low'), isTrue);
      expect(matches(sprint, 'lowest'), isFalse);
      expect(matches(sprint, 'sam 2026-10-03'), isTrue);
      expect(matches(makeNote('b', body: 'Inline code `⏫` is not a priority'), 'high'), isFalse);
    });

    test('shows every note for a blank search', () {
      expect(matches(makeNote('a', body: '# Trip'), ''), isTrue);
      expect(matches(makeNote('a', body: '# Trip'), '   '), isTrue);
    });

    test('the search finds what the rule finds, from the reading it keeps of each note', () {
      // The search looks through a reading of each note made once and kept (lib/core/note_text.dart `searchText`).
      // The rule is the page's, written out here as it was before anything was kept: the note's words with its
      // filled blanks' brackets out, its priorities named, in lower case, made anew at each asking. Whatever the
      // note and whatever is typed, the two say the same, for All notes, for the home page and for `matches`.
      final sign = RegExp('🔺|⏫|🔼|🔽|⏬', unicode: true);
      bool rule(Note note, String query) {
        final words = query.toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
        if (words.isEmpty) return true;
        final priorities = sign.hasMatch(note.body) ? fieldsIn(note.body).where((span) => span.kind == FieldKind.priority).map((span) => '${span.value} priority').join(' ') : '';
        final text = '${plainFills(note.body)} $priorities'.toLowerCase();
        return words.every(text.contains);
      }

      const parts = [
        '# Trip', 'Packing: tent, stove', '- [ ] Fix the login loop @sam ⏫ 📅 2026-10-03', '- [ ] Tidy up 🔽', '- [x] Done 🔺', 'Inline code `⏫` here',
        'Flights on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)', 'Weather: {?weather today}', 'A ??doubt??(check with Sam)',
        '---', 'title: "A Named Note"', 'ÉCOLE İstanbul ǅ', '', '   ', '| a | b |', '```board', 'Mixed CASE Words', '🔼 alone', 'priority', '⏬',
      ];
      const queries = [
        '', '   ', 'trip', 'TRIP packing', 'tent kettle', 'high', 'high priority', 'highest', 'low', 'lowest', 'medium priority', 'memory', 'asked', 'midweek', 'weather today',
        'sam', 'sam 2026-10-03', 'école', 'istanbul', 'ǆ', 'named note', 'board', 'priority', 'a b', '⏫', '🔽', 'case  words', ' login ',
      ];
      var seed = 20261010;
      int next(int below) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed % below;
      }

      final notes = [
        for (var n = 0; n < 400; n += 1)
          makeNote('n$n', body: [for (var line = next(7); line >= 0; line -= 1) parts[next(parts.length)]].join('\n'), updatedAt: n),
      ];
      for (final query in queries) {
        final found = [
          for (final note in notes)
            if (rule(note, query)) note.id,
        ]..sort();
        expect(ids(browseNotes(notes, Browse(query: query)))..sort(), found, reason: 'All notes, typed "$query"');
        final home = homeLists(notes, query, HomeFilter.all);
        expect(ids([...home.books, ...home.notes])..sort(), found, reason: 'the home page, typed "$query"');
        expect([for (final note in notes) if (matches(note, query)) note.id]..sort(), found, reason: 'matches, typed "$query"');
      }
      // A note changed is read again: the same id with other words is found by the new ones and not the old.
      final was = makeNote('same', body: '# Kettle');
      final now = makeNote('same', body: '# Stove');
      expect(ids(browseNotes([was], const Browse(query: 'kettle'))), ['same']);
      expect(ids(browseNotes([now], const Browse(query: 'kettle'))), isEmpty);
      expect(ids(browseNotes([now], const Browse(query: 'stove'))), ['same']);
      expect(searchText(now), '# stove ');
    });
  });

  group('the order and the archive', () {
    final notes = [
      makeNote('old', body: '# Zebra', updatedAt: 1),
      makeNote('new', body: '# apple', updatedAt: 3),
      makeNote('blank', body: '', updatedAt: 2),
      makeNote('gone', body: '# Mango', updatedAt: 4, archivedAt: 5),
    ];

    test('puts the last touched first, and keeps the archive out unless asked', () {
      expect(ids(browseNotes(notes, const Browse())), ['new', 'blank', 'old']);
      expect(ids(browseNotes(notes, const Browse(archived: true))), ['gone', 'new', 'blank', 'old']);
    });

    test('orders by name whatever the case, with a nameless note after every name', () {
      expect(ids(browseNotes(notes, const Browse(sort: AllNotesSort.title, archived: true))), ['new', 'gone', 'old', 'blank']);
    });

    test('narrows to the search first', () {
      expect(browseNotes(notes, const Browse(query: 'mango')), isEmpty);
      expect(ids(browseNotes(notes, const Browse(query: 'mango', archived: true))), ['gone']);
    });

    test('does not reorder the notes it was given', () {
      final before = ids(notes);
      browseNotes(notes, const Browse(sort: AllNotesSort.title, archived: true));
      expect(ids(notes), before);
    });

    test('counts the archive', () {
      expect(archivedCount(notes), 1);
      expect(archivedCount(const <Note>[]), 0);
    });
  });

  group('the tapes', () {
    final notes = [
      makeNote('spoken', body: '# Spoken', source: NoteSource.capture, recordingMs: 40000, updatedAt: 4),
      makeNote('typed', body: '# Typed then spoken', recordingMs: 12000, updatedAt: 3),
      makeNote('plain', body: '# Plain', updatedAt: 2),
      makeNote('removed', body: '# Removed', source: NoteSource.capture, updatedAt: 1),
      makeNote('gone', body: '# Gone', source: NoteSource.capture, recordingMs: 9000, updatedAt: 5, archivedAt: 6),
    ];

    test('shows only the notes with a recording when asked, typed ones included, and the archive still only when asked', () {
      expect(ids(browseNotes(notes, const Browse(tapes: true))), ['spoken', 'typed']);
      expect(ids(browseNotes(notes, const Browse(archived: true, tapes: true))), ['gone', 'spoken', 'typed']);
      expect(ids(browseNotes(notes, const Browse(query: 'typed', tapes: true))), ['typed']);
    });

    test('knows a tape by its recording, and counts them', () {
      expect(notes.map(hasTape), [true, true, false, false, true]);
      expect(tapeCount(notes), 3);
      expect(tapeCount(notes.where((n) => n.archivedAt == null)), 2);
    });
  });

  group('the order kept on the device', () {
    test('is newest first until another is chosen, and only ever one of the two', () {
      final kept = MemoryStored();
      expect(readSort(kept), AllNotesSort.newest);
      writeSort(AllNotesSort.title, kept);
      expect(readSort(kept), AllNotesSort.title);
      expect(kept.getItem('glyph-all-notes-sort'), 'title');
      kept.setItem('glyph-all-notes-sort', 'sideways');
      expect(readSort(kept), AllNotesSort.newest);
    });

    test('is the two the page offers, by these words', () {
      expect([for (final each in sorts) (each.id, each.label)], [('newest', 'Newest'), ('title', 'A to Z')]);
    });
  });
}
