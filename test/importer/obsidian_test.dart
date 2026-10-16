import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/json_canvas.dart' show canvasOf;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/importer/import_report.dart';
import 'package:ghost_md/importer/import_sources.dart';
import 'package:ghost_md/importer/import_target.dart';
import 'package:ghost_md/importer/obsidian.dart';
import 'package:ghost_md/importer/obsidian_links.dart';

import 'support.dart';

/// Settings › Import › Obsidian vault (lib/importer/obsidian.dart), over the vault in fixtures/vault: notes in
/// folders, front matter, wiki links and embeds, attachments by name, by a relative path and by a path with a
/// space, a canvas, a broken canvas, files nothing links to, a missing picture, and Obsidian's own folders.
void main() {
  const root = 'workspaces/Imported from Obsidian 2026-10-16';

  group('a vault', () {
    late ImportHarness it;
    late ImportReport report;
    // A note already where the vault's Welcome.md would go: the import must not write over it.
    final theirs = Note(id: 'mine', body: 'Mine, not the vault’s.\n', createdAt: 1, updatedAt: 1, path: '$root/Welcome.md');

    setUp(() async {
      it = ImportHarness(notes: [theirs]);
      report = await importObsidianVault(DirectoryFolder(fixture('vault')), it.target());
    });
    tearDown(() => it.dispose());

    test('counts what it brought and what it left', () {
      expect(report.notes, 7, reason: 'six notes and the list of files nothing linked to');
      expect(report.canvases, 1);
      expect(report.pictures, 2, reason: 'photo.png and diagram one.png; the GIF is not a picture the library keeps');
      expect(report.files, 4, reason: 'lease.pdf, report.pdf (kept once for two notes), loose.txt and spin.gif');
      expect(report.missing, 1, reason: 'Missing.md names nothere.png');
      expect(report.skipped, [
        '.obsidian/, Obsidian’s settings',
        '.trash/, Obsidian’s trash',
        'Projects/.hidden/, a hidden folder',
        'Broken.canvas, not a canvas Ghost.md can read',
      ]);
      expect(importDoneSaid(report), 'Imported 7 notes, 1 canvas, 2 pictures and 4 files, in the workspace Imported from Obsidian 2026-10-16.');
      expect(importSkippedSaid(report), contains('1 link to a missing file'));
    });

    test('never writes over a note: a taken name gets a number, and the report says so', () {
      expect(it.library.noteOf('mine')!.body, 'Mine, not the vault’s.\n');
      expect(it.at('$root/Welcome 2.md'), isNotNull);
      expect(report.renamed, [(from: 'Welcome.md', to: 'Welcome 2.md')]);
      expect(importRenamedSaid(report), 'A name was taken, so one note has another: Welcome.md is now Welcome 2.md.');
    });

    test('keeps the vault’s folders inside the workspace’s', () {
      final paths = {for (final note in it.library.value) if (note.id != 'mine') note.path};
      expect(paths, {
        '$root/Daily/2026-10-15.md',
        '$root/Missing.md',
        '$root/Projects/Alpha.md',
        '$root/Projects/alpha notes.md',
        '$root/Projects/Board.md',
        '$root/Welcome 2.md',
        '$root/Ünïcödé 日本.md',
        '$root/Files from vault.md',
      });
    });

    test('files everything in one workspace, which takes it all away in one go', () {
      final spaces = it.workspaces.value;
      expect(spaces.list.map((w) => w.name), ['Imported from Obsidian 2026-10-16']);
      final id = spaces.list.single.id;
      expect(report.groupId, id);
      expect(report.noteIds, hasLength(8));
      for (final note in report.noteIds) {
        expect(spaces.of[note], id);
      }
      expect(spaces.of.containsKey('mine'), isFalse);
      removeImport(it.workspaces, report);
      expect(it.workspaces.value.list, isEmpty);
      expect(it.trash.value.keys.toSet(), report.noteIds.toSet());
      expect(it.trash.isTrashed('mine'), isFalse);
    });

    test('keeps front matter and note links as written, and points attachments at their copies', () {
      final welcome = it.at('$root/Welcome 2.md')!.body;
      expect(welcome, startsWith('---\ntags:\n  - start\n  - garden\naliases: [Home]\n---\n# Welcome\n'));
      expect(welcome, contains('[[Projects/Alpha]] and [[Alpha|the alpha plan]], and embeds a note: ![[Alpha#Plan]].'));
      expect(welcome, contains('A picture by its name alone:\n\n![](image/p2.png)\n'));
      expect(welcome, contains('And one with a size: ![](image/p2.png)'));
      final lease = RegExp(r'\[lease\]\((file/[0-9a-f-]{36}\.pdf)\)').firstMatch(welcome)!.group(1)!;
      final report = RegExp(r'\[quarterly report\]\((file/[0-9a-f-]{36}\.pdf)\)').firstMatch(welcome)!.group(1)!;
      expect(it.files[lease.substring(5)], utf8.encode('%PDF-1.4\n% a tiny stand-in for a lease\n%%EOF\n'));
      expect(it.files[report.substring(5)], utf8.encode('%PDF-1.4\n% the quarterly report\n%%EOF\n'));
      // Code is never rewritten, fenced or inline; nor is the web.
      expect(welcome, contains('```\n![[photo.png]] stays as written inside code\n```'));
      expect(welcome, contains('Inline `![[photo.png]]` too.'));
      expect(welcome, contains('[Obsidian](https://obsidian.md) and ![remote](https://example.com/x.png)'));
      final alpha = it.at('$root/Projects/Alpha.md')!.body;
      expect(alpha, contains('![A diagram](image/p1.png)'));
      // report.pdf was kept once, for both notes that name it.
      expect(alpha, contains('See [report.pdf]($report) and <https://example.com>.'));
      expect(it.pictures.keys.toSet(), {'p1.png', 'p2.png'});
      expect(it.at('$root/Missing.md')!.body, 'This one names a picture that is not there: ![[nothere.png]]\n');
      expect(it.at('$root/Ünïcödé 日本.md')!.body, 'Ünïcödé — 日本語のノート 🌱\n');
    });

    test('makes a canvas of a .canvas, its picture card pointed at the kept picture', () {
      final board = it.at('$root/Projects/Board.md')!.body;
      expect(board, startsWith('---\ntitle: "Board"\n---\n{'));
      final canvas = canvasOf(board)!;
      expect(canvas.nodes.map((n) => n.id), ['t1', 'f1', 'p1', 'g1']);
      expect(canvas.nodes.firstWhere((n) => n.id == 'p1').file, 'p2.png');
      expect(canvas.nodes.firstWhere((n) => n.id == 'f1').file, 'Projects/Alpha.md');
      expect(canvas.edges.single.id, 'e1');
    });

    test('lists what no note linked to, so nothing in the vault is lost', () {
      final files = it.at('$root/Files from vault.md')!.body;
      expect(files, startsWith('# Files from vault\n'));
      expect(files, contains(RegExp(r'- \[attachments/loose\.txt\]\(file/[0-9a-f-]{36}\.txt\)')));
      expect(files, contains(RegExp(r'- \[attachments/spin\.gif\]\(file/[0-9a-f-]{36}\.gif\)')));
    });

    test('dates each note by its file', () {
      final daily = it.at('$root/Daily/2026-10-15.md')!;
      expect(daily.updatedAt, greaterThan(0));
      expect(daily.createdAt, daily.updatedAt);
      expect(daily.body, '- [ ] Water the plants\n- [x] Call Sam #home\n');
    });
  });

  test('a second import the same day is a group of its own', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final first = await importObsidianVault(DirectoryFolder(fixture('vault')), it.target());
    final second = await importObsidianVault(DirectoryFolder(fixture('vault')), it.target());
    expect(first.groupName, 'Imported from Obsidian 2026-10-16');
    expect(second.groupName, 'Imported from Obsidian 2026-10-16 (2)');
    expect(second.renamed, isEmpty);
    expect(it.at('workspaces/Imported from Obsidian 2026-10-16 (2)/Welcome.md'), isNotNull);
  });

  test('an import stopped keeps what it made, filed', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    var asked = 0;
    final report = await importObsidianVault(DirectoryFolder(fixture('vault')), it.target(), stopped: () => ++asked > 2);
    expect(report.notes, 2);
    expect(it.workspaces.value.of.length, 2);
  });

  test('an empty folder makes no workspace', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final report = await importObsidianVault(DirectoryFolder(it.data.path), it.target());
    expect(report.empty, isTrue);
    expect(report.groupId, isNull);
    expect(it.workspaces.value.list, isEmpty);
    expect(importDoneSaid(report), 'Nothing was imported.');
  });

  group('references', () {
    test('found outside code, and only attachments', () {
      final refs = attachmentRefs('![[a.png]] [[Note]] [x](b.pdf) `![[c.png]]` [w](https://x.com/d.png) ![[Note.md]]\n```\n![[e.png]]\n```\n');
      expect(refs.map((r) => (r.target, r.embed, r.wiki)), [('a.png', true, true), ('b.pdf', false, false)]);
    });

    test('resolved as Obsidian resolves them', () {
      final vault = VaultResolver(['attachments/photo.png', 'Projects/img/plan.png', 'plan.png', 'Docs/a b.pdf']);
      expect(vault.resolve('photo.png', const []), 'attachments/photo.png', reason: 'by its name alone');
      expect(vault.resolve('img/plan.png', const ['Projects']), 'Projects/img/plan.png', reason: 'from the note’s folder');
      expect(vault.resolve('../plan.png', const ['Projects']), 'plan.png');
      expect(vault.resolve('PLAN.PNG', const []), 'plan.png', reason: 'from the top, ignoring case');
      expect(vault.resolve('Docs/a b.pdf', const ['Elsewhere']), 'Docs/a b.pdf');
      expect(vault.resolve('nothere.png', const []), isNull);
    });

    test('rewritten in place, with captions and words', () {
      Landed? landed(AttachmentRef ref) => ref.target.endsWith('.png') ? (ref: 'image/x.png', picture: true) : (ref: 'file/y.pdf', picture: false);
      expect(rewriteAttachments('![[a.png|A cat]] ![[a.png|200x100]] [[r.pdf]] [[r.pdf|The report]] ![[r.pdf]] ![alt](<a b.png>) [t](r.pdf "title")', landed),
          '![A cat](image/x.png) ![](image/x.png) [r.pdf](file/y.pdf) [The report](file/y.pdf) [r.pdf](file/y.pdf) ![alt](image/x.png) [t](file/y.pdf)');
    });
  });
}
