// The app's updates (lib/core/updates.dart): the cases of the web's src/app/core/ota.test.ts and useUpdates.test.tsx
// that are about the APK, which is all a Flutter app has to update; the rule for when a build looks at all; and the
// download and the hand-over, over a made-up server and phone. The last group asks the real core
// (native/target/debug/libghost_core.dylib, tool/build-native.sh host) to read a release signed outside it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ui' show AppLifecycleState;

// flutter_test's own, which it does not hand on.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/update_keys.dart';
import 'package:ghost_md/core/updates.dart';

const _base = 'https://releases.example/flutter';

ApkInfo _info(String version, int code, {List<int> file = const [1, 2, 3, 4, 5, 6], String url = 'ghost-flutter.apk'}) =>
    ApkInfo(version: version, versionCode: code, sha256: 'hash-of-${file.join()}', bytes: file.length, url: url);

Map<String, Object?> _json(ApkInfo info) => {'version': info.version, 'versionCode': info.versionCode, 'sha256': info.sha256, 'bytes': info.bytes, 'url': info.url};

/// A release address that serves what a test puts there, and counts what it was asked.
class _Server implements UpdateTransport {
  ApkInfo? published;
  List<int> file = const [1, 2, 3, 4, 5, 6];
  String signature = 'signed';
  Object? down;
  Object? downloadFails;
  final List<String> asked = [];

  /// Held open while a test looks at the download half way.
  Completer<void>? holding;

  int get looks => asked.where((url) => url.endsWith('/apk.json')).length;

  @override
  Future<Uint8List> read(String url) async {
    asked.add(url);
    if (down != null) throw down!;
    final published = this.published;
    if (published == null) throw UpdateFailure('$url: the server answered 404');
    return Uint8List.fromList(utf8.encode(url.endsWith('.sig') ? signature : jsonEncode(_json(published))));
  }

  @override
  Future<void> download(String url, File to, {required int limit, required void Function(int received) onProgress}) async {
    asked.add(url);
    if (downloadFails != null) throw downloadFails!;
    final half = file.length ~/ 2;
    onProgress(half);
    await holding?.future;
    if (file.length > limit) throw const UpdateFailure('the server sent more than the published APK size');
    to.writeAsBytesSync(file);
    onProgress(file.length);
  }
}

/// The core's two commands as kept/updates.rs answers them, with "signed" for a signature that verifies and a
/// file's hash as [_info] writes one.
CoreInvoke _core(List<String> asked) => (String command, [Map<String, Object?> args = const {}]) async {
      asked.add(command);
      switch (command) {
        case 'update_read':
          if (args['signature'] != 'signed' || (args['keys'] as List).isEmpty) throw const CoreError('the signature did not verify against any trusted key');
          return jsonDecode(utf8.decode(base64.decode(args['body'] as String)));
        case 'update_verify':
          final bytes = File(args['path'] as String).readAsBytesSync();
          if (bytes.length != args['bytes'] || 'hash-of-${bytes.join()}' != args['sha256']) throw const CoreError('the APK did not match its published checksum');
          return null;
      }
      throw CoreError('unknown command $command');
    };

class _Phone implements UpdatePhone {
  _Phone(this.app);
  InstalledApp? app;
  String answer = 'started';
  final List<String> handed = [];

  @override
  Future<InstalledApp?> installed() async => app;

