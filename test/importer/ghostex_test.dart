import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/export/ghostex.dart';
import 'package:ghost_md/export/ghostex_calls.dart';
import 'package:ghost_md/export/ghostex_seal.dart';
import 'package:ghost_md/importer/ghostex.dart';
import 'package:ghost_md/share/share_in.dart';

import '../export/support.dart';

const _library = 'native/target/debug/libghost_core.dylib';

/// Settings › Import › A .ghostex file (lib/importer/ghostex.dart): an export read back into an empty library is
/// the library it came from, word for word and file for file; a note already here is skipped or copied as chosen; a
/// protected export opens with its password and with no other (over the real core, lib/export/ghostex_seal.dart).
void main() {
  final at = DateTime(2026, 10, 17, 9, 41);
  const all = GhostexOptions(archived: true, organizations: true, recordings: true);

  Future<String> exported(GhostexDevice from, [GhostexOptions options = all]) async =>
      (await writeGhostex(from.source(), options, from.path('export.ghostex'), at: at)).path;

  group('a round trip into an empty library', () {
    late GhostexDevice from, into;
    late GhostexReport report;

    setUpAll(() async {
      from = everything();
      into = GhostexDevice();
      report = await importGhostex(await exported(from), into.target());
    });
    tearDownAll(() {
      from.dispose();
      into.dispose();
    });

    test('every note it held, and none in the trash', () {
      final ids = {for (final note in into.library.value) note.id};
      expect(ids, {for (final note in from.library.value) if (note.id != 'binned') note.id});
      expect(report.noteIds.toSet(), ids);
    });

    test('identical bodies and metadata', () {
      for (final note in into.library.value) {
        final was = from.library.noteOf(note.id)!;
        expect(note.body, was.body, reason: note.id);
        expect((note.createdAt, note.updatedAt, note.starred, note.archivedAt, note.sourceWord), (was.createdAt, was.updatedAt, was.starred, was.archivedAt, was.sourceWord), reason: note.id);
        expect(note.recordingMs, was.recordingMs, reason: note.id);
        expect(note.segments, was.segments, reason: note.id);
      }
    });

    test('identical pictures, files and recordings', () {
      expect(into.picture(pictureA), jpeg);
      expect(into.picture(pictureB), png);
      expect(into.file(fileA), pdf);
      expect(into.recording('spoken'), wav);
    });

    test('its workspaces by name, hue and nesting; an organization’s as the person’s own', () {
      final spaces = into.workspaces.value;
      String? named(String id) {
        final filed = spaces.of[id];
        return filed == null ? null : spaces.list.firstWhere((w) => w.id == filed).name;
      }

      expect(named('plan'), 'Work');
      expect(named('acme'), 'Clients');
      expect(named('team'), 'Acme Team');
      expect(named('loose'), isNull);
      final work = spaces.list.firstWhere((w) => w.name == 'Work');
      final clients = spaces.list.firstWhere((w) => w.name == 'Clients');
      final team = spaces.list.firstWhere((w) => w.name == 'Acme Team');
      expect(work.hue, 'sea');
      expect(clients.parent, work.id);
      expect(team.org, isNull, reason: 'an import never files a note where it would be shared');
      expect(team.hue, 'ember');
      expect(spaces.list.map((w) => w.name), isNot(contains('Nothing here')), reason: 'only the workspaces that hold a note');
    });

    test('says what it did', () {
      expect((report.notes, report.notebooks, report.canvases, report.pictures, report.files, report.recordings), (10, 1, 1, 2, 1, 1));
      expect((report.alreadyHere, report.copies, report.missing), (0, 0, 0));
      expect(report.skipped, isEmpty);
      expect(
        ghostexImportSaid(report),
        'Imported 10 notes, 1 notebook, 1 canvas, 2 pictures, 1 file and 1 recording. One note was an organization’s: it is yours now, in a workspace of the organization’s name. File it in the organization to share it again.',
      );
    });
  });

  group('a note whose id is already here', () {
    late GhostexDevice from;
    late String zip;
    final mine = Note(id: 'plan', body: '# Mine\n\nNot the export’s.\n', createdAt: 5, updatedAt: 6);

    setUp(() async {
      from = everything();
      zip = await exported(from, const GhostexOptions());
    });
    tearDown(() => from.dispose());

    test('is skipped, and the note here is left as it is', () async {
      final into = GhostexDevice(notes: [mine]);
      addTearDown(into.dispose);
      final report = await importGhostex(zip, into.target(), collision: GhostexCollision.skip);
      expect(into.library.noteOf('plan'), mine);
      expect(into.library.value.where((n) => n.body.contains('The plan.')), isEmpty);
      expect(report.alreadyHere, 1);
      expect(report.notes, 7);
      expect(into.picture(pictureA), isNull, reason: 'a skipped note’s pictures are not brought');
      expect(ghostexImportSaid(report), 'Imported 7 notes, 1 notebook, 1 canvas, 1 picture and 1 file; one note was here already and was left as it is.');
    });

    test('or kept as a copy under a new id, beside it', () async {
      final into = GhostexDevice(notes: [mine]);
      addTearDown(into.dispose);
      final report = await importGhostex(zip, into.target(), collision: GhostexCollision.copy);
      expect(into.library.noteOf('plan'), mine);
      final copy = into.library.noteOf('copy-1')!;
      expect(copy.body, from.library.noteOf('plan')!.body);
      expect((copy.createdAt, copy.starred), (from.library.noteOf('plan')!.createdAt, true));
      expect(into.workspaces.value.of['copy-1'], into.workspaces.value.list.firstWhere((w) => w.name == 'Work').id);
      expect(into.workspaces.value.of.containsKey('plan'), isFalse);
      expect(report.copies, 1);
      expect(report.notes, 8);
      expect(into.picture(pictureA), jpeg);
      expect(ghostexImportSaid(report), contains('; one note was here already, so it came in as a copy.'));
    });

    test('is counted before the person chooses', () async {
      final into = GhostexDevice(notes: [mine]);
      addTearDown(into.dispose);
      expect(await ghostexCounts(zip, into.library), (notes: 10, here: 1));
    });
  });

  group('what is not a .ghostex, or is not to be trusted', () {
    late GhostexDevice device;
    setUp(() => device = GhostexDevice());
    tearDown(() => device.dispose());

    String zipOf(Map<String, String> entries) {
      final path = device.path('made.zip');
      final zip = ZipFileEncoder()..create(path);
      for (final MapEntry(:key, :value) in entries.entries) {
        zip.addArchiveFile(ArchiveFile.string(key, value));
      }
      zip.closeSync();
      return path;
    }

    String manifest(List<Map<String, Object?>> notes, {int version = 1}) => jsonEncode({'format': 'ghostex', 'version': version, 'notes': notes, 'workspaces': []});

    test('a ZIP with no manifest, another format, or a newer version is refused in words', () async {
      await expectLater(importGhostex(zipOf({'a.md': 'x'}), device.target()), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('no manifest'))));
      await expectLater(importGhostex(zipOf({'manifest.json': '{"format":"other","version":1}'}), device.target()), throwsA(isA<StateError>().having((e) => e.message, 'message', 'That is not a .ghostex file.')));
      await expectLater(importGhostex(zipOf({'manifest.json': manifest([], version: 2)}), device.target()), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('newer Ghost.md'))));
      expect(device.library.value, isEmpty);
    });

    test('names it would not make are not used: a bad id is made anew, a bad picture name is left out', () async {
      final path = zipOf({
        'manifest.json': manifest([
          {'id': '../../evil', 'path': 'notes/A.md', 'title': 'A', 'created': '2026-01-01T00:00:00.000Z', 'pictures': ['../../etc/passwd.jpg'], 'files': ['x/../y.pdf']},
          {'id': 'gone', 'path': 'notes/Gone.md', 'title': 'Gone'},
        ]),
        'notes/A.md': '# A\n',
        'pictures/../../etc/passwd.jpg': 'no',
      });
      final report = await importGhostex(path, device.target());
      expect(device.library.value.single.id, 'copy-1');
      expect(device.library.value.single.body, '# A\n');
      expect(report.missing, 2);
      expect(report.skipped, ['Gone, whose words are not in the file']);
      expect(Directory(device.path('pictures')).existsSync(), isFalse);
    });

    test('what a file starts with says what it is', () async {
      File(device.path('plain.txt')).writeAsStringSync('hello there');
      File(device.path('sealed')).writeAsBytesSync([...ghostexMagic.codeUnits, 1, 2, 3]);
      expect(await ghostexKindOfFile(device.path('plain.txt')), GhostexKind.neither);
      expect(await ghostexKindOfFile(device.path('sealed')), GhostexKind.sealed);
      expect(await ghostexKindOfFile(zipOf({'manifest.json': manifest([])})), GhostexKind.zip);
    });
  });

  group('opened from elsewhere', () {
    test('a .ghostex opened from Files or shared to the app is one, and nothing else is', () {
      const file = SharedItem(picture: false, path: '/cache/shared/1/matt-2026-10-17.ghostex', name: 'matt-2026-10-17.ghostex');
      expect(ghostexShared(const SharedIn(id: 's', items: [file]))?.path, file.path);
      expect(ghostexShared(const SharedIn(id: 's', items: [SharedItem(picture: false, path: '/a.pdf', name: 'a.pdf')])), isNull);
      expect(ghostexShared(const SharedIn(id: 's', text: 'with words', items: [file])), isNull);
      expect(ghostexShared(const SharedIn(id: 's', items: [file, file])), isNull);
    });

    test('the Mac’s Finder hands one over as a link of the app’s', () {
      expect(ghostexLinked('ghostmd://ghostex?path=%2FUsers%2Fm%2FDownloads%2Fmatt%202026.ghostex')?.path, '/Users/m/Downloads/matt 2026.ghostex');
      expect(ghostexLinked('ghostmd://ghostex?path=%2Fetc%2Fpasswd'), isNull);
      expect(ghostexLinked('ghostmd://ghostex?path=relative.ghostex'), isNull);
      expect(ghostexLinked('ghostmd://note/abc'), isNull);
    });
  });

  group('protected with a password, over the real core', () {
    final built = File(_library).existsSync();
    final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';
    late GhostCore core;
    late CoreCrypto crypto;
    late GhostexDevice from;
    late GhostexSeal seal;

    setUpAll(() async {
      if (!built) return;
      core = await GhostCore.open(libraryPath: File(_library).absolute.path);
      crypto = CoreCrypto(core.invoke);
      seal = CoreGhostexSeal(crypto, rounds: 1000);
    });
    tearDownAll(() async {
      if (built) await core.close();
    });
    setUp(() => from = everything());
    tearDown(() => from.dispose());

    Future<String> sealed() async => (await writeGhostex(from.source(), const GhostexOptions(recordings: true, password: 'correct horse'), from.path('sealed.ghostex'), seal: seal, temp: from.root.path, at: at)).path;

    test('the whole ZIP is sealed behind a header of its own', () async {
      final path = await sealed();
      final bytes = File(path).readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 8)), 'GHOSTEX1');
      expect(bytes[8], 1, reason: 'the layout’s version');
      expect(bytes.sublist(9, 13), [0, 0, 0x03, 0xE8], reason: 'the rounds it was derived over, 1000');
      expect(bytes[ghostexHeaderBytes], 1, reason: 'the core’s own sealed blob follows');
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('manifest.json')), reason: 'nothing of the ZIP shows');
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('The plan.')));
      expect(from.root.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).where((n) => n.endsWith('.zip') || n.endsWith('.part') || n.endsWith('.sealing')), isEmpty, reason: 'no plain copy left behind');
    }, skip: skip);

    test('opens with its password into the ZIP it was, and reads back', () async {
      final path = await sealed();
      final zip = from.path('opened.zip');
      await seal.open(path, zip, 'correct horse');
      expect(await ghostexKindOfFile(zip), GhostexKind.zip);
      final into = GhostexDevice();
      addTearDown(into.dispose);
      final report = await importGhostex(zip, into.target());
      expect((report.notes, report.notebooks, report.canvases), (8, 1, 1));
      expect(into.library.noteOf('plan')!.body, from.library.noteOf('plan')!.body);
      expect(into.recording('spoken'), wav);
    }, skip: skip);

    test('and with no other: a wrong password is said, and nothing is written', () async {
      final path = await sealed();
      final zip = from.path('wrong.zip');
      await expectLater(seal.open(path, zip, 'wrong horse'), throwsA(isA<GhostexWrongPassword>()));
      expect(File(zip).existsSync(), isFalse);
    }, skip: skip);

    test('a file changed after it was sealed does not open', () async {
      final path = await sealed();
      final bytes = File(path).readAsBytesSync();
      bytes[bytes.length - 40] ^= 0x01;
      File(path).writeAsBytesSync(bytes);
      final zip = from.path('changed.zip');
      await expectLater(seal.open(path, zip, 'correct horse'), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('changed'))));
      expect(File(zip).existsSync(), isFalse);
    }, skip: skip);

    test('Settings’ calls ask for the password, then open and count it', () async {
      final path = await sealed();
      final into = GhostexDevice(notes: [const Note(id: 'plan', body: '# Mine\n', createdAt: 1, updatedAt: 1)]);
      addTearDown(into.dispose);
      final calls = Ghostex(source: into.source(), target: () async => into.target(), temp: () async => into.root.path, seal: seal);
      final chosen = GhostexChosen(path: path, name: 'sealed.ghostex');
      await expectLater(calls.open(chosen), throwsA(isA<GhostexNeedsPassword>()));
      await expectLater(calls.open(chosen, password: 'nope'), throwsA(isA<GhostexWrongPassword>()));
      final opened = await calls.open(chosen, password: 'correct horse');
      expect((opened.notes, opened.here, opened.temporary), (10, 1, true));
      final report = await calls.read(opened, collision: GhostexCollision.copy);
      expect(report.copies, 1);
      expect(File(opened.zip).existsSync(), isFalse, reason: 'the opened ZIP goes once it is read');
    }, skip: skip);
  });

  test('Settings’ calls write the file under its name, the last one cleared away', () async {
    final from = everything();
    addTearDown(from.dispose);
    final calls = Ghostex(source: from.source(), target: () async => from.target(), temp: () async => from.root.path, handle: () => 'matt');
    final first = await calls.export(const GhostexOptions(), at: DateTime(2026, 10, 16));
    final made = await calls.export(const GhostexOptions(), at: at);
    expect(made.name, 'matt-2026-10-17.ghostex');
    expect(made.written.path, '${from.root.path}/ghostex/matt-2026-10-17.ghostex');
    expect(File(first.written.path).existsSync(), isFalse);
    expect(Directory('${from.root.path}/ghostex').listSync().map((f) => f.uri.pathSegments.last), ['matt-2026-10-17.ghostex']);
    await expectLater(calls.export(const GhostexOptions(password: 'x'), at: at), throwsStateError, reason: 'no seal, no password');
  });
}
