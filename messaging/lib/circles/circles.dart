/// The circles this device is in, kept, gossiped and shared (lib/circles/circle.dart says what a circle is).
///
/// - **Kept** with the device's choices (`circles`), and the seeds of circles left (`circles_gone`) so the phone and
///   its computer don't hand one back to each other.
/// - **Gossiped** in each circle's own room on the hub ([CircleRoom]): coming in, a device asks for a newer manifest
///   than its own, and whoever has one says it; a change is said to everyone there. Each device keeps the newest one
///   that checks out (signed by the owner or an admin the owner granted).
/// - **Shared** with friends (an envelope of kind `voice`, `t: circle`, as a space is: lib/voice/channels.dart) or by
///   a link (Circle.link; site/join explains it in a browser).
/// - **The phone and its computer** keep the same circles: the phone's list goes with its spaces when the computer
///   asks (Voice.syncNow), and a circle made or changed on the computer goes to the phone (`op: circle`).
///
/// A circle's spaces are handed to Voice ([Voice.setCircled]), which holds each one's chat room as it does a space of
/// one's own, for previews and unread counts; they are listed in their circle, not in Messages.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../friends/buddies.dart';
import '../me/me.dart';
import '../net/crypto.dart';
import '../net/hub_carrier.dart';
import '../net/net.dart';
import '../net/packet.dart';
import '../net/switchboard.dart';
import '../sms.dart';
import '../voice/channels.dart';
import '../voice/voice.dart';
import 'circle.dart';

export 'circle.dart';

/// A circle offered to this device and not yet taken up: a friend's invite (Circles.share), or a circle's link opened
/// from outside the app. It waits, with Join and Not now, until it is joined or dismissed (Matt, 2026-11-17: "Finish the
/// missing pieces that went unfinished", of Circles: until then a friend's invite joined the circle at once, unasked,
/// and was never shown).
@immutable
class CircleInvite {
  const CircleInvite(this.circle, this.from, this.at, {this.later = false, this.link = false, this.fresh = false});

  /// The circle as the invite or link gave it: a link's has only its name until it is joined.
  final Circle circle;

  /// Who invited this device, as it knows them; empty for a link.
  final String from;
  final DateTime at;

  /// Not now was pressed: kept under Invites in the Circles tab, without the card or the banner.
  final bool later;

  /// The circle (its owner above all) came from a link, which a friend's invite for the same circle doesn't override.
  final bool link;

  /// Came since the app started, and not yet answered: the banner over everything says it. Not kept.
  final bool fresh;

  String get seed => circle.seed;

  /// How many spaces the circle has, where that is known: a link says only its name until the circle is joined.
  int? get spaceCount => circle.manifest.isSigned || circle.spaces.isNotEmpty ? circle.spaces.length : null;

  CircleInvite copyWith({Circle? circle, String? from, bool? later, bool? link, bool? fresh}) =>
      CircleInvite(circle ?? this.circle, from ?? this.from, at, later: later ?? this.later, link: link ?? this.link, fresh: fresh ?? this.fresh);

  Map<String, Object?> toJson() => {'c': circle.toJson(), 'f': from, 'at': at.millisecondsSinceEpoch, if (later) 'l': 1, if (link) 'k': 1};

  static CircleInvite? fromJson(Object? j) {
    if (j is! Map) return null;
    final c = Circle.fromJson(j['c']);
    if (c == null) return null;
    return CircleInvite(c, j['f'] is String ? j['f'] as String : '', DateTime.fromMillisecondsSinceEpoch(j['at'] is int ? j['at'] as int : 0), later: j['l'] == 1, link: j['k'] == 1);
  }
}

/// [words] trimmed and cut to 100 characters, as a circle's, a space's or a heading's name is kept: a pasted page of
/// text as a name would make the manifest too big to pass on. Null stays null.
String? capName(String? words) {
  final w = words?.trim();
  if (w == null || w.length <= 100) return w;
  return w.substring(0, 100).trim();
}

class Circles extends ChangeNotifier {
  Circles._();
  static final Circles instance = Circles._();

  /// For a test: a manager of its own, with no device choices.
  @visibleForTesting
  factory Circles.forTest({NetSigner? signer, VoiceRoute? route, AppState? app}) {
    final c = Circles._()
      ..signerOverride = signer
      .._route = route;
    if (app != null) {
      c._app = app;
      c._load(app);
    }
    return c;
  }

  AppState? _app;
  VoiceRoute? _route;

  /// The circles this device is in, in the order they were joined.
  List<Circle> all = [];

  /// The seeds of circles left here or on the phone or computer, the newest [_goneKept].
  final List<String> _gone = [];
  static const _goneKept = 300;

  final Map<String, CircleRoom> _rooms = {};

  /// Circles offered to this device and not yet joined, the newest first: friends' invites and links opened from
  /// outside the app, until each is joined ([acceptInvite]) or dismissed ([dismissInvite]). Kept (`circle_invites`), so
  /// Not now keeps one for later, across launches.
  List<CircleInvite> invites = [];
  static const _invitesKept = 20;

  /// The invite the banner over everything shows: the newest that came since the app started and hasn't been answered.
  CircleInvite? get invite => invites.where((i) => i.fresh && !i.later).firstOrNull;

  /// The invite waiting for [seed]'s circle, where there is one.
  CircleInvite? inviteFor(String seed) => invites.where((i) => i.seed == seed).firstOrNull;

  /// For a test: what signs manifests in place of Voice's signer.
  @visibleForTesting
  NetSigner? signerOverride;

  NetSigner? get signer => signerOverride ?? Voice.instance.signer;

  bool removed(String seed) => _gone.contains(seed);

  Future<void> start(AppState app) async {
    if (_app != null) return;
    _app = app;
    _load(app);
    Net.instance.listen(_received);
    Voice.instance.addListener(_follow);
    _changed(keep: false);
    _follow();
  }

