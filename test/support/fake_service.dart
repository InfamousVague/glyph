/// The account and sync service in memory, for tests. A port of `src/test/fakeService.ts`, route for route: the
/// routes, revisions and refusals of server/src/accounts.rs and server/src/sync.rs, so every rule a client lives by
/// is tried without a server. Served to the code under test as a [Fetcher] ([FakeService.fetcher]), which is how the
/// app's calls take it (lib/account/api.dart).
///
/// One account at most, as a device only ever knows one: already there (`FakeService.start(seed: …)`, the account a
/// test signs in to), or made by a signup through the fetcher (`FakeService.start()`, for the account flows
/// themselves). Its feed of notes, its settings, its recordings and its notifications share one revision counter,
/// as the server's do. Other people exist only as `peers`: handles that resolve for an invitation without being the
/// account, and never call anything.
///
/// The organizations and notifications routes (server/src/orgs.rs, notifications.rs; docs/TEAMS.md) are here with
/// the server's refusals in its own words, since the client is built on telling those apart from a route the
/// service does not have yet: `teams: false` plays that older service, answering every one of them `no such route`.
/// What the server would write into OTHER accounts' feeds goes nowhere here, since the one account is always the
/// caller; [FakeService.notifies] plays a row the server wrote into this account's feed, and [FakeService.invited]
/// an organization a peer invited the account to.
///
/// What it does NOT do: rate limits, and most shape checks on ids and blobs. And it never holds the account key the
/// way the server never does, with one exception it says out loud: for an account it was given a password for, it
/// made the key itself, so it can play "another device" - sealing a note as the app seals one
/// ([FakeService.deviceWrites]) and opening what a client wrote ([FakeService.stored]).
///
/// What differs from the web's:
/// - Its crypto is `test/support/fake_crypto.dart`, which is NOT cryptography: a device under test must be given the
///   same kind, and nothing here proves the wire. The device signature at `login/device` is checked by
///   [FakeCrypto.verifyNonce] where the web's fake asks WebCrypto. A test may hand it the real crypto and the core's
///   own Ed25519 check instead ([FakeService.start]; test/e2e/real_crypto_test.dart).
/// - It is a class, made by [FakeService.start], with the web's returned object's members as its own.
/// - `Date.now()` is [FakeService.clock], which a test may set.
/// - A second signup under another handle throws a [StateError], which the app's [Api] lets through to the test
///   (the web's `Error` is swallowed into "could not be reached").
/// - [FakeService.listen] serves the same fetcher on 127.0.0.1, for the one test that needs a socket: the `dart:io`
///   fetcher's own.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/ids.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_json.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/workspaces.dart' show workspaceHues;

import 'fake_crypto.dart';

export 'fake_crypto.dart' show fastRounds;

/// How many updates a note's log holds before a snapshot must cut it (docs/SHARED.md, S11), as the service keeps it
/// (`UPDATES_KEPT`).
const int updatesKept = 500;

/// The id the one account is given, whoever makes it (`ACCOUNT_ID`).
const int fakeAccountId = 7;

/// The most rows an organization holds, and the most invitations one account may have waiting (docs/TEAMS.md).
const int _orgRows = 50;
const int _pendingInvites = 20;

/// How long after declining the same organization may not ask again.
const int _declineGapMs = 24 * 60 * 60000;

/// A note as the service keeps it: a feed item, filed under the id it leaves out (`Stored`).
class StoredNote {
  StoredNote({required this.rev, required this.deleted, required this.blob});
  final int rev;
  final bool deleted;
  final String? blob;

  Map<String, Object?> toJson(String id) => {'id': id, 'rev': rev, 'deleted': deleted, 'blob': blob};
}

/// A recording, a picture or a versions file as stored: sealed, at its revision.
class StoredFile {
  StoredFile(this.rev, this.bytes);
  final int rev;
  final Uint8List bytes;
}

/// A team note's row as the service keeps it (server/src/store/org_notes.rs; `TeamRow`).
class TeamRow {
  TeamRow({required this.rev, required this.deleted, required this.blob, required this.by, required this.updatedAt});
  final int rev;
  final bool deleted;
  final String? blob;
  final String by;
  final int updatedAt;

  Map<String, Object?> toJson(String id) => {'id': id, 'rev': rev, 'deleted': deleted, 'blob': blob, 'by': by, 'updatedAt': updatedAt};
}

/// One update in a team note's log.
class TeamUpdate {
  TeamUpdate({required this.seq, required this.blob, required this.by, required this.at});
  final int seq;
  final String blob;
  final String by;
  final int at;

  Map<String, Object?> toJson() => {'seq': seq, 'blob': blob, 'by': by, 'at': at};
}

/// A row of an organization as the service keeps it: who, their role, and whether they joined, wait, or declined.
class OrgRowKept {
  OrgRowKept({required this.handle, required this.role, required this.state, required this.since, required this.invitedBy});
  final String handle;

  /// `owner`, `admin` or `member`.
  String role;

  /// `member`, `invited` or `declined`.
  String state;
  int since;
  String? invitedBy;

  /// Their colour in this organization, overriding their account's (docs/SHARED.md, S7).
  String? hue;
}

/// An invite link as the service keeps it (server/src/store/org_links.rs): its organization, and who made it.
class StoredLink {
  StoredLink({required this.id, required this.code, required this.orgId, required this.createdAt, required this.expiresAt, required this.maxUses, required this.by});
  final String id;
  final String code;
  final String orgId;
  final int createdAt;
  final int? expiresAt;
  final int? maxUses;
  int uses = 0;
  final String? by;

  Map<String, Object?> toJson() => {'id': id, 'code': code, 'createdAt': createdAt, 'expiresAt': expiresAt, 'maxUses': maxUses, 'uses': uses, 'by': by};
}

/// An organization as the service keeps it (`StoredOrg`).
class StoredOrg {
  StoredOrg({required this.id, required this.name, required this.hue, required this.createdAt});
  final String id;
  String name;
  String? hue;
  final int createdAt;

  /// By handle, lower-cased.
  final Map<String, OrgRowKept> rows = {};

  /// The organization key's generation in force (docs/SHARED.md, S2); 0 for none yet.
  int generation = 0;

  /// Turns the key owes (S11): members gone since the generation was made; cleared by the next generation.
  int turns = 0;

  /// The key wrapped per member, by handle lower-cased, then by generation.
  final Map<String, Map<int, String>> wraps = {};

  /// The AIs seen in it through a member's connector (server/src/store/org_ais.rs), by id.
  final Map<String, Map<String, Object?>> ais = {};

  /// The team's notes (S4), its write counter, each note's log and its next seq, and its files.
  int rev = 0;
  final Map<String, TeamRow> notes = {};
  final Map<String, List<TeamUpdate>> updates = {};
  final Map<String, int> seqs = {};
  final Map<String, StoredFile> files = {};
}

class _Account {
  _Account({required this.handle, required this.loginSecret, required this.wrapped, required this.devices, required this.recovery, this.key});
  final String handle;

  /// The login half of the password, as sign-in sends it (the server keeps a hash of it; a test needs no hash).
  String loginSecret;

  /// The account key wrapped under the password's other half.
  String wrapped;

  /// Each device's public signing key, as base64url.
  final List<String> devices;

  /// The recovery sheet: each code's login half, and the account key wrapped under that code.
  Map<String, String> recovery;

  /// The account key itself, only for an account this service was given a password for (see the header).
  final SealKey? key;

  /// The account's colour (docs/SHARED.md, S7), and its encryption key pair as registered (S3).
  String? hue;
  ({String pub, String sealed})? encryption;
}

