import '../circles/circles.dart' show Circles, CirclePerm;
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../friends/buddies.dart';
import '../friends/groups.dart';
import '../me/me.dart';
import '../net/crypto.dart';
import '../net/hub_carrier.dart';
import '../net/net.dart';
import '../net/packet.dart';
import '../net/switchboard.dart';
import '../sms.dart';
import '../sounds.dart';
import '../circles/circles.dart';
import '../circles/sms_space.dart';
import 'hangout.dart';
import 'mention_alerts.dart';
import 'roles.dart';
import 'rtc.dart';
import 'voice.dart';
import 'voice_settings.dart';

/// Someone calling a group: its channel, and who. Or, with [invite], a friend who invited this phone into a space.
@immutable
class VoiceRing {
  const VoiceRing(this.channel, this.from, this.at, {this.invite = false, this.offer = false});
  final VoiceChannel channel;
  final String from;
  final DateTime at;

  /// Not a call but an invite: a friend gave this phone [channel] (Voice.share), to join now or later.
  final bool invite;

  /// An invite that waited on the relay for this phone's number ([Voice.offers]): not among the spaces until Join is
  /// pressed, since anyone who knows a number can leave one.
  final bool offer;

  Map<String, Object> toJson() => {'c': channel.toJson(), 'f': from, 'at': at.millisecondsSinceEpoch};

  static VoiceRing? offerFromJson(Object? j) {
    if (j is! Map || j['f'] is! String || j['at'] is! int) return null;
    final c = VoiceChannel.fromJson(j['c']);
    return c == null ? null : VoiceRing(c, j['f'] as String, DateTime.fromMillisecondsSinceEpoch(j['at'] as int), invite: true, offer: true);
  }
}

/// The voice channels this device can see and the one it is in (lib/voice/voice.dart says what a channel is).
///
/// - **A group's channel** is always there for its members, open to hop in and out of.
/// - **Channels you make** have a name and are shared with friends you choose (by username, lib/friends/buddies.dart):
///   each is sent the seed, sealed, as an envelope of kind `voice` (`channel`).
/// - **Calling the group** sends each member a `voice` envelope (`ring`): their app says the group is calling, and
///   Join puts them in the channel.
///
/// Who is in each is shown without joining (the hub's `look`). On a phone the channels ride its own connection to the
/// hub; a computer, which speaks through its phone, connects with a key of its own for the voice alone.
class Voice extends ChangeNotifier {
  Voice._();
  static final Voice instance = Voice._();

  StreamSubscription<void>? _leaveCall;

  AppState? _app;

  /// The person's choices, once the app has started Voice: for what a call's plugins read.
  AppState? get app => _app;
  HubCarrier? _ownHub;
  VoiceRoute? _route;
  final List<StreamSubscription<Object?>> _subs = [];
  final Map<String, List<String>> _in = {};

  /// The channel this device is in, while it is.
  VoiceSession? session;
  RtcMedia? media;

  /// Someone calling a group, or a friend's invite into a space, until it is answered or put away.
  VoiceRing? ringing;

  /// Channels made here or shared by friends.
  List<VoiceChannel> own = [];

  /// The spaces of every circle this device is in (lib/circles/circles.dart sets them as its circles change): their
  /// chat rooms are held for previews and unread counts as a space of one's own is, but they are listed in their
  /// circle, not in Messages, and the phone and computer keep them in step as circles, not one by one.
  List<VoiceChannel> circled = [];

  /// Sets [circled] and looks again at what is held.
  void setCircled(List<VoiceChannel> spaces) {
    final before = circled.map((c) => '${c.seed}${c.kind.wire}${c.name}').join();
    circled = spaces;
    if (spaces.map((c) => '${c.seed}${c.kind.wire}${c.name}').join() != before) _look();
  }

  /// What this device's spaces stand on, once the relay is connected: the circles' rooms go through it too.
  VoiceRoute? get route => _route;

  /// The seeds of channels removed on this device or its phone or computer, kept so that neither gives one back to
  /// the other (Matt, 2026-11-15: "Removing a hangout channel doesn't remove it for all devices": the computer still
  /// had it and, every few seconds, handed the phone it again). The newest [_goneKept].
  final List<String> _gone = [];
  static const _goneKept = 300;

  bool removed(String seed) => _gone.contains(seed);

  /// Spaces offered by invites that waited on the relay for this phone's number (lib/invites/pending_invites.dart),
  /// newest last, kept (`voice_offers`) until Join or a month. A friend's share puts a space among [own] at once, as
  /// it comes from a friend; one of these could be from anyone who knows the number, so nothing of it is joined,
  /// named or held until the person presses Join on its ring ([acceptOffer]).
  List<VoiceRing> offers = [];

