// Pictures reach every device, whatever road they took to the first one. A port of
// `src/app/core/sync/pictures.test.ts`. Matt's HelloTrade book: another program wrote the chapters through the MCP
// and dropped their JPEGs into the Mac's picture folder, so the Mac drew them and the phone showed every one broken -
// the Mac had marked each as sent without sending it, and the phone, having asked once when the note arrived, never
// asked again.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/sync/notes.dart';

import 'support.dart';

const picture = 'a1b2c3d4-0000-4000-8000-000000000001.jpg';
final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
final chapter = note('ch-1', '# Signing the order\n\n![The limit price](image/$picture)\n', createdAt: 1, updatedAt: 2);

/// What the account holds for a file, opened: it only ever holds it sealed.
Future<Uint8List?> opened(FakeService api, String id) async {
  final stored = api.files[id];
  return stored == null ? null : api.crypto.openBytes(api.accountKey, stored.bytes, 'file:$id');
}

/// A note written as the MCP writes one: sealed, naming its pictures, with no file sent.
Future<int> writtenElsewhere(FakeService api, Note written) => api.deviceWrites(written, extra: {'images': [picture]});

void main() {
  setUp(forgetPictureAsks);

  group('pictures that reached a device some other way than sync', () {
    test('are sent by the Mac that holds them, and fetched by a phone that asked before they were there', () async {
      final api = await FakeService.start(seed: testAccount);
      final phone = deviceOf(api, clock: 1000000);
      final mac = deviceOf(api, clock: 1000000, pictures: {picture: bytes});
      await writtenElsewhere(api, chapter);

      // The phone reads the chapter first: the picture is not in the account, so it has nothing to draw.
      await phone.run();
      expect(phone.notes.containsKey('ch-1'), isTrue);
      expect(phone.held.containsKey(picture), isFalse);

      // The Mac reads it, finds the picture in its own folder, and sends it.
      await mac.run();
      final id = fileId(FileKind.image, picture)!;
      expect(api.files[id], isNotNull);
      expect(mac.state.files[id]?.rev, greaterThan(0));

      // The phone's next pass a keystroke later does not ask again; the next timed pass does, and gets it.
      await phone.run();
      expect(phone.held.containsKey(picture), isFalse);
      phone.clock += askAgainMs;
      await phone.run();
      expect(phone.held[picture], bytes);
      expect(phone.state.files[id]?.rev, greaterThan(0));
    });

    test('repairs a Mac that marked a picture sent without sending it, as the older app did', () async {
      final api = await FakeService.start(seed: testAccount);
      final mac = deviceOf(api, clock: 5000000, pictures: {picture: bytes});
      await writtenElsewhere(api, chapter);
      await mac.run();
      // Put back as the older app left it: the note seen, the picture at revision 0, nothing in the account.
      final id = fileId(FileKind.image, picture)!;
      api.files.clear();
      mac.state = mac.state.copyWith(files: {id: const FileMark(rev: 0)});
      await mac.run();
      expect(await opened(api, id), bytes);
    });

    test('does not send a picture the account already holds, and settles it by asking for its head', () async {
      final api = await FakeService.start(seed: testAccount);
      final first = deviceOf(api, clock: 9000000, pictures: {picture: bytes});
      first.notes['ch-1'] = chapter;
      await first.run();
      final id = fileId(FileKind.image, picture)!;
      expect(api.files[id], isNotNull);

      // Signed in again with nothing remembered, holding the same picture: one HEAD, no upload.
      api.calls.clear();
      first.state = emptyState();
      await first.run();
      expect(api.calls.where((c) => c == 'PUT recordings/$id'), isEmpty);
      expect(api.calls, contains('HEAD recordings/$id'));
      expect(first.state.files[id]?.rev, greaterThan(0));
      // Settled: the pass after asks nothing about it.
      api.calls.clear();
      await first.run();
      expect(api.calls.any((c) => c.contains(id)), isFalse);
    });

    test('sends anyway where a HEAD cannot be asked, and a picture already there is taken as there', () async {
      final api = await FakeService.start(seed: testAccount, head: false);
      final mac = deviceOf(api, clock: 13000000, pictures: {picture: bytes});
      await writtenElsewhere(api, chapter);
      await mac.run();
      final id = fileId(FileKind.image, picture)!;
      expect(await opened(api, id), bytes);
      // Asked again with nothing remembered: the upload meets the one already there, and that settles it.
      mac.state = mac.state.copyWith(files: {});
      await mac.run();
      expect(mac.state.files[id]?.rev, api.files[id]?.rev);
      expect(mark(mac.notes['ch-1']!), mark(chapter));
    });
  });
}
