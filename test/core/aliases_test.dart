import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/aliases.dart';
import 'package:ghost_md/core/note_text.dart';

import 'make_note.dart';

/// The other names a note answers to (lib/core/aliases.dart): every way Obsidian has written `aliases:`.
void main() {
  group('aliases', () {
    test('a list in brackets, quoted or not', () {
      expect(aliasesOf('---\naliases: [Lisbon, "The trip", \'Ana\'\'s plan\']\n---\n# Trip'), ['Lisbon', 'The trip', "Ana's plan"]);
    });

    test('a list with commas, and a comma inside quotes kept', () {
      expect(aliasesOf('---\naliases: Lisbon, The trip\n---\n# Trip'), ['Lisbon', 'The trip']);
      expect(aliasesOf('---\naliases: "Lisbon, Portugal", Porto\n---\n'), ['Lisbon, Portugal', 'Porto']);
    });

    test('a list of lines, as Obsidian writes it since 1.4', () {
      const body = '---\ntitle: Trip\naliases:\n  - Lisbon\n  - "The trip"\ntags:\n  - travel\n---\n# Trip';
      expect(aliasesOf(body), ['Lisbon', 'The trip']);
    });

    test('the old one-name key, any case, and Windows line ends', () {
      expect(aliasesOf('---\nAlias: Lisbon\n---\n'), ['Lisbon']);
      expect(aliasesOf('---\r\naliases: [Lisbon]\r\n---\r\nWords'), ['Lisbon']);
    });

    test('nothing for a note with no front matter, an empty list, or front matter never closed', () {
      expect(aliasesOf('# Trip\n\naliases: [Lisbon]'), isEmpty);
      expect(aliasesOf('---\naliases: []\n---\n'), isEmpty);
      expect(aliasesOf('---\naliases:\n---\n'), isEmpty);
      expect(aliasesOf('---\naliases: [Lisbon]\n'), isEmpty);
    });

    test('each name once by its key, and none with no letters', () {
      expect(aliasesOf('---\naliases: [Lisbon, lisbon!, "--"]\n---\n'), ['Lisbon']);
    });

    test('a list of lines is not front matter to the rest of the app: the title is what that rule makes of it', () {
      // lib/core/front_matter.dart takes only `key:` lines and blank ones, as the web app and the core do.
      const body = '---\naliases:\n  - Lisbon\n---\n# Trip';
      expect(aliasesOf(body), ['Lisbon']);
      expect(noteTitle(body), '---');
      expect(noteTitle('---\naliases: [Lisbon]\n---\n# Trip'), 'Trip');
    });

    test('kept by the note for the body it has, and read again when the words change', () {
      final note = makeNote('a', body: '---\naliases: [One]\n---\n# A');
      final first = aliasesOfNote(note);
      expect(identical(aliasesOfNote(note), first), isTrue);
      expect(aliasesOfNote(note.copyWith(body: '---\naliases: [Two]\n---\n# A')), ['Two']);
    });
  });
}
