// A note's files and the words read in its things, between two devices (lib/sync/notes.dart): sealed like every
// other file, by name; a file larger than travels left where it was added; the words read after a note went owed
// again so the other device fetches them; and a device that keeps no files (an iPhone, for now) asks for none.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/attachment_refs.dart';
import 'package:ghost_md/sync/notes.dart';

import 'support.dart';

const String file = 'b1b2c3d4-0000-4000-8000-000000000002.pdf';
final Uint8List lease = Uint8List.fromList(utf8.encode('%PDF-1.4 a small lease'));

Future<Uint8List?> opened(FakeService api, String id) async {
  final stored = api.files[id];
  return stored == null ? null : api.crypto.openBytes(api.accountKey, stored.bytes, 'file:$id');
}

void main() {
  setUp(forgetPictureAsks);

  test('a file a note links goes sealed with it, and the other device fetches it by name', () async {
    final api = await FakeService.start(seed: testAccount);
    final phone = deviceOf(api, clock: 1000000);
    final mac = deviceOf(api, clock: 1000000);
    phone.files.attachments[file] = lease;
    phone.notes['flat'] = note('flat', '# Flat\n\n[Lease.pdf](file/$file "22 bytes")\n', createdAt: 1, updatedAt: 2);
    await phone.run();
    final id = fileId(FileKind.attachment, file)!;
    expect(await opened(api, id), lease);
    expect(api.files[id]!.bytes, isNot(lease), reason: 'the service holds it sealed');

    await mac.run();
    expect(mac.notes['flat']!.body, phone.notes['flat']!.body);
    expect(mac.files.attachments[file], lease);
    expect(mac.state.files[id]?.rev, greaterThan(0));
  });

  test('a file larger than travels stays where it was added, is never read, and nobody asks for it', () async {
    final api = await FakeService.start(seed: testAccount);
    final phone = deviceOf(api, clock: 1000000);
    final mac = deviceOf(api, clock: 1000000);
    phone.files.attachments[file] = Uint8List(attachmentSyncLimit + 1);
    phone.notes['big'] = note('big', '[Film.mov](file/$file "26.3 MB")\n', createdAt: 1, updatedAt: 2);
    await phone.run();
    expect(api.files[fileId(FileKind.attachment, file)!], isNull);
    expect(phone.files.attachmentReads, 0, reason: 'its length was asked, not its bytes');
    api.calls.clear();
    await mac.run();
    expect(mac.notes.containsKey('big'), isTrue);
    expect(api.calls.where((call) => call.contains('a-pdf-')), isEmpty, reason: 'its line says it is larger than travels');
  });

  test('words read after the note went are sent, the note owed again, and the other device fetches them', () async {
    final api = await FakeService.start(seed: testAccount);
    final phone = deviceOf(api, clock: 1000000);
    final mac = deviceOf(api, clock: 1000000);
    phone.files.attachments[file] = lease;
    phone.notes['flat'] = note('flat', '# Flat\n\n[Lease.pdf](file/$file)\n', createdAt: 1, updatedAt: 2);
    await phone.run();
    await mac.run();
    expect(mac.files.texts, isEmpty);

    // The phone reads the lease afterwards: its words are owed to the account with the note that shows it.
    phone.files.texts['file/$file'] = Uint8List.fromList(utf8.encode('Rent is due monthly'));
    phone.owed.add('flat');
    await phone.run();
    final id = fileId(FileKind.text, 'file/$file')!;
    expect(utf8.decode((await opened(api, id))!), 'Rent is due monthly');
    expect(phone.owed, isEmpty, reason: 'sent with the note');

    await mac.run();
    expect(utf8.decode(mac.files.texts['file/$file']!), 'Rent is due monthly');
  });

  test('a device that keeps no files fetches none and sends none', () async {
    final api = await FakeService.start(seed: testAccount);
    final phone = deviceOf(api, clock: 1000000);
    final iphone = deviceOf(api, clock: 1000000);
    iphone.files.keepsMedia = false;
    phone.files.attachments[file] = lease;
    phone.notes['flat'] = note('flat', '# Flat\n\n[Lease.pdf](file/$file)\n', createdAt: 1, updatedAt: 2);
    await phone.run();
    api.calls.clear();
    await iphone.run();
    expect(iphone.notes.containsKey('flat'), isTrue);
    expect(iphone.files.attachments, isEmpty);
    expect(api.calls.where((call) => call.contains('a-pdf-')), isEmpty);
  });
}
