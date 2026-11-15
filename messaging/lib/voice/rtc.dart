import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'voice.dart';
import 'voice_fx.dart';
import 'voice_settings.dart';

/// The microphone, the camera and a WebRTC connection to each other member (lib/voice/voice.dart says what goes
/// between them and how).
///
/// Sound is taken at 48 kHz in stereo with automatic gain and noise suppression off, so what is sent is the
/// microphone as it is (echo cancellation stays on: without it a speaker feeds back into the call), and sent as Opus
/// at 510 kb/s. Each connection carries one sound and one picture both ways from its start; turning video on or off
/// puts the camera's picture in or takes it out, with nothing to work out again between the two.
class RtcMedia implements VoiceMedia {
  RtcMedia({this.iceServers = defaultIce, this.settings = const VoiceSettings()});

  /// The devices, Opus and processing, and the picture's quality, as Settings › Voice has them.
  VoiceSettings settings;

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
  final Map<String, double> _volume = {};
  final Set<String> _silenced = {};

  /// Each one's sound as this device plays it: silenced (deafened, or that one muted here) or at their volume.
  void _apply(String id, MediaStream stream) {
    for (final t in stream.getAudioTracks()) {
      t.enabled = !_deaf && !_silenced.contains(id);
      // Each person's own volume times the output volume (Settings › Voice and video), boosted to twice at most.
      final v = ((_volume[id] ?? 1.0) * settings.outputVolume / 100).clamp(0.0, 4.0);
      unawaited(Helper.setVolume(v, t).catchError((_) {}));
    }
  }

  @override
  void setPeerVolume(String id, double volume) {
    _volume[id] = volume.clamp(0.0, 2.0);
    final s = remote.value[id];
    if (s != null) _apply(id, s);
  }

  @override
  void setPeerMuted(String id, bool muted) {
    muted ? _silenced.add(id) : _silenced.remove(id);
    final s = remote.value[id];
    if (s != null) _apply(id, s);
  }

  @override
  final ValueNotifier<Map<String, double>> levels = ValueNotifier(const {});
  Timer? _levelTimer;

  /// A connection that holds the microphone and never connects: what this device's own level is read from, alone in a
  /// call or with others (Matt, 2026-11-15: "on desktop it doesn't seem like when i'm talking i see the wobbles coming
  /// from my voice chat"). It was read from the connections to the others alone, so alone in a call, and wherever
  /// those had not yet said it, the face had nothing to ripple with.
  RTCPeerConnection? _meter;
  double? _energy, _energyTime;

  /// How loud the microphone is from a media source's numbers: its own level where it gives one, else from the
  /// energy it has heard over the time it has heard it (the two WebRTC keeps; the Mac's has given the second only).
  double? _micLevel(Map<dynamic, dynamic> v) {
    if (v['audioLevel'] is num) return (v['audioLevel'] as num).toDouble();
    final e = v['totalAudioEnergy'], d = v['totalSamplesDuration'];
    if (e is! num || d is! num) return null;
    final was = _energy, wasTime = _energyTime;
    _energy = e.toDouble();
    _energyTime = d.toDouble();
    if (was == null || wasTime == null || _energyTime! <= wasTime) return null;
    return math.sqrt(((_energy! - was) / (_energyTime! - wasTime)).clamp(0.0, 1.0));
  }

  /// Reads how loud each sound is, several times a second (WebRTC's audioLevel: the incoming sound's at each
  /// connection, the microphone's at its media source), eased so a face does not flicker between words.
  Future<void> _readLevels() async {
    final next = <String, double>{};
    final meter = _meter;
    if (meter != null) {
      try {
        for (final r in await meter.getStats()) {
          if ((r.type == 'media-source' || r.type == 'track') && r.values['kind'] == 'audio' && r.values['remoteSource'] != true) {
            final l = _micLevel(r.values);
            if (l != null) next['me'] = l;
          }
        }
      } catch (_) {}
    }
    for (final e in _peers.entries) {
      final made = e.value._pc;
      if (made == null) continue;
      try {
        final pc = await made;
        for (final r in await pc.getStats()) {
          final v = r.values;
          if (r.type == 'inbound-rtp' && v['kind'] == 'audio' && v['audioLevel'] is num) next[e.key] = (v['audioLevel'] as num).toDouble();
          if (r.type == 'media-source' && v['kind'] == 'audio' && v['audioLevel'] is num && !next.containsKey('me')) next['me'] = (v['audioLevel'] as num).toDouble();
        }
      } catch (_) {}
    }
    final was = levels.value;
    levels.value = {for (final k in {...was.keys, ...next.keys}) k: _ease(was[k] ?? 0, next[k] ?? 0)};
  }

  static double _ease(double from, double to) => to > from ? from + (to - from) * 0.6 : from + (to - from) * 0.25;

  int get audioBitrate => settings.sendKbps * 1000;

  /// Stands in for the system's list of devices (a test, with no WebRTC underneath).
  @visibleForTesting
  static Future<List<MediaDeviceInfo>> Function()? enumerate;

