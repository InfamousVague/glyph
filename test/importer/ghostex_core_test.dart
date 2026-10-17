// A .ghostex written and read back through the real Rust core, on the Mac: Settings' own calls (lib/export/
// ghostex_calls.dart `Ghostex.overCore`) over lib/core/core_library.dart and native/target/debug/libghost_core.dylib
// (tool/build-native.sh host). The notes are written by `store_apply`, the pictures and the recording found by
// `file_path` and kept again by `sync_put_file_path`, the files by the attachments' store: every note deleted for
// good between the two, its pictures with it, and everything made again as it was.
//
// One process has one core (dispatch.rs `CORE`), so this file has the library to itself.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/core_library.dart';
import 'package:ghost_md/core/native/files.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/export/ghostex.dart';
import 'package:ghost_md/export/ghostex_calls.dart';
import 'package:ghost_md/files/attachment_store.dart';
import 'package:ghost_md/importer/ghostex.dart';

const _library = 'native/target/debug/libghost_core.dylib';

void main() {
  final built = File(_library).existsSync();
  final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';

  late Directory root;
  late GhostCore core;
  late CoreLibrary library;

  setUpAll(() async {
    if (!built) return;
    root = Directory(Directory.systemTemp.createTempSync('ghost-core-ghostex-').resolveSymbolicLinksSync());
    core = await GhostCore.open(libraryPath: File(_library).absolute.path);
    await core.init(dataDir: '${root.path}/data', cacheDir: '${root.path}/cache');
    library = CoreLibrary(core.invoke, resume: false, log: (_) {});
    await library.load();
    keptAttachments = AttachmentStore(dataDir: '${root.path}/data');
  });

  tearDownAll(() async {
    if (!built) return;
    keptAttachments = null;
    library.dispose();
    await core.close();
    root.deleteSync(recursive: true);
  });

  test('everything deleted for good comes back as it was', () async {
    final files = CoreFiles(core.invoke);
    // A real picture's first bytes, and a real WAV's header with a moment of silence.
    final picture = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, ...'IHDR'.codeUnits, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 0x1F, 0x15, 0xC4, 0x89]);
    final header = ByteData(44)
      ..setUint32(0, 0x52494646)
      ..setUint32(4, 36 + 3200, Endian.little)
      ..setUint32(8, 0x57415645)
      ..setUint32(12, 0x666d7420)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, 16000, Endian.little)
      ..setUint32(28, 32000, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461)
      ..setUint32(40, 3200, Endian.little);
    final wav = Uint8List.fromList([...header.buffer.asUint8List(), ...List.filled(3200, 0)]);
    final pdf = Uint8List.fromList('%PDF-1.7 a lease'.codeUnits);
    const pictureName = '5e1f0b6a-2c3d-4e5f-8a9b-0c1d2e3f4a5b.png';
    const fileName = '6f2a1c7b-3d4e-4f60-9bac-1d2e3f4a5b6c.pdf';
    await files.write(CoreFileKind.image, pictureName, picture);
    await keptAttachments!.write(fileName, pdf);

    final ids = [for (var i = 0; i < 4; i += 1) await core.newId()];
    final made = [
      Note(id: ids[0], body: '---\ntags: [a]\n---\n# Plan\n\n![](image/$pictureName)\n\n[Lease.pdf](file/$fileName "16 bytes")\n', createdAt: 1767225600123, updatedAt: 1767225700456, starred: true),
      Note(id: ids[1], body: '# Put away\n\nArchived.\n', createdAt: 1767225600000, updatedAt: 1767225600500, archivedAt: 1767225800000),
      Note(id: ids[2], body: '# Spoken\n\nHello there.\n', createdAt: 1767225600000, updatedAt: 1767225601000, source: NoteSource.capture, recordingMs: 100, segments: const [Segment(startMs: 0, endMs: 100, text: 'Hello there.')]),
      Note(id: ids[3], body: '# Plan\n\nA second of one title.\n', createdAt: 1767225600001, updatedAt: 1767225600002),
    ];
    for (final note in made) {
      await library.apply(note);
    }
    await files.write(CoreFileKind.recording, ids[2], wav);
    final workspaces = WorkspaceStore();
    final work = workspaces.addWorkspace('Work', 'moss')!;
    workspaces.fileNotes([ids[0], ids[3]], work.id);
    final before = {for (final id in ids) id: (await library.get(id))!};

    final calls = Ghostex.overCore(library: library, workspaces: workspaces, invoke: core.invoke, handle: () => 'matt', platform: TargetPlatform.macOS);
    final out = await calls.export(const GhostexOptions(archived: true, recordings: true), at: DateTime(2026, 10, 17));
    expect((out.written.notes, out.written.pictures, out.written.files, out.written.recordings, out.written.missing), (4, 1, 1, 1, 0));

    for (final id in ids) {
      await library.destroy(id);
      workspaces.forgetNote(id);
    }
    expect(library.value.where((n) => ids.contains(n.id)), isEmpty);
    expect(await files.exists(CoreFileKind.image, pictureName), isFalse, reason: 'the picture went with the last note that showed it');
    expect(await files.exists(CoreFileKind.recording, ids[2]), isFalse);

    final opened = await calls.open(GhostexChosen(path: out.written.path, name: out.name));
    expect((opened.notes, opened.here), (4, 0));
    final report = await calls.read(opened, collision: GhostexCollision.skip);
    expect((report.notes, report.pictures, report.files, report.recordings), (4, 1, 0, 1), reason: 'the file was still here, by its name');
    expect(report.skipped, isEmpty);
    for (final id in ids) {
      final now = (await library.get(id))!, was = before[id]!;
      expect(now.body, was.body, reason: id);
      expect((now.createdAt, now.updatedAt, now.starred, now.archivedAt, now.sourceWord, now.recordingMs), (was.createdAt, was.updatedAt, was.starred, was.archivedAt, was.sourceWord, was.recordingMs), reason: id);
      expect(now.segments, was.segments, reason: id);
    }
    expect(await files.read(CoreFileKind.image, pictureName), picture);
    expect(await files.read(CoreFileKind.recording, ids[2]), wav);
    expect(await keptAttachments!.read(fileName), pdf);
    final again = workspaces.value;
    expect({again.of[ids[0]], again.of[ids[3]]}, {work.id}, reason: 'Work was found by its name, not made twice');
    expect(again.list.where((w) => w.name == 'Work'), hasLength(1));
  }, skip: skip);
}
