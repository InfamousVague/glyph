import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Mac app's own updates, so a copy that is installed is never installed again by hand (Matt, 2026-11-13:
/// "install the app on my mac and make sure it has OTA updates so we don't need to reinstall again").
///
/// - **What it reads** is `https://ghost-sms.com/mac.json`, which tool/release-mac.mjs puts beside the phone app's
///   `apk.json`: `{ version, versionCode, sha256, bytes, url }`, the url being the zip of the app beside it. A newer
///   one is one whose `versionCode` (the app's `CFBundleVersion`) is above this app's.
/// - **What it does** is download that zip into the app's own cache and hand it to the Mac's half
///   (macos/Runner/UpdatesChannel.swift), which holds it to the size and SHA-256 the description gives, unpacks it
///   beside the running app, and checks what came out is this app, newer, and signed by this app's own team. That
///   last check is what makes an update believed: nothing the server or the network says can stand in for Matt's
///   Developer ID.
/// - **When it is in place** the app says so ([MacUpdatePhase.ready]): Restart to update swaps it in and opens it,
///   and so does quitting the app, so the next launch is the new version either way.
/// - **Looked for** as the app opens and every six hours after, and from Settings when asked.
///
/// `GHOST_DESK_UPDATES` names another address to read (a local server, to walk an update through: the Mac's half
/// believes only what this app's team signed, wherever it came from), and `off` looks nowhere. With
/// `GHOST_DESK_UPDATE_RESTART=now` the app restarts into an update as soon as one is in place, so the whole of it
/// can be walked through with no hand on the app (docs/desktop.md, "Updating itself").

/// Where an installed Mac app reads of a newer one.
const macFeed = 'https://ghost-sms.com/mac.json';

/// A release, as its description gives it.
class MacRelease {
  const MacRelease({required this.version, required this.build, required this.sha256, required this.bytes, required this.url});
  final String version;

  /// The app's `CFBundleVersion`: what newer is asked of.
  final int build;
  final String sha256;
  final int bytes;
  final Uri url;

  /// The least and the most a zip of this app could be: a description outside them is not one.
  static const smallest = 1 << 20;
  static const largest = 500 << 20;

  /// Reads a description read from [feed]; null where it is not one: a field missing or of the wrong kind, a size
  /// no app is, or a zip somewhere other than beside the description.
  static MacRelease? parse(String text, Uri feed) {
    final Object? said;
    try {
      said = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (said is! Map) return null;
    final version = said['version'], build = said['versionCode'], sha256 = said['sha256'], bytes = said['bytes'], url = said['url'];
    if (version is! String || !RegExp(r'^\d+(\.\d+){1,3}$').hasMatch(version)) return null;
    if (build is! int || build <= 0) return null;
    if (sha256 is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) return null;
    if (bytes is! int || bytes < smallest || bytes > largest) return null;
    if (url is! String || url.isEmpty) return null;
    final Uri at;
    try {
      at = feed.resolve(url);
    } catch (_) {
      return null;
    }
    // The zip is beside its description: the same server, spoken to the same way.
    if (at.scheme != feed.scheme || at.host != feed.host || at.port != feed.port) return null;
    return MacRelease(version: version, build: build, sha256: sha256.toLowerCase(), bytes: bytes, url: at);
  }
}

/// The app as it is installed (UpdatesChannel.swift `installed`).
class InstalledMac {
  const InstalledMac({required this.version, required this.build, required this.dir, this.updated = false});
  final String version;
  final int build;

  /// Where a download is kept for the Mac's half to unpack.
  final String dir;

  /// This launch is the first of a version the app put in place itself.
  final bool updated;
}

/// The Mac's half (macos/Runner/UpdatesChannel.swift), or a test's own.
abstract class UpdateHost {
  /// The installed app, or null where there is no Mac half: then nothing is looked for.
  Future<InstalledMac?> installed();

  /// Hands over the downloaded zip: `ready` once it is unpacked and checked beside the app, `manual: <why>` where
  /// this copy cannot replace itself, or a reason it was refused.
  Future<String> install(String path, {required String sha256, required int bytes});

