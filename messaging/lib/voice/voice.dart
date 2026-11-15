import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../net/crypto.dart';
import '../net/hub_carrier.dart';

/// Voice and video channels (Matt, 2026-11-14: "I'd like to be able to jump in audio chats like discord has always
/// open voice channels that you can jump in and out at any time and you can see who's connected and also toggle
/// video on and off, also allow for group chat video and voice calls to hop in the voice and video channel at any time
/// with the option to call the group. This will be our fist step towards a discord style server please make sure we
/// stream at lossless quality").
///
/// **A channel** is a room on the relay server's hub, named and opened by a seed only its members hold: a group's
/// is made from the group's id (16 random bytes the members alone were given), one you make has a seed of its own,
/// given to the friends you share it with. From the seed come the room's name, its token (to join or look at it) and
/// the key what is said in it is sealed with ([VoiceChannel]). The hub sees that some installs are in a room, never
/// who they are or what they say.
///
/// **Who is connected** is shown without joining: the hub is asked to say who is in each channel ([VoiceRoute.look]).
/// Names come from the members themselves, sealed, as they join ([VoiceSession]).
///
/// **The sound and picture** go between the phones directly (WebRTC; lib/voice/rtc.dart), each to each: the hub
/// carries only how to connect. Sound is Opus at its highest: 48 kHz, stereo, 510 kb/s, no discontinuous
/// transmission ([highestOpus]); video is sent at up to 1080p and 12 Mb/s, holding resolution over frame rate.
/// That is as close to lossless as a live call carries: Opus at 510 kb/s is beyond what people hear as different
/// from the source, and no browser or phone engine sends uncompressed sound or picture.
@immutable
class VoiceChannel {
  const VoiceChannel({required this.seed, required this.name, this.group, this.mine = false});

  /// 32 bytes in hex: everything else comes from it.
  final String seed;
  final String name;

  /// The group whose channel this is; null for one made by someone.
  final String? group;

  /// Made on this phone.
  final bool mine;

  Uint8List get _seed => NetCrypto.unhex(seed);
  String get room => NetCrypto.hex(NetCrypto.derive(_seed, 'voice room').sublist(0, 16));
  String get token => NetCrypto.hex(NetCrypto.derive(_seed, 'voice token'));
  Uint8List get key => NetCrypto.derive(_seed, 'voice key');

  /// A group's channel, from the group's id.
  factory VoiceChannel.ofGroup(String groupId, String name) =>
      VoiceChannel(seed: NetCrypto.hex(NetCrypto.sha256(utf8.encode('ghost-voice group|$groupId'))), name: name, group: groupId);

  /// A new channel of this phone's.
  factory VoiceChannel.make(String name) => VoiceChannel(seed: NetCrypto.hex(NetCrypto.randomBytes(32)), name: name, mine: true);

  Map<String, Object> toJson() => {'s': seed, 'n': name, if (mine) 'm': 1};

  /// A link anyone can open in a browser to hop in, as a guest or signed up (site/join; Matt, 2026-11-14: "Make the
  /// voice hangouts possible to share via a link so people can join to talk anonymously or sign up through the
  /// browser similar to a zoom meeting"). The seed is in the part after the #, which a browser never sends to any
  /// server, so the link opens the channel and the relay still can't read it. Whoever has it is in, as with a
  /// meeting link.
  String get link => 'https://ghost-sms.com/join/#$seed.${base64Url.encode(utf8.encode(name)).replaceAll('=', '')}';

  static VoiceChannel? fromJson(Object? j) {
    if (j is! Map || j['s'] is! String || (j['s'] as String).length != 64 || j['n'] is! String) return null;
    return VoiceChannel(seed: j['s'] as String, name: j['n'] as String, mine: j['m'] == 1);
  }
}

/// What a voice channel stands on: the hub's rooms. The app's is the hub carrier ([HubVoiceRoute]); a test gives
/// one that passes packets between sessions.
abstract class VoiceRoute {
  String get me;
  Future<List<String>> join(String room, String token);
  void leave(String room);
  void send(String room, Uint8List bytes);
  void look(String room, String token);
  void unlook(String room);
  Stream<RoomEvent> get events;
  Stream<({String room, String from, Uint8List bytes})> get packets;
  Stream<({String room, List<String> members})> get looks;
}

class HubVoiceRoute implements VoiceRoute {
  HubVoiceRoute(this.hub);
  final HubCarrier hub;
  @override
  String get me => hub.signer.id;
  @override
  Future<List<String>> join(String room, String token) => hub.join(room, token);
  @override
  void leave(String room) => hub.leave(room);
  @override
  void send(String room, Uint8List bytes) => hub.sendRoom(room, bytes);
  @override
  void look(String room, String token) => hub.look(room, token);
  @override
  void unlook(String room) => hub.unlook(room);
  @override
  Stream<RoomEvent> get events => hub.roomEvents;
  @override
  Stream<({String room, String from, Uint8List bytes})> get packets => hub.roomPackets;
  @override
  Stream<({String room, List<String> members})> get looks => hub.looks;
}

