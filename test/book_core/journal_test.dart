import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/chapter_number.dart';
import 'package:ghost_md/book/journal.dart';
import 'package:ghost_md/core/book.dart' show chaptersOf, isBookBody, isJournalBody, withChapter;
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/properties.dart' show withFrontMatterValue;
import 'package:ghost_md/core/title_key.dart';

import '../core/make_note.dart';

/// A journal is a notebook with a template, and its entries are notes named by the minute they were made. The keys
/// it adds, the names, the wall clock an entry keeps, and which notes are some journal's entries. Case for case with
/// the web's `book/journal.test.ts`, less what a Dart test cannot do:
///
/// - **the clock read in another zone**: the page's tests set `process.env.TZ` mid-run, and a Dart process keeps the
///   zone it started in. What those cases hold that does not hang on the zone is held (the stamp has no offset; a
///   `date:` is read as the clock it says, wherever);
/// - **the language asked**: an entry's name is ASCII digits by construction here, where the page had to prove
///   `Intl` was not asked.
final String diary = journalNoteBody('Diary', defaultTemplate, true);

/// Every file [entry] reaches by its own imports and exports, and every package it names.
({Set<String> files, Set<String> packages}) reached(String entry) {
  final files = <String>{}, packages = <String>{};
  final directive = RegExp(r"^(?:import|export)\s+'([^']+)'", multiLine: true);
  void walk(String path) {
    if (!files.add(path)) return;
    for (final found in directive.allMatches(File(path).readAsStringSync())) {
      final target = found.group(1)!;
      if (target.startsWith('dart:') || target.startsWith('package:')) {
        packages.add(target);
      } else {
        walk(File(path).parent.uri.resolve(target).toFilePath());
      }
    }
  }

  walk(File(entry).absolute.path);
  return (files: files, packages: packages);
}