/// JS's `Number(value ?? 0)`: a number as it is, a numeric string parsed, nothing as 0, anything else NaN.
num _num(Object? value) => switch (value) {
      null => 0,
      final num n => n,
      final String s => num.tryParse(s.trim()) ?? (s.trim().isEmpty ? 0 : double.nan),
      true => 1,
      false => 0,
      _ => double.nan,
    };

/// JS's `String(value)`.
String _str(Object? value) => value == null ? 'undefined' : '$value';

String _lower(String handle) => handle.trim().toLowerCase();

bool _isHue(Object? hue) => hue == null || (hue is String && workspaceHues.contains(hue));

/// The service in memory (`fakeService`).
class FakeService {
  FakeService._(this.crypto, this._verify, this._account, {required this.head, required this.teams, required this.peers, this.ais = true});

  /// The service, holding the account [seed] names, signed up with that password, or none. [head] false: a HEAD
  /// never reaches the service, and the fetch throws as a browser's does when something drops it. [teams] false: a
  /// service from before organizations, answering every orgs and notifications route `no such route`. [peers]:
  /// handles that resolve for an invitation without being the account. [crypto] is the fake's unless given; with
  /// the real one (lib/account/crypto.dart, for the proof that the flows hold under real cryptography) [verify] must
  /// be given too: the service's check of a device's signature, which no client's crypto has.
  static Future<FakeService> start({
    ({String handle, String password})? seed,
    bool head = true,
    bool teams = true,
    List<String> peers = const ['sam'],
    bool ais = true,
    AccountCrypto? crypto,
    Future<bool> Function(String publicKey, String nonce, String signature)? verify,
  }) async {
    final fake = crypto ?? FakeCrypto();
    final checked = verify ?? (fake is FakeCrypto ? fake.verifyNonce : null);
    if (checked == null) throw ArgumentError('A service given its own crypto must be given a way to verify a device signature too.');
    _Account? account;
    if (seed != null) {
      final key = await fake.newAccountKey();
      final derived = await fake.derive(seed.password, passwordSalt(seed.handle), iterations: fastRounds);
      account = _Account(handle: seed.handle, loginSecret: derived.login, wrapped: await fake.wrap(key, derived.wrapKey), devices: [], recovery: {}, key: key);
    }
    return FakeService._(fake, checked, account, head: head, teams: teams, peers: List.of(peers), ais: ais);
  }

  /// The crypto this service seals with: a device in the same test uses the same kind.
  final AccountCrypto crypto;
  final Future<bool> Function(String publicKey, String nonce, String signature) _verify;
  final bool head;
  final bool teams;

  /// False: a service with organizations but from before their AI entries, answering those routes `no such route`.
  final bool ais;

  /// The handles that resolve for an invitation without being the account.
  final List<String> peers;

  /// The service's time, in ms: the wall clock's unless a test sets it.
  int Function() clock = () => DateTime.now().millisecondsSinceEpoch;

  _Account? _account;

  /// The feed as stored: each note's revision and sealed blob, or its deletion marker.
  final Map<String, StoredNote> notes = {};

  /// The recordings and pictures as stored, sealed, by their file id.
  final Map<String, StoredFile> files = {};
  ({int rev, String blob})? _prefs;

  /// The links shared from the account, as stored: each share's sealed blob by its id, and when it was written, in
  /// seconds. Not in the web's fake, whose share tests stand in for the call itself; here they go through the fetcher.
  final Map<String, ({String blob, int updated})> shares = {};

  /// The account's published sites (server/src/sites.rs): each one's sealed blob, what the account's devices sealed
  /// about it, and when it was first and last published, in ms.
  final Map<String, ({String blob, String meta, int created, int updated})> sites = {};

  /// Email to a note (server/src/mail.rs): the account's address, whether this service takes mail at all, and the
  /// mail waiting, sealed, by id. A test puts a mail here as the service would have sealed it.
  String? mailAddress;
  bool takesMail = true;
  final Map<String, ({String wrapped, String blob, int at})> mail = {};

  /// The organizations as stored, by id, with their rows by handle.
  final Map<String, StoredOrg> orgs = {};

  /// Invite links as stored, by code.
  final Map<String, StoredLink> links = {};
  final Map<String, String> _peerHues = {};
  final Map<String, String> _peerKeys = {};

  /// The account's notifications as stored, by id: each row at the revision it was last written.
  final Map<String, FeedNotification> feed = {};
  int _counter = 0;
  final Set<String> _tokens = {};
  final Set<String> _nonces = {};
  int _issued = 0;

  /// Every request, as `METHOD path`: what a test asserts the client asked, and in what order.
  final List<String> calls = [];

  String _token() {
    final t = 'tok-${++_issued}';
    _tokens.add(t);
    return t;
  }

  static FetchResponse _json(int status, Object? body) => FetchResponse.json(status, body);
  static FetchResponse _refuse(int status, String error) => _json(status, {'error': error});
  FetchResponse _signedIn(_Account a, [String? wrapped]) => _json(200, {
        'token': _token(),
        'account': {'id': fakeAccountId, 'handle': a.handle},
        if (wrapped != null && wrapped.isNotEmpty) 'wrapped': wrapped,
      });
  static bool _sameHandle(_Account? a, Object? handle) => a != null && a.handle.toLowerCase() == (handle == null ? '' : '$handle').trim().toLowerCase();
  int _nextRev() => ++_counter;

  void _forget() {
    _account = null;
    notes.clear();
    files.clear();
    _prefs = null;
    shares.clear();
    sites.clear();
    mailAddress = null;
    mail.clear();
    orgs.clear();
    links.clear();
    feed.clear();
    _counter = 0;
    _tokens.clear();
  }

  // --- organizations and notifications, as the server keeps them --------------------------------------------------

  /// A handle as the service knows it: the account's, or a peer's; null for nobody.
  String? _resolve(Object? handle) {
    final wanted = _lower(handle == null ? '' : '$handle');
    if (wanted.isEmpty) return null;
    final account = _account;
    if (account != null && _lower(account.handle) == wanted) return account.handle;
    for (final peer in peers) {
      if (_lower(peer) == wanted) return peer;
    }
    return null;
  }

  OrgRowKept? _rowOf(StoredOrg org, String handle) => org.rows[_lower(handle)];
  List<OrgRowKept> _joined(StoredOrg org) => [for (final r in org.rows.values) if (r.state == 'member') r];
  bool _isAccount(String handle) => _account != null && _lower(_account!.handle) == _lower(handle);

  /// A handle's account colour: the account's, or a peer's as a test gave it.
  String? _hueOf(String handle) => _isAccount(handle) ? _account!.hue : _peerHues[_lower(handle)];

  /// A handle's encryption public key, as registered.
  String? _pubOf(String handle) => _isAccount(handle) ? _account!.encryption?.pub : _peerKeys[_lower(handle)];

  /// A row's colour: its override in the organization, else the account's.
  String? _colourOf(OrgRowKept r) => r.hue ?? _hueOf(r.handle);
  String? _wrapOf(StoredOrg org, String handle, [int? at]) {
    final generation = at ?? org.generation;
    if (generation == 0) return null;
    final theirs = org.wraps[_lower(handle)];
    return theirs == null ? null : theirs[generation];
  }

  bool _stale(StoredOrg org) => org.generation > 0 && org.turns > 0;

  /// The generation in force, against a body's or a query's: 409 with the one in force when it is another (S11).
  FetchResponse? _inForce(StoredOrg org, Object? generation) =>
      generation is num && generation != org.generation ? _json(409, {'error': 'That is not the generation in force.', 'generation': org.generation}) : null;