  void _load(AppState app) {
    try {
      all = [for (final j in jsonDecode(app.choice('circles', '[]')) as List) ?Circle.fromJson(j)];
      _gone.addAll((jsonDecode(app.choice('circles_gone', '[]')) as List).whereType<String>());
      final seen = jsonDecode(app.choice('circles_seen', '{}')) as Map;
      for (final e in seen.entries) {
        _seen['${e.key}'] = {for (final p in ((e.value as Map?) ?? const {}).entries) '${p.key}': '${p.value}'};
      }
    } catch (_) {}
    try {
      // One for a circle joined meanwhile (on the phone or computer) has been answered.
      invites = [for (final j in jsonDecode(app.choice('circle_invites', '[]')) as List) ?CircleInvite.fromJson(j)].where((i) => bySeed(i.seed) == null).toList();
    } catch (_) {}
  }

  Circle? bySeed(String seed) => all.where((c) => c.seed == seed).firstOrNull;

  /// The circle [space] is a space of, where it is one.
  Circle? circleOf(VoiceChannel space) => space.circle == null ? null : bySeed(space.circle!);

  // --- what the lists show ------------------------------------------------------------------------------------------

  /// How many messages from others in [c]'s spaces came after this device last read each.
  int unread(Circle c) => c.channels.fold(0, (n, s) => n + Voice.instance.unreadIn(s));

  /// How many of those mention this device (Voice.mentionsIn).
  int mentions(Circle c) => c.channels.fold(0, (n, s) => n + Voice.instance.mentionsIn(s));

  /// Who is in a call in [c] now, by id, each once.
  List<String> inVoice(Circle c) => {for (final s in c.channels) if (s.hasVoice) ...Voice.instance.inChannel(s)}.toList();

  /// Everyone this device has seen in each circle, by circle seed, then id, with the name they gave: who was here, wrote
  /// in a space or added a file, kept so they are still among its members once they have gone (Matt, 2026-11-18: "I
  /// still don't see memebers i added in the members list on mobile even though they are posting files").
  final Map<String, Map<String, String>> _seen = {};

  /// Who has been seen in [c], by id, with their name ('' where none was given).
  Map<String, String> seenIn(Circle c) => _seen[c.seed] ?? const {};

  /// Keeps [people] (id to name) as seen in [c]; a name is kept over none, a newer over an older. Saved only where
  /// something is new, and told no one: it is asked while the members list is drawn.
  void noteSeen(Circle c, Map<String, String> people) {
    final have = _seen.putIfAbsent(c.seed, () => {});
    var changed = false;
    for (final e in people.entries) {
      if (e.key.isEmpty) continue;
      final had = have[e.key];
      if (had == null || (e.value.isNotEmpty && e.value != had)) {
        have[e.key] = e.value.isNotEmpty ? e.value : (had ?? '');
        changed = true;
      }
    }
    if (changed) _app?.set('circles_seen', jsonEncode(_seen));
  }

  /// How many are in [c]'s room now, this device among them; 0 before it is joined.
  int onlineIn(Circle c) {
    final r = _rooms[c.seed];
    return r == null || !r.opened ? 0 : r.present.length + 1;
  }

  /// Who else is in [c]'s room now, by id: the circle's settings list them among its people.
  Set<String> presentIn(Circle c) {
    final r = _rooms[c.seed];
    return r == null || !r.opened ? const {} : {...r.present};
  }

  /// [c]'s voice spaces with anyone in them now.
  List<VoiceChannel> liveSpaces(Circle c) => [for (final s in c.channels) if (s.hasVoice && Voice.instance.live(s)) s];

  // --- making and changing ------------------------------------------------------------------------------------------

  /// Whether this install may change [c]: its owner, or an admin the owner granted.
  bool canEdit(Circle c) {
    final s = signer;
    return s != null && c.manifest.canSign(s.id);
  }

  /// Makes a circle named [name] in [hue] with [icon], owned by this install, with a texting space and a voice space to
  /// start with (or [spaces]).
  Future<Circle?> make({required String name, String? hue, String icon = 'users', String? picture, List<CircleSpace>? spaces}) async {
    final s = signer;
    if (s == null) return null;
    final owner = NetCrypto.hex(s.publicKey);
    final seed = NetCrypto.hex(NetCrypto.randomBytes(32));
    final first = CircleManifest(
      owner: owner,
      version: 1,
      name: capName(name)!.isEmpty ? 'Circle' : capName(name)!,
      hue: hue != null && circleHues.contains(hue) ? hue : hueOfSeed(seed),
      icon: icon,
      picture: picture != null && picture.length <= circlePictureMax ? picture : null,
      spaces: spaces ?? [CircleSpace.make('General', kind: SpaceKind.text, order: 0), CircleSpace.make('Lounge', order: 1)],
    );
    final signed = await first.signedBy(s.id, s.publicKey, s.sign);
    final c = Circle(seed: seed, owner: owner, manifest: signed, mine: true);
    all = [...all, c];
    _changed();
    _toPhone(c);
    return c;
  }

  /// Changes [c]'s name, colour, icon or picture.
  Future<bool> edit(Circle c, {String? name, String? hue, String? icon, String? picture, bool clearPicture = false}) {
    if (hue != null && !circleHues.contains(hue)) return Future.value(false);
    if (picture != null && picture.length > circlePictureMax) return Future.value(false);
    final n = capName(name);
    return _publish(c, (m) => m.next(name: n == null || n.isEmpty ? null : n, hue: hue, icon: icon, picture: picture, clearPicture: clearPicture));
  }

