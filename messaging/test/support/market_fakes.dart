import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ghost_messaging/art/app_icon.dart';
import 'package:ghost_messaging/art/lucide.g.dart';
import 'package:ghost_messaging/market/market_api.dart';
import 'package:ghost_messaging/market/market_models.dart';
import 'package:ghost_messaging/market/market_state.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/plugins/pack/pack.dart';
import 'package:ghost_messaging/plugins/plugin.dart';
import 'package:ghost_messaging/plugins/registry.dart';

/// The Marketplace made up for the tests (test/market_*.dart, test/marketplace_test.dart, test/dev_plugins_settings_test
/// .dart): packs like the format's examples (SPEC A.15), a relay answered from memory, and the device's installed and
/// in-development packs held in memory. The runtime's own checks (parsing, verifying, installing) are stubs until it
/// lands (lib/plugins/pack), so these stand in for them: a parse that knows the packs by their bytes' SHA-256, a
/// verify that believes an approval signed "good", and an installer that puts a plugin in the registry.

/// The 64 px glyph Bills carries (SPEC A.15): a PNG of pixels alone.
final Uint8List billsIcon = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAaklEQVR42u3awQ0AIAgAMfZfGoeQEMHeAMb0AT6MkCRJkq7K5gAAAPA2wLTzAQAAAAAAAAD1F6x68AAAAMAQBAAAAABbAAAAAIYgAAAAAGzbAgAAADAEAQAAAADAFgC/xAAA+AtAkiRJwzpcxpX3TIHg+gAAAABJRU5ErkJggg==');

/// A pack shaped as A.15's Bills is once parsed: a Bills tab with the amount on its row, a Receipts kind that can mark
/// them read as they come, a button to copy the amount, two settings of its own.
PluginPack billsPack({String id = 'bills', String name = 'Bills', String version = '1.0.0', String? developer = 'maya', Uint8List? icon, List<String> labels = const ['bills', 'money', 'sorting'], List<String> shots = const [], String? whatsNew, String? minApp, String? support = 'https://example.com/plugins/bills', String shelf = 'organise', String hue = 'amber', List<String> links = const [], Set<PackPermission> permissions = const {PackPermission.sort, PackPermission.copy, PackPermission.markRead}}) {
  final json = <String, Object?>{
    'format': packFormat, 'id': id, 'version': version, 'name': name, 'tagline': 'Bills and payment reminders in a tab of their own',
    'description': 'Texts from companies about a bill go to a Bills tab, with the amount large on the row and a press to copy it.',
    'symbol': 'calculator', 'hue': hue, 'shelf': shelf, 'labels': labels, 'permissions': [for (final p in permissions) p.wire],
    'developer': ?developer, 'support': ?support, 'whatsNew': ?whatsNew, 'minApp': ?minApp, 'shots': shots, 'links': links,
    'rules': {'sections': [{'key': 'bills'}]},
  };
  return PluginPack(
    id: id,
    version: version,
    name: name,
    tagline: 'Bills and payment reminders in a tab of their own',
    description: 'Texts from companies about a bill go to a Bills tab, with the amount large on the row and a press to copy it.',
    symbol: 'calculator',
    hue: hue,
    shelf: shelf,
    icon: icon,
    labels: labels,
    permissions: permissions,
    links: links,
    shots: shots,
    developer: developer,
    support: support,
    whatsNew: whatsNew,
    minApp: minApp,
    settings: const [
      PackSetting(type: 'toggle', key: 'autoread', label: 'Mark receipts as read', hint: 'As they come: texts that say a payment went through.', icon: 'check-check'),
      PackSetting(type: 'words', key: 'extra', label: 'More words for bills', hint: 'A text with any of these goes to Bills too.', placeholder: 'council tax, water rates'),
    ],
    rules: PackRules(
      sections: const [
        PackSection(key: 'bills', label: 'Bills', icon: 'calculator', kind: 'tab', takes: PackWhen(tagged: ['bill'], untagged: ['paid']), row: PackRow(value: '{tag:bill}', caption: 'A bill', end: 'copyamount')),
        PackSection(key: 'receipts', label: 'Receipts', icon: 'check-check', kind: 'filter', takes: PackWhen(tagged: ['paid'])),
      ],
      actions: [
        const PackAction(id: 'copyamount', label: 'Copy the amount', icon: 'copy', verb: 'copy', slots: ['row', 'list.conversation.menu', 'conversation.message.menu'], when: PackWhen(tagged: ['bill']), text: '{tag:bill}', say: 'Amount copied'),
        if (links.isNotEmpty) PackAction(id: 'open', label: 'Open the page', icon: 'link', verb: 'link', slots: const ['conversation.header'], url: links.first),
      ],
      incoming: const [PackIncoming(section: 'receipts', verbs: ['markread'], setting: 'autoread')],
    ),
    json: json,
  );
}

