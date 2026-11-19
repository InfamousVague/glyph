import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../net/crypto.dart';
import '../net/hub_carrier.dart';
import '../sounds.dart';

/// What a space is for (Matt, 2026-11-17: "each space should be able to act as a chat and a voice chat, or just a
/// texting space. Additionally add full functionality for filesharing in a space when the space is designated a Files
/// Space"). Every space has its chat room; only a [voice] one has a call, so a [text] or [files] one never shows Join
/// and never asks the relay who is in a call room it does not have.
///
/// Carried as `k` wherever a space goes (its JSON, its link, the invite, the phone and computer in step), left out for
/// [voice], so a space from before kinds is a voice one and an older build reading a newer space just sees a voice
/// space.
enum SpaceKind {
  voice('Chat and voice', 'Talk any time, with a chat beside it'),
  text('Texting', 'A chat, no voice'),
  files('Files', 'Share files, with a chat beside them');

  const SpaceKind(this.label, this.hint);
  final String label;
  final String hint;

  /// Its word on the wire: `voice`, `text`, `files`.
  String get wire => name;

  bool get hasVoice => this == voice;

  /// From its word; voice for anything else (missing, or a kind from a newer build).
  static SpaceKind of(Object? wire) {
    for (final k in values) {
      if (k.name == wire) return k;
    }
    return voice;
  }
}

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
  const VoiceChannel({required this.seed, required this.name, this.group, this.mine = false, this.owner = '', this.discord, this.kind = SpaceKind.voice, this.circle});

  /// 32 bytes in hex: everything else comes from it.
  final String seed;
  final String name;

  /// The group whose channel this is; null for one made by someone.
  final String? group;

  /// Made on this phone.
  final bool mine;

  /// Bridged to a Discord voice channel (lib/voice/discord.dart, messaging/discord/): `<guild>/<channel>`. The bridge
  /// is a member of the space and carries its sound and chat to and from Discord, so it is not end-to-end encrypted.
  final String? discord;

  /// The public key (33 bytes in hex) of the install that made it: the hangout's owner, who decides its roles
  /// (lib/voice/roles.dart). Empty for a group's channel and for hangouts made before roles.
  final String owner;

  /// What it is for: chat and voice, texting, or files ([SpaceKind]). A group's channel is always voice.
  final SpaceKind kind;

  /// The circle it is a space of (its seed, lib/circles/circle.dart), or null for a space of its own. A circle's spaces
  /// are listed in the circle, not in Messages; this is not kept in the space's JSON, since the circle's list of spaces
  /// is what says which are its.
  final String? circle;

  /// Whether it has a call: a [SpaceKind.voice] space, or a group's channel.
  bool get hasVoice => kind.hasVoice;

  Uint8List get _seed => NetCrypto.unhex(seed);
  String get room => NetCrypto.hex(NetCrypto.derive(_seed, 'voice room').sublist(0, 16));
  String get token => NetCrypto.hex(NetCrypto.derive(_seed, 'voice token'));
  Uint8List get key => NetCrypto.derive(_seed, 'voice key');

  /// The hangout's chat room: a room of its own beside the call's, which anyone looking at the hangout is in, so the
  /// chat and the roles reach people who are not in the call (lib/voice/hangout.dart).
  String get chatRoom => NetCrypto.hex(NetCrypto.derive(_seed, 'hangout room').sublist(0, 16));
  String get chatToken => NetCrypto.hex(NetCrypto.derive(_seed, 'hangout token'));

  /// A group's channel, from the group's id.
  factory VoiceChannel.ofGroup(String groupId, String name) =>
      VoiceChannel(seed: NetCrypto.hex(NetCrypto.sha256(utf8.encode('ghost-voice group|$groupId'))), name: name, group: groupId);

  /// A new channel of this phone's.
  factory VoiceChannel.make(String name, {String owner = '', SpaceKind kind = SpaceKind.voice}) => VoiceChannel(seed: NetCrypto.hex(NetCrypto.randomBytes(32)), name: name, mine: true, owner: owner, kind: kind);

  /// A hangout (not a group's channel): it has a chat and roles.
  bool get hangout => group == null;

  VoiceChannel copyWith({bool? mine, String? name, SpaceKind? kind}) =>
      VoiceChannel(seed: seed, name: name ?? this.name, group: group, mine: mine ?? this.mine, owner: owner, discord: discord, kind: kind ?? this.kind, circle: circle);

  Map<String, Object> toJson() => {'s': seed, 'n': name, if (mine) 'm': 1, if (owner.isNotEmpty) 'o': owner, if (kind != SpaceKind.voice) 'k': kind.wire};

  /// A link anyone can open in a browser to hop in, as a guest or signed up (site/join; Matt, 2026-11-14: "Make the
  /// voice hangouts possible to share via a link so people can join to talk anonymously or sign up through the
  /// browser similar to a zoom meeting"). The seed is in the part after the #, which a browser never sends to any
  /// server, so the link opens the channel and the relay still can't read it. Whoever has it is in, as with a
  /// meeting link.
  ///
  /// The owner's key follows the name, so the browser knows whose roles to believe; a texting or Files space ends with
  /// its kind (`.text`, `.files`), which can't be taken for a name or a key, so the page knows not to offer voice.
  String get link => 'https://gogho.st/join/#$seed.${base64Url.encode(utf8.encode(name)).replaceAll('=', '')}${owner.isEmpty ? '' : '.$owner'}${kind == SpaceKind.voice ? '' : '.${kind.wire}'}';

  /// The space a [link] (or just its part after the #) is; null where it is not one, a circle's among them.
  static VoiceChannel? fromLink(String link) {
    final hash = link.contains('#') ? link.substring(link.indexOf('#') + 1) : link;
    final m = RegExp(r'^([0-9a-f]{64})(?:\.([A-Za-z0-9_-]*))?(?:\.(0[23][0-9a-f]{64}))?(?:\.(voice|text|files))?$').firstMatch(hash);
    if (m == null) return null;
    var name = 'Space';
    try {
      final b = m.group(2) ?? '';
      if (b.isNotEmpty) name = utf8.decode(base64Url.decode(base64Url.normalize(b)));
    } catch (_) {}
    return VoiceChannel(seed: m.group(1)!, name: name.isEmpty ? 'Space' : name, owner: m.group(3) ?? '', kind: SpaceKind.of(m.group(4)));
  }

  static VoiceChannel? fromJson(Object? j) {
    if (j is! Map || j['s'] is! String || (j['s'] as String).length != 64 || j['n'] is! String) return null;
    final owner = j['o'] is String && RegExp(r'^0[23][0-9a-f]{64}$').hasMatch(j['o'] as String) ? j['o'] as String : '';
    return VoiceChannel(seed: j['s'] as String, name: j['n'] as String, mine: j['m'] == 1, owner: owner, kind: SpaceKind.of(j['k']));
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

  /// Sends [bytes] to the room and has the hub keep them for whoever joins later (HubCarrier.sendRoom's keep).
  void sendKept(String room, Uint8List bytes) => hub.sendRoom(room, bytes, keep: true);
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

/// Someone in a Discord voice channel a space is bridged to, as the bridge says (voice room message 'dc').
@immutable
class DiscordPerson {
  const DiscordPerson({required this.id, required this.name, this.speaking = false, this.muted = false, this.deafened = false, this.bot = false});
  final String id;
  final String name;
  final bool speaking, muted, deafened, bot;

  static DiscordPerson? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['name'] is! String) return null;
    return DiscordPerson(id: j['id'] as String, name: j['name'] as String, speaking: j['speaking'] == true, muted: j['muted'] == true, deafened: j['deafened'] == true, bot: j['bot'] == true);
  }
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

  /// Where the space is bridged to Discord: everyone in the Discord voice channel, as the bridge last said ('dc'), and
  /// the bridge's own id (a member, not shown as a person).
  List<DiscordPerson> discordPeople = const [];
  String? bridgeId;

  /// The Discord people's talking as levels (`dc:<id>`), for their faces to ripple as everyone's do.
  final ValueNotifier<Map<String, double>> discordLevels = ValueNotifier(const {});

  /// Who is not answered at all (a hangout's banned: lib/voice/hangout.dart).
  bool Function(String id)? refuse;

  /// This device may not unmute (muted for everyone, or its role may not speak), or turn on video.
  bool locked = false, videoLocked = false;
  final Map<String, VoicePeer> _peers = {};
  final List<StreamSubscription<Object?>> _subs = [];
  bool muted = false, deafened = false, video = false, joined = false;

  /// When this device came into the call.
  DateTime? since;

  /// Told when another device of this identity came into the call and took it over ([join]); without it the session
  /// just leaves.
  Future<void> Function()? onMovedAway;
  bool _moving = false;

  /// This join's own mark, said with 'moved', offers and answers: so of two devices of one identity the one that came
  /// in later stays, and an answer meant for the other is never taken here.
  final String _join = NetCrypto.hex(NetCrypto.randomBytes(8));

  /// The join each other member's last offer came from ('j'): a new one is another of their devices, or them again.
  final Map<String, Object?> _offerJoin = {};

  Future<void> join({bool withVideo = false}) async {
    video = withVideo;
    await media.start();
    if (withVideo) await media.setVideo(true);
    _subs.add(route.packets.where((p) => p.room == channel.room).listen((p) => _heard(p.from, p.bytes)));
    _subs.add(route.events.where((e) => e.room == channel.room).listen(_event));
    // A call is joined now or said to have failed: a room asked for before the relay server is up waits for it
    // (HubCarrier.join), and a call should not.
    final there = await route.join(channel.room, channel.token).timeout(const Duration(seconds: 15), onTimeout: () => throw StateError('the relay server did not answer'));
    joined = true;
    since = DateTime.now();
    Sounds.instance.play(UiSound.hangoutJoin);
    // This identity is in the call on this device now ('moved'): another of its devices already in it (a phone and its
    // computer, or two computers signed in to one account, are one identity: Voice.separateKey) leaves, as Discord does
    // when one joins from elsewhere, and everyone else lets go of any connection they had with this identity, so the
    // offers below make new ones. Said on every join: the relay never names one's own identity among those here, and to
    // whoever had no such connection it means nothing. Two devices answering the same offers would have broken the call.
    _say({'t': 'moved', 'at': since!.millisecondsSinceEpoch, 'j': _join});
    for (final id in there) {
      if (id == route.me || (refuse?.call(id) ?? false)) continue;
      members[id] = VoiceMember(id);
    }
    _sayState();
    for (final id in members.keys.toList()) {
      unawaited(_offer(id));
    }
    notifyListeners();
  }

  Future<void> leave() async {
    if (joined) Sounds.instance.play(UiSound.hangoutLeave);
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
    if (!on && locked) return;
    if (on != muted) Sounds.instance.play(on ? UiSound.mute : UiSound.unmute);
    muted = on;
    media.muted = on || deafened;
    _sayState();
    notifyListeners();
  }

  void setDeafened(bool on) {
    if (on != deafened) Sounds.instance.play(on ? UiSound.deafen : UiSound.undeafen);
    deafened = on;
    media.deafened = on;
    media.muted = muted || on;
    _sayState();
    notifyListeners();
  }

  Future<void> setVideo(bool on) async {
    if (on && videoLocked) return;
    video = on;
    await media.setVideo(on);
    _sayState();
    notifyListeners();
  }

  void _event(RoomEvent e) {
    // Another device of this identity is not someone else in the call.
    if (e.came == route.me || e.went == route.me) return;
    if (e.came != null) {
      if (refuse?.call(e.came!) ?? false) return;
      // They offer: they came in.
      if (!members.containsKey(e.came!)) {
        Sounds.instance.stopLoop(UiSound.ringOut);
        Sounds.instance.play(UiSound.someoneJoined);
      }
      members[e.came!] = VoiceMember(e.came!);
      _sayState();
    } else if (e.went != null) {
      final was = members.remove(e.went) != null;
      unawaited(_peers.remove(e.went)?.close());
      // The last of the others gone: the call is over, said so; anyone else going is someone leaving.
      if (was) Sounds.instance.play(members.isEmpty ? UiSound.callEnded : UiSound.someoneLeft);
    }
    notifyListeners();
  }

  VoicePeer _peerFor(String id) => _peers[id] ??= media.peer(id, onCandidate: (c) => _say({'t': 'ice', 'to': id, 'c': c}));

  Future<void> _offer(String id) async {
    final sdp = await _peerFor(id).makeOffer();
    _say({'t': 'offer', 'to': id, 'sdp': highestOpus(sdp, kbps: kbps, stereo: stereo), 'j': _join});
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
    // Said by another device of this identity: it took the call over ([join]), so this one goes. Nothing else it says is
    // for this device (an offer it makes is to the others, never to itself).
    if (from == route.me) {
      // Only for a join later than this one (two coming in at once: the later stays, and the earlier hears it).
      final at = (m['at'] as num?)?.toInt() ?? 0, mine = since?.millisecondsSinceEpoch ?? 0;
      final later = at > mine || (at == mine && '${m['j'] ?? ''}'.compareTo(_join) > 0);
      if (m['t'] == 'moved' && joined && !_moving && later) {
        _moving = true;
        unawaited(_movedAway());
      }
      return;
    }
    // Going, for the device that took over: what the others answer it is not for this one.
    if (_moving) return;
    final to = m['to'];
    if (to != null && to != route.me) return;
    if (refuse?.call(from) ?? false) {
      members.remove(from);
      unawaited(_peers.remove(from)?.close());
      return;
    }
    switch (m['t']) {
      case 'dc':
        // The bridge to Discord saying who is in the Discord voice channel, and who is talking there.
        bridgeId = from;
        discordPeople = [for (final p in (m['people'] as List? ?? const [])) ?DiscordPerson.fromJson(p)];
        discordLevels.value = {for (final p in discordPeople) 'dc:${p.id}': p.speaking && !p.muted ? 0.5 : 0.0};
        notifyListeners();
      case 'me':
        final had = members[from] ?? VoiceMember(from);
        members[from] = had.copyWith(name: '${m['n'] ?? ''}', muted: m['m'] == true, video: m['v'] == true, guest: m['g'] == true, username: m['u'] is String ? m['u'] as String : null);
        notifyListeners();
      case 'offer':
        members.putIfAbsent(from, () => VoiceMember(from));
        // An offer from another join of theirs (another device, or the app opened again) is a new connection: the old
        // one goes first, whether or not 'moved' got here (an older build says none).
        final j = m['j'];
        if (_peers.containsKey(from) && j != null && _offerJoin[from] != j) await _peers.remove(from)?.close();
        _offerJoin[from] = j;
        final answer = await _peerFor(from).takeOffer('${m['sdp']}');
        _say({'t': 'answer', 'to': from, 'sdp': highestOpus(answer, kbps: kbps, stereo: stereo), 'j': ?j});
        // Said again for the newcomer, who may have joined after it was said.
        _sayState();
      case 'moved':
        // They came in on another of their devices: the connection to the one they left goes, and their offer makes a
        // new one.
        unawaited(_peers.remove(from)?.close());
        notifyListeners();
      case 'answer':
        // One meant for another device of this identity's (its offer's mark, not this one's) is not taken here.
        final j = m['j'];
        if (j != null && j != _join) return;
        await _peers[from]?.takeAnswer('${m['sdp']}');
      case 'ice':
        if (m['c'] is Map) await _peerFor(from).addCandidate((m['c'] as Map).cast<String, dynamic>());
    }
  }

  Future<void> _movedAway() async {
    final told = onMovedAway;
    if (told != null) return told();
    await leave();
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
