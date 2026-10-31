// Two devices on one account whose files lie in different folders: one still laid out as every build before
// 2026-10-31 kept them (`recordings/`, `images/` beside the library, never gathered), the other with everything under
// its library (`Library/recordings/`, `Library/image/`) and the old folders still read (docs/MARKDOWN_FIRST.md §9.1,
// tauri/src-tauri/src/library/attachments.rs). Sync names a file by kind and name alone (lib/sync/notes.dart
// `fileId`), so each device reads from wherever it has the file and keeps what arrives where its own build writes:
// nothing in the pass keys on a folder. The devices' files are folders on disk here ([FolderFiles]), standing for
// the core's `Places` behind `CoreDeviceBytes` (lib/sync/device.dart).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/sync/notes.dart';

import 'support.dart';

/// A device's recordings and pictures as files in folders, each kind read from a list of folders in order and
/// written to the first (the core's `Places`); versions files and the rest in memory.
class FolderFiles implements LocalFiles {
  FolderFiles({required this.recordings, required this.pictures});

  final List<String> recordings;
  final List<String> pictures;
  final Map<String, Uint8List> other = {};
  final Set<String> owing = {};

  List<String>? _dirsOf(FileKind kind) => switch (kind) { FileKind.recording => recordings, FileKind.image => pictures, _ => null };

  String _nameOf(FileKind kind, String name) => kind == FileKind.recording ? '$name.wav' : name;

  File? _find(FileKind kind, String name) {
    for (final dir in _dirsOf(kind)!) {
      final file = File('$dir/${_nameOf(kind, name)}');
      if (file.existsSync()) return file;
    }
    return null;
  }

  @override
  Future<Uint8List?> read(FileKind kind, String name) async => _dirsOf(kind) == null ? other['${kind.name}:$name'] : _find(kind, name)?.readAsBytesSync();

  @override
  Future<void> write(FileKind kind, String name, Uint8List bytes) async {
    final dirs = _dirsOf(kind);
    if (dirs == null) {
      other['${kind.name}:$name'] = bytes;
      return;
    }
    File('${dirs.first}/${_nameOf(kind, name)}')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  @override
  Future<int?> lengthOf(FileKind kind, String name) async => (await read(kind, name))?.length;

  @override
  bool get keepsMedia => true;

  @override
  List<String> owed() => owing.toList();

  @override
  void settled(String name) => owing.remove(name);

  @override
  FileDigest? get digest => null;
}

void main() {
  setUp(forgetPictureAsks);

  test('a recording and a picture cross between a device on the old layout and one that has settled', () async {
    final root = Directory.systemTemp.createTempSync('attachment-layouts');
    addTearDown(() => root.deleteSync(recursive: true));
    final api = await FakeService.start(seed: testAccount);
    final older = deviceOf(api);
    final settled = deviceOf(api);
    final olderFiles = FolderFiles(recordings: ['${root.path}/older/recordings'], pictures: ['${root.path}/older/images']);
    final settledFiles = FolderFiles(
      recordings: ['${root.path}/settled/Library/recordings', '${root.path}/settled/recordings'],
      pictures: ['${root.path}/settled/Library/image', '${root.path}/settled/images'],
    );
    Future<Outcome> run(Device device, FolderFiles files) => syncNotes(SyncContext(token: device.token, key: device.key, notes: device.local, files: files, state: device.state, save: device.save, api: device.api, crypto: device.crypto, now: device.now));

    // The older layout's device has a meeting with its tape beside the library, and a picture beside it too.
    final tape = Uint8List.fromList([82, 73, 70, 70, 1, 2, 3, 4]);
    final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 5, 6]);
    const picture = 'a1b2c3d4-0000-4000-8000-000000000001.jpg';
    older.notes['m1'] = note('m1', '# Standup\n\nspoken', createdAt: 1, updatedAt: 1, recordingMs: 1200);
    older.notes['p1'] = note('p1', '# Whiteboard\n\n![](image/$picture)\n', createdAt: 1, updatedAt: 1);
    await olderFiles.write(FileKind.recording, 'm1', tape);
    await olderFiles.write(FileKind.image, picture, jpeg);
    expect(File('${root.path}/older/recordings/m1.wav').existsSync(), isTrue);
    await run(older, olderFiles);
    expect(api.files.containsKey(fileId(FileKind.recording, 'm1')!), isTrue, reason: 'sent from beside the library, by kind and name');
    expect(api.files.containsKey(fileId(FileKind.image, picture)!), isTrue);

    // The settled device takes both, and keeps them under its library: the layout is the build's, not the sender's.
    await run(settled, settledFiles);
    expect(settled.notes.keys, containsAll(['m1', 'p1']));
    expect(File('${root.path}/settled/Library/recordings/m1.wav').readAsBytesSync(), tape);
    expect(File('${root.path}/settled/Library/image/$picture').readAsBytesSync(), jpeg);
    expect(Directory('${root.path}/settled/recordings').existsSync(), isFalse, reason: 'nothing of the old layout is made');

    // The settled device has a tape an older build left beside its library, never gathered: read from there, sent,
    // and kept by the other device where it writes. And a picture of its own under the library goes the same road.
    final left = Uint8List.fromList([82, 73, 70, 70, 9, 9]);
    const theirs = 'a1b2c3d4-0000-4000-8000-000000000002.jpg';
    File('${root.path}/settled/recordings/m2.wav')
      ..createSync(recursive: true)
      ..writeAsBytesSync(left);
    await settledFiles.write(FileKind.image, theirs, jpeg);
    settled.notes['m2'] = note('m2', '# Retro\n\nspoken', createdAt: 2, updatedAt: 2, recordingMs: 900);
    settled.notes['p2'] = note('p2', '# Sketch\n\n![](image/$theirs)\n', createdAt: 2, updatedAt: 2);
    await run(settled, settledFiles);
    expect(api.files.containsKey(fileId(FileKind.recording, 'm2')!), isTrue, reason: 'read from the old folder while the library’s has nothing by that name');
    await run(older, olderFiles);
    expect(File('${root.path}/older/recordings/m2.wav').readAsBytesSync(), left, reason: 'kept where that build writes');
    expect(File('${root.path}/older/images/$theirs').readAsBytesSync(), jpeg);
    expect(Directory('${root.path}/older/Library').existsSync(), isFalse);
    // Neither device's state names a folder: the files are marked by kind and name alone.
    for (final device in [older, settled]) {
      for (final id in device.state.files.keys) {
        expect(id, isNot(contains('/')), reason: 'a file mark is `<kind>:<name>`, never a path');
      }
    }
  });
}