  /// Adds a space named [name] of [kind] to [c], at the end of [section] (or of the list); gives it back.
  Future<CircleSpace?> addSpace(Circle c, String name, {SpaceKind kind = SpaceKind.voice, String? section, Map<String, Object?> extra = const {}}) async {
    final words = capName(name)!;
    final heading = capName(section);
    final last = c.manifest.spaces.fold(-1, (n, s) => s.order > n ? s.order : n);
    final space = CircleSpace.make(words.isEmpty ? kind.label : words, kind: kind, order: last + 1, section: heading == null || heading.isEmpty ? null : heading, extra: extra);
    final ok = await _publish(c, (m) => m.next(spaces: [...m.spaces, space]));
    return ok ? space : null;
  }

  /// Renames, retypes or moves a space of [c] under another heading ([clearSection]: under none).
  Future<bool> updateSpace(Circle c, String seed, {String? name, SpaceKind? kind, String? section, bool clearSection = false}) {
    if (c.space(seed) == null) return Future.value(false);
    final n = capName(name);
    return _publish(c, (m) => m.next(spaces: [
          for (final s in m.spaces) s.seed == seed ? s.copyWith(name: n == null || n.isEmpty ? null : n, kind: kind, section: capName(section), clearSection: clearSection) : s,
        ]));
  }

  /// Takes a space out of [c]'s list, with what it said of each role. Its chat stays with whoever has it; it is just no
  /// longer the circle's.
  Future<bool> removeSpace(Circle c, String seed) {
    if (c.space(seed) == null) return Future.value(false);
    return _publish(c, (m) {
      final left = [for (final s in m.spaces) if (s.seed != seed) s];
      return m.next(spaces: left, extra: m.overrides.containsKey(seed) ? m.withOverrides(m.overrides, spaces: left) : null);
    });
  }

  /// Moves a space to [index] in [c]'s list (and under [section], where given): every space is numbered again in its
  /// new order.
  Future<bool> moveSpace(Circle c, String seed, int index, {String? section, bool clearSection = false}) {
    final list = c.spaces;
    final at = list.indexWhere((s) => s.seed == seed);
    if (at < 0) return Future.value(false);
    final moving = list.removeAt(at).copyWith(section: section, clearSection: clearSection);
    list.insert(index.clamp(0, list.length), moving);
    return _publish(c, (m) => m.next(spaces: [for (final (i, s) in list.indexed) s.copyWith(order: i)]));
  }

  /// Makes [id] an admin of [c], who may then change it too; the owner's alone to do.
  Future<bool> grantAdmin(Circle c, String id, {bool on = true}) async {
    final s = signer;
    if (s == null || s.id != c.manifest.ownerId) return false;
    final have = bySeed(c.seed) ?? c;
    final grants = {...have.manifest.adminGrants};
    if (on) {
      grants[id] = NetCrypto.hex(await s.sign(CircleManifest.grantMessage(c.owner, id)));
    } else {
      grants.remove(id);
    }
    // A new generation of the admin list, signed by the owner alone: it outranks every manifest signed under an older
    // list, so a removed admin's manifests (however high they numbered them) lose to this one, for new joiners too.
    final gv = have.manifest.grantsVersion + 1;
    final gs = NetCrypto.hex(await s.sign(CircleManifest.grantsMessage(c.owner, gv, grants)));
    return _publish(c, (m) => m.next(adminGrants: grants, grantsVersion: gv, grantsSig: gs, restart: true));
  }

  // --- roles (Matt, 2026-11-18: "Build custom roles") -----------------------------------------------------------------
  // A role that can change the circle, its spaces or its roles gives its holder the owner's admin grant too: every
  // version of the app checks a manifest by who signed it, so whoever may change the circle must be able to sign. Only
  // the owner can give that grant, so only the owner gives such a role; the finer permissions are this version's.

  /// What this install may do in [c].
  Set<CirclePerm> myPerms(Circle c) {
    final id = signer?.id;
    return id == null ? const {} : (bySeed(c.seed) ?? c).manifest.permsOf(id);
  }

  bool can(Circle c, CirclePerm p) => myPerms(c).contains(p);

  /// Whether this install may do [p] in [space]: always outside a circle; inside one, as its roles say and then as the
  /// space says of them (CircleManifest.permsIn: its overrides, Deny, As the circle says or Allow for each role). Every
  /// place that asks (writing in a chat, joining a call, adding a file, inviting) obeys a space's overrides by this.
  bool allows(VoiceChannel space, CirclePerm p) {
    final c = circleOf(space);
    final id = signer?.id;
    return c == null || id == null || c.manifest.permsIn(id, space.seed).contains(p);
  }

  /// Whether this install may change, move, give or take away [roleId] in [c]: one under their own highest role, or any
  /// for the owner (CircleManifest.mayManageRole).
  bool mayManageRole(Circle c, String roleId) {
    final id = signer?.id;
    return id != null && (bySeed(c.seed) ?? c).manifest.mayManageRole(id, roleId);
  }

  /// Adds [role] to [c] (at the bottom of the list, over everyone), or changes the one with its id. One that can change
  /// things is the owner's alone to give; one at or above this install's own highest role isn't theirs to change.
  Future<bool> saveRole(Circle c, CircleRole role) async {
    final have = bySeed(c.seed) ?? c;
    if (!can(have, CirclePerm.roles) || role.name.trim().isEmpty || !mayManageRole(have, role.id)) return false;
    final before = have.manifest.roles.where((r) => r.id == role.id).firstOrNull;
    final isOwner = signer?.id == have.manifest.ownerId;
    if (!isOwner && role.signs && !(before?.signs ?? false)) return false;
    final roles = before == null ? [...have.manifest.roles, role] : [for (final r in have.manifest.roles) r.id == role.id ? role : r];
    if (roles.length > circleRolesMax) return false;
    final holders = [for (final e in have.manifest.roleAssignments.entries) if (e.value.contains(role.id)) e.key];
    final ok = await _publish(have, (m) => m.next(extra: m.withRoles(roles: roles)));
    if (ok) await _grantsFor(have, holders);
    return ok;
  }

