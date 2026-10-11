/// The app's updates: looking for a newer build of the app itself, bringing it down, checking it, and handing it to
/// Android's installer. Ports the APK's part of `src/app/core/ota.ts` (`useUpdates`, `ApkPhase`, `installApk`,
/// `isNewerVersion`, `sourceHost`, `describeBuild`) and of `src-tauri/src/ota/apk.rs`.
///
/// One [Updates] is made for the app (lib/main.dart) and feeds every screen that says anything of an update, as the
/// page's one `Updates` did: the launch screen's line, Settings › About, and the card above the notes
/// (lib/root/update_wiring.dart turns it into what each is handed).
///
/// What differs from the web:
/// - **There is no page to update.** A Flutter app is one binary: nothing is downloaded and run on a reload, so
///   `ready`, `reload`, `settleBoot`, `claimAutoReload`, the quarantine and `ota.json` have nothing to carry over.
///   What is left is the APK: a signed `apk.json` beside the file it names.
/// - **Where it looks is said at build time** (`--dart-define=GHOST_UPDATES=https://…`): a build not told has no
///   update check at all; nor has any debug build, nor one that trusts no key (lib/core/update_keys.dart).
///   [UpdatesConfig] is that rule. THE BUILD THAT REPLACES THE TAURI APP (`--dart-define=GHOST_CUTOVER=true`, with
///   Gradle's `GHOST_CUTOVER=1`: tool/cutover-build.sh gives both; docs/CUTOVER.md) is that app's next version, so
///   told nothing it looks where that app's installs look, [tauriReleases]. Every other build is refused that
///   address whatever it is told: it is another app there, and Ghost.md's APK is not an update of it. A signed
///   description cannot move the app to another address (the page's `sources`): one place, until a release has
///   needed two.
/// - **The signature it asks for is its own file**, `apk.json.flutter.sig`, beside the Tauri app's `apk.json.sig`
///   over the same `apk.json`: the same key signs both, each with its app's context (`ghost-flutter-apk\0` here,
///   `glyph-apk\0` there; native/src/kept/updates.rs). So one description at one address serves the Tauri installs
///   that are to be offered this app and this app's own installs after them (tool/release_apk.mjs writes all
///   three files).
/// - **The requests are Dart's** ([HttpUpdateTransport]) and the checking is the core's (`update_read`,
///   `update_verify`; native/src/kept/updates.rs, the Tauri app's lines). Rust made the requests there; the rule is
///   the same one: a description is read only once a trusted key signed exactly its bytes, and a file is handed to
///   the installer only at the size and the SHA-256 that description gives.
/// - **Newer is by the version or by the version code**, where the page had the version or the native generation:
///   the code is what Android itself goes by.
/// - **A failed look says so** ([Updates.lastError]). On the page a missing or unsigned `apk.json` was quiet, since
///   `ota.json` was the check; here it is the whole of it.
/// - **The phone's own notifier is not ported** (`UpdateCheckWorker.kt`): nothing looks while the app is closed.
///   README, "What stage 9's other pieces left open".
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ai/support/failure.dart';
import '../capture/meeting.dart' show stopTheMeeting;
import 'locale_dates.dart';
import 'native/core.dart';
import 'update_keys.dart';

// ---- what the build was told ----------------------------------------------------------------------------------------

/// Where this app's releases are (`--dart-define=GHOST_UPDATES=https://…/flutter`): `apk.json`,
/// `apk.json.flutter.sig` and the APK sit directly under it. Empty in a build not told, which then never looks.
const String _source = String.fromEnvironment('GHOST_UPDATES');

/// When this build was made, UTC `YYYYMMDDHHMMSS` (`--dart-define=GHOST_BUILD=…`, the page's `__GLYPH_BUILD__`).
const String ghostBuild = String.fromEnvironment('GHOST_BUILD');

/// FOR A TEST RUN ONLY, and read only by a debug build: `GHOST_UPDATES_TEST=true` turns the check on there, lets
/// the address be `http://` (an emulator reaching the Mac), and trusts `GHOST_UPDATES_TEST_KEY` beside the app's
/// own keys. A release or profile build reads neither, whatever it was built with.
const bool _testing = bool.fromEnvironment('GHOST_UPDATES_TEST');
const String _testKey = String.fromEnvironment('GHOST_UPDATES_TEST_KEY');

