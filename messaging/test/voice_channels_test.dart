import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/voice/channels.dart';
import 'package:ghost_messaging/voice/voice.dart';

/// Voice and video channels (lib/voice/voice.dart). Matt, 2026-11-14: "jump in audio chats like discord has always
/// open voice channels that you can jump in and out at any time and you can see who's connected and also toggle video
/// on and off ... please make sure we stream at lossless quality".
///
/// A hub stood in for (rooms: join, leave, a packet to everyone else, who came and went) and WebRTC stood in for (each
/// connection says what it was asked to make and take), so what goes between the members can be watched.
class _Hub {
  final Map<String, Map<String, _Route>> rooms = {};
}

class _Route implements VoiceRoute {
  _Route(this.hub, this.me);
  final _Hub hub;
  @override
  final String me;
  final _events = StreamController<RoomEvent>.broadcast();
  final _packets = StreamController<({String room, String from, Uint8List bytes})>.broadcast();
  final _looks = StreamController<({String room, List<String> members})>.broadcast();

  @override
  Future<List<String>> join(String room, String token) async {
    final r = hub.rooms[room] ??= {};
    final others = r.keys.toList();
    r[me] = this;
    for (final o in r.values) {
      if (o != this) scheduleMicrotask(() => o._events.add(RoomEvent(room, came: me)));
    }
    return others;
  }

  @override
  void leave(String room) {
    final r = hub.rooms[room];
    r?.remove(me);
    for (final o in r?.values ?? const <_Route>[]) {
      scheduleMicrotask(() => o._events.add(RoomEvent(room, went: me)));
    }
  }

  @override
  void send(String room, Uint8List bytes) {
    for (final o in hub.rooms[room]?.values ?? const <_Route>[]) {
      if (o != this) scheduleMicrotask(() => o._packets.add((room: room, from: me, bytes: bytes)));
    }
  }

  @override
  void look(String room, String token) {}
  @override
  void unlook(String room) {}
  @override
  Stream<RoomEvent> get events => _events.stream;
  @override
  Stream<({String room, String from, Uint8List bytes})> get packets => _packets.stream;
  @override
  Stream<({String room, List<String> members})> get looks => _looks.stream;
}

class _Media implements VoiceMedia {
  @override
  final ValueNotifier<Map<String, double>> levels = ValueNotifier(const {});
  final log = <String>[];
  bool started = false, isMuted = false, isDeaf = false, isVideo = false;
  @override
  Future<void> start() async => started = true;
  @override
  Future<void> stop() async => started = false;
  @override
  set muted(bool on) => isMuted = on;
  @override
  set deafened(bool on) => isDeaf = on;
  @override
  Future<void> setVideo(bool on) async => isVideo = on;
  @override
  VoicePeer peer(String id, {required void Function(Map<String, dynamic> candidate) onCandidate}) => _Peer(this, id, onCandidate);
  @override
  void setPeerVolume(String id, double volume) {}
  @override
  void setPeerMuted(String id, bool muted) {}
}

class _Peer implements VoicePeer {
  _Peer(this.media, this.id, this.onCandidate);
  final _Media media;
  final String id;
  final void Function(Map<String, dynamic>) onCandidate;
  static const _opus = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=rtpmap:111 opus/48000/2\r\na=fmtp:111 minptime=10;useinbandfec=1\r\n';
  @override
  Future<String> makeOffer() async {
    media.log.add('offer to $id');
    onCandidate({'candidate': 'c-from-offerer'});
    return _opus;
  }

  @override
  Future<String> takeOffer(String sdp) async {
    media.log.add('answer $id${sdp.contains('maxaveragebitrate=510000') ? ' (510k)' : ''}');
    return _opus;
  }

