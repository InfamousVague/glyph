import 'dart:convert';
import 'dart:typed_data';

import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/mail/mail_in.dart';

/// A mail laid out as the service lays one out before sealing it (server/src/mail/message.rs, `GML1`).
Uint8List gml1({String subject = 'Café plans', String from = 'Sam Lee <sam@example.com>', String to = 'k7m2q9xh4t3vbn8p@in.ghostmarkdown.com', int date = 1792159500000, String body = 'Meet at the café.', List<({String name, String type, List<int> bytes, String? cid})> files = const []}) {
  final head = utf8.encode(jsonEncode({
    'v': 1,
    'subject': subject,
    'from': from,
    'to': to,
    'date': date,
    'body': body,
    'files': [
      for (final f in files) {'name': f.name, 'type': f.type, 'size': f.bytes.length, 'cid': f.cid},
    ],
  }));
  final out = BytesBuilder()
    ..add('GML1'.codeUnits)
    ..add((ByteData(4)..setUint32(0, head.length)).buffer.asUint8List())
    ..add(head);
  for (final f in files) {
    out.add(f.bytes);
  }
  return out.takeBytes();
}

/// [payload] sealed as the service seals a mail [id] to the account whose encryption public key is [pub]: a fresh key
/// wrapped to it, and the mail under that key.
Future<({String wrapped, String blob})> sealedFor(AccountCrypto crypto, String pub, String id, Uint8List payload) async {
  final raw = crypto.randomBytes(32);
  final wrapped = await crypto.wrapFor(pub, raw, mailWrapContext(id));
  final key = await crypto.importSealKey(raw);
  return (wrapped: wrapped, blob: toBase64Url(await crypto.sealBytes(key, payload, mailSealContext(id))));
}

/// A PNG's first bytes, enough for the core to call it one.
const List<int> png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
