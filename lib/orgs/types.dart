/// An organization as the service describes it (docs/TEAMS.md; server/src/orgs.rs): a name, a hue, and rows of
/// people by handle, each with a role and whether they have joined yet. A port of `src/app/core/orgs/types.ts`.
///
/// Plaintext on the service, as handles already are, so another account's invitation can reach this one; the notes
/// stay sealed.
///
/// What differs: the shapes are classes read forgivingly from the service's JSON (`fromJson`), where the page casts.
/// A role and a state are the web's own words, kept as strings as its unions are. The one rule about an
/// organization's workspace id (`orgWorkspaceId`, `orgIdOf`, `isOrgWorkspace`) was ported with the workspaces
/// (lib/core/workspaces.dart) and is exported from here too, as the page's leaf has it.
library;

import 'package:flutter/foundation.dart';

import '../core/workspaces.dart' show OrgLike;

export '../core/workspaces.dart' show isOrgWorkspace, orgIdOf, orgOfWorkspace, orgWorkspaceId, workspaceFamily;

/// `owner`, `admin` or `member` (`Role`).
const List<String> roles = ['owner', 'admin', 'member'];

bool isRole(Object? value) => value is String && roles.contains(value);

/// Whether a row has joined, or is still looking at the invitation (`MemberState`): `member` or `invited`.
bool isMemberState(Object? value) => value == 'member' || value == 'invited';

/// What the organization key needs, as the list says it (docs/SHARED.md, S2; `KeyNeeds`): the generation in force (0
/// while none has been made), whether this account holds a wrap at it, and how many members with a public key lack
/// one.
@immutable
class KeyNeeds {
  const KeyNeeds({this.generation = 0, this.mine = false, this.missing = 0, this.stale = false});

  /// What the key needs, as kept; a row from before keys reads as none made and nobody missing (`asKeys`).
  factory KeyNeeds.fromJson(Object? raw) {
    final k = raw is Map ? raw : const <Object?, Object?>{};
    final generation = k['generation'], missing = k['missing'];
    return KeyNeeds(generation: generation is num ? generation.toInt() : 0, mine: k['mine'] == true, missing: missing is num ? missing.toInt() : 0, stale: k['stale'] == true);
  }

  final int generation;
  final bool mine;
  final int missing;

  /// A member has left or been removed since the generation was made (S11): the key owes a turn.
  final bool stale;

  Map<String, Object?> toJson() => {'generation': generation, 'mine': mine, 'missing': missing, 'stale': stale};

  @override
  bool operator ==(Object other) => other is KeyNeeds && other.generation == generation && other.mine == mine && other.missing == missing && other.stale == stale;

  @override
  int get hashCode => Object.hash(generation, mine, missing, stale);

  @override
  String toString() => 'KeyNeeds(generation: $generation, mine: $mine, missing: $missing, stale: $stale)';
}

/// One of the organizations the account is in, or invited to: what `GET orgs` lists (`OrgRow`).
@immutable
class OrgRow implements OrgLike {
  const OrgRow({
    required this.id,
    required this.name,
    this.hue,
    required this.role,
    required this.state,
    this.members = 0,
    this.invitedBy,
    this.createdAt = 0,
    this.colour,
    this.keys = const KeyNeeds(),
  });

  /// A row as kept or as listed, if it has the shape this build reads; null for one it does not (`asRow`).
  static OrgRow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'], role = raw['role'], state = raw['state'];
    if (id is! String || name is! String || !isRole(role) || !isMemberState(state)) return null;
    final members = raw['members'], createdAt = raw['createdAt'];
    return OrgRow(
      id: id,
      name: name,
      hue: raw['hue'] is String ? raw['hue'] as String : null,
      role: role as String,
      state: state as String,
      members: members is num ? members.toInt() : 0,
      invitedBy: raw['invitedBy'] is String ? raw['invitedBy'] as String : null,
      createdAt: createdAt is num ? createdAt.toInt() : 0,
      colour: raw['colour'] is String ? raw['colour'] as String : null,
      keys: KeyNeeds.fromJson(raw['keys']),
    );
  }

  @override
  final String id;
  @override
  final String name;

  /// A workspace hue (lib/core/workspaces.dart `workspaceHues`), or null for the app's own ink.
  @override
  final String? hue;

  /// This account's role in it.
  final String role;

  /// Whether this account has joined (`member`), or is invited (`invited`).
  final String state;

  /// How many have joined.
  final int members;

  /// The handle that invited this account, for an invited row; null when that account is gone.
  final String? invitedBy;
  final int createdAt;

  /// This account's colour in it (docs/SHARED.md, S7): the organization's override, else the account's own, else
  /// null.
  final String? colour;

  /// What its key needs; a row kept by a build before keys reads as none made and nobody missing.
  final KeyNeeds keys;

  OrgRow copyWith({String? role, String? Function()? colour}) => OrgRow(
        id: id,
        name: name,
        hue: hue,
        role: role ?? this.role,
        state: state,
        members: members,
        invitedBy: invitedBy,
        createdAt: createdAt,
        colour: colour == null ? this.colour : colour(),
        keys: keys,
      );

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'hue': hue, 'role': role, 'state': state, 'members': members, 'invitedBy': invitedBy, 'createdAt': createdAt, 'colour': colour, 'keys': keys.toJson()};

  @override
  bool operator ==(Object other) =>
      other is OrgRow &&
      other.id == id &&
      other.name == name &&
      other.hue == hue &&
      other.role == role &&
      other.state == state &&
      other.members == members &&
      other.invitedBy == invitedBy &&
      other.createdAt == createdAt &&
      other.colour == colour &&
      other.keys == keys;

  @override
  int get hashCode => Object.hash(id, name, hue, role, state, members, invitedBy, createdAt, colour, keys);

  @override
  String toString() => 'OrgRow($id, $name, $role, $state)';
}

