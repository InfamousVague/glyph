import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/export/ghostex.dart';

import 'support.dart';

/// Settings › Account › Export everything (lib/export/ghostex.dart), over a library with something of everything
/// (support.dart `everything`): the file's name, the manifest and the paths in the ZIP, unsafe titles, and each
/// option honoured.
void main() {
  final at = DateTime(2026, 10, 17, 9, 41);

  /// The ZIP at [path], each entry's bytes by its name.
  Map<String, List<int>> unzip(String path) {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return {for (final file in archive.files) if (file.isFile) file.name: file.readBytes() ?? const <int>[]};
    } finally {
      input.closeSync();
    }
  }

  Map<String, Object?> manifestOf(Map<String, List<int>> zip) => (jsonDecode(utf8.decode(zip['manifest.json']!)) as Map).cast<String, Object?>();

  Map<String, Object?> noteIn(Map<String, Object?> manifest, String id) => ((manifest['notes']! as List).cast<Map>().firstWhere((n) => n['id'] == id)).cast<String, Object?>();

  group('names', () {
    test('the file is <handle>-<YYYY-MM-DD>.ghostex, on the device’s clock', () {
      expect(ghostexName('matt', at), 'matt-2026-10-17.ghostex');
      expect(ghostexName(null, at), 'ghost-2026-10-17.ghostex');
      expect(ghostexName('', DateTime(2026, 1, 5)), 'ghost-2026-01-05.ghostex');
      expect(ghostexName('a/b c', at), 'a-b-c-2026-10-17.ghostex');
    });

    test('a title becomes a name every disk holds', () {
      expect(ghostexFileName('Plan'), 'Plan');
      expect(ghostexFileName('a/b:c*?"<>|d'), 'a b c d');
      expect(ghostexFileName('../secret'), 'secret');
      expect(ghostexFileName('  .hidden. '), 'hidden');
      expect(ghostexFileName(''), 'Untitled');
      expect(ghostexFileName('\u0000\u0007'), 'Untitled');
      expect(ghostexFileName('CON'), 'CON (note)');
      expect(ghostexFileName('lpt1.txt'), 'lpt1.txt (note)');
      expect(ghostexFileName('Console'), 'Console');
      expect(ghostexFileName('Ünïcödé 日本'), 'Ünïcödé 日本');
      final long = ghostexFileName('日本' * 100);
      expect(utf8.encode(long).length, lessThanOrEqualTo(120));
      expect(long, '日本' * 20, reason: 'cut at a whole character, never inside one');
      expect(ghostexFileName('${'a' * 119} 😀 tail'), 'a' * 119, reason: 'an emoji is never cut in half, and the space before the cut goes');
    });

    test('two notes of one title in one folder are told apart, without case', () {
      final names = GhostexNames();
      expect(names.place('notes', 'Same', 'md'), 'notes/Same.md');
      expect(names.place('notes', 'same', 'md'), 'notes/same 2.md');
      expect(names.place('notes', 'Same', 'md'), 'notes/Same 3.md');
      expect(names.place('notes/Work', 'Same', 'md'), 'notes/Work/Same.md');
    });
  });

  group('an export with nothing ticked', () {
    late GhostexDevice device;
    late GhostexWritten written;
    late Map<String, List<int>> zip;
    late Map<String, Object?> manifest;

    setUpAll(() async {
      device = everything();
      written = await writeGhostex(device.source(), const GhostexOptions(), device.path('out.ghostex'), at: at, app: 'Ghost.md 2.1.0');
      zip = unzip(written.path);
      manifest = manifestOf(zip);
    });
    tearDownAll(() => device.dispose());

    test('is a ZIP with the manifest first, and no part file left beside it', () {
      final input = InputFileStream(written.path);
      try {
        expect(ZipDecoder().decodeStream(input).files.first.name, 'manifest.json');
      } finally {
        input.closeSync();
      }
      expect(File('${written.path}.part').existsSync(), isFalse);
      expect(written.bytes, File(written.path).lengthSync());
    });

    test('the manifest says what it is', () {
      expect(manifest['format'], 'ghostex');
      expect(manifest['version'], 1);
      expect(manifest['exportedAt'], at.toUtc().toIso8601String());
      expect(manifest['app'], 'Ghost.md 2.1.0');
      expect(manifest['options'], {'archived': false, 'organizations': false, 'recordings': false});
    });

    test('lists every note but the archived, the organization’s and the trashed', () {
      final ids = [for (final n in manifest['notes']! as List) (n as Map)['id']];
      expect(ids, ['plan', 'acme', 'loose', 'same2', 'same3', 'unsafe', 'con', 'book', 'canvas', 'spoken']);
      expect(written.notes, 10);
    });

    test('each note with its id, path, title, dates, pin, archive, workspace, organization and tags', () {
      expect(noteIn(manifest, 'plan'), {
        'id': 'plan',
        'path': 'notes/Work/Plan.md',
        'title': 'Plan',
        'created': '2026-09-01T08:30:15.123Z',
        'updated': '2026-09-01T08:30:16.123Z',
        'pinned': true,
        'archived': false,
        'workspace': 'w-work',
        'organization': null,
        'tags': ['planning', 'work'],
        'source': 'editor',
        'pictures': [pictureA],
      });
      expect(noteIn(manifest, 'acme')['files'], [fileA]);
      expect(noteIn(manifest, 'canvas')['pictures'], [pictureB], reason: 'a canvas’s picture card names its picture bare');
      expect(noteIn(manifest, 'spoken')['source'], 'capture');
      expect(noteIn(manifest, 'spoken').containsKey('recording'), isFalse);
    });

    test('paths: the workspace’s folder, folders inside folders, none for a note in none, and safe unique names', () {
      final paths = {for (final n in manifest['notes']! as List) (n as Map)['id']: n['path']};
      expect(paths, {
        'plan': 'notes/Work/Plan.md',
        'acme': 'notes/Work/Clients/Acme.md',
        'loose': 'notes/Same.md',
        'same2': 'notes/Work/Same.md',
        'same3': 'notes/same 2.md',
        'unsafe': 'notes/a b c.md',
        'con': 'notes/CON (note).md',
        'book': 'notes/Work/The Book.md',
        'canvas': 'notes/Board.md',
        'spoken': 'notes/Spoken.md',
      });
      for (final path in paths.values) {
        expect(zip.containsKey(path), isTrue, reason: '$path is in the ZIP');
      }
    });

    test('each note’s markdown is its body, front matter included', () {
      expect(utf8.decode(zip['notes/Work/Plan.md']!), device.library.noteOf('plan')!.body);
      expect(utf8.decode(zip['notes/Work/The Book.md']!), startsWith('---\nbook: true\n---\n'));
    });

    test('the pictures and files the notes name, and no recordings', () {
      expect(zip['pictures/$pictureA'], jpeg);
      expect(zip['pictures/$pictureB'], png);
      expect(zip['files/$fileA'], pdf);
      expect(zip.keys.where((k) => k.startsWith('recordings/')), isEmpty);
      expect(manifest['pictures'], [pictureA, pictureB]);
      expect(manifest['files'], [fileA]);
      expect((written.pictures, written.files, written.recordings, written.missing), (2, 1, 0, 0));
    });

    test('the workspaces the notes are in, with their hues and parents; the notebooks with their pages', () {
      expect(manifest['workspaces'], [
        {'id': 'w-work', 'name': 'Work', 'folder': 'Work', 'hue': 'sea', 'parent': null, 'organization': null},
        {'id': 'w-clients', 'name': 'Clients', 'folder': 'Work/Clients', 'hue': null, 'parent': 'w-work', 'organization': null},
      ]);
      expect(manifest['notebooks'], [
        {'id': 'book', 'title': 'The Book', 'journal': false, 'pages': ['Plan', 'Acme']},
      ]);
    });

    test('says what it wrote', () {
      expect(ghostexDoneSaid(written, name: 'matt-2026-10-17.ghostex'), 'Exported 10 notes, 2 pictures and 1 file as matt-2026-10-17.ghostex.');
    });
  });

  group('the options', () {
    late GhostexDevice device;
    setUp(() => device = everything());
    tearDown(() => device.dispose());

    test('archived notes, organizations’ notes and recordings, each when ticked', () async {
      final written = await writeGhostex(device.source(), const GhostexOptions(archived: true, organizations: true, recordings: true), device.path('all.ghostex'), at: at);
      final zip = unzip(written.path);
      final manifest = manifestOf(zip);
      final ids = [for (final n in manifest['notes']! as List) (n as Map)['id']];
      expect(ids, containsAll(['old', 'team']));
      expect(ids, isNot(contains('binned')), reason: 'the trash is never exported');
      expect(noteIn(manifest, 'old')['archived'], true);
      expect(noteIn(manifest, 'old')['archivedAt'], '2026-09-01T08:30:27.123Z');
      expect(noteIn(manifest, 'team'), containsPair('workspace', 'org-acme'));
      expect(noteIn(manifest, 'team'), containsPair('organization', 'acme'));
      expect(noteIn(manifest, 'team')['path'], 'notes/Acme Team/Standup.md');
      expect(noteIn(manifest, 'spoken')['recording'], {
        'path': 'recordings/spoken.wav',
        'ms': 4200,
        'segments': [
          {'start': 0, 'end': 1500, 'text': 'Hello'},
          {'start': 1500, 'end': 4200, 'text': 'there.'},
        ],
      });
      expect(zip['recordings/spoken.wav'], wav);
      expect((manifest['workspaces']! as List).map((w) => (w as Map)['id']), ['w-work', 'w-clients', 'org-acme']);
      expect(((manifest['workspaces']! as List).last as Map)['organization'], 'acme');
      expect(written.recordings, 1);
      expect(manifest['options'], {'archived': true, 'organizations': true, 'recordings': true});
    });

    test('what a note names that is not on this device is left out and counted', () async {
      File(device.path('pictures/$pictureA')).deleteSync();
      final written = await writeGhostex(device.source(), const GhostexOptions(recordings: true), device.path('some.ghostex'), at: at);
      final zip = unzip(written.path);
      expect(zip.containsKey('pictures/$pictureA'), isFalse);
      expect(manifestOf(zip)['pictures'], [pictureB]);
      expect(written.missing, 1);
      expect(ghostexDoneSaid(written), endsWith('One file a note names is not on this device, and not in it.'));
    });

    test('a password needs something to seal with', () async {
      await expectLater(writeGhostex(device.source(), const GhostexOptions(password: 'pw'), device.path('x.ghostex'), at: at), throwsStateError);
      expect(File(device.path('x.ghostex')).existsSync(), isFalse);
    });

    test('two workspaces whose names come out the same have folders of their own', () async {
      final store = device.workspaces;
      final a = store.addWorkspace('A:B')!, b = store.addWorkspace('A?B')!;
      final one = await device.library.createNote('# One\n', id: 'one');
      final two = await device.library.createNote('# Two\n', id: 'two');
      store.fileNote(one.id, a.id);
      store.fileNote(two.id, b.id);
      final written = await writeGhostex(device.source(), const GhostexOptions(), device.path('folders.ghostex'), at: at);
      final manifest = manifestOf(unzip(written.path));
      expect(noteIn(manifest, 'one')['path'], 'notes/A B/One.md');
      expect(noteIn(manifest, 'two')['path'], 'notes/A B 2/Two.md');
    });
  });

  test('a note with nothing in it still has a name', () async {
    final device = GhostexDevice(notes: [const Note(id: 'blank', body: '', createdAt: 1, updatedAt: 2)]);
    addTearDown(device.dispose);
    final written = await writeGhostex(device.source(), const GhostexOptions(), device.path('blank.ghostex'), at: at);
    final input = InputFileStream(written.path);
    addTearDown(input.closeSync);
    final archive = ZipDecoder().decodeStream(input);
    expect(archive.files.map((f) => f.name), ['manifest.json', 'notes/Untitled.md']);
  });

  test('a picture name in a body is only ever one the app makes', () {
    expect(ghostexPictures('![x](image/a.jpg) ![y](image/../../etc.png)'), ['a.jpg']);
    expect(workspacePath(const [Workspace(id: 'a', name: 'A')], 'a').single.name, 'A');
  });
}