void main() {
  group('a journal note', () {
    test('is a notebook that says so, and only beside book: true', () {
      expect(diary, '---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: "# {{date}}\\n\\n**{{time}}** "\nentry-place: true\n---\n# Diary\n\n');
      expect(isBookBody(diary), isTrue);
      expect(isJournalBody(diary), isTrue);
      expect(isJournalBody('---\njournal: true\n---\n# Not a notebook\n'), isFalse);
      expect(isJournalBody('---\nbook: true\njournal: YES\n---\n'), isTrue);
      expect(isJournalBody('---\nbook: true\njournal: false\n---\n'), isFalse);
      expect(isJournalBody('---\nbook: true\njournal: no\n---\n'), isFalse);
      expect(frontMatterEnd(diary.split('\n')), 7);
      expect(noteTitle(diary), 'Diary');
      expect(entryPlaceOf(diary), isTrue);
      expect(entryPlaceOf(journalNoteBody('Log', defaultTemplate, false)), isFalse);
      expect(entryPlaceOf('---\nbook: true\njournal: true\nentry-place: false\n---\n'), isFalse);
      expect(entryPlaceOf('---\nbook: true\njournal: true\nentry-place: Yes\n---\n'), isTrue);
      // Its name as the heading says it, out of its quotes; no name at all is a Journal.
      expect(journalNoteBody('Say "hi"', defaultTemplate, false), matches(RegExp(r'''^---\ntitle: "Say 'hi'"\n[\s\S]*\n---\n# Say 'hi'\n\n$''')));
      expect(journalNoteBody('  ', defaultTemplate, false), matches(RegExp(r'^---\ntitle: "Journal"\n[\s\S]*\n---\n# Journal\n\n$')));
    });

    test('keeps any template through its one line: quotes, backslashes, curly quotes, emoji and line breaks', () {
      const text = '# {{date}}\n\n"Quoted" and \\back\\slashes, ‘curly’ “quotes” 🌙\n\t- [ ] ';
      final body = journalNoteBody('Moon log', text, false);
      // One line of front matter, whatever the text.
      expect(frontMatterEnd(body.split('\n')), 6);
      expect(templateOf(body), text);
      expect(templateOf(withTemplate(diary, text)), text);
      // The line separators JSON leaves raw are escaped too.
      expect(withTemplate(diary, 'a\u2028b'), contains(r'template: "a\u2028b"'));
      expect(templateOf(withTemplate(diary, 'a\u2028b')), 'a\u2028b');
    });

    test('reads a template written by hand without quotes, with \\n as a line break, and the default where there is none', () {
      expect(templateOf('---\nbook: true\njournal: true\ntemplate: # {{date}}\\n\\n{{time}} \n---\n'), '# {{date}}\n\n{{time}}');
      expect(templateOf("---\nbook: true\njournal: true\ntemplate: 'Just {{time}}'\n---\n"), 'Just {{time}}');
      expect(templateOf('---\nbook: true\njournal: true\n---\n'), defaultTemplate);
      // Only the front matter's: a line in the words that looks like the key is words.
      expect(templateOf('---\nbook: true\njournal: true\n---\ntemplate: "Not this"\n'), defaultTemplate);
    });

    test('changes its template and its place switch without touching the other keys or the index', () {
      final indexed = withEntry(withEntry(diary, '2026-09-27 21.40'), '2026-09-28 08.10');
      final changed = withEntryPlace(withTemplate(indexed, entryPresets[1].text), false);
      expect(frontMatterValue(changed, 'title'), 'Diary');
      expect(frontMatterValue(changed, 'book'), 'true');
      expect(templateOf(changed), '**{{time}}** ');
      expect(entryPlaceOf(changed), isFalse);
      // Off is the key taken out, not a `false` an older app would have to read.
      expect(changed, isNot(contains('entry-place')));
      expect([for (final c in chaptersOf(changed)) c.title], ['2026-09-27 21.40', '2026-09-28 08.10']);
    });

    test('is made from a notebook, and made a notebook again with book: true and every page kept', () {
      const notebook = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Trees]]\n';
      final kept = withJournal(notebook, entryPresets[3].text, false);
      expect(isJournalBody(kept), isTrue);
      expect(templateOf(kept), entryPresets[3].text);
      expect(entryPlaceOf(kept), isFalse);
      expect(withoutJournal(withEntryPlace(kept, true)), notebook);
    });

    test('puts an entry’s line last: after the last line of the index, or after its words when it has none', () {
      expect(withEntry(diary, '2026-09-28 14.05'), '$diary- [[2026-09-28 14.05]]\n');
      final worded = '${diary}Written on the train.\n';
      expect(withEntry(worded, '2026-09-28 14.05'), '${diary}Written on the train.\n\n- [[2026-09-28 14.05]]\n');
      // The next goes after it, whatever time it names: the index is in the order they were made.
      final two = withEntry(withEntry(diary, '2026-09-28 14.05'), '2026-09-27 09.00');
      expect([for (final c in chaptersOf(two)) c.title], ['2026-09-28 14.05', '2026-09-27 09.00']);
      // It is withChapter's append, so a numbered index goes on numbering.
      expect(withEntry('---\nbook: true\njournal: true\n---\n1. [[A]]\n', 'B'), withChapter('---\nbook: true\njournal: true\n---\n1. [[A]]\n', 'B'));
      // At the top level, never a part of the page above it, and numbered on from the last top-level line.
      const kept = '---\nbook: true\njournal: true\n---\n- [[Trip]]\n  - [[Day one]]\n';
      expect(withEntry(kept, '2026-09-28 14.05'), '$kept- [[2026-09-28 14.05]]\n');
      const numbered = '---\nbook: true\njournal: true\n---\n1. [[Trip]]\n   1. [[Day one]]\n';
      expect(withEntry(numbered, '2026-09-28 14.05'), '${numbered}2. [[2026-09-28 14.05]]\n');
      final last = chaptersOf(withEntry(numbered, '2026-09-28 14.05')).last;
      expect((last.title, last.depth), ('2026-09-28 14.05', 0));
      expect(withEntry(kept, 'Day one'), kept);
    });

    test('says what an entry starts with in one fixed sentence, and knows its presets', () {
      expect([for (final p in entryPresets) p.name], ['The date and the time', 'Just the time', 'A morning page', 'A day’s to-dos']);
      expect(entryPresets[0].text, defaultTemplate);
      expect(presetOf(defaultTemplate), 'stamped');
      expect(presetOf(entryPresets[3].text), 'todos');
      expect(presetOf('# {{date}}'), 'own');
      expect(templateSentence(entryPresets[2].text), 'Starts with a question for the morning.');
      expect(templateSentence('Anything'), 'Starts with your own template.');
      for (final preset in entryPresets) {
        expect(preset.sentence, matches(RegExp(r'^[A-Z][^;—–…]*\.$')));
      }
    });
  });

  group('an entry', () {
    test('is named by the minute in ASCII digits, whatever the language', () {
      final at = DateTime(2026, 9, 28, 14, 5);
      expect(entryTitle(at), '2026-09-28 14.05');
      // Its key keeps the month, so September and October are two keys.
      expect(titleKey(entryTitle(at)), '2026 09 28 14 05');
      expect(titleKey(entryTitle(DateTime(2026, 10, 28, 14, 5))), isNot(titleKey(entryTitle(at))));
      expect(entryTitle(DateTime(2026, 1, 2, 7, 9)), '2026-01-02 07.09');
    });

    test('is told by its name, a second in the same minute included, and is not a numbered chapter', () {
      expect(isEntryTitle('2026-09-28 14.05'), isTrue);
      expect(isEntryTitle('2026-09-28 14.05 (2)'), isTrue);
      expect(isEntryTitle('2026-09-28'), isFalse);
      expect(isEntryTitle('Notes 2026-09-28 14.05'), isFalse);
      expect(isEntryTitle('2026-09-28 14.05 later'), isFalse);
      expect(isEntryTitle('Trees'), isFalse);
      expect(chapterOf('2026-09-28 14.05'), isNull);
      expect(chapterOf('2026-09-28 14.05 (2)'), isNull);
    });

    test('takes (2) and then (3) for a minute already taken, matched as titles are', () {
      final keys = {titleKey('2026-09-28 14.05')};
      expect(uniqueTitle('2026-09-28 14.05', keys), '2026-09-28 14.05 (2)');
      keys.add(titleKey('2026-09-28 14.05 (2)'));
      expect(uniqueTitle('2026-09-28 14.05', keys), '2026-09-28 14.05 (3)');
      expect(uniqueTitle('2026-09-28 14.06', keys), '2026-09-28 14.06');
    });

    test('keeps the wall clock it was written at, with no offset', () {
      // In this device's zone: see the header. The same moment given as UTC reads the same clock here.
      final here = DateTime(2026, 9, 28, 14, 5);
      expect(localStamp(here), '2026-09-28T14:05');
      expect(localStamp(here.toUtc()), '2026-09-28T14:05');
      expect(entryTitle(here.toUtc()), '2026-09-28 14.05');
      expect(localStamp(here), isNot(matches(RegExp(r'[+Z]|-\d\d:\d\d$'))));
    });

    test('is a note named by its front matter, with its date, then the words it starts with', () {
      final body = entryBody('2026-09-28 14.05', '2026-09-28T14:05', '# Monday 28 September\n\n**14:05** ');
      expect(body, '---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n# Monday 28 September\n\n**14:05** ');
      expect(noteTitle(body), '2026-09-28 14.05');
      // A heading rewritten, or the words, and the entry keeps its name.
      expect(noteTitle(body.replaceFirst('# Monday 28 September', '# A long walk')), '2026-09-28 14.05');
    });

    test('is ordered by the clock it says it was written at, else when its note was made', () {
      final said = stampOf('---\ndate: 2026-09-28T23:30\n---\nLate.', 0);
      expect(wallIso(said), '2026-09-28T23:30:00.000Z');
      // Wherever it is read, written at half past eleven on the 28th: still the 28th.
      expect(DateTime.fromMillisecondsSinceEpoch(stampOf('---\ndate: 2026-09-28T23:30\n---\n', 0), isUtc: true).day, 28);
      final made = DateTime(2026, 7, 4, 9, 15).millisecondsSinceEpoch;
      expect(wallIso(stampOf('# No date', made)), '2026-07-04T09:15:00.000Z');
      expect(wallIso(stampOf('---\ndate: not a date\n---\n', made)), '2026-07-04T09:15:00.000Z');
    });
  });

  group('which notes are entries', () {
    test('names a journal’s entries and planned pages, never a notebook’s pages, and never the journal', () {
      final journal = makeNote('diary', body: withEntry(withEntry(diary, '2026-09-28 14.05'), 'A plan'));
      final notebook = makeNote('guide', body: '---\ntitle: "Field guide"\nbook: true\n---\n- [[Trees]]\n');
      final entry = makeNote('e1', body: entryBody('2026-09-28 14.05', '2026-09-28T14:05', 'Words.'));
      final plan = makeNote('plan', body: '# A plan');
      final trees = makeNote('trees', body: '# Trees');
      expect(entryPages([journal, notebook, entry, plan, trees]).toList()..sort(), ['e1', 'plan']);
      expect(entryPages([notebook, trees]), isEmpty);
    });
  });

  group('the pure half', () {
    test('reaches nothing that draws or stores', () {
      for (final entry in ['lib/book/journal.dart', 'lib/core/template.dart']) {
        final (:files, :packages) = reached(entry);
        // The annotations of package:flutter/foundation.dart draw nothing; no widget, no painting, no channel.
        expect(packages.where((name) => name != 'dart:convert' && name != 'dart:math' && name != 'package:flutter/foundation.dart'), isEmpty, reason: entry);
        expect(files.where((file) => RegExp(r'/lib/(?:editor|root|note|sheet|home|shell|art)/|core/library\.dart$|core/stored').hasMatch(file)), isEmpty, reason: entry);
      }
    });

    test('keeps every other key when the journal is written', () {
      final body = withFrontMatterValue(diary, 'authors', '"Matt, Claude"');
      expect(frontMatterValue(withoutJournal(withTemplate(body, 'x')), 'authors'), 'Matt, Claude');
    });
  });
}