  /// Members with a public key and no wrap at the generation in force (every one with a key, before a generation).
  List<OrgRowKept> _lacking(StoredOrg org) => [
        for (final r in org.rows.values)
          if ((r.state == 'member' || r.state == 'invited') && _pubOf(r.handle) != null && _wrapOf(org, r.handle) == null) r,
      ];
  Map<String, Object?> _keysJson(StoredOrg org, OrgRowKept me) => {'generation': org.generation, 'mine': _wrapOf(org, me.handle) != null, 'missing': _lacking(org).length, 'stale': _stale(org)};
  static String _shown(String state) => state == 'declined' ? 'invited' : state;
  Map<String, Object?> _memberJson(OrgRowKept r) =>
      {'handle': r.handle, 'role': r.role, 'state': _shown(r.state), 'since': r.since, 'invitedBy': r.invitedBy, 'colour': _colourOf(r), 'pub': _pubOf(r.handle)};
  Map<String, Object?> _orgJson(StoredOrg org, OrgRowKept me) => {
        'id': org.id,
        'name': org.name,
        'hue': org.hue,
        'role': me.role,
        'state': _shown(me.state),
        'invitedBy': me.invitedBy,
        'createdAt': org.createdAt,
        'colour': _colourOf(me),
        'keys': _keysJson(org, me),
        'members': [for (final r in org.rows.values) if (r.state != 'declined') _memberJson(r)],
        // Only those that came through someone still in it, as the server's join answers them.
        if (ais) 'ais': [for (final ai in org.ais.values) if (_rowOf(org, ai['via']! as String)?.state == 'member') ai],
      };
  Map<String, Object?> _rowJson(StoredOrg org, OrgRowKept me) => {
        'id': org.id,
        'name': org.name,
        'hue': org.hue,
        'role': me.role,
        'state': _shown(me.state),
        'members': _joined(org).length,
        'invitedBy': me.invitedBy,
        'createdAt': org.createdAt,
        'colour': _colourOf(me),
        'keys': _keysJson(org, me),
      };

  /// A row written into the account's feed by the service, at a new revision: what [notifies] plays.
  FeedNotification _fed({required String kind, String? id, int? at, int? readAt, bool hidden = false, String? from, NotificationOrg? org, Map<String, Object?>? body, String? blob, String? state}) {
    final item = FeedNotification(id: id ?? shortId(), rev: _nextRev(), kind: kind, at: at ?? clock(), readAt: readAt, hidden: hidden, from: from, org: org, body: body, blob: blob, state: state);
    feed[item.id] = item;
    return item;
  }

  /// The account's pending invitation to an organization, as a feed row, if there is one.
  FeedNotification? _pendingInvite(String orgId) {
    for (final n in feed.values) {
      if (n.kind == 'invite' && n.org?.id == orgId && n.state == 'pending') return n;
    }
    return null;
  }

  /// A change to a feed row takes a new revision, so every device is fed it again.
  FeedNotification _touch(FeedNotification item, {int? Function()? readAt, bool? hidden, String? state}) {
    final next = FeedNotification(
      id: item.id,
      rev: _nextRev(),
      kind: item.kind,
      at: item.at,
      readAt: readAt == null ? item.readAt : readAt(),
      hidden: hidden ?? item.hidden,
      from: item.from,
      org: item.org,
      body: item.body,
      blob: item.blob,
      state: state ?? item.state,
    );
    feed[item.id] = next;
    return next;
  }

  /// Whether a link still works: not expired, not used up.
  bool _working(StoredLink link) => (link.expiresAt == null || link.expiresAt! > clock()) && (link.maxUses == null || link.uses < link.maxUses!);

  /// A link to an organization, made by [by].
  StoredLink _linkTo(StoredOrg org, String by, int? expiresAt, int? maxUses) {
    final link = StoredLink(id: shortId(), code: shortId(), orgId: org.id, createdAt: clock(), expiresAt: expiresAt, maxUses: maxUses, by: by);
    links[link.code] = link;
    return link;
  }

  StoredOrg _peerOrg(String name, String by) {
    final org = StoredOrg(id: shortId(), name: name, hue: null, createdAt: clock());
    org.rows[_lower(by)] = OrgRowKept(handle: by, role: 'owner', state: 'member', since: org.createdAt, invitedBy: null);
    orgs[org.id] = org;
    return org;
  }

  // --- the fetch ---------------------------------------------------------------------------------------------------

  /// The service, as the [Fetcher] the code under test is given.
  Fetcher get fetcher => _fetch;

