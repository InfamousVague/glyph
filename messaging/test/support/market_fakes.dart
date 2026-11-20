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
    final kept = store.answer(method, path, headers, body);
    if (kept != null) return kept.bytes != null ? (status: kept.status, headers: const <String, String>{}, body: kept.bytes!) : _json(kept.status, kept.body);
    return _json(404, {'ok': false, 'error': 'not_found', 'message': 'There\'s nothing here by that name.'});
  }

  /// The developers' and the reviewer's routes (8 to 21), answered from memory.
  final store = FakeMarketStore();

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

  /// Review keys retired by their own signature, as a test says (the runtime's are read from the revoked list).
  Set<String> retired = {};
  @override
  Set<String> get retiredKeys => retired;
  @override
  bool mayTurnOnDev(String packId) => agreed.contains(packId);

  void tell() => notifyListeners();

  /// A store pack on this device, running in the registry (switched [on]) or stuck with [problem].
  void putStore(PluginPack pack, {bool on = true, String? problem, bool running = true, PackRevocation? revoked}) {
    final plugin = FakePackPlugin(pack);
    stores.removeWhere((p) => p.id == pack.id);
    if (running) {
      registry.uninstall(plugin.id);
      registry.install(plugin);
      switches?.write(PluginRegistry.switchKey(plugin), on ? 'on' : 'off');
    }
    stores.add(InstalledPack(id: pack.id, version: pack.version, sha256: sha256Hex(packBytes(pack)), installedAt: DateTime(2026, 11, 20), pack: pack, running: running, problem: problem, revoked: revoked, listing: {'name': pack.name, 'tagline': pack.tagline, 'hue': pack.hue, 'symbol': pack.symbol}));
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


/// The Marketplace's submissions, plugins, reports and review as a relay would keep them (SPEC C.4 to C.6), in memory:
/// enough of the relay for the submission form, My submissions and the review screens to run against.
class FakeMarketStore {
  final submissions = <String, Map<String, Object?>>{};
  final plugins = <String, Map<String, Object?>>{};
  final reports = <String, Map<String, Object?>>{};
  final shotBytes = <String, Uint8List>{};

  /// What each decision, listing, revocation and block asked, in order.
  final decided = <Map<String, Object?>>[];

  /// Who sent the submissions, as the relay names them, and whether they're verified, blocked or signed in as the admin.
  String developerId = 'd' * 32;
  bool verified = true, blocked = false, admin = true;

  /// Who route 17 says took a plugin off: the developer from My submissions, the admin from the review.
  String unlistedBy = 'owner';

  /// What the next check (route 8 with `check: true`) and the next submit answer, where not ok.
  ({int status, Map<String, Object?> body})? checkRefusal, submitRefusal;

  /// What the next decision answers, where not ok (a `not_admin`, then the real answer).
  final decideRefusals = <({int status, Map<String, Object?> body})>[];
  int checks = 0;
  int _n = 0;
  int now = 1763600000000;

  static String _hex(int n, int width) => n.toRadixString(16).padLeft(width, '0');

  /// A submission put in place as if it had been sent: [package] the pack's canonical bytes.
  String put(Uint8List package, {String status = 'submitted', List<Uint8List> shots = const [], String notes = '', String list = 'now', List<Map<String, Object?>> reviewerNotes = const []}) {
    final pack = (jsonDecode(utf8.decode(package)) as Map).cast<String, Object?>();
    final sid = _hex(++_n, 24);
    final shas = <String>[];
    for (final b in shots) {
      final sha = sha256Hex(b);
      shotBytes[sha] = b;
      shas.add(sha);
    }
    submissions[sid] = {
      'sid': sid, 'plugin': pack['id'], 'version': pack['version'], 'sha256': sha256Hex(package), 'size': package.length, 'status': status,
      'name': pack['name'], 'tagline': pack['tagline'], 'description': pack['description'], 'symbol': pack['symbol'] ?? 'puzzle', 'hue': pack['hue'], 'shelf': pack['shelf'],
      'labels': pack['labels'] ?? const [], 'permissions': pack['permissions'] ?? const [], 'links': pack['links'] ?? const [], 'developer': pack['developer'], 'support': pack['support'], 'whatsNew': pack['whatsNew'], 'minApp': pack['minApp'],
      'submittedAt': now + _n, 'updatedAt': now + _n,
      'notes': [if (notes.isNotEmpty) {'at': now + _n, 'by': 'developer', 'text': notes, 'status': null}, ...reviewerNotes],
      'shots': [for (final sha in shas) {'sha256': sha, 'mime': 'image/png'}], 'list': list, 'listing': null, 'revoked': null,
      'package': base64Encode(package),
    };
    plugins.putIfAbsent(pack['id'] as String, () => {'id': pack['id'], 'listing': 'none', 'current': null, 'by': null, 'note': null, 'noteAt': null});
    if (status == 'approved') _approve(sid);
    return sid;
  }

  void _approve(String sid) {
    final s = submissions[sid]!;
    final p = plugins[s['plugin']]!;
    // The version before stops being current, and its listing with it.
    for (final other in submissions.values) {
      if (other['plugin'] == s['plugin'] && other['sid'] != sid) other['listing'] = null;
    }
    s['status'] = 'approved';
    final listed = s['list'] == 'now' && p['by'] != 'owner';
    s['listing'] = listed ? 'listed' : 'unlisted';
    p['current'] = s['version'];
    p['listing'] = listed ? 'listed' : 'unlisted';
    p['by'] = listed ? null : 'owner';
  }

  Map<String, Object?> _view(Map<String, Object?> s) => {for (final e in s.entries) if (e.key != 'package') e.key: e.value};

  Map<String, Object?> _row(Map<String, Object?> s) {
    final current = submissions.values.where((x) => x['plugin'] == s['plugin'] && x['listing'] != null && x['sid'] != s['sid']).firstOrNull;
    final had = {...?(current?['permissions'] as List?)?.cast<String>()};
    return {
      ..._view(s),
      'developerId': developerId, 'verified': verified, 'blocked': blocked,
      'isUpdate': current != null || (s['listing'] == null && plugins[s['plugin']]?['current'] != null && s['status'] != 'approved'),
      'newPermissions': current == null ? const <String>[] : [for (final p in (s['permissions'] as List).cast<String>()) if (!had.contains(p)) p],
      'again': submissions.values.any((x) => x['plugin'] == s['plugin'] && x['sid'] != s['sid'] && ((x['notes'] as List).any((n) => (n as Map)['by'] == 'reviewer'))),
    };
  }

  static const _notAdmin = {'ok': false, 'error': 'not_admin', 'message': 'Sign in on Settings › Admin again to do that.'};
  static const _notFound = {'ok': false, 'error': 'not_found', 'message': 'There\'s nothing here by that name.'};

  /// The answer to one request, or null where it isn't one of these routes.
  ({int status, Object? body, Uint8List? bytes})? answer(String method, String path, Map<String, String> headers, List<int> body) {
    ({int status, Object? body, Uint8List? bytes}) json(int status, Object? b) => (status: status, body: b, bytes: null);
    Map<String, Object?> read() => body.isEmpty ? const {} : (jsonDecode(utf8.decode(body)) as Map).cast<String, Object?>();
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty || parts.first != 'market') return null;
    final rest = parts.sublist(1);
    // Route 8: a check, or a submission.
    if (method == 'POST' && rest.length == 1 && rest[0] == 'submissions') {
      final j = read();
      if (j['check'] == true) {
        checks++;
        final r = checkRefusal;
        return r == null ? json(200, {'ok': true, 'checked': true}) : json(r.status, r.body);
      }
      final refused = submitRefusal;
      if (refused != null) return json(refused.status, refused.body);
      if (blocked) return json(403, {'ok': false, 'error': 'blocked', 'message': 'This account can\'t submit plugins.'});
      final package = base64Decode(j['package'] as String);
      final shots = <Uint8List>[];
      final keptShas = <String>[];
      for (final s in (j['shots'] as List? ?? const [])) {
        final m = s as Map;
        if (m['keep'] is String) {
          keptShas.add(m['keep'] as String);
        } else {
          shots.add(base64Decode(m['data'] as String));
        }
      }
      // Earlier open submissions of the plugin are replaced by this one.
      final id = (jsonDecode(utf8.decode(package)) as Map)['id'];
      for (final s in submissions.values) {
        if (s['plugin'] == id && (s['status'] == 'submitted' || s['status'] == 'in_review' || s['status'] == 'changes_requested')) s['status'] = 'superseded';
      }
      final sid = put(package, shots: shots, notes: '${j['notes'] ?? ''}', list: '${j['list'] ?? 'now'}');
      // Kept screenshots in the order the package names them.
      final names = ((jsonDecode(utf8.decode(package)) as Map)['shots'] as List? ?? const []).cast<String>();
      submissions[sid]!['shots'] = [for (final sha in names) if (shotBytes.containsKey(sha) || keptShas.contains(sha)) {'sha256': sha, 'mime': 'image/png'}];
      return json(201, {'ok': true, 'submission': _view(submissions[sid]!)});
    }
    if (method == 'GET' && rest.length == 1 && rest[0] == 'mine') {
      final mine = submissions.values.toList()..sort((a, b) => (b['submittedAt'] as int).compareTo(a['submittedAt'] as int));
      return json(200, {'ok': true, 'blocked': blocked, 'submissions': [for (final s in mine) _view(s)], 'plugins': plugins.values.toList()});
    }
    if (rest.length >= 2 && rest[0] == 'submissions') {
      final s = submissions[rest[1]];
      if (s == null) return json(404, _notFound);
      if (rest.length == 2 && method == 'GET') return json(200, {'ok': true, 'submission': _view(s)});
      if (rest.length == 2 && method == 'DELETE') {
        s['status'] = 'withdrawn';
        decided.add({'withdraw': s['sid']});
        return json(200, {'ok': true, 'submission': _view(s)});
      }
      if (rest.length == 3 && rest[2] == 'package') return (status: 200, body: null, bytes: base64Decode(s['package'] as String));
      if (rest.length == 4 && rest[2] == 'shots') {
        final n = int.tryParse(rest[3]) ?? -1;
        final shots = s['shots'] as List;
        if (n < 0 || n >= shots.length) return json(404, _notFound);
        final bytes = shotBytes[(shots[n] as Map)['sha256']];
        return bytes == null ? json(404, _notFound) : (status: 200, body: null, bytes: bytes);
      }
    }
    // The review: the admin's alone.
    final review = rest.isNotEmpty && (rest[0] == 'review' || rest[0] == 'reports' || rest[0] == 'developers' || (rest[0] == 'plugins' && rest.length == 3 && rest[2] == 'revoke'));
    if (review && !admin) return json(403, _notAdmin);
    if (method == 'GET' && rest.length == 1 && rest[0] == 'review') {
      final all = submissions.values.toList()..sort((a, b) => (a['submittedAt'] as int).compareTo(b['submittedAt'] as int));
      final open = [for (final s in all) if (s['status'] == 'submitted' || s['status'] == 'in_review' || s['status'] == 'changes_requested') _row(s)];
      final recent = [for (final s in all.reversed) if (!(s['status'] == 'submitted' || s['status'] == 'in_review' || s['status'] == 'changes_requested')) _row(s)];
      int count(String st) => all.where((s) => s['status'] == st).length;
      return json(200, {'ok': true, 'open': open, 'recent': recent, 'counts': {'submitted': count('submitted'), 'in_review': count('in_review'), 'changes_requested': count('changes_requested'), 'reports': reports.values.where((r) => r['done'] != true).length}});
    }
    if (rest.length == 2 && rest[0] == 'review') {
      final s = submissions[rest[1]];
      if (s == null) return json(404, _notFound);
      if (method == 'GET') {
        final current = submissions.values.where((x) => x['plugin'] == s['plugin'] && x['listing'] != null && x['sid'] != s['sid']).firstOrNull;
        final asked = (submissions.values.toList()..sort((a, b) => (b['submittedAt'] as int).compareTo(a['submittedAt'] as int)))
            .where((x) => x['plugin'] == s['plugin'] && x['sid'] != s['sid'] && (x['notes'] as List).any((n) => (n as Map)['by'] == 'reviewer'))
            .firstOrNull;
        return json(200, {
          'ok': true,
          'submission': _row(s),
          'package': s['package'],
          'previous': current == null ? null : {'version': current['version'], 'sha256': current['sha256'], 'package': current['package']},
          'asked': asked == null ? null : {'sid': asked['sid'], 'version': asked['version'], 'sha256': asked['sha256'], 'package': asked['package'], 'note': ((asked['notes'] as List).lastWhere((n) => (n as Map)['by'] == 'reviewer') as Map)['text'], 'status': asked['status']},
          'history': [for (final x in submissions.values) if (x['plugin'] == s['plugin'] && x['sid'] != s['sid']) _view(x)],
          'developer': {'id': developerId, 'username': s['developer'], 'blocked': blocked, 'plugins': plugins.length, 'submissions': submissions.length, 'firstAt': now},
        });
      }
      if (method == 'POST') {
        if (decideRefusals.isNotEmpty) {
          final r = decideRefusals.removeAt(0);
          decided.add({'refused': r.body['error'], ...read()});
          return json(r.status, r.body);
        }
        final d = read();
        decided.add({'sid': s['sid'], 'key': headers['x-ghost-key'], ...d});
        final decision = d['decision'];
        final note = d['note'];
        void noted(String status) => (s['notes'] as List).add({'at': now, 'by': 'reviewer', 'text': note ?? '', 'status': status});
        switch (decision) {
          case 'start':
            s['status'] = 'in_review';
          case 'approve':
            final a = d['approval'] as Map;
            if (a['key'] != headers['x-ghost-key'] || a['sha256'] != s['sha256'] || a['plugin'] != s['plugin'] || a['version'] != s['version']) return json(400, {'ok': false, 'error': 'bad_approval', 'message': 'The approval\'s signature or its words don\'t match this plugin.'});
            _approve(s['sid'] as String);
            for (final r in (d['revokes'] as List? ?? const [])) {
              final sha = (r as Map)['sha256'];
              for (final x in submissions.values) {
                if (x['sha256'] == sha) x['revoked'] = {'at': r['at'], 'why': r['why']};
              }
            }
            if (note is String && note.isNotEmpty) noted('approved');
          case 'changes' || 'reject':
            if (note is! String || note.isEmpty) return json(400, {'ok': false, 'error': 'bad_request', 'message': 'Something in that isn\'t right.'});
            s['status'] = decision == 'changes' ? 'changes_requested' : 'rejected';
            noted(s['status'] as String);
        }
        return json(200, {'ok': true, 'submission': _row(s)});
      }
    }
    if (method == 'POST' && rest.length == 3 && rest[0] == 'plugins') {
      final p = plugins[rest[1]];
      if (p == null) return json(404, _notFound);
      final d = read();
      decided.add({'plugin': rest[1], 'route': rest[2], ...d});
      if (rest[2] == 'listing') {
        final listed = d['listed'] == true;
        p['listing'] = listed ? 'listed' : 'unlisted';
        p['by'] = listed ? null : unlistedBy;
        p['note'] = d['note'];
        for (final s in submissions.values) {
          if (s['plugin'] == rest[1] && s['listing'] != null) s['listing'] = p['listing'];
        }
        return json(200, {'ok': true, 'plugin': p});
      }
      if (rest[2] == 'revoke') {
        for (final s in submissions.values) {
          if (s['sha256'] == d['sha256']) s['revoked'] = {'at': d['at'], 'why': d['why']};
        }
        return json(200, {'ok': true, 'revoked': d, 'plugin': p});
      }
    }
    if (method == 'GET' && rest.length == 1 && rest[0] == 'reports') return json(200, {'ok': true, 'reports': reports.values.toList()});
    if (method == 'POST' && rest.length == 2 && rest[0] == 'reports') {
      final r = reports[rest[1]];
      if (r == null) return json(404, _notFound);
      r['done'] = true;
      r['doneAt'] = now;
      decided.add({'resolved': rest[1]});
      return json(200, {'ok': true});
    }
    if (method == 'POST' && rest.length == 3 && rest[0] == 'developers' && rest[2] == 'block') {
      final d = read();
      decided.add({'block': rest[1], ...d});
      blocked = d['blocked'] == true;
      return json(200, {'ok': true, 'developer': {'id': rest[1], 'username': 'maya', 'blocked': blocked, 'plugins': plugins.length, 'submissions': submissions.length, 'firstAt': now}});
    }
    return null;
  }
}

/// [pack] as a file a developer would load: its JSON made canonical, with [change] made to it first.
Uint8List packFile(Map<String, Object?> json, [void Function(Map<String, Object?> json)? change]) {
  final copy = (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>();
  change?.call(copy);
  return canonicalBytes(copy);
}

/// The docs' Bills (test/fixtures/packs/bills.ghostplugin, SPEC A.15) as decoded JSON: the example's id is refused for a
/// submission, so the tests give it one of their own.
Map<String, Object?> billsJson({String id = 'mybills'}) {
  final j = (jsonDecode(File('test/fixtures/packs/bills.ghostplugin').readAsStringSync()) as Map).cast<String, Object?>();
  j['id'] = id;
  return j;
}
