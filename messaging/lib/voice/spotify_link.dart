/// A listener's connection to the music (lib/voice/spotify.dart): an ordinary one that only receives, to the DJ's
/// device, with a loudness of its own on this one. Beside the call's own connections and never among them: a recording,
/// captions and Scribe take the people's sounds (RtcMedia.sounds), and this is in none of them.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_sound.dart';
import 'rtc.dart';
import 'spotify_app.dart' show musicOpus;

/// What the session asks of a listener's connection: WebRTC's ([RtcMusicEar]), or a test's.
abstract class MusicEar {
  /// Takes the DJ's offer; this side's answer.
  Future<String> takeOffer(String sdp);
  Future<void> candidate(Map<String, dynamic> c);

  /// How loud, 0 to 1, and whether it is heard at all (deafened, it is not).
  void set({required double volume, required bool silent});

  /// The speaker chosen, where the page plays the sound itself (a browser).
  Future<void> output(String deviceId);
  Future<void> close();
}

/// Makes an ear: [servers] as the call has them, [relayOnly] as the DJ made their side, [onCandidate] told each way to
/// connect found here, and [onState] whether it is through (true), or lost for good (false).
typedef MakeEar = MusicEar Function({required List<Map<String, Object>> servers, required bool relayOnly, required void Function(Map<String, dynamic>) onCandidate, required void Function(bool up) onState});

class RtcMusicEar implements MusicEar {
  RtcMusicEar({required this.servers, required this.relayOnly, required this.onCandidate, required this.onState});
  final List<Map<String, Object>> servers;
  final bool relayOnly;
  final void Function(Map<String, dynamic>) onCandidate;
  final void Function(bool up) onState;

  static MusicEar make({required List<Map<String, Object>> servers, required bool relayOnly, required void Function(Map<String, dynamic>) onCandidate, required void Function(bool up) onState}) =>
      RtcMusicEar(servers: servers, relayOnly: relayOnly, onCandidate: onCandidate, onState: onState);

  /// Not through this long after it began, or lost for this long: given up on, and asked for again.
  static const connectWithin = Duration(seconds: 15), lostFor = Duration(seconds: 6);

  static const _who = 'ghost-music';
  Future<RTCPeerConnection>? _pc;
  final List<RTCIceCandidate> _early = [];
  final List<MediaStreamTrack> _tracks = [];
  bool _described = false, _closed = false;
  Timer? _patience;
  double _volume = 1;
  bool _silent = false;
  final CallSound _out = CallSound();

  Future<RTCPeerConnection> get _made => _pc ??= _make();

  Future<RTCPeerConnection> _make() async {
    final pc = await RtcMedia.make({'iceServers': servers, 'sdpSemantics': 'unified-plan', if (relayOnly) 'iceTransportPolicy': 'relay'});
    pc.onIceCandidate = (c) {
      if (c.candidate != null && !_closed) onCandidate({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    pc.onTrack = (e) {
      RtcMedia.note(pc, e.track);
      if (_closed || e.track.kind != 'audio') return;
      if (!_tracks.any((t) => t.id == e.track.id)) _tracks.add(e.track);
      _out.play(_who, e.track);
      _apply();
    };
    pc.onConnectionState = (s) {
      if (_closed) return;
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _patience?.cancel();
          onState(true);
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _wait(lostFor);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed || RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _lost();
        default:
      }
    };
    return pc;
  }

  void _wait(Duration most) {
    _patience?.cancel();
    _patience = Timer(most, _lost);
  }

  void _lost() {
    _patience?.cancel();
    if (!_closed) onState(false);
  }

  @override
  Future<String> takeOffer(String sdp) async {
    _wait(connectWithin);
    final pc = await _made;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    _described = true;
    for (final c in _early) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
    _early.clear();
    // Only ever listening: nothing of this device's is put in it.
    final answer = await pc.createAnswer();
    final mine = musicOpus(answer.sdp ?? '');
    await pc.setLocalDescription(RTCSessionDescription(mine, 'answer'));
    return mine;
  }

  @override
  Future<void> candidate(Map<String, dynamic> m) async {
    final c = RTCIceCandidate(m['candidate'] as String?, m['sdpMid'] as String?, (m['sdpMLineIndex'] as num?)?.toInt());
    if (!_described) {
      if (_early.length < 64) _early.add(c);
      return;
    }
    await (await _made).addCandidate(c);
  }

  @override
  void set({required double volume, required bool silent}) {
    _volume = volume;
    _silent = silent;
    _apply();
  }

  void _apply() {
    if (CallSound.playsItself) {
      _out.set(_who, volume: _volume, silent: _silent);
      return;
    }
    for (final t in _tracks) {
      t.enabled = !_silent;
      unawaited(Helper.setVolume(_volume, t).catchError((_) {}));
    }
  }

  @override
  Future<void> output(String deviceId) async {
    if (CallSound.playsItself) await _out.output(deviceId);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _patience?.cancel();
    _out.stopAll();
    final made = _pc;
    if (made == null) return;
    try {
      final pc = await made;
      await RtcMedia.closeConnection(pc);
      await pc.dispose();
    } catch (e) {
      debugPrint('spotify: music connection not closed: $e');
    }
  }
}
