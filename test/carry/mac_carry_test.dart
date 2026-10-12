// The carry from the Tauri app on a Mac (lib/carry/mac_carry.dart; docs/CUTOVER.md, section 7): a made-up
// `~/Library` with a Tauri app's folder and its web view's storage in it (webkit_make.dart), this app's own folder
// beside them, and the Rust core's real crypto raising the keys. Nothing here is anybody's: the notes, the keys
// and the session are made in this file.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/carry/mac_carry.dart';
import 'package:ghost_md/carry/tauri_carry.dart';
import 'package:ghost_md/core/mac_app.dart';
import 'package:ghost_md/core/native/device_paths.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/team/docs.dart';

import '../team_sync/support.dart' show coreBuilt, coreSkip, openCore;
import 'tauri_carry_test.dart' show FakeDevice, MapPrefs;
import 'webkit_make.dart';
import 'webkit_stores_test.dart' show accountRaw, edPublic, edSeed, pairPoint, pairScalar;

/// The Mac's half, in a test: a Keychain that holds [master] or nothing, and a disk that clones or cannot.
class FakeMac implements MacCarryDevice {
  FakeMac({this.master, this.clones = false});

  Uint8List? master;
  bool clones;
  int asked = 0;
  final List<String> cloned = [];

  @override
  Future<Uint8List?> masterKey() async {
    asked += 1;
    // As WebKit keeps it: base64 text.
    return master == null ? null : Uint8List.fromList(ascii.encode(base64.encode(master!)));
  }

  @override
  Future<bool> clone(String from, String to) async {
    if (!clones) return false;
    File(from).copySync(to);
    cloned.add(to);
    return true;
  }
}