  /// How long an offer waits, as the relay keeps its copy.
  static const offerLife = Duration(days: 30);

  /// Offers put off with Not now while the app has been open: raised again the next time it opens.
  final Set<String> _putOff = {};

  /// Keeps [c] as an offer from [from] and raises its ring where nothing else is ringing. True once it is held here,
  /// so the relay's copy can go: offered, or already among the spaces, or removed here.
  bool offerSpace(VoiceChannel c, String from) {
    if (own.any((o) => o.seed == c.seed) || circled.any((o) => o.seed == c.seed) || removed(c.seed)) return true;
    offers = [for (final o in offers) if (o.channel.seed != c.seed) o, VoiceRing(c, from, DateTime.now(), invite: true, offer: true)];
    _keepOffers();
    _putOff.remove(c.seed);
    _raiseOffer();
    return true;
  }

  void _keepOffers() => _app?.set('voice_offers', jsonEncode([for (final o in offers) o.toJson()]));

  /// The next offer not put off, on the ring, where nothing rings and its call is not the one this device is in.
  void _raiseOffer() {
    if (ringing != null) return;
    final next = offers.where((o) => !_putOff.contains(o.channel.seed) && session?.channel.room != o.channel.room && !own.any((c) => c.seed == o.channel.seed)).firstOrNull;
    if (next == null) return;
    ringing = next;
    notifyListeners();
  }

  /// Join on an offer's ring: the space goes among the spaces as a friend's share does, then its call is joined where
  /// it has one.
  Future<void> acceptOffer(VoiceRing r) async {
    final c = r.channel;
    offers = [for (final o in offers) if (o.channel.seed != c.seed) o];
    _keepOffers();
    if (identical(ringing, r)) ringing = null;
    // Pressed Join after it was removed: wanted again.
    _unmarkGone(c.seed);
    if (!own.any((o) => o.seed == c.seed)) {
      own = [...own, c];
      await _keep();
    }
    notifyListeners();
    if (c.hasVoice) await join(c);
    _raiseOffer();
  }

  void _markGone(String seed) {
    _gone.remove(seed);
    _gone.add(seed);
    if (_gone.length > _goneKept) _gone.removeRange(0, _gone.length - _goneKept);
    _app?.set('voice_gone', jsonEncode(_gone));
  }

  void _unmarkGone(String seed) {
    if (_gone.remove(seed)) _app?.set('voice_gone', jsonEncode(_gone));
  }

  /// The seeds of spaces archived here: out of Messages, in Archive with the archived conversations (Matt, 2026-11-17:
  /// "spaces outside of servers move to the main chat list and can be swiped to leave a space or delete / archive").
  final Set<String> _archived = {};

  bool archived(VoiceChannel c) => _archived.contains(c.seed);

  void archive(VoiceChannel c, bool on) {
    if (on ? !_archived.add(c.seed) : !_archived.remove(c.seed)) return;
    _app?.set('voice_archived', jsonEncode([..._archived]));
    notifyListeners();
  }

  /// How loud each person is played here, and who is silenced here, by their id: kept, and applied in every call with
  /// them (Matt, 2026-11-15: "press and hold on a user to habe options like muting changing volume levels").
  final Map<String, double> _volumes = {};
  final Set<String> _silenced = {};

  double volumeOf(String id) => _volumes[id] ?? 1.0;
  bool silenced(String id) => _silenced.contains(id);

  void setVolume(String id, double v) {
    _volumes[id] = v.clamp(0.0, 2.0);
    media?.setPeerVolume(id, _volumes[id]!);
    _keepPeople();
  }

  void setSilenced(String id, bool on) {
    on ? _silenced.add(id) : _silenced.remove(id);
    media?.setPeerMuted(id, on);
    // And what the hangout's roster says on top (someone muted for everyone stays silent).
    _enforce();
    _keepPeople();
  }

  void _keepPeople() {
    _app?.set('voice_people', jsonEncode({'v': _volumes, 'm': _silenced.toList()}));
    notifyListeners();
  }

  /// When each channel (by room) last had someone in it, as this device saw: what the list sorts channels by among
  /// conversations (Matt, 2026-11-15: "a mixed view that shows them all intertwined sorted by recency").
  final Map<String, int> _seen = {};

  /// Someone is in [c] now (this device among them).
  bool live(VoiceChannel c) => inChannel(c).isNotEmpty || session?.channel.room == c.room;

  /// When [c] last had anyone in it: now while it does; null where never seen.
  DateTime? lastActive(VoiceChannel c) {
    if (live(c)) return DateTime.now();
    final at = _seen[c.room];
    return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
  }

  void _saw(String room) {
    _seen[room] = DateTime.now().millisecondsSinceEpoch;
    _app?.set('voice_seen', jsonEncode(_seen));
  }