  /// Takes [roleId] out of [c], and from everyone who had it.
  Future<bool> deleteRole(Circle c, String roleId) async {
    final have = bySeed(c.seed) ?? c;
    if (!can(have, CirclePerm.roles) || !mayManageRole(have, roleId)) return false;
    final holders = [for (final e in have.manifest.roleAssignments.entries) if (e.value.contains(roleId)) e.key];
    final ok = await _publish(have, (m) {
      final left = [for (final r in m.roles) if (r.id != roleId) r];
      final roles = m.withRoles(roles: left, assignments: {for (final e in m.roleAssignments.entries) e.key: [for (final id in e.value) if (id != roleId) id]});
      // What each space said of it goes with it.
      final spoke = m.overrides.values.any((per) => per.containsKey(roleId));
      return m.next(extra: spoke ? CircleManifest(owner: m.owner, name: m.name, spaces: m.spaces, extra: roles).withOverrides(m.overrides, roles: left) : roles);
    });
    if (ok) await _grantsFor(have, holders);
    return ok;
  }

  /// Gives [member] exactly [roleIds] in [c] (none takes every role away). Each role given or taken away must be under
  /// this install's own highest (the owner's: any).
  Future<bool> setRolesOf(Circle c, String member, List<String> roleIds) async {
    final have = bySeed(c.seed) ?? c;
    if (!can(have, CirclePerm.roles) || member == have.manifest.ownerId) return false;
    final isOwner = signer?.id == have.manifest.ownerId;
    final giving = [for (final r in have.manifest.roles) if (roleIds.contains(r.id)) r];
    final had = have.manifest.rolesOf(member);
    final changed = {...giving.map((r) => r.id)}.difference({...had.map((r) => r.id)}).union({...had.map((r) => r.id)}.difference({...giving.map((r) => r.id)}));
    if (changed.any((id) => !mayManageRole(have, id))) return false;
    if (!isOwner && giving.any((r) => r.signs) != had.any((r) => r.signs)) return false;
    final ok = await _publish(have, (m) => m.next(extra: m.withRoles(assignments: {...m.roleAssignments, member: [for (final r in giving) r.id]})));
    if (ok) await _grantsFor(have, [member]);
    return ok;
  }

  /// Puts [c]'s roles in the [order] given (their ids, highest first; Matt, 2026-11-18: "permission hierarchy"). Only
  /// the roles under this install's own highest may move, and only among themselves (CircleManifest.mayOrder).
  Future<bool> orderRoles(Circle c, List<String> order) {
    final have = bySeed(c.seed) ?? c;
    final id = signer?.id;
    if (id == null || !have.manifest.mayOrder(id, order)) return Future.value(false);
    final byId = {for (final r in have.manifest.roles) r.id: r};
    if (order.indexed.every((e) => have.manifest.roles[e.$1].id == e.$2)) return Future.value(true);
    return _publish(have, (m) => m.next(extra: m.withRoles(roles: [for (final rid in order) ?byId[rid]])));
  }

  /// Moves [roleId] from its place to [index] in [c]'s list (0 the highest): a drag, or Move up / Move down.
  Future<bool> moveRole(Circle c, String roleId, int index) {
    final have = bySeed(c.seed) ?? c;
    final ids = [for (final r in have.manifest.roles) r.id];
    if (!ids.remove(roleId)) return Future.value(false);
    ids.insert(index.clamp(0, ids.length), roleId);
    return orderRoles(have, ids);
  }

  /// What the space [spaceSeed] of [c] says of [perm] for [roleId] (or everyone, CircleManifest.everyoneId): Deny,
  /// As the circle says, or Allow. For whoever may manage spaces, and only for everyone or a role under their own.
  Future<bool> setOverride(Circle c, String spaceSeed, String roleId, CirclePerm perm, PermOverride state) {
    final have = bySeed(c.seed) ?? c;
    final space = have.space(spaceSeed);
    if (space == null || !can(have, CirclePerm.spaces) || !CirclePerm.inSpace(space.kind).contains(perm)) return Future.value(false);
    if (roleId != CircleManifest.everyoneId && (!have.manifest.roles.any((r) => r.id == roleId) || !mayManageRole(have, roleId))) return Future.value(false);
    if (have.manifest.overrideOf(spaceSeed, roleId).of(perm) == state) return Future.value(true);
    return _publish(have, (m) {
      final all = {for (final e in m.overrides.entries) e.key: {...e.value}};
      final per = all[spaceSeed] ??= {};
      per[roleId] = (per[roleId] ?? CircleOverride.none).withState(perm, state);
      return m.next(extra: m.withOverrides(all));
    });
  }

  /// Puts every override [spaceSeed] has for [roleId] back to As the circle says.
  Future<bool> clearOverrides(Circle c, String spaceSeed, String roleId) {
    final have = bySeed(c.seed) ?? c;
    if (have.space(spaceSeed) == null || !can(have, CirclePerm.spaces)) return Future.value(false);
    if (roleId != CircleManifest.everyoneId && !mayManageRole(have, roleId)) return Future.value(false);
    if (have.manifest.overrideOf(spaceSeed, roleId).isEmpty) return Future.value(true);
    return _publish(have, (m) {
      final all = {for (final e in m.overrides.entries) e.key: {...e.value}};
      all[spaceSeed]?.remove(roleId);
      return m.next(extra: m.withOverrides(all));
    });
  }

  /// What everyone in [c] may do. Changing the circle, its spaces or roles is never everyone's.
  /// Turns the plugin [id] on or off for everyone in [c], with [choices] for the circle: only whoever may change the
  /// circle (its owner, or an admin with Change the circle).
  Future<bool> setPlugin(Circle c, String id, {required bool on, Map<String, Object?> choices = const {}}) {
    final have = bySeed(c.seed) ?? c;
    if (!can(have, CirclePerm.circle)) return Future.value(false);
    return _publish(have, (m) => m.next(extra: m.withPlugin(id, on: on, choices: choices)));
  }

