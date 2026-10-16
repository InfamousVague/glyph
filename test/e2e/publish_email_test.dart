// Publishing a notebook as a site, and email to a note, end to end against the REAL service (server) on this Mac,
// with the real crypto (the Rust core) and the app's own sign-up, over real sockets (docs/SITES.md, docs/MAIL.md):
//
//   GLYPH_MAILGUN_SIGNING_KEY=<key> tool/local-server.sh start      # prints GHOST_E2E_API; run.env has the data dir
//   GHOST_E2E_API=… GHOST_E2E_DATA=… GHOST_E2E_MAIL_KEY=<key> flutter test --no-pub test/e2e/publish_email_test.dart
//
// Skipped unless GHOST_E2E_API is set, and refused unless it names 127.0.0.1 (world.dart `LocalWorld`). A made-up
// account under a handle nobody has; the sample library's Portugal notebook, with a picture and a link between two
// of its pages; a mail posted to the service's webhook exactly as Mailgun posts one, signed with the key the service
// was started with. What the run made is written to build/e2e-publish-email/ for the browser to open.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/sample_library.dart' show seedLibrary;
import 'package:ghost_md/mail/mail_in.dart';
import 'package:ghost_md/share/sites.dart';

import '../team_sync/support.dart' show coreLibrary, coreSkip;
import 'world.dart';

const String _password = 'correct horse battery staple';

/// HMAC-SHA-256 over the core's SHA-256 (RFC 2104): Mailgun's signature of `timestamp` then `token`.
Future<String> hmac(Device device, String key, String message) async {
  var k = Uint8List.fromList(utf8.encode(key));
  if (k.length > 64) k = await device.crypto.sha256(k);
  final block = Uint8List(64)..setRange(0, k.length, k);
  final inner = await device.crypto.sha256(Uint8List.fromList([for (final b in block) b ^ 0x36, ...utf8.encode(message)]));
  final outer = await device.crypto.sha256(Uint8List.fromList([for (final b in block) b ^ 0x5c, ...inner]));
  return [for (final b in outer) b.toRadixString(16).padLeft(2, '0')].join();
}

/// A mail as a phone's mail app sends one: words in HTML with a photo shown inline, and a PDF attached.
String mime(String to, Uint8List photo) {
  String wrapped(String text) => [for (var i = 0; i < text.length; i += 76) text.substring(i, i + 76 > text.length ? text.length : i + 76)].join('\r\n');
  return [
    'From: Sam Lee <sam@example.com>',
    'To: $to',
    'Subject: =?UTF-8?Q?Saturday_at_the_caf=C3=A9?=',
    'Date: Fri, 16 Oct 2026 14:05:00 +0000',
    'MIME-Version: 1.0',
    'Content-Type: multipart/mixed; boundary="outer"',
    '',
    '--outer',
    'Content-Type: multipart/related; boundary="rel"',
    '',
    '--rel',
    'Content-Type: text/html; charset=utf-8',
    '',
    '<html><body><p>Meet at the <b>café</b> at ten, then the <a href="https://example.com/market">market</a>.</p><ul><li>bread</li><li>pomegranates</li></ul><p><img src="cid:harbour@sam" alt="The harbour"></p></body></html>',
    '--rel',
    'Content-Type: image/jpeg',
    'Content-ID: <harbour@sam>',
    'Content-Disposition: inline; filename="harbour.jpg"',
    'Content-Transfer-Encoding: base64',
    '',
    wrapped(base64.encode(photo)),
    '--rel--',
    '--outer',
    'Content-Type: application/pdf; name="menu.pdf"',
    'Content-Disposition: attachment; filename="menu.pdf"',
    'Content-Transfer-Encoding: base64',
    '',
    base64.encode(utf8.encode('%PDF-1.4\n% the menu\n')),
    '--outer--',
    '',
  ].join('\r\n');
}