/// One person in an organization (`Member`).
@immutable
class Member {
  const Member({required this.handle, required this.role, required this.state, this.since = 0, this.invitedBy, this.colour, this.pub});

  static Member? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final handle = raw['handle'], role = raw['role'], state = raw['state'], since = raw['since'];
    if (handle is! String || !isRole(role) || !isMemberState(state)) return null;
    return Member(
      handle: handle,
      role: role as String,
      state: state as String,
      since: since is num ? since.toInt() : 0,
      invitedBy: raw['invitedBy'] is String ? raw['invitedBy'] as String : null,
      colour: raw['colour'] is String ? raw['colour'] as String : null,
      pub: raw['pub'] is String ? raw['pub'] as String : null,
    );
  }

  final String handle;
  final String role;
  final String state;

  /// When they joined, or were invited, in ms.
  final int since;
  final String? invitedBy;

  /// Their colour in this organization, or null for none (S7).
  final String? colour;

  /// Their encryption public key, to wrap the organization key to (S3); null until a device of theirs made one.
  final String? pub;

  @override
  String toString() => 'Member($handle, $role, $state)';
}

/// An AI that has read or written the organization's notes through a member's connector (docs/MCP.md,
/// "Organizations"; server/src/store/org_ais.rs; `OrgAi`). Matt: "when an AI has accessed an ORG add it as a member
/// labeled as (AI)". A record beside the members, never one of them: it holds no key wrap and takes no seat, and its
/// access is the member's own, so removing the entry removes the record and not the access.
@immutable
class OrgAi {
  const OrgAi({required this.id, required this.name, required this.via, this.firstSeen = 0, this.lastSeen = 0});

  /// An entry as the service answers it; null for one without its id, its name or whose connector it came through.
  static OrgAi? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'], via = raw['via'], firstSeen = raw['firstSeen'], lastSeen = raw['lastSeen'];
    if (id is! String || name is! String || via is! String) return null;
    return OrgAi(id: id, name: name, via: via, firstSeen: firstSeen is num ? firstSeen.toInt() : 0, lastSeen: lastSeen is num ? lastSeen.toInt() : 0);
  }

  final String id;

  /// What the AI's app called itself: "Claude".
  final String name;

  /// The handle of the member whose connector it came through.
  final String via;

  /// When it was first and last seen, in ms.
  final int firstSeen;
  final int lastSeen;

  @override
  String toString() => 'OrgAi($id, $name, via $via)';
}

/// An organization in full: what `GET orgs/{id}` answers a member (`Org`).
@immutable
class Org implements OrgLike {
  const Org({
    required this.id,
    required this.name,
    this.hue,
    required this.role,
    required this.state,
    this.members = const [],
    this.ais = const [],
    this.invitedBy,
    this.createdAt = 0,
    this.colour,
    this.keys = const KeyNeeds(),
  });

  /// The organization an answer carries; a [FormatException] for a body that is not one.
  factory Org.fromJson(Object? raw) {
    final row = OrgRow.fromJson(raw is Map ? {...raw, 'members': 0} : raw);
    if (row == null || raw is! Map) throw const FormatException('The service answered without the organization.');
    final members = raw['members'], ais = raw['ais'];
    return Org(
      id: row.id,
      name: row.name,
      hue: row.hue,
      role: row.role,
      state: row.state,
      members: List.unmodifiable([
        if (members is List)
          for (final each in members) ?Member.fromJson(each),
      ]),
      ais: List.unmodifiable([
        if (ais is List)
          for (final each in ais) ?OrgAi.fromJson(each),
      ]),
      invitedBy: row.invitedBy,
      createdAt: row.createdAt,
      colour: row.colour,
      keys: row.keys,
    );
  }