  /// What [space]'s circle says of the plugin [id]: null outside a circle, or where it has said nothing.
  bool? pluginOnIn(VoiceChannel space, String id) => circleOf(space)?.manifest.pluginOn(id);

  Future<bool> setEveryone(Circle c, Set<CirclePerm> perms) {
    final have = bySeed(c.seed) ?? c;
    if (!can(have, CirclePerm.roles)) return Future.value(false);
    return _publish(have, (m) => m.next(extra: m.withRoles(everyone: {for (final p in perms) if (!p.signs) p})));
  }

  /// The owner's admin grant for each of [ids], whose roles just changed, as their roles now ask: given where a role can
  /// change things, taken back where none does. Someone given roles is governed by them from then on; an admin made by
  /// hand and never given a role is not among [ids], and is left as they are.
  Future<void> _grantsFor(Circle c, List<String> ids) async {
    if (signer?.id != (bySeed(c.seed) ?? c).manifest.ownerId) return;
    for (final id in ids) {
      final m = (bySeed(c.seed) ?? c).manifest;
      final mine = m.rolesOf(id);
      final needs = mine.any((r) => r.signs);
      final has = m.granted(id);
      if (needs && !has) {
        await grantAdmin(c, id);
      } else if (!needs && has) {
        await grantAdmin(c, id, on: false);
      }
    }
  }

  /// [c]'s next manifest, made by [change], signed here, taken, and said to the circle and the phone. Refused (false)
  /// where it would not fit one packet on the hub, which a reader would drop on the floor: a member's copy would never
  /// change again, and the next launch here would lose the circle.
  Future<bool> _publish(Circle c, CircleManifest Function(CircleManifest m) change) async {
    final s = signer;
    final have = bySeed(c.seed) ?? c;
    if (s == null || !have.manifest.canSign(s.id)) return false;
    var draft = change(have.manifest);
    // Numbered to the top: the owner starts the numbers again under a new admin list (CircleManifest.versionCap).
    if (draft.version >= CircleManifest.versionCap) {
      if (s.id != have.manifest.ownerId) return false;
      final gv = have.manifest.grantsVersion + 1;
      final gs = NetCrypto.hex(await s.sign(CircleManifest.grantsMessage(have.owner, gv, draft.adminGrants)));
      draft = draft.next(grantsVersion: gv, grantsSig: gs, restart: true);
    }
    final signed = await draft.signedBy(s.id, s.publicKey, s.sign);
    if (!signed.fitsAPacket) return false;
    final next = have.merged(signed);
    if (next == null) return false;
    _put(next);
    _rooms[next.seed]?.say(next.manifest);
    _toPhone(next);
    return true;
  }

  // --- joining and leaving ------------------------------------------------------------------------------------------

  /// Comes into [c]: kept, its room joined (where its manifest comes from, if this one is only what a link said), and
  /// its spaces' chats held. One already here takes [c]'s manifest only where it is newer.
  Circle join(Circle c) {
    _unmarkGone(c.seed);
    // Joined some other way (its link pasted, or on the phone or computer): its invite has been answered.
    if (invites.any((i) => i.seed == c.seed)) _setInvites([for (final i in invites) if (i.seed != c.seed) i]);
    final have = bySeed(c.seed);
    if (have != null) {
      final next = have.merged(c.manifest);
      if (next != null) _put(next);
      return bySeed(c.seed)!;
    }
    all = [...all, c];
    _changed();
    // A join is said as one (circle-join), so a phone that had it as left takes it back rather than leaving it again
    // on the next sync, as a plain `circle` did.
    if (Sms.paired) unawaited(Sms.instance.voiceSync({'op': 'circle-join', 'c': c.toJson()}).catchError((_) => <String, dynamic>{}));
    return c;
  }

  /// Comes into the circle a link is; null where it is not a circle's link. For a link pasted into the app (+ New ›
  /// Join a circle by link), which is asking to join; one opened from outside the app is [offerLink].
  Circle? joinLink(String link) {
    final c = Circle.fromLink(link);
    if (c == null) return null;
    // An invite from a friend may have named another owner: the link is the one to go by.
    final waiting = inviteFor(c.seed);
    return join(waiting != null && waiting.circle.owner == c.owner ? (waiting.circle.merged(c.manifest) ?? waiting.circle) : c);
  }

  /// The first circle's link in [text] (the link alone, or an invite's words with it, as circleInviteWords writes
  /// them); null where there is none.
  static String? linkIn(String? text) {
    if (text == null) return null;
    final m = RegExp(r'https://gogho\.st/join/#c\.[0-9a-f]{64}(?:\.[A-Za-z0-9_-]*)?(?:\.0[23][0-9a-f]{64})?').firstMatch(text);
    return m == null || Circle.fromLink(m.group(0)!) == null ? null : m.group(0);
  }

  /// A circle's link opened from outside the app (a tap on gogho.st/join/#c.…, or the link shared to the app): the
  /// circle itself where it is held already, to open; else an invite to it, to Join or put off, as a friend's is. Null
  /// where [link] is not a circle's.
  ({Circle? held, CircleInvite? invite})? offerLink(String link) {
    final c = Circle.fromLink(link);
    if (c == null) return null;
    final held = bySeed(c.seed);
    if (held != null) return (held: held, invite: null);
    return (held: null, invite: offer(c, from: '', link: true));
  }

