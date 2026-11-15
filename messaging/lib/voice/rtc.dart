import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'voice.dart';

/// The microphone, the camera and a WebRTC connection to each other member (lib/voice/voice.dart says what goes
/// between them and how).
///
/// Sound is taken at 48 kHz in stereo with automatic gain and noise suppression off, so what is sent is the
/// microphone as it is (echo cancellation stays on: without it a speaker feeds back into the call), and sent as Opus
/// at 510 kb/s. Each connection carries one sound and one picture both ways from its start; turning video on or off
/// puts the camera's picture in or takes it out, with nothing to work out again between the two.
class RtcMedia implements VoiceMedia {
  RtcMedia({this.iceServers = defaultIce});

  static const defaultIce = [
    {
      'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'],
    },
  ];
  final List<Map<String, Object>> iceServers;

  MediaStream? _mic;
  MediaStream? _cam;

  /// This device's camera while video is on, for its own tile.
  final ValueNotifier<MediaStream?> localVideo = ValueNotifier(null);

  /// What each other member sends, by their id.
  final ValueNotifier<Map<String, MediaStream>> remote = ValueNotifier(const {});
  final Map<String, _RtcPeer> _peers = {};
  bool _deaf = false;

  @override
  final ValueNotifier<Map<String, double>> levels = ValueNotifier(const {});
  Timer? _levelTimer;

  /// Reads how loud each sound is, several times a second (WebRTC's audioLevel: the incoming sound's at each
  /// connection, the microphone's at its media source), eased so a face does not flicker between words.
  Future<void> _readLevels() async {
    final next = <String, double>{};
    for (final e in _peers.entries) {
      final made = e.value._pc;
      if (made == null) continue;
      try {
        final pc = await made;
        for (final r in await pc.getStats()) {
          final v = r.values;
          if (r.type == 'inbound-rtp' && v['kind'] == 'audio' && v['audioLevel'] is num) next[e.key] = (v['audioLevel'] as num).toDouble();
          if (r.type == 'media-source' && v['kind'] == 'audio' && v['audioLevel'] is num) next['me'] = (v['audioLevel'] as num).toDouble();
        }
      } catch (_) {}
    }
    final was = levels.value;
    levels.value = {for (final k in {...was.keys, ...next.keys}) k: _ease(was[k] ?? 0, next[k] ?? 0)};
  }

  static double _ease(double from, double to) => to > from ? from + (to - from) * 0.6 : from + (to - from) * 0.25;

  static const audioBitrate = 510000;

  @override
  Future<void> start() async {
    _mic ??= await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': false,
        'autoGainControl': false,
        'channelCount': 2,
        'sampleRate': 48000,
      },
      'video': false,
    });
    if (!kIsWeb && Platform.isAndroid) await Helper.setSpeakerphoneOn(true);
    _levelTimer ??= Timer.periodic(const Duration(milliseconds: 150), (_) => _readLevels());
  }

  @override
  Future<void> stop() async {
    _levelTimer?.cancel();
    _levelTimer = null;
    levels.value = const {};
    for (final p in _peers.values.toList()) {
      await p.close();
    }
    _peers.clear();
    remote.value = const {};
    for (final s in [_mic, _cam]) {
      for (final t in s?.getTracks() ?? const <MediaStreamTrack>[]) {
        await t.stop();
      }
      await s?.dispose();
    }
    _mic = null;
    _cam = null;
    localVideo.value = null;
  }

  @override
  set muted(bool on) {
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !on;
    }
  }

  @override
  set deafened(bool on) {
    _deaf = on;
    for (final s in remote.value.values) {
      for (final t in s.getAudioTracks()) {
        t.enabled = !on;
      }
    }
  }

  MediaStreamTrack? get _camTrack => _cam?.getVideoTracks().firstOrNull;

  @override
  Future<void> setVideo(bool on) async {
    if (on && _cam == null) {
      _cam = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'width': 1920, 'height': 1080, 'frameRate': 30, 'facingMode': 'user'},
      });
      localVideo.value = _cam;
    } else if (!on && _cam != null) {
      final cam = _cam!;
      _cam = null;
      localVideo.value = null;
      for (final p in _peers.values) {
        await p.showCamera(null);
      }
      for (final t in cam.getTracks()) {
        await t.stop();
      }
      await cam.dispose();
      return;
    }
    for (final p in _peers.values) {
      await p.showCamera(_camTrack);
    }
  }

  @override
  VoicePeer peer(String id, {required void Function(Map<String, dynamic> candidate) onCandidate}) {
    final had = _peers[id];
    if (had != null) return had;
    final made = _peers[id] = _RtcPeer(this, id, onCandidate);
    _retune();
    return made;
  }

  /// Someone came or went: every copy of the picture is sized again for how many there are now.
  void _retune() {
    for (final p in _peers.values) {
      final made = p._pc;
      if (made != null) unawaited(made.then(p._highest).catchError((_) {}));
    }
  }

  void _heard(String id, MediaStream stream) {
    for (final t in stream.getAudioTracks()) {
      t.enabled = !_deaf;
    }
    remote.value = {...remote.value, id: stream};
  }

  void _gone(String id) {
    if (_peers.remove(id) != null) _retune();
    remote.value = {...remote.value}..remove(id);
  }
}

