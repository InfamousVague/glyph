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
///
/// THE MAC (Matt, 2026-10-24: "Work on making the mac apps update OTA it's a pain to have to download the new
/// version from the website every time"). The website's Mac build updates itself the same way, with [UpdateKind.mac]
/// where the phone has [UpdateKind.apk]: the same address, the same key, the same rule.
/// - **What it reads** is `mac.json` beside the APK's files, signed into `mac.json.sig` over a context of its own
///   (`ghost-flutter-mac\0`; native/src/kept/updates.rs `CONTEXT_MAC`) by the key that signs the APK's, and naming
///   `glyph-mac.zip`: the notarised, stapled app, zipped by `ditto` (scripts/deploy-flutter-mac.mjs `--prepare`
///   writes all three). Its `versionCode` is the app's `CFBundleVersion`, made as the phone's code is (2.3.16 is
///   2003016, tool/cutover-build-mac.sh), so newer is asked exactly as on Android.
/// - **What installs it is the Mac's half** (macos/Runner/UpdatesChannel.swift, on the same channel the phone
///   answers, `ghost_md/updates`). Handed the verified zip it unpacks it beside the running app, asks the Mac whether
///   what came out is this app, newer, and signed by this app's team, and answers `ready`: the new version is in
///   place to be swapped in ([ApkPhaseReady], "Restart to update"). [Updates.restart] swaps the two bundles and
///   starts the new one, the old kept until the new one has opened; quitting does the swap too, and the next launch
///   is the new version. Where the app cannot replace itself (run from its disk image, from where it was downloaded,
///   or from a folder this account cannot write to) it answers `manual: <why>`, and the disk image is opened in the
///   browser instead.
/// - **Not the Mac App Store's build** ([updateKindFor]): the store updates what it sells, and refuses an app with
///   an updater in it. The Swift half is not even compiled into that build (`GHOST_MAC_STORE`,
///   macos/Runner/Configs/AppInfo.xcconfig).
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
import 'mac_app.dart' show macAppStore, runsAsMacApp;
import 'native/core.dart';
import 'open_link.dart' as links;
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

/// AS FOR A TEST RUN, and read only beside `GHOST_UPDATES_TEST` by a debug build: the update presses its own
/// buttons, Install eight seconds after one is found and Restart to update eight seconds after it is in place, so
/// tool/mac-update-proof.sh can walk an update through the app's real screens with no hand on them.
const bool _walk = bool.fromEnvironment('GHOST_UPDATES_TEST_WALK');

/// Whether this is the build that replaces the Tauri app (`--dart-define=GHOST_CUTOVER=true`; the header).
const bool _cutover = bool.fromEnvironment('GHOST_CUTOVER');

/// Where the Tauri app's installs look for a release (`tauri/src-tauri/ota-sources.txt`, its one line; the
/// directory `tauri/scripts/deploy-ota.mjs` publishes `glyph.apk` and `apk.json` into).
const String tauriReleases = 'https://attack.fm/glyph';

/// The Tauri app's own update addresses ([tauriReleases], and the site it moved to). Only the build that replaces
/// that app looks there; any other is another app, whatever it is told.
const Set<String> _theRealApps = <String>{tauriReleases, 'https://ghostmarkdown.com/glyph'};

/// The signature this app reads, beside `apk.json` (the header).
const String updateSignatureName = 'apk.json.flutter.sig';

/// What an install of this app updates itself from (the header): the phone's APK, or the Mac's zip of the app.
enum UpdateKind {
  apk(feed: 'apk.json', signature: updateSignatureName, extension: 'apk', file: 'APK', download: 'APK download'),
  mac(feed: 'mac.json', signature: 'mac.json.sig', extension: 'zip', file: 'download', download: 'The download');

  const UpdateKind({required this.feed, required this.signature, required this.extension, required this.file, required this.download});

  /// The signed description, beside the file it names.
  final String feed;

  /// Its signature's file.
  final String signature;

  /// What a download is kept as (`ghost-<code>.<extension>`).
  final String extension;