  /// [c], offered by [from] (a friend's name, or empty for a link): waiting among [invites] until it is joined or
  /// dismissed. One already held only takes the offer's manifest where it is newer, and gives back null.
  ///
  /// Offered again, it comes back to the top as new, Not now or not. Where a link and a friend's invite name different
  /// owners for the same circle, the link is believed: the circle's owner decides whose list of spaces is taken.
  CircleInvite? offer(Circle c, {required String from, bool link = false}) {
    if (bySeed(c.seed) != null) {
      join(c);
      return null;
    }
    final had = inviteFor(c.seed);
    var circle = c;
    var linked = link;
    if (had != null) {
      if (had.link && !link && had.circle.owner != c.owner) {
        // A friend's invite naming another owner than the link did: the link's circle stays.
        circle = had.circle;
        linked = true;
      } else if (had.circle.owner == c.owner) {
        // The same circle: the newer of the two manifests.
        circle = c.merged(had.circle.manifest) ?? had.circle.merged(c.manifest) ?? (c.manifest.isSigned || !had.circle.manifest.isSigned ? c : had.circle);
        linked = link || had.link;
      }
    }
    // A link says nobody: the friend who sent it before stays named.
    final i = CircleInvite(circle, from.isNotEmpty ? from : (had?.from ?? ''), DateTime.now(), link: linked, fresh: true);
    final rest = [for (final x in invites) if (x.seed != c.seed) x];
    _setInvites([i, ...rest.take(_invitesKept - 1)]);
    return i;
  }

  /// Leaves [c]: off this device and its phone or computer. Its link brings it back.
  Future<void> leave(Circle c) async {
    _markGone(c.seed);
    all = [for (final x in all) if (x.seed != c.seed) x];
    final room = _rooms.remove(c.seed);
    if (room != null) await room.close();
    if (Sms.paired) unawaited(Sms.instance.voiceSync({'op': 'circle-forget', 's': c.seed}).catchError((_) => <String, dynamic>{}));
    if (invites.any((i) => i.seed == c.seed)) _setInvites([for (final i in invites) if (i.seed != c.seed) i], tell: false);
    _changed();
  }

  /// Takes an invite up ([seed]'s, or the banner's): the circle joined, even one left before, and given back to open.
  /// Null where there is no such invite.
  Circle? acceptInvite([String? seed]) {
    final i = seed == null ? invite : inviteFor(seed);
    if (i == null) return null;
    _setInvites([for (final x in invites) if (x.seed != i.seed) x], tell: false);
    return join(i.circle);
  }

  /// Not now: [seed]'s invite (or the banner's) put off, kept under Invites in the Circles tab until it is joined or
  /// dismissed.
  void laterInvite([String? seed]) {
    final i = seed == null ? invite : inviteFor(seed);
    if (i == null) return;
    _setInvites([for (final x in invites) x.seed == i.seed ? x.copyWith(later: true, fresh: false) : x]);
  }

  /// Puts [seed]'s invite (or the banner's) away for good: the circle isn't joined. A friend sending it again brings it
  /// back.
  void dismissInvite([String? seed]) {
    final i = seed == null ? invite : inviteFor(seed);
    if (i == null) return;
    _setInvites([for (final x in invites) if (x.seed != i.seed) x]);
  }

  /// [seed]'s invite seen where it waits (its banner pressed, to show the Circles tab): no banner for it any more, but
  /// it is not put off, so its card stays at the top of the tab.
  void seenInvite(String seed) {
    if (inviteFor(seed)?.fresh != true) return;
    _setInvites([for (final x in invites) x.seed == seed ? x.copyWith(fresh: false) : x]);
  }

  /// [seed]'s invite answered elsewhere: the circle joined or left on the paired phone or computer (answerDesk,
  /// fromPhone), so this device shows no card or banner for a circle it already holds or has left (Matt, 2026-11-17:
  /// "Finish the missing pieces that went unfinished"). Before, only Join here cleared it, and the other device kept the
  /// card, and the Circles tab's count, until its next launch.
  void _answered(String seed) {
    if (invites.any((i) => i.seed == seed)) _setInvites([for (final i in invites) if (i.seed != seed) i]);
  }

  void _setInvites(List<CircleInvite> next, {bool tell = true}) {
    invites = next;
    _app?.set('circle_invites', jsonEncode([for (final i in invites) i.toJson()]));
    if (tell) notifyListeners();
  }

  void _markGone(String seed) {
    _gone.remove(seed);
    _gone.add(seed);
    if (_gone.length > _goneKept) _gone.removeRange(0, _gone.length - _goneKept);
    _app?.set('circles_gone', jsonEncode(_gone));
  }

  void _unmarkGone(String seed) {
    if (_gone.remove(seed)) _app?.set('circles_gone', jsonEncode(_gone));
  }

  /// Puts [c] in place of the one held with its seed.
  void _put(Circle c) {
    all = [for (final x in all) x.seed == c.seed ? c : x];
    _rooms[c.seed]?.circle = c;
    _changed();
  }

  /// Kept, handed to Voice, the rooms followed, and told.
  void _changed({bool keep = true}) {
    if (keep) _app?.set('circles', jsonEncode([for (final c in all) c.toJson()]));
    // The hub dialled on a phone while there are circles, even one with no spaces yet: its room is how its list comes.
    if (_app != null && !Sms.paired) unawaited(Net.instance.want('circles', all.isNotEmpty));
    Voice.instance.setCircled([for (final c in all) ...c.channels]);
    _openRooms();
    notifyListeners();
  }

  // --- sharing ------------------------------------------------------------------------------------------------------

  /// Gives [c] to [friends], with its manifest, as a space is given (Voice.share). Gives back those it could not reach.
  Future<List<Buddy>> share(Circle c, List<Buddy> friends) async {
    final me = Me.instance;
    final by = me.displayName.isNotEmpty ? me.displayName : (me.username == null ? 'Someone' : '@${me.username}');
    final missed = <Buddy>[];
    for (final f in friends) {
      final peer = Net.instance.byId(f.id);
      if (peer == null) {
        missed.add(f);
        continue;
      }
      try {
        final d = await Net.instance.send(peer, Envelope(kind: 'voice', body: inviteBody(c, by)));
        if (!d.sent) missed.add(f);
      } catch (_) {
        missed.add(f);
      }
    }
    return missed;
  }