/// Whether this is the build that replaces the Tauri app (`--dart-define=GHOST_CUTOVER=true`; the header).
const bool _cutover = bool.fromEnvironment('GHOST_CUTOVER');

/// Where the Tauri app's installs look for a release (`../glyph/src-tauri/ota-sources.txt`, its one line; the
/// directory `../glyph/scripts/deploy-ota.mjs` publishes `glyph.apk` and `apk.json` into).
const String tauriReleases = 'https://attack.fm/glyph';

/// The Tauri app's own update addresses ([tauriReleases], and the site it moved to). Only the build that replaces
/// that app looks there; any other is another app, whatever it is told.
const Set<String> _theRealApps = <String>{tauriReleases, 'https://ghostmarkdown.com/glyph'};

/// The signature this app reads, beside `apk.json` (the header).
const String updateSignatureName = 'apk.json.flutter.sig';

/// Where to look and whom to believe, or nothing: the rule in the header.
@immutable
class UpdatesConfig {
  const UpdatesConfig._({required this.source, required this.keys, required this.http});

  /// The base address, with no trailing slash.
  final String source;

  /// The keys a description may be signed by (raw Ed25519, base64).
  final List<String> keys;

  /// Whether `http://` is let through: a test run's.
  final bool http;

  /// What this build was told, or null where it does not check.
  static UpdatesConfig? fromBuild() => of(source: _source, keys: trustedUpdateKeys, debug: kDebugMode, testing: _testing, testKey: _testKey, cutover: _cutover);

  /// The rule, with everything it reads handed in. Null for: no address (but in the build that replaces the Tauri
  /// app, [cutover], which then looks at [tauriReleases]); a debug build not under test; an address that is not
  /// https (http, under test); the Tauri app's own in any build but that one; and no key to believe.
  static UpdatesConfig? of({required String source, required List<String> keys, required bool debug, bool testing = false, String testKey = '', bool cutover = false}) {
    final test = debug && testing;
    if (debug && !test) return null;
    var base = source.trim();
    if (base.isEmpty && cutover) base = tauriReleases;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.tryParse(base);
    if (base.isEmpty || uri == null || uri.host.isEmpty || uri.hasQuery || uri.hasFragment || RegExp(r'\s').hasMatch(base)) return null;
    if (uri.scheme != 'https' && !(test && uri.scheme == 'http')) return null;
    if (!cutover && _theRealApps.contains(base.toLowerCase())) return null;
    final trusted = <String>[...keys, if (test && testKey.trim().isNotEmpty) testKey.trim()];
    if (trusted.isEmpty) return null;
    return UpdatesConfig._(source: base, keys: List.unmodifiable(trusted), http: test);
  }
}

// ---- words ----------------------------------------------------------------------------------------------------------