  /// Swaps the version in place for the running one and opens it: `restarting`, or why not.
  Future<String> restart();
}

class ChannelUpdateHost implements UpdateHost {
  const ChannelUpdateHost();
  static const _channel = MethodChannel('ghost_desktop/updates');

  @override
  Future<InstalledMac?> installed() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('installed');
      if (m == null) return null;
      return InstalledMac(
        version: (m['version'] as String?) ?? '',
        build: (m['versionCode'] as num?)?.toInt() ?? 0,
        dir: (m['dir'] as String?) ?? '',
        updated: m['updated'] == true,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String> install(String path, {required String sha256, required int bytes}) async {
    try {
      return await _channel.invokeMethod<String>('install', {'path': path, 'sha256': sha256, 'bytes': bytes}) ?? 'no answer';
    } on MissingPluginException {
      return 'no installer';
    }
  }

  @override
  Future<String> restart() async {
    try {
      return await _channel.invokeMethod<String>('restart') ?? 'no answer';
    } on MissingPluginException {
      return 'no installer';
    }
  }
}

enum MacUpdatePhase {
  /// Nothing newer, as far as is known.
  idle,
  checking,
  downloading,

  /// The new version is in place beside this one: a restart, or a quit, swaps it in.
  ready,
  restarting,

  /// There is a newer one and this copy cannot replace itself ([MacUpdates.problem] says why).
  manual,

  /// Looking, downloading or putting it in place did not work ([MacUpdates.problem]); it is tried again later.
  failed,
}

/// Looks for a newer Mac app, brings it down and has it put in place (the header).
class MacUpdates extends ChangeNotifier {
  MacUpdates({Uri? feed, UpdateHost? host, HttpClient Function()? client, this.every = const Duration(hours: 6), this.restartWhenReady = false})
      : feed = feed ?? Uri.parse(macFeed),
        _host = host ?? const ChannelUpdateHost(),
        _client = client ?? HttpClient.new;

  /// As it would stand with [installed] and a newer [release] at [phase]: for a picture of what the app says of it.
  @visibleForTesting
  MacUpdates.standing({required InstalledMac installed, required MacUpdatePhase phase, MacRelease? release, String? problem, UpdateHost? host})
      : feed = Uri.parse(macFeed),
        every = const Duration(hours: 6),
        restartWhenReady = false,
        _host = host ?? const ChannelUpdateHost(),
        _client = HttpClient.new {
    _installed = installed;
    _phase = phase;
    _release = release;
    _problem = problem;
    _checked = DateTime.now();
  }

  /// The updater for this run of the app: where `GHOST_DESK_UPDATES` says to look, or nowhere for `off`.
  static MacUpdates? fromEnvironment(Map<String, String> env) {
    final said = (env['GHOST_DESK_UPDATES'] ?? '').trim();
    if (said == 'off') return null;
    final feed = said.isEmpty ? null : Uri.tryParse(said);
    return MacUpdates(feed: feed != null && feed.hasScheme && feed.host.isNotEmpty ? feed : null, restartWhenReady: env['GHOST_DESK_UPDATE_RESTART'] == 'now');
  }

  final Uri feed;
  final Duration every;

  /// Restart into an update as soon as it is in place, with nobody asked (`GHOST_DESK_UPDATE_RESTART=now`).
  final bool restartWhenReady;
  final UpdateHost _host;
  final HttpClient Function() _client;
  Timer? _timer;
  bool _busy = false;

  InstalledMac? get installed => _installed;
  InstalledMac? _installed;
  MacUpdatePhase get phase => _phase;
  MacUpdatePhase _phase = MacUpdatePhase.idle;

  /// The newer version found, once one is.
  MacRelease? get release => _release;
  MacRelease? _release;

  /// How much of the download is here, 0 to 1.
  double get progress => _progress;
  double _progress = 0;

  /// Why it did not work, or why this copy cannot replace itself.
  String? get problem => _problem;
  String? _problem;

  /// When the release's description was last read.
  DateTime? get checked => _checked;
  DateTime? _checked;

