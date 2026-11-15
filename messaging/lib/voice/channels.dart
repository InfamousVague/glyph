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
import 'rtc.dart';
import 'voice.dart';
import 'voice_settings.dart';

/// Someone calling a group: its channel, and who.
@immutable
class VoiceRing {
  const VoiceRing(this.channel, this.from, this.at);
  final VoiceChannel channel;
  final String from;
  final DateTime at;
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

  AppState? _app;
  HubCarrier? _ownHub;
  VoiceRoute? _route;
  final List<StreamSubscription<Object?>> _subs = [];
  final Map<String, List<String>> _in = {};

  /// The channel this device is in, while it is.
  VoiceSession? session;
  RtcMedia? media;

  /// Someone calling a group, until it is answered or put away.
  VoiceRing? ringing;

  /// Channels made here or shared by friends.
  List<VoiceChannel> own = [];

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
    if (_app != null) return;
    _app = app;
    try {
      own = [for (final j in jsonDecode(app.choice('voice_channels', '[]')) as List) ?VoiceChannel.fromJson(j)];
      _seen.addAll((jsonDecode(app.choice('voice_seen', '{}')) as Map).cast<String, int>());
      final people = jsonDecode(app.choice('voice_people', '{}')) as Map;
      _volumes.addAll(((people['v'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
      _silenced.addAll(((people['m'] as List?) ?? const []).cast<String>());
    } catch (_) {}
    Net.instance.addListener(_follow);
    if (Sms.remote) {
      unawaited(syncNow());
      _sync?.cancel();
      _sync = Timer.periodic(const Duration(seconds: 8), (_) => syncNow());
    }
    Groups.instance.addListener(_look);
    Net.instance.listen(_received);
    _follow();
  }

  /// Every channel: each group's, then those made or shared; on a computer, the phone's too.
  List<VoiceChannel> get channels {
    final out = <VoiceChannel>[
      for (final g in Groups.instance.all)
        if (!g.gone) VoiceChannel.ofGroup(g.id, g.name),
      ..._phone,
      ...own,
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
        final c = VoiceChannel.fromJson({'s': what['s'], 'n': what['n']});
        if (c != null && !own.any((o) => o.seed == c.seed)) {
          own = [...own, VoiceChannel(seed: c.seed, name: c.name, mine: true)];
          await _keep();
        }
        return {'ok': true};
      case 'forget':
        own = [for (final o in own) if (o.seed != what['s']) o];
        await _keep();
        return {'ok': true};
      default:
        final me = Me.instance;
        return {
          'channels': [
            for (final c in channels) {'s': c.seed, 'n': c.name, if (c.group != null) 'g': c.group, if (c.mine) 'm': 1},
          ],
          'name': me.displayName.isNotEmpty ? me.displayName : (me.username == null ? '' : '@${me.username}'),
          if (me.username != null) 'u': me.username,
        };
    }
  }

  /// On a computer: asks the phone for its channels now, and every few seconds while the app is open.
  Future<void> syncNow() async {
    if (!Sms.remote) return;
    try {
      final got = await Sms.instance.voiceSync({'op': 'list'});
      final list = <VoiceChannel>[];
      for (final j in (got['channels'] as List? ?? const [])) {
        if (j is! Map || j['s'] is! String || j['n'] is! String || (j['s'] as String).length != 64) continue;
        list.add(VoiceChannel(seed: j['s'] as String, name: j['n'] as String, group: j['g'] as String?, mine: j['m'] == 1));
      }
      final name = got['name'] is String ? got['name'] as String : null;
      final changed = list.map((c) => '${c.seed}${c.name}').join() != _phone.map((c) => '${c.seed}${c.name}').join() || name != _deskName;
      _phone = list;
      _deskName = name;
      _deskUsername = got['u'] as String?;
      // Channels made here that the phone does not have yet go to it.
      for (final c in own) {
        if (!list.any((p) => p.seed == c.seed)) unawaited(Sms.instance.voiceSync({'op': 'add', 's': c.seed, 'n': c.name}).catchError((_) => <String, dynamic>{}));
      }
      if (changed) _look();
    } catch (_) {
      // The phone is away or older: the computer keeps what it last heard.
    }
  }

  /// Who is in [channel] now, as the hub says.
  List<String> inChannel(VoiceChannel channel) => _in[channel.room] ?? const [];

  /// The id this device is in channels as.
  String? get me => _route?.me;

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
    if (Sms.remote) {
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
    if (Sms.remote && _ownHub == null && channels.isNotEmpty) return _follow();
    final route = _route;
    if (route == null) return;
    // The hub dialled for the channels too, on a phone, while there are any.
    if (!Sms.remote) unawaited(Net.instance.want('voice', channels.isNotEmpty));
    for (final c in channels) {
      route.look(c.room, c.token);
    }
    notifyListeners();
  }

  Future<void> _keep() async {
    _app?.set('voice_channels', jsonEncode([for (final c in own) c.toJson()]));
    _look();
  }

  /// Makes a channel of this phone's, named [name].
  Future<VoiceChannel> make(String name) async {
    final c = VoiceChannel.make(name.trim().isEmpty ? 'Voice' : name.trim());
    own = [...own, c];
    await _keep();
    // Made on a computer: the phone keeps it too.
    if (Sms.remote) unawaited(Sms.instance.voiceSync({'op': 'add', 's': c.seed, 'n': c.name}).catchError((_) => <String, dynamic>{}));
    return c;
  }

  Future<void> forget(VoiceChannel c) async {
    if (session?.channel.room == c.room) await leave();
    own = [for (final o in own) if (o.seed != c.seed) o];
    _phone = [for (final o in _phone) if (o.seed != c.seed) o];
    if (Sms.remote) unawaited(Sms.instance.voiceSync({'op': 'forget', 's': c.seed}).catchError((_) => <String, dynamic>{}));
    _route?.unlook(c.room);
    await _keep();
  }

  /// Gives [c] to [friends]: they can see who is in it and hop in.
  Future<void> share(VoiceChannel c, List<Buddy> friends) async {
    for (final f in friends) {
      final peer = Net.instance.byId(f.id);
      if (peer == null) continue;
      await Net.instance.send(peer, Envelope(kind: 'voice', body: {'t': 'channel', 's': c.seed, 'n': c.name}));
    }
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
    return told;
  }

  void _received(Received r) {
    if (r.envelope.kind != 'voice') return;
    final b = r.envelope.body;
    switch (b['t']) {
      case 'channel':
        // Only from a friend.
        if (Buddies.instance.byId(r.peer.id)?.state != 'yes') return;
        final c = VoiceChannel.fromJson({'s': b['s'], 'n': b['n']});
        if (c == null || own.any((o) => o.seed == c.seed)) return;
        own = [...own, c];
        unawaited(_keep());
      case 'ring':
        final g = Groups.instance.all.where((g) => g.id == b['g'] && !g.gone).firstOrNull;
        if (g == null || g.member(r.peer.id) == null) return;
        ringing = VoiceRing(VoiceChannel.ofGroup(g.id, g.name), '${b['n'] ?? nameOf(r.peer.id)}', DateTime.now());
        notifyListeners();
    }
  }

  void dismissRing() {
    ringing = null;
    notifyListeners();
  }

  /// Hops into [c], leaving any other first.
  Future<void> join(VoiceChannel c, {bool video = false}) async {
    final route = _route;
    if (route == null) throw StateError('The relay server isn\'t connected.');
    if (session?.channel.room == c.room) return;
    await leave();
    if (ringing?.channel.room == c.room) ringing = null;
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
    _saw(c.room);
    s.addListener(notifyListeners);
    notifyListeners();
    try {
      await s.join(withVideo: video);
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
    media = null;
    if (s != null) {
      s.removeListener(notifyListeners);
      await s.leave();
    }
    notifyListeners();
  }
}