/// Dotted versions compared numerically; anything unparsable compares as older (`isNewerVersion`).
bool isNewerVersion(String offered, String installed) {
  List<int> parse(String v) => [for (final part in v.split(RegExp(r'[.+-]')).take(3)) _leadingInt(part)];
  final a = parse(offered), b = parse(installed);
  for (var i = 0; i < 3; i += 1) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// `Number.parseInt(part, 10) || 0`: the digits a part begins with, and nothing for a part with none.
int _leadingInt(String part) => int.tryParse(RegExp(r'^\s*[+-]?\d+').stringMatch(part)?.trim() ?? '') ?? 0;

/// "attack.fm" for "https://attack.fm/glyph": where updates come from, as a person reads it (`sourceHost`).
String? sourceHost(String? source) {
  if (source == null || source.isEmpty) return null;
  final uri = Uri.tryParse(source);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Sep 12, 10:15 PM": a build id as a person scans it, in their own time zone (`describeBuild`); "unknown build"
/// for anything that is not fourteen digits. The page asked the browser's locale for the words (`shortWhen`); here
/// they are English in the phone's own order and clock once it has said (core/locale_dates.dart: "12 Sept, 22:15"
/// on a British phone), and as an American one writes them until then.
String describeBuild(String? build, {DateTime Function(DateTime utc)? toLocal}) {
  if (build == null || !RegExp(r'^\d{14}$').hasMatch(build)) return 'unknown build';
  int n(int from, int to) => int.parse(build.substring(from, to));
  final utc = DateTime.utc(n(0, 4), n(4, 6), n(6, 8), n(8, 10), n(10, 12), n(12, 14));
  final at = toLocal?.call(utc) ?? utc.toLocal();
  final told = toldDate(at, DateForm.MMMdhm2);
  if (told != null) return told;
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '${_months[at.month - 1]} ${at.day}, ${hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
}

// ---- what a release says, and where an install stands ---------------------------------------------------------------

/// The APK a release offers (`ApkInfo`), as its signed `apk.json` says it. tool/release.md has the fields.
@immutable
class ApkInfo {
  const ApkInfo({required this.version, required this.versionCode, required this.sha256, required this.bytes, required this.url});

  final String version;
  final int versionCode;
  final String sha256;
  final int bytes;

  /// A file's name beside `apk.json`, or a whole https address.
  final String url;

  /// What the core answered (`update_read`): already verified, so a wrong shape here is the core's fault.
  static ApkInfo of(Object? answer) {
    if (answer case {'version': final String version, 'versionCode': final num code, 'sha256': final String sha256, 'bytes': final num bytes, 'url': final String url}) {
      return ApkInfo(version: version, versionCode: code.toInt(), sha256: sha256, bytes: bytes.toInt(), url: url);
    }
    throw const FormatException('the update was not described as this build reads one');
  }
}

/// Where a new version of the app is (`ApkPhase`).
sealed class ApkPhase {
  const ApkPhase();
}

/// Nothing newer is out (`'none'`).
class ApkPhaseNone extends ApkPhase {
  const ApkPhaseNone();
}

/// Every phase but none is about one release.
sealed class ApkPhaseOf extends ApkPhase {
  const ApkPhaseOf(this.info);
  final ApkInfo info;
}

/// Out, and not asked for yet (`'available'`).
class ApkPhaseAvailable extends ApkPhaseOf {
  const ApkPhaseAvailable(super.info);
}

/// Coming down (`'downloading'`).
class ApkPhaseDownloading extends ApkPhaseOf {
  const ApkPhaseDownloading(super.info, {required this.received, required this.total});
  final int received;
  final int total;
}

/// Handed to Android, whose own screen is up, or was put away (`'installing'`).
class ApkPhaseInstalling extends ApkPhaseOf {
  const ApkPhaseInstalling(super.info);
}

/// Android has to be told this app may install apps, and its page for that is up (`'needs-permission'`).
class ApkPhaseNeedsPermission extends ApkPhaseOf {
  const ApkPhaseNeedsPermission(super.info);
}

/// It did not install, and why (`'failed'`).
class ApkPhaseFailed extends ApkPhaseOf {
  const ApkPhaseFailed(super.info, this.message);
  final String message;
}

// ---- the phone's half -----------------------------------------------------------------------------------------------

/// The app as it is installed, and where a download is kept for the installer.
@immutable
class InstalledApp {
  const InstalledApp({required this.version, required this.versionCode, required this.updatesDir});

  /// `versionName`, as Android's package manager has it (the page's `status.nativeVersion`).
  final String version;
  final int versionCode;

  /// `<cacheDir>/updates`: the one directory the phone's installer is ever handed a file from (`UPDATES`, paths.rs).
  final String updatesDir;
}

/// What the phone does for an update (android/…/ghost_md/UpdateInstaller.kt on Android; a test's own).
abstract class UpdatePhone {
  /// The installed app, or null where there is no phone half: then nothing is looked for.
  Future<InstalledApp?> installed();

  /// Hands the verified file at [path] to Android's installer (`GlyphHost.installApk`): `started`, `permission`
  /// when the person must first let this app install apps (their page for it is opened), or a reason.
  Future<String> install(String path);
}

/// The phone's half over the channel `ghost_md/updates`. Off Android there is none.
class ChannelUpdatePhone implements UpdatePhone {
  const ChannelUpdatePhone([this.channel = const MethodChannel('ghost_md/updates')]);

  final MethodChannel channel;

  @override
  Future<InstalledApp?> installed() async {
    try {
      final answer = await channel.invokeMapMethod<String, Object?>('installed');
      if (answer case {'version': final String version, 'versionCode': final int code, 'dir': final String dir}) {
        return InstalledApp(version: version, versionCode: code, updatesDir: dir);
      }
    } on MissingPluginException {
      // A desktop run, a test: no phone half.
    } on PlatformException {
      // The phone would not say: as none.
    }
    return null;
  }

  @override
  Future<String> install(String path) async {
    try {
      return await channel.invokeMethod<String>('install', <String, Object?>{'path': path}) ?? 'no answer';
    } on MissingPluginException {
      return 'no installer';
    } on PlatformException catch (error) {
      return error.message ?? error.code;
    }
  }
}

// ---- the requests ---------------------------------------------------------------------------------------------------

/// The two requests an update makes. A failure throws, its words beginning with what was asked for.
abstract class UpdateTransport {
  /// A small file, whole (`fetch_bytes`): `apk.json` and its signature. Never from a cache.
  Future<Uint8List> read(String url);

  /// The APK into [to], telling [onProgress] as it comes; refused once more than [limit] bytes arrive.
  Future<void> download(String url, File to, {required int limit, required void Function(int received) onProgress});
}

/// Over `HttpClient`, with the Tauri app's timeouts (fetch.rs `client`): fifteen seconds to connect, thirty of
/// silence, and never a total one, since an APK over a slow connection is legitimately minutes.
class HttpUpdateTransport implements UpdateTransport {
  HttpUpdateTransport({HttpClient? client}) : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final HttpClient _client;
  static const Duration _quiet = Duration(seconds: 30);

  /// A description and its signature are a few hundred bytes; anything past this is not one.
  static const int _smallest = 64 * 1024;

  Future<HttpClientResponse> _get(String url, {bool fresh = false}) async {
    final request = await _client.getUrl(Uri.parse(url)).timeout(_quiet);
    if (fresh) request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(_quiet);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>().catchError((_) {});
      throw HttpException('the server answered ${response.statusCode}');
    }
    return response;
  }

  @override
  Future<Uint8List> read(String url) async {
    try {
      final response = await _get(url, fresh: true);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_quiet)) {
        bytes.add(chunk);
        if (bytes.length > _smallest) throw const HttpException('too large to be an update’s description');
      }
      return bytes.takeBytes();
    } catch (error) {
      throw UpdateFailure('$url: ${_words(error)}');
    }
  }

  @override
  Future<void> download(String url, File to, {required int limit, required void Function(int received) onProgress}) async {
    IOSink? out;
    try {
      final response = await _get(url);
      out = to.openWrite();
      var received = 0, nextReport = 0;
      await for (final chunk in response.timeout(_quiet)) {
        received += chunk.length;
        if (received > limit) throw const UpdateFailure('the server sent more than the published APK size');
        out.add(chunk);
        // Every half megabyte (apk.rs), not every chunk: each is a redraw.
        if (received >= nextReport) {
          onProgress(received);
          nextReport = received + 512 * 1024;
        }
      }
      await out.flush();
      await out.close();
      out = null;
      onProgress(received);
    } on UpdateFailure {
      rethrow;
    } catch (error) {
      throw UpdateFailure('APK download: ${_words(error)}');
    } finally {
      await out?.close().catchError((_) {});
    }
  }

  static String _words(Object error) => switch (error) {
        TimeoutException() => 'the server went quiet',
        SocketException(:final message) => message,
        HttpException(:final message) => message,
        _ => failureText(error),
      };
}