  @override
  final String id;
  @override
  final String name;
  @override
  final String? hue;
  final String role;
  final String state;
  final List<Member> members;

  /// The AIs seen in it; none from a service before them, which never says.
  final List<OrgAi> ais;
  final String? invitedBy;
  final int createdAt;
  final String? colour;
  final KeyNeeds keys;

  /// A row of the kept list as a full organization answers it (`rowOf`).
  OrgRow get row => OrgRow(
        id: id,
        name: name,
        hue: hue,
        role: role,
        state: state,
        members: members.where((m) => m.state == 'member').length,
        invitedBy: invitedBy,
        createdAt: createdAt,
        colour: colour,
        keys: keys,
      );

  @override
  String toString() => 'Org($id, $name, $role, $state)';
}

/// An invite link, as the owner and admins see it (server/src/store/org_links.rs; `InviteLink`): a code anyone
/// signed in who holds it may join with, until it expires, is used up or is turned off.
@immutable
class InviteLink {
  const InviteLink({required this.id, required this.code, this.createdAt = 0, this.expiresAt, this.maxUses, this.uses = 0, this.by});

  factory InviteLink.fromJson(Object? raw) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final id = map['id'], code = map['code'];
    if (id is! String || code is! String) throw const FormatException('The service answered without the link.');
    final createdAt = map['createdAt'], expiresAt = map['expiresAt'], maxUses = map['maxUses'], uses = map['uses'];
    return InviteLink(
      id: id,
      code: code,
      createdAt: createdAt is num ? createdAt.toInt() : 0,
      expiresAt: expiresAt is num ? expiresAt.toInt() : null,
      maxUses: maxUses is num ? maxUses.toInt() : null,
      uses: uses is num ? uses.toInt() : 0,
      by: map['by'] is String ? map['by'] as String : null,
    );
  }

  final String id;
  final String code;
  final int createdAt;

  /// When it stops working, in ms; null for when it is turned off.
  final int? expiresAt;

  /// How many may join by it; null for no limit.
  final int? maxUses;
  final int uses;

  /// The handle of who made it; null once their account is gone.
  final String? by;
}

/// What a working code says before it is followed: enough to ask "Join it?", and nothing about who is in it
/// (`JoinPreview`).
@immutable
class JoinPreview {
  const JoinPreview({required this.orgId, required this.name, this.hue, this.members = 0, this.by, this.member = false});

  factory JoinPreview.fromJson(Object? raw) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    final org = map['org'];
    if (org is! Map || org['id'] is! String || org['name'] is! String) throw const FormatException('The service answered without the organization.');
    final members = org['members'];
    return JoinPreview(
      orgId: org['id'] as String,
      name: org['name'] as String,
      hue: org['hue'] is String ? org['hue'] as String : null,
      members: members is num ? members.toInt() : 0,
      by: map['by'] is String ? map['by'] as String : null,
      member: map['member'] == true,
    );
  }

  final String orgId;
  final String name;
  final String? hue;
  final int members;
  final String? by;

  /// Whether the caller is in it already.
  final bool member;
}

/// What this device keeps of the account's organizations: the list as the service last gave it (`OrgState`).
@immutable
class OrgState {
  const OrgState({this.list = const [], this.at, this.colour});

  /// Nothing kept (`NONE`).
  static const OrgState none = OrgState();

  /// A state as kept, or null for a shape that is none (`asState`).
  static OrgState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['list'], at = raw['at'], colour = raw['colour'];
    if (list is! List) return null;
    return OrgState(list: List.unmodifiable([for (final each in list) ?OrgRow.fromJson(each)]), at: at is num ? at.toInt() : null, colour: colour is String ? colour : null);
  }

  final List<OrgRow> list;

  /// When the list was last taken from the service, in ms; null for never.
  final int? at;

  /// The account's own colour (S7), as the list last said it; null for none.
  final String? colour;

  OrgState copyWith({List<OrgRow>? list, String? Function()? colour}) => OrgState(list: list ?? this.list, at: at, colour: colour == null ? this.colour : colour());

  Map<String, Object?> toJson() => {'list': [for (final row in list) row.toJson()], 'at': at, 'colour': colour};

  @override
  bool operator ==(Object other) => other is OrgState && other.at == at && other.colour == colour && listEquals(other.list, list);

  @override
  int get hashCode => Object.hash(at, colour, Object.hashAll(list));

  @override
  String toString() => 'OrgState(${list.length} rows, at: $at, colour: $colour)';
}
