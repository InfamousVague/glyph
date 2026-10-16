import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart' show chaptersOf, isBookBody;
import 'package:ghost_md/importer/evernote.dart';
import 'package:ghost_md/importer/import_report.dart';
import 'package:ghost_md/importer/import_sources.dart';
import 'package:ghost_md/importer/import_target.dart';

import 'support.dart';

/// Settings › Import › Evernote export (lib/importer/evernote.dart), over fixtures/evernote/Recipes.enex: a note
/// with every kind of ENML, a picture, a PDF and a resource the body never names, tags with spaces and a number, an
/// encrypted passage, a note with no title and two with the same; and a 2 MB note.
void main() {
  const root = 'workspaces/Imported from Evernote 2026-10-16';

  group('an export', () {
    late ImportHarness it;
    late ImportReport report;
    setUp(() async {
      it = ImportHarness();
      report = await importEvernote([DirectoryFile(fixture('evernote/Recipes.enex'))], it.target());
    });
    tearDown(() => it.dispose());

    test('counts what it brought and what it left', () {
      expect(report.notes, 3);
      expect(report.notebooks, 1);
      expect(report.pictures, 2, reason: 'the pancake and the picture no line names');
      expect(report.files, 1, reason: 'the menu');
      expect(report.missing, 1, reason: 'an en-media whose hash no resource has');
      expect(report.skipped, ['one encrypted passage, which Evernote keeps locked']);
      expect(report.renamed, [(from: 'Pancakes & more.md', to: 'Pancakes & more 2.md')]);
      expect(importDoneSaid(report), 'Imported 3 notes, 1 notebook, 2 pictures and 1 file, in the workspace Imported from Evernote 2026-10-16.');
    });

    test('a note: its title, its tags as marks, its body, its pictures and files, where it was clipped from', () {
      final note = it.at('$root/Recipes/Pancakes & more.md')!;
      final body = note.body;
      expect(body, startsWith('# Pancakes & more\n\n#Breakfast #Quick-meals #tag-2024\n\n# Pancakes\n\nMakes **eight**, *thin* and **golden**, ~~never~~ burnt.\n'));
      expect(body, contains('- [x] Eggs\n- [ ] Milk'));
      expect(body, contains('- [x] Butter\n- [ ] Lemons'));
      expect(body, contains('1. Mix\n2. Rest\n   - ten minutes\n   - covered\n3. Fry'));
      expect(body, contains('| Item | Grams |\n| --- | --- |\n| Flour | 200 |\n| Sugar \\| fine | 20 |'));
      expect(body, contains('```\nlet x = 1;\n  if (x < 2) x++;\n```'));
      expect(body, contains('[the recipe](https://example.com/pancakes) and [[Waffles]]'));
      expect(body, contains('\n![](image/p1.png)\n'));
      expect(body, contains(RegExp(r'The menu: \[Menu\.pdf\]\(file/[0-9a-f-]{36}\.pdf\)')));
      expect(body, contains('Ünïcödé — 日本語 🥞 مرحبا'));
      // The resource the body never names, at the end, then the source.
      expect(body, endsWith('![](image/p2.png)\n\n[Source](https://example.com/clip)\n'));
      expect(note.createdAt, DateTime.utc(2024, 1, 2, 3, 4, 5).millisecondsSinceEpoch);
      expect(note.updatedAt, DateTime.utc(2025, 6, 7, 8, 9, 10).millisecondsSinceEpoch);
    });

    test('a note with no title, and two with the same, none written over', () {
      expect(it.at('$root/Recipes/Untitled.md')!.body, '# Untitled\n\nA note with no title.\n');
      expect(it.at('$root/Recipes/Pancakes & more 2.md')!.body, '# Pancakes & more\n\nSame title, a second note.\n');
      expect(it.at('$root/Recipes/Untitled.md')!.updatedAt, DateTime.utc(2024).millisecondsSinceEpoch, reason: 'no updated date: the created one');
    });

    test('the notebook is a notebook of its notes, beside their folder, and all of it in one workspace', () {
      final book = it.at('$root/Recipes.md')!.body;
      expect(isBookBody(book), isTrue);
      expect(chaptersOf(book).map((c) => c.title), ['Pancakes & more', 'Untitled']);
      final id = it.workspaces.value.list.single.id;
      expect(it.workspaces.value.list.single.name, 'Imported from Evernote 2026-10-16');
      expect(report.noteIds.every((note) => it.workspaces.value.of[note] == id), isTrue);
      removeImport(it.workspaces, report);
      expect(it.trash.value.length, 4);
    });
  });

  test('tags as the app reads them', () {
    expect(tagMark('Quick meals'), '#Quick-meals');
    expect(tagMark('work/clients'), '#work/clients');
    expect(tagMark('2024'), '#tag-2024');
    expect(tagMark('Ünï cödé'), '#Ünï-cödé');
    expect(tagMark('!!!'), isNull);
  });

  test('a 2 MB note, its words turned into Markdown away from the screen', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final line = '<div>${'Lorem ipsum dolor sit amet, ünïcödé 日本 ' * 25}</div>';
    final body = '<en-note>${line * (2 * 1024 * 1024 ~/ line.length + 1)}</en-note>';
    final file = File('${it.data.path}/Big notebook.enex')
      ..writeAsStringSync('<?xml version="1.0" encoding="UTF-8"?>\n<en-export><note><title>Big</title><created>20240101T000000Z</created><content><![CDATA[$body]]></content></note></en-export>');
    final report = await importEvernote([DirectoryFile(file.path)], it.target());
    expect(report.notes, 1);
    final note = it.at('workspaces/Imported from Evernote 2026-10-16/Big notebook/Big.md')!;
    expect(note.body.length, greaterThan(1900000));
    expect(note.body, startsWith('# Big\n\nLorem ipsum dolor sit amet, ünïcödé 日本 Lorem'));
  });

  test('a file that is not an export is said, and the rest still come in', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final bad = File('${it.data.path}/Not one.enex')..writeAsStringSync('<en-export><note><title>Half</title><content><![CDATA[<en-note/>]]></content></note><note><title>Cut<');
    final report = await importEvernote([DirectoryFile(bad.path), DirectoryFile(fixture('evernote/Recipes.enex'))], it.target());
    expect(report.skipped.first, startsWith('Not one.enex after 1 notes, which could not be read'));
    expect(report.notes, 4);
    expect(report.notebooks, 2);
  });

}