/// An update's request or file that did not come to anything, in words a person reads.
class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---- the updates ----------------------------------------------------------------------------------------------------

/// The first look, after launch has settled and the list has painted (`FIRST_CHECK_MS`).
const Duration firstCheck = Duration(seconds: 4);

/// How long a returning app waits before looking again (`RECHECK_MS`). A minute: coming back to the app is the
/// moment a wait for an update is felt, and a check is one small signed file.
const Duration recheck = Duration(minutes: 1);

/// And again, on this beat, for as long as the app is open and on screen (`POLL_MS`; Matt: "the OTA update is
/// taking really long to show up in the app"). Nothing runs while the app is hidden.
const Duration poll = Duration(minutes: 2);

/// The app's updates (`Updates`, `useUpdates`): what every screen that speaks of one listens to.
class Updates extends ChangeNotifier with WidgetsBindingObserver {
  Updates({
    required this.config,
    required CoreInvoke invoke,
    required UpdatePhone phone,
    UpdateTransport? transport,
    bool Function()? recording,
    bool Function()? localOnly,
    DateTime Function()? now,
  })  : _invoke = invoke,
        _phone = phone,
        _transport = transport ?? HttpUpdateTransport(),
        _recording = recording,
        _localOnly = localOnly,
        _now = now ?? DateTime.now;

