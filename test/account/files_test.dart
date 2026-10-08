// lib/core/native/files.dart over the Rust core's real C functions, on the Mac (tool/build-native.sh host): the
// files sync carries, by both roads. A small file's bytes cross; a recording is sealed where it lies and adopted
// from where it was opened, with lib/account/crypto.dart, as the sync engine will do it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/files.dart';
import 'package:ghost_md/core/native/ghost_core.dart';

const _library = 'native/target/debug/libghost_core.dylib';

void main() {
  final built = File(_library).existsSync();
  final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';

  late Directory root;
  late String data, cache;
  late GhostCore core;
  late CoreFiles files;
  late CoreCrypto crypto;

  setUpAll(() async {
    if (!built) return;
    root = Directory(Directory.systemTemp.createTempSync('ghost-files-test-').resolveSymbolicLinksSync());
    data = '${root.path}/data';
    cache = '${root.path}/cache';
    core = await GhostCore.open(libraryPath: File(_library).absolute.path);
    await core.init(dataDir: data, cacheDir: cache);
    files = CoreFiles(core.invoke);
    crypto = CoreCrypto(core.invoke);
  });

  tearDownAll(() async {
    if (!built) return;
    await core.close();
    root.deleteSync(recursive: true);
  });

  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2]);

  test('a picture is kept under its name only if it is what the name says', () async {
    expect(await files.read(CoreFileKind.image, 'abc.jpg'), isNull);
    expect(await files.exists(CoreFileKind.image, 'abc.jpg'), isFalse);
    expect(await files.write(CoreFileKind.image, 'abc.jpg', jpeg), isTrue);
    expect(File('$data/images/abc.jpg').readAsBytesSync(), jpeg);
    expect(await files.read(CoreFileKind.image, 'abc.jpg'), jpeg);
    expect(await files.exists(CoreFileKind.image, 'abc.jpg'), isTrue);
    expect(await files.digest(CoreFileKind.image, 'abc.jpg'), await crypto.sha16(jpeg));
    expect(await files.where(CoreFileKind.image, 'abc.jpg'), (path: '$data/images/abc.jpg', bytes: 6));
    // The Tauri command's own refusals.
    Future<String> refused(String name, List<int> bytes) async {
      try {
        await files.write(CoreFileKind.image, name, Uint8List.fromList(bytes));
      } on CoreError catch (e) {
        return e.message;
      }
      fail('$name was kept');
    }

    expect(await refused('abc.png', jpeg), 'That picture is not what its name says.');
    expect(await refused('../abc.jpg', jpeg), 'That is not a picture name.');
    expect(await refused('t.jpg', utf8.encode('hello')), 'That is not a picture Glyph can add.');
    expect(await files.read(CoreFileKind.image, '../abc.jpg'), isNull);
  }, skip: skip);

  test('a versions file is read and written beside its note', () async {
    final id = await core.newId();
    await core.invoke('create_note', {'id': id, 'body': '# Plan\n', 'source': 'editor'});
    expect(await files.read(CoreFileKind.versions, id), isNull);
    final text = utf8.encode('{"v":1,"versions":["día ✓"]}');
    expect(await files.write(CoreFileKind.versions, id, Uint8List.fromList(text)), isTrue);
    expect(await files.read(CoreFileKind.versions, id), text);
    expect(File('$data/Library/Inbox/Plan.versions').readAsBytesSync(), text);
    expect(await files.digest(CoreFileKind.versions, id), await crypto.sha16(Uint8List.fromList(text)));
    expect(await files.write(CoreFileKind.versions, 'nobody', Uint8List.fromList(text)), isFalse);
    await expectLater(files.where(CoreFileKind.versions, id), throwsA(isA<CoreError>()));
  }, skip: skip);

  test('a recording goes to the account and comes back without its bytes ever crossing', () async {
    final key = await crypto.newAccountKey();
    final wav = Uint8List.fromList([...utf8.encode('RIFF'), for (var i = 0; i < 3 * 1024 * 1024; i += 1) (i * 13) & 0xff]);
    Directory('$data/recordings').createSync(recursive: true);
    File('$data/recordings/n1.wav').writeAsBytesSync(wav);

    // Up: where it lies, its fingerprint, sealed from there into the body of a PUT.
    final at = (await files.where(CoreFileKind.recording, 'n1'))!;
    expect(at.bytes, wav.length);
    final digest = await files.digest(CoreFileKind.recording, 'n1');
    expect(digest, await crypto.sha16(wav));
    final sealed = await crypto.sealFile(key, 'file:r-n1', path: at.path, out: '$cache/sync/r-n1.sealed');
    expect(sealed, wav.length + 29);

    // Down, on another device (here: under another note's id): a GET's body opened beside, then adopted.
    await crypto.openFile(key, 'file:r-n1', path: '$cache/sync/r-n1.sealed', out: '$cache/sync/r-n2.opened');
    await files.adopt(CoreFileKind.recording, 'n2', '$cache/sync/r-n2.opened');
    expect(File('$cache/sync/r-n2.opened').existsSync(), isFalse, reason: 'moved in');
    expect(await files.digest(CoreFileKind.recording, 'n2'), digest);
    expect(File('$data/recordings/n2.wav').readAsBytesSync(), wav);

    // What is not a recording is not adopted, and is left for whoever opened it.
    File('$cache/sync/bad').writeAsBytesSync(utf8.encode('ID3'));
    await expectLater(
      files.adopt(CoreFileKind.recording, 'n3', '$cache/sync/bad'),
      throwsA(isA<CoreError>().having((e) => e.message, 'message', 'That is not a recording Glyph can keep.')),
    );
    expect(File('$cache/sync/bad').existsSync(), isTrue);
    expect(await files.exists(CoreFileKind.recording, 'n3'), isFalse);
    // The small road still works for one: the page's own `sync_put_file`.
    expect(await files.write(CoreFileKind.recording, 'n4', Uint8List.fromList(utf8.encode('RIFF short'))), isTrue);
    expect(await files.read(CoreFileKind.recording, 'n4'), utf8.encode('RIFF short'));
  }, skip: skip);
}