  Future<FetchResponse> _fetch(FetchRequest request) async {
    final url = request.url;
    final method = request.method;
    final path = url.path.replaceFirst(RegExp(r'^.*/v1/'), '');
    calls.add('$method $path');
    // JSON for every route but a recording's PUT, whose body is the bytes themselves.
    final isJson = request.headers.entries.any((h) => h.key.toLowerCase() == 'content-type' && h.value.startsWith('application/json'));
    final decoded = isJson && request.text.isNotEmpty ? jsonDecode(request.text) : null;
    final body = decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
    final bearer = request.bearer;
    final query = url.queryParameters;
    final account = _account;

    // --- the ways in, which need no session ---
    if (method == 'POST' && path == 'signup') {
      if (account != null && !_sameHandle(account, body['handle'])) throw StateError('The fake service holds one account, and this test signed up a second.');
      if (account != null) return _refuse(409, 'That handle is taken.');
      final sheet = body['recovery'] is List ? body['recovery'] as List : const [];
      if (sheet.length != 8) return _refuse(400, 'A recovery sheet is eight codes.');
      final made = _Account(
        handle: _str(body['handle']).trim(),
        loginSecret: (body['loginSecret'] == null ? '' : '${body['loginSecret']}').toLowerCase(),
        wrapped: body['wrapped'] == null ? '' : '${body['wrapped']}',
        devices: [if (body['devicePublicKey'] != null && '${body['devicePublicKey']}'.isNotEmpty) '${body['devicePublicKey']}'],
        recovery: {for (final code in sheet) '${(code as Map)['login']}'.toLowerCase(): '${code['wrapped']}'},
      );
      _account = made;
      return _signedIn(made);
    }
    if (method == 'POST' && path == 'login') {
      // The same answer for a wrong handle and a wrong password, as the server gives.
      if (account == null || !_sameHandle(account, body['handle']) || account.loginSecret != _str(body['loginSecret']).toLowerCase()) return _refuse(401, 'Wrong handle or password.');
      return _signedIn(account, account.wrapped);
    }
    if (method == 'POST' && path == 'login/challenge') {
      // A nonce whether or not the handle exists, so this says nothing about which do.
      final nonce = 'nonce-${++_issued}';
      _nonces.add(nonce);
      return _json(200, {'nonce': nonce});
    }
    if (method == 'POST' && path == 'login/device') {
      // The nonce is spent by the attempt, whether or not the signature holds.
      if (!_nonces.remove(_str(body['nonce']))) return _refuse(401, 'That sign-in took too long. Try again.');
      if (account == null || !_sameHandle(account, body['handle'])) return _refuse(401, 'This device could not be verified.');
      for (final device in account.devices) {
        if (await _verify(device, _str(body['nonce']), _str(body['signature']))) return _signedIn(account);
      }
      return _refuse(401, 'This device could not be verified.');
    }
    if (method == 'POST' && path == 'login/recovery') {
      // The code is spent, and what comes back is the key wrapped under that code alone.
      final login = _str(body['login']).toLowerCase();
      final wrapped = account != null && _sameHandle(account, body['handle']) ? account.recovery[login] : null;
      if (account == null || wrapped == null) return _refuse(401, 'Wrong handle or code, or a code already used.');
      account.recovery.remove(login);
      return _signedIn(account, wrapped);
    }

    // --- a share read by its link, which needs no session (server/src/shares.rs) ---
    final share = RegExp(r'^shares/([^/]+)$').firstMatch(path);
    if (share != null && method == 'GET') {
      final kept = shares[Uri.decodeComponent(share[1]!)];
      return kept != null ? _json(200, {'blob': kept.blob}) : _refuse(404, 'No share by that link.');
    }

    // --- a site read by its link, which needs no session (server/src/sites.rs) ---
    final site = RegExp(r'^sites/([^/]+)$').firstMatch(path);
    if (site != null && method == 'GET') {
      final kept = sites[Uri.decodeComponent(site[1]!)];
      return kept != null ? _json(200, {'blob': kept.blob, 'updated': kept.updated}) : _refuse(404, 'Nothing is published at that link. It may have been unpublished.');
    }

    // --- everything else is for a signed-in device ---
    if (bearer == null || bearer.isEmpty) return _refuse(401, 'Sign in first.');
    if (!_tokens.contains(bearer) || account == null) return _refuse(401, 'Your session has ended. Sign in again.');
    final mine = account;

    if (method == 'POST' && path == 'refresh') return _signedIn(mine);
    if (method == 'POST' && path == 'device') {
      mine.devices.add(_str(body['devicePublicKey']));
      return _json(200, {'ok': true});
    }
    if (method == 'GET' && path == 'keys') return _json(200, {'wrapped': mine.wrapped});
    if (method == 'PUT' && path == 'password') {
      mine.loginSecret = _str(body['loginSecret']).toLowerCase();
      mine.wrapped = _str(body['wrapped']);
      return _json(200, {'ok': true});
    }
    if (method == 'GET' && path == 'recovery') return _json(200, {'left': mine.recovery.length});
    if (method == 'POST' && path == 'recovery') {
      final sheet = body['codes'] is List ? body['codes'] as List : const [];
      if (sheet.length != 8) return _refuse(400, 'A recovery sheet is eight codes.');
      mine.recovery = {for (final code in sheet) '${(code as Map)['login']}'.toLowerCase(): '${code['wrapped']}'};
      return _json(200, {'left': 8});
    }
    if (method == 'DELETE' && path == 'account') {
      // 403 rather than 401: the session is fine, only the password is wrong, and a 401 reads as signed out.
      if (mine.loginSecret != (body['loginSecret'] == null ? '' : '${body['loginSecret']}').toLowerCase()) return _refuse(403, 'That is not the password.');
      _forget();
      return _json(200, {'deleted': true});
    }

    // --- colours and the encryption key pair (docs/SHARED.md, S3, S7) ---
    if (path == 'account/colour' || path == 'account/key') {
      if (!teams) return _refuse(404, noSuchRoute);
      if (method == 'PUT' && path == 'account/colour') {
        final hue = body['hue'];
        if (!_isHue(hue)) return _refuse(400, 'That hue is not one of the workspace hues.');
        mine.hue = hue == 'ink' ? null : hue as String?;
        return _json(200, {'colour': mine.hue});
      }
      if (method == 'GET' && path == 'account/key') {
        final kept = mine.encryption;
        return kept != null ? _json(200, {'pub': kept.pub, 'sealed': kept.sealed}) : _refuse(404, 'No key pair yet.');
      }
      if (method == 'PUT' && path == 'account/key') {
        final pub = body['pub'], sealed = body['sealed'];
        if (pub is! String || sealed is! String || pub.isEmpty || sealed.isEmpty) return _refuse(400, 'That key pair could not be read.');
        final kept = mine.encryption;
        if (kept != null) return _json(409, {'pub': kept.pub, 'sealed': kept.sealed, 'error': 'The account has a key pair already; this is it.'});
        mine.encryption = (pub: pub, sealed: sealed);
        return _json(201, {'pub': pub, 'sealed': sealed});
      }
    }

    if (method == 'GET' && path == 'notes') {
      final since = _num(query['since']);
      final items = [for (final MapEntry(:key, :value) in notes.entries) if (value.rev > since) (key, value)]..sort((a, b) => a.$2.rev.compareTo(b.$2.rev));
      return _json(200, {'rev': _counter, 'items': [for (final (id, n) in items) n.toJson(id)], 'more': false});
    }
    final note = RegExp(r'^notes/([^/]+)$').firstMatch(path);
    if (note != null && (method == 'PUT' || method == 'DELETE')) {
      final id = Uri.decodeComponent(note[1]!);
      final current = notes[id];
      // A note never seen is taken whatever its base: there is nothing it could overwrite.
      if (current != null && current.rev != _num(body['base'])) return _json(409, current.toJson(id));
      final rev = _nextRev();
      notes[id] = method == 'PUT' ? StoredNote(rev: rev, deleted: false, blob: _str(body['blob'])) : StoredNote(rev: rev, deleted: true, blob: null);
      return _json(200, {'rev': rev});
    }

    // --- shared links (server/src/shares.rs): sealed blobs by id, the account's to write and take down ---
    if (path == 'shares' && method == 'GET') {
      return _json(200, {'shares': [for (final MapEntry(:key, :value) in shares.entries) {'id': key, 'updated': value.updated}]});
    }
    if (share != null && method == 'PUT') {
      final blob = body['blob'];
      if (blob is! String || blob.isEmpty) return _refuse(400, 'That share is empty or too large.');
      shares[Uri.decodeComponent(share[1]!)] = (blob: blob, updated: clock() ~/ 1000);
      return _json(200, {'ok': true});
    }
    if (share != null && method == 'DELETE') {
      shares.remove(Uri.decodeComponent(share[1]!));
      return _json(200, {'deleted': true});
    }

    // --- published sites (server/src/sites.rs) ---
    if (path == 'sites' && method == 'GET') {
      return _json(200, {
        'sites': [
          for (final MapEntry(:key, :value) in sites.entries) {'id': key, 'meta': value.meta, 'created': value.created, 'updated': value.updated},
        ],
      });
    }
    if (site != null && method == 'PUT') {
      final blob = body['blob'], meta = body['meta'];
      if (blob is! String || blob.isEmpty) return _refuse(400, 'That site is empty or too large.');
      if (meta is! String || meta.isEmpty) return _refuse(400, 'What that site says about itself could not be read.');
      final id = Uri.decodeComponent(site[1]!);
      final now = clock();
      sites[id] = (blob: blob, meta: meta, created: sites[id]?.created ?? now, updated: now);
      return _json(200, {'id': id, 'updated': now});
    }
    if (site != null && method == 'DELETE') {
      sites.remove(Uri.decodeComponent(site[1]!));
      return _json(204, null);
    }

    // --- email to a note (server/src/mail.rs) ---
    if (path == 'mail/address') {
      if (method == 'GET') return _json(200, {'address': mailAddress, 'available': takesMail});
      if (method == 'POST') {
        if (!takesMail) return _refuse(503, 'Email to a note is not set up on this service yet.');
        if (mine.encryption == null) return _refuse(409, 'Your account needs its encryption key first. Sync once, then try again.');
        mailAddress = 'k7m2q9xh4t3v${(++_issued).toString().padLeft(4, '0')}@in.ghostmarkdown.com';
        return _json(200, {'address': mailAddress});
      }
      if (method == 'DELETE') {
        mailAddress = null;
        return _json(204, null);
      }
    }
    if (path == 'mail' && method == 'GET') {
      final waiting = mail.entries.toList()..sort((a, b) => a.value.at.compareTo(b.value.at));
      return _json(200, {
        'mail': [
          for (final MapEntry(:key, :value) in waiting) {'id': key, 'size': value.wrapped.length + value.blob.length, 'at': value.at},
        ],
      });
    }
    final mailed = RegExp(r'^mail/([^/]+)$').firstMatch(path);
    if (mailed != null && method == 'GET') {
      final id = Uri.decodeComponent(mailed[1]!);
      final kept = mail[id];
      return kept != null ? _json(200, {'id': id, 'wrapped': kept.wrapped, 'blob': kept.blob, 'at': kept.at}) : _refuse(404, 'That mail is not waiting. Another of your devices may have filed it.');
    }
    if (mailed != null && method == 'DELETE') {
      mail.remove(Uri.decodeComponent(mailed[1]!));
      return _json(204, null);
    }

    if (path == 'prefs' && method == 'GET') return _json(200, {'rev': _prefs?.rev ?? 0, 'blob': _prefs?.blob});
    if (path == 'prefs' && method == 'PUT') {
      final kept = _prefs;
      if ((kept?.rev ?? 0) != _num(body['base'])) return kept != null ? _json(409, {'rev': kept.rev, 'blob': kept.blob}) : _refuse(500, 'Those settings could not be stored.');
      final next = (rev: _nextRev(), blob: _str(body['blob']));
      _prefs = next;
      return _json(200, {'rev': next.rev});
    }

    // --- organizations and notifications (docs/TEAMS.md) ---
    if (RegExp(r'^(orgs|notifications|joins)(/|$)').hasMatch(path)) {
      // A service from before these routes: the one 404 the client reads as "not yet".
      if (!teams) return _refuse(404, noSuchRoute);
      return _teams(mine, method, path, body, query, request.body) ?? _refuse(404, 'No route $method $path');
    }

    final file = RegExp(r'^recordings/([^/]+)$').firstMatch(path);
    if (file != null) {
      final id = file[1]!;
      final had = files[id];
      if (method == 'HEAD') {
        if (!head) throw const HttpException('Failed to fetch');
        return had != null ? FetchResponse(200, headers: {'x-glyph-rev': '${had.rev}'}) : FetchResponse(404);
      }
      if (method == 'GET') return had != null ? FetchResponse(200, headers: {'x-glyph-rev': '${had.rev}'}, bytes: had.bytes) : _refuse(404, 'No recording by that id.');
      if (method == 'PUT') {
        final base = _num(query['base']);
        if (had != null && had.rev != base) return _json(409, {'rev': had.rev});
        final rev = _nextRev();
        files[id] = StoredFile(rev, Uint8List.fromList(request.body ?? const []));
        return _json(200, {'rev': rev});
      }
    }
    return _refuse(404, 'No route $method $path');
  }

