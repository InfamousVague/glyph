import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../net/crypto.dart';
import '../net/hub_carrier.dart';
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
    _say({'t': 'sync?', 'since': messages.isEmpty ? 0 : messages.last.at, 'v': roster.version});
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
    _say({'t': 'msg', ...m.toJson()});
    return true;
  }

  /// Whether this device may delete [m]: its own, or anyone's with Manage messages.
  bool canDelete(HangoutMessage m) => m.from == me || (can(Perm.manageMessages) && roster.outranks(me, m.from)) || roster.isOwner(me);

  void delete(HangoutMessage m) {
    if (!canDelete(m)) return;
    _drop(m.id);
    _say({'t': 'del', 'id': m.id});
  }

  void _add(Iterable<HangoutMessage> fresh) {
    final have = {for (final m in messages) m.id};
    final more = [for (final m in fresh) if (have.add(m.id)) m];
    if (more.isEmpty) return;
    messages = [...messages, ...more]..sort((a, b) => a.at.compareTo(b.at));
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
    _say({'t': 'roster', 'r': signed.toJson()});
    return true;
  }

  void _take(Roster r) {
    roster = r;
    store.keepRoster(channel.chatRoom, r);
    if (r.banned.contains(me)) {
      putOut = 'You were banned from this space.';
    }
    onRoster?.call(r);
    notifyListeners();
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
      _say({'t': 'sync?', 'since': messages.isEmpty ? 0 : messages.last.at, 'v': roster.version});
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

  void _say(Map<String, Object?> what) {
    if (!opened) return;
    try {
      route.send(channel.chatRoom, NetCrypto.seal(channel.key, utf8.encode(jsonEncode(what))));
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
      case 'hist':
        _add([
          for (final j in (m['m'] as List? ?? const []))
            if (j is Map && j['f'] is String) ?HangoutMessage.fromJson(j.cast<String, dynamic>(), j['f'] as String),
        ]);
      case 'roster':
        final r = Roster.fromJson(m['r']);
        if (r != null && r.version > roster.version && r.trustedFor(channel.owner)) _take(r);
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

/// Where a device keeps a hangout's chat and roster between visits.
abstract class HangoutStore {
  List<HangoutMessage> messages(String room);
  void keepMessages(String room, List<HangoutMessage> messages);
  Roster? roster(String room);
  void keepRoster(String room, Roster roster);
}

class MemoryHangoutStore implements HangoutStore {
  final Map<String, List<HangoutMessage>> _messages = {};
  final Map<String, Roster> _rosters = {};
  @override
  List<HangoutMessage> messages(String room) => _messages[room] ?? const [];
  @override
  void keepMessages(String room, List<HangoutMessage> messages) => _messages[room] = messages;
  @override
  Roster? roster(String room) => _rosters[room];
  @override
  void keepRoster(String room, Roster roster) => _rosters[room] = roster;
}
