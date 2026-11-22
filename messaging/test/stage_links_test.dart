import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/voice/voice.dart';

// A stage's connections (GMFB-29, from the Uplink gap review: "A stage/stream mode: some people speak, many listen, with
// a listener count"). In a call everyone connects to everyone; on a stage two who both listen have nothing to send each
// other, so they make no connection, and a stage holds many more listeners. Three devices on a stand-in relay: who
// offers to whom is read from each one's log.

class _Hub {
  final Map<String, List<_Route>> rooms = {};
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
    final r = hub.rooms[room] ??= [];
    final others = [for (final o in r) o.me];
    for (final o in r) {
      scheduleMicrotask(() => o._events.add(RoomEvent(room, came: me)));
    }
    r.add(this);
    return others;
  }

  @override
  void leave(String room) => hub.rooms[room]?.remove(this);
  @override
  void send(String room, Uint8List bytes) {
    for (final o in [...?hub.rooms[room]]) {
      if (!identical(o, this)) scheduleMicrotask(() => o._packets.add((room: room, from: me, bytes: bytes)));
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
  final offers = <String>[];
  final closed = <String>[];
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  set muted(bool on) {}
  @override
  set deafened(bool on) {}
  @override
  Future<void> setVideo(bool on) async {}
  @override
  VoicePeer peer(String id, {required void Function(Map<String, dynamic> candidate) onCandidate}) => _Peer(this, id);
  @override
  void setPeerVolume(String id, double volume) {}
  @override
  void setPeerMuted(String id, bool muted) {}
}

class _Peer implements VoicePeer {
  _Peer(this.media, this.id);
  final _Media media;
  final String id;
  static const _opus = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=rtpmap:111 opus/48000/2\r\n';
  @override
  Future<String> makeOffer() async {
    media.offers.add(id);
    return _opus;
  }

  @override
  Future<String> takeOffer(String sdp) async => _opus;
  @override
  Future<void> takeAnswer(String sdp) async {}
  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) async {}
  @override
  Future<void> close() async => media.closed.add(id);
}

Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('on a stage two listeners make no connection; brought up to speak, one connects to the rest', () async {
    final hub = _Hub();
    final c = VoiceChannel.make('Town hall');
    // Ids so the lower one is known: a1 (the speaker), b2 and c3 (listening).
    const host = 'a1', ann = 'b2', bob = 'c3';
    final listening = {ann, bob};
    bool listens(String id) => listening.contains(id);
    final media = {host: _Media(), ann: _Media(), bob: _Media()};
    VoiceSession session(String id) => VoiceSession(channel: c, route: _Route(hub, id), media: media[id]!, name: id)..listens = listens;
    final h = session(host), a = session(ann), b = session(bob);
    await h.join();
    await _settle();
    await a.join();
    await _settle();
    await b.join();
    await _settle();

    expect(media[ann]!.offers, [host], reason: 'Ann offers to the speaker alone');
    expect(media[bob]!.offers, [host], reason: 'Bob too, not to Ann: both listen');
    expect(b.members.keys, containsAll([host, ann]), reason: 'still in the call together');

    // A hand up, said to everyone.
    a.raiseHand(true);
    await _settle();
    expect(h.members[ann]!.hand, isTrue);

    // Ann brought up to speak: she and Bob now connect, the lower id offering, once.
    listening.remove(ann);
    a.raiseHand(false);
    for (final s in [h, a, b]) {
      s.relink();
    }
    await _settle();
    expect(media[ann]!.offers, [host, bob]);
    expect(media[bob]!.offers, [host], reason: 'Bob waits for the offer from the lower id');
    expect(h.members[ann]!.hand, isFalse);

    // Back to the audience: their connection goes.
    listening.add(ann);
    for (final s in [a, b]) {
      s.relink();
    }
    await _settle();
    expect(media[ann]!.closed, contains(bob));
    expect(media[bob]!.closed, contains(ann));
  });

  test('a call that is not a stage connects everyone as before', () async {
    final hub = _Hub();
    final c = VoiceChannel.make('Friday hang');
    final media = {'a1': _Media(), 'b2': _Media(), 'c3': _Media()};
    for (final id in ['a1', 'b2', 'c3']) {
      await VoiceSession(channel: c, route: _Route(hub, id), media: media[id]!, name: id).join();
      await _settle();
    }
    expect(media['c3']!.offers, ['a1', 'b2']);
  });
}