/// One other person's connection in a call: what WebRTC needs said between the two, said through the channel.
abstract class VoicePeer {
  Future<String> makeOffer();
  Future<String> takeOffer(String sdp);
  Future<void> takeAnswer(String sdp);
  Future<void> addCandidate(Map<String, dynamic> candidate);
  Future<void> close();
}

/// This device's microphone and camera, and the connections to the others (lib/voice/rtc.dart).
abstract class VoiceMedia {
  /// How loud each one is now, 0 to 1: `me` for this device's microphone, and each other member by id. What the
  /// call's faces ripple with while someone talks.
  ValueListenable<Map<String, double>> get levels;
  Future<void> start();
  Future<void> stop();
  set muted(bool on);
  set deafened(bool on);
  Future<void> setVideo(bool on);

  /// How loud [id] is played on this device, 0 to 2 (1 as they send it), and whether they are silenced for this
  /// device alone (Matt, 2026-11-15: "press and hold on a user to habe options like muting changing volume levels for
  /// that user").
  void setPeerVolume(String id, double volume);
  void setPeerMuted(String id, bool muted);
  VoicePeer peer(String id, {required void Function(Map<String, dynamic> candidate) onCandidate});
}

/// Someone in the call, as they said they are.
@immutable
class VoiceMember {
  const VoiceMember(this.id, {this.name = '', this.muted = false, this.video = false, this.guest = false, this.username});
  final String id;
  final String name;

  /// Their username on Ghost Messaging, where they have one and said it: to add them as a friend.
  final String? username;
  final bool muted;
  final bool video;

  /// Joined from a browser by the link, with no username: a guest.
  final bool guest;
  VoiceMember copyWith({String? name, bool? muted, bool? video, bool? guest, String? username}) =>
      VoiceMember(id, name: name ?? this.name, muted: muted ?? this.muted, video: video ?? this.video, guest: guest ?? this.guest, username: username ?? this.username);
}

/// Being in one channel: joined on the hub, a connection to each member, and what each says of themselves.
///
/// Who connects to whom: whoever comes in makes an offer to each who is already there; those there answer. So two
/// never offer each other at once. What is said (offers, answers, ways to connect, and each member's name, muted
/// and video) is sealed with the channel's key and sent to the room, naming who it is for where it is for one.
class VoiceSession extends ChangeNotifier {
  VoiceSession({required this.channel, required this.route, required this.media, required this.name, this.username, this.kbps = 510, this.stereo = true});

  /// Opus as the settings ask (lib/voice/voice_settings.dart).
  final int kbps;
  final bool stereo;

  /// This device's username, said to the others so they can add it as a friend.
  final String? username;

  final VoiceChannel channel;
  final VoiceRoute route;
  final VoiceMedia media;

  /// This device's name, as the others see it.
  final String name;

  final Map<String, VoiceMember> members = {};
  final Map<String, VoicePeer> _peers = {};
  final List<StreamSubscription<Object?>> _subs = [];
  bool muted = false, deafened = false, video = false, joined = false;

  /// When this device came into the call.
  DateTime? since;

  Future<void> join({bool withVideo = false}) async {
    video = withVideo;
    await media.start();
    if (withVideo) await media.setVideo(true);
    _subs.add(route.packets.where((p) => p.room == channel.room).listen((p) => _heard(p.from, p.bytes)));
    _subs.add(route.events.where((e) => e.room == channel.room).listen(_event));
    final there = await route.join(channel.room, channel.token);
    joined = true;
    since = DateTime.now();
    for (final id in there) {
      members[id] = VoiceMember(id);
    }
    _sayState();
    for (final id in there) {
      unawaited(_offer(id));
    }
    notifyListeners();
  }