  /// The file in a sentence: "the APK did not match its published checksum", "the download did not match …".
  final String file;

  /// What a failed download's words begin with: "APK download: Connection reset by peer".
  final String download;
}

/// Which update a build makes itself ([Updates.forBuild]): the phone's on Android; the Mac's in the Mac app itself,
/// never in the Mac App Store's build; nothing anywhere else (a test, an iPhone, whose updates are the store's).
UpdateKind? updateKindFor({required bool android, required bool macApp, required bool macStore}) {
  if (android) return UpdateKind.apk;
  if (macApp && !macStore) return UpdateKind.mac;
  return null;
}

/// Where the website's disk image is, beside the release's other files: what a Mac that cannot replace its own app
/// is sent to (the header).
const String macDiskImage = 'glyph.dmg';

/// Said when an install that would end the process is asked for while a take is being recorded: the meeting's
/// sentence ([stopTheMeeting]) for the recorder.
const String stopTheRecording = 'Stop the recording first.';

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

/// The Mac's: downloaded, verified, and unpacked beside the running app, which a restart (or a quit) swaps in.
/// The page's `ready`, for an app rather than a page.
class ApkPhaseReady extends ApkPhaseOf {
  const ApkPhaseReady(super.info);
}

/// The Mac's: the new version is being swapped in, and the app is about to quit and open again as it.
class ApkPhaseRestarting extends ApkPhaseOf {
  const ApkPhaseRestarting(super.info);
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
  const InstalledApp({required this.version, required this.versionCode, required this.updatesDir, this.justUpdated = false});

  /// `versionName`, as Android's package manager has it (the page's `status.nativeVersion`); on a Mac the bundle's
  /// `CFBundleShortVersionString`.
  final String version;

  /// `versionCode`; on a Mac `CFBundleVersion`, made the same way.
  final int versionCode;

  /// `<cacheDir>/updates`: the one directory the phone's installer is ever handed a file from (`UPDATES`, paths.rs).
  final String updatesDir;

  /// The Mac's: this launch is the first of a version the app put in place itself (UpdatesChannel.swift `settle`),
  /// which the launch screen says ("Updated to Ghost.md 2.3.16").
  final bool justUpdated;
}

/// What the phone does for an update (android/…/ghost_md/UpdateInstaller.kt on Android, macos/Runner/
/// UpdatesChannel.swift on a Mac; a test's own).
abstract class UpdatePhone {
  /// The installed app, or null where there is no phone half: then nothing is looked for.
  Future<InstalledApp?> installed();

  /// Hands the verified file at [path] to Android's installer (`GlyphHost.installApk`): `started`, `permission`
  /// when the person must first let this app install apps (their page for it is opened), or a reason. A Mac
  /// unpacks and checks the zip and answers `ready` once the new app is in place beside the running one, or
  /// `manual: <why>` where it cannot replace itself.
  Future<String> install(String path);
}

/// The Mac's half has one thing more: to swap in the version [UpdatePhone.install] put in place, and start it.
abstract class RestartingUpdatePhone implements UpdatePhone {
  /// `restarting` as the app begins to quit, or a reason it will not.
  Future<String> restart();
}

/// The phone's half over the channel `ghost_md/updates`, and the Mac's on the same one. Anywhere else there is none.
class ChannelUpdatePhone implements RestartingUpdatePhone {
  const ChannelUpdatePhone([this.channel = const MethodChannel('ghost_md/updates')]);

  final MethodChannel channel;

