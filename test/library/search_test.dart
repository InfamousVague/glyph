import 'package:flutter_test/flutter_test.dart' hide matches;
import 'package:ghost_md/core/search.dart';

import 'support.dart';

/// What the search finds (lib/core/search.dart): the cases of "what the search finds" in the web's
/// `notes/allNotes.test.ts`, which is the page's one rule for a search over the notes (docs/DESIGN.md §115: every
/// word typed must appear somewhere in the note, whatever the case).
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
    });

    test('differs from the web in one row: a priority’s sign in inline code is found here, and is no priority there', () {
      // The web's last line of the case above expects false: it reads the to-dos' fields (core/taskFields.ts), which
      // come with the tickets. Held here so the day that port lands, this is the test that says so.
      expect(matches(makeNote('b', body: 'Inline code `⏫` is not a priority'), 'high'), isTrue);
    });

    test('shows every note for a blank search', () {
      expect(matches(makeNote('a', body: '# Trip'), ''), isTrue);
      expect(matches(makeNote('a', body: '# Trip'), '   '), isTrue);
    });
  });

  group('a search over the notes', () {
    final notes = [makeNote('trip', body: '# Trip\n\nPacking: tent, stove'), makeNote('list', body: '# Groceries\n\n- tent pegs'), makeNote('plan', body: '# Plan')];

    test('keeps the notes with every word, in the order they were given', () {
      expect(ids(searchNotes(notes, 'tent')), ['trip', 'list']);
      expect(ids(searchNotes(notes, 'Tent  PACKING')), ['trip']);
      expect(searchNotes(notes, 'kettle'), isEmpty);
    });

    test('is every note for a blank query, in a list of its own', () {
      final all = searchNotes(notes, '  ');
      expect(ids(all), ['trip', 'list', 'plan']);
      expect(all, isNot(same(notes)));
    });

    test('reads a query as its words, lower case, split at any white space', () {
      expect(searchWords('  Trip\tPACKING\n list '), ['trip', 'packing', 'list']);
      expect(searchWords('   '), isEmpty);
    });
  });
}
