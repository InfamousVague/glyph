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

/// A friend gave this device a circle (Circles.share): to show, until it is put away.
@immutable
class CircleInvite {
  const CircleInvite(this.circle, this.from, this.at);
  final Circle circle;
  final String from;
  final DateTime at;
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
  factory Circles.forTest({NetSigner? signer, VoiceRoute? route}) => Circles._()
    ..signerOverride = signer
    .._route = route;

  AppState? _app;
  VoiceRoute? _route;

  /// The circles this device is in, in the order they were joined.
  List<Circle> all = [];

  /// The seeds of circles left here or on the phone or computer, the newest [_goneKept].
  final List<String> _gone = [];
  static const _goneKept = 300;

  final Map<String, CircleRoom> _rooms = {};

  /// A friend's invite into a circle, until it is put away ([dismissInvite]).
  CircleInvite? invite;

  /// For a test: what signs manifests in place of Voice's signer.
  @visibleForTesting
  NetSigner? signerOverride;

  NetSigner? get signer => signerOverride ?? Voice.instance.signer;

  bool removed(String seed) => _gone.contains(seed);

  Future<void> start(AppState app) async {
    if (_app != null) return;
    _app = app;
    try {
      all = [for (final j in jsonDecode(app.choice('circles', '[]')) as List) ?Circle.fromJson(j)];
      _gone.addAll((jsonDecode(app.choice('circles_gone', '[]')) as List).whereType<String>());
    } catch (_) {}
    Net.instance.listen(_received);
    Voice.instance.addListener(_follow);
    _changed(keep: false);
    _follow();
  }

  Circle? bySeed(String seed) => all.where((c) => c.seed == seed).firstOrNull;

  /// The circle [space] is a space of, where it is one.
  Circle? circleOf(VoiceChannel space) => space.circle == null ? null : bySeed(space.circle!);

  // --- what the lists show ------------------------------------------------------------------------------------------

  /// How many messages from others in [c]'s spaces came after this device last read each.
  int unread(Circle c) => c.channels.fold(0, (n, s) => n + Voice.instance.unreadIn(s));

  /// Who is in a call in [c] now, by id, each once.
  List<String> inVoice(Circle c) => {for (final s in c.channels) if (s.hasVoice) ...Voice.instance.inChannel(s)}.toList();

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
  Future<CircleSpace?> addSpace(Circle c, String name, {SpaceKind kind = SpaceKind.voice, String? section}) async {
    final words = capName(name)!;
    final heading = capName(section);
    final last = c.manifest.spaces.fold(-1, (n, s) => s.order > n ? s.order : n);
    final space = CircleSpace.make(words.isEmpty ? kind.label : words, kind: kind, order: last + 1, section: heading == null || heading.isEmpty ? null : heading);
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

  /// Takes a space out of [c]'s list. Its chat stays with whoever has it; it is just no longer the circle's.
  Future<bool> removeSpace(Circle c, String seed) {
    if (c.space(seed) == null) return Future.value(false);
    return _publish(c, (m) => m.next(spaces: [for (final s in m.spaces) if (s.seed != seed) s]));
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

  /// Comes into the circle a link is; null where it is not a circle's link.
  Circle? joinLink(String link) {
    final c = Circle.fromLink(link);
    return c == null ? null : join(c);
  }

  /// Leaves [c]: off this device and its phone or computer. Its link brings it back.
  Future<void> leave(Circle c) async {
    _markGone(c.seed);
    all = [for (final x in all) if (x.seed != c.seed) x];
    final room = _rooms.remove(c.seed);
    if (room != null) await room.close();
    if (Sms.paired) unawaited(Sms.instance.voiceSync({'op': 'circle-forget', 's': c.seed}).catchError((_) => <String, dynamic>{}));
    if (invite?.circle.seed == c.seed) invite = null;
    _changed();
  }

  /// Takes the invite up: the circle joined (even one left before).
  Circle? acceptInvite() {
    final i = invite;
    if (i == null) return null;
    invite = null;
    return join(i.circle);
  }

  void dismissInvite() {
    invite = null;
    notifyListeners();
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
    // A circle this device left is not brought back by a friend sending it again: it waits as an invite, to accept.
    if (removed(c.seed)) {
      invite = CircleInvite(c, from, DateTime.now());
      notifyListeners();
      return;
    }
    final joined = join(c);
    invite = CircleInvite(joined, from, DateTime.now());
    notifyListeners();
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
      }
      return {'ok': true};
    }
    final c = Circle.fromJson(what['c']);
    if (c == null) return {'ok': false};
    // Joined on the computer: a circle left before is taken back here too.
    if (what['op'] == 'circle-join') _unmarkGone(c.seed);
    if (removed(c.seed)) return {'ok': false, 'gone': true};
    final have = bySeed(c.seed);
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
    for (final r in _rooms.values) {
      await r.close();
    }
    _rooms.clear();
    all = [];
    _gone.clear();
    invite = null;
    Voice.instance.setCircled(const []);
    notifyListeners();
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
    final there = await route.join(room, circle.token);
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
  void say(CircleManifest m) => _say({'t': 'circle', 'm': m.toJson()});

  void _ask() => _say({'t': 'sync?', 'v': circle.manifest.version});

  void _say(Map<String, Object?> what) {
    if (!opened) return;
    try {
      route.send(circle.room, NetCrypto.seal(circle.key, utf8.encode(jsonEncode(what))));
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