  /// The organizations and notifications routes; null for none of them.
  FetchResponse? _teams(_Account mine, String method, String path, Map<String, Object?> body, Map<String, String> query, Uint8List? raw) {
    final me = mine.handle;

    /// The organization at an id and the account's row in it; null for one the account is not in.
    ({StoredOrg org, OrgRowKept row})? inOrg(String id, [List<String> states = const ['member']]) {
      final org = orgs[id];
      final row = org != null ? _rowOf(org, me) : null;
      return org != null && row != null && states.contains(row.state) ? (org: org, row: row) : null;
    }

    int showing(StoredOrg org) => org.rows.values.where((r) => r.state != 'declined').length;

    if (method == 'POST' && path == 'orgs') {
      final name = (body['name'] == null ? '' : '${body['name']}').trim();
      if (name.isEmpty || name.length > 60) return _refuse(400, 'An organization’s name is 1 to 60 characters.');
      if (!_isHue(body['hue'])) return _refuse(400, 'That is not one of the hues.');
      if (orgs.values.where((o) => _rowOf(o, me)?.role == 'owner').length >= 20) return _refuse(409, 'You own as many organizations as you can.');
      final org = StoredOrg(id: shortId(), name: name, hue: body['hue'] as String?, createdAt: clock());
      final owner = OrgRowKept(handle: me, role: 'owner', state: 'member', since: org.createdAt, invitedBy: null);
      org.rows[_lower(me)] = owner;
      orgs[org.id] = org;
      return _json(201, {'org': _orgJson(org, owner)});
    }
    if (method == 'GET' && path == 'orgs') {
      final rows = <Map<String, Object?>>[];
      for (final org in orgs.values) {
        final row = _rowOf(org, me);
        if (row != null && row.state != 'declined') rows.add(_rowJson(org, row));
      }
      return _json(200, {'orgs': rows, 'colour': mine.hue});
    }
    // Team notes (docs/SHARED.md, S4, S5): the feed, a row, its log, each log's head, and the organization's files.
    final teamHeads = RegExp(r'^orgs/([^/]+)/heads$').firstMatch(path);
    if (teamHeads != null && method == 'GET') {
      final found = inOrg(Uri.decodeComponent(teamHeads[1]!));
      if (found == null) return _refuse(404, 'No such organization.');
      return _json(200, {
        'heads': {for (final MapEntry(:key, :value) in found.org.notes.entries) if (!value.deleted) key: found.org.seqs[key] ?? 0},
      });
    }
    final teamNotes = RegExp(r'^orgs/([^/]+)/notes(?:/([^/]+))?(/updates)?$').firstMatch(path);
    if (teamNotes != null) {
      final found = inOrg(Uri.decodeComponent(teamNotes[1]!));
      if (found == null) return _refuse(404, 'No such organization.');
      final org = found.org;
      if (teamNotes[2] == null && method == 'GET') {
        final since = _num(query['since']);
        final items = [for (final MapEntry(:key, :value) in org.notes.entries) if (value.rev > since) (key, value)]..sort((a, b) => a.$2.rev.compareTo(b.$2.rev));
        return _json(200, {'rev': org.rev, 'items': [for (final (id, n) in items) n.toJson(id)], 'more': false});
      }
      final id = Uri.decodeComponent(teamNotes[2] ?? '');
      if (teamNotes[3] != null) {
        final row = org.notes[id];
        if (row == null || row.deleted) return _refuse(404, 'No such note.');
        final log = org.updates[id] ?? [];
        if (method == 'GET') {
          final since = _num(query['since']);
          return _json(200, {'seq': log.isNotEmpty ? log.last.seq : (org.seqs[id] ?? 0), 'items': [for (final u in log) if (u.seq > since) u.toJson()], 'more': false});
        }
        if (method == 'POST') {
          final blobs = body['blobs'] is List ? body['blobs'] as List : const [];
          if (blobs.isEmpty || blobs.any((b) => b is! String || b.isEmpty)) return _refuse(400, 'Those updates could not be read.');
          final turned = _inForce(org, body['generation']);
          if (turned != null) return turned;
          var seq = org.seqs[id] ?? 0;
          // A log past its length asks for a snapshot first (S11; server/src/store/org_notes.rs UPDATES_KEPT).
          if (log.length + blobs.length > updatesKept) return _json(409, {'error': 'snapshot', 'seq': seq});
          for (final blob in blobs) {
            log.add(TeamUpdate(seq: ++seq, blob: blob as String, by: me, at: clock()));
          }
          org.updates[id] = log;
          org.seqs[id] = seq;
          return _json(200, {'seq': seq});
        }
      }
      if (method == 'PUT' || method == 'DELETE') {
        final current = org.notes[id];
        final turned = method == 'PUT' ? _inForce(org, body['generation']) : null;
        if (turned != null) return turned;
        if (current != null && current.rev != _num(body['base'])) return _json(409, current.toJson(id));
        final blob = body['blob'];
        if (method == 'PUT' && (blob is! String || blob.isEmpty)) return _refuse(400, 'That note is empty or too large to sync.');
        final rev = ++org.rev;
        org.notes[id] = method == 'PUT' ? TeamRow(rev: rev, deleted: false, blob: blob as String, by: me, updatedAt: clock()) : TeamRow(rev: rev, deleted: true, blob: null, by: me, updatedAt: clock());
        final upTo = body['upTo'];
        if (method == 'DELETE') {
          org.updates.remove(id);
        } else if (upTo is num) {
          org.updates[id] = [for (final u in org.updates[id] ?? const <TeamUpdate>[]) if (u.seq > upTo) u];
        }
        return _json(200, {'rev': rev});
      }
    }
    final teamFile = RegExp(r'^orgs/([^/]+)/files/([^/]+)$').firstMatch(path);
    if (teamFile != null) {
      final found = inOrg(Uri.decodeComponent(teamFile[1]!));
      if (found == null) return _refuse(404, 'No such organization.');
      final org = found.org;
      final id = teamFile[2]!;
      final had = org.files[id];
      if (method == 'HEAD') return had != null ? FetchResponse(200, headers: {'x-glyph-rev': '${had.rev}'}) : FetchResponse(404);
      if (method == 'GET') return had != null ? FetchResponse(200, headers: {'x-glyph-rev': '${had.rev}'}, bytes: had.bytes) : _refuse(404, 'No file by that id.');
      if (method == 'PUT') {
        final base = _num(query['base']);
        final asked = query['generation'];
        final turned = _inForce(org, asked == null ? null : _num(asked));
        if (turned != null) return turned;
        if (had != null && had.rev != base) return _json(409, {'rev': had.rev});
        final rev = ++org.rev;
        org.files[id] = StoredFile(rev, Uint8List.fromList(raw ?? const []));
        return _json(200, {'rev': rev});
      }
    }
    // The AIs seen in an organization through a member's connector (server/src/orgs.rs, store/org_ais.rs).
    final seenAi = RegExp(r'^orgs/([^/]+)/ais(?:/([^/]+))?$').firstMatch(path);
    if (seenAi != null) {
      if (!ais) return _refuse(404, noSuchRoute);
      final found = inOrg(Uri.decodeComponent(seenAi[1]!));
      if (found == null) return _refuse(404, 'No such organization.');
      final org = found.org;
      if (method == 'POST' && seenAi[2] == null) {
        final name = (body['name'] == null ? '' : '${body['name']}').trim();
        if (name.isEmpty || name.length > 40) return _refuse(400, 'An AI’s name is 1 to 40 characters.');
        Map<String, Object?>? had;
        for (final ai in org.ais.values) {
          if (ai['name'] == name && _lower(ai['via']! as String) == _lower(me)) had = ai;
        }
        final ai = had != null ? {...had, 'lastSeen': clock()} : <String, Object?>{'id': shortId(), 'name': name, 'via': found.row.handle, 'firstSeen': clock(), 'lastSeen': clock()};
        org.ais[ai['id']! as String] = ai;
        return _json(200, {'ai': ai});
      }
      if (method == 'DELETE' && seenAi[2] != null) {
        final ai = org.ais[Uri.decodeComponent(seenAi[2]!)];
        if (ai == null) return _refuse(404, 'No such AI in this organization.');
        if (_lower(ai['via']! as String) != _lower(me) && found.row.role == 'member') return _refuse(403, 'Only the owner or an admin can do that.');
        org.ais.remove(ai['id']);
        return _json(200, {'removed': true});
      }
    }
    // The caller's colour in one organization (docs/SHARED.md, S7), and the organization key's wraps (S2).
    final colour = RegExp(r'^orgs/([^/]+)/colour$').firstMatch(path);
    if (colour != null && method == 'PUT') {
      final found = inOrg(Uri.decodeComponent(colour[1]!));
      if (found == null) return _refuse(404, 'No such organization.');
      final hue = body['hue'];
      if (!_isHue(hue)) return _refuse(400, 'That hue is not one of the workspace hues.');
      found.row.hue = hue == 'ink' ? null : hue as String?;
      return _json(200, {'org': _orgJson(found.org, found.row)});
    }
    final keys = RegExp(r'^orgs/([^/]+)/keys$').firstMatch(path);
    if (keys != null) {
      final found = inOrg(Uri.decodeComponent(keys[1]!));
      if (found == null) return _refuse(404, 'No such organization.');
      final (:org, :row) = found;
      FetchResponse answer([int? at]) => _json(200, {
            'generation': org.generation,
            'mine': _wrapOf(org, row.handle, at),
            'missing': [for (final r in _lacking(org)) {'handle': r.handle, 'pub': _pubOf(r.handle)}],
            'stale': _stale(org),
          });
      if (method == 'GET') {
        final at = query['generation'];
        if (at != null && !(_num(at) >= 1)) return _refuse(400, 'That generation could not be read.');
        return answer(at == null ? null : _num(at).toInt());
      }
      if (method == 'POST') {
        final generation = body.containsKey('generation') ? _num(body['generation']) : double.nan;
        final wraps = body['wraps'] is List ? body['wraps'] as List : const [];
        if (!(generation >= 1) || wraps.any((w) => w is! Map || w['handle'] is! String || w['wrapped'] is! String)) return _refuse(400, 'Those wraps could not be read.');
        final inForce = org.generation;
        if (body['make'] == true) {
          if (generation != inForce + 1) return _json(409, {'error': 'That is not the generation in force.', 'generation': inForce});
          org.generation = generation.toInt();
          org.turns = 0;
        } else if (generation != inForce) {
          return _json(409, {'error': 'That is not the generation in force.', 'generation': inForce});
        }
        for (final wrap in wraps) {
          final handle = (wrap as Map)['handle'] as String;
          final member = _rowOf(org, handle);
          // A member, or someone invited: their wrap waits for them (docs/SHARED.md, S2).
          if (member == null || (member.state != 'member' && member.state != 'invited')) continue;
          org.wraps.putIfAbsent(_lower(handle), () => {}).putIfAbsent(generation.toInt(), () => wrap['wrapped'] as String);
        }
        return answer();
      }
    }
    final one = RegExp(r'^orgs/([^/]+)$').firstMatch(path);
    if (one != null) {
      final found = inOrg(Uri.decodeComponent(one[1]!));
      if (found == null) return _refuse(404, 'No such organization.');
      final (:org, :row) = found;
      if (method == 'GET') return _json(200, {'org': _orgJson(org, row)});
      if (method == 'PUT') {
        if (row.role == 'member') return _refuse(403, 'Only the owner or an admin can change the organization.');
        if (body.containsKey('name')) {
          final name = _str(body['name']).trim();
          if (name.isEmpty || name.length > 60) return _refuse(400, 'An organization’s name is 1 to 60 characters.');
          org.name = name;
        }
        if (body.containsKey('hue')) {
          if (!_isHue(body['hue'])) return _refuse(400, 'That is not one of the hues.');
          org.hue = body['hue'] as String?;
        }
        return _json(200, {'org': _orgJson(org, row)});
      }
      if (method == 'DELETE') {
        if (row.role != 'owner') return _refuse(403, 'Only the owner can delete the organization.');
        orgs.remove(org.id);
        return _json(200, {'deleted': true});
      }
    }
    final members = RegExp(r'^orgs/([^/]+)/members(?:/([^/]+))?$').firstMatch(path);
    if (members != null) {
      final found = inOrg(Uri.decodeComponent(members[1]!));
      if (found == null) return _refuse(404, 'No such organization.');
      final (:org, :row) = found;
      if (method == 'POST' && members[2] == null) {
        if (row.role == 'member') return _refuse(403, 'Only the owner or an admin can invite.');
        final handle = _resolve(body['handle']);
        if (handle == null) return _refuse(404, 'No one has that handle.');
        final had = _rowOf(org, handle);
        if (had?.state == 'member') return _refuse(409, 'They are already a member.');
        if (had != null && had.state == 'declined' && clock() - had.since < _declineGapMs) return _refuse(409, 'They declined; ask again tomorrow.');
        if (had != null && had.state == 'invited') {
          // A pending invitation is refreshed, not doubled.
          had.since = clock();
          had.invitedBy = me;
          return _json(200, {'member': _memberJson(had)});
        }
        final waiting = orgs.values.where((o) => _rowOf(o, handle)?.state == 'invited').length;
        if (waiting >= _pendingInvites) return _refuse(409, 'They have as many invitations waiting as they can.');
        if (showing(org) >= _orgRows) return _refuse(409, 'The organization is full.');
        final invited = OrgRowKept(handle: handle, role: 'member', state: 'invited', since: clock(), invitedBy: me);
        org.rows[_lower(handle)] = invited;
        return _json(200, {'member': _memberJson(invited)});
      }
      if (members[2] != null) {
        final target = _rowOf(org, Uri.decodeComponent(members[2]!));
        if (target == null || target.state == 'declined') return _refuse(404, 'No one by that handle is in this organization.');
        if (method == 'DELETE') {
          final self = _lower(target.handle) == _lower(me);
          if (target.role == 'owner') return _refuse(403, 'Hand the organization over first.');
          if (!self) {
            if (row.role == 'member') return _refuse(403, 'Only the owner or an admin can remove a member.');
            if (target.role == 'admin' && row.role != 'owner') return _refuse(403, 'Only the owner can remove an admin.');
          }
          // A member gone owes the key a turn (S11); an invitee withdrawn had no wrap.
          if (target.state == 'member') org.turns += 1;
          org.rows.remove(_lower(target.handle));
          return _json(200, {'removed': true});
        }
        if (method == 'PUT') {
          if (row.role != 'owner') return _refuse(403, 'Only the owner can change a role.');
          if (_lower(target.handle) == _lower(me)) return _refuse(403, 'Hand the organization over first.');
          if (target.state == 'invited') return _refuse(409, 'They have not joined yet.');
          final role = body['role'];
          if (role != 'owner' && role != 'admin' && role != 'member') return _refuse(400, 'A role is owner, admin or member.');
          if (role == 'owner') row.role = 'admin';
          target.role = role as String;
          return _json(200, {'member': _memberJson(target)});
        }
      }
    }
    final orgLinks = RegExp(r'^orgs/([^/]+)/links(?:/([^/]+))?$').firstMatch(path);
    if (orgLinks != null) {
      final found = inOrg(Uri.decodeComponent(orgLinks[1]!));
      if (found == null) return _refuse(404, 'No such organization.');
      final (:org, :row) = found;
      if (row.role == 'member') return _refuse(403, 'Only the owner or an admin can do that.');
      final live = [for (final l in links.values) if (l.orgId == org.id && _working(l)) l];
      if (method == 'GET' && orgLinks[2] == null) return _json(200, {'links': [for (final l in live.reversed) l.toJson()]});
      if (method == 'POST' && orgLinks[2] == null) {
        final expiresIn = body['expiresIn'], maxUses = body['maxUses'];
        if (expiresIn is num && (expiresIn < 3600 || expiresIn > 30 * 24 * 3600)) return _refuse(400, 'A link lasts an hour to thirty days, or until it is turned off.');
        if (maxUses is num && (maxUses < 1 || maxUses > _orgRows)) return _refuse(400, 'A link may be used 1 to 50 times, or without a limit.');
        if (live.length >= 10) return _refuse(409, 'This organization has as many invite links as it can. Turn one off first.');
        final link = _linkTo(org, me, expiresIn is num ? clock() + (expiresIn * 1000).toInt() : null, maxUses is num ? maxUses.toInt() : null);
        return _json(201, {'link': link.toJson()});
      }
      if (method == 'DELETE' && orgLinks[2] != null) {
        final wanted = Uri.decodeComponent(orgLinks[2]!);
        final link = links.values.where((l) => l.orgId == org.id && l.id == wanted).firstOrNull;
        if (link == null) return _refuse(404, 'That invite link has expired or was turned off.');
        links.remove(link.code);
        return _json(200, {'dropped': true});
      }
    }
    final join = RegExp(r'^joins/([^/]+)$').firstMatch(path);
    if (join != null) {
      final link = links[Uri.decodeComponent(join[1]!)];
      final org = link != null && _working(link) ? orgs[link.orgId] : null;
      if (link == null || org == null) return _refuse(404, 'That invite link has expired or was turned off.');
      final had = _rowOf(org, me);
      if (method == 'GET') {
        return _json(200, {
          'org': {'id': org.id, 'name': org.name, 'hue': org.hue, 'members': _joined(org).length},
          'by': link.by,
          'member': had?.state == 'member',
        });
      }
      if (method == 'POST') {
        if (had != null && had.state == 'member') return _json(200, {'org': _orgJson(org, had)});
        if (had?.state != 'invited' && showing(org) >= _orgRows) return _refuse(409, 'The organization is full.');
        final row = OrgRowKept(handle: me, role: 'member', state: 'member', since: clock(), invitedBy: had?.invitedBy ?? link.by);
        org.rows[_lower(me)] = row;
        link.uses += 1;
        final notice = _pendingInvite(org.id);
        if (notice != null) _touch(notice, state: 'accepted');
        return _json(200, {'org': _orgJson(org, row)});
      }
    }
    final invite = RegExp(r'^orgs/([^/]+)/invite$').firstMatch(path);
    if (invite != null && method == 'POST') {
      final found = inOrg(Uri.decodeComponent(invite[1]!), const ['invited']);
      if (found == null) return _refuse(404, 'You were not invited.');
      final (:org, :row) = found;
      final notice = _pendingInvite(org.id);
      if (body['accept'] == true) {
        row.state = 'member';
        row.since = clock();
        if (notice != null) _touch(notice, state: 'accepted');
        return _json(200, {'org': _orgJson(org, row)});
      }
      row.state = 'declined';
      row.since = clock();
      if (notice != null) _touch(notice, state: 'declined');
      return _json(200, {'declined': true});
    }

    if (method == 'GET' && path == 'notifications') {
      final since = _num(query['since']);
      final asked = query['limit'] == null ? 100 : _num(query['limit']);
      final limit = asked.isNaN ? 1 : asked.clamp(1, 200).toInt();
      final newer = [for (final n in feed.values) if (n.rev > since) n]..sort((a, b) => a.rev.compareTo(b.rev));
      final items = newer.take(limit).toList();
      final more = newer.length > items.length;
      // The cursor is the last row given when there is more to come, and the account's head when there is not.
      return _json(200, {'rev': more ? items.last.rev : _counter, 'items': [for (final n in items) n.toJson()], 'more': more});
    }
    if (method == 'POST' && path == 'notifications') {
      final id = body['id'] == null ? '' : '${body['id']}';
      if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)) return _refuse(400, 'That is not an id.');
      if (!isSelfKind(body['kind'])) return _refuse(400, 'Only your own kinds can be posted.');
      final blob = body['blob'];
      if (blob is! String || blob.isEmpty || blob.length > 8 * 1024) return _refuse(400, 'A notification’s blob is up to 8 KB.');
      // An id this account already has: the same answer, and nothing written (a retry after a lost answer).
      final had = feed[id];
      if (had != null) return _json(200, {'rev': had.rev});
      final made = _fed(id: id, kind: body['kind'] as String, blob: blob);
      return _json(200, {'rev': made.rev});
    }
    if (method == 'POST' && path == 'notifications/read') {
      final ids = body['ids'] is List ? {for (final id in body['ids'] as List) '$id'} : null;
      final before = body['before'] is num ? body['before'] as num : double.infinity;
      for (final item in feed.values.toList()) {
        final wanted = body['all'] == true ? item.rev <= before : (ids?.contains(item.id) ?? false);
        if (wanted && item.readAt == null) _touch(item, readAt: clock);
      }
      return _json(200, {'rev': _counter});
    }
    final row = RegExp(r'^notifications/([^/]+)$').firstMatch(path);
    if (row != null && method == 'PUT') {
      final item = feed[Uri.decodeComponent(row[1]!)];
      if (item == null) return _refuse(404, 'No such notification.');
      int? Function()? readAt;
      if (body['read'] == true && item.readAt == null) readAt = clock;
      if (body['read'] == false) readAt = () => null;
      final hidden = body['hidden'] is bool ? body['hidden'] as bool : null;
      final next = readAt != null || hidden != null ? _touch(item, readAt: readAt, hidden: hidden) : item;
      return _json(200, {'rev': next.rev});
    }
    return null;
  }

  // --- what a test asks of it --------------------------------------------------------------------------------------

  SealKey _keyOf() => _account?.key ?? (throw StateError('The fake service holds no account key: only an account it was seeded with has one.'));

  /// The seeded account's key, for a test that seals or opens as a device of that account would.
  SealKey get accountKey => _keyOf();

  /// A live token for the account, as a device that signed in earlier holds one.
  String signedIn() {
    if (_account == null) throw StateError('The fake service holds no account to sign in to.');
    return _token();
  }

  /// Another device writing a note, sealed as the app seals it: `{ v: 1, note, ...extra }` under `note:<id>`.
  /// Answers the note's new revision.
  Future<int> deviceWrites(Note written, {Map<String, Object?> extra = const {}}) async {
    final rev = _nextRev();
    notes[written.id] = StoredNote(rev: rev, deleted: false, blob: await crypto.seal(_keyOf(), {'v': 1, 'note': noteToJson(written), ...extra}, 'note:${written.id}'));
    return rev;
  }

  /// What the account holds for a note, opened: the payload a client wrote, or null for none or a deletion.
  Future<Map<String, Object?>?> stored(String id) async {
    final blob = notes[id]?.blob;
    if (blob == null) return null;
    return (await crypto.open(_keyOf(), blob, 'note:$id') as Map).cast<String, Object?>();
  }

  /// Every token the service has handed out stops working at once, as a week passing would do.
  void expireAllTokens() => _tokens.clear();

  /// Whether the account is still there: false after a signup that never came, or after it was deleted.
  bool hasAccount() => _account != null;

  /// How many recovery codes the account has left unspent.
  int codesLeft() => _account?.recovery.length ?? 0;

  /// A peer's colour and encryption public key, as their own devices would have set them (docs/SHARED.md).
  void peerColour(String handle, String? hue) => hue == null ? _peerHues.remove(_lower(handle)) : _peerHues[_lower(handle)] = hue;
  void peerKey(String handle, String? pub) => pub == null ? _peerKeys.remove(_lower(handle)) : _peerKeys[_lower(handle)] = pub;

  /// A team's notes as stored, by id: each row's revision, blob and writer; and its logs by note.
  Map<String, TeamRow> teamNotes(String orgId) => orgs[orgId]?.notes ?? {};
  List<TeamUpdate> teamUpdates(String orgId, String noteId) => orgs[orgId]?.updates[noteId] ?? [];
  Map<String, StoredFile> teamFiles(String orgId) => orgs[orgId]?.files ?? {};

  /// The organization key's state as stored: the generation in force and each member's wraps by generation.
  ({int generation, Map<String, Map<int, String>> wraps}) keysOf(String orgId) {
    final org = orgs[orgId];
    return (generation: org?.generation ?? 0, wraps: {for (final MapEntry(:key, :value) in (org?.wraps ?? const <String, Map<int, String>>{}).entries) key: Map.of(value)});
  }

  /// The account's registered encryption key pair, as stored.
  ({String pub, String sealed})? get encryption => _account?.encryption;

  /// A row the service wrote into the account's feed - another account's doing - at a new revision. Answers it.
  FeedNotification notifies({required String kind, String? id, int? at, int? readAt, bool hidden = false, String? from, NotificationOrg? org, Map<String, Object?>? body, String? blob, String? state}) =>
      _fed(kind: kind, id: id, at: at, readAt: readAt, hidden: hidden, from: from, org: org, body: body, blob: blob, state: state);

  /// The AIs seen in an organization, as stored (`aisOf`).
  List<Map<String, Object?>> aisOf(String orgId) => [...?orgs[orgId]?.ais.values];

  /// An AI seen in an organization through [via]'s connector, as their own would tell it (`peerAi`). Answers its id.
  String peerAi(String orgId, String name, {String? via, int? firstSeen, int? lastSeen}) {
    final org = orgs[orgId];
    if (org == null) throw StateError('No such organization in the fake service.');
    final id = shortId();
    org.ais[id] = {'id': id, 'name': name, 'via': via ?? (peers.isNotEmpty ? peers.first : 'sam'), 'firstSeen': firstSeen ?? clock(), 'lastSeen': lastSeen ?? clock()};
    return id;
  }

  /// An organization [by] (a peer) made and invited the account to: the invitation lands in the feed. Answers the
  /// organization's id.
  String invited(String name, [String? by]) {
    final inviter = by ?? (peers.isNotEmpty ? peers.first : 'sam');
    final org = _peerOrg(name, inviter);
    final account = _account;
    if (account != null) {
      org.rows[_lower(account.handle)] = OrgRowKept(handle: account.handle, role: 'member', state: 'invited', since: clock(), invitedBy: inviter);
      _fed(kind: 'invite', from: inviter, org: (id: org.id, name: name), body: {'name': name}, state: 'pending');
    }
    return org.id;
  }

  /// An organization a peer made, with an invite link to it the account has been sent: answers the code.
  String peerLink(String name, {String? by, int? expiresAt, int? maxUses}) {
    final maker = by ?? (peers.isNotEmpty ? peers.first : 'sam');
    return _linkTo(_peerOrg(name, maker), maker, expiresAt, maxUses).code;
  }

  /// The account's row in an organization, as the service holds it; null when it has none.
  ({String role, String state})? rowIn(String orgId) {
    final org = orgs[orgId];
    final account = _account;
    final row = org != null && account != null ? _rowOf(org, account.handle) : null;
    return row != null ? (role: row.role, state: row.state) : null;
  }

  /// The settings as stored: the sealed blob and its revision, or null for none yet.
  ({int rev, String blob})? get prefs => _prefs;

  // --- over a socket -----------------------------------------------------------------------------------------------

  /// The same service on 127.0.0.1, at a port the system picks, under `/api`: for the `dart:io` fetcher's own test.
  /// [handle] may answer a request itself (a slow route, say); null from it is the service's answer.
  Future<FakeServer> listen({Future<FetchResponse?> Function(FetchRequest request)? handle}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((incoming) async {
      final bytes = BytesBuilder(copy: false);
      await incoming.forEach(bytes.add);
      final headers = <String, String>{};
      incoming.headers.forEach((name, values) => headers[name] = values.join(', '));
      final request = FetchRequest(method: incoming.method, url: incoming.uri, headers: headers, body: bytes.isEmpty ? null : bytes.takeBytes());
      try {
        final answer = await handle?.call(request) ?? await _fetch(request);
        incoming.response.statusCode = answer.status;
        answer.headers.forEach(incoming.response.headers.set);
        incoming.response.add(answer.bytes);
      } catch (_) {
        incoming.response.statusCode = 500;
      }
      await incoming.response.close().catchError((Object _) {});
    });
    return FakeServer._(server);
  }
}

/// A [FakeService] listening on 127.0.0.1.
class FakeServer {
  FakeServer._(this._server);
  final HttpServer _server;

  /// What an [Api] is given: `http://127.0.0.1:<port>/api`.
  String get base => 'http://127.0.0.1:${_server.port}/api';

  Future<void> close() => _server.close(force: true);
}