/// [pack]'s bytes as the store would hold them: canonical, so each pack has a SHA-256 of its own.
Uint8List packBytes(PluginPack pack) => canonicalBytes(pack.json);

/// A test's review key, and its signer: approvals signed "good" by it verify in [FakeChecks.verify].
final NetKeys reviewKeys = NetKeys.generate();
final String reviewKey = base64Encode(reviewKeys.public);
final NetSigner devSigner = KeysSigner(NetKeys.generate());

/// The catalog's entry for [pack], approved by [key] (the test's review key where not given).
CatalogEntry entryOf(PluginPack pack, {String? key, String sig = 'good', int updatedAt = 1763600000000, String? sha, String? approvedId}) {
  final sha256 = sha ?? sha256Hex(packBytes(pack));
  return CatalogEntry(id: pack.id, version: pack.version, sha256: sha256, size: packBytes(pack).length, approval: PackApproval(plugin: approvedId ?? pack.id, version: pack.version, sha256: sha256, key: key ?? reviewKey, sig: sig, at: 0), listedAt: updatedAt, updatedAt: updatedAt);
}

/// The runtime's checks, as the tests have them: a parse that knows the packs given it by their bytes, and a verify
/// that believes "good" signatures, counting what it was asked.
class FakeChecks {
  final Map<String, PluginPack> _packs = {};
  int verified = 0;

  void know(PluginPack pack) => _packs[sha256Hex(packBytes(pack))] = pack;

  PackParse parse(List<int> bytes, {required String appVersion, bool checkMinApp = true}) {
    final sha = sha256Hex(bytes);
    final pack = _packs[sha];
    return pack == null ? const PackParse(issues: [PackIssue('bad_json', '', 'Not a pack these tests know.')]) : PackParse(pack: pack, canonical: Uint8List.fromList(bytes), sha256: sha);
  }

  Future<List<bool>> verify(List<ApprovalCheck> checks) async {
    verified += checks.length;
    return [for (final c in checks) c.approval.sig == 'good' && c.keys.contains(c.approval.key) && !c.retired.contains(c.approval.key)];
  }
}

/// One request the relay was asked.
typedef FakeRequest = ({String method, Uri url, Map<String, String> headers, List<int> body});

/// The relay, answered from memory: the catalog, the revoked list, the packages and screenshots by SHA-256, and
/// whatever a test sets in [answers] by path. Every request is kept in [asked], and how many were in flight at once.
class FakeRelay {
  final asked = <FakeRequest>[];
  Catalog catalog = const Catalog();
  final packages = <String, Uint8List>{};
  final shots = <String, Uint8List>{};
  Map<String, Object?> revoked = const {'ok': true, 'v': 1, 'at': 0, 'revoked': [], 'retired': []};
  final answers = <String, ({int status, Object? body})>{};

  /// A catalog's bytes in place of the one above (a test's too large one).
  Uint8List? catalogBytes;
  int inFlight = 0, mostInFlight = 0;

