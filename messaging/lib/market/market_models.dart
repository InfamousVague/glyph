/// What the Marketplace on the relay (relay/lib/market.dart) says and is sent, as Dart (Matt, 2026-11-20: "I would like
/// users to be able to develop and submit their own plugins to our plugin marketplace and I'd like to be able to verify
/// them for the store through a review process"). Each `fromJson` takes what it knows and leaves the rest, so a newer
/// relay's extra fields never break an older app; each `toJson` is what is sent.
///
/// Nothing the catalog says is ever drawn: a listing's name, icon and permissions come from its package once the app
/// has checked it (market_state.dart). The submission shapes are the developer's own words back to them.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../plugins/pack/pack.dart' show PackApproval, PackRevocation, PackRetirement;

String _text(Object? v, [String or = '']) => v is String ? v : or;
String? _maybe(Object? v) => v is String ? v : null;
int _int(Object? v, [int or = 0]) => v is int ? v : (v is num ? v.toInt() : or);
int? _maybeInt(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
List<String> _texts(Object? v) => v is List ? [for (final x in v) if (x is String) x] : const [];
List<Map> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) x] : const [];

/// What the Marketplace is (route 1): its version, the format it takes, whether it is open, its limits and words.
class MarketInfo {
  const MarketInfo({this.market = 1, this.format = '', this.open = false, this.limits = const {}, this.labels = const [], this.shelves = const [], this.hues = const [], this.permissions = const []});
  final int market;
  final String format;
  final bool open;
  final Map<String, int> limits;
  final List<String> labels, shelves, hues, permissions;

  factory MarketInfo.fromJson(Map j) => MarketInfo(
        market: _int(j['market'], 1),
        format: _text(j['format']),
        open: j['open'] == true,
        limits: {for (final e in (j['limits'] is Map ? j['limits'] as Map : const {}).entries) if (e.key is String && e.value is int) e.key as String: e.value as int},
        labels: _texts(j['labels']),
        shelves: _texts(j['shelves']),
        hues: _texts(j['hues']),
        permissions: _texts(j['permissions']),
      );

  Map<String, Object?> toJson() => {'market': market, 'format': format, 'open': open, 'limits': limits, 'labels': labels, 'shelves': shelves, 'hues': hues, 'permissions': permissions};
}

/// One listed plugin, its current version: only what its approval covers, or what nobody draws.
class CatalogEntry {
  const CatalogEntry({required this.id, required this.version, required this.sha256, this.size = 0, required this.approval, this.listedAt, this.updatedAt = 0});
  final String id, version, sha256;
  final int size;
  final PackApproval approval;
  final int? listedAt;
  final int updatedAt;

  /// FormatException where it isn't an entry with an approval.
  factory CatalogEntry.fromJson(Map j) {
    final id = j['id'], version = j['version'], sha = j['sha256'], approval = j['approval'];
    if (id is! String || version is! String || sha is! String || approval is! Map) throw const FormatException('Not a catalog entry');
    return CatalogEntry(id: id, version: version, sha256: sha, size: _int(j['size']), approval: PackApproval.fromJson(approval), listedAt: _maybeInt(j['listedAt']), updatedAt: _int(j['updatedAt']));
  }

  Map<String, Object?> toJson() => {'id': id, 'version': version, 'sha256': sha256, 'size': size, 'approval': approval.toJson(), 'listedAt': listedAt, 'updatedAt': updatedAt};
}

/// The catalog (route 2): every listed plugin, newest change first, and the ETag it came with.
class Catalog {
  const Catalog({this.v = 1, this.at = 0, this.plugins = const [], this.etag});
  final int v;
  final int at;
  final List<CatalogEntry> plugins;

  /// The relay's ETag for these bytes, to ask with If-None-Match next time.
  final String? etag;

  /// Entries that don't read are left out, so one broken entry can't hide the rest.
  factory Catalog.fromJson(Map j, {String? etag}) {
    final plugins = <CatalogEntry>[];
    for (final m in _maps(j['plugins'])) {
      try {
        plugins.add(CatalogEntry.fromJson(m));
      } on FormatException {
        // Left out.
      }
    }
    return Catalog(v: _int(j['v'], 1), at: _int(j['at']), plugins: plugins, etag: etag);
  }