  Future<void> start(AppState app) async {
    // The call notification's Leave (android CallService.kt).
    _leaveCall ??= Sms.instance.leaveCall.stream.listen((_) => unawaited(leave()));
    if (_app != null) return;
    _app = app;
    try {
      own = [for (final j in jsonDecode(app.choice('voice_channels', '[]')) as List) ?VoiceChannel.fromJson(j)];
      _seen.addAll((jsonDecode(app.choice('voice_seen', '{}')) as Map).cast<String, int>());
      _readAt.addAll((jsonDecode(app.choice('voice_read', '{}')) as Map).map((k, v) => MapEntry('$k', (v as num).toInt())));
      _gone.addAll((jsonDecode(app.choice('voice_gone', '[]')) as List).whereType<String>());
      _archived.addAll((jsonDecode(app.choice('voice_archived', '[]')) as List).whereType<String>());
      final cutoff = DateTime.now().subtract(offerLife);
      offers = [for (final j in jsonDecode(app.choice('voice_offers', '[]')) as List) ?VoiceRing.offerFromJson(j)].where((o) => o.at.isAfter(cutoff) && !own.any((c) => c.seed == o.channel.seed)).toList();
      final people = jsonDecode(app.choice('voice_people', '{}')) as Map;
      _volumes.addAll(((people['v'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
      _silenced.addAll(((people['m'] as List?) ?? const []).cast<String>());
    } catch (_) {}
    Net.instance.addListener(_follow);
    if (Sms.paired) {
      unawaited(syncNow());
      _sync?.cancel();
      _sync = Timer.periodic(const Duration(seconds: 8), (_) => syncNow());
    }
    Groups.instance.addListener(_look);
    Net.instance.listen(_received);
    _follow();
    _raiseOffer();
  }

  /// Every channel: each group's, then those made or shared; on a computer, the phone's too.
  List<VoiceChannel> get channels {
    final out = <VoiceChannel>[
      for (final g in Groups.instance.all)
        if (!g.gone) VoiceChannel.ofGroup(g.id, g.name),
      ..._phone,
      ...own,
      ...circled,
    ];
    final seen = <String>{};
    return [for (final c in out) if (seen.add(c.seed)) c];
  }

  // --- the phone and its computer, in step (Matt, 2026-11-15: "make sure voice chats are kept actively in sync
  // between mobile and desktop clients") ---------------------------------------------------------------------------

  /// On a computer: the phone's channels (its groups' and its own), as it last said, and its name and username, which
  /// the computer goes by in a call.
  List<VoiceChannel> _phone = [];
  String? _deskName, _deskUsername;
  Timer? _sync;

  /// On the phone: what a paired computer asks (android DartAsk "voice"): every channel, the name to go by, and a
  /// channel the computer made, to keep here too.
  Future<Object?> answerDesk(Map<String, Object?> what) async {
    switch (what['op']) {
      case 'add':
        final c = VoiceChannel.fromJson({'s': what['s'], 'n': what['n'], 'o': what['o'], 'k': what['k']});
        // One removed here is not given back by a computer that had not heard yet.
        if (c != null && removed(c.seed)) return {'ok': false, 'gone': true};
        if (c != null && !own.any((o) => o.seed == c.seed)) {
          own = [...own, c.copyWith(mine: true)];
          await _keep();
        }
        return {'ok': true};
      case 'forget':
        if (what['s'] is String) _markGone(what['s'] as String);
        if (session != null && session!.channel.seed == what['s']) await leave();
        own = [for (final o in own) if (o.seed != what['s']) o];
        await _keep();
        return {'ok': true};
      case 'circle' || 'circle-join' || 'circle-forget':
        // A circle the computer made or changed, or left (lib/circles/circles.dart).
        return Circles.instance.answerDesk(what);
      default:
        final me = Me.instance;
        return {
          // A circle's spaces go with their circle ('circles'), not one by one.
          'channels': [
            for (final c in channels)
              if (c.circle == null) {'s': c.seed, 'n': c.name, if (c.group != null) 'g': c.group, if (c.mine) 'm': 1, if (c.owner.isNotEmpty) 'o': c.owner, if (c.kind != SpaceKind.voice) 'k': c.kind.wire},
          ],
          ...Circles.instance.forDesk(),
          // What was removed, here or from a computer, for every computer to take away too.
          'gone': _gone,
          'name': me.displayName.isNotEmpty ? me.displayName : (me.username == null ? '' : '@${me.username}'),
          if (me.username != null) 'u': me.username,
        };
    }
  }

  /// On a computer: asks the phone for its channels now, and every few seconds while the app is open.
  Future<void> syncNow() async {
    if (!Sms.paired) return;
    try {
      final got = await Sms.instance.voiceSync({'op': 'list'});
      // Removed on the phone: removed here too, and never handed back to it.
      final phoneGone = (got['gone'] as List? ?? const []).whereType<String>().toSet();
      var dropped = false;
      for (final s in phoneGone) {
        if (!removed(s)) _markGone(s);
        if (own.any((o) => o.seed == s)) {
          own = [for (final o in own) if (o.seed != s) o];
          dropped = true;
          if (session?.channel.seed == s) unawaited(leave());
        }
      }
      if (dropped) _app?.set('voice_channels', jsonEncode([for (final c in own) c.toJson()]));
      final list = <VoiceChannel>[];
      for (final j in (got['channels'] as List? ?? const [])) {
        if (j is! Map || j['s'] is! String || j['n'] is! String || (j['s'] as String).length != 64) continue;
        // Removed here while the phone was away: it is told again, and not shown meanwhile.
        if (removed(j['s'] as String)) {
          unawaited(Sms.instance.voiceSync({'op': 'forget', 's': j['s']}).catchError((_) => <String, dynamic>{}));
          continue;
        }
        final c = VoiceChannel.fromJson(j);
        if (c == null) continue;
        list.add(VoiceChannel(seed: c.seed, name: c.name, group: j['g'] as String?, mine: c.mine, owner: c.owner, kind: c.kind));
      }
      final name = got['name'] is String ? got['name'] as String : null;
      final changed = dropped || list.map((c) => '${c.seed}${c.name}${c.kind.wire}').join() != _phone.map((c) => '${c.seed}${c.name}${c.kind.wire}').join() || name != _deskName;
      _phone = list;
      _deskName = name;
      _deskUsername = got['u'] as String?;
      // Channels made here that the phone does not have yet go to it.
      for (final c in own) {
        if (!list.any((p) => p.seed == c.seed) && !removed(c.seed)) unawaited(Sms.instance.voiceSync(_deskAdd(c)).catchError((_) => <String, dynamic>{}));
      }
      // And the phone's circles, each kept at its newest list of spaces (lib/circles/circles.dart).
      Circles.instance.fromPhone(got);
      if (changed) _look();
    } catch (_) {
      // The phone is away or older: the computer keeps what it last heard.
    }
  }

  /// What the phone is told of a space made on a computer.
  static Map<String, Object?> _deskAdd(VoiceChannel c) => {'op': 'add', 's': c.seed, 'n': c.name, if (c.owner.isNotEmpty) 'o': c.owner, if (c.kind != SpaceKind.voice) 'k': c.kind.wire};

  /// Who is in [channel] now, as the hub says.
  List<String> inChannel(VoiceChannel channel) => _in[channel.room] ?? const [];

  /// The id this device is in channels as.
  String? get me => _route?.me;

  /// What this install signs with on the hub: its hangouts' rosters, and the key it owns hangouts by. On a computer
  /// its own key (made on first need), on a phone the phone's.
  NetSigner? get signer {
    final r = _route;
    if (r is HubVoiceRoute) return r.hub.signer;
    if (Sms.paired && _app != null) return (_ownHub ??= _macHub()).signer;
    return Net.instance.hub?.signer;
  }

  /// The public key (hex) this install owns spaces and circles by.
  String? get ownerKey {
    final s = signer;
    return s == null ? null : NetCrypto.hex(s.publicKey);
  }

  /// A name for [id]: a friend's, a group member's, or what they said in the call.
  String nameOf(String id) {
    if (id == me) return 'You';
    final said = session?.members[id]?.name;
    if (said != null && said.isNotEmpty) return said;
    final b = Buddies.instance.byId(id);
    if (b != null) return b.shown;
    for (final g in Groups.instance.all) {
      final m = g.member(id);
      if (m != null) return m.label;
    }
    return 'Someone';
  }

  void _follow() {
    final HubCarrier? hub;
    if (Sms.paired) {
      // Dialled only once there is a channel to see.
      if (channels.isEmpty && _ownHub == null) return;
      hub = _ownHub ??= _macHub();
      unawaited(hub.start());
    } else {
      hub = Net.instance.hub;
    }
    if (hub == null || (_route is HubVoiceRoute && identical((_route as HubVoiceRoute).hub, hub))) return;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final route = _route = HubVoiceRoute(hub);
    _subs.add(route.looks.listen((l) {
      _in[l.room] = l.members;
      if (l.members.isNotEmpty) _saw(l.room);
      notifyListeners();
    }));
    _look();
  }

  /// A computer's own key for the hub, kept with its choices.
  HubCarrier _macHub() {
    final app = _app!;
    var scalar = app.choice('voice_key', '');
    final NetKeys keys;
    if (scalar.length == 64) {
      keys = NetKeys.fromScalar(NetCrypto.unhex(scalar));
    } else {
      keys = NetKeys.generate();
      app.set('voice_key', NetCrypto.hex(keys.scalar));
    }
    return HubCarrier(url: Net.defaultHub, signer: KeysSigner(keys));
  }

  void _look() {
    if (Sms.paired && _ownHub == null && channels.isNotEmpty) return _follow();
    final route = _route;
    if (route == null) return;
    // The hub dialled for the channels too, on a phone, while there are any.
    if (!Sms.paired) unawaited(Net.instance.want('voice', channels.isNotEmpty));
    // Only a space with a call is looked at: a texting or Files space has no call room to ask about.
    for (final c in channels) {
      if (c.hasVoice) route.look(c.room, c.token);
    }
    _listenAll();
    notifyListeners();
  }

  // --- every space's chat, listened to while the app runs (Matt, 2026-11-17: spaces in the chats list "with a preview
  // of the last message sent in the space"; he chose staying connected over a preview of what this device last saw) ---

  /// The spaces whose chat rooms this device stays in for the list: held once each ([hold]).
  final Set<String> _listening = {};

  /// When this device last read each space's chat, by its seed (ms): what its unread count counts from.
  final Map<String, int> _readAt = {};

  void _listenAll() {
    if (_route == null) return;
    final want = {for (final c in channels) if (c.hangout) c.seed: c};
    for (final seed in [..._listening]) {
      if (want.containsKey(seed)) continue;
      _listening.remove(seed);
      final room = _hangouts[seed];
      if (room != null) unawaited(release(room.channel));
    }
    for (final c in want.values) {
      // A circle's space made another kind (or renamed): its room, held already, follows, so its roles and its
      // call match what it now is (HangoutRoom.updateChannel).
      final held = _hangouts[c.seed];
      if (held != null && (held.channel.kind != c.kind || held.channel.name != c.name)) held.updateChannel(c);
      if (!_listening.add(c.seed)) continue;
      // A space first listened to starts read: what was said in it before is not news.
      if (!_readAt.containsKey(c.seed)) {
        _readAt[c.seed] = lastMessage(c)?.at ?? DateTime.now().millisecondsSinceEpoch;
        _app?.set('voice_read', jsonEncode(_readAt));
      }
      unawaited(hold(c).catchError((_) => null));
    }
  }

  /// The newest message in [c]'s chat this device has; null where none (or a group's channel, whose chat is its texts).
  HangoutMessage? lastMessage(VoiceChannel c) {
    if (!c.hangout) return null;
    final room = _hangouts[c.seed];
    if (room != null) return room.messages.lastOrNull;
    final app = _app;
    return app == null ? null : AppHangoutStore(app).messages(c.chatRoom).lastOrNull;
  }

  /// How many of [c]'s messages from others came after this device last read it.
  int unreadIn(VoiceChannel c) {
    final room = _hangouts[c.seed];
    if (room == null) return 0;
    final since = _readAt[c.seed] ?? 0;
    return room.messages.where((m) => m.at > since && m.from != room.me).length;
  }

  /// How many of [c]'s unread messages ([unreadIn]) mention this device (Matt, 2026-11-19: "Add mentions support to
  /// spaces and circles with the @user prefix"): what an "@" on its unread mark counts.
  int mentionsIn(VoiceChannel c) {
    final room = _hangouts[c.seed];
    if (room == null) return 0;
    final since = _readAt[c.seed] ?? 0;
    return room.messages.where((m) => m.at > since && m.from != room.me && room.mentionsMe(m)).length;
  }

  /// [c]'s chat is read to its newest message.
  void markRead(VoiceChannel c) {
    final at = lastMessage(c)?.at ?? DateTime.now().millisecondsSinceEpoch;
    if ((_readAt[c.seed] ?? 0) >= at) return;
    _readAt[c.seed] = at;
    _app?.set('voice_read', jsonEncode(_readAt));
    MentionAlerts.instance?.read(c);
    notifyListeners();
  }

  Future<void> _keep() async {
    _app?.set('voice_channels', jsonEncode([for (final c in own) c.toJson()]));
    _look();
  }

  /// Makes a channel of this phone's, named [name], for chat and voice, texting or files ([kind]).
  Future<VoiceChannel> make(String name, {SpaceKind kind = SpaceKind.voice}) async {
    // This install owns it: its key is in the hangout, so everyone with the link knows whose roles to believe.
    final c = VoiceChannel.make(name.trim().isEmpty ? (kind == SpaceKind.voice ? 'Voice' : kind.label) : name.trim(), owner: ownerKey ?? '', kind: kind);
    own = [...own, c];
    await _keep();
    // Made on a computer: the phone keeps it too.
    if (Sms.paired) unawaited(Sms.instance.voiceSync(_deskAdd(c)).catchError((_) => <String, dynamic>{}));
    return c;
  }

  Future<void> forget(VoiceChannel c) async {
    if (session?.channel.room == c.room) await leave();
    _markGone(c.seed);
    own = [for (final o in own) if (o.seed != c.seed) o];
    _phone = [for (final o in _phone) if (o.seed != c.seed) o];
    if (Sms.paired) unawaited(Sms.instance.voiceSync({'op': 'forget', 's': c.seed}).catchError((_) => <String, dynamic>{}));
    _route?.unlook(c.room);
    await _keep();
  }

  /// Gives [c] to [friends]: they can see who is in it and hop in, and their app says who invited them (`by`, this
  /// phone's name). Gives back those it could not reach (no way to them now, or the send failed). A group's channel is
  /// its members' alone: given to no one.
  Future<List<Buddy>> share(VoiceChannel c, List<Buddy> friends) async {
    if (c.group != null) return friends;
    final by = _myName.isNotEmpty ? _myName : 'Someone';
    final missed = <Buddy>[];
    for (final f in friends) {
      final peer = Net.instance.byId(f.id);
      if (peer == null) {
        missed.add(f);
        continue;
      }
      try {
        final d = await Net.instance.send(peer, Envelope(kind: 'voice', body: {'t': 'channel', 's': c.seed, 'n': c.name, if (c.owner.isNotEmpty) 'o': c.owner, if (c.kind != SpaceKind.voice) 'k': c.kind.wire, 'by': by}));
        if (!d.sent) missed.add(f);
      } catch (_) {
        missed.add(f);
      }
    }
    return missed;
  }

  /// Rings everyone in [group]: their apps say the group is calling.
  Future<int> ring(Group group) async {
    var told = 0;
    final name = Me.instance.displayName.isNotEmpty ? Me.instance.displayName : (Me.instance.username == null ? 'Someone' : '@${Me.instance.username}');
    for (final m in group.others) {
      final peer = Net.instance.byId(m.id);
      if (peer == null) continue;
      final d = await Net.instance.send(peer, Envelope(kind: 'voice', body: {'t': 'ring', 'g': group.id, 'n': name}), urgent: true);
      if (d.sent) told++;
    }
    // Ringing out until someone comes in (VoiceSession: someone joining stops it), the call is left, or half a minute.
    if (told > 0) {
      Sounds.instance.loop(UiSound.ringOut);
      _ringOutEnds?.cancel();
      _ringOutEnds = Timer(_ringTime, () => Sounds.instance.stopLoop(UiSound.ringOut));
    }
    return told;
  }

  Timer? _ringOutEnds, _ringInEnds, _ringClears;

  /// How long a group's call rings, here or out.
  static const _ringTime = Duration(seconds: 30);

  /// Ringing here while [ringing] is, half a minute at most.
  void _ringIn(bool on) {
    _ringInEnds?.cancel();
    if (!on) return Sounds.instance.stopLoop(UiSound.ringIn);
    Sounds.instance.loop(UiSound.ringIn);
    _ringInEnds = Timer(_ringTime, () => Sounds.instance.stopLoop(UiSound.ringIn));
  }

  void _received(Received r) {
    if (r.envelope.kind != 'voice') return;
    final b = r.envelope.body;
    switch (b['t']) {
      case 'channel':
        // Only from a friend.
        if (Buddies.instance.byId(r.peer.id)?.state != 'yes') return;
        final c = VoiceChannel.fromJson({'s': b['s'], 'n': b['n'], 'o': b['o'], 'k': b['k']});
        if (c == null) return;
        // Said on screen, Join and Not now, unless already in its call or a group is calling (Matt, 2026-11-16:
        // invites into spaces).
        // The name this phone keeps for the friend first: the sender's own word for itself after.
        final ring = ringing;
        if (session?.channel.room != c.room && (ring == null || ring.invite || DateTime.now().difference(ring.at) >= _ringTime)) {
          ringing = VoiceRing(c, Buddies.instance.byId(r.peer.id)?.shown ?? '${b['by'] ?? nameOf(r.peer.id)}', DateTime.now(), invite: true);
          notifyListeners();
        }
        if (own.any((o) => o.seed == c.seed)) return;
        // Shared again by a friend, after it was removed: wanted again.
        _unmarkGone(c.seed);
        own = [...own, c];
        unawaited(_keep());
      case 'ring':
        final g = Groups.instance.all.where((g) => g.id == b['g'] && !g.gone).firstOrNull;
        if (g == null || g.member(r.peer.id) == null) return;
        final ring = ringing = VoiceRing(VoiceChannel.ofGroup(g.id, g.name), '${b['n'] ?? nameOf(r.peer.id)}', DateTime.now());
        // Not while already in that call.
        if (session?.channel.room != ring.channel.room) _ringIn(true);
        // Put away when unanswered for as long as it rings.
        _ringClears?.cancel();
        _ringClears = Timer(_ringTime, () {
          if (identical(ringing, ring)) dismissRing();
        });
        notifyListeners();
    }
  }

  void dismissRing() {
    _ringClears?.cancel();
    // An offer put off is kept, and raised again when the app next opens; the next one waiting comes up now.
    final r = ringing;
    if (r != null && r.offer) _putOff.add(r.channel.seed);
    ringing = null;
    _ringIn(false);
    _raiseOffer();
    notifyListeners();
  }

  // --- hangouts: chat and roles (lib/voice/hangout.dart, lib/voice/roles.dart) -----------------------------------

  final Map<String, HangoutRoom> _hangouts = {};
  final Map<String, int> _holds = {};

  /// [c]'s chat and roles where they are made already; null where not (nothing is made).
  HangoutRoom? heldHangout(VoiceChannel c) => _hangouts[c.seed];

  /// [c]'s chat and roles: made on first need, kept for as long as the app runs (its messages and roster are kept
  /// with the device's choices between runs). Null for a group's channel, or before the relay is connected.
  HangoutRoom? hangoutFor(VoiceChannel c) {
    if (!c.hangout) return null;
    final have = _hangouts[c.seed];
    if (have != null) return have;
    final route = _route;
    if (route == null) return null;
    final room = HangoutRoom(
      channel: c,
      route: route,
      name: _myName,
      username: _deskName == null ? Me.instance.username : _deskUsername,
      signer: signer,
      store: _app == null ? null : AppHangoutStore(_app!),
    );
    room.onRoster = (_) => _enforce();
    // Someone mentioning this device: its notification (lib/voice/mention_alerts.dart).
    room.onFresh = (fresh) {
      MentionAlerts.instance?.heard(room, fresh, readAt: _readAt[c.seed] ?? 0, nameOf: nameOf);
      // An SMS space this phone texts for: what is written there goes out by text (lib/circles/sms_space.dart).
      SmsSpaces.instance.heard(room, fresh);
    };
    room.addListener(notifyListeners);
    return _hangouts[c.seed] = room;
  }

  /// The hangout open in the conversation's place (the pane) while not in its call: VoiceScreen shows it (Matt,
  /// 2026-11-15: "clicking on a voice chat should show me the chat in the normal spot and connected participants with
  /// a "join" button").
  VoiceChannel? viewing;

  void view(VoiceChannel? c) {
    viewing = c;
    notifyListeners();
  }

  /// For a picture or a test: [room] as its hangout's, with no relay.
  @visibleForTesting
  void putHangout(HangoutRoom room) => _hangouts[room.channel.seed] = room;

  @visibleForTesting
  void clearHangouts() => _hangouts.clear();

  /// For a picture or a test: who the relay says is in [room], as a look would ([members] empty clears it).
  @visibleForTesting
  void putLook(String room, List<String> members) {
    members.isEmpty ? _in.remove(room) : _in[room] = members;
    notifyListeners();
  }

  /// For a test: what this device has read, forgotten.
  @visibleForTesting
  void clearRead() => _readAt.clear();

  /// Opens [c]'s chat room while something shows it (its page, or the call): [release] when done.
  Future<HangoutRoom?> hold(VoiceChannel c) async {
    final room = hangoutFor(c);
    if (room == null) return null;
    _holds[c.seed] = (_holds[c.seed] ?? 0) + 1;
    room.name = _myName;
    await room.open();
    return room;
  }

  Future<void> release(VoiceChannel c) async {
    final n = (_holds[c.seed] ?? 1) - 1;
    if (n > 0) {
      _holds[c.seed] = n;
      return;
    }
    _holds.remove(c.seed);
    await _hangouts[c.seed]?.close();
  }

  String get _myName => _deskName ?? (Me.instance.displayName.isNotEmpty ? Me.instance.displayName : (Me.instance.username == null ? '' : '@${Me.instance.username}'));

  /// Does in the call what the hangout's roster says: who is heard (not muted for everyone, allowed to speak, not
  /// silenced here), whether this device may speak or show video, and leaving when put out.
  void _enforce() {
    final s = session, m = media;
    if (s == null || m == null) return;
    final room = s.channel.hangout ? _hangouts[s.channel.seed] : null;
    for (final id in s.members.keys) {
      m.setPeerMuted(id, _silenced.contains(id) || (room != null && !room.heard(id)));
    }
    if (room == null) return;
    if (room.putOut != null) {
      unawaited(leave());
      return;
    }
    s.locked = !room.heard(room.me);
    if (s.locked && !s.muted) s.setMuted(true);
    s.videoLocked = !room.can(Perm.video);
    if (s.videoLocked && s.video) unawaited(s.setVideo(false));
  }

  /// Hops into [c], leaving any other first.
  Future<void> join(VoiceChannel c, {bool video = false}) async {
    final route = _route;
    if (route == null) throw StateError('The relay server isn\'t connected.');
    // A texting or Files space has no call (SpaceKind).
    if (!c.hasVoice) throw StateError('${c.name} is a ${c.kind.label.toLowerCase()} space, with no voice.');
    // In a circle, as its roles say (lib/circles: CirclePerm.voice).
    if (!Circles.instance.allows(c, CirclePerm.voice)) throw StateError('Your role in this circle can\'t talk in voice spaces.');
    if (session?.channel.room == c.room) return;
    await leave();
    if (ringing?.channel.room == c.room) {
      ringing = null;
      _ringIn(false);
    }
    final settings = _app == null ? const VoiceSettings() : VoiceSettings.of(_app!);
    final m = media = RtcMedia(settings: settings);
    for (final e in _volumes.entries) {
      m.setPeerVolume(e.key, e.value);
    }
    for (final id in _silenced) {
      m.setPeerMuted(id, true);
    }
    final name = _deskName ?? (Me.instance.displayName.isNotEmpty ? Me.instance.displayName : (Me.instance.username == null ? '' : '@${Me.instance.username}'));
    final s = session = VoiceSession(channel: c, route: route, media: m, name: name, username: _deskName == null ? Me.instance.username : _deskUsername, kbps: settings.sendKbps, stereo: settings.sendStereo);
    // A hangout's chat and roles while in its call: whoever is banned is not answered, and the roster is done.
    final room = await hold(c);
    if (room != null) {
      if (room.putOut != null) {
        session = null;
        media = null;
        await release(c);
        throw StateError(room.putOut!);
      }
      s.refuse = (id) => room.roster.banned.contains(id);
      room.sayMe(inVoice: true);
    }
    _saw(c.room);
    s.addListener(notifyListeners);
    s.addListener(_enforce);
    notifyListeners();
    try {
      final withVideo = video && (room == null || room.can(Perm.video));
      // On the phone the call goes on with the screen locked: its service holds the microphone and keeps the phone
      // awake until the call ends (android CallService.kt; Matt, 2026-11-15: "voice chat stops working when the phone
      // is locked").
      await Sms.instance.callStarted(c.name, video: withVideo);
      await s.join(withVideo: withVideo);
      _enforce();
    } catch (e) {
      await leave();
      rethrow;
    }
  }

  /// The settings as they stand (Settings › Voice), and a device chosen: kept, and used in the call there is.
  VoiceSettings get settings => _app == null ? const VoiceSettings() : VoiceSettings.of(_app!);

  /// Settings › Voice and video changed: what can change in a call there is changes now (RtcMedia.applyLive).
  Future<void> settingsChanged() async {
    final m = media;
    if (m is RtcMedia) await m.applyLive(settings);
  }

  Future<void> useInput(String deviceId) async {
    _app?.set('voice_input', deviceId);
    await media?.setInput(deviceId);
    notifyListeners();
  }

  Future<void> useOutput(String deviceId) async {
    _app?.set('voice_output', deviceId);
    await media?.setOutput(deviceId);
    notifyListeners();
  }

  Future<void> leave() async {
    final s = session;
    session = null;
    Sounds.instance.stopLoop(UiSound.ringOut);
    media = null;
    if (s != null) unawaited(Sms.instance.callEnded());
    if (s != null) {
      s.removeListener(notifyListeners);
      s.removeListener(_enforce);
      await s.leave();
      final room = _hangouts[s.channel.seed];
      if (room != null) {
        room.sayMe(inVoice: false);
        await release(s.channel);
      }
    }
    notifyListeners();
  }
}

/// A hangout's chat and roster kept with the device's choices (`hangout_<room>_m`, `hangout_<room>_r`).
class AppHangoutStore implements HangoutStore {
  AppHangoutStore(this.app);
  final AppState app;

  @override
  List<HangoutMessage> messages(String room) {
    try {
      final list = jsonDecode(app.choice('hangout_${room}_m', '[]')) as List;
      return [for (final j in list) if (j is Map && j['f'] is String) ?HangoutMessage.fromJson(j.cast<String, dynamic>(), j['f'] as String)];
    } catch (_) {
      return const [];
    }
  }

  @override
  void keepMessages(String room, List<HangoutMessage> messages) => app.set('hangout_${room}_m', jsonEncode([for (final m in messages) m.toStored()]));

  @override
  Roster? roster(String room) {
    try {
      return Roster.fromJson(jsonDecode(app.choice('hangout_${room}_r', '')));
    } catch (_) {
      return null;
    }
  }

  @override
  void keepRoster(String room, Roster roster) => app.set('hangout_${room}_r', jsonEncode(roster.toJson()));
}