  /// Unreachable: every request fails as a socket would.
  bool down = false;

  void list(PluginPack pack, {CatalogEntry? entry}) {
    final e = entry ?? entryOf(pack);
    catalog = Catalog(plugins: [...catalog.plugins.where((p) => p.id != e.id), e]);
    packages[e.sha256] = packBytes(pack);
  }

  static ({int status, Map<String, String> headers, Uint8List body}) _json(int status, Object? body) => (status: status, headers: const {'content-type': 'application/json'}, body: utf8.encode(jsonEncode(body)));

  Future<({int status, Map<String, String> headers, Uint8List body})> call(String method, Uri url, Map<String, String> headers, List<int> body, {required int most}) async {
    asked.add((method: method, url: url, headers: headers, body: body));
    if (down) throw const SocketException('down');
    final path = url.path;
    final own = answers['$method $path'];
    if (own != null) return _json(own.status, own.body);
    if (path.endsWith('/market/catalog')) {
      if (catalogBytes != null) return (status: 200, headers: const <String, String>{}, body: catalogBytes!);
      return _json(200, {'ok': true, ...catalog.toJson()});
    }
    if (path.endsWith('/market/revoked')) return _json(200, revoked);
    final package = RegExp(r'/market/packages/([0-9a-f]{64})$').firstMatch(path);
    if (package != null) {
      inFlight++;
      if (inFlight > mostInFlight) mostInFlight = inFlight;
      // A turn of the event loop, so the other fetches can start before this one ends.
      await Future<void>.delayed(Duration.zero);
      inFlight--;
      final bytes = packages[package.group(1)];
      return bytes == null ? _json(404, {'ok': false, 'error': 'not_found', 'message': 'There\'s nothing here by that name.'}) : (status: 200, headers: const <String, String>{}, body: bytes);
    }
    final shot = RegExp(r'/market/shots/([0-9a-f]{64})$').firstMatch(path);
    if (shot != null) {
      final bytes = shots[shot.group(1)];
      return bytes == null ? _json(404, {'ok': false, 'error': 'not_found', 'message': 'There\'s nothing here by that name.'}) : (status: 200, headers: const <String, String>{}, body: bytes);
    }
    if (path.endsWith('/market/report')) return _json(201, {'ok': true, 'id': '0123456789abcdef'});
    if (path.endsWith('/market/mine')) return _json(200, {'ok': true, 'blocked': false, 'submissions': [], 'plugins': []});
    return _json(404, {'ok': false, 'error': 'not_found', 'message': 'There\'s nothing here by that name.'});
  }

  /// The paths asked for, in order.
  List<String> get paths => [for (final r in asked) '${r.method} ${r.url}'];
}

/// A pack running in the registry, as the runtime's PackPlugin would be: drawn from its pack, its tab and kind as the
/// registry's sections, nothing it does to texts.
class FakePackPlugin extends GhostPlugin {
  FakePackPlugin(this.pack, {this.source = PluginSource.reviewed});
  final PluginPack pack;
  @override
  final PluginSource source;

  @override
  String get id => registryIdOf(pack.id);
  @override
  String get name => pack.name;
  @override
  String get description => pack.description;
  @override
  String get tagline => pack.tagline;
  @override
  String get hue => pack.hue;
  @override
  PluginShelf get shelf => PluginShelf.values.byName(pack.shelf);
  @override
  LucideIcon get icon => Lucide.all[pack.symbol] ?? Lucide.puzzle;
  @override
  Uint8List? get iconPng => pack.icon;
  @override
  List<String> get labels => pack.labels;
  @override
  String? get developer => pack.developer;
  @override
  String? get version => pack.version;
  @override
  bool get onByDefault => false;
  @override
  late final List<PluginReach> reaches = packReaches(pack);
  @override
  late final List<String> adds = packAdds(pack);
  @override
  late final List<ListSection> sections = [
    for (final s in pack.rules.sections) ListSection(id: sectionIdOf(pack.id, s.key), label: s.label, icon: Lucide.all[s.icon] ?? Lucide.puzzle, filter: s.kind == 'filter', takes: (f, t, p) => false),
  ];
  @override
  late final List<PluginSetting> settings = [
    for (final s in pack.settings)
      if (s.type == 'toggle') PluginSetting.toggle(key: s.key!, label: s.label, hint: s.hint, fallback: s.fallback) else if (s.type == 'words') PluginSetting.words(key: s.key!, label: s.label, hint: s.hint, placeholder: s.placeholder),
  ];
}