  Map<String, Object?> toJson() => {'v': v, 'at': at, 'plugins': [for (final p in plugins) p.toJson()]};
}

/// The withdrawals and retirements (route 3), kept as they came: InstalledPlugins.takeRevocations verifies each entry
/// itself, so nothing here is trusted.
class RevokedList {
  const RevokedList(this.json, {this.etag});
  final Map<String, Object?> json;
  final String? etag;

  List<Map> get revoked => _maps(json['revoked']);
  List<Map> get retired => _maps(json['retired']);
}

/// A screenshot going with a submission: new bytes (always a PNG the app made again, market_files.dart
/// shrinkScreenshot), or one of an earlier submission of the plugin kept by its SHA-256.
class ShotUpload {
  const ShotUpload.png(Uint8List this.bytes) : keep = null;
  const ShotUpload.kept(String this.keep) : bytes = null;
  final Uint8List? bytes;
  final String? keep;

  Map<String, Object?> toJson() => keep != null ? {'keep': keep} : {'mime': 'image/png', 'data': base64Encode(bytes!)};
}

/// One version of one plugin sent for review (route 8).
class SubmissionRequest {
  const SubmissionRequest({required this.package, this.shots = const [], this.notes = '', this.list = true, this.agree = true});

  /// Base64 of the package's canonical bytes.
  final String package;
  final List<ShotUpload> shots;
  final String notes;

  /// Listed once it is approved ("now"), or approved and left unlisted until the developer lists it ("later").
  final bool list;
  final bool agree;

  Map<String, Object?> toJson() => {'package': package, 'shots': [for (final s in shots) s.toJson()], 'notes': notes, 'list': list ? 'now' : 'later', 'agree': agree};
}

/// A note on a submission: the developer's for the reviewer (the first), or the reviewer's, with the status it set.
class SubmissionNote {
  const SubmissionNote({required this.at, required this.by, required this.text, this.status});
  final int at;
  final String by;                 // 'developer' or 'reviewer'
  final String text;
  final String? status;

  factory SubmissionNote.fromJson(Map j) => SubmissionNote(at: _int(j['at']), by: _text(j['by'], 'reviewer'), text: _text(j['text']), status: _maybe(j['status']));
  Map<String, Object?> toJson() => {'at': at, 'by': by, 'text': text, 'status': status};
}

/// Everything the developer may see of their own submission.
class SubmissionView {
  const SubmissionView({required this.sid, required this.plugin, required this.version, this.sha256 = '', this.size = 0, required this.status, this.name = '', this.tagline = '', this.description = '', this.symbol = 'puzzle', this.hue = 'slate', this.shelf = 'tools', this.labels = const [], this.permissions = const [], this.links = const [], this.developer, this.support, this.whatsNew, this.minApp, this.submittedAt = 0, this.updatedAt = 0, this.notes = const [], this.shots = const [], this.list = 'now', this.listing, this.revokedAt, this.revokedWhy});
  final String sid, plugin, version, sha256;
  final int size;

  /// 'submitted', 'in_review', 'changes_requested', 'approved', 'rejected', 'withdrawn' or 'superseded'.
  final String status;
  final String name, tagline, description, symbol, hue, shelf;
  final List<String> labels, permissions, links;
  final String? developer, support, whatsNew, minApp;
  final int submittedAt, updatedAt;
  final List<SubmissionNote> notes;

  /// The screenshots' SHA-256s, in order.
  final List<String> shots;
  final String list;

  /// 'listed' or 'unlisted' where this is the plugin's current approved version; null otherwise.
  final String? listing;

  /// Set where review withdrew this approved version, with its reason.
  final int? revokedAt;
  final String? revokedWhy;

  /// Still waiting on someone: the reviewer, or the developer's changes.
  bool get open => status == 'submitted' || status == 'in_review' || status == 'changes_requested';

