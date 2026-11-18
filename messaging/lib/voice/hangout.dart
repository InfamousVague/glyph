import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../net/crypto.dart';
import '../net/hub_carrier.dart';
import 'channels.dart' show AppHangoutStore;
import 'roles.dart';
import 'voice.dart';

/// A hangout's chat, and its roles kept and enforced (Matt, 2026-11-15: "Implement a permissions system similar to
/// discord for hangouts and add a chat to hangouts so the whole group can send messages to the hangout as well as
/// voice and video, make default roles such as admin, moderator, member").
///
/// **Its room.** Beside the call's room each hangout has a chat room on the hub (VoiceChannel.chatRoom), sealed with
/// the same key, which anyone looking at the hangout is in, in the call or not. Everything here goes through it:
/// messages, deletions, the roster (lib/voice/roles.dart) and what moderators do.
///
/// **History.** The hub keeps nothing. Each device keeps the last [keep] messages it saw ([HangoutStore]); coming in,
/// it asks for what it missed and the one there with the lowest id answers, so one copy comes back, not one from each.
/// The roster comes the same way, from anyone whose is newer and checks out.
///
/// **Enforcement.** Each device does what the roster says of what it hears: a message from someone who may not write
/// is not shown, a deletion by someone who may not delete is ignored, someone muted for everyone is silenced on every
/// device ([onRoster]: lib/voice/channels.dart), someone banned is not answered at all, and a device told to leave by
/// someone above it with the right to remove people leaves.
class HangoutRoom extends ChangeNotifier {
  HangoutRoom({required this.channel, required this.route, required this.name, this.username, this.signer, HangoutStore? store})
      : store = store ?? MemoryHangoutStore() {
    roster = this.store.roster(channel.chatRoom) ?? Roster.first(channel.owner, kind: channel.kind);
    if (roster.owner != channel.owner) roster = Roster.first(channel.owner, kind: channel.kind);
    messages = this.store.messages(channel.chatRoom);
    _loadAbout();
  }

  static const keep = 300;

  /// The space: replaced, same seed, when the circle it is in changes its kind ([updateChannel]).
  VoiceChannel channel;
  final VoiceRoute route;
  final HangoutStore store;

  /// What this install signs rosters with; null where it can't (it then changes nothing).
  final NetSigner? signer;
  String name;
  String? username;

  late Roster roster;
  late List<HangoutMessage> messages;

  /// Who is in the chat room now, with what they said of themselves.
  final Map<String, HangoutPerson> present = {};

  /// Set when someone with the right to told this device to leave, or it was banned: why.
  String? putOut;
  bool opened = false;

  /// Told when the roster changes, to do what it says in the call (who is heard, who is seen).
  void Function(Roster roster)? onRoster;

  final List<StreamSubscription<Object?>> _subs = [];

  String get me => route.me;
  bool can(Perm p) => roster.can(me, p);

  Future<void> open() async {
    if (opened) return;
    opened = true;
    putOut = roster.banned.contains(me) ? 'You were banned from this space.' : null;
    _subs.add(route.packets.where((p) => p.room == channel.chatRoom).listen((p) => _heard(p.from, p.bytes)));
    _subs.add(route.events.where((e) => e.room == channel.chatRoom).listen(_event));
    final there = await route.join(channel.chatRoom, channel.chatToken);
    for (final id in there) {
      present[id] = present[id] ?? HangoutPerson(id);
    }
    _hi();
    _say({'t': 'sync?', 'since': messages.isEmpty ? 0 : messages.last.at, 'v': roster.version, 'av': _about?.version ?? 0});
    notifyListeners();
  }

  Future<void> close() async {
    if (!opened) return;
    opened = false;
    route.leave(channel.chatRoom);
    // Taken out first: an open() while these are cancelled starts a list of its own.
    final subs = [..._subs];
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
    present.clear();
    notifyListeners();
  }

  /// Said again when this device goes in or out of the call, or its name changes.
  void sayMe({bool? inVoice}) {
    if (inVoice != null) _inVoice = inVoice;
    _hi();
  }

  bool _inVoice = false;

  void _hi() => _say({'t': 'hi', 'n': name, if (username != null) 'u': username, 'a': _inVoice});

  // --- chat --------------------------------------------------------------------------------------------------------