/// The device's packs held in memory, the registry's plugins changed as the runtime would change them.
class FakeInstalled extends InstalledPlugins {
  FakeInstalled({required Directory root, required this.checks, PluginRegistry? registry, List<String>? reviewKeys, bool storeAllowed = true, bool devAllowed = true})
      : _registry = registry,
        super(root: root, reviewKeys: reviewKeys ?? [reviewKey], storeAllowed: storeAllowed, devAllowed: devAllowed);

  /// How bytes are read as packs: the test's.
  final FakeChecks checks;

  /// Where a switch is written as the runtime would write it: the test's app.
  PluginStore? switches;

  final PluginRegistry? _registry;
  PluginRegistry get registry => _registry ?? PluginRegistry.instance;

  final stores = <InstalledPack>[];
  final devs = <DevPack>[];
  final revokedShas = <String>{};
  final took = <Object?>[];
  final installs = <({Uint8List bytes, PackApproval approval, Map<String, Object?> listing, bool on})>[];
  final calls = <String>[];

  /// What the next installReviewed answers where it isn't ok (a test's refusal).
  PackOutcome? refuse;

  /// The dev packs agreed to, and what the next load answers.
  final agreed = <String>{};
  PackOutcome? nextLoad;

  @override
  List<InstalledPack> get store => List.unmodifiable(stores);
  @override
  List<DevPack> get dev => List.unmodifiable(devs);
  @override
  bool isRevoked(String sha256) => revokedShas.contains(sha256);
  @override
  bool mayTurnOnDev(String packId) => agreed.contains(packId);

  void tell() => notifyListeners();

  /// A store pack on this device, running in the registry (switched [on]) or stuck with [problem].
  void putStore(PluginPack pack, {bool on = true, String? problem, bool running = true}) {
    final plugin = FakePackPlugin(pack);
    stores.removeWhere((p) => p.id == pack.id);
    if (running) {
      registry.uninstall(plugin.id);
      registry.install(plugin);
      switches?.write(PluginRegistry.switchKey(plugin), on ? 'on' : 'off');
    }
    stores.add(InstalledPack(id: pack.id, version: pack.version, sha256: sha256Hex(packBytes(pack)), installedAt: DateTime(2026, 11, 20), pack: pack, running: running, problem: problem, listing: {'name': pack.name, 'tagline': pack.tagline, 'hue': pack.hue, 'symbol': pack.symbol}));
    tell();
  }

  /// A dev pack loaded, running in the registry.
  void putDev(PluginPack? pack, {String? id, DevSource source = const DevSource('paste'), List<PackIssue> issues = const [], List<DevError> errors = const [], bool running = true, String? problem}) {
    final packId = pack?.id ?? id!;
    devs.removeWhere((d) => d.id == packId);
    if (pack != null && running) {
      registry.uninstall(registryIdOf(packId));
      registry.install(FakePackPlugin(pack, source: PluginSource.dev));
    }
    devs.add(DevPack(id: packId, source: source, loadedAt: DateTime(2026, 11, 20, 9), pack: pack, issues: issues, errors: errors, agreed: agreed.contains(packId) ? DevPack.consentLines(pack!) : null, problem: problem, running: running && pack != null));
    tell();
  }