  /// What an invite into [c] says: its seed, owner, name and manifest, and who sent it.
  static Map<String, Object?> inviteBody(Circle c, String by) => {'t': 'circle', 's': c.seed, 'o': c.owner, 'n': c.name, 'm': c.manifest.toJson(), 'by': by};

  /// The circle an invite's [body] gives; null where it is not one. Its manifest is taken where it checks out, else
  /// just its name until the real one comes from the circle's room.
  static Circle? fromInvite(Map<String, Object?> body) {
    if (body['t'] != 'circle' || body['s'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(body['s'] as String)) return null;
    final seed = body['s'] as String;
    final owner = body['o'] is String && RegExp(r'^0[23][0-9a-f]{64}$').hasMatch(body['o'] as String) ? body['o'] as String : '';
    final m = CircleManifest.fromJson(body['m']);
    final name = body['n'] is String && (body['n'] as String).trim().isNotEmpty ? (body['n'] as String).trim() : (m?.name ?? 'Circle');
    return Circle(seed: seed, owner: owner, manifest: m != null && m.trustedFor(owner) ? m : CircleManifest.placeholder(owner: owner, name: name, hue: hueOfSeed(seed)));
  }

  void _received(Received r) {
    if (r.envelope.kind != 'voice' || r.envelope.body['t'] != 'circle') return;
    // Only from a friend.
    if (Buddies.instance.byId(r.peer.id)?.state != 'yes') return;
    final c = fromInvite(r.envelope.body.cast<String, Object?>());
    if (c == null) return;
    final from = Buddies.instance.byId(r.peer.id)?.shown ?? '${r.envelope.body['by'] ?? 'A friend'}';
    // Waits, said on screen with Join and Not now, rather than joined at once: the circle's room is not entered (where
    // its members would see this device) until the person says so, and a circle left before is not brought back by a
    // friend sending it again. One already held takes the invite's manifest where it is newer.
    offer(c, from: from);
  }

  // --- the phone and its computer, in step ---------------------------------------------------------------------------

  /// On the phone: what goes to a paired computer with its spaces (Voice.answerDesk's list).
  Map<String, Object?> forDesk() => {'circles': [for (final c in all) c.toJson()], 'circles_gone': _gone};

  /// On the phone: a circle a computer made or changed ([what] `op: circle`, `c`), or left (`op: circle-forget`, `s`).
  Future<Object?> answerDesk(Map<String, Object?> what) async {
    if (what['op'] == 'circle-forget') {
      final c = what['s'] is String ? bySeed(what['s'] as String) : null;
      if (c != null) {
        await leave(c);
      } else if (what['s'] is String) {
        _markGone(what['s'] as String);
        _answered(what['s'] as String);
      }
      return {'ok': true};
    }
    final c = Circle.fromJson(what['c']);
    if (c == null) return {'ok': false};
    // Joined on the computer: a circle left before is taken back here too.
    if (what['op'] == 'circle-join') _unmarkGone(c.seed);
    if (removed(c.seed)) return {'ok': false, 'gone': true};
    final have = bySeed(c.seed);
    // Joined (or held) on the computer: its invite here is answered too, card and banner.
    _answered(c.seed);
    if (have == null) {
      all = [...all, c.copyWith(mine: true)];
      _changed();
    } else {
      final next = have.merged(c.manifest);
      if (next != null) _put(next);
    }
    return {'ok': true};
  }

  /// On a computer: the phone's circles, from its answer to Voice.syncNow. Each takes the newer manifest, the phone's or
  /// this one's; one the phone left is left here; one made here goes to the phone.
  void fromPhone(Map<String, dynamic> got) {
    if (got['circles'] is! List) return;
    var changed = false;
    for (final s in (got['circles_gone'] as List? ?? const []).whereType<String>()) {
      if (!removed(s)) {
        _markGone(s);
        changed = true;
      }
      _answered(s);
      final c = bySeed(s);
      if (c != null) {
        all = [for (final x in all) if (x.seed != s) x];
        unawaited(_rooms.remove(s)?.close());
        changed = true;
      }
    }
    final phone = <String>{};
    for (final j in got['circles'] as List) {
      final c = Circle.fromJson(j);
      if (c == null) continue;
      phone.add(c.seed);
      // The phone holds it and hasn't it as left: it is the one to go by, so a mark of leaving here (a circle left
      // here, then joined again on the phone) gives way, rather than telling the phone to leave it again.
      if (removed(c.seed)) {
        _unmarkGone(c.seed);
        changed = true;
      }
      final have = bySeed(c.seed);
      _answered(c.seed);
      if (have == null) {
        all = [...all, c];
        changed = true;
      } else {
        final next = have.merged(c.manifest);
        if (next != null) {
          all = [for (final x in all) x.seed == c.seed ? next : x];
          _rooms[c.seed]?.circle = next;
          changed = true;
        } else if (have.manifest.version > c.manifest.version) {
          _toPhone(have);
        }
      }
    }
    for (final c in all) {
      if (!phone.contains(c.seed)) _toPhone(c);
    }
    // Only when something did change: every sync (8 s) rewrote every circle and rebuilt every list that shows one.
    if (changed) _changed();
  }

  /// On a computer: [c] to the phone, to keep too.
  void _toPhone(Circle c) {
    if (!Sms.paired) return;
    unawaited(Sms.instance.voiceSync({'op': 'circle', 'c': c.toJson()}).catchError((_) => <String, dynamic>{}));
  }

  // --- the rooms ----------------------------------------------------------------------------------------------------

  /// The relay came or went (Voice's route): each circle's room joined on the new one.
  void _follow() {
    final route = Voice.instance.route;
    if (identical(route, _route)) return;
    _route = route;
    for (final r in _rooms.values) {
      unawaited(r.close());
    }
    _rooms.clear();
    _openRooms();
  }

  void _openRooms() {
    // A circle no longer here: its room left.
    for (final seed in [..._rooms.keys]) {
      if (bySeed(seed) == null) unawaited(_rooms.remove(seed)!.close());
    }
    final route = _route;
    if (route == null) return;
    for (final c in all) {
      if (_rooms.containsKey(c.seed)) continue;
      final room = _rooms[c.seed] = CircleRoom(circle: c, route: route, onManifest: _heard);
      unawaited(room.open().catchError((_) {}));
    }
  }

  /// A newer manifest heard in a circle's room.
  void _heard(Circle c, CircleManifest m) {
    final have = bySeed(c.seed);
    final next = have?.merged(m);
    if (next == null) return;
    _put(next);
    _toPhone(next);
  }

  /// For a test: [c]'s room, where it is open.
  @visibleForTesting
  CircleRoom? roomOf(Circle c) => _rooms[c.seed];

  /// For a test: everything forgotten.
  @visibleForTesting
  Future<void> clear() async {
    // Forgotten at once, before the rooms close: a test that does not wait for this (or the next test's first frame)
    // must not find the last one's circles and invites still there.
    final rooms = [..._rooms.values];
    _rooms.clear();
    all = [];
    _gone.clear();
    invites = [];
    Voice.instance.setCircled(const []);
    notifyListeners();
    for (final r in rooms) {
      await r.close();
    }
  }
}

/// A circle's own room on the hub, where its manifest goes round: sealed with the circle's key, so the hub carries it
/// without reading it.
///
/// - Coming in, a device says the version it has (`sync?`); each device with a newer one answers, the lowest id first
///   and the rest a moment later, unless they hear it answered meanwhile (every member hears what is said to one).
/// - A change is said to everyone (`circle`).
/// - What is heard is checked by [Circle.merged] before it is taken ([onManifest]).
class CircleRoom {
  CircleRoom({required this.circle, required this.route, required this.onManifest});