  Future<void> leave() async {
    if (joined) route.leave(channel.room);
    joined = false;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final p in _peers.values) {
      await p.close();
    }
    _peers.clear();
    members.clear();
    await media.stop();
    notifyListeners();
  }

  void setMuted(bool on) {
    muted = on;
    media.muted = on || deafened;
    _sayState();
    notifyListeners();
  }

  void setDeafened(bool on) {
    deafened = on;
    media.deafened = on;
    media.muted = muted || on;
    _sayState();
    notifyListeners();
  }

  Future<void> setVideo(bool on) async {
    video = on;
    await media.setVideo(on);
    _sayState();
    notifyListeners();
  }

  void _event(RoomEvent e) {
    if (e.came != null) {
      // They offer: they came in.
      members[e.came!] = VoiceMember(e.came!);
      _sayState();
    } else if (e.went != null) {
      members.remove(e.went);
      unawaited(_peers.remove(e.went)?.close());
    }
    notifyListeners();
  }

  VoicePeer _peerFor(String id) => _peers[id] ??= media.peer(id, onCandidate: (c) => _say({'t': 'ice', 'to': id, 'c': c}));

  Future<void> _offer(String id) async {
    final sdp = await _peerFor(id).makeOffer();
    _say({'t': 'offer', 'to': id, 'sdp': highestOpus(sdp, kbps: kbps, stereo: stereo)});
  }

  void _sayState() => _say({'t': 'me', 'n': name, 'm': muted || deafened, 'v': video, if (username != null) 'u': username});

  void _say(Map<String, Object?> what) {
    if (!joined) return;
    try {
      route.send(channel.room, NetCrypto.seal(channel.key, utf8.encode(jsonEncode(what))));
    } catch (_) {}
  }

  Future<void> _heard(String from, Uint8List bytes) async {
    final clear = NetCrypto.open(channel.key, bytes);
    if (clear == null) return;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(utf8.decode(clear)) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final to = m['to'];
    if (to != null && to != route.me) return;
    switch (m['t']) {
      case 'me':
        final had = members[from] ?? VoiceMember(from);
        members[from] = had.copyWith(name: '${m['n'] ?? ''}', muted: m['m'] == true, video: m['v'] == true, guest: m['g'] == true, username: m['u'] is String ? m['u'] as String : null);
        notifyListeners();
      case 'offer':
        members.putIfAbsent(from, () => VoiceMember(from));
        final answer = await _peerFor(from).takeOffer('${m['sdp']}');
        _say({'t': 'answer', 'to': from, 'sdp': highestOpus(answer, kbps: kbps, stereo: stereo)});
        // Said again for the newcomer, who may have joined after it was said.
        _sayState();
      case 'answer':
        await _peers[from]?.takeAnswer('${m['sdp']}');
      case 'ice':
        if (m['c'] is Map) await _peerFor(from).addCandidate((m['c'] as Map).cast<String, dynamic>());
    }
  }

  @override
  void dispose() {
    unawaited(leave());
    super.dispose();
  }
}

/// How each copy of this device's picture is sent, by how many others are in the call (tool/voicebench, 2026-11-15:
/// each connection encodes its own copy, so at 1080p for everyone three or more people fell to a frame a second).
/// Alone with one other it is the camera's full 1080p at up to 12 Mb/s; with more, a smaller copy to each, and under
/// load a little resolution goes before the frame rate does. Sound is always Opus at 510 kb/s.
({double scale, int bitrate, String preference}) videoFor(int others) => switch (others) {
      <= 1 => (scale: 1.0, bitrate: 12000000, preference: 'balanced'),
      2 => (scale: 1.5, bitrate: 4000000, preference: 'balanced'),
      3 || 4 => (scale: 2.0, bitrate: 2000000, preference: 'balanced'),
      _ => (scale: 3.0, bitrate: 1000000, preference: 'balanced'),
    };

/// [sdp] with Opus asked for at its highest: full band at 48 kHz, stereo both ways, 510 kb/s, constant bit rate,
/// no discontinuous transmission, with forward error correction kept for lost packets.
String highestOpus(String sdp, {int kbps = 510, bool stereo = true}) {
  final lines = sdp.split('\r\n');
  final opus = RegExp(r'^a=rtpmap:(\d+) opus/48000', caseSensitive: false);
  final payloads = {for (final l in lines) if (opus.hasMatch(l)) opus.firstMatch(l)!.group(1)!};
  if (payloads.isEmpty) return sdp;
  final want = {'minptime': '10', 'useinbandfec': '1', 'stereo': stereo ? '1' : '0', 'sprop-stereo': stereo ? '1' : '0', 'maxaveragebitrate': '${kbps * 1000}', 'maxplaybackrate': '48000', 'cbr': '1', 'usedtx': '0'};
  final out = <String>[];
  final fmtpDone = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final fmtp = RegExp(r'^a=fmtp:(\d+) (.*)$').firstMatch(l);
    if (fmtp != null && payloads.contains(fmtp.group(1))) {
      final params = <String, String>{};
      for (final kv in fmtp.group(2)!.split(';')) {
        final at = kv.indexOf('=');
        if (at > 0) params[kv.substring(0, at).trim()] = kv.substring(at + 1).trim();
      }
      params.addAll(want);
      out.add('a=fmtp:${fmtp.group(1)} ${params.entries.map((e) => '${e.key}=${e.value}').join(';')}');
      fmtpDone.add(fmtp.group(1)!);
      continue;
    }
    out.add(l);
    final rtp = opus.firstMatch(l);
    if (rtp != null && !lines.any((x) => x.startsWith('a=fmtp:${rtp.group(1)} '))) {
      out.add('a=fmtp:${rtp.group(1)} ${want.entries.map((e) => '${e.key}=${e.value}').join(';')}');
      fmtpDone.add(rtp.group(1)!);
    }
  }
  return out.join('\r\n');
}