  @override
  Future<PackOutcome> installReviewed(Uint8List bytes, PackApproval approval, {Map<String, Object?> listing = const {}, bool on = true}) async {
    installs.add((bytes: bytes, approval: approval, listing: listing, on: on));
    final refused = refuse;
    if (refused != null) return refused;
    final pack = checks.parse(bytes, appVersion: '0.10.1').pack;
    if (pack == null) return const PackOutcome.failed('invalid', 'The plugin has problems.');
    final had = stores.where((p) => p.id == pack.id).firstOrNull;
    final wasOn = had != null && switches?.read('plugin_x${pack.id}') == 'on';
    putStore(pack, on: had == null ? on : (on || wasOn));
    return PackOutcome.ok(registry.plugins.firstWhere((p) => p.id == registryIdOf(pack.id)));
  }

  @override
  Future<PackOutcome> removeStore(String packId, {bool forget = false}) async {
    calls.add('removeStore $packId${forget ? ' forget' : ''}');
    stores.removeWhere((p) => p.id == packId);
    registry.uninstall(registryIdOf(packId));
    switches?.write('plugin_x$packId', '');
    tell();
    return PackOutcome.ok(FakePackPlugin(billsPack(id: packId)));
  }

  @override
  Future<PackOutcome> loadDev(List<int> bytes, DevSource source, {bool on = false}) async {
    calls.add('loadDev ${source.kind} ${utf8.decode(bytes, allowMalformed: true).length}');
    final out = nextLoad;
    if (out != null) return out;
    final pack = checks.parse(bytes, appVersion: '0.10.1').pack;
    if (pack == null) return const PackOutcome.failed('invalid', 'The plugin has problems.', issues: [PackIssue('bad_json', '', 'That isn\'t JSON.')]);
    putDev(pack, source: source);
    return PackOutcome.ok(registry.plugins.firstWhere((p) => p.id == registryIdOf(pack.id)), needsConsent: !agreed.contains(pack.id));
  }

  @override
  Future<PackOutcome> agreeDev(String packId) async {
    calls.add('agreeDev $packId');
    agreed.add(packId);
    final d = devs.where((d) => d.id == packId).firstOrNull;
    if (d?.pack != null) putDev(d!.pack, source: d.source);
    final plugin = registry.plugins.where((p) => p.id == registryIdOf(packId)).firstOrNull;
    if (plugin != null) switches?.write(PluginRegistry.switchKey(plugin), 'on');
    tell();
    return plugin == null ? const PackOutcome.failed('not_found', 'Not loaded.') : PackOutcome.ok(plugin);
  }

  @override
  Future<PackOutcome> reloadDev(String packId) async {
    calls.add('reloadDev $packId');
    final d = devs.where((d) => d.id == packId).first;
    return PackOutcome.ok(registry.plugins.firstWhere((p) => p.id == registryIdOf(d.id)));
  }

  @override
  Future<PackOutcome> removeDev(String packId) async {
    calls.add('removeDev $packId');
    devs.removeWhere((d) => d.id == packId);
    registry.uninstall(registryIdOf(packId));
    tell();
    return PackOutcome.ok(FakePackPlugin(billsPack(id: packId), source: PluginSource.dev));
  }

  @override
  void unpause(String packId) => calls.add('unpause $packId');

  @override
  Future<int> takeRevocations(Object? json) async {
    took.add(json);
    return 0;
  }
}

/// A MarketState over [relay], [installed] and [checks], its cache in [cache].
MarketState marketOver(FakeRelay relay, FakeInstalled installed, FakeChecks checks, Directory cache, {DateTime Function()? now, NetSigner? signer}) {
  final api = MarketApi(hubUrl: 'https://relay.test', signer: signer ?? devSigner, transport: relay.call, now: now);
  return MarketState(api: () => api, cache: cache, installed: installed, parse: checks.parse, verify: checks.verify, now: now, appVersion: '0.10.1');
}
