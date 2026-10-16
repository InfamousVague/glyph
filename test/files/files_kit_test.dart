// Files, scans and the words read in them on one device (lib/files/files_kit.dart, read_pass.dart): a file chosen
// is kept and read soon, a scan kept as one PDF with its words read off the scanner's own pictures, what the notes
// already show read slowly and never while Battery saver is on, the notes that show a thing read owed to sync, and
// a deleted note's files gone where no other note links them.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/attachment_refs.dart';
import 'package:ghost_md/core/shared_files.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/files/attachment_store.dart';
import 'package:ghost_md/files/files_kit.dart';
import 'package:ghost_md/files/phone_documents.dart';
import 'package:ghost_md/files/plus_files.dart';
import 'package:ghost_md/files/read_pass.dart';
import 'package:ghost_md/files/read_text.dart';
import 'package:ghost_md/mail/mail_note.dart';
import 'package:ghost_md/sync/notes.dart' show FileKind;

import 'support.dart';

const String picture = 'a1b2c3d4-0000-4000-8000-000000000001.jpg';

void main() {
  late Directory data;
  late FakeDocuments device;
  late MemoryStored kept;
  late List<({String id, String body})> notes;

  FilesKit kit() => FilesKit(
        dataDir: data.path,
        store: AttachmentStore(dataDir: data.path),
        texts: ReadTexts(dataDir: data.path),
        device: device,
        bodies: () async => notes,
        kept: kept,
        listenForInput: false,
      );

  Future<void> idle(FilesKit kit) async {
    for (var i = 0; i < 50 && kit.pass.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    data = Directory.systemTemp.createTempSync('files-kit');
    device = FakeDocuments();
    kept = MemoryStored();
    notes = <({String id, String body})>[];
  });
  tearDown(() => data.deleteSync(recursive: true));

  test('a file chosen is kept under its own name and read soon after, where it is a PDF', () async {
    final it = kit();
    final cache = File('${data.path}/picked/abc.part')
      ..createSync(recursive: true)
      ..writeAsStringSync(tinyPdf());
    device.picked = PickedFile(path: cache.path, name: 'Lease 2026.pdf', bytes: cache.lengthSync());
    final file = await it.pick();
    expect(file, isNotNull);
    expect(file!.markdown, startsWith('[Lease 2026.pdf](file/${file.name} "'));
    expect(cache.existsSync(), isFalse, reason: 'the picker’s copy is moved in');
    device.words[file.name] = <String>['Lease agreement', 'Rent monthly'];
    await it.pass.readExisting();
    notes.add((id: 'flat', body: '# Flat\n\n${file.markdown}\n'));
    it.pass.readSoon(ReadThing.file(file.name));
    await idle(it);
    expect(it.texts.wordsOf(ReadThing.file(file.name)), 'Lease agreement\fRent monthly');
    expect(it.owed(), ['flat'], reason: 'the note that shows it owes the account its words');
    it.settled('flat');
    expect(it.owed(), isEmpty);
  });

  test('a scan is one PDF named for the moment, its words read off the scanner’s pictures, which then go', () async {
    final it = kit();
    final dir = Directory('${data.path}/picked')..createSync(recursive: true);
    final pdf = File('${dir.path}/s.pdf')..writeAsStringSync(tinyPdf(pages: 2));
    final one = File('${dir.path}/s-1.jpg')..writeAsBytesSync([1]);
    final two = File('${dir.path}/s-2.jpg')..writeAsBytesSync([2]);
    device.scanned = ScannedDocument(pdf: pdf.path, pages: [one.path, two.path]);
    device.words
      ..[one.path] = ['INVOICE 0042']
      ..[two.path] = ['Total due 42.10'];
    final scan = await it.scan(name: 'Scan 2026-10-16 14.05.pdf');
    expect(scan!.markdown, startsWith('[Scan 2026-10-16 14.05.pdf](file/'));
    for (var i = 0; i < 50 && one.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(it.texts.wordsOf(ReadThing.file(scan.name)), 'INVOICE 0042\fTotal due 42.10');
    expect(one.existsSync() || two.existsSync(), isFalse);
  });

  test('what the notes already show is read slowly, and waits while Battery saver is on', () async {
    final it = kit();
    File('${data.path}/images/$picture')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0xff, 0xd8]);
    notes.add((id: 'dinner', body: '# Dinner\n\n![](image/$picture)\n\n![](image/gone-0000.jpg)\n'));
    device.words[picture] = ['TOTAL 42.10'];
    device.batterySaver = true;
    await it.pass.readExisting();
    expect(it.pass.progress, const ReadProgress(done: 0, total: 1), reason: 'a picture not on this device is not counted');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(it.pass.progress?.waiting, 'Waiting while Battery saver is on.');
    expect(device.readPaths, isEmpty);
    it.pass.on = false;
    expect(it.pass.on, isFalse);
    expect(kept.readText(readKey), 'off');
    it.pass.on = true;
    device.batterySaver = false;
  });

  test('read now, with nothing in the way, it counts each one and owes the notes that show it', () async {
    final it = kit();
    File('${data.path}/images/$picture')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0xff, 0xd8]);
    notes.add((id: 'dinner', body: '# Dinner\n\n![](image/$picture)\n'));
    notes.add((id: 'again', body: '![same](image/$picture)'));
    device.words[picture] = ['TOTAL 42.10'];
    await it.pass.readExisting();
    await idle(it);
    expect(it.pass.progress, const ReadProgress(done: 1, total: 1));
    expect(it.texts.wordsOf(const ReadThing.picture(picture)), 'TOTAL 42.10');
    expect(it.owed()..sort(), ['again', 'dinner']);
    // Asked again, nothing is read twice.
    await it.pass.readExisting();
    expect(it.pass.progress, const ReadProgress(done: 0, total: 0));
  });

  test('a device that reads nothing has the switch off and reads nothing', () async {
    device = FakeDocuments(reads: false);
    final it = kit();
    expect(it.pass.possible, isFalse);
    expect(it.pass.on, isFalse);
    it.pass.readSoon(const ReadThing.picture(picture));
    expect(it.pass.busy, isFalse);
  });

  test('carries a note’s files and words for sync, and their lengths without reading them', () async {
    final it = kit();
    await it.write(FileKind.attachment, 'f1.pdf', Uint8List.fromList([1, 2, 3, 4]));
    expect(await it.lengthOf(FileKind.attachment, 'f1.pdf'), 4);
    expect(await it.read(FileKind.attachment, 'f1.pdf'), Uint8List.fromList([1, 2, 3, 4]));
    await it.write(FileKind.text, 'file/f1.pdf', Uint8List.fromList([0x52, 0xc3, 0xa9]));
    expect(it.texts.wordsOf(const ReadThing.file('f1.pdf')), 'Ré');
    expect(await it.lengthOf(FileKind.text, 'file/f1.pdf'), 3);
    expect(await it.read(FileKind.text, 'image/none.jpg'), isNull);
    await expectLater(it.write(FileKind.text, 'video/a.mp4', Uint8List(1)), throwsA(isA<StateError>()));
  });

  test('a note deleted for good takes the files only it linked, with their words', () async {
    final it = kit();
    final mine = await it.store.keep(AttachmentBytes(Uint8List(3)), original: 'mine.pdf');
    final shared = await it.store.keep(AttachmentBytes(Uint8List(3)), original: 'shared.pdf');
    await it.texts.keep(ReadThing.file(mine.name), 'words');
    notes.add((id: 'other', body: shared.markdown));
    await it.noteDeleted('${mine.markdown}\n${shared.markdown}', id: 'gone');
    expect(await it.store.fileOf(mine.name), isNull);
    expect(it.texts.has(ReadThing.file(mine.name)), isFalse);
    expect(await it.store.fileOf(shared.name), isNotNull);
    expect((await it.used()).files, 1);
    expect(attachmentNames(shared.markdown), [shared.name]);
  });

  test('the quick action scans into a new note’s words, named for the minute, and is nothing where nothing scans', () async {
    final it = kit();
    expect(await scanToNewNote(kit: it), isNull, reason: 'the device has not said it scans');
    final pdf = File('${data.path}/picked/q.pdf')
      ..createSync(recursive: true)
      ..writeAsStringSync(tinyPdf(pages: 1));
    device.scanned = ScannedDocument(pdf: pdf.path, pages: const []);
    it.scans = true;
    final body = await scanToNewNote(kit: it, at: DateTime(2026, 10, 16, 14, 5));
    expect(body, startsWith('# Scan 2026-10-16 14.05\n\n[Scan 2026-10-16 14.05.pdf](file/'));
    expect(scanName(DateTime(2026, 1, 2, 3, 4)), 'Scan 2026-01-02 03.04.pdf');
  });

  test('a share, an import and a mail keep their files in the attachments’ store once the kit is the app’s', () async {
    final it = kit()..install();
    addTearDown(FilesKit.uninstall);
    final ref = await storeSharedFile(SharedBytes(Uint8List.fromList([1, 2, 3])), name: 'Shared.pdf', dataDir: data.path);
    expect(ref, startsWith('file/'));
    expect(await it.store.sizeOf(ref.substring(5)), 3, reason: 'kept in images/files, where the cards and sync look');
    final line = await keepMailFile(MailFile(name: 'Invoice.pdf', type: 'application/pdf', bytes: Uint8List.fromList([4, 5])), 0);
    expect(line, startsWith('[Invoice.pdf](file/'));
    expect(attachmentOfLine(line), isNotNull);
    FilesKit.uninstall();
    expect(await keepMailFile(MailFile(name: 'x.zip', type: 'application/zip', bytes: Uint8List(1)), 0), startsWith('Came with it, not kept'));
  });

  test('files the share sheet kept before are taken into the store under the names their notes link', () async {
    final it = kit();
    File('${data.path}/attachments/0a1b2c3d-0000-4000-8000-000000000009.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync([7, 7]);
    File('${data.path}/attachments/no-extension').writeAsBytesSync([1]);
    await it.takeInSharedFiles();
    expect(await it.store.sizeOf('0a1b2c3d-0000-4000-8000-000000000009.pdf'), 2);
    expect(File('${data.path}/attachments/no-extension').existsSync(), isTrue, reason: 'not a name the store keeps');
  });
}
