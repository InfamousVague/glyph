// What a real device is made of, over the Mac's build of the core (tool/build-native.sh host): its recordings and
// pictures as sync and a share ask for them (lib/sync/device.dart over lib/core/native/files.dart), its notes in
// the real library (lib/sync/local.dart), and its key store (lib/account/device_keys.dart) keeping the session and
// the three keys by the real crypto's `keep` and `restore`. The Android half of the secure store
// (android/…/SecureStore.kt) cannot run here: what is tried is the channel's own words, and the store in memory.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/core/native/files.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/versions_store.dart';
import 'package:ghost_md/sync/device.dart';
import 'package:ghost_md/sync/local.dart';
import 'package:ghost_md/sync/notes.dart';

import '../support/fake_service.dart';
import '../support/sync_device.dart';
import 'support.dart';

/// A PNG of [width] by [height], drawn by the engine.
Future<Uint8List> png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < height; y += 8) {
    canvas.drawRect(ui.Rect.fromLTWH(0, y.toDouble(), width.toDouble(), 4), ui.Paint()..color = ui.Color.fromARGB(255, y % 256, (y * 7) % 256, 120));
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<(int, int)> sizeOf(Uint8List bytes) async {
  final described = await ui.ImageDescriptor.encoded(await ui.ImmutableBuffer.fromUint8List(bytes));
  return (described.width, described.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = coreSkip;
  late Directory root;
  late GhostCore core;
  late CoreFiles files;
  late CoreCrypto crypto;

  setUpAll(() async {
    if (!coreBuilt) return;
    root = Directory(Directory.systemTemp.createTempSync('ghost-device-test-').resolveSymbolicLinksSync());
    core = await openCore();
    await core.init(dataDir: '${root.path}/data', cacheDir: '${root.path}/cache');
    files = CoreFiles(core.invoke);
    crypto = CoreCrypto(core.invoke);
  });

  tearDownAll(() async {
    if (!coreBuilt) return;
    await core.close();
    root.deleteSync(recursive: true);
  });

  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
  final tape = Uint8List.fromList([...ascii.encode('RIFF'), 36, 0, 0, 0, ...ascii.encode('WAVEfmt '), 1, 2, 3, 4]);

  group('the device\'s files', () {
    test('a whole pass against the service lands a note, its picture, its recording and its versions file in the real library, and sends this device\'s own back', () async {
      // The service in memory, with the real crypto; another device of the account, its notes in maps.
      final service = await FakeService.start(
        seed: (handle: 'matt', password: 'correct horse'),
        crypto: crypto,
        verify: (publicKey, nonce, signature) async => await core.invoke('device_key_verify', {'public': publicKey, 'nonce': nonce, 'signature': signature}) as bool,
      );
      final other = SyncDevice<SyncState>(service, state: emptyState());
      other.notes['n1'] = const Note(id: 'n1', body: '# Trip\n\n![](image/abc.jpg)', createdAt: 1000, updatedAt: 1000, recordingMs: 400, segments: [Segment(text: 'hi', startMs: 0, endMs: 400)]);
      other.held['abc.jpg'] = jpeg;
      other.tapes['n1'] = tape;
      other.keepVersions('n1', '# Ghost.md versions 1\n# note n1\n\nv1 2026-10-05T00:00:00.000Z matt 00000000 full\n  +# Trip\n');
      Future<Outcome> pass(SyncDevice<SyncState> d) =>
          syncNotes(SyncContext(token: d.token, key: d.key, notes: d.local, files: d.files, state: d.state, save: d.save, api: d.api, crypto: crypto, now: d.now));
      expect((await pass(other)).unsent, 0);

      // This device: the library's notes, the versions store, and the core's files.
      final pictured = <String>[];
      final notes = LibraryNotes(core.invoke);
      final kept = KeptFiles(versions: VersionsStore(core.invoke, kept: MemoryStored()), bytes: CoreDeviceBytes(files, onPicture: pictured.add));
      var state = emptyState();
      Future<Outcome> here() => syncNotes(SyncContext(
            token: service.signedIn(),
            key: service.accountKey,
            notes: notes,
            files: kept,
            state: state,
            save: (next) => state = next,
            api: Api(base: 'http://service.test/api', fetcher: service.fetcher),
            crypto: crypto,
          ));
      final arrived = await here();
      expect((arrived.changed, arrived.unsent, arrived.reason), (1, 0, null));
      final got = (await notes.get('n1'))!;
      expect(got.body, '# Trip\n\n![](image/abc.jpg)');
      expect(got.segments, hasLength(1));
      expect(await files.read(CoreFileKind.image, 'abc.jpg'), jpeg);
      expect(pictured, ['abc.jpg']);
      expect(await files.read(CoreFileKind.recording, 'n1'), tape);
      expect(utf8.decode((await kept.read(FileKind.versions, 'n1'))!), contains('v1 2026-10-05'));
      // The recording's fingerprint is the core's own, with the tape never read into Dart; no tape is said as none.
      expect((await kept.digest('n1'))?.sha, await crypto.sha16(tape));
      expect((await kept.digest('n9'))?.sha, isNull);
      expect(await kept.digest('n9'), isNotNull);
      // A quiet pass asks for nothing more of the files.
      final before = service.calls.length;
      expect((await here()).changed, 0);
      expect(service.calls.sublist(before).where((call) => call.contains('recordings/')), isEmpty);

      // Written here: a picture kept by the core, a note in the library; the other device reads both.
      await files.write(CoreFileKind.image, 'here.jpg', jpeg);
      await notes.apply(const Note(id: 'n2', body: 'from the library ![](image/here.jpg)', createdAt: 2000, updatedAt: 2000));
      expect((await here()).unsent, 0);
      await pass(other);
      expect(other.notes['n2']?.body, 'from the library ![](image/here.jpg)');
      expect(other.held['here.jpg'], jpeg);
    }, skip: skip);

    test('a share\'s pictures are read and kept by the core, and a PNG too large is drawn smaller as a PNG', () async {
      final kept = <String>[];
      final pictures = CorePictures(files, onPicture: kept.add);
      expect(await pictures.read('missing.png'), isNull);
      expect(await pictures.read('../../etc/passwd'), isNull);
      await pictures.keep('kept.jpg', jpeg);
      expect(await pictures.read('kept.jpg'), jpeg);
      expect(kept, ['kept.jpg']);
      // A picture that is not what its name says is the core's to refuse, in its own words.
      await expectLater(pictures.keep('wrong.png', jpeg), throwsA(anything));

      final wide = await png(2048, 512);
      final drawn = await pictures.smaller(wide);
      expect(await sizeOf(drawn), (1024, 256));
      expect(drawn.length, lessThan(wide.length));
      // Still a PNG, so still what its name says: the core keeps it.
      await pictures.keep('wide.png', drawn);
      final tall = await smallerPng(await png(300, 1500), longSide: 500);
      expect(await sizeOf(tall), (100, 500));
      // Small enough already, not a PNG, or not a picture at all: as it is.
      final small = await png(640, 480);
      expect(identical(await pictures.smaller(small), small), isTrue);
      expect(identical(await pictures.smaller(jpeg), jpeg), isTrue);
      final broken = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]);
      expect(identical(await pictures.smaller(broken), broken), isTrue);
      // A device with a JPEG writer draws a photograph smaller with it (the phone's: Kotlin's `Pictures.smaller`),
      // and the copy, still a JPEG, is still what its name says: the core keeps it.
      final written = Uint8List.fromList(jpeg.sublist(0, jpeg.length - 1));
      final withWriter = CorePictures(files, jpeg: (bytes, {required longSide, required quality}) async => written);
      expect(await withWriter.smaller(jpeg), written);
      await withWriter.keep('copy.jpg', await withWriter.smaller(jpeg));
      expect(await withWriter.read('copy.jpg'), written);
      // A PNG stays the engine's own to draw, writer or no.
      expect(await sizeOf(await withWriter.smaller(wide)), (1024, 256));
      // And a test's own way of drawing smaller, whole.
      expect(await CorePictures(files, smallerWith: (bytes) async => Uint8List.fromList([1])).smaller(wide), [1]);
    }, skip: skip);
  });

  group('the device\'s key store', () {
    const session = Session(token: 'tok-1', handle: 'matt', accountId: 7);

    test('keeps the session and the three keys through the core, and a launch later raises them again', () async {
      final store = MemorySecureStore();
      final first = DeviceKeyStore(crypto: crypto, store: store);
      expect((await first.session(), await first.accountKey(), await first.deviceKey(), await first.encryptionKey()), (null, null, null, null));
      final account = await crypto.settle(await crypto.newAccountKey());
      final device = await crypto.newDeviceKey();
      final pair = await crypto.settleEncryptionKey(await crypto.newEncryptionKey());
      await first.setSession(session);
      await first.setAccountKey(account);
      await first.setDeviceKey(device);
      await first.setEncryptionKey(pair);
      expect(store.held.keys.toSet(), {'glyph-account-session', 'account', 'device', 'encryption'});
      expect(jsonDecode(store.held['glyph-account-session']!), session.toJson());
      // Held by the handle it was given: no second copy in the core for every pass that asks.
      expect(identical(await first.accountKey(), account), isTrue);
      final sealed = await crypto.seal(account, {'note': 'sealed before the app closed'}, 'note:n1');
      final wrapped = await crypto.wrapFor(await crypto.encryptionPublicKeyOf(pair), Uint8List.fromList(List.filled(32, 9)), wrapContext('org1', 1));

      // The next launch: another store over what was kept, and the keys are the same keys.
      final next = DeviceKeyStore(crypto: crypto, store: store);
      expect(await next.session(), session);
      final account2 = (await next.accountKey())!, device2 = (await next.deviceKey())!, pair2 = (await next.encryptionKey())!;
      expect(identical(account2, account), isFalse);
      expect(account2.extractable || device2.extractable || pair2.extractable, isFalse);
      expect(await crypto.open(account2, sealed, 'note:n1'), {'note': 'sealed before the app closed'});
      expect(await crypto.publicKeyOf(device2), await crypto.publicKeyOf(device));
      final signature = await crypto.signNonce(device2, 'nonce-1');
      expect(await core.invoke('device_key_verify', {'public': await crypto.publicKeyOf(device), 'nonce': 'nonce-1', 'signature': signature}), isTrue);
      expect(await crypto.unwrapWith(pair2, wrapped, wrapContext('org1', 1)), List.filled(32, 9));
      expect(identical(await next.accountKey(), account2), isTrue);

      // Signing out: each forgotten, here and where it was kept.
      await next.setAccountKey(null);
      await next.setDeviceKey(null);
      await next.setEncryptionKey(null);
      await next.setSession(null);
      expect(store.held, isEmpty);
      expect((await next.session(), await next.accountKey()), (null, null));
      expect(await DeviceKeyStore(crypto: crypto, store: store).deviceKey(), isNull);
    }, skip: skip);

    test('answers null, never a throw, for what it cannot read, and holds what it cannot keep until the app closes', () async {
      final store = MemorySecureStore()
        ..held['glyph-account-session'] = '{"token": 4'
        ..held['account'] = 'not a key at all'
        ..held['device'] = ''
        ..held['encryption'] = 'AAAA';
      final keys = DeviceKeyStore(crypto: crypto, store: store);
      expect((await keys.session(), await keys.accountKey(), await keys.deviceKey(), await keys.encryptionKey()), (null, null, null, null));
      // A session that is not whole is no session.
      store.held['glyph-account-session'] = jsonEncode({'token': 't', 'handle': 'matt'});
      expect(await DeviceKeyStore(crypto: crypto, store: store).session(), isNull);

      // A store that fails every call: signed in for as long as the app is open, and nothing thrown.
      final broken = DeviceKeyStore(crypto: crypto, store: _Broken());
      expect((await broken.session(), await broken.accountKey()), (null, null));
      final account = await crypto.settle(await crypto.newAccountKey());
      await broken.setAccountKey(account);
      await broken.setSession(session);
      expect((await broken.session(), identical(await broken.accountKey(), account)), (session, true));
    }, skip: skip);

    test('the phone\'s store is asked by name over its channel: read, write, and delete for a value forgotten', () async {
      final calls = <String>[];
      final kept = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ChannelSecureStore.channel, (call) async {
        calls.add('${call.method} ${jsonEncode(call.arguments)}');
        final args = (call.arguments as Map).cast<String, Object?>();
        final name = args['name'] as String;
        switch (call.method) {
          case 'read':
            return kept[name];
          case 'write':
            kept[name] = args['value'] as String;
          case 'delete':
            kept.remove(name);
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ChannelSecureStore.channel, null));
      expect(ChannelSecureStore.channel.name, 'ghost_md/secure_store');
      const store = ChannelSecureStore();
      expect(await store.read('account'), isNull);
      await store.write('account', 'raw-key');
      expect(await store.read('account'), 'raw-key');
      await store.write('account', null);
      expect(calls, [
        'read {"name":"account"}',
        'write {"name":"account","value":"raw-key"}',
        'read {"name":"account"}',
        'delete {"name":"account"}',
      ]);
      // And the key store over it: a phone with no handler (a platform that never registered one) is signed out,
      // not broken.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ChannelSecureStore.channel, null);
      final keys = DeviceKeyStore(crypto: crypto, store: store);
      expect(await keys.session(), isNull);
      await keys.setSession(session);
      expect(await keys.session(), session);
      // Off Android, the device's store is memory.
      expect(deviceSecureStore(), isA<MemorySecureStore>());
    }, skip: skip);
  });
}

class _Broken implements SecureStore {
  @override
  Future<String?> read(String name) async => throw PlatformException(code: 'secure_store', message: 'The Keystore is not there.');

  @override
  Future<void> write(String name, String? value) async => throw PlatformException(code: 'secure_store', message: 'The Keystore is not there.');
}
