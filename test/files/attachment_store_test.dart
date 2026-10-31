// The files notes link, kept on this device beside the pictures (lib/files/attachment_store.dart): under fresh
// names in <data>/images/files, whole or not at all, from bytes, a path or a copy, and gone only when a note deleted
// for good linked them and no other note does.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/attachment_refs.dart';
import 'package:ghost_md/files/attachment_places.dart';
import 'package:ghost_md/files/attachment_store.dart';

void main() {
  late Directory data;
  late AttachmentStore store;
  var made = 0;

  setUp(() {
    data = Directory.systemTemp.createTempSync('files-store');
    made = 0;
    store = AttachmentStore(dataDir: data.path, newName: () => 'f${made += 1}');
  });
  tearDown(() => data.deleteSync(recursive: true));

  test('keeps bytes under a fresh name in the pictures’ folder, and answers the note’s line', () async {
    final kept = await store.keep(AttachmentBytes(Uint8List.fromList(List<int>.filled(2500, 7))), original: 'Lease 2026.PDF');
    expect(kept.name, 'f1.pdf');
    expect(kept.bytes, 2500);
    expect(kept.ref, 'file/f1.pdf');
    expect(kept.markdown, '[Lease 2026.PDF](file/f1.pdf "3 KB")');
    expect(File('${data.path}/images/files/f1.pdf').lengthSync(), 2500);
    expect(await store.sizeOf('f1.pdf'), 2500);
    expect((await store.read('f1.pdf'))!.first, 7);
    expect(Directory('${data.path}/images/files').listSync().map((e) => e.uri.pathSegments.last), ['f1.pdf'], reason: 'nothing of the write is left beside it');
  });

  test('moves a picker’s copy in, copies a file it does not own, and takes one only something else can read', () async {
    final picked = File('${data.path}/picked.part')..writeAsStringSync('hello');
    final moved = await store.keep(AttachmentPath(picked.path, move: true), original: 'hello.txt');
    expect(picked.existsSync(), isFalse);
    expect(await store.read(moved.name), Uint8List.fromList('hello'.codeUnits));

    final theirs = File('${data.path}/theirs.csv')..writeAsStringSync('a,b');
    final copied = await store.keep(AttachmentPath(theirs.path), original: 'theirs.csv');
    expect(theirs.existsSync(), isTrue);
    expect(copied.name, 'f2.csv');

    final granted = await store.keep(AttachmentCopy((path) => File(path).writeAsString('from a picker')), original: 'Notes');
    expect(granted.name, 'f3.bin');
    expect(granted.bytes, 'from a picker'.length);
  });

  test('says why when a file cannot be kept, and leaves nothing half written', () async {
    await expectLater(store.keep(AttachmentPath('${data.path}/nowhere.pdf'), original: 'nowhere.pdf'), throwsA(isA<StateError>().having((e) => e.message, 'message', 'That file could not be added.')));
    await expectLater(store.keep(AttachmentCopy((path) async => throw const FileSystemException('full')), original: 'x.pdf'), throwsA(isA<StateError>()));
    expect(await store.all(), isEmpty);
    final dir = Directory('${data.path}/images/files');
    expect(dir.existsSync() ? dir.listSync() : const <FileSystemEntity>[], isEmpty);
  });

  test('keeps a file that arrived by sync under its own name, and never a name that is not one', () async {
    var told = 0;
    store.addListener(() => told += 1);
    await store.write('5f0c2e9a.pdf', Uint8List.fromList([1, 2, 3]));
    expect(await store.sizeOf('5f0c2e9a.pdf'), 3);
    expect(store.landedTimes('5f0c2e9a.pdf'), 1);
    expect(told, 1);
    await expectLater(store.write('../escape.pdf', Uint8List(1)), throwsA(isA<StateError>()));
    expect(await store.read('../escape.pdf'), isNull);
    expect(store.pathOf('a/b.pdf'), isNull);
  });

  test('a deleted note’s files go only where no other note links them, with the words read in them', () async {
    final lease = await store.keep(AttachmentBytes(Uint8List(10)), original: 'Lease.pdf');
    final map = await store.keep(AttachmentBytes(Uint8List(20)), original: 'map.png');
    File('${store.dir.path}/${lease.name}$readTextSuffix').writeAsStringSync('rent');
    final deleted = '# Flat\n\n${lease.markdown}\n\n${map.markdown}\n';
    final gone = await store.forgetUnlinked(deleted, () async => ['# Trip\n\n${map.markdown}\n']);
    expect(gone, [lease.name]);
    expect(await store.fileOf(lease.name), isNull);
    expect(File('${store.dir.path}/${lease.name}$readTextSuffix').existsSync(), isFalse);
    expect(await store.fileOf(map.name), isNotNull, reason: 'another note still links it');
    expect(await store.forgetUnlinked('no files', () async => throw StateError('never asked')), isEmpty);
    expect(await store.bytesUsed(), 20);
  });

  test('follows the core’s folders: writes under the library, reads both places, and takes an old copy out', () async {
    final under = '${data.path}/Library/file';
    final beside = '${data.path}/images/files';
    // An older build's file, beside the library, and the words read in it.
    Directory(beside).createSync(recursive: true);
    File('$beside/old.pdf').writeAsBytesSync([1, 2, 3]);
    File('$beside/old.pdf$readTextSuffix').writeAsStringSync('lease');
    expect(await store.fileOf('old.pdf'), isNotNull, reason: 'the old folder alone until the core has answered');
    var told = 0;
    store.addListener(() => told += 1);
    store.follow(AttachmentPlaces(image: const [], file: [under, beside], video: const [], recording: const []));
    expect(told, 1);
    store.follow(AttachmentPlaces(image: const [], file: [under, beside], video: const [], recording: const []));
    expect(told, 1, reason: 'the same answer again says nothing');
    store.follow(const AttachmentPlaces(image: [], file: [], video: [], recording: []));
    expect(store.dirs, [under, beside], reason: 'an answer with no folder for the files is no answer');
    expect(store.dir.path, under);
    // Read from beside the library still; written under it.
    expect((await store.fileOf('old.pdf'))!.path, '$beside/old.pdf');
    expect(await store.sizeOf('old.pdf'), 3);
    final kept = await store.keep(AttachmentBytes(Uint8List(5)), original: 'new.pdf');
    expect((await store.fileOf(kept.name))!.path, '$under/${kept.name}');
    expect(store.pathOf('x.pdf'), '$under/x.pdf');
    expect(await store.all(), {'old.pdf': 3, kept.name: 5});
    // One in both folders is read from under the library; a copy that arrives by sync lands there and the old goes.
    File('$under/old.pdf').writeAsBytesSync([9, 9, 9, 9]);
    expect(await store.sizeOf('old.pdf'), 4);
    await store.write('5f0c2e9a.pdf', Uint8List.fromList([7]));
    expect(File('$under/5f0c2e9a.pdf').existsSync(), isTrue);
    File('$beside/5f0c2e9a.pdf').writeAsBytesSync([8, 8]);
    await store.write('5f0c2e9a.pdf', Uint8List.fromList([7, 7]));
    expect(File('$beside/5f0c2e9a.pdf').existsSync(), isFalse, reason: 'the copy an older build left goes');
    // A removal reaches both folders, and the words read beside each.
    await store.remove('old.pdf');
    expect(File('$under/old.pdf').existsSync(), isFalse);
    expect(File('$beside/old.pdf').existsSync(), isFalse);
    expect(File('$beside/old.pdf$readTextSuffix').existsSync(), isFalse);
    // A store made over the core's answer from the start writes under the library at once.
    final told2 = AttachmentStore(dataDir: data.path, newName: () => 'g1', places: AttachmentPlaces(image: const [], file: [under, beside], video: const [], recording: const []));
    expect(told2.dir.path, under);
  });

  test('the door everything brings a file in by is the app’s own store, and says so before there is one', () async {
    keptAttachments = null;
    await expectLater(storeAttachment(AttachmentBytes(Uint8List(1)), name: 'a.txt'), throwsA(isA<StateError>()));
    keptAttachments = store;
    addTearDown(() => keptAttachments = null);
    final kept = await storeAttachment(AttachmentBytes(Uint8List(4)), name: 'shared.pdf');
    expect(attachmentOfLine(kept.markdown)?.name, kept.name);
  });
}
