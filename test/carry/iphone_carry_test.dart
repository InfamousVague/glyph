// The carry from the Tauri app on an iPhone (lib/carry/iphone_carry.dart; docs/CUTOVER.md, section 8): a made-up
// app container laid out as the Tauri iPhone app's was seen to be in a simulator (its folder under Application
// Support, its web view's storage under WebKit, an empty Preferences and an empty Documents), this app's own
// folder beside the Tauri app's, and the Rust core's real crypto raising the keys. Nothing here is anybody's: the
// notes, the keys and the session are made in this file.
//
// The carry itself is the Mac's (test/carry/mac_carry_test.dart holds every corner of it); what is held here is
// that an iPhone's container is ground it stands on, and that the iPhone's build is the one it was asked to be.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/carry/iphone_carry.dart';
import 'package:ghost_md/carry/mac_carry.dart';
import 'package:ghost_md/carry/sqlite_read.dart';
import 'package:ghost_md/carry/tauri_carry.dart';
import 'package:ghost_md/core/mac_app.dart';
import 'package:ghost_md/core/native/device_paths.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/team/docs.dart';

import '../team_sync/support.dart' show coreBuilt, coreSkip, openCore;
import 'mac_carry_test.dart' show FakeMac;
import 'tauri_carry_test.dart' show MapPrefs;
import 'webkit_make.dart';
import 'webkit_stores_test.dart' show accountRaw, edPublic, edSeed, pairPoint, pairScalar;