  /// The circle as it stands here: changed by its manager as its manifest changes.
  Circle circle;
  final VoiceRoute route;
  final void Function(Circle circle, CircleManifest manifest) onManifest;

  final Set<String> present = {};
  final List<StreamSubscription<Object?>> _subs = [];
  final Map<String, Timer> _answering = {};
  bool opened = false;
  bool _dropped = false;

  String get me => route.me;

  /// How long each device after the first waits before answering, so one answer usually does.
  static const step = Duration(milliseconds: 250);

  Future<void> open() async {
    if (opened) return;
    opened = true;
    final room = circle.room;
    _subs.add(route.packets.where((p) => p.room == room).listen((p) => _heard(p.from, p.bytes)));
    _subs.add(route.events.where((e) => e.room == room).listen(_event));
    final List<String> there;
    try {
      there = await route.join(room, circle.token);
    } catch (_) {
      // Not in yet: in as soon as the relay server answers, when [_event] hears who is here.
      _dropped = true;
      return;
    }
    present.addAll(there);
    _ask();
  }

  Future<void> close() async {
    if (!opened) return;
    opened = false;
    route.leave(circle.room);
    for (final t in _answering.values) {
      t.cancel();
    }
    _answering.clear();
    final subs = [..._subs];
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
    present.clear();
  }

  /// Says [m] to everyone in the room.
  void say(CircleManifest m) => _say({'t': 'circle', 'm': m.toJson()}, keep: true);

  void _ask() => _say({'t': 'sync?', 'v': circle.manifest.version});

  /// [keep]: a change to the circle is kept by the hub for whoever comes in later.
  void _say(Map<String, Object?> what, {bool keep = false}) {
    if (!opened) return;
    try {
      final sealed = NetCrypto.seal(circle.key, utf8.encode(jsonEncode(what)));
      final r = route;
      if (keep && r is HubVoiceRoute) {
        r.sendKept(circle.room, sealed);
      } else {
        r.send(circle.room, sealed);
      }
    } catch (_) {}
  }

  void _event(RoomEvent e) {
    if (e.closed) {
      _dropped = true;
      present.clear();
    } else if (e.members != null && _dropped) {
      // Back in after the relay dropped: whatever changed meanwhile.
      _dropped = false;
      present
        ..clear()
        ..addAll(e.members!);
      _ask();
    } else if (e.came != null) {
      present.add(e.came!);
    } else if (e.went != null) {
      present.remove(e.went);
      _answering.remove(e.went)?.cancel();
    }
  }

  void _heard(String from, Uint8List bytes) {
    final clear = NetCrypto.open(circle.key, bytes);
    if (clear == null) return;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(utf8.decode(clear)) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'sync?':
        final v = m['v'] is int ? m['v'] as int : 0;
        if (!circle.manifest.isSigned || circle.manifest.version <= v) return;
        // The lowest id of those here answers at once, the next a step later, and so on.
        final ids = [me, ...present.where((id) => id != from && id != me)]..sort();
        final wait = step * ids.indexOf(me).clamp(0, 12);
        _answering.remove(from)?.cancel();
        _answering[from] = Timer(wait, () {
          _answering.remove(from);
          _say({'t': 'circle', 'to': from, 'm': circle.manifest.toJson()});
        });
      case 'circle':
        final got = CircleManifest.fromJson(m['m']);
        if (got == null) return;
        // Answered by someone else, as new as what this device would say: no need to say it too.
        final to = m['to'];
        if (to is String && to != me && got.version >= circle.manifest.version) _answering.remove(to)?.cancel();
        if (got.follows(circle.manifest, circle.owner)) onManifest(circle, got);
    }
  }
}