void main() {
  late GhostCore core;
  late Directory temp;
  late String library, tauri, own;
  final master = randomBytes(16);
  final written = DateTime.utc(2026, 9, 1, 8, 30);

  setUpAll(() async {
    if (coreBuilt) core = await openCore();
  });
  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  void put(String path, String words) {
    File('$tauri/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(words)
      ..setLastModifiedSync(written);
  }

  /// What the page sealed under its account key: the core's own seal under the same bytes.
  Future<String> sealed(String context, {Uint8List? raw}) async {
    final key = ((await core.invoke('key_restore', {'kind': 'account', 'raw': toBase64Url(raw ?? accountRaw)})) as Map)['key'];
    return await core.invoke('seal', {'key': key, 'context': context, 'text': jsonEncode({'words': 'made up'})}) as String;
  }

  Map<String, String> pageKept({String? notification}) => {
        'glyph-preferences': '{"theme":"dawn","workspaces":{"list":[{"id":"w1","name":"Harbour"}]}}',
        'glyph-account-session': '{"token":"mac-carry-token-not-real","handle":"cutover","accountId":4242}',
        'glyph-github-token': 'ghp_mac_carry_not_real',
        'glyph-sync-4242-notes': '{"cursor":9,"notes":{}}',
        'glyph-sync-4242-notifications': jsonEncode({
          'cursor': 3,
          'items': {
            'n1': {'id': 'n1', 'rev': 1, 'kind': 'invite'},
            if (notification != null) 'n2': {'id': 'n2', 'rev': 2, 'kind': 'written-up', 'blob': notification},
          },
        }),
        'glyph-versions-unsent': '[]',
        'someone-elses': 'never carried',
      };

  /// A Mac as the Tauri app left it.
  void makeMac({Map<String, String>? local, Uint8List? wrapUnder, bool keys = true}) {
    put('Library/Inbox/First note.md', '---\nid: a\n---\nfirst');
    put('Library/workspaces/Harbour/Second.md', '---\nid: b\n---\nsecond');
    put('Library/workspaces/Harbour/Second.versions', 'versions of b');
    put('Library/.glyph/library.json', '{"version":1}');
    put('Library/.glyph/notes/a.json', '{"recordingMs":16000}');
    put('Library/.glyph/index.sqlite', 'an index');
    put('Library/.glyph/index.sqlite-wal', 'its log');
    put('Library/.DS_Store', 'the Finder\'s');
    put('Library/Inbox/.0123456789abcdef0123456789abcdef.tmp', 'a write cut short');
    Directory('$tauri/Library/orgs').createSync(recursive: true);
    put('images/p1.jpg', 'a picture');
    put('recordings/r1.wav', 'a tape');
    put('video/v1.mp4', 'a film');
    put('models/ggml-base.en-q5_1.bin', 'a model');
    put('models/Qwen.gguf.part', 'half a model');
    put('ota/20261007000113/ota.json', '{}');
    put('ota/state.json', '{}');
    put('jobs/config.json', '{}');
    put('index/0123456789abcdef.sqlite', 'another index');
    put('slack.json', '{"channels":{"c0ffee-1":"https://hooks.slack.com/services/T000/B000/x"}}');
    put('notion.json', '{"accessToken":"secret_x","refreshToken":null,"botId":"bot1","workspaceId":"ws1","workspaceName":"Space","workspaceIcon":null}');
    Link('$tauri/Library/Inbox/elsewhere').createSync(temp.path);
    makeWebKit(Directory('$library/WebKit/com.mattssoftware.glyph/WebsiteData'), local: local ?? pageKept(), databases: [
      if (keys) accountDatabase(wrapUnder ?? master, account: accountRaw, encryption: (scalar: pairScalar, point: pairPoint), device: (seed: edSeed, public: edPublic)),
      teamDatabase({
        'note_mac_team_1': (state: [1, 2, 3, 250, 251, 252], seq: 7, snapshotSeq: 5, pending: [
          [9, 8, 7],
          [6],
        ]),
      }),
    ]);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('maccarry').absolute;
    library = '${temp.resolveSymbolicLinksSync()}/Library';
    tauri = '$library/Application Support/com.mattssoftware.glyph';
    own = '$library/Application Support/com.mattssoftware.glyph.v2';
    Directory(own).createSync(recursive: true);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  ({TauriCarry carry, MapPrefs prefs, MemorySecureStore secure, FakeMac mac}) make({FakeMac? mac, MapPrefs? prefs, MemorySecureStore? secure}) {
    final kept = prefs ?? MapPrefs(), secrets = secure ?? MemorySecureStore(), device = mac ?? FakeMac(master: master);
    return (carry: macCarry(ownDataDir: own, prefs: kept, secure: secrets, device: device, now: () => DateTime.utc(2026, 10, 12, 12)), prefs: kept, secure: secrets, mac: device);
  }

  String log() => File('$own/carry/tauri-carry.log').readAsStringSync();
  Map marker() => jsonDecode(File('$own/carry/tauri-carry.json').readAsStringSync()) as Map;
  String read(String path) => File('$own/$path').readAsStringSync();

  /// Everything of the Tauri app's: its folder and its web view's storage.
  Map<String, String> theirs() => {...treeState(Directory(tauri)), ...treeState(Directory('$library/WebKit'))};

  group('on a Mac the Tauri app was on', skip: webKitSkip ?? coreSkip, () {
    test('the library, the settings and a signed-in person with their keys are all this app\'s, and nothing of the Tauri app\'s is touched', () async {
      makeMac(local: pageKept(notification: await sealed('notification:n2')));
      final before = theirs();
      final made = make();

      // The files first: the library as it was, each file with the time it was last written.
      final files = await made.carry.copied();
      expect(files.done, isTrue);
      expect(files.failed, isEmpty);
      expect(read('Library/Inbox/First note.md'), '---\nid: a\n---\nfirst');
      expect(read('Library/workspaces/Harbour/Second.md'), '---\nid: b\n---\nsecond');
      expect(read('Library/workspaces/Harbour/Second.versions'), 'versions of b');
      expect(read('Library/.glyph/library.json'), '{"version":1}');
      expect(read('Library/.glyph/notes/a.json'), '{"recordingMs":16000}');
      expect(read('images/p1.jpg'), 'a picture');
      expect(read('recordings/r1.wav'), 'a tape');
      expect(read('video/v1.mp4'), 'a film');
      expect(File('$own/Library/Inbox/First note.md').lastModifiedSync().toUtc(), written);
      expect(Directory('$own/Library/orgs').existsSync(), isTrue, reason: 'a folder with nothing in it yet is still a folder of the library');
      // What is not carried: the index, the Finder's and the Rust's scraps, a link out of the folder, the pages,
      // the jobs, and the two files of secrets (which go to the Keychain, not to a second file).
      for (final left in ['Library/.glyph/index.sqlite', 'Library/.glyph/index.sqlite-wal', 'Library/.DS_Store', 'Library/Inbox/.0123456789abcdef0123456789abcdef.tmp', 'Library/Inbox/elsewhere', 'ota', 'jobs', 'index', 'slack.json', 'notion.json', 'models/Qwen.gguf.part']) {
        expect(FileSystemEntity.typeSync('$own/$left', followLinks: false), FileSystemEntityType.notFound, reason: left);
      }
      expect((marker()['files'] as Map)['counts'], {'notes': 2, 'versions files': 1, 'sidecars': 2, 'index files left': 2, 'links left': 1, 'pictures': 1, 'recordings': 1, 'films': 1, 'models left to download': 1});

      // Then the settings: every key of the page's but the two secrets, text for text.
      final settings = await made.carry.settings();
      expect(settings.done, isTrue);
      final expected = pageKept(notification: jsonDecode(made.prefs.kept['glyph-sync-4242-notifications']!)['items']['n2']['blob'] as String)
        ..remove('glyph-account-session')
        ..remove('glyph-github-token')
        ..remove('someone-elses');
      expect(made.prefs.kept, expected);
      expect(made.prefs.reloads, 1);
      final doc = await FileDocs.forAccount(own, 4242).read('note_mac_team_1');
      expect(doc!.state, [1, 2, 3, 250, 251, 252]);
      expect(doc.seq, 7);
      expect(doc.snapshotSeq, 5);
      expect(doc.pending, [
        [9, 8, 7],
        [6],
      ]);

      // Then the secrets, each key proven.
      final secrets = await made.carry.secrets(core.invoke);
      expect(secrets.done, isTrue);
      expect(secrets.failed, isEmpty);
      expect(made.secure.held.keys.toSet(), {'glyph-account-session', 'glyph-github-token', 'glyph-slack-webhook:c0ffee-1', 'glyph-notion-account', 'account', 'device', 'encryption'});
      expect(made.secure.held['account'], toBase64Url(accountRaw));
      expect(made.secure.held['device'], toBase64Url(edSeed));
      expect(made.secure.held['encryption'], toBase64Url(pairScalar));
      expect(made.mac.asked, 1, reason: 'the Keychain is asked once for both halves');
      final crypto = CoreCrypto(core.invoke);
      final keys = DeviceKeyStore(crypto: crypto, store: made.secure);
      expect((await keys.session())!.handle, 'cutover');
      expect(await crypto.encryptionPublicKeyOf((await keys.encryptionKey())!), toBase64Url(pairPoint));
      expect(await keys.accountKey(), isNotNull);
      expect(await keys.deviceKey(), isNotNull);

      expect(log(), contains('read copies of WebKit’s files: 7 keys of localStorage, 1 team documents, 5 wrapped keys'));
      expect(log(), contains('WebKit’s key opened 3 of 3 stored keys (account, device, encryption)'));
      expect(log(), contains('the account key opened what the page sealed'));
      expect(log(), contains('the device key answers its public key'));
      expect(log(), contains('the encryption key answers its public key'));
      // Nothing secret, and no note's name, in the log or the marker.
      for (final secret in ['mac-carry-token-not-real', 'ghp_mac_carry_not_real', toBase64Url(accountRaw), toBase64Url(pairScalar), toBase64Url(edSeed), 'secret_x', 'hooks.slack.com', 'First note', 'Second', base64.encode(master)]) {
        expect(log(), isNot(contains(secret)));
        expect(File('$own/carry/tauri-carry.json').readAsStringSync(), isNot(contains(secret)));
      }
      // The way back: not a byte, a name or a time of the Tauri app's changed, and nothing added beside them.
      expect(theirs(), before);
      expect(Directory(library).listSync().map((each) => each.path.split('/').last).toSet(), {'Application Support', 'WebKit'});
      expect(Directory('$library/Application Support').listSync().map((each) => each.path.split('/').last).toSet(), {'com.mattssoftware.glyph', 'com.mattssoftware.glyph.v2'});
    });

    test('it runs once: the next launch copies nothing, asks no Keychain and changes nothing', () async {
      makeMac();
      final first = make();
      await first.carry.secrets(core.invoke);
      expect((marker()['secrets'] as Map)['found'], isTrue);
      // The person goes on in this app: a note rewritten, another thrown away, a setting changed.
      File('$own/Library/Inbox/First note.md').writeAsStringSync('rewritten here');
      File('$own/Library/workspaces/Harbour/Second.md').deleteSync();
      first.prefs.kept['glyph-preferences'] = '{"theme":"dusk"}';
      final again = make(prefs: first.prefs, secure: first.secure, mac: FakeMac());
      expect((await again.carry.copied()).ran, isFalse);
      expect((await again.carry.settings()).ran, isFalse);
      expect((await again.carry.secrets(core.invoke)).ran, isFalse);
      expect(again.mac.asked, 0);
      expect(read('Library/Inbox/First note.md'), 'rewritten here');
      expect(File('$own/Library/workspaces/Harbour/Second.md').existsSync(), isFalse, reason: 'a note thrown away here does not come back');
      expect(first.prefs.kept['glyph-preferences'], '{"theme":"dusk"}');
    });

    test('a file already here is never written over', () async {
      makeMac();
      File('$own/Library/Inbox/First note.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('this app\'s own');
      final made = make();
      expect((await made.carry.copied()).done, isTrue);
      expect(read('Library/Inbox/First note.md'), 'this app\'s own');
      expect(read('Library/workspaces/Harbour/Second.md'), '---\nid: b\n---\nsecond');
      expect(((marker()['files'] as Map)['counts'] as Map)['notes already here'], 1);
    });

    test('cut short, nothing of the settings or the session is carried over half a library; run again, it is whole', () async {
      makeMac();
      // A note that cannot be read today.
      Process.runSync('chmod', ['000', '$tauri/Library/workspaces/Harbour/Second.md']);
      addTearDown(() => Process.runSync('chmod', ['644', '$tauri/Library/workspaces/Harbour/Second.md']));
      final first = make();
      final cut = await first.carry.copied();
      expect(cut.done, isFalse);
      expect(File('$own/carry/tauri-carry.json').existsSync(), isFalse);
      expect((await first.carry.settings()).failed, ['files']);
      expect((await first.carry.secrets(core.invoke)).done, isFalse);
      expect(first.prefs.kept, isEmpty, reason: 'the sync\'s cursors over half a library would read the missing note as deleted');
      expect(first.secure.held, isEmpty);
      expect(first.mac.asked, 0);
      expect(read('Library/Inbox/First note.md'), isNotEmpty, reason: 'what could be copied was');
      expect(log(), contains('1 could not be copied'));
      expect(Directory('$own/Library').listSync(recursive: true).where((each) => each.path.endsWith('.carry-part')), isEmpty);

      Process.runSync('chmod', ['644', '$tauri/Library/workspaces/Harbour/Second.md']);
      final again = make(prefs: first.prefs, secure: first.secure);
      expect((await again.carry.secrets(core.invoke)).done, isTrue);
      expect(read('Library/workspaces/Harbour/Second.md'), '---\nid: b\n---\nsecond');
      expect(again.prefs.kept['glyph-sync-4242-notes'], '{"cursor":9,"notes":{}}');
      expect(again.secure.held.containsKey('glyph-account-session'), isTrue);
    });

    test('a Keychain that will not hand over WebKit\'s key: signed in, the keys left, and the password asked once', () async {
      makeMac();
      final made = make(mac: FakeMac());
      final secrets = await made.carry.secrets(core.invoke);
      expect(secrets.done, isTrue);
      expect(made.secure.held.keys.toSet(), {'glyph-account-session', 'glyph-github-token', 'glyph-slack-webhook:c0ffee-1', 'glyph-notion-account'});
      expect(log(), contains('the Keychain did not give WebKit’s key for stored keys: 5 keys left wrapped'));
      expect(log(), contains('signed in, but the account key could not be read: the password is asked once'));
    });

    test('a master key that is not the one the keys were wrapped under opens none of them', () async {
      makeMac(wrapUnder: randomBytes(16));
      final made = make();
      await made.carry.secrets(core.invoke);
      expect(made.secure.held.containsKey('account'), isFalse);
      expect(made.secure.held.containsKey('encryption'), isFalse);
      expect(made.secure.held.containsKey('device'), isFalse);
      expect(log(), contains('WebKit’s key opened 0 of 3 stored keys'));
    });

    test('an account key that does not open what the page sealed is not carried', () async {
      // The page's notification was sealed under another key than the one in its key store.
      makeMac(local: pageKept(notification: await sealed('notification:n2', raw: fromBase64Url('KT5Ybr-WVWEyVYV-XkgGX4wkDq46Aj2oSEnVDaDHQME'))));
      final made = make();
      expect((await made.carry.secrets(core.invoke)).done, isTrue);
      expect(made.secure.held.containsKey('account'), isFalse);
      expect(made.secure.held.containsKey('encryption'), isTrue, reason: 'the pair proves itself by its own public key');
      expect(made.secure.held.containsKey('glyph-account-session'), isTrue);
      expect(log(), contains('did not open what the page sealed: not carried'));
      expect(log(), contains('the password is asked once'));
    });

    test('with nothing the page sealed to try it on, the account key is carried on WebKit\'s own tag', () async {
      makeMac();
      final made = make();
      await made.carry.secrets(core.invoke);
      expect(made.secure.held['account'], toBase64Url(accountRaw));
      expect(log(), contains('opened under WebKit’s own key with its tag'));
    });

    test('models are cloned where the disk can, and never copied byte for byte', () async {
      makeMac();
      final made = make(mac: FakeMac(master: master, clones: true));
      expect((await made.carry.copied()).done, isTrue);
      expect(read('models/ggml-base.en-q5_1.bin'), 'a model');
      expect(File('$own/models/Qwen.gguf.part').existsSync(), isFalse);
      expect(((marker()['files'] as Map)['counts'] as Map)['models'], 1);
      expect(made.mac.cloned.every((path) => path.startsWith('$own/')), isTrue);
    });

    test('a library folder the person chose is opened where it is', () async {
      makeMac();
      put('library-root.json', '{"kind":"folder","path":"/Users/somebody/Notes"}');
      final made = make();
      expect((await made.carry.copied()).done, isTrue);
      expect(read('library-root.json'), '{"kind":"folder","path":"/Users/somebody/Notes"}');
      expect(log(), contains('the library is a folder the person chose'));
    });

    test('a signed-out Tauri app: its library and settings, and no session', () async {
      makeMac(local: {'glyph-preferences': '{"theme":"dawn"}'}, keys: false);
      final made = make();
      expect((await made.carry.secrets(core.invoke)).done, isTrue);
      expect(made.prefs.kept, {'glyph-preferences': '{"theme":"dawn"}'});
      expect(made.secure.held.keys.toSet(), {'glyph-slack-webhook:c0ffee-1', 'glyph-notion-account'});
      expect(made.mac.asked, 0, reason: 'with no stored key there is nothing to ask the Keychain for');
      expect(read('Library/Inbox/First note.md'), isNotEmpty);
    });
  });

  test('a Mac the Tauri app was never on carries nothing, asks nothing and marks itself done', () async {
    final made = make(mac: FakeMac());
    final files = await made.carry.copied();
    expect(files.ran, isFalse);
    expect(files.done, isTrue);
    expect((await made.carry.settings()).ran, isFalse);
    expect((await made.carry.secrets((command, [args = const {}]) => fail('asked the core'))).ran, isFalse);
    expect(made.prefs.kept, isEmpty);
    expect(made.secure.held, isEmpty);
    expect(made.mac.asked, 0);
    expect(marker()['files'], {'at': '2026-10-12T12:00:00.000Z', 'found': false});
    expect(marker()['settings'], {'at': '2026-10-12T12:00:00.000Z', 'found': false});
    expect(Directory(own).listSync().map((each) => each.path.split('/').last), ['carry']);
    expect(Directory(tauri).existsSync(), isFalse, reason: 'looking for the Tauri app\'s folder does not make one');
  });

  group('this app\'s folder is never the Tauri app\'s', () {
    test('the carry will not be made over the Tauri app\'s folder or a place inside it', () {
      for (final folder in [tauri, '$tauri/Flutter', '$tauri/../com.mattssoftware.glyph']) {
        expect(() => macCarry(ownDataDir: folder, prefs: MapPrefs(), secure: MemorySecureStore(), device: FakeMac()), throwsStateError, reason: folder);
        expect(() => MacCarryFiles(from: tauri, to: folder), throwsStateError, reason: folder);
      }
    });

    test('the folder of the build that replaces the Tauri app is a name of its own, in Swift and in Dart', () {
      final swift = File('macos/Runner/GhostChannels.swift').readAsStringSync();
      expect(swift, contains('static let cutoverFolder = "com.mattssoftware.glyph.v2"'));
      expect(swift, contains('static func folderName(id: String) -> String { id == realApp ? cutoverFolder : id }'));
      expect(swift, contains('guard !id.isEmpty, id != realApp, !id.contains("/"), !id.contains("..") else { return nil }'), reason: 'no build is ever given the Tauri app\'s folder');
      expect(isRealAppPath(own), isFalse);
      expect(isRealAppPath(tauri), isTrue);
      expect(DevicePaths.own(dataDir: own, cacheDir: '$library/Caches/com.mattssoftware.glyph.v2').dataDir, own);
      expect(() => DevicePaths.own(dataDir: tauri, cacheDir: '$library/Caches/com.mattssoftware.glyph.v2'), throwsStateError);
    });

    test('where the Tauri app\'s things are looked for: beside this app\'s folder, or under a stand-in for ~/Library', () {
      final beside = MacPlaces.beside(own);
      expect(beside.tauriData, tauri);
      expect(beside.websiteData, '$library/WebKit/com.mattssoftware.glyph/WebsiteData');
      final stand = MacPlaces.beside(own, standIn: '/tmp/copy/Library');
      expect(stand.tauriData, '/tmp/copy/Library/Application Support/com.mattssoftware.glyph');
      expect(stand.websiteData, '/tmp/copy/Library/WebKit/com.mattssoftware.glyph/WebsiteData');
      expect(MacPlaces.beside(own, standIn: '').tauriData, tauri);
    });

    test('the Mac\'s half answers on the channel and with the names this file asks, and only reads the Keychain', () {
      final swift = File('macos/Runner/GhostChannels.swift').readAsStringSync();
      expect(swift, contains('listen("${ChannelMacCarryDevice.channel.name}"'));
      expect(swift, allOf(contains('case "masterKey":'), contains('case "clone":'), contains('"from"'), contains('"to"')));
      expect(swift, contains('guard Bundle.main.bundleIdentifier == realApp else { return nil }'), reason: 'only the build that replaces the Tauri app asks for that app\'s key');
      expect(swift, contains('SecKeychainSetUserInteractionAllowed(false)'), reason: 'the person is never asked');
      final carry = swift.substring(swift.indexOf('MARK: the carry from the Tauri app'), swift.indexOf('This app\'s folder under `base`'));
      expect(carry, isNot(anyOf(contains('SecItemAdd'), contains('SecItemUpdate'), contains('SecItemDelete'), contains('removeItem'), contains('moveItem'))));
      final config = File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
      expect(config, allOf(contains('GHOST_APP_ID_ = com.mattssoftware.glyph.flutter'), contains('GHOST_APP_ID_1 = com.mattssoftware.glyph\n'), contains(r'PRODUCT_BUNDLE_IDENTIFIER = $(GHOST_APP_ID_$(GHOST_CUTOVER))')));
    });
  });

  test('what the page sealed under its account key is found in its notifications', () {
    final probes = accountProbesIn({
      'glyph-sync-7-notifications': jsonEncode({
        'items': {
          'a': {'id': 'a', 'blob': 'AAAA'},
          'b': {'id': 'b'},
          'c': {'id': 'c', 'blob': ''},
        },
      }),
      'glyph-sync-7-notes': '{"items":{"x":{"id":"x","blob":"BBBB"}}}',
      'glyph-sync-8-notifications': 'not json',
    });
    expect(probes, [(context: 'notification:a', blob: 'AAAA')]);
  });

  test('a phone\'s carry is over the same ground as before the Mac\'s: its own folder, and a web view asked', () async {
    // No fixture of a phone's storage is needed for this much: an empty web view folder, and a page that answers.
    final data = Directory('${temp.path}/phone')..createSync();
    Directory('${data.path}/app_webview/Default/Local Storage/leveldb').createSync(recursive: true);
    File('${data.path}/slack.json').writeAsStringSync('{"channels":{"c0ffee-1":"https://hooks.slack.com/services/T000/B000/x"}}');
    final device = FakeDevice((context) => jsonEncode({
          'v': 1,
          'local': {'glyph-preferences': '{"theme":"dawn"}', 'glyph-account-session': '{"token":"t","handle":"phone","accountId":5}', 'other': 'x'},
          'databases': ['glyph-team'],
          'keys': {},
          'team': [
            {'id': 'note_1', 'state': 'AQID', 'seq': 1, 'snapshotSeq': 1, 'pending': []},
          ],
        }));
    final prefs = MapPrefs(), secure = MemorySecureStore();
    final carry = TauriCarry(dataDir: data.path, prefs: prefs, secure: secure, device: device, now: () => DateTime.utc(2026, 10, 12, 12));
    expect(carry.source, isA<PhoneCarrySource>());
    expect(carry.files, isNull);
    final files = await carry.copied();
    expect(files.ran, isFalse);
    expect(files.done, isTrue);
    expect(File('${data.path}/carry/tauri-carry.json').existsSync(), isFalse, reason: 'a phone has no files\' half to mark');
    expect((await carry.settings()).done, isTrue);
    expect(prefs.kept, {'glyph-preferences': '{"theme":"dawn"}'});
    expect(File('${data.path}/team/5/note_1.json').existsSync(), isTrue);
    expect((await carry.secrets((command, [args = const {}]) => fail('no key to raise'))).done, isTrue);
    expect(secure.held.keys.toSet(), {'glyph-account-session', 'glyph-slack-webhook:c0ffee-1'});
    expect(device.reads, 1);
    expect(device.forgot, carryStaleWork);
    final marked = jsonDecode(File('${data.path}/carry/tauri-carry.json').readAsStringSync()) as Map;
    expect(marked.keys.toSet(), {'v', 'settings', 'secrets'});
    expect(marked['settings'], containsPair('source', 'webview'));
    expect(File('${data.path}/carry/tauri-carry.log').readAsStringSync(), contains('read the web view at http://tauri.localhost: 3 keys of localStorage (0 in its files), databases [glyph-team]'));
  });
}