  factory SubmissionView.fromJson(Map j) {
    final revoked = j['revoked'] is Map ? j['revoked'] as Map : null;
    return SubmissionView(
      sid: _text(j['sid']),
      plugin: _text(j['plugin']),
      version: _text(j['version']),
      sha256: _text(j['sha256']),
      size: _int(j['size']),
      status: _text(j['status'], 'submitted'),
      name: _text(j['name']),
      tagline: _text(j['tagline']),
      description: _text(j['description']),
      symbol: _text(j['symbol'], 'puzzle'),
      hue: _text(j['hue'], 'slate'),
      shelf: _text(j['shelf'], 'tools'),
      labels: _texts(j['labels']),
      permissions: _texts(j['permissions']),
      links: _texts(j['links']),
      developer: _maybe(j['developer']),
      support: _maybe(j['support']),
      whatsNew: _maybe(j['whatsNew']),
      minApp: _maybe(j['minApp']),
      submittedAt: _int(j['submittedAt']),
      updatedAt: _int(j['updatedAt']),
      notes: [for (final n in _maps(j['notes'])) SubmissionNote.fromJson(n)],
      shots: [for (final s in _maps(j['shots'])) if (s['sha256'] is String) s['sha256'] as String],
      list: _text(j['list'], 'now'),
      listing: _maybe(j['listing']),
      revokedAt: revoked == null ? null : _maybeInt(revoked['at']),
      revokedWhy: revoked == null ? null : _maybe(revoked['why']),
    );
  }

  Map<String, Object?> toJson() => {
        'sid': sid, 'plugin': plugin, 'version': version, 'sha256': sha256, 'size': size, 'status': status,
        'name': name, 'tagline': tagline, 'description': description, 'symbol': symbol, 'hue': hue, 'shelf': shelf,
        'labels': labels, 'permissions': permissions, 'links': links, 'developer': developer, 'support': support, 'whatsNew': whatsNew, 'minApp': minApp,
        'submittedAt': submittedAt, 'updatedAt': updatedAt, 'notes': [for (final n in notes) n.toJson()],
        'shots': [for (final s in shots) {'sha256': s, 'mime': 'image/png'}], 'list': list, 'listing': listing,
        'revoked': revokedAt == null ? null : {'at': revokedAt, 'why': revokedWhy},
      };
}

/// A plugin's place in the Marketplace, as its developer sees it.
class PluginState {
  const PluginState({required this.id, this.listing = 'none', this.current, this.by, this.note, this.noteAt});
  final String id;

  /// 'none' until its first approval, then 'listed' or 'unlisted'.
  final String listing;
  final String? current;

  /// Who last unlisted it: 'owner' or 'admin'.
  final String? by;
  final String? note;
  final int? noteAt;

  factory PluginState.fromJson(Map j) => PluginState(id: _text(j['id']), listing: _text(j['listing'], 'none'), current: _maybe(j['current']), by: _maybe(j['by']), note: _maybe(j['note']), noteAt: _maybeInt(j['noteAt']));
  Map<String, Object?> toJson() => {'id': id, 'listing': listing, 'current': current, 'by': by, 'note': note, 'noteAt': noteAt};
}

/// What route 9 says of this developer: whether they may submit, their submissions newest first, their plugins.
class MyMarket {
  const MyMarket({this.blocked = false, this.submissions = const [], this.plugins = const []});
  final bool blocked;
  final List<SubmissionView> submissions;
  final List<PluginState> plugins;

  factory MyMarket.fromJson(Map j) => MyMarket(
        blocked: j['blocked'] == true,
        submissions: [for (final s in _maps(j['submissions'])) SubmissionView.fromJson(s)],
        plugins: [for (final p in _maps(j['plugins'])) PluginState.fromJson(p)],
      );

  Map<String, Object?> toJson() => {'blocked': blocked, 'submissions': [for (final s in submissions) s.toJson()], 'plugins': [for (final p in plugins) p.toJson()]};
}

/// Why someone reports a plugin, as the relay names it, and the words the sheet offers (D.5).
enum ReportReason {
  misleading('misleading', 'It\'s misleading'),
  harmful('harmful', 'It\'s harmful or abusive'),
  spam('spam', 'It\'s spam'),
  privacy('privacy', 'It asks too much of my texts'),
  broken('broken', 'It doesn\'t work'),
  other('other', 'Something else');

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;
}

/// A report of a plugin (route 7). The username goes only where the person chose to send it.
class PluginReport {
  const PluginReport({required this.plugin, required this.version, required this.reason, this.text = '', this.username});
  final String plugin, version;
  final ReportReason reason;
  final String text;
  final String? username;