  @override
  Future<String> install(String path) async {
    handed.add(path);
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final config = UpdatesConfig.of(source: _base, keys: const ['a-key'], debug: false)!;
  late _Server server;
  late _Phone phone;
  late List<String> core;
  late Directory dir;
  var recording = false;
  var localOnly = false;

  setUp(() {
    server = _Server();
    core = [];
    recording = false;
    localOnly = false;
    dir = Directory.systemTemp.createTempSync('ghost-updates-test');
    phone = _Phone(InstalledApp(version: '0.1.0', versionCode: 1, updatesDir: '${dir.path}/updates'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Updates make({DateTime Function()? now}) => Updates(config: config, invoke: _core(core), phone: phone, transport: server, recording: () => recording, localOnly: () => localOnly, now: now);

  group('versions', () {
    test('compares dotted versions numerically', () {
      expect(isNewerVersion('0.10.0', '0.9.9'), isTrue);
      expect(isNewerVersion('0.2.0', '0.2.0'), isFalse);
      expect(isNewerVersion('0.1.9', '0.2.0'), isFalse);
      expect(isNewerVersion('1.0.0', '0.99.0'), isTrue);
      // A build number after the version is not part of it, and nonsense is older than anything.
      expect(isNewerVersion('0.2.0+7', '0.2.0+3'), isFalse);
      expect(isNewerVersion('nope', '0.0.1'), isFalse);
      expect(isNewerVersion('1', '0.9.9'), isTrue);
    });

    test('names an update source by its host', () {
      expect(sourceHost('https://attack.fm/glyph'), 'attack.fm');
      expect(sourceHost(null), isNull);
      expect(sourceHost('not a url'), isNull);
      expect(sourceHost('http://10.0.2.2:8123/flutter'), '10.0.2.2:8123');
    });

    test('describes a build id, and refuses to invent one', () {
      expect(describeBuild('20260912221530', toLocal: (utc) => utc), 'Sep 12, 10:15 PM');
      expect(describeBuild('20260101000500', toLocal: (utc) => utc), 'Jan 1, 12:05 AM');
      expect(describeBuild('20260912221530'), isNot('unknown build'));
      expect(describeBuild('nope'), 'unknown build');
      expect(describeBuild(null), 'unknown build');
    });
  });

  group('whether a build looks at all', () {
    UpdatesConfig? of(String source, {List<String> keys = const ['a-key'], bool debug = false, bool testing = false, String testKey = ''}) =>
        UpdatesConfig.of(source: source, keys: keys, debug: debug, testing: testing, testKey: testKey);

    test('only where it was told an https address of its own, and trusts a key', () {
      expect(of(_base)?.source, _base);
      expect(of('$_base/')?.source, _base, reason: 'a trailing slash is not part of the address');
      expect(of(''), isNull, reason: 'a build not told never looks');
      expect(of(_base, keys: const []), isNull, reason: 'nor one with nobody to believe');
      expect(of('http://releases.example/flutter'), isNull);
      expect(of('releases.example/flutter'), isNull);
      expect(of('https://'), isNull);
      expect(of('https://releases.example/flutter?x=1'), isNull);
    });

    test('never at the real app\'s releases', () {
      expect(of('https://attack.fm/glyph'), isNull);
      expect(of('https://attack.fm/glyph/'), isNull);
      expect(of('https://ghostmarkdown.com/glyph'), isNull);
      expect(of('https://attack.fm/glyph', debug: true, testing: true, testKey: 'k'), isNull);
    });

    test('never in a debug build, but one built for a test run, which may be served over http by a key of its own', () {
      expect(of(_base, debug: true), isNull);
      expect(of(_base, debug: true, testKey: 'a-test-key'), isNull, reason: 'a key alone turns nothing on');
      final test = of('http://10.0.2.2:8123/flutter', keys: const [], debug: true, testing: true, testKey: 'a-test-key');
      expect(test?.source, 'http://10.0.2.2:8123/flutter');
      expect(test?.keys, ['a-test-key']);
      expect(test?.http, isTrue);
    });

    test('a release reads neither of the test run\'s words', () {
      expect(of('http://10.0.2.2:8123/flutter', testing: true, testKey: 'a-test-key'), isNull);
      final release = of(_base, keys: const ['a-key'], testing: true, testKey: 'a-test-key');
      expect(release?.keys, ['a-key']);
      expect(release?.http, isFalse);
    });

    test('and this build, as it stands, does not: no key has been chosen for it', () {
      expect(trustedUpdateKeys, isEmpty);
      expect(UpdatesConfig.fromBuild(), isNull);
      expect(Updates.forBuild(invoke: _core(core)), isNull);
    });
  });

  group('when the app looks for an update', () {
    test('looks four seconds after launch, and not before', () {
      fakeAsync((async) {
        final updates = make()..start();
        async.elapse(const Duration(milliseconds: 3999));
        expect(server.looks, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(server.looks, 1);
        expect(updates.lastChecked, isNotNull);
        updates.dispose();
      });
    });

    test('looks again on a two-minute beat while in front, and not while hidden', () {
      fakeAsync((async) {
        final updates = make(now: () => async.getClock(DateTime(2026)).now())..start();
        async.elapse(const Duration(seconds: 4));
        async.elapse(const Duration(minutes: 2));
        expect(server.looks, 2);
        updates.shown(false);
        async.elapse(const Duration(minutes: 4));
        expect(server.looks, 2);
        updates.dispose();
      });
    });

    test('looks when the app comes back, if it has not looked for a minute', () {
      fakeAsync((async) {
        final updates = make(now: () => async.getClock(DateTime(2026)).now())..start();
        async.elapse(const Duration(seconds: 4));
        expect(server.looks, 1);
        updates.shown(false);
        async.elapse(const Duration(seconds: 59));
        updates.shown(true);
        async.flushMicrotasks();
        expect(server.looks, 1);
        updates.shown(false);
        async.elapse(const Duration(milliseconds: 1001));
        updates.shown(true);
        async.flushMicrotasks();
        expect(server.looks, 2);
        updates.dispose();
      });
    });

    test('follows the app\'s own lifecycle', () {
      fakeAsync((async) {
        final updates = make(now: () => async.getClock(DateTime(2026)).now())..start();
        async.elapse(const Duration(seconds: 4));
        updates.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 5));
        expect(server.looks, 1);
        updates.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(server.looks, 2);
        updates.dispose();
      });
    });

    test('never looks with Nothing leaves the phone on, on a device with no phone half, or once let go', () {
      fakeAsync((async) {
        localOnly = true;
        final quiet = make()..start();
        async.elapse(const Duration(minutes: 10));
        expect(server.asked, isEmpty);
        quiet.dispose();

        localOnly = false;
        phone.app = null;
        final nowhere = make()..start();
        async.elapse(const Duration(minutes: 10));
        expect(server.asked, isEmpty);
        expect(nowhere.checking, isFalse);
        nowhere.dispose();
        async.elapse(const Duration(minutes: 10));
        expect(server.asked, isEmpty);
      });
    });

    test('does not look twice at once', () {
      fakeAsync((async) {
        final updates = make();
        unawaited(updates.check());
        unawaited(updates.check());
        expect(updates.checking, isTrue);
        async.flushMicrotasks();
        expect(server.looks, 1);
        expect(updates.checking, isFalse);
        updates.dispose();
      });
    });
  });

  group('what the app makes of the answer', () {
    test('says it could not look until a check gets through', () async {
      server.down = const UpdateFailure('$_base/apk.json: Connection refused');
      final updates = make();
      await updates.check();
      expect(updates.lastError, '$_base/apk.json: Connection refused');
      expect(updates.apk, isA<ApkPhaseNone>());
      server
        ..down = null
        ..published = _info('0.1.0', 1);
      await updates.check();
      expect(updates.lastError, isNull);
      expect(updates.lastChecked, isNotNull);
    });

    test('offers an APK newer than this one by its version or its version code, and no other', () async {
      final updates = make();
      server.published = _info('0.1.0', 1);
      await updates.check();
      expect(updates.apk, isA<ApkPhaseNone>());
      server.published = _info('0.2.0', 1);
      await updates.check();
      expect((updates.apk as ApkPhaseAvailable).info.version, '0.2.0');
      server.published = _info('0.0.9', 1);
      await updates.check();
      expect(updates.apk, isA<ApkPhaseNone>(), reason: 'an older release takes the offer away');
      server.published = _info('0.1.0', 2);
      await updates.check();
      expect((updates.apk as ApkPhaseAvailable).info.versionCode, 2);
    });

    test('believes nothing a trusted key did not sign, and says so', () async {
      server
        ..published = _info('9.9.9', 99)
        ..signature = 'forged';
      final updates = make();
      await updates.check();
      expect(updates.apk, isA<ApkPhaseNone>());
      expect(updates.lastError, '$_base/apk.json: the signature did not verify against any trusted key');
      expect(server.asked, ['$_base/apk.json', '$_base/apk.json.sig']);
    });

    test('tells whoever listens', () async {
      server.published = _info('0.2.0', 2);
      final updates = make();
      var told = 0;
      updates.addListener(() => told += 1);
      await updates.check();
      expect(told, greaterThanOrEqualTo(2));
      expect(updates.installed?.version, '0.1.0');
      expect(updates.host, 'releases.example');
    });
  });

  group('the APK', () {
    Future<Updates> offered() async {
      server.published = _info('0.2.0', 2);
      final updates = make();
      await updates.check();
      expect(updates.apk, isA<ApkPhaseAvailable>());
      return updates;
    }

    test('nothing is installed when nothing is offered', () async {
      final updates = make();
      await updates.installApk();
      expect(server.asked, isEmpty);
      expect(phone.handed, isEmpty);
    });

    test('is downloaded with its progress shown and handed to the installer, and a check does not interrupt it', () async {
      final updates = await offered();
      server.holding = Completer<void>();
      final seen = <String>[];
      updates.addListener(() {
        final apk = updates.apk;
        final line = apk is ApkPhaseDownloading ? 'downloading ${apk.received}/${apk.total}' : apk.runtimeType.toString();
        if (seen.isEmpty || seen.last != line) seen.add(line);
      });
      final install = updates.installApk();
      await pumpEventQueue();
      expect((updates.apk as ApkPhaseDownloading).received, 3);
      await updates.check();
      expect(updates.apk, isA<ApkPhaseDownloading>(), reason: 'a check leaves a download alone');
      server.holding!.complete();
      await install;
      expect(seen, ['downloading 0/6', 'downloading 3/6', 'downloading 6/6', 'ApkPhaseInstalling']);
      expect(phone.handed, ['${dir.path}/updates/ghost-2.apk']);
      expect(File(phone.handed.single).readAsBytesSync(), server.file);
      expect(File('${dir.path}/updates/download.part').existsSync(), isFalse);
      expect(core.where((c) => c == 'update_verify'), isNotEmpty);
      await updates.check();
      expect(updates.apk, isA<ApkPhaseInstalling>(), reason: 'nor Android\'s own screen');
    });

    test('is fetched from beside its description, or from the https address the description gives', () async {
      final updates = await offered();
      await updates.installApk();
      expect(server.asked.last, '$_base/ghost-flutter.apk');
      server.published = _info('0.3.0', 3, url: 'https://assets.example/ghost-3.apk');
      await updates.check();
      await updates.installApk();
      expect(server.asked.last, 'https://assets.example/ghost-3.apk');
      expect(Directory('${dir.path}/updates').listSync().map((e) => e.uri.pathSegments.last), ['ghost-3.apk'], reason: 'only the one being installed stays');
    });

    test('says when Android first has to be allowed to install, and when the installer did not start', () async {
      final updates = await offered();
      phone.answer = 'permission';
      await updates.installApk();
      expect(updates.apk, isA<ApkPhaseNeedsPermission>());
      // Pressed again once allowed: the verified file is still there, and is not fetched twice.
      final downloads = server.asked.where((url) => url.endsWith('.apk')).length;
      phone.answer = 'started';
      await updates.installApk();
      expect(updates.apk, isA<ApkPhaseInstalling>());
      expect(server.asked.where((url) => url.endsWith('.apk')).length, downloads);
      phone.answer = 'ActivityNotFoundException';
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, 'The installer did not start (ActivityNotFoundException).');
    });

    test('is not installed while a meeting records, since the installer would end the recording without a word', () async {
      final updates = await offered();
      recording = true;
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, 'Stop the meeting first.');
      expect(server.asked.where((url) => url.endsWith('.apk')), isEmpty);
      expect(phone.handed, isEmpty);

      // One that starts while the download runs: the file is kept for a later tap, and nothing is handed over.
      recording = false;
      server.holding = Completer<void>();
      final install = updates.installApk();
      await pumpEventQueue();
      recording = true;
      server.holding!.complete();
      await install;
      expect((updates.apk as ApkPhaseFailed).message, 'Stop the meeting first.');
      expect(phone.handed, isEmpty);
      expect(File('${dir.path}/updates/ghost-2.apk').existsSync(), isTrue);
    });

    test('says so on a build that cannot install, and when the download fails', () async {
      final updates = await offered();
      server.downloadFails = const UpdateFailure('APK download: Connection reset by peer');
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, 'APK download: Connection reset by peer');
      expect(phone.handed, isEmpty);
      server.downloadFails = null;
      phone.answer = 'no installer';
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, 'The installer did not start (no installer).');
    });

    test('a file that is not the one published is refused, removed, and never reaches the installer', () async {
      final updates = await offered();
      // One byte changed, the size the same.
      server.file = const [1, 2, 3, 4, 5, 7];
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, 'the APK did not match its published checksum');
      expect(phone.handed, isEmpty);
      expect(Directory('${dir.path}/updates').listSync(), isEmpty);
      // More than was published.
      server.file = const [1, 2, 3, 4, 5, 6, 7];
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, 'the server sent more than the published APK size');
      expect(phone.handed, isEmpty);
      // And a description swapped for an unsigned one between the look and the press.
      server
        ..file = const [1, 2, 3, 4, 5, 6]
        ..signature = 'forged';
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, contains('the signature did not verify'));
      expect(phone.handed, isEmpty);
    });
  });

  group('the phone\'s half', () {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('ghost_md/updates');
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('reads the installed app and hands a file over, on the channel the activity answers', () async {
      final asked = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        asked.add('${call.method} ${call.arguments ?? ''}'.trim());
        return call.method == 'installed' ? {'version': '0.1.0', 'versionCode': 1, 'dir': '/cache/updates'} : 'started';
      });
      const phone = ChannelUpdatePhone();
      final app = await phone.installed();
      expect((app?.version, app?.versionCode, app?.updatesDir), ('0.1.0', 1, '/cache/updates'));
      expect(await phone.install('/cache/updates/ghost-2.apk'), 'started');
      expect(asked, ['installed', 'install {path: /cache/updates/ghost-2.apk}']);
    });

    test('with no phone half there is no installed app, and nothing installs', () async {
      const phone = ChannelUpdatePhone();
      expect(await phone.installed(), isNull);
      expect(await phone.install('/cache/updates/ghost-2.apk'), 'no installer');
    });

    test('the activity answers on that channel with those names, and only ever hands over a file from the updates directory', () {
      const main = 'android/app/src/main';
      final kotlin = File('$main/kotlin/com/mattssoftware/ghost_md/UpdateInstaller.kt').readAsStringSync();
      expect(kotlin, contains('const val CHANNEL = "${channel.name}"'));
      expect(kotlin, allOf(contains('"installed" ->'), contains('"install" ->'), contains('"version" to'), contains('"versionCode" to'), contains('"dir" to')));
      expect(kotlin, contains('if (apk.parentFile != updates || !apk.name.endsWith(".apk") || !apk.isFile) return "not an update"'));
      expect(File('$main/kotlin/com/mattssoftware/ghost_md/MainActivity.kt').readAsStringSync(), contains('UpdateInstaller(this).register(messenger)'));
      final manifest = File('$main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
      expect(manifest, allOf(contains(r'android:authorities="${applicationId}.updates"'), contains('@xml/ghost_update_paths')));
      expect(kotlin, contains(r'"${activity.packageName}.updates"'));
      expect(File('$main/res/xml/ghost_update_paths.xml').readAsStringSync(), contains('<cache-path name="updates" path="updates/" />'));
    });
  });

  group('the real core', () {
    const library = 'native/target/debug/libghost_core.dylib';
    final built = File(library).existsSync();
    final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $library)';
    const fixtures = 'native/tests/fixtures/update';

    test('reads a release signed as tool/release.md says, for the key it was signed by and no other', () async {
      final core = await GhostCore.open(libraryPath: File(library).absolute.path);
      addTearDown(core.close);
      final body = File('$fixtures/apk.json').readAsBytesSync();
      final signature = File('$fixtures/apk.json.sig').readAsStringSync();
      final key = File('$fixtures/public-key.txt').readAsStringSync().trim();
      final info = ApkInfo.of(await core.invoke('update_read', {'body': base64.encode(body), 'signature': signature, 'keys': [key]}));
      expect((info.version, info.versionCode, info.bytes, info.url), ('0.2.0', 2000, 6, 'ghost-flutter.apk'));
      await expectLater(
        core.invoke('update_read', {'body': base64.encode(body), 'signature': signature, 'keys': ['+lGP9TU8jcvUCrDjPwD5W33HsJn/Bhxm3gH4TK5CvkM=']}),
        throwsA(isA<CoreError>().having((e) => e.message, 'message', 'the signature did not verify against any trusted key')),
      );
      await expectLater(core.invoke('update_read', {'body': base64.encode([...body, 32]), 'signature': signature, 'keys': [key]}), throwsA(isA<CoreError>()));

      // And the file it names: "an apk", six bytes, by its hash.
      final file = File('${dir.path}/ghost-flutter.apk')..writeAsStringSync('an apk');
      expect(await core.invoke('update_verify', {'path': file.path, 'sha256': info.sha256, 'bytes': info.bytes}), isNull);
      file.writeAsStringSync('an apq');
      await expectLater(
        core.invoke('update_verify', {'path': file.path, 'sha256': info.sha256, 'bytes': info.bytes}),
        throwsA(isA<CoreError>().having((e) => e.message, 'message', 'the APK did not match its published checksum')),
      );
    }, skip: skip);
  });
}