  /// Asks the Mac what is installed, looks once, and goes on looking.
  Future<void> start() async {
    _installed = await _host.installed();
    if (_installed == null) return;
    notifyListeners();
    unawaited(check());
    _timer = Timer.periodic(every, (_) => check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _set(MacUpdatePhase phase, {String? problem}) {
    _phase = phase;
    _problem = problem;
    notifyListeners();
  }

  /// Looks for a newer version and, where there is one, brings it down and has it put in place.
  Future<void> check() async {
    final here = _installed;
    if (here == null || _busy) return;
    // One in place is not looked past, and one this copy cannot take is not fetched again each time.
    if (_phase == MacUpdatePhase.ready || _phase == MacUpdatePhase.restarting || _phase == MacUpdatePhase.manual) return;
    _busy = true;
    _set(MacUpdatePhase.checking);
    try {
      final found = await _read();
      _checked = DateTime.now();
      if (found == null || found.build <= here.build) {
        _release = null;
        _set(MacUpdatePhase.idle);
        return;
      }
      _release = found;
      _progress = 0;
      _set(MacUpdatePhase.downloading);
      final zip = await _fetch(found, here);
      final answer = await _host.install(zip.path, sha256: found.sha256, bytes: found.bytes);
      if (answer == 'ready') {
        _set(MacUpdatePhase.ready);
        if (restartWhenReady) unawaited(restart());
      } else if (answer.startsWith('manual: ')) {
        _set(MacUpdatePhase.manual, problem: answer.substring('manual: '.length));
      } else {
        _set(MacUpdatePhase.failed, problem: answer);
      }
    } catch (e) {
      _set(MacUpdatePhase.failed, problem: e is UpdateProblem ? e.words : 'The update could not be reached ($e)');
    } finally {
      _busy = false;
    }
  }

  /// Restart to update: the version in place is swapped in and opened.
  Future<void> restart() async {
    if (_phase != MacUpdatePhase.ready) return;
    _set(MacUpdatePhase.restarting);
    final answer = await _host.restart();
    if (answer != 'restarting') _set(MacUpdatePhase.failed, problem: answer);
  }

  /// The release's description; null where nothing has been published there (the server has no such file).
  Future<MacRelease?> _read() async {
    final client = _client()..connectionTimeout = const Duration(seconds: 15);
    try {
      // Read afresh each time: a description an hour old would hide a release.
      final request = await client.getUrl(feed.replace(queryParameters: {...feed.queryParameters, 't': '${DateTime.now().millisecondsSinceEpoch}'})).timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode == 404) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw UpdateProblem('${feed.host} answered ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 64 * 1024) throw const UpdateProblem('The release\'s description is too long to be one');
      }
      final found = MacRelease.parse(utf8.decode(bytes, allowMalformed: true), feed);
      if (found == null) throw const UpdateProblem('The release\'s description could not be read');
      return found;
    } finally {
      client.close(force: true);
    }
  }

  /// Brings the zip down into the app's own folder for it, which holds nothing else: what was there goes first.
  Future<File> _fetch(MacRelease release, InstalledMac here) async {
    final dir = Directory(here.dir);
    if (dir.existsSync()) {
      for (final old in dir.listSync()) {
        try {
          old.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    dir.createSync(recursive: true);
    final file = File('${dir.path}/ghost-messaging-mac-${release.build}.zip');
    final client = _client()..connectionTimeout = const Duration(seconds: 15);
    IOSink? out;
    try {
      final request = await client.getUrl(release.url).timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw UpdateProblem('${release.url.host} answered ${response.statusCode} for the download');
      }
      out = file.openWrite();
      var got = 0, said = 0.0;
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        got += chunk.length;
        if (got > release.bytes) throw const UpdateProblem('The download is larger than the release says');
        out.add(chunk);
        _progress = got / release.bytes;
        if (_progress - said >= 0.01) {
          said = _progress;
          notifyListeners();
        }
      }
      await out.flush();
      await out.close();
      out = null;
      if (got != release.bytes) throw const UpdateProblem('The download stopped before it was whole');
      _progress = 1;
      notifyListeners();
      return file;
    } catch (_) {
      try {
        await out?.close();
      } catch (_) {}
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}

/// Why an update did not come, in words for the person.
class UpdateProblem implements Exception {
  const UpdateProblem(this.words);
  final String words;

  @override
  String toString() => words;
}