  @override
  Future<void> takeAnswer(String sdp) async => media.log.add('took answer from $id${sdp.contains('stereo=1') ? ' (stereo)' : ''}');
  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) async => media.log.add('candidate from $id');
  @override
  Future<void> close() async => media.log.add('closed $id');
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a channel is made from its seed: the same room, token and key for every member; a group\'s from its id', () {
    final a = VoiceChannel.ofGroup('00112233445566778899aabbccddeeff', 'Climbing');
    final b = VoiceChannel.ofGroup('00112233445566778899aabbccddeeff', 'Climbing crew');
    expect(a.room, b.room);
    expect(a.token, b.token);
    expect(a.key, b.key);
    expect(a.room.length, 32);
    expect(a.token.length, 64);
    expect(VoiceChannel.ofGroup('ffeeddccbbaa99887766554433221100', 'x').room, isNot(a.room));
    final own = VoiceChannel.make('Hangout');
    expect(VoiceChannel.fromJson(own.toJson())!.room, own.room);
    expect(VoiceChannel.make('Hangout').room, isNot(own.room), reason: 'a new seed each time');
  });

  test('Opus is asked for at its highest: 510 kb/s, stereo, full band, constant, no silence cut', () {
    const sdp = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111 63\r\na=rtpmap:111 opus/48000/2\r\na=fmtp:111 minptime=10;useinbandfec=1\r\na=rtpmap:63 red/48000/2\r\n';
    final out = highestOpus(sdp);
    final fmtp = out.split('\r\n').firstWhere((l) => l.startsWith('a=fmtp:111'));
    for (final want in ['maxaveragebitrate=510000', 'stereo=1', 'sprop-stereo=1', 'maxplaybackrate=48000', 'cbr=1', 'usedtx=0', 'useinbandfec=1']) {
      expect(fmtp, contains(want));
    }
    expect(out, contains('a=rtpmap:63 red/48000/2'), reason: 'everything else left as it was');
    // Where Opus has no fmtp line, one is added.
    expect(highestOpus('m=audio 9 RTP 111\r\na=rtpmap:111 opus/48000/2\r\n'), contains('a=fmtp:111 '));
  });

  test('hopping in and out: whoever comes offers, those there answer, names and state go sealed, and leaving closes', () async {
    final hub = _Hub();
    final c = VoiceChannel.make('Hangout');
    final mayaMedia = _Media(), samMedia = _Media();
    final maya = VoiceSession(channel: c, route: _Route(hub, 'maya-id'), media: mayaMedia, name: 'Maya');
    final sam = VoiceSession(channel: c, route: _Route(hub, 'sam-id'), media: samMedia, name: 'Sam');

    await maya.join();
    expect(maya.members, isEmpty);
    expect(mayaMedia.started, isTrue);

    await sam.join(withVideo: true);
    await _settle();
    // Sam came in: Sam offers, Maya answers, at Opus's highest.
    expect(samMedia.log, contains('offer to maya-id'));
    expect(mayaMedia.log, contains('answer sam-id (510k)'));
    expect(samMedia.log, contains('took answer from maya-id (stereo)'));
    expect(mayaMedia.log, contains('candidate from sam-id'));
    expect(mayaMedia.log.where((l) => l.startsWith('offer')), isEmpty, reason: 'two never offer each other');
    // Each knows the other by the name they gave, and that Sam's video is on.
    expect(maya.members['sam-id']!.name, 'Sam');
    expect(maya.members['sam-id']!.video, isTrue);
    expect(sam.members['maya-id']!.name, 'Maya');
    expect(samMedia.isVideo, isTrue);

    // Muted, deafened, video: said to the others.
    maya.setMuted(true);
    await _settle();
    expect(mayaMedia.isMuted, isTrue);
    expect(sam.members['maya-id']!.muted, isTrue);
    sam.setDeafened(true);
    await _settle();
    expect(samMedia.isDeaf, isTrue);
    expect(samMedia.isMuted, isTrue, reason: 'deafened is muted too');
    expect(maya.members['sam-id']!.muted, isTrue);
    await sam.setVideo(false);
    await _settle();
    expect(maya.members['sam-id']!.video, isFalse);

    // Out again any time.
    await sam.leave();
    await _settle();
    expect(maya.members, isEmpty);
    expect(mayaMedia.log, contains('closed sam-id'));
    expect(samMedia.started, isFalse);
    await maya.leave();
  });

  test('what is said in a channel is sealed with its key: a member with another key hears nothing', () async {
    final hub = _Hub();
    final c = VoiceChannel.make('Hangout');
    final other = VoiceChannel.make('x');
    final a = VoiceSession(channel: c, route: _Route(hub, 'a'), media: _Media(), name: 'A');
    final b = VoiceSession(channel: other, route: _Route(hub, 'b'), media: _Media(), name: 'B');
    await a.join();
    // The same room on the stand-in hub, a different key: as someone who got into the room without the seed.
    hub.rooms[other.room] = hub.rooms[c.room]!;
    await b.join();
    await _settle();
    expect(a.members['b']?.name ?? '', isEmpty);
    await a.leave();
    await b.leave();
  });

  // tool/voicebench, 2026-11-15: at 1080p and 12 Mb/s for everyone, three members fell to a frame a second.
  test('the picture is sized by how many others are in the call: full 1080p one to one, smaller as it grows', () {
    expect(videoFor(1), (scale: 1.0, bitrate: 12000000, preference: 'balanced'));
    expect(videoFor(2).scale, 1.5);
    expect(videoFor(3).bitrate, 2000000);
    expect(videoFor(4).scale, 2.0);
    expect(videoFor(7).scale, 3.0);
    // What a member sends at most, all copies together, stays under 12 Mb/s however many there are.
    for (var others = 1; others <= 10; others++) {
      expect(videoFor(others).bitrate * others, lessThanOrEqualTo(12000000), reason: '$others others');
    }
  });

  // Matt, 2026-11-14: "Make the voice hangouts possible to share via a link so people can join to talk anonymously or
  // sign up through the browser similar to a zoom meeting". tool/voicebench/join_test.mjs checks the page makes the
  // same room and token from this link.
  test('a hangout\'s link: the seed and the name after the #, which no server is sent', () {
    const c = VoiceChannel(seed: '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff', name: 'Friday hang ✨');
    expect(c.link, 'https://gogho.st/join/#00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff.RnJpZGF5IGhhbmcg4pyo');
    expect(c.room, '42c94d6559e4ea774004c9c5aa93e907');
    expect(c.token, '6ad07432d21d71cd131266a87b30ac1c84a167e5eea281ccdcee5cca2963ad64');
    expect(Uri.parse(c.link).path, '/join/', reason: 'the path is all a server sees');
  });

  test('a member who joined from a browser with no username is a guest', () async {
    final hub = _Hub();
    final c = VoiceChannel.make('Hangout');
    final a = VoiceSession(channel: c, route: _Route(hub, 'a'), media: _Media(), name: 'A');
    await a.join();
    final guest = _Route(hub, 'g');
    await guest.join(c.room, c.token);
    guest.send(c.room, NetCrypto.seal(c.key, utf8.encode(jsonEncode({'t': 'me', 'n': 'Alex', 'g': true}))));
    await _settle();
    expect(a.members['g']!.guest, isTrue);
    expect(a.members['g']!.name, 'Alex');
    await a.leave();
  });

  test('a username goes with a member\'s name, so the others can add them as a friend', () async {
    final hub = _Hub();
    final c = VoiceChannel.make('Hangout');
    final a = VoiceSession(channel: c, route: _Route(hub, 'a'), media: _Media(), name: 'Maya', username: 'maya');
    final b = VoiceSession(channel: c, route: _Route(hub, 'b'), media: _Media(), name: 'Sam');
    await a.join();
    await b.join();
    await _settle();
    expect(b.members['a']!.username, 'maya');
    expect(a.members['b']!.username, isNull);
    await a.leave();
    await b.leave();
  });

  // Matt, 2026-11-15: "make sure voice chats are kept actively in sync between mobile and desktop clients".
  test('the phone answers its computer: every channel with its group, a name to go by; and keeps one the computer made', () async {
    final v = Voice.instance;
    final mine = VoiceChannel.make('Friday hang');
    v.own = [mine];
    addTearDown(() => v.own = []);
    final list = await v.answerDesk({'op': 'list'}) as Map;
    expect([for (final c in list['channels'] as List) (c as Map)['s']], [mine.seed]);
    expect(((list['channels'] as List).first as Map)['m'], 1);
    final made = VoiceChannel.make('From the Mac');
    await v.answerDesk({'op': 'add', 's': made.seed, 'n': made.name});
    expect(v.own.map((c) => c.seed), [mine.seed, made.seed]);
    await v.answerDesk({'op': 'add', 's': made.seed, 'n': made.name});
    expect(v.own, hasLength(2), reason: 'kept once');
    await v.answerDesk({'op': 'forget', 's': made.seed});
    expect(v.own.map((c) => c.seed), [mine.seed]);
  });

  // Matt, 2026-11-15: "Removing a hangout channel doesn't remove it for all devices".
  test('a channel removed on the phone stays removed: its computer is told, and cannot hand it back', () async {
    final v = Voice.instance;
    final hang = VoiceChannel.make('Friday hang');
    v.own = [hang];
    addTearDown(() => v.own = []);
    await v.forget(hang);
    expect(v.own, isEmpty);
    // The computer, which had it and had not heard, offers it to the phone again: refused.
    final back = await v.answerDesk({'op': 'add', 's': hang.seed, 'n': hang.name}) as Map;
    expect(back['gone'], isTrue);
    expect(v.own, isEmpty);
    // And the list the computer reads says it is gone, so the computer takes it away too.
    final list = await v.answerDesk({'op': 'list'}) as Map;
    expect(list['gone'], contains(hang.seed));
    expect([for (final c in list['channels'] as List) (c as Map)['s']], isNot(contains(hang.seed)));
    // Removed from the computer: the phone marks it gone as well.
    final other = VoiceChannel.make('From the Mac');
    await v.answerDesk({'op': 'add', 's': other.seed, 'n': other.name});
    await v.answerDesk({'op': 'forget', 's': other.seed});
    expect(v.removed(other.seed), isTrue);
    expect((await v.answerDesk({'op': 'add', 's': other.seed, 'n': other.name}) as Map)['gone'], isTrue);
  });
}