  Map<String, Object?> toJson() => {'plugin': plugin, 'version': version, 'reason': reason.wire, 'text': text, if (username != null) 'username': username};
}

/// One screenshot of a draft: a kept one of an earlier submission (its SHA-256), or new bytes, with where they were put
/// on disk once the draft was saved.
class DraftShot {
  const DraftShot({this.keep, this.bytes, this.path});
  final String? keep;
  final Uint8List? bytes;
  final String? path;

  Map<String, Object?> toJson() => {if (keep != null) 'keep': keep, if (path != null) 'path': path};
  factory DraftShot.fromJson(Map j) => DraftShot(keep: _maybe(j['keep']), path: _maybe(j['path']));
}

/// The submission form's values for one pack id, kept while the person leaves the Marketplace and comes back (D.8):
/// the form's fields, which of them the person changed (a corrected copy of the pack loaded again keeps those and takes
/// the rest from the file), and the screenshots.
class SubmitDraft {
  const SubmitDraft({required this.packId, this.name, this.tagline, this.description, this.icon, this.hue, this.shelf, this.labels, this.version, this.whatsNew, this.support, this.shots = const [], this.notes = '', this.list = true, this.agree = false, this.changed = const {}, this.at = 0});
  final String packId;
  final String? name, tagline, description;

  /// The icon as base64, as the pack holds it.
  final String? icon;
  final String? hue, shelf;
  final List<String>? labels;
  final String? version, whatsNew, support;
  final List<DraftShot> shots;
  final String notes;
  final bool list;
  final bool agree;

  /// The fields the person changed in the form, by name ('name', 'icon', 'labels', 'shots', ...).
  final Set<String> changed;
  final int at;

  SubmitDraft copyWith({List<DraftShot>? shots, int? at}) => SubmitDraft(packId: packId, name: name, tagline: tagline, description: description, icon: icon, hue: hue, shelf: shelf, labels: labels, version: version, whatsNew: whatsNew, support: support, shots: shots ?? this.shots, notes: notes, list: list, agree: agree, changed: changed, at: at ?? this.at);

  Map<String, Object?> toJson() => {
        'v': 1, 'packId': packId, 'name': name, 'tagline': tagline, 'description': description, 'icon': icon, 'hue': hue, 'shelf': shelf,
        'labels': labels, 'version': version, 'whatsNew': whatsNew, 'support': support, 'shots': [for (final s in shots) s.toJson()],
        'notes': notes, 'list': list, 'agree': agree, 'changed': changed.toList()..sort(), 'at': at,
      };

  factory SubmitDraft.fromJson(Map j) => SubmitDraft(
        packId: _text(j['packId']),
        name: _maybe(j['name']),
        tagline: _maybe(j['tagline']),
        description: _maybe(j['description']),
        icon: _maybe(j['icon']),
        hue: _maybe(j['hue']),
        shelf: _maybe(j['shelf']),
        labels: j['labels'] is List ? _texts(j['labels']) : null,
        version: _maybe(j['version']),
        whatsNew: _maybe(j['whatsNew']),
        support: _maybe(j['support']),
        shots: [for (final s in _maps(j['shots'])) DraftShot.fromJson(s)],
        notes: _text(j['notes']),
        list: j['list'] != false,
        agree: j['agree'] == true,
        changed: _texts(j['changed']).toSet(),
        at: _int(j['at']),
      );
}

/// The revocations and retirements in a [RevokedList] read as records, for showing (never trusted: the installer
/// verifies each before it counts).
extension RevokedRecords on RevokedList {
  List<PackRevocation> get revocations {
    final out = <PackRevocation>[];
    for (final m in revoked) {
      try {
        out.add(PackRevocation.fromJson(m));
      } on FormatException {
        // Left out.
      }
    }
    return out;
  }

  List<PackRetirement> get retirements {
    final out = <PackRetirement>[];
    for (final m in retired) {
      try {
        out.add(PackRetirement.fromJson(m));
      } on FormatException {
        // Left out.
      }
    }
    return out;
  }
}

// The review's own shapes (ReviewRow, ReviewQueue, ReviewItem, AskedBefore, DeveloperView, ReviewDecision, ReportView)
// come with the review screens (lib/ui/market/review_*.dart).
