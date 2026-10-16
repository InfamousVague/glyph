// The promise of email to a note, held across the two halves that keep it (docs/MAIL.md): a mail sealed by the
// SERVICE's own code (server/src/mail/seal.rs, written by its test `the_sealed_mail_the_app_opens` into
// fixtures/sealed_mail.json) opens with the account's private key in the APP's own code - lib/mail/mail_in.dart over
// the Rust core's real `unwrap_with`, `seal_key_import` and `open` (lib/account/crypto.dart) - and with no other key,
// and not as another mail.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/mail/mail_in.dart';
import 'package:ghost_md/mail/mail_note.dart';

const _library = 'native/target/debug/libghost_core.dylib';

void main() {
  final built = File(_library).existsSync();
  final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';
  final fixture = (jsonDecode(File('test/mail/fixtures/sealed_mail.json').readAsStringSync()) as Map).cast<String, Object?>();
  late GhostCore core;
  late CoreCrypto crypto;

  setUpAll(() async {
    if (!built) return;
    core = await GhostCore.open(libraryPath: File(_library).absolute.path);
    crypto = CoreCrypto(core.invoke);
  });

  tearDownAll(() async {
    if (built) await core.close();
  });

  test('a mail the service sealed opens with the account\'s private key, through the core, into its note', () async {
    final pair = await crypto.importEncryptionKey((fixture['jwk'] as Map).cast<String, Object?>());
    // The pair's public half is the one the service sealed to.
    expect(await crypto.encryptionPublicKeyOf(pair), fixture['pub']);
    final id = fixture['id'] as String;
    final mail = await openSealedMail(crypto, pair, id: id, wrapped: fixture['wrapped'] as String, blob: fixture['blob'] as String);
    expect((mail.subject, mail.from), ('Café plans', 'Sam Lee <sam@example.com>'));
    expect(mail.body, contains('**café**'));
    expect(mail.body, contains('![the door](cid:pic1@x)'));
    expect(mail.body, isNot(contains('tracker')));
    expect(mail.files.map((f) => (f.name, f.type)), [('door.png', 'image/png'), ('menu.pdf', 'application/pdf')]);
    expect(mail.files.first.bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    final body = mailNoteBody(mail, pictures: {0: mailPictureName(id, 0, 'png')}, others: [await notKeptLine(mail.files[1], 1)]);
    expect(body, startsWith('---\nfrom: "Sam Lee <sam@example.com>"\n---\n# Café plans\n'));
    expect(body, contains('![the door](image/${mailPictureName(id, 0, 'png')})'));
    expect(body, contains('Came with it, not kept: menu.pdf (9 bytes).'));
  }, skip: skip);

  test('no other account\'s key opens it, and it does not open as another mail', () async {
    final pair = await crypto.importEncryptionKey((fixture['jwk'] as Map).cast<String, Object?>());
    final stranger = await crypto.newEncryptionKey();
    final id = fixture['id'] as String;
    await expectLater(openSealedMail(crypto, stranger, id: id, wrapped: fixture['wrapped'] as String, blob: fixture['blob'] as String), throwsA(anything));
    await expectLater(openSealedMail(crypto, pair, id: 'another-mail-id-000000', wrapped: fixture['wrapped'] as String, blob: fixture['blob'] as String), throwsA(anything));
  }, skip: skip);
}
