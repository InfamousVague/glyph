/// The packs on this device (Matt, 2026-11-20: "I would like users to be able to develop and submit their own plugins
/// to our plugin marketplace", and "a developer setting for users to be able to manually upload plugins for
/// development testing"): those installed from the Marketplace, each checked again against its approval at every
/// load, and those loaded in Settings › Developer, unreviewed and on only while developer mode is. The disk is what is
/// installed; the app's choices hold only small indexes of it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app_state.dart';
import '../../desktop/store.dart' show DeskStore;
import '../plugin.dart';
import '../registry.dart';
import 'format.dart';
import 'manifest.dart';
import 'pack_plugin.dart';
import 'review.dart';
import 'review_keys.dart';

/// This device's plugins folder when none is given: on Android the app's own files, on a computer or an iPhone the
/// folder lib/desktop/main.dart keeps everything else in (GHOST_DESK_DIR's where set). Under flutter test, a fresh
/// folder in the system's temp, never the installed app's.
Directory pluginsRoot() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return Directory.systemTemp.createTempSync('ghost-plugins-');
  if (Platform.isAndroid) return Directory('${Directory.systemTemp.parent.path}/files/plugins');
  final dir = Platform.environment['GHOST_DESK_DIR'];
  final base = dir == null || dir.isEmpty ? DeskStore.defaultDir() : Directory(dir);
  return Directory('${base.path}${Platform.pathSeparator}plugins');
}

/// Where a pack in development came from, so it can be loaded again.
class DevSource {
  const DevSource(this.kind, {this.url, this.path, this.name});
  final String kind;                // 'file', 'paste', 'link', 'api'
  final String? url;                // a link's address
  final String? path;               // a computer's file; Android's picked copies are not kept
  final String? name;               // the file's name, for the row

  static const kinds = ['file', 'paste', 'link', 'api'];

  /// A link, or a file with a path on a Mac or Windows.
  bool get reloadable => (kind == 'link' && url != null) || (kind == 'file' && path != null && (Platform.isMacOS || Platform.isWindows));

  Map<String, Object?> toJson() => {'kind': kind, if (url != null) 'url': url, if (path != null) 'path': path, if (name != null) 'name': name};

  /// FormatException where it isn't one of [kinds].
  factory DevSource.fromJson(Map j) {
    final kind = j['kind'];
    if (kind is! String || !kinds.contains(kind)) throw const FormatException('Not a plugin\'s source');
    String? text(String key) => j[key] is String ? j[key] as String : null;
    return DevSource(kind, url: text('url'), path: text('path'), name: text('name'));
  }
}

/// Something a pack in development threw, or was refused, while it ran.
class DevError {
  const DevError(this.at, this.line);
  final DateTime at;
  final String line;                // cut to 300
}

/// A pack installed from the Marketplace, as it stands on this device: running, or why not.
class InstalledPack {
  const InstalledPack({required this.id, required this.version, required this.sha256, required this.installedAt, this.approval, this.pack, this.plugin, this.running = false, this.revoked, this.problem, this.listing = const {}});
  final String id, version, sha256;
  final DateTime installedAt;
  final PackApproval? approval;
  final PluginPack? pack;           // null where it could not be read or parsed
  final PackPlugin? plugin;         // whenever it parsed, in the registry or not
  final bool running;               // in the registry now
  final PackRevocation? revoked;
  final String? problem;            // null, or: bad_approval, untrusted_key, invalid, needs_newer_app, revoked, io, id_taken, too_many_packs, paused
  final Map<String, Object?> listing;   // listing.json
}

/// A pack loaded in Settings › Developer, as it stands on this device.
class DevPack {
  const DevPack({required this.id, required this.source, required this.loadedAt, this.pack, this.plugin, this.issues = const [], this.errors = const [], this.agreed, this.problem, bool running = false}) : _running = running;
  final String id;
  final DevSource source;
  final DateTime loadedAt;
  final PluginPack? pack;           // null when the copy on disk does not parse
  final PackPlugin? plugin;         // the copy that is running, which may be an older one (below)
  final List<PackIssue> issues;     // of the newest copy
  final List<DevError> errors;      // newest first, at most 20: what it threw or was refused while running
  final List<String>? agreed;       // the packReaches and packAdds lines agreed to (D.5), null until it was first switched on
  final String? problem;            // null, or: invalid, new_copy_invalid, id_installed, dev_mode_off, paused, too_many_packs, needs_consent
  final bool _running;

  /// [plugin] is in the registry now.
  bool get running => plugin != null && _running;

  /// It can do something now that the person hasn't agreed to: some line of what it reaches or adds isn't among
  /// [agreed], or it was never agreed to at all.
  bool get needsConsent {
    final pack = this.pack;
    if (pack == null) return false;
    final agreed = this.agreed;
    if (agreed == null) return true;
    return consentLines(pack).any((line) => !agreed.contains(line));
  }