  /// The app's own, or null where this build does not check (the header): then no screen says anything of updates.
  static Updates? forBuild({required CoreInvoke invoke, bool Function()? localOnly}) {
    final config = UpdatesConfig.fromBuild();
    if (config == null || !Platform.isAndroid) return null;
    return Updates(config: config, invoke: invoke, phone: const ChannelUpdatePhone(), localOnly: localOnly);
  }

  final UpdatesConfig config;
  final CoreInvoke _invoke;
  final UpdatePhone _phone;
  final UpdateTransport _transport;
  final bool Function()? _localOnly;
  final DateTime Function() _now;
  bool Function()? _recording;

  /// Whether a meeting is being recorded (`meetingStateNow()?.recording`). The root says, once voice is up.
  set recording(bool Function()? asks) => _recording = asks;

  ApkPhase get apk => _apk;
  ApkPhase _apk = const ApkPhaseNone();

  bool get checking => _checking;
  bool _checking = false;

  /// Why the last look found nothing out, where it could not look (`lastError`).
  String? get lastError => _lastError;
  String? _lastError;

  /// When it last looked, answered or not (`lastChecked`).
  DateTime? get lastChecked => _lastChecked;
  DateTime? _lastChecked;

  /// The app as installed, once the phone has said (`status`).
  InstalledApp? get installed => _installed;
  InstalledApp? _installed;

  /// Where updates come from, as a person reads it.
  String? get host => sourceHost(config.source);

  bool _running = false;
  bool _front = true;
  bool _started = false;
  bool _gone = false;
  DateTime? _lastAt;
  Timer? _first;
  Timer? _beat;

  void _set(VoidCallback change) {
    if (_gone) return;
    change();
    notifyListeners();
  }