  /// Writes [text] to the hangout; false where this device may not.
  bool send(String text) {
    final words = text.trim();
    if (words.isEmpty || !can(Perm.chat) || putOut != null) return false;
    final m = HangoutMessage(id: NetCrypto.hex(NetCrypto.randomBytes(8)), from: me, name: name, text: words.length > 4000 ? words.substring(0, 4000) : words, at: DateTime.now().millisecondsSinceEpoch);
    _add([m]);
    _say({'t': 'msg', ...m.toJson()}, keep: true);
    return true;
  }

  /// Whether this device may delete [m]: its own, or anyone's with Manage messages.
  bool canDelete(HangoutMessage m) => m.from == me || (can(Perm.manageMessages) && roster.outranks(me, m.from)) || roster.isOwner(me);

  void delete(HangoutMessage m) {
    if (!canDelete(m)) return;
    _drop(m.id);
    _say({'t': 'del', 'id': m.id}, keep: true);
  }

  void _add(Iterable<HangoutMessage> fresh) {
    final have = {for (final m in messages) m.id};
    final more = [for (final m in fresh) if (have.add(m.id)) m];
    if (more.isEmpty) return;
    // By when they were written, and two written in the same millisecond by id: each device kept those in the order it
    // happened to hear them, so the writer saw its own first and everyone else the other's (hangout_test's chat case
    // caught the two devices disagreeing).
    messages = [...messages, ...more]..sort((a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.id.compareTo(b.id));
    if (messages.length > keep) messages = messages.sublist(messages.length - keep);
    store.keepMessages(channel.chatRoom, messages);
    notifyListeners();
  }

  void _drop(String id) {
    final before = messages.length;
    messages = [for (final m in messages) if (m.id != id) m];
    if (messages.length == before) return;
    store.keepMessages(channel.chatRoom, messages);
    notifyListeners();
  }

  // --- roles and moderation -------------------------------------------------------------------------------------

  bool get canManage => roster.canManage(me) && signer != null;

  /// Gives [id] [roleId]. Making an admin is the owner's alone: it carries the owner's signature that they are one.
  Future<bool> setRole(String id, String roleId) async {
    if (!canManage || !roster.outranks(me, id)) return false;
    final role = roster.roleById(roleId);
    if (role == null) return false;
    final grants = {...roster.adminGrants};
    if (roleId == Role.admin) {
      if (!roster.isOwner(me)) return false;
      grants[id] = NetCrypto.hex(await signer!.sign(Roster.grantMessage(roster.owner, id)));
    } else {
      grants.remove(id);
      // An admin gives out only roles below their own.
      if (!roster.isOwner(me) && role.rank >= roster.roleOf(me).rank) return false;
    }
    final assigned = {...roster.assigned, id: roleId};
    return _publish(roster.next(assigned: assigned, adminGrants: grants));
  }

  /// Mutes [id] for everyone, or lets them speak again.
  Future<bool> muteForAll(String id, bool on) async {
    if (!can(Perm.muteOthers) || !roster.outranks(me, id)) return false;
    // A mute stands in the roster when an admin makes it; a moderator's is said to the room and held while they are.
    if (canManage) {
      final muted = {...roster.muted};
      on ? muted.add(id) : muted.remove(id);
      return _publish(roster.next(muted: muted));
    }
    // Said to everyone (not to them alone): every device holds it.
    _say({'t': 'mute', 'who': id, 'on': on});
    _applyMute(id, on);
    return true;
  }

  /// Moderators' mutes, held on each device while it is in the hangout.
  final Set<String> heldMutes = {};

  void _applyMute(String id, bool on) {
    on ? heldMutes.add(id) : heldMutes.remove(id);
    onRoster?.call(roster);
    notifyListeners();
  }

  /// Whether [id] may be heard: the roster, and any mute a moderator said.
  bool heard(String id) => roster.can(id, Perm.speak) && !heldMutes.contains(id);

  /// Puts [id] out of the hangout now; they can come back.
  bool remove(String id) {
    if (!can(Perm.removeMembers) || !roster.outranks(me, id)) return false;
    _say({'t': 'kick', 'to': id});
    present.remove(id);
    notifyListeners();
    return true;
  }

  /// Bans [id]: kept out for good (in the roster), and put out now.
  Future<bool> ban(String id, {bool on = true}) async {
    if (!can(Perm.ban) || !roster.outranks(me, id) || !canManage) return false;
    final banned = {...roster.banned};
    on ? banned.add(id) : banned.remove(id);
    final ok = await _publish(roster.next(banned: banned));
    if (ok && on) {
      _say({'t': 'kick', 'to': id});
      present.remove(id);
    }
    return ok;
  }

  /// [c], the same space with its kind (or name) changed by its circle: kept here so what the space may do follows it.
  /// Made a Files space, members may add files and moderators and admins manage them, as a new Files space's roles
  /// have; made another kind, the Files permissions go. A roster no one has signed yet is the kind's first roster; a
  /// signed one is changed and signed here where this install may manage it (else by whoever may, as they see it).
  void updateChannel(VoiceChannel c) {
    if (c.seed != channel.seed) return;
    final was = channel.kind;
    channel = c;
    if (c.kind != was) {
      if (roster.version == 0 && roster.sig == null) {
        _take(Roster.first(c.owner, kind: c.kind));
      } else if (canManage) {
        final defaults = {for (final r in Role.defaultsFor(c.kind)) r.id: r};
        final roles = [
          for (final r in roster.ranked)
            r.copyWith(perms: c.kind == SpaceKind.files ? {...r.perms, ...?defaults[r.id]?.perms.intersection(Perm.files)} : r.perms.difference(Perm.files)),
        ];
        unawaited(_publish(roster.next(roles: roles)));
      }
    }
    notifyListeners();
  }

  /// Changes what [role] may do, or its name or rank; or adds it where it is new. Admin keeps every permission.
  Future<bool> saveRole(Role role) async {
    if (!canManage) return false;
    // Only what a space of this kind has: a voice or texting space's roles never name a Files permission (Perm.files).
    final fixed = role.id == Role.admin ? role.copyWith(perms: Perm.of(channel.kind), rank: 30) : role.copyWith(perms: role.perms.intersection(Perm.of(channel.kind)), rank: role.rank.clamp(1, 29));
    final roles = [for (final r in roster.ranked) r.id == role.id ? fixed : r];
    if (!roles.any((r) => r.id == role.id)) roles.add(fixed);
    return _publish(roster.next(roles: roles));
  }

  /// Takes away a role (not admin, not the one newcomers get); whoever had it goes back to the newcomers' role.
  Future<bool> deleteRole(String roleId) async {
    if (!canManage || roleId == Role.admin || roleId == roster.newcomer) return false;
    final roles = [for (final r in roster.ranked) if (r.id != roleId) r];
    final assigned = {for (final e in roster.assigned.entries) if (e.value != roleId) e.key: e.value};
    return _publish(roster.next(roles: roles, assigned: assigned));
  }

  /// The role people have until given another.
  Future<bool> setNewcomer(String roleId) async {
    if (!canManage || roleId == Role.admin || roster.roleById(roleId) == null) return false;
    return _publish(roster.next(newcomer: roleId));
  }

  Future<bool> _publish(Roster next) async {
    final s = signer;
    if (s == null) return false;
    final signed = await next.signedBy(me, s.publicKey, s.sign);
    if (!signed.trustedFor(channel.owner)) return false;
    _take(signed);
    _say({'t': 'roster', 'r': signed.toJson()}, keep: true);
    return true;
  }

  void _take(Roster r) {
    roster = r;
    store.keepRoster(channel.chatRoom, r);
    // A description by someone this roster no longer makes owner or admin goes from under the name: it stayed there
    // on every device after its writer was demoted (Matt, 2026-11-17: "Finish the missing pieces that went
    // unfinished"). It waits, in case they are made one again.
    final shown = _about;
    if (shown != null && !shown.trustedFor(channel.chatRoom, r)) {
      _about = null;
      if (shown.version > (_waitingAbout?.version ?? 0)) _waitingAbout = shown;
    }
    // An about signed by an admin can come before the roster that makes them one: tried again now.
    final waiting = _waitingAbout;
    if (waiting != null && waiting.trustedFor(channel.chatRoom, r)) {
      _waitingAbout = null;
      _takeAbout(waiting);
    }
    if (r.banned.contains(me)) {
      putOut = 'You were banned from this space.';
    }
    onRoster?.call(r);
    notifyListeners();
  }

  // --- the description ---------------------------------------------------------------------------------------------

  /// What the space is for, as its owner or an admin wrote it, shown under its name in the header (Matt, 2026-11-17:
  /// "make the text header for spaces show the icon and the name and an area for a description of the channel").
  /// Null where no one has written one, or it was cleared.
  String? get about => (_about?.text ?? '').isEmpty ? null : _about!.text;

  SpaceAbout? _about;

  /// The newest about heard that the roster doesn't yet trust (its admin's roster not here yet).
  SpaceAbout? _waitingAbout;

  /// Writes [text] as the space's description, for everyone in it; false where this install may not (only the owner
  /// and admins, as with the roster).
  Future<bool> setAbout(String text) async {
    final s = signer;
    if (s == null || !canManage) return false;
    final words = text.trim();
    final next = await SpaceAbout.sign(channel.chatRoom, words.length > SpaceAbout.most ? words.substring(0, SpaceAbout.most) : words, (_about?.version ?? 0) + 1, me, s.publicKey, s.sign);
    if (!next.trustedFor(channel.chatRoom, roster)) return false;
    _takeAbout(next);
    _say({'t': 'about', 'a': next.toJson()}, keep: true);
    return true;
  }

  void _heardAbout(Object? j) {
    final a = SpaceAbout.fromJson(j);
    if (a == null) return;
    // Two admins writing the same version at once: the one whose signature sorts last, on every device alike, rather
    // than whichever each heard first.
    final cur = _about;
    if (cur == null ? a.version <= 0 : (a.version < cur.version || (a.version == cur.version && a.sig.compareTo(cur.sig) <= 0))) return;
    if (a.trustedFor(channel.chatRoom, roster)) {
      _takeAbout(a);
    } else if (a.version > (_waitingAbout?.version ?? 0)) {
      _waitingAbout = a;
    }
  }

  void _takeAbout(SpaceAbout a) {
    _about = a;
    if (_waitingAbout != null && _waitingAbout!.version <= a.version) _waitingAbout = null;
    _keepAbout(a);
    notifyListeners();
  }

  /// The about is kept beside the roster, but not in it: an older build rebuilds a roster's signed bytes from the
  /// fields it knows, so a new field there would have 0.9.2 refuse every roster. The app's store has no slot for it,
  /// so it goes under a key of its own in the same choices (`hangout_<room>_about`), which keep any key.
  static String _aboutKey(String room) => 'hangout_${room}_about';

  void _keepAbout(SpaceAbout a) {
    final s = store, words = jsonEncode(a.toJson());
    if (s is HangoutAboutStore) {
      (s as HangoutAboutStore).keepAbout(channel.chatRoom, words);
    } else if (s is AppHangoutStore) {
      s.app.set(_aboutKey(channel.chatRoom), words);
    }
  }

  void _loadAbout() {
    final s = store;
    String? words;
    if (s is HangoutAboutStore) {
      words = (s as HangoutAboutStore).aboutOf(channel.chatRoom);
    } else if (s is AppHangoutStore) {
      words = s.app.choice(_aboutKey(channel.chatRoom), '');
    }
    if (words == null || words.isEmpty) return;
    try {
      final a = SpaceAbout.fromJson(jsonDecode(words));
      if (a == null) return;
      a.trustedFor(channel.chatRoom, roster) ? _about = a : _waitingAbout = a;
    } catch (_) {}
  }

  // --- the room ------------------------------------------------------------------------------------------------------

  /// The relay dropped this device out of the room ([RoomEvent.closed]); it puts it back in on reconnecting.
  bool _dropped = false;

  void _event(RoomEvent e) {
    if (e.closed) {
      _dropped = true;
      present.clear();
    } else if (e.members != null && _dropped) {
      // Back in after the relay dropped and came back: who is here now, and what was said meanwhile.
      _dropped = false;
      present.clear();
      for (final id in e.members!) {
        present[id] = HangoutPerson(id);
      }
      _hi();
      _say({'t': 'sync?', 'since': messages.isEmpty ? 0 : messages.last.at, 'v': roster.version, 'av': _about?.version ?? 0});
    } else if (e.came != null) {
      present[e.came!] = HangoutPerson(e.came!);
      // Who is here and what they call themselves, for the newcomer.
      _hi();
    } else if (e.went != null) {
      present.remove(e.went);
      heldMutes.remove(e.went);
    }
    notifyListeners();
  }

  /// Says [what] to everyone in the chat room. [keep]: the hub keeps it for whoever comes in later (a message, a
  /// deletion, the roster, the description), so a phone that was closed when it was said still has it (Matt, 2026-11-18:
  /// "I can't see their messages in spaces within a circle").
  void _say(Map<String, Object?> what, {bool keep = false}) {
    if (!opened) return;
    try {
      final sealed = NetCrypto.seal(channel.key, utf8.encode(jsonEncode(what)));
      final r = route;
      if (keep && r is HubVoiceRoute) {
        r.sendKept(channel.chatRoom, sealed);
      } else {
        r.send(channel.chatRoom, sealed);
      }
    } catch (_) {}
  }

  /// Whether this device is the one to answer [asker]: the lowest id of those here besides them.
  bool _answers(String asker) {
    final ids = [me, ...present.keys.where((id) => id != asker)]..sort();
    return ids.first == me;
  }

  void _heard(String from, Uint8List bytes) {
    final clear = NetCrypto.open(channel.key, bytes);
    if (clear == null) return;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(utf8.decode(clear)) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final to = m['to'];
    if (to != null && to != me) {
      // Others told to leave are gone from here too.
      if (m['t'] == 'kick' && roster.can(from, Perm.removeMembers) && roster.outranks(from, '$to')) {
        present.remove('$to');
        notifyListeners();
      }
      return;
    }
    // Someone banned is not heard at all.
    if (roster.banned.contains(from)) return;
    switch (m['t']) {
      case 'hi':
        present[from] = HangoutPerson(from, name: '${m['n'] ?? ''}', username: m['u'] is String ? m['u'] as String : null, inVoice: m['a'] == true, guest: m['g'] == true);
        notifyListeners();
      case 'msg':
        final msg = HangoutMessage.fromJson(m, from);
        if (msg != null && roster.can(from, Perm.chat)) _add([msg]);
      case 'del':
        final id = '${m['id']}';
        final msg = messages.where((x) => x.id == id).firstOrNull;
        if (msg != null && (msg.from == from || roster.isOwner(from) || (roster.can(from, Perm.manageMessages) && roster.outranks(from, msg.from)))) _drop(id);
      case 'sync?':
        if (_answers(from)) {
          final since = m['since'] is int ? m['since'] as int : 0;
          final missed = [for (final x in messages) if (x.at > since) x];
          if (missed.isNotEmpty) _say({'t': 'hist', 'to': from, 'm': [for (final x in missed.take(keep)) x.toJson()..['f'] = x.from]});
        }
        if (roster.sig != null && (m['v'] is! int || roster.version > (m['v'] as int))) _say({'t': 'roster', 'to': from, 'r': roster.toJson()});
        // The description the same way, after the roster that trusts its writer. An older build's sync? has no `av`
        // and gets it anyway; it has no case for `about` and passes over it (this switch has no default).
        final a = _about;
        if (a != null && (m['av'] is! int || a.version > (m['av'] as int))) _say({'t': 'about', 'to': from, 'a': a.toJson()});
      case 'hist':
        _add([
          for (final j in (m['m'] as List? ?? const []))
            if (j is Map && j['f'] is String) ?HangoutMessage.fromJson(j.cast<String, dynamic>(), j['f'] as String),
        ]);
      case 'roster':
        final r = Roster.fromJson(m['r']);
        if (r != null && r.version > roster.version && r.trustedFor(channel.owner)) _take(r);
      case 'about':
        _heardAbout(m['a']);
      case 'mute':
        if (roster.can(from, Perm.muteOthers) && roster.outranks(from, '${m['who']}')) _applyMute('${m['who']}', m['on'] == true);
      case 'kick':
        if (roster.can(from, Perm.removeMembers) && roster.outranks(from, me)) {
          putOut = roster.banned.contains(me) ? 'You were banned from this space.' : 'You were removed from this space.';
          onRoster?.call(roster);
          notifyListeners();
        }
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

/// Someone in a hangout's chat room, as they said they are.
@immutable
class HangoutPerson {
  const HangoutPerson(this.id, {this.name = '', this.username, this.inVoice = false, this.guest = false});
  final String id;
  final String name;
  final String? username;
  final bool inVoice;
  final bool guest;
}

/// One message in a hangout's chat.
@immutable
class HangoutMessage {
  const HangoutMessage({required this.id, required this.from, required this.name, required this.text, required this.at});
  final String id;

  /// Who wrote it (their id on the hub, as the hub said), and the name they wrote it under.
  final String from;
  final String name;
  final String text;

  /// When, in milliseconds since 1970, by the writer's clock.
  final int at;

  Map<String, Object> toJson() => {'id': id, 'x': text, 'at': at, 'n': name};

  /// From what [from] said: its id, words and time; null where it is not a message.
  static HangoutMessage? fromJson(Map<String, dynamic> j, String from) {
    if (j['id'] is! String || j['x'] is! String || j['at'] is! int) return null;
    final text = (j['x'] as String).trim();
    if (text.isEmpty) return null;
    return HangoutMessage(id: j['id'] as String, from: from, name: j['n'] is String ? j['n'] as String : '', text: text.length > 4000 ? text.substring(0, 4000) : text, at: j['at'] as int);
  }

  Map<String, Object> toStored() => {...toJson(), 'f': from};
}

/// A space's description: its words, numbered and signed by the owner or an admin, as the roster is but apart from it
/// ([HangoutRoom.about]). On the wire, in the space's chat room: `{t: about, a: {d, v, by, k, s}}`.
@immutable
class SpaceAbout {
  const SpaceAbout({required this.text, required this.version, required this.by, required this.byKey, required this.sig});

  /// Up to this many characters.
  static const most = 300;

  final String text;
  final int version;

  /// Who signed it: their id on the hub, their public key (hex), their signature (hex) over [signedBytes].
  final String by;
  final String byKey;
  final String sig;

  /// The bytes signed: domain-separated, and naming the space's chat room so an about can't be carried to another.
  static List<int> signedBytes(String room, String text, int version, String by, String byKey) =>
      utf8.encode('ghost-hangout about|${jsonEncode({'c': room, 'd': text, 'v': version, 'by': by, 'k': byKey})}');

  static Future<SpaceAbout> sign(String room, String text, int version, String by, Uint8List publicKey, Future<Uint8List> Function(List<int>) sign) async {
    final key = NetCrypto.hex(publicKey);
    final s = await sign(signedBytes(room, text, version, by, key));
    return SpaceAbout(text: text, version: version, by: by, byKey: key, sig: NetCrypto.hex(s));
  }

  Map<String, Object> toJson() => {'d': text, 'v': version, 'by': by, 'k': byKey, 's': sig};

  static SpaceAbout? fromJson(Object? j) {
    if (j is! Map || j['d'] is! String || j['v'] is! int || j['by'] is! String || j['k'] is! String || j['s'] is! String) return null;
    if ((j['d'] as String).length > most || (j['v'] as int) < 1) return null;
    return SpaceAbout(text: j['d'] as String, version: j['v'] as int, by: j['by'] as String, byKey: j['k'] as String, sig: j['s'] as String);
  }

  /// Whether to believe it in the space whose chat room is [room], by [roster]: signed by the key it names, and that
  /// key the owner's or an admin's the owner made (Roster.canManage, which checks the owner's grant).
  bool trustedFor(String room, Roster roster) {
    if (!roster.hasOwner) return false;
    try {
      final k = NetCrypto.unhex(byKey);
      if (NetCrypto.idOf(k) != by) return false;
      if (!NetCrypto.verify(k, signedBytes(room, text, version, by, byKey), NetCrypto.unhex(sig))) return false;
    } catch (_) {
      return false;
    }
    return roster.canManage(by);
  }
}

/// A store that keeps a space's description too ([SpaceAbout] as JSON). The app's store ([AppHangoutStore]) does it
/// under a key of its own instead, until it takes this on.
abstract class HangoutAboutStore {
  String? aboutOf(String room);
  void keepAbout(String room, String about);
}

/// Where a device keeps a hangout's chat and roster between visits.
abstract class HangoutStore {
  List<HangoutMessage> messages(String room);
  void keepMessages(String room, List<HangoutMessage> messages);
  Roster? roster(String room);
  void keepRoster(String room, Roster roster);
}

class MemoryHangoutStore implements HangoutStore, HangoutAboutStore {
  final Map<String, List<HangoutMessage>> _messages = {};
  final Map<String, Roster> _rosters = {};
  final Map<String, String> _abouts = {};
  @override
  String? aboutOf(String room) => _abouts[room];
  @override
  void keepAbout(String room, String about) => _abouts[room] = about;
  @override
  List<HangoutMessage> messages(String room) => _messages[room] ?? const [];
  @override
  void keepMessages(String room, List<HangoutMessage> messages) => _messages[room] = messages;
  @override
  Roster? roster(String room) => _rosters[room];
  @override
  void keepRoster(String room, Roster roster) => _rosters[room] = roster;
}
