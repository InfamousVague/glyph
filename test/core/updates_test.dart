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
import 'package:ghost_md/core/locale_dates.dart';
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

/// The Mac's half: `ready` once the new app is in place, and a count of restarts.
class _Mac implements RestartingUpdatePhone {
  _Mac(this.app);
  InstalledApp? app;
  String answer = 'ready';
  String restartAnswer = 'restarting';
  final List<String> handed = [];
  int restarts = 0;

  @override
  Future<InstalledApp?> installed() async => app;

  @override
  Future<String> install(String path) async {
    handed.add(path);
    return answer;
  }

  @override
  Future<String> restart() async {
    if (restartAnswer == 'restarting') restarts += 1;
    return restartAnswer;
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

    group('describes a build id in the phone’s own words (core/locale_dates.dart)', () {
      tearDown(() => toldLocale = null);

      test('an American phone has the month first and a 12-hour clock', () {
        toldLocale = DateLocale.enUS;
        expect(describeBuild('20260912221530', toLocal: (utc) => utc), 'Sep 12, 10:15 PM');
        expect(describeBuild('20260101000500', toLocal: (utc) => utc), 'Jan 1, 12:05 AM');
        expect(describeBuild('nope'), 'unknown build');
      });

      test('a British phone has the day first and a 24-hour clock', () {
        toldLocale = DateLocale.enGB;
        expect(describeBuild('20260912221530', toLocal: (utc) => utc), '12 Sept, 22:15');
        expect(describeBuild('20260101000500', toLocal: (utc) => utc), '1 Jan, 00:05');
        expect(describeBuild('nope'), 'unknown build');
      });
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

    // docs/CUTOVER.md: the build made to replace the Tauri app is that app's next version, so it looks where that
    // app's installs look, which is the one line of tauri/src-tauri/ota-sources.txt.
    test('but the build that replaces the real app, which told nothing looks where that app\'s installs do', () {
      UpdatesConfig? cut(String source, {bool debug = false, List<String> keys = const ['a-key']}) => UpdatesConfig.of(source: source, keys: keys, debug: debug, cutover: true);
      expect(cut('')?.source, 'https://attack.fm/glyph');
      expect(cut('https://attack.fm/glyph/')?.source, tauriReleases);
      expect(cut(_base)?.source, _base, reason: 'told another, it looks there');
      expect(cut('', debug: true), isNull, reason: 'a debug build still never looks');
      expect(cut('', keys: const []), isNull);
      expect(cut('http://attack.fm/glyph'), isNull);
      final sources = File('tauri/src-tauri/ota-sources.txt');
      if (sources.existsSync()) {
        expect([for (final line in sources.readAsLinesSync()) if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim()], [tauriReleases]);
      }
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

    test('the key it believes is Ghost.md\'s own, and a build told nothing still does not look', () {
      expect(trustedUpdateKeys, ['+lGP9TU8jcvUCrDjPwD5W33HsJn/Bhxm3gH4TK5CvkM=']);
      final theirs = File('tauri/src-tauri/ota-trusted-keys.txt');
      if (theirs.existsSync()) {
        expect([for (final line in theirs.readAsLinesSync()) if (line.trim().isNotEmpty && !line.startsWith('#')) line.split('#').first.trim()], trustedUpdateKeys);
      }
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
      expect(server.asked, ['$_base/apk.json', '$_base/apk.json.flutter.sig']);
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

  group('the Mac', () {
    late _Mac mac;
    late List<Map<String, Object?>> read;
    late List<String> opened;
    var taking = false;

    setUp(() {
      mac = _Mac(InstalledApp(version: '2.3.15', versionCode: 2003015, updatesDir: '${dir.path}/updates'));
      read = [];
      opened = [];
      taking = false;
    });

    /// The core as for the phone, and what each `update_read` was asked with.
    CoreInvoke asks() {
      final inner = _core(core);
      return (String command, [Map<String, Object?> args = const {}]) {
        if (command == 'update_read') read.add(args);
        return inner(command, args);
      };
    }

    Updates makeMac() => Updates(
          config: config,
          invoke: asks(),
          phone: mac,
          transport: server,
          recording: () => recording,
          taking: () => taking,
          localOnly: () => localOnly,
          kind: UpdateKind.mac,
          openLink: (url) async => opened.add(url),
        );

    Future<Updates> offered() async {
      server.published = _info('2.3.16', 2003016, url: 'glyph-mac.zip');
      final updates = makeMac();
      await updates.check();
      expect(updates.apk, isA<ApkPhaseAvailable>());
      return updates;
    }

    test('is made in the Mac app alone, never in the Mac App Store\'s build, and the phone\'s on Android', () {
      expect(updateKindFor(android: true, macApp: false, macStore: false), UpdateKind.apk);
      expect(updateKindFor(android: false, macApp: true, macStore: false), UpdateKind.mac);
      expect(updateKindFor(android: false, macApp: true, macStore: true), isNull, reason: 'the store updates what it sells');
      expect(updateKindFor(android: false, macApp: false, macStore: false), isNull, reason: 'a test run, an iPhone');
      // And this run, a test on a Mac, is neither: no build here makes one.
      expect(Updates.forBuild(invoke: _core(core)), isNull);
    });

    test('reads mac.json and its own signature, and asks the core to read it as the Mac\'s', () async {
      await offered();
      expect(server.asked, ['$_base/mac.json', '$_base/mac.json.sig']);
      expect(read.single['kind'], 'mac');
      // The phone's description is asked as it always was, with no kind.
      final phoneUpdates = Updates(config: config, invoke: asks(), phone: phone, transport: server);
      server.published = _info('0.2.0', 2);
      await phoneUpdates.check();
      expect(server.asked.skip(2), ['$_base/apk.json', '$_base/$updateSignatureName']);
      expect(read, hasLength(2));
      expect(read.last.containsKey('kind'), isFalse);
    });

    test('is newer by the version or by the build, as on Android', () async {
      final updates = makeMac();
      for (final (version, code, newer) in [('2.3.16', 2003016, true), ('2.3.15', 2003015, false), ('2.3.14', 2003014, false), ('2.3.15', 2003016, true), ('2.4.0', 2004000, true)]) {
        server.published = _info(version, code, url: 'glyph-mac.zip');
        await updates.check();
        expect(updates.apk is ApkPhaseAvailable, newer, reason: '$version ($code) over 2.3.15 (2003015)');
      }
    });

    test('downloads the zip, has the Mac put it in place, and restarts into it when asked', () async {
      final updates = await offered();
      final seen = <String>[];
      updates.addListener(() {
        final line = updates.apk.runtimeType.toString();
        if (seen.isEmpty || seen.last != line) seen.add(line);
      });
      await updates.installApk();
      expect(seen, ['ApkPhaseDownloading', 'ApkPhaseReady']);
      expect(server.asked.last, '$_base/glyph-mac.zip');
      expect(mac.handed, ['${dir.path}/updates/ghost-2003016.zip']);
      expect(File(mac.handed.single).readAsBytesSync(), server.file);
      // A check leaves an update in place alone, and pressing Install again does nothing.
      await updates.check();
      expect(updates.apk, isA<ApkPhaseReady>());
      await updates.installApk();
      expect(mac.handed, hasLength(1));
      // Restart to update.
      await updates.restart();
      expect(updates.apk, isA<ApkPhaseRestarting>());
      expect(mac.restarts, 1);
      await updates.check();
      expect(updates.apk, isA<ApkPhaseRestarting>(), reason: 'nor while it quits');
    });

    test('a newer release than the one in place is offered over it', () async {
      final updates = await offered();
      await updates.installApk();
      expect(updates.apk, isA<ApkPhaseReady>());
      server.published = _info('2.3.17', 2003017, url: 'glyph-mac.zip');
      await updates.check();
      expect((updates.apk as ApkPhaseAvailable).info.version, '2.3.17');
    });

    test('is put in place while a meeting records, but not restarted into until it stops, nor during a take', () async {
      final updates = await offered();
      recording = true;
      await updates.installApk();
      expect(updates.apk, isA<ApkPhaseReady>(), reason: 'putting it in place ends nothing');
      await updates.restart();
      expect((updates.apk as ApkPhaseFailed).message, 'Stop the meeting first.');
      expect(mac.restarts, 0);
      recording = false;
      taking = true;
      await updates.installApk();
      await updates.restart();
      expect((updates.apk as ApkPhaseFailed).message, 'Stop the recording first.');
      expect(mac.restarts, 0);
      taking = false;
      await updates.installApk();
      await updates.restart();
      expect(mac.restarts, 1);
    });

    test('an app that cannot replace itself is sent to the disk image instead', () async {
      final updates = await offered();
      mac.answer = 'manual: Ghost.md is running from its disk image.';
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, 'Ghost.md is running from its disk image. The disk image is opening in your browser instead.');
      expect(opened, ['$_base/glyph.dmg']);
    });

    test('says why, when the Mac refused what came out of the zip or would not restart', () async {
      final updates = await offered();
      mac.answer = 'the download is not signed by Ghost.md’s developer (a sealed resource is missing or invalid)';
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, 'It could not be put in place (the download is not signed by Ghost.md’s developer (a sealed resource is missing or invalid)).');
      mac.answer = 'ready';
      await updates.installApk();
      mac.restartAnswer = 'nothing is in place to restart into';
      await updates.restart();
      expect((updates.apk as ApkPhaseFailed).message, 'Ghost.md could not restart into it (nothing is in place to restart into).');
    });

    test('a zip that is not the one published is refused in the Mac\'s words, and never reaches the Mac', () async {
      final updates = await offered();
      server.file = const [1, 2, 3, 4, 5, 7];
      await updates.installApk();
      expect((updates.apk as ApkPhaseFailed).message, 'the download did not match its published checksum');
      expect(mac.handed, isEmpty);
    });

    test('the Mac\'s half says on its channel whether this launch is a version it put in place, and restarts', () async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('ghost_md/updates');
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final asked = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        asked.add(call.method);
        return switch (call.method) {
          'installed' => {'version': '2.3.16', 'versionCode': 2003016, 'dir': '/cache/updates', 'updated': true},
          'restart' => 'restarting',
          _ => 'ready',
        };
      });
      const phone = ChannelUpdatePhone();
      final app = await phone.installed();
      expect((app?.version, app?.versionCode, app?.justUpdated), ('2.3.16', 2003016, true));
      expect(await phone.install('/cache/updates/ghost-2003016.zip'), 'ready');
      expect(await phone.restart(), 'restarting');
      expect(asked, ['installed', 'install', 'restart']);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await phone.restart(), 'no installer', reason: 'no Mac half: a test, a phone');
    });

    test('the Swift answers that channel with those names, checks the team, and is compiled out of the store\'s build', () {
      final swift = File('macos/Runner/UpdatesChannel.swift').readAsStringSync();
      expect(swift, startsWith('#if !GHOST_MAC_STORE'));
      expect(swift.trimRight(), endsWith('#endif'));
      expect(swift, contains('FlutterMethodChannel(name: "ghost_md/updates"'));
      expect(swift, allOf(contains('case "installed":'), contains('case "install":'), contains('case "restart":')));
      expect(swift, allOf(contains('"version":'), contains('"versionCode":'), contains('"dir":'), contains('"updated":')));
      expect(swift, contains(r'anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"'));
      expect(swift, contains('guard build > ownBuild else'));
      expect(swift, contains('guard plist["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier'));
      expect(swift, contains('renamex_np(staged.app.path, target.path, UInt32(RENAME_SWAP))'));
      final window = File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();
      expect(window, contains('#if !GHOST_MAC_STORE\n    updates = UpdatesChannel(messenger: messenger)\n    #endif'));
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

    test('reads the Mac\'s release, signed as scripts/deploy-flutter-mac.mjs signs it, only as the Mac\'s', () async {
      final core = await GhostCore.open(libraryPath: File(library).absolute.path);
      addTearDown(core.close);
      final body = File('$fixtures/mac.json').readAsBytesSync();
      final signature = File('$fixtures/mac.json.sig').readAsStringSync();
      final key = File('$fixtures/mac-public-key.txt').readAsStringSync().trim();
      Map<String, Object?> args({String? kind}) => {'body': base64.encode(body), 'signature': signature, 'keys': [key], 'kind': ?kind};
      final info = ApkInfo.of(await core.invoke('update_read', args(kind: 'mac')));
      expect((info.version, info.versionCode, info.bytes, info.url), ('9.9.2', 9009002, 5, 'glyph-mac.zip'));
      for (final kind in [null, 'apk']) {
        await expectLater(
          core.invoke('update_read', args(kind: kind)),
          throwsA(isA<CoreError>().having((e) => e.message, 'message', 'the signature did not verify against any trusted key')),
          reason: 'the Mac\'s description read as the phone\'s',
        );
      }
      final zip = File('${dir.path}/glyph-mac.zip')..writeAsStringSync('a zip');
      expect(await core.invoke('update_verify', {'path': zip.path, 'sha256': info.sha256, 'bytes': info.bytes}), isNull);
    }, skip: skip);
  });
}