  /// Begins the timing (`useUpdates`' effect): a look four seconds on, one on every return after a minute away,
  /// and one on a two-minute beat while in front. Once.
  void start() {
    if (_started || _gone) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_phone.installed().then((app) {
      if (app != null && _installed == null) _set(() => _installed = app);
    }));
    _first = Timer(firstCheck, () => unawaited(check()));
    // On the beat, while the app is in front: a hidden app is asleep.
    _beat = Timer.periodic(poll, (_) {
      if (_front) unawaited(check());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => shown(state == AppLifecycleState.resumed);

  /// The app came to the front, or left it (`visibilitychange`).
  void shown(bool front) {
    final was = _front;
    _front = front;
    if (!front || was) return;
    final last = _lastAt;
    if (last == null || _now().difference(last) > recheck) unawaited(check());
  }

  /// Looks for a newer build (`check`). Nothing at all with "Nothing leaves the phone" on: not even whether there
  /// is one is asked of anywhere.
  Future<void> check() async {
    if (_gone || _running || (_localOnly?.call() ?? false)) return;
    _running = true;
    _set(() => _checking = true);
    try {
      final app = _installed ?? await _phone.installed();
      // No phone half: nothing here could be installed, so nothing is asked.
      if (app == null) return;
      _installed = app;
      final ApkInfo offered;
      try {
        offered = await _described();
      } catch (error) {
        _lastAt = _now();
        _set(() {
          _lastChecked = _lastAt;
          _lastError = failureText(error);
        });
        return;
      }
      _lastAt = _now();
      final newer = isNewerVersion(offered.version, app.version) || offered.versionCode > app.versionCode;
      _set(() {
        _lastChecked = _lastAt;
        _lastError = null;
        final prev = _apk;
        if (!newer) {
          _apk = const ApkPhaseNone();
        } else if (prev is! ApkPhaseDownloading && prev is! ApkPhaseInstalling) {
          // A download or install in progress is not interrupted by a check.
          _apk = ApkPhaseAvailable(offered);
        }
      });
    } finally {
      _running = false;
      _set(() => _checking = false);
    }
  }

  /// `apk.json`, read only if a trusted key signed exactly its bytes (`fetch_signed`).
  Future<ApkInfo> _described() async {
    final url = '${config.source}/apk.json';
    final body = await _transport.read(url);
    final signature = await _transport.read('${config.source}/$updateSignatureName');
    try {
      final answer = await _invoke('update_read', {'body': base64.encode(body), 'signature': utf8.decode(signature, allowMalformed: true), 'keys': config.keys, 'http': config.http});
      return ApkInfo.of(answer);
    } catch (error) {
      throw UpdateFailure('$url: ${failureText(error)}');
    }
  }

  /// Brings the new version down and hands it to Android (`installApk`). Pressed again while Android's screen is
  /// up, or after it was put away, it hands the same file over again: the verified file is still in the cache.
  Future<void> installApk() async {
    final phase = _apk;
    if (phase is! ApkPhaseOf || phase is ApkPhaseDownloading) return;
    final info = phase.info;
    // The installer ends the process, and a meeting being recorded with it: stopped without a word, and written up
    // only at the next launch. So not while one records, as a reset is not (core/reset.dart).
    if (_recording?.call() ?? false) {
      _set(() => _apk = ApkPhaseFailed(info, stopTheMeeting));
      return;
    }
    _set(() => _apk = ApkPhaseDownloading(info, received: 0, total: info.bytes));
    try {
      final path = await _fetch((latest, received) => _set(() => _apk = ApkPhaseDownloading(info, received: received, total: latest.bytes)));
      // A meeting started while the download ran: the same answer, now that the file is here for a later tap.
      if (_recording?.call() ?? false) {
        _set(() => _apk = ApkPhaseFailed(info, stopTheMeeting));
        return;
      }
      final answer = await _phone.install(path);
      _set(() {
        _apk = switch (answer) {
          'permission' => ApkPhaseNeedsPermission(info),
          'started' => ApkPhaseInstalling(info),
          _ => ApkPhaseFailed(info, 'The installer did not start ($answer).'),
        };
      });
    } catch (error) {
      _set(() => _apk = ApkPhaseFailed(info, failureText(error)));
    }
  }

  /// Downloads the published APK, verified, and answers with its path (`ota_fetch_apk`, apk.rs `fetch`). The
  /// description is read again, signature and all: what is installed is what is published now.
  Future<String> _fetch(void Function(ApkInfo info, int received) progress) async {
    final app = _installed ?? await _phone.installed();
    if (app == null) throw UpdateFailure('This build can’t install updates itself. Download it from ${host ?? 'where you got it'}.');
    final info = await _described();
    // A relative name is served beside apk.json; an absolute https URL (a release asset on another host) is allowed
    // too. Either way the signed SHA-256 decides, and Android refuses an APK signed by another key.
    final download = info.url.contains('://') ? info.url : '${config.source}/${info.url}';
    final dir = Directory(app.updatesDir);
    await dir.create(recursive: true);
    final target = File('${dir.path}/ghost-${info.versionCode}.apk');
    Future<bool> matches(File file) async {
      if (!file.existsSync()) return false;
      try {
        await _invoke('update_verify', {'path': file.path, 'sha256': info.sha256, 'bytes': info.bytes});
        return true;
      } catch (_) {
        return false;
      }
    }

    if (await matches(target)) {
      // Already here from an earlier tap (the one that stopped for the install permission, usually). Say so, or
      // the card sits on "0 of 44 MB".
      progress(info, info.bytes);
      return target.path;
    }
    // Old downloads are tens of megabytes each; only the one being fetched stays.
    await for (final entry in dir.list()) {
      try {
        await entry.delete(recursive: true);
      } catch (_) {
        // In use, or gone already.
      }
    }
    final part = File('${dir.path}/download.part');
    try {
      await _transport.download(download, part, limit: info.bytes, onProgress: (received) => progress(info, received));
      if (!await matches(part)) throw const UpdateFailure('the APK did not match its published checksum');
    } catch (_) {
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {
        // Nothing to remove.
      }
      rethrow;
    }
    try {
      await part.rename(target.path);
    } catch (error) {
      throw UpdateFailure('cannot place the APK: ${failureText(error)}');
    }
    progress(info, info.bytes);
    return target.path;
  }

  @override
  void dispose() {
    _gone = true;
    _first?.cancel();
    _beat?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
