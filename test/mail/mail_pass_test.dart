// Email to a note, on a device (lib/mail/mail_in.dart): the address turned on (the account's encryption key seen to
// first), made anew and off; and a sync pass filing what was mailed - opened with the account's pair, its pictures
// kept, its note written into the library with no folder, the sealed copy taken off the service - once, however
// often the pass runs. Over the service in memory and the fake crypto; the real crypto's half is sealed_mail_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart' show Api;
import 'package:ghost_md/account/enc_key.dart';
import 'package:ghost_md/mail/mail_in.dart';
import 'package:ghost_md/mail/mail_note.dart';
import 'package:ghost_md/sync/notes.dart' show FileKind;

import '../account_ui/support.dart';
import 'support.dart';

/// The account's encryption public key, made and registered as a device does.
Future<String> publicKey(Device device) async {
  final kept = await ensureEncryptionKey(EncryptionKeyContext(token: device.account.session!.token, accountKey: (await device.account.accountKey())!, keys: device.keys, api: device.api, crypto: device.service.crypto));
  return kept.pub;
}

/// A mail as the service would keep it, waiting for this account.
Future<void> mailed(Device device, String id, {int at = 1, String subject = 'Café plans', List<({String name, String type, List<int> bytes, String? cid})> files = const []}) async {
  final sealed = await sealedFor(device.service.crypto, await publicKey(device), id, gml1(subject: subject, body: 'Meet at the café.\n\n![the door](cid:pic1@x)', files: files));
  device.service.mail[id] = (wrapped: sealed.wrapped, blob: sealed.blob, at: at);
}

void main() {
  test('an address is turned on with the account\'s key seen to, made anew, and turned off', () async {
    final device = await Device.make(publishing: true);
    final mail = device.mailIn!;
    expect((await mail.refresh()).address, isNull);
    final first = await mail.newAddress();
    expect(first, endsWith('@in.ghostmarkdown.com'));
    expect(device.service.calls, containsAllInOrder(['GET account/key', 'PUT account/key', 'POST mail/address']));
    expect(mail.address?.address, first);
    final second = await mail.newAddress();
    expect(second, isNot(first));
    await mail.turnOff();
    expect((mail.address?.address, mail.address?.available), (null, true));
    expect(device.service.mailAddress, isNull);
  });

  test('a service that takes no mail, or has no mail routes, reads as one with nothing to offer', () async {
    final service = await FakeService.start(seed: seeded);
    service.takesMail = false;
    final device = await Device.make(service: service, publishing: true);
    expect((await device.mailIn!.refresh()).available, isFalse);
    final before = await FakeService.start(seed: seeded);
    final older = await Device.make(service: before, publishing: true, fetcher: (request) async => request.url.path.contains('/mail') ? FetchResponse.json(404, {'error': 'no such route'}) : before.fetcher(request));
    final said = await older.mailIn!.refresh();
    expect((said.address, said.available), (null, false));
  });

  test('a pass files a mail as a note in the Inbox, its picture kept in place, and takes it off the service', () async {
    final device = await Device.make(publishing: true);
    await mailed(device, 'AbCdEfGhIjKlMnOpQrStUv', files: [
      (name: 'door.png', type: 'image/png', bytes: png, cid: 'pic1@x'),
      (name: 'menu.pdf', type: 'application/pdf', bytes: '%PDF-1.4\n'.codeUnits, cid: null),
    ]);
    await device.engine!.syncNow();
    expect(device.engine!.status.value.phase, 'idle', reason: '${device.engine!.status.value.message}');
    final note = device.notes.held[mailNoteId('AbCdEfGhIjKlMnOpQrStUv')]!;
    final picture = mailPictureName('AbCdEfGhIjKlMnOpQrStUv', 0, 'png');
    expect(note.body, startsWith('---\nfrom: "Sam Lee <sam@example.com>"\n---\n# Café plans\n\nMeet at the café.\n\n![the door](image/$picture)\n'));
    expect(note.body, contains('Came with it, not kept: menu.pdf (9 bytes).'));
    expect(note.path, isNull, reason: 'no folder: it lands in Inbox/');
    expect(note.createdAt, 1792159500000, reason: 'when it was sent');
    expect(await device.files.read(FileKind.image, picture), png);
    expect(device.service.mail, isEmpty, reason: 'the sealed copy goes once the note is filed');
    // The same pass sent the note on to the account, sealed, as any new note.
    expect(device.service.notes.keys, contains(note.id));
  });

  test('a mail filed already is not filed twice: a pass cut short, or a second device, writes one note', () async {
    final device = await Device.make(publishing: true);
    await mailed(device, 'AbCdEfGhIjKlMnOpQrStUv');
    final ctx = MailPassContext(token: device.account.session!.token, api: device.api, crypto: device.service.crypto, pair: () async => (await device.keys.encryptionKey())!, notes: device.notes, files: device.files, now: () => 5);
    // The note is written, and the service never heard: the mail is still there.
    final kept = device.service.mail['AbCdEfGhIjKlMnOpQrStUv']!;
    expect(await syncMail(ctx), 1);
    device.service.mail['AbCdEfGhIjKlMnOpQrStUv'] = kept;
    device.notes.held[mailNoteId('AbCdEfGhIjKlMnOpQrStUv')] = device.notes.held[mailNoteId('AbCdEfGhIjKlMnOpQrStUv')]!.copyWith(body: '# Café plans\n\nEdited since.');
    expect(await syncMail(ctx), 0, reason: 'filed already');
    expect(device.notes.held, hasLength(1));
    expect(device.notes.held.values.single.body, contains('Edited since.'), reason: 'and left as the person left it');
    expect(device.service.mail, isEmpty);
  });

  test('mail is filed oldest first, and a pass with none, or against a service with no mail routes, asks once and is quiet', () async {
    final device = await Device.make(publishing: true);
    await mailed(device, 'later-later-later-0001', at: 20, subject: 'Later');
    await mailed(device, 'sooner-sooner-sooner01', at: 10, subject: 'Sooner');
    final ctx = MailPassContext(token: device.account.session!.token, api: device.api, crypto: device.service.crypto, pair: () async => (await device.keys.encryptionKey())!, notes: device.notes, files: device.files, now: () => 5);
    device.service.calls.clear();
    expect(await syncMail(ctx), 2);
    expect(device.service.calls.where((c) => c.startsWith('GET mail/')), ['GET mail/sooner-sooner-sooner01', 'GET mail/later-later-later-0001']);
    device.service.calls.clear();
    expect(await syncMail(ctx), 0);
    expect(device.service.calls, ['GET mail']);
    final older = MailPassContext(token: 't', api: Api(base: 'http://service.test/api', fetcher: (_) async => FetchResponse.json(404, {'error': 'no such route'})), crypto: device.service.crypto, pair: () async => throw StateError('not asked'), notes: device.notes, files: device.files, now: () => 5);
    expect(await syncMail(older), 0);
  });

  test('a mail that will not open is left waiting, and the pass goes on to the next', () async {
    final device = await Device.make(publishing: true);
    await mailed(device, 'good-good-good-good-01', at: 2);
    device.service.mail['bad-bad-bad-bad-bad-01'] = (wrapped: 'AAAA', blob: 'AAAA', at: 1);
    await device.engine!.syncNow();
    expect(device.notes.held.keys, [mailNoteId('good-good-good-good-01')]);
    expect(device.service.mail.keys, ['bad-bad-bad-bad-bad-01']);
    expect(device.engine!.status.value.phase, 'idle');
  });
}