class _RtcPeer implements VoicePeer {
  _RtcPeer(this.media, this.id, this.onCandidate);
  final RtcMedia media;
  final String id;
  final void Function(Map<String, dynamic> candidate) onCandidate;
  Future<RTCPeerConnection>? _pc;
  final List<RTCIceCandidate> _early = [];
  bool _described = false;
  MediaStream? _stream;

  Future<RTCPeerConnection> get pc => _pc ??= _make();

  Future<RTCPeerConnection> _make() async {
    final pc = await createPeerConnection({'iceServers': media.iceServers, 'sdpSemantics': 'unified-plan'});
    pc.onIceCandidate = (c) {
      if (c.candidate != null) onCandidate({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    pc.onTrack = (e) async {
      var stream = e.streams.isNotEmpty ? e.streams.first : _stream;
      if (stream == null) {
        stream = await createLocalMediaStream('from-$id');
        await stream.addTrack(e.track);
      } else if (!stream.getTracks().any((t) => t.id == e.track.id)) {
        await stream.addTrack(e.track);
      }
      _stream = stream;
      media._heard(id, stream);
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed || s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) media._gone(id);
    };
    return pc;
  }

  /// One sound and one picture both ways, for the side that offers.
  Future<void> _addOwn(RTCPeerConnection pc) async {
    final mic = media._mic!.getAudioTracks().first;
    await pc.addTransceiver(track: mic, kind: RTCRtpMediaType.RTCRtpMediaTypeAudio, init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv, streams: [media._mic!]));
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv, sendEncodings: [RTCRtpEncoding(maxBitrate: videoFor(media._peers.length).bitrate, maxFramerate: 30, scaleResolutionDownBy: videoFor(media._peers.length).scale)]),
    );
    if (media._camTrack != null) await showCamera(media._camTrack);
  }

  /// The side that answers takes the offer's sound and picture, and puts its own in them.
  Future<void> _fillOwn(RTCPeerConnection pc) async {
    for (final t in await pc.getTransceivers()) {
      final kind = t.receiver.track?.kind;
      if (kind == 'audio') {
        await t.sender.replaceTrack(media._mic!.getAudioTracks().first);
        await t.setDirection(TransceiverDirection.SendRecv);
      } else if (kind == 'video') {
        await t.sender.replaceTrack(media._camTrack);
        await t.setDirection(TransceiverDirection.SendRecv);
      }
    }
  }

  /// Sound at 510 kb/s; the picture as big as the number of others allows ([videoFor]).
  Future<void> _highest(RTCPeerConnection pc) async {
    final v = videoFor(media._peers.length);
    for (final s in await pc.getSenders()) {
      final kind = s.track?.kind;
      final p = s.parameters;
      final encodings = p.encodings;
      if (encodings == null || encodings.isEmpty) continue;
      for (final e in encodings) {
        e.maxBitrate = kind == 'audio' ? RtcMedia.audioBitrate : v.bitrate;
        if (kind == 'video') e.scaleResolutionDownBy = v.scale;
      }
      if (kind == 'video') p.degradationPreference = RTCDegradationPreference.BALANCED;
      try {
        await s.setParameters(p);
      } catch (_) {}
    }
  }

  Future<void> showCamera(MediaStreamTrack? track) async {
    final c = await pc;
    for (final t in await c.getTransceivers()) {
      if (t.receiver.track?.kind == 'video' || t.sender.track?.kind == 'video') await t.sender.replaceTrack(track);
    }
    await _highest(c);
  }

  @override
  Future<String> makeOffer() async {
    final c = await pc;
    await _addOwn(c);
    final offer = await c.createOffer();
    final sdp = highestOpus(offer.sdp ?? '');
    await c.setLocalDescription(RTCSessionDescription(sdp, 'offer'));
    await _highest(c);
    return sdp;
  }

  @override
  Future<String> takeOffer(String sdp) async {
    final c = await pc;
    await c.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    await _settled(c);
    await _fillOwn(c);
    final answer = await c.createAnswer();
    final mine = highestOpus(answer.sdp ?? '');
    await c.setLocalDescription(RTCSessionDescription(mine, 'answer'));
    await _highest(c);
    return mine;
  }

  @override
  Future<void> takeAnswer(String sdp) async {
    final c = await pc;
    await c.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    await _settled(c);
  }

  Future<void> _settled(RTCPeerConnection c) async {
    _described = true;
    for (final cand in _early) {
      await c.addCandidate(cand);
    }
    _early.clear();
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> m) async {
    final cand = RTCIceCandidate(m['candidate'] as String?, m['sdpMid'] as String?, (m['sdpMLineIndex'] as num?)?.toInt());
    if (!_described) {
      _early.add(cand);
      return;
    }
    await (await pc).addCandidate(cand);
  }

  @override
  Future<void> close() async {
    final made = _pc;
    _pc = null;
    if (made != null) await (await made).close();
    await _stream?.dispose();
    media._gone(id);
  }
}
