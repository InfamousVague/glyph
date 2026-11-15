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

  Future<void> start(AppState app) async {
    if (_app != null) return;
    _app = app;
    try {
      own = [for (final j in jsonDecode(app.choice('voice_channels', '[]')) as List) ?VoiceChannel.fromJson(j)];
    } catch (_) {}
    Net.instance.addListener(_follow);
    Groups.instance.addListener(_look);
    Net.instance.listen(_received);
    _follow();
  }

  /// Every channel: each group's, then those made or shared.
  List<VoiceChannel> get channels => [
        for (final g in Groups.instance.all)
          if (!g.gone) VoiceChannel.ofGroup(g.id, g.name),
        ...own,
      ];

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
    return c;
  }

  Future<void> forget(VoiceChannel c) async {
    if (session?.channel.room == c.room) await leave();
    own = [for (final o in own) if (o.seed != c.seed) o];
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
    final m = media = RtcMedia();
    final name = Me.instance.displayName.isNotEmpty ? Me.instance.displayName : (Me.instance.username == null ? '' : '@${Me.instance.username}');
    final s = session = VoiceSession(channel: c, route: route, media: m, name: name);
    s.addListener(notifyListeners);
    notifyListeners();
    try {
      await s.join(withVideo: video);
    } catch (e) {
      await leave();
      rethrow;
    }
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
