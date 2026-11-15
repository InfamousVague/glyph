import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
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
}