  @override
  Future<InstalledApp?> installed() async {
    try {
      final answer = await channel.invokeMapMethod<String, Object?>('installed');
      if (answer case {'version': final String version, 'versionCode': final int code, 'dir': final String dir}) {
        return InstalledApp(version: version, versionCode: code, updatesDir: dir, justUpdated: answer['updated'] == true);
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

  @override
  Future<String> restart() async {
    try {
      return await channel.invokeMethod<String>('restart') ?? 'no answer';
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
  HttpUpdateTransport({HttpClient? client, this.kind = UpdateKind.apk}) : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final HttpClient _client;

  /// Whose download this is, for its words.
  final UpdateKind kind;
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
        if (received > limit) throw UpdateFailure('the server sent more than the published ${kind.file} size');
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
      throw UpdateFailure('${kind.download}: ${_words(error)}');
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
    bool Function()? taking,
    bool Function()? localOnly,
    DateTime Function()? now,
    this.kind = UpdateKind.apk,
    Future<void> Function(String url)? openLink,
  })  : _invoke = invoke,
        _phone = phone,
        _transport = transport ?? HttpUpdateTransport(kind: kind),
        _recording = recording,
        _taking = taking,
        _localOnly = localOnly,
        _openLink = openLink ?? links.openLink,
        _now = now ?? DateTime.now;

  /// The app's own, or null where this build does not check (the header): then no screen says anything of updates.
  /// On a phone the APK; in the Mac app the Mac's own, but never in the Mac App Store's build ([updateKindFor]).
  static Updates? forBuild({required CoreInvoke invoke, bool Function()? localOnly}) {
    final config = UpdatesConfig.fromBuild();
    final kind = updateKindFor(android: Platform.isAndroid, macApp: runsAsMacApp, macStore: macAppStore);
    if (config == null || kind == null) return null;
    final updates = Updates(config: config, invoke: invoke, phone: const ChannelUpdatePhone(), localOnly: localOnly, kind: kind);
    if (kDebugMode && _testing && _walk) updates._walkItself();
    return updates;
  }

  /// [_walk]'s presses: each phase that waits on a person is moved on once, after a beat, if it still waits.
  void _walkItself() {
    ApkPhase? seen;
    addListener(() {
      final phase = _apk;
      if (identical(phase, seen)) return;
      seen = phase;
      Future<void> Function()? press = switch (phase) {
        ApkPhaseAvailable() => installApk,
        ApkPhaseReady() => restart,
        _ => null,
      };
      if (press == null) return;
      Timer(const Duration(seconds: 8), () {
        if (identical(_apk, phase)) unawaited(press());
      });
    });
  }

  final UpdatesConfig config;

  /// What this install updates itself from: the phone's APK or the Mac's app.
  final UpdateKind kind;
  final CoreInvoke _invoke;
  final UpdatePhone _phone;
  final UpdateTransport _transport;
  final bool Function()? _localOnly;
  final Future<void> Function(String url) _openLink;
  final DateTime Function() _now;
  bool Function()? _recording;
  bool Function()? _taking;

  /// Whether a meeting is being recorded (`meetingStateNow()?.recording`). The root says, once voice is up.
  set recording(bool Function()? asks) => _recording = asks;

  /// Whether a take is being recorded (the recorder is on screen). The root says, as for [recording].
  set taking(bool Function()? asks) => _taking = asks;

  /// What stops an install that would end the process now, in words, or null: a meeting, then a take.
  String? get _busy {
    if (_recording?.call() ?? false) return stopTheMeeting;
    if (_taking?.call() ?? false) return stopTheRecording;
    return null;
  }

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
        } else if (prev is ApkPhaseReady && prev.info.versionCode >= offered.versionCode) {
          // The Mac's: this version is already in place for a restart. A newer one still is offered over it.
        } else if (prev is! ApkPhaseDownloading && prev is! ApkPhaseInstalling && prev is! ApkPhaseRestarting) {
          // A download or install in progress is not interrupted by a check.
          _apk = ApkPhaseAvailable(offered);
        }
      });
    } finally {
      _running = false;
      _set(() => _checking = false);
    }
  }

  /// `apk.json` (the Mac's `mac.json`), read only if a trusted key signed exactly its bytes (`fetch_signed`), over
  /// its kind's context.
  Future<ApkInfo> _described() async {
    final url = '${config.source}/${kind.feed}';
    final body = await _transport.read(url);
    final signature = await _transport.read('${config.source}/${kind.signature}');
    try {
      final answer = await _invoke('update_read', {
        'body': base64.encode(body),
        'signature': utf8.decode(signature, allowMalformed: true),
        'keys': config.keys,
        'http': config.http,
        if (kind != UpdateKind.apk) 'kind': kind.name,
      });
      return ApkInfo.of(answer);
    } catch (error) {
      throw UpdateFailure('$url: ${failureText(error)}');
    }
  }

  /// Brings the new version down and hands it to Android (`installApk`). Pressed again while Android's screen is
  /// up, or after it was put away, it hands the same file over again: the verified file is still in the cache.
  ///
  /// On a Mac it brings the zip down and hands it to the Mac's half, which puts the new app in place beside this
  /// one ([ApkPhaseReady]); nothing is ended by that, so a recording does not stop it: [restart] is what ends the
  /// process, and is what waits for one.
  Future<void> installApk() async {
    final phase = _apk;
    if (phase is! ApkPhaseOf || phase is ApkPhaseDownloading || phase is ApkPhaseReady || phase is ApkPhaseRestarting) return;
    final info = phase.info;
    final mac = kind == UpdateKind.mac;
    // The installer ends the process, and a meeting being recorded with it: stopped without a word, and written up
    // only at the next launch. So not while one records, as a reset is not (core/reset.dart).
    final busy = mac ? null : _busy;
    if (busy != null) {
      _set(() => _apk = ApkPhaseFailed(info, busy));
      return;
    }
    _set(() => _apk = ApkPhaseDownloading(info, received: 0, total: info.bytes));
    try {
      final path = await _fetch((latest, received) => _set(() => _apk = ApkPhaseDownloading(info, received: received, total: latest.bytes)));
      // A meeting started while the download ran: the same answer, now that the file is here for a later tap.
      final busy = mac ? null : _busy;
      if (busy != null) {
        _set(() => _apk = ApkPhaseFailed(info, busy));
        return;
      }
      final answer = await _phone.install(path);
      if (mac && answer.startsWith('manual')) {
        // The app cannot replace itself where it is: the disk image, as the download page gives it.
        final why = answer.replaceFirst(RegExp(r'^manual:?\s*'), '');
        unawaited(_openLink('${config.source}/$macDiskImage').catchError((_) {}));
        _set(() => _apk = ApkPhaseFailed(info, '${why.isEmpty ? '' : '$why '}The disk image is opening in your browser instead.'));
        return;
      }
      _set(() {
        _apk = switch (answer) {
          'permission' when !mac => ApkPhaseNeedsPermission(info),
          'started' when !mac => ApkPhaseInstalling(info),
          'ready' when mac => ApkPhaseReady(info),
          _ when mac => ApkPhaseFailed(info, 'It could not be put in place ($answer).'),
          _ => ApkPhaseFailed(info, 'The installer did not start ($answer).'),
        };
      });
    } catch (error) {
      _set(() => _apk = ApkPhaseFailed(info, failureText(error)));
    }
  }

  /// The Mac's "Restart to update": the version [installApk] put in place is swapped in, and the app quits and opens
  /// again as it (UpdatesChannel.swift `restart`). Not while a meeting or a take records, which quitting would end.
  Future<void> restart() async {
    final phase = _apk;
    final phone = _phone;
    if (phase is! ApkPhaseReady || phone is! RestartingUpdatePhone) return;
    final info = phase.info;
    final busy = _busy;
    if (busy != null) {
      _set(() => _apk = ApkPhaseFailed(info, busy));
      return;
    }
    _set(() => _apk = ApkPhaseRestarting(info));
    final answer = await phone.restart();
    if (answer != 'restarting') _set(() => _apk = ApkPhaseFailed(info, 'Ghost.md could not restart into it ($answer).'));
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
    final target = File('${dir.path}/ghost-${info.versionCode}.${kind.extension}');
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
      if (!await matches(part)) throw UpdateFailure('the ${kind.file} did not match its published checksum');
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
      throw UpdateFailure('cannot place the ${kind.file}: ${failureText(error)}');
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