  /// What the person agrees to for [pack], a line each as text: its privacy card's lines, then what it adds.
  static List<String> consentLines(PluginPack pack) => [
        for (final r in packReaches(pack)) r.hint == null ? r.label : '${r.label}: ${r.hint}',
        ...packAdds(pack),
      ];
}

/// What installing, loading or removing a pack came to.
class PackOutcome {
  const PackOutcome.ok(GhostPlugin this.plugin, {this.issues = const [], this.needsConsent = false}) : ok = true, code = null, message = '';
  const PackOutcome.failed(String this.code, this.message, {this.issues = const []}) : ok = false, plugin = null, needsConsent = false;
  final bool ok;
  final String? code;
  final String message;             // plain words for a toast or a row's hint
  final List<PackIssue> issues;
  final GhostPlugin? plugin;
  final bool needsConsent;          // loaded, but left off until the person agrees to what it can do now (D.5, D.7)
}

/// Something for the shell to toast (D.1).
class PackNotice {
  const PackNotice(this.kind, this.packId, this.words);
  final String kind;                // 'withdrawn', 'paused', 'api_loaded'; MarketState's own are 'submission' (D.11)
  final String packId;
  final String words;               // what the toast says (D.5, A.10.9, B.14)
}

class InstalledPlugins extends ChangeNotifier {
  /// Nothing is read or written here: [load] reads the folder, and a test puts its own here (a temp [root], its own
  /// [reviewKeys]) without touching the installed app's.
  InstalledPlugins({Directory? root, PluginRegistry? registry, List<String>? reviewKeys, bool? storeAllowed, bool? devAllowed, HttpClient Function()? http, Future<bool> Function(String url)? openLink, DateTime Function()? now})
      : _root = root,
        _reviewKeys = reviewKeys,
        _storeAllowed = storeAllowed,
        _devAllowed = devAllowed;

  static InstalledPlugins instance = InstalledPlugins();      // no I/O in the constructor; a test puts its own here and the old one back in tearDown

  Directory? _root;
  final List<String>? _reviewKeys;
  final bool? _storeAllowed;
  final bool? _devAllowed;
  final _notices = StreamController<PackNotice>.broadcast();

  /// The plugins folder: the one given, else this device's ([pluginsRoot]), worked out when first asked.
  Directory get root => _root ??= pluginsRoot();

  /// The review keys whose approvals install: the ones given (a test's), else this build's.
  List<String> get reviewKeys => _reviewKeys ?? marketReviewKeys;

  /// Pinned keys retired by a verified PackRetirement.
  Set<String> get retiredKeys => const {};

  /// No store packs at all on an iPhone, whose App Store reads a storefront of other developers' features against its
  /// rules.
  bool get storeAllowed => _storeAllowed ?? !Platform.isIOS;

  /// No plugins in development in an App Store build.
  bool get devAllowed => _devAllowed ?? !packAppStoreBuild;

  /// What the shell toasts: a pack withdrawn, paused, or loaded from the API.
  Stream<PackNotice> get notices => _notices.stream;

  Future<void> load(AppState app, {required String appVersion, Duration within = const Duration(seconds: 3)}) async => throw UnimplementedError(_later);
  bool get loaded => false;
  List<InstalledPack> get store => const [];                   // in install order
  List<DevPack> get dev => const [];                           // in load order
  InstalledPack? storeOf(String packId) => store.where((p) => p.id == packId).firstOrNull;
  DevPack? devOf(String packId) => dev.where((p) => p.id == packId).firstOrNull;

  Future<PackOutcome> installReviewed(Uint8List bytes, PackApproval approval, {Map<String, Object?> listing = const {}, bool on = true}) async => throw UnimplementedError(_later);
  Future<PackOutcome> removeStore(String packId, {bool forget = false}) async => throw UnimplementedError(_later);
  Future<PackOutcome> loadDev(List<int> bytes, DevSource source, {bool on = false}) async => throw UnimplementedError(_later);
  Future<PackOutcome> loadDevFromLink(Uri url, {bool on = false}) async => throw UnimplementedError(_later);
  Future<PackOutcome> reloadDev(String packId) async => throw UnimplementedError(_later);
  Future<PackOutcome> removeDev(String packId) async => throw UnimplementedError(_later);

  /// The person agreed on D.5's sheet: keep its lines, switch it on.
  Future<PackOutcome> agreeDev(String packId) async => throw UnimplementedError(_later);

  /// It has been agreed to with every line it has now.
  bool mayTurnOnDev(String packId) {
    final d = devOf(packId);
    return d != null && d.pack != null && !d.needsConsent;
  }

  void unpause(String packId) {
    if (storeOf(packId)?.plugin == null && devOf(packId)?.plugin == null) return;
    throw UnimplementedError(_later);
  }

  /// GET /market/revoked's body: how many installed packs it newly withdrew.
  Future<int> takeRevocations(Object? json) async => throw UnimplementedError(_later);
  List<PackRevocation> get revocations => const [];
  bool isRevoked(String sha256) => revocations.any((r) => r.sha256 == sha256);
}

const String _later = 'Installing and loading packs come with the Marketplace\'s runtime (lib/plugins/pack/installed.dart).';