void main() {
  final base = Platform.environment['GHOST_E2E_API'] ?? '';
  final key = Platform.environment['GHOST_E2E_MAIL_KEY'] ?? '';
  final data = Platform.environment['GHOST_E2E_DATA'] ?? '';
  final skip = base.isEmpty ? 'no local server: GHOST_E2E_API is not set' : (key.isEmpty ? 'GHOST_E2E_MAIL_KEY is not set' : coreSkip);
  late GhostCore core;
  late LocalWorld world;
  final out = Directory('build/e2e-publish-email');

  setUpAll(() async {
    if (skip != null) return;
    world = LocalWorld(base);
    core = await GhostCore.open(libraryPath: File(coreLibrary).absolute.path);
    out.createSync(recursive: true);
  });

  tearDownAll(() async {
    if (skip == null) await core.close();
  });

  test('a made-up account publishes the sample library\'s Portugal notebook as a site, and reads it back by its link alone', () async {
    final phone = Device(world, core, label: 'Phone');
    final handle = freshHandle('site');
    await phone.account.signUp(handle, _password);
    // The sample library, with a picture on The coast and a link from it to Lisbon.
    final photo = File('assets/sample/sample-smoke.jpg').readAsBytesSync();
    const picture = '6f1d2c3b-4a59-4e87-9c10-2b3a4c5d6e7f.jpg';
    phone.pictures[picture] = photo;
    final library = seedLibrary(DateTime(2026, 10, 16, 10).millisecondsSinceEpoch);
    for (final note in library) {
      final title = noteTitle(note.body);
      phone.notes[note.id] = title == 'The coast'
          ? note.copyWith(body: '${note.body}\n\n![The harbour at Cascais](image/$picture)\n\nThe first three days were in [[Lisbon, the first three days]].\n')
          : note;
    }
    final portugal = phone.notes.values.firstWhere((n) => noteTitle(n.body) == 'Portugal');
    final sites = Sites(account: phone.account, api: phone.api, crypto: phone.crypto, pictures: MapPictures(phone.pictures), listNotes: phone.disk.notes.list);
    final site = await sites.publish(portugal, phone.notes.values.toList());
    // The site, read by a stranger with the link alone.
    final stranger = Device(world, core, label: 'A reader');
    final strangers = Sites(account: stranger.account, api: stranger.api, crypto: stranger.crypto, pictures: MapPictures({}), listNotes: () async => const <Note>[]);
    final read = await strangers.readSite(site.id, site.key);
    expect(read.pages.map((p) => p.title), ['Portugal', 'Packing', 'Lisbon, the first three days', 'The coast']);
    expect(read.pictures?[picture], photo);
    // Another device of the account lists it, with its link.
    final mac = Device(world, core, label: 'Mac');
    await mac.account.signIn(handle, _password);
    final listed = await Sites(account: mac.account, api: mac.api, crypto: mac.crypto, pictures: MapPictures({}), listNotes: () async => const <Note>[]).refresh();
    expect(listed.single.link, site.link);
    File('${out.path}/site.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'handle': handle, 'id': site.id, 'key': site.key, 'link': site.link, 'updated': site.updated})}\n');
    // ignore: avoid_print
    print('published ${site.title} at /s/${site.id}#${site.key} (${read.pages.length} pages, ${read.pictures?.length ?? 0} picture)');
  }, skip: skip);

  test('a mail posted to the webhook with Mailgun\'s signature is kept sealed, and the next sync files it as a note', () async {
    final phone = Device(world, core, label: 'Phone', mailIn: syncMail);
    final handle = freshHandle('mail');
    await phone.account.signUp(handle, _password);
    final mail = MailIn(account: phone.account, keys: phone.keys, api: phone.api, crypto: phone.crypto);
    expect((await mail.refresh()).available, isTrue, reason: 'the service was started with a signing key');
    final address = await mail.newAddress();
    // Exactly what Mailgun posts for a route forwarding to …/mime.
    final timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final token = 'e2e-${DateTime.now().microsecondsSinceEpoch}-token';
    final photo = File('assets/sample/sample-smoke.jpg').readAsBytesSync();
    final form = {
      'recipient': address,
      'sender': 'sam@example.com',
      'subject': 'Saturday at the café',
      'body-mime': mime(address, photo),
      'timestamp': timestamp,
      'token': token,
      'signature': await hmac(phone, key, '$timestamp$token'),
    };
    final body = form.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('$base/v1/mail/inbound/mime'));
    request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    request.write(body);
    final answer = await request.close();
    final said = await answer.transform(utf8.decoder).join();
    client.close();
    expect(answer.statusCode, 200, reason: said);
    // A forged post is refused.
    final forged = await HttpClient().postUrl(Uri.parse('$base/v1/mail/inbound/mime'));
    forged.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    forged.write(body.replaceFirst(RegExp(r'signature=[0-9a-f]+'), 'signature=${'0' * 64}').replaceFirst('token=e2e', 'token=f2e'));
    expect((await forged.close()).statusCode, 401);
    // Waiting, sealed: not a word of it in the service's files.
    if (data.isNotEmpty) {
      final bytes = <int>[];
      for (final file in Directory(data).listSync().whereType<File>()) {
        bytes.addAll(file.readAsBytesSync());
      }
      final text = latin1.decode(bytes, allowInvalid: true).toLowerCase();
      for (final word in ['pomegranates', 'market', 'sam@example.com', 'saturday at the']) {
        expect(text.contains(word), isFalse, reason: '"$word" is in the service\'s files');
      }
    }
    // The app's sync opens it with the account's key pair and files it.
    await phone.sync();
    final filed = phone.notes.values.where((n) => n.body.contains('Saturday at the café')).toList();
    expect(filed, hasLength(1));
    final note = filed.single;
    expect(noteTitle(note.body), 'Saturday at the café');
    expect(note.body, startsWith('---\nfrom: "Sam Lee <sam@example.com>"\n---\n# Saturday at the café\n'));
    expect(note.body, contains('**café**'));
    expect(note.body, contains('[market](https://example.com/market)'));
    expect(note.body, contains('- pomegranates'));
    expect(note.body, contains('Came with it, not kept: menu.pdf'));
    final name = RegExp(r'image/([0-9a-f-]+\.jpg)').firstMatch(note.body)!.group(1)!;
    expect(phone.pictures[name], photo);
    expect(note.path, isNull);
    // Taken off the service once filed; and the note went on, as any note does, to the account's other devices.
    final waiting = await phone.api.callMap('GET', 'mail', token: phone.account.session!.token);
    expect(waiting['mail'], isEmpty);
    final mac = Device(world, core, label: 'Mac');
    await mac.account.signIn(handle, _password);
    await mac.sync();
    expect(mac.notes[note.id]?.body, note.body);
    expect(mac.pictures[name], photo);
    File('${out.path}/mail-note.md').writeAsStringSync(note.body);
    File('${out.path}/mail.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'handle': handle, 'address': address, 'noteId': note.id})}\n');
    // ignore: avoid_print
    print('mail to $address filed as "${noteTitle(note.body)}" (${note.id}), on the Mac too');
  }, skip: skip);
}