  Map<String, Object> get _audioAsked => {
        if (settings.input.isNotEmpty) 'deviceId': settings.input,
        'echoCancellation': settings.useEcho,
        // WebRTC's own only where it is the one used: RNNoise and DeepFilterNet run after capture (VoiceFx).
        'noiseSuppression': settings.noiseOn(VoiceFx.available) == NoiseMode.webrtc,
        'autoGainControl': settings.useGain,
        // Music mode keeps the high-pass filter off too: the microphone as it is.
        if (settings.music) 'googHighpassFilter': false,
        'channelCount': settings.sendStereo ? 2 : 1,
        'sampleRate': 48000,
      };

  /// The devices there are of [kind] (`audioinput`, `audiooutput`), by the system's names for them.
  static Future<List<MediaDeviceInfo>> devices(String kind) async {
    try {
      final all = await (enumerate ?? navigator.mediaDevices.enumerateDevices)();
      return [for (final d in all) if (d.kind == kind) d];
    } catch (_) {
      return const [];
    }
  }

  /// Takes sound from another microphone, in the call as it goes: the new one's track in every connection's place.
  Future<void> setInput(String deviceId) async {
    settings = settings.copyWith(input: deviceId);
    final old = _mic;
    if (old == null) return;
    final fresh = await navigator.mediaDevices.getUserMedia({'audio': _audioAsked, 'video': false});
    final track = fresh.getAudioTracks().first;
    track.enabled = old.getAudioTracks().firstOrNull?.enabled ?? true;
    _mic = fresh;
    for (final p in _peers.values) {
      final made = p._pc;
      if (made == null) continue;
      for (final s in await (await made).getSenders()) {
        if (s.track?.kind == 'audio') await s.replaceTrack(track);
      }
    }
    final meter = _meter;
    if (meter != null) {
      for (final s in await meter.getSenders()) {
        if (s.track?.kind == 'audio') await s.replaceTrack(track);
      }
    }
    for (final t in old.getTracks()) {
      await t.stop();
    }
    await old.dispose();
  }

  /// Plays the call through another speaker or headset.
  Future<void> setOutput(String deviceId) async {
    settings = settings.copyWith(output: deviceId);
    if (deviceId.isNotEmpty) await Helper.selectAudioOutput(deviceId).catchError((_) {});
  }

  @override
  Future<void> start() async {
    // The native processing first: what it can run decides whether WebRTC's own noise suppression is asked for.
    await VoiceFx.apply(settings);
    _mic ??= await navigator.mediaDevices.getUserMedia({'audio': _audioAsked, 'video': false});
    // And again with the microphone open: the native hook is there only once WebRTC is (android VoiceFx.kt).
    unawaited(VoiceFx.apply(settings));
    if (settings.output.isNotEmpty) {
      await Helper.selectAudioOutput(settings.output).catchError((_) {});
    } else if (!kIsWeb && Platform.isAndroid) {
      await Helper.setSpeakerphoneOn(true);
    }
    if (_meter == null) {
      try {
        final meter = await createPeerConnection({'iceServers': <Map<String, Object>>[], 'sdpSemantics': 'unified-plan'});
        await meter.addTransceiver(track: _mic!.getAudioTracks().first, kind: RTCRtpMediaType.RTCRtpMediaTypeAudio, init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly, streams: [_mic!]));
        _meter = meter;
      } catch (_) {}
    }
    _levelTimer ??= Timer.periodic(const Duration(milliseconds: 150), (_) => _readLevels());
  }

  @override
  Future<void> stop() async {
    _levelTimer?.cancel();
    _levelTimer = null;
    levels.value = const {};
    await _meter?.close();
    _meter = null;
    _energy = _energyTime = null;
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
    for (final e in remote.value.entries) {
      _apply(e.key, e.value);
    }
  }

  /// Settings changed while in the call: how loud others are and the microphone's processing at once; the rest
  /// from the next call.
  Future<void> applyLive(VoiceSettings fresh) async {
    settings = fresh.copyWith(input: settings.input, output: settings.output);
    for (final e in remote.value.entries) {
      _apply(e.key, e.value);
    }
    await VoiceFx.apply(settings);
  }

  MediaStreamTrack? get _camTrack => _cam?.getVideoTracks().firstOrNull;

  @override
  Future<void> setVideo(bool on) async {
    if (on && _cam == null) {
      _cam = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'width': settings.videoSize.width, 'height': settings.videoSize.height, 'frameRate': 30, 'facingMode': 'user'},
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
    _apply(id, stream);
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
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv, sendEncodings: [RTCRtpEncoding(maxBitrate: media.settings.sendTo(media._peers.length, videoFor(media._peers.length)).bitrate, maxFramerate: 30, scaleResolutionDownBy: media.settings.sendTo(media._peers.length, videoFor(media._peers.length)).scale)]),
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
    final v = media.settings.sendTo(media._peers.length, videoFor(media._peers.length));
    for (final s in await pc.getSenders()) {
      final kind = s.track?.kind;
      final p = s.parameters;
      final encodings = p.encodings;
      if (encodings == null || encodings.isEmpty) continue;
      for (final e in encodings) {
        e.maxBitrate = kind == 'audio' ? media.audioBitrate : v.bitrate;
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
    final sdp = highestOpus(offer.sdp ?? '', kbps: media.settings.sendKbps, stereo: media.settings.sendStereo);
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
    final mine = highestOpus(answer.sdp ?? '', kbps: media.settings.sendKbps, stereo: media.settings.sendStereo);
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