void main() {
  late GhostCore core;
  late Directory temp;
  late String container, library, tauri, own;
  final master = randomBytes(16);
  final written = DateTime.utc(2026, 10, 2, 9, 15);

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

  Future<String> sealed(String context) async {
    final key = ((await core.invoke('key_restore', {'kind': 'account', 'raw': toBase64Url(accountRaw)})) as Map)['key'];
    return await core.invoke('seal', {'key': key, 'context': context, 'text': jsonEncode({'words': 'made up'})}) as String;
  }

  Map<String, String> pageKept({String? notification}) => {
        'glyph-preferences': '{"theme":"boreal","workspaces":{"list":[{"id":"w1","name":"Proof space"}]}}',
        'glyph-workspace-current': '"w1"',
        'glyph-account-session': '{"token":"iphone-carry-token-not-real","handle":"cutover","accountId":1}',
        'glyph-sync-1-notes': '{"cursor":12,"notes":{}}',
        'glyph-sync-1-notifications': jsonEncode({
          'cursor': 1,
          'items': {
            if (notification != null) 'c1': {'id': 'c1', 'rev': 1, 'kind': 'sync-conflict', 'blob': notification},
          },
        }),
        'glyph-guide-seen': 'true',
      };

  /// An iPhone's container as the Tauri app leaves it (seen in a simulator, 2026-10-13).
  void makeIPhone({Map<String, String>? local}) {
    put('Library/Inbox/Typed on the phone.md', '---\nid: a\n---\nfirst');
    put('Library/Inbox/With a picture.md', '---\nid: b\n---\n![](image/p1.jpg)');
    put('Library/Inbox/With a picture.versions', 'versions of b');
    put('Library/orgs/Proof team/Team note.md', '---\nid: note_team_1\n---\nthe team\'s');
    put('Library/.glyph/library.json', '{"version":1}');
    put('Library/.glyph/notes/b.json', '{"places":[]}');
    put('Library/.glyph/index.sqlite', 'an index');
    put('Library/.glyph/index.sqlite-wal', 'its log');
    put('Library/.glyph/index.sqlite-shm', 'its map');
    put('images/p1.jpg', 'a picture');
    put('ota/installed.json', '{}');
    for (final empty in ['Documents', 'Library/Preferences', 'Library/Caches/com.mattssoftware.glyph/WebKit', 'tmp']) {
      Directory('$container/$empty').createSync(recursive: true);
    }
    makeWebKit(Directory('$library/WebKit/com.mattssoftware.glyph/WebsiteData'), local: local ?? pageKept(), databases: [
      accountDatabase(master, account: accountRaw, encryption: (scalar: pairScalar, point: pairPoint), device: (seed: edSeed, public: edPublic)),
      teamDatabase({
        'note_team_1': (state: [4, 5, 6], seq: 2, snapshotSeq: 1, pending: [
          [7],
        ]),
      }),
    ]);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('iphonecarry').absolute;
    // The shape of a container's path on a phone: no folder in it is named for the app.
    container = '${temp.resolveSymbolicLinksSync()}/Containers/Data/Application/26DDD5F6-0592-45EF-ACA1-1CC7A16B9FC4';
    library = '$container/Library';
    tauri = '$library/Application Support/com.mattssoftware.glyph';
    own = '$library/Application Support/com.mattssoftware.glyph.v2';
    Directory(own).createSync(recursive: true);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  ({TauriCarry carry, MapPrefs prefs, MemorySecureStore secure, FakeMac phone}) make({FakeMac? phone}) {
    final kept = MapPrefs(), secrets = MemorySecureStore(), device = phone ?? FakeMac(master: master, clones: true);
    return (carry: iPhoneCarry(ownDataDir: own, prefs: kept, secure: secrets, device: device, now: () => DateTime.utc(2026, 10, 13, 12)), prefs: kept, secure: secrets, phone: device);
  }

  String log() => File('$own/carry/tauri-carry.log').readAsStringSync();
  Map marker() => jsonDecode(File('$own/carry/tauri-carry.json').readAsStringSync()) as Map;
  String read(String path) => File('$own/$path').readAsStringSync();
  Map<String, String> theirs() => {...treeState(Directory(tauri)), ...treeState(Directory('$library/WebKit'))};

  group('in a container the Tauri iPhone app was in', skip: webKitSkip ?? coreSkip, () {
    test('the notes, the picture, the settings and a signed-in person with their keys are all this app\'s, and nothing of the Tauri app\'s is touched', () async {
      makeIPhone(local: pageKept(notification: await sealed('notification:c1')));
      final before = theirs();
      final made = make();

      final files = await made.carry.copied();
      expect(files.done, isTrue);
      expect(read('Library/Inbox/Typed on the phone.md'), '---\nid: a\n---\nfirst');
      expect(read('Library/Inbox/With a picture.versions'), 'versions of b');
      expect(read('Library/orgs/Proof team/Team note.md'), contains('the team\'s'));
      expect(read('Library/.glyph/notes/b.json'), '{"places":[]}');
      expect(read('images/p1.jpg'), 'a picture');
      expect(File('$own/Library/Inbox/Typed on the phone.md').lastModifiedSync().toUtc(), written);
      for (final left in ['Library/.glyph/index.sqlite', 'Library/.glyph/index.sqlite-wal', 'Library/.glyph/index.sqlite-shm', 'ota', 'recordings', 'video', 'models']) {
        expect(FileSystemEntity.typeSync('$own/$left', followLinks: false), FileSystemEntityType.notFound, reason: left);
      }
      expect((marker()['files'] as Map)['counts'], {'notes': 3, 'versions files': 1, 'sidecars': 2, 'index files left': 3, 'pictures': 1});
      expect(made.phone.cloned, hasLength(7), reason: 'every file is a clone on a phone\'s disk: a library takes no second helping of it');

      final settings = await made.carry.settings();
      expect(settings.done, isTrue);
      expect(made.prefs.kept.keys.toSet(), {'glyph-preferences', 'glyph-workspace-current', 'glyph-sync-1-notes', 'glyph-sync-1-notifications', 'glyph-guide-seen'});
      expect(made.prefs.kept['glyph-preferences'], pageKept()['glyph-preferences']);
      final doc = await FileDocs.forAccount(own, 1).read('note_team_1');
      expect(doc!.state, [4, 5, 6]);
      expect(doc.pending, [
        [7],
      ]);

      final secrets = await made.carry.secrets(core.invoke);
      expect(secrets.done, isTrue);
      expect(secrets.failed, isEmpty);
      expect(made.secure.held.keys.toSet(), {'glyph-account-session', 'account', 'device', 'encryption'});
      expect(made.secure.held['account'], toBase64Url(accountRaw));
      expect(made.phone.asked, 1);
      final crypto = CoreCrypto(core.invoke);
      final keys = DeviceKeyStore(crypto: crypto, store: made.secure);
      expect((await keys.session())!.handle, 'cutover');
      expect(await crypto.encryptionPublicKeyOf((await keys.encryptionKey())!), toBase64Url(pairPoint));
      expect(await keys.accountKey(), isNotNull);
      expect(await keys.deviceKey(), isNotNull);

      // The lines a first launch on a phone is read for (docs/CUTOVER.md §8).
      expect(log(), contains('files: 3 notes'));
      expect(log(), contains('read copies of WebKit’s files: 6 keys of localStorage, 1 team documents, 5 wrapped keys'));
      expect(log(), contains('WebKit’s key opened 3 of 3 stored keys (account, device, encryption)'));
      expect(log(), contains('the account key opened what the page sealed'));
      expect(log(), contains('the device key answers its public key'));
      expect(log(), contains('the encryption key answers its public key'));
      for (final secret in ['iphone-carry-token-not-real', toBase64Url(accountRaw), toBase64Url(pairScalar), toBase64Url(edSeed), 'Typed on the phone', 'With a picture', base64.encode(master)]) {
        expect(log(), isNot(contains(secret)));
        expect(File('$own/carry/tauri-carry.json').readAsStringSync(), isNot(contains(secret)));
      }

      // Not a byte, a name or a time of the Tauri app's changed, nothing was put in the two folders it left
      // empty, and the only new thing in the container is this app's own folder.
      expect(theirs(), before);
      expect(Directory('$container/Documents').listSync(), isEmpty, reason: 'nothing of a person\'s is put where Files could show it');
      expect(Directory('$library/Preferences').listSync(), isEmpty, reason: 'the carry itself writes no preferences file: the app\'s store does, under its own keys');
      expect(Directory('$library/Application Support').listSync().map((each) => each.path.split('/').last).toSet(), {'com.mattssoftware.glyph', 'com.mattssoftware.glyph.v2'});
      expect(Directory(library).listSync().map((each) => each.path.split('/').last).toSet(), {'Application Support', 'WebKit', 'Preferences', 'Caches'});
    });

    test('it runs once: the next launch copies nothing, asks no Keychain and changes nothing', () async {
      makeIPhone();
      final first = make();
      await first.carry.secrets(core.invoke);
      final after = treeState(Directory(own));
      final second = make();
      expect((await second.carry.copied()).ran, isFalse);
      expect((await second.carry.settings()).ran, isFalse);
      expect((await second.carry.secrets(core.invoke)).ran, isFalse);
      expect(second.phone.asked, 0);
      expect(second.prefs.kept, isEmpty);
      expect(treeState(Directory(own)), after);
    });

    test('a Keychain that will not hand over WebKit\'s key: signed in, the keys left, and the password asked once', () async {
      makeIPhone();
      final made = make(phone: FakeMac(clones: true));
      final secrets = await made.carry.secrets(core.invoke);
      expect(secrets.done, isTrue);
      expect(made.secure.held.keys.toSet(), {'glyph-account-session'});
      expect(log(), contains('the Keychain did not give WebKit’s key for stored keys: 5 keys left wrapped'));
      expect(log(), contains('the password is asked once'));
    });

    test('a disk that will not clone copies byte for byte, and comes to the same library', () async {
      makeIPhone();
      final made = make(phone: FakeMac(master: master));
      expect((await made.carry.copied()).done, isTrue);
      expect(read('images/p1.jpg'), 'a picture');
      expect(made.phone.cloned, isEmpty);
    });
  });

  test('a new install, with no Tauri app ever in the container, carries nothing, asks nothing and marks itself done', () async {
    final made = make(phone: FakeMac());
    expect((await made.carry.copied()).ran, isFalse);
    expect((await made.carry.settings()).ran, isFalse);
    expect((await made.carry.secrets((command, [args = const {}]) => fail('asked the core'))).ran, isFalse);
    expect(made.prefs.kept, isEmpty);
    expect(made.secure.held, isEmpty);
    expect(made.phone.asked, 0);
    expect(marker()['files'], {'at': '2026-10-13T12:00:00.000Z', 'found': false});
    expect(Directory(own).listSync().map((each) => each.path.split('/').last), ['carry']);
    expect(Directory(tauri).existsSync(), isFalse);
  });

  group('this app\'s folder is never the Tauri app\'s', () {
    test('the carry will not be made over the Tauri app\'s folder or a place inside it', () {
      for (final folder in [tauri, '$tauri/v2', '$own/../com.mattssoftware.glyph']) {
        expect(() => iPhoneCarry(ownDataDir: folder, prefs: MapPrefs(), secure: MemorySecureStore(), device: FakeMac()), throwsStateError, reason: folder);
      }
    });

    test('a container\'s own path is no reason to refuse, and the Tauri app\'s folder in it always is', () {
      expect(isRealAppPath(own), isFalse);
      expect(isRealAppPath('$library/Caches/com.mattssoftware.glyph.v2'), isFalse);
      expect(isRealAppPath(tauri), isTrue);
      expect(isRealAppPath('$library/WebKit/com.mattssoftware.glyph/WebsiteData'), isTrue);
      expect(DevicePaths.own(dataDir: own, cacheDir: '$library/Caches/com.mattssoftware.glyph.v2').dataDir, own);
      expect(() => DevicePaths.own(dataDir: tauri, cacheDir: '$library/Caches/com.mattssoftware.glyph'), throwsStateError);
      final beside = MacPlaces.beside(own);
      expect(beside.tauriData, tauri);
      expect(beside.websiteData, '$library/WebKit/com.mattssoftware.glyph/WebsiteData');
    });

    test('the folder of the build that replaces the Tauri app is a name of its own, in the iPhone\'s Swift as in the Mac\'s', () {
      final swift = File('ios/Runner/GhostChannels.swift').readAsStringSync();
      expect(swift, contains('static let realApp = "com.mattssoftware.glyph"'));
      expect(swift, contains('static let cutoverFolder = "com.mattssoftware.glyph.v2"'));
      expect(swift, contains('static func folderName(id: String) -> String { id == realApp ? cutoverFolder : id }'));
      expect(swift, contains('guard !id.isEmpty, id != realApp, !id.contains("/"), !id.contains("..") else { return nil }'), reason: 'no build is ever given the Tauri app\'s folder');
      final mac = File('macos/Runner/GhostChannels.swift').readAsStringSync();
      String rule(String source) => source.substring(source.indexOf('static func ownDirectory(in base: URL, id: String) -> URL? {'), source.indexOf('return own\n', source.indexOf('static func ownDirectory(in base: URL, id: String) -> URL? {')));
      expect(rule(swift), rule(mac), reason: 'one rule, word for word, on both');
    });

    test('the iPhone\'s half answers on the channel and with the names the carry asks, and only reads the Keychain', () {
      final swift = File('ios/Runner/GhostChannels.swift').readAsStringSync();
      expect(swift, contains('listen("${ChannelMacCarryDevice.channel.name}"'));
      expect(swift, allOf(contains('case "masterKey":'), contains('case "clone":'), contains('"from"'), contains('"to"')));
      expect(swift, contains('guard Bundle.main.bundleIdentifier == realApp else { return nil }'), reason: 'only the build that replaces the Tauri app asks for that app\'s key');
      expect(swift, contains(r'kSecAttrAccount: "com.apple.WebKit.WebCrypto.master+\(realApp)"'));
      final carry = swift.substring(swift.indexOf('MARK: the carry from the Tauri app'), swift.indexOf('MARK: pictures'));
      expect(carry, isNot(anyOf(contains('SecItemAdd'), contains('SecItemUpdate'), contains('SecItemDelete'), contains('removeItem'), contains('moveItem'), contains('copyItem'))));
      expect(carry, contains('guard target.hasPrefix(dirs.data.standardizedFileURL.path + "/") else { return false }'), reason: 'a clone is only ever made into this app\'s own folder');
    });
  });

  group('which app an iPhone build is', () {
    final config = File('ios/Flutter/AppInfo.xcconfig').readAsStringSync();
    final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    test('told nothing it is Ghost Flutter beside the real app; only GHOST_CUTOVER=1 makes it Ghost.md under the real id', () {
      expect(config, allOf(contains('GHOST_APP_ID_ = com.mattssoftware.glyph.flutter\n'), contains('GHOST_APP_ID_0 = com.mattssoftware.glyph.flutter\n'), contains('GHOST_APP_ID_1 = com.mattssoftware.glyph\n')));
      expect(config, allOf(contains('GHOST_APP_NAME_ = Ghost Flutter\n'), contains('GHOST_APP_NAME_0 = Ghost Flutter\n'), contains('GHOST_APP_NAME_1 = Ghost.md\n')));
      expect(config, allOf(contains(r'GHOST_APP_ID = $(GHOST_APP_ID_$(GHOST_CUTOVER))'), contains(r'GHOST_APP_NAME = $(GHOST_APP_NAME_$(GHOST_CUTOVER))')));
      for (final file in ['ios/Flutter/Debug.xcconfig', 'ios/Flutter/Release.xcconfig']) {
        expect(File(file).readAsStringSync(), contains('#include "AppInfo.xcconfig"'), reason: file);
      }
      expect(RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = "\$\(GHOST_APP_ID\)";').allMatches(project), hasLength(3), reason: 'the Runner in debug, profile and release');
      expect(project, isNot(contains('PRODUCT_BUNDLE_IDENTIFIER = com.mattssoftware.glyph;')));
      expect(RegExp(r'<string>\$\(GHOST_APP_NAME\)</string>').allMatches(plist), hasLength(2), reason: 'the name under the icon and the bundle\'s name');
    });

    test('an iPhone\'s alone, compiled without the load optimiser, with the core\'s names kept', () {
      expect(RegExp(r'TARGETED_DEVICE_FAMILY = 1;').allMatches(project), hasLength(3));
      expect(project, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
      expect(File('ios/Flutter/Release.xcconfig').readAsStringSync(), contains('EXTRA_GEN_SNAPSHOT_OPTIONS=--no-load_cse'));
      expect(RegExp(r'STRIP_STYLE = "non-global";').allMatches(project), hasLength(3));
      expect(project, contains('DEVELOPMENT_TEAM = F6ZAL7ANAD;'));
    });

    test('it asks for what an iPhone build does and no more, and says what it is to the store', () {
      expect(plist, contains('<key>NSCameraUsageDescription</key>'));
      for (final absent in ['NSMicrophoneUsageDescription', 'NSLocationWhenInUseUsageDescription', 'NSSpeechRecognitionUsageDescription', 'NSPhotoLibraryUsageDescription', 'UIBackgroundModes', 'UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace']) {
        expect(plist, isNot(contains('<key>$absent</key>')), reason: absent);
      }
      expect(plist, contains('<string>ghostmd</string>'));
      expect(plist, contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'), reason: 'exempt from documentation: standard algorithms, not sold in France (Matt, 2026-10-13; docs/CUTOVER.md §8, "Export compliance")');
      final privacy = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
      expect(privacy, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
      for (final declared in ['NSPrivacyAccessedAPICategoryFileTimestamp', 'C617.1', 'NSPrivacyAccessedAPICategoryDiskSpace', 'E174.1', 'NSPrivacyAccessedAPICategorySystemBootTime', '35F9.1', 'NSPrivacyAccessedAPICategoryUserDefaults', 'CA92.1', 'NSPrivacyCollectedDataTypeUserID', 'NSPrivacyCollectedDataTypeOtherUserContent', 'NSPrivacyCollectedDataTypePhotosorVideos']) {
        expect(privacy, contains(declared), reason: declared);
      }
      expect(privacy, isNot(anyOf(contains('PreciseLocation'), contains('CoarseLocation'))), reason: 'an iPhone build finds no position');
      expect(project, contains('PrivacyInfo.xcprivacy in Resources'), reason: 'the manifest is copied into the app');
    });

    test('the build script gives both halves of the switch, a number above the store\'s, and uploads nothing', () {
      final script = File('tool/cutover-build-ios.sh').readAsStringSync();
      expect(script, allOf(contains('GHOST_CUTOVER=1 flutter build ios'), contains('--dart-define=GHOST_CUTOVER=true'), contains('--dart-define=GHOST_VERSION="\$version"'), contains('--dart-define=GHOST_BUILD='), contains('--dart-define=GHOST_COMMIT=')));
      expect(script, contains(r'[ "$code" -gt 1010000 ]'), reason: 'above the Tauri app\'s 1.10.0');
      expect(script, allOf(contains('<string>app-store-connect</string>'), contains('<string>export</string>'), contains('-allowProvisioningUpdates')));
      final commands = script.split('\n').where((line) => !line.trimLeft().startsWith('#')).join('\n');
      for (final never in ['altool', 'notarytool', 'iTMSTransporter', 'Transporter', '<string>upload</string>', 'ASC_KEY_ID"\n', 'echo "\$ASC']) {
        expect(commands, isNot(contains(never)), reason: never);
      }
    });
  });

  test('the system\'s SQLite is asked for where an iPhone has it', () {
    // lib/carry/sqlite_read.dart opens /usr/lib/libsqlite3.dylib on a Mac and on an iPhone alike (in a simulator
    // the same path under the runtime's root): seen to read WebKit's files in the simulator's proof.
    expect(File('lib/carry/sqlite_read.dart').readAsStringSync(), contains("Platform.isMacOS || Platform.isIOS ? '/usr/lib/libsqlite3.dylib'"));
    expect(SqliteRead.rows, isNotNull);
  });
}
