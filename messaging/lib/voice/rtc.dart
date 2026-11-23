import 'dart:async';
import 'dart:math' as math;
import '../platform_info.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'voice.dart';
import 'voice_fx.dart';
import 'voice_settings.dart';

/// The microphone, the camera and a WebRTC connection to each other member (lib/voice/voice.dart says what goes
/// between them and how).
///
/// Sound is taken at 48 kHz, in stereo or mono, with echo cancellation, automatic gain and noise suppression each as
/// Settings › Voice has it ([_audioAsked]), and sent as Opus at the rate chosen there, 510 kb/s unless changed.
/// Each connection carries one sound and one picture both ways from its start; turning video on or off
/// puts the camera's picture in or takes it out, with nothing to work out again between the two.
class RtcMedia implements VoiceMedia, FallbackMedia, ScreenMedia, LinkedMedia {
  RtcMedia({this.relay, this.settings = const VoiceSettings(), this.light = false});

  /// Settings' microphone test, made light where the native half can say how loud the microphone is (the Mac's,
  /// VoiceFx.level): the microphone is started by itself, off the main thread, and no meter is made, unless the test
  /// is to be heard (GMFB-20, Matt, Mac 0.12.5: "it's laggy and shows the pinwheel when starting a microphone test in
  /// settings"). The meter is two connections to each other, and on the Mac flutter_webrtc makes, negotiates and
  /// closes them on the main thread, each step waiting while WebRTC starts or stops the sound device.
  final bool light;

  /// The microphone recording by itself ([light]), with no connection sending it.
  bool _local = false;

  /// The devices, Opus and processing, and the picture's quality, as Settings › Voice has them.
  VoiceSettings settings;

  /// The servers a connection asks for its own public address where no others are given: public STUN only, no relay.
  static const defaultIce = [
    {
      'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'],
    },
  ];

  /// The relay's TURN server for calls as the hub last handed it out with a room joined (relay/lib/turn.dart,
  /// HubCarrier.callRelay), asked for as each connection is made; null or none: direct only.
  final Map<String, Object>? Function()? relay;

  /// Where a connection looks for a way through: the public STUN servers, and the relay where there is one. WebRTC
  /// tries them all at once and takes the best that works, so a call goes direct wherever it can and through the
  /// relay only where it can't.
  List<Map<String, Object>> get iceServers => [...defaultIce, ?relay?.call()];

  @override
  bool get hasRelay => relay?.call() != null;

  MediaStream? _mic;
  MediaStream? _cam;

  /// The screen or window this device is sharing (GMFB-27): sent in the camera's place while there is one.
  MediaStream? _screen;

  @override
  final ValueNotifier<MediaStream?> localScreen = ValueNotifier(null);

  /// Said before a phone's screen is captured and after it stops: the call's service takes on, or drops, the media
  /// projection kind Android 14 asks for (lib/voice/channels.dart).
  Future<void> Function(bool sharing)? screenService;

  /// How tall the shared screen is, where WebRTC says: it is sent at 1080 lines at most.
  double? _screenHeight;

  /// This device's camera while video is on, for its own tile.
  final ValueNotifier<MediaStream?> localVideo = ValueNotifier(null);

  /// Each other member's picture, by their id: a stream made on this device holding the video track their connection
  /// receives, for their tile ([_RtcPeer._took]).
  final ValueNotifier<Map<String, MediaStream>> remote = ValueNotifier(const {});
  final Map<String, _RtcPeer> _peers = {};
  bool _deaf = false;

  // This device's own choices for each other member: how loud they are played (0 to 2) and who is silenced here.
  final Map<String, double> _volume = {};
  final Set<String> _silenced = {};

  /// Each one's sound as this device plays it: silenced (deafened, or that one muted here) or at their volume.
  void _apply(String id) {
    for (final t in _peers[id]?._sounds ?? const <MediaStreamTrack>[]) {
      t.enabled = !_deaf && !_silenced.contains(id);
      // Each person's own volume times the output volume (Settings › Voice and video), boosted to twice at most, and
      // times the auto leveler's gain for them where it is on (leveler.dart).
      final v = ((_volume[id] ?? 1.0) * settings.outputVolume / 100 * (_leveled[id] ?? 1.0)).clamp(0.0, 6.0);
      unawaited(Helper.setVolume(v, t).catchError((_) {}));
    }
  }

  /// The auto leveler's gain for each person (leveler.dart): 1 is as they arrive.
  final Map<String, double> _leveled = {};

  /// Sets it for [id], held between a quarter and three and a half times; 1 takes it away.
  void setLevelGain(String id, double gain) {
    if (gain == 1) {
      if (_leveled.remove(id) == null) return;
    } else {
      _leveled[id] = gain.clamp(0.25, 3.5);
    }
    _apply(id);
  }

  @override
  void setPeerVolume(String id, double volume) {
    _volume[id] = volume.clamp(0.0, 2.0);
    _apply(id);
  }

  @override
  void setPeerMuted(String id, bool muted) {
    muted ? _silenced.add(id) : _silenced.remove(id);
    _apply(id);
  }

  @override
  final ValueNotifier<Map<String, double>> levels = ValueNotifier(const {});

  /// How this device's connection to each person stands, by their id ([PeerLink]): drawn on their face and row.
  final ValueNotifier<Map<String, PeerLink>> links = ValueNotifier(const {});

  /// Sets how the connection to [id] stands; null takes them out of [links].
  void _link(String id, PeerLink? to) {
    final now = links.value;
    if (now[id] == to) return;
    links.value = to == null ? ({...now}..remove(id)) : {...now, id: to};
  }
  Timer? _levelTimer;

  /// A connection that holds the microphone and never connects: what this device's own level is read from, alone in a
  /// call or with others (Matt, 2026-11-15: "on desktop it doesn't seem like when i'm talking i see the wobbles coming
  /// from my voice chat"). It was read from the connections to the others alone, so alone in a call, and wherever
  /// those had not yet said it, the face had nothing to ripple with.
  RTCPeerConnection? _meter;

  /// The meter's other end, on this device: the meter is connected to it, so the microphone is really sending even
  /// with nobody else in the call (Matt, 2026-11-16: "make it so that even when we're in the call alone we see the
  /// voice activity of ourselves"). A sender that never connects is never started on Android's and the Mac's WebRTC,
  /// and gave no level at all. What arrives here is silenced: nobody hears themselves.
  RTCPeerConnection? _meterSink;

  /// The microphone's total energy and the seconds it covers, as last read: a level is worked out from how much each
  /// grew ([_micLevel]).
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
    // One reading at a time: when the app is busy (an upload sealing beside the call), readings that overlapped piled
    // up getStats on the platform channel and made it busier still (GMFB-6).
    if (_reading) return;
    _reading = true;
    try {
      await _readLevelsOnce();
    } finally {
      _reading = false;
    }
  }

  bool _reading = false;

  /// Connected, or poor where a word takes longer than [poorAfter] there and back.
  static const poorAfter = 0.4;
  @visibleForTesting
  static PeerLink linkFor(double roundTrip) => roundTrip > poorAfter ? PeerLink.poor : PeerLink.connected;

  /// One reading: this device's own level, then each connection's, into [levels].
  Future<void> _readLevelsOnce() async {
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
    // A light test with nothing to be heard: the native half says how loud the microphone is ([light]).
    if (_local && meter == null) next['me'] = await VoiceFx.level();
    // The meter while alone, not with others (_openMeter, _closeMeter); a light test has one only to be heard.
    if (_peers.isEmpty && _meter == null && !_opening && (!_local || hearMyself)) {
      unawaited(_openMeter());
    } else if (_peers.isNotEmpty && _meter != null) {
      unawaited(_closeMeter());
    }
    // What reaches the meter's other end is never heard: held to silence at every reading, not trusted to one event
    // (Matt, 2026-11-16: "I can hear myself also if I mute and unmute in a space": on the phone the track was played).
    unawaited(_silenceSink());
    // Where the sender says nothing, the level of what reached the meter's other end.
    final sink = _meterSink;
    if (sink != null && !next.containsKey('me')) {
      try {
        for (final r in await sink.getStats()) {
          final v = r.values;
          if (r.type == 'inbound-rtp' && v['kind'] == 'audio' && v['audioLevel'] is num) next['me'] = (v['audioLevel'] as num).toDouble();
        }
      } catch (_) {}
    }
    // Muted, this device is not talking, whatever the microphone still hears.
    if (_mic?.getAudioTracks().any((t) => t.enabled) == false) next['me'] = 0;
    for (final e in _peers.entries.toList()) {
      final made = e.value._pc;
      if (made == null) continue;
      try {
        final pc = await made;
        double? rtt;
        for (final r in await pc.getStats()) {
          final v = r.values;
          // How long a word takes there and back, on the way in use (GMFB-4): over 400 ms a call is hard to talk on.
          if (r.type == 'candidate-pair' && (v['nominated'] == true || v['state'] == 'succeeded') && v['currentRoundTripTime'] is num) {
            rtt = math.max(rtt ?? 0, (v['currentRoundTripTime'] as num).toDouble());
          }
          if (r.type == 'inbound-rtp' && v['kind'] == 'audio' && v['audioLevel'] is num) next[e.key] = (v['audioLevel'] as num).toDouble();
          if (r.type == 'media-source' && v['kind'] == 'audio' && v['audioLevel'] is num && !next.containsKey('me')) next['me'] = (v['audioLevel'] as num).toDouble();
        }
        final link = links.value[e.key];
        if (rtt != null && (link == PeerLink.connected || link == PeerLink.poor)) _link(e.key, linkFor(rtt));
      } catch (_) {}
    }
    final was = levels.value;
    final eased = {for (final k in {...was.keys, ...next.keys}) k: _ease(was[k] ?? 0, next[k] ?? 0)};
    // Told only when a face would move: a new map each reading had every listener rebuild seven times a second while
    // nobody spoke (GMFB-6).
    final moved = eased.length != was.length || eased.entries.any((e) => ((was[e.key] ?? -1) - e.value).abs() > 0.01);
    if (moved) levels.value = eased;
  }

  /// The meter is being opened: a second reading in the meantime doesn't open another.
  bool _opening = false;

  /// What the ids of the meter partner's copy of the microphone start with ([_openMeter]).
  static const meterPrefix = 'ghost-meter-';

  /// [sdp] (the meter's offer) with the microphone's track and stream ids given the meter's own prefix, so the
  /// partner's copy is a track of its own to flutter_webrtc and switching it off never touches the microphone.
  @visibleForTesting
  static String meterApart(String sdp, {required String trackId, required String streamId}) =>
      sdp.replaceAll(trackId, '$meterPrefix$trackId').replaceAll(streamId, '$meterPrefix$streamId');

  /// Opens the meter and its silent partner, for this device's own level while it is alone in the call.
  Future<void> _openMeter() async {
    final mic = _mic;
    if (_meter != null || _opening || mic == null) return;
    _opening = true;
    try {
      final config = {'iceServers': <Map<String, Object>>[], 'sdpSemantics': 'unified-plan'};
      final meter = await createPeerConnection(config);
      final sink = await createPeerConnection(config);
      // Connected on this device alone: each end's ways to connect handed straight to the other.
      meter.onIceCandidate = (c) {
        if (c.candidate != null) unawaited(sink.addCandidate(c).catchError((_) {}));
      };
      sink.onIceCandidate = (c) {
        if (c.candidate != null) unawaited(meter.addCandidate(c).catchError((_) {}));
      };
      // What arrives is never played.
      sink.onTrack = (_) => unawaited(_silenceSink());
      await meter.addTransceiver(
        track: mic.getAudioTracks().first,
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        // Low: only its level is wanted.
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly, streams: [mic], sendEncodings: [RTCRtpEncoding(maxBitrate: 16000)]),
      );
      final offer = await meter.createOffer();
      await meter.setLocalDescription(offer);
      // The partner's copy of the microphone gets ids of its own. flutter_webrtc finds a track by its id, looking at
      // this device's own tracks first, so under the microphone's id "switch off the partner's copy" switched off
      // the microphone itself, and the copy was played (Matt, 2026-11-16: "I can hear myself also if I mute and
      // unmute in a space"; "I cant hear the other person that joined the space"). With no ids to change, no meter.
      final micTrack = mic.getAudioTracks().first;
      final trackId = micTrack.id;
      final sdp = offer.sdp ?? '';
      if (trackId == null || trackId.isEmpty || !sdp.contains(trackId)) {
        await meter.close();
        await sink.close();
        _opening = false;
        return;
      }
      final apart = meterApart(sdp, trackId: trackId, streamId: mic.id);
      await sink.setRemoteDescription(RTCSessionDescription(apart, offer.type));
      final answer = await sink.createAnswer();
      await sink.setLocalDescription(answer);
      await meter.setRemoteDescription(answer);
      _meterSink = sink;
      await _silenceSink();
      _meter = meter;
    } catch (_) {}
    _opening = false;
  }

  /// Closes the meter once someone else is in the call: their connections measure the microphone from then on, and
  /// nothing of this device's own sound is looped back while anyone is listening.
  Future<void> _closeMeter() async {
    final meter = _meter, sink = _meterSink;
    _meter = null;
    _meterSink = null;
    _energy = null;
    _energyTime = null;
    await meter?.close();
    await sink?.close();
  }

  /// Switches off every track the meter's other end receives and turns it to nothing, so this device never plays its
  /// own microphone back. Asked again and again (every reading), since on some phones a receiver's track is made, or
  /// made again, without the event that announces it.
  Future<void> _silenceSink() async {
    final sink = _meterSink;
    if (sink == null) return;
    // The audio test alone, never a call: the copy played back through the speaker chosen ([hearMyself]).
    final hear = hearMyself && _peers.isEmpty;
    try {
      for (final r in await sink.getReceivers()) {
        final track = r.track;
        // Only the partner's own copy, by the ids given it: never the microphone.
        if (track == null || track.kind != 'audio' || !(track.id ?? '').startsWith(meterPrefix)) continue;
        if (track.enabled != hear) track.enabled = hear;
        await Helper.setVolume(hear ? 1 : 0, track).catchError((_) {});
      }
    } catch (_) {}
  }

  /// Settings' audio test (GMFB-2, @kevin: "When testing voice calls it is difficult to diagnose issues without an in
  /// app audio device test"): the microphone played back through the speaker chosen, so both are heard as a call
  /// would use them. Only ever while nobody else is connected; a call's sink stays silent whatever this says.
  bool hearMyself = false;

  static double _ease(double from, double to) => to > from ? from + (to - from) * 0.6 : from + (to - from) * 0.25;

  /// The most sound is sent at, in bits a second, as the settings ask.
  int get audioBitrate => settings.sendKbps * 1000;

  /// Stands in for the system's list of devices (a test, with no WebRTC underneath).
  @visibleForTesting
  static Future<List<MediaDeviceInfo>> Function()? enumerate;

  /// Windows' WebRTC (flutter_webrtc's common/cpp) takes the microphone from `optional: [{sourceId}]` and reads
  /// `deviceId` as the speaker; the Mac's and the phones' take `deviceId` as the microphone. Asked as `deviceId` on
  /// Windows, every choice of microphone was the system's first (Matt, 2026-11-21: "the device picker is not working
  /// in windows").
  static bool get _sourceIds => !kIsWeb && (PlatformInfo.isWindows || PlatformInfo.isLinux);

  Map<String, Object> get _audioAsked => {
        if (settings.input.isNotEmpty && !_sourceIds) 'deviceId': settings.input,
        if (settings.input.isNotEmpty && _sourceIds)
          'optional': [
            {'sourceId': settings.input},
          ],
        if (settings.output.isNotEmpty && _sourceIds) 'deviceId': settings.output,
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
    // The computers' audio device modules hold one microphone for every track: chosen there too, in case a new
    // track's constraint is not read.
    if (deviceId.isNotEmpty && !kIsWeb && (PlatformInfo.isMacOS || PlatformInfo.isWindows || PlatformInfo.isLinux)) {
      await Helper.selectAudioInput(deviceId).catchError((_) {});
    }
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
    } else if (!kIsWeb && PlatformInfo.isAndroid) {
      await Helper.setSpeakerphoneOn(true);
    }
    // A light test: the microphone by itself, measured by the native half ([light]).
    if (light && _peers.isEmpty && VoiceFx.levelSupported) {
      try {
        await NativeAudioManagement.startLocalRecording();
        _local = true;
      } catch (_) {
        _local = false;
      }
    }
    // Alone, the microphone is measured through the meter (_openMeter); with others, through their connections.
    if (_peers.isEmpty && !_local) await _openMeter();
    _levelTimer ??= Timer.periodic(const Duration(milliseconds: 150), (_) => _readLevels());
  }

  @override
  Future<void> stop() async {
    _levelTimer?.cancel();
    _levelTimer = null;
    if (_local) {
      _local = false;
      await NativeAudioManagement.stopLocalRecording().catchError((_) {});
    }
    levels.value = const {};
    links.value = const {};
    await _meter?.close();
    _meter = null;
    await _meterSink?.close();
    _meterSink = null;
    _energy = _energyTime = null;
    for (final p in _peers.values.toList()) {
      await p.close();
    }
    _peers.clear();
    remote.value = const {};
    for (final s in [_mic, _cam, _screen]) {
      for (final t in s?.getTracks() ?? const <MediaStreamTrack>[]) {
        await t.stop();
      }
      await s?.dispose();
    }
    _mic = null;
    _cam = null;
    localVideo.value = null;
    if (_screen != null && !kIsWeb && PlatformInfo.isAndroid) unawaited(screenService?.call(false));
    _screen = null;
    _screenHeight = null;
    localScreen.value = null;
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
    _peers.keys.forEach(_apply);
  }

  /// Settings changed while in the call: how loud others are and the microphone's processing at once; the rest
  /// from the next call.
  Future<void> applyLive(VoiceSettings fresh) async {
    settings = fresh.copyWith(input: settings.input, output: settings.output);
    _peers.keys.forEach(_apply);
    await VoiceFx.apply(settings);
  }

  MediaStreamTrack? get _camTrack => _cam?.getVideoTracks().firstOrNull;

  /// What this device's picture is now: the screen while it is shared, else the camera while it is on.
  MediaStreamTrack? get _picture => _screen?.getVideoTracks().firstOrNull ?? _camTrack;

  /// Shown the screen of whoever shares it, sent at 1080 lines at most, holding its sharpness over its frame rate:
  /// words on a screen matter more than smooth movement.
  bool get sharing => _screen != null;

  /// A shared screen's bitrate: what the camera would get with this many in the call, but never under 2.5 Mb/s, as
  /// small words blur first.
  @visibleForTesting
  static int screenBitrate(int camera) => math.max(camera, 2500000);

  /// How much a shared screen [height] lines tall is scaled down: to 1080 lines at most, never up.
  @visibleForTesting
  static double screenScale(double? height) => height == null || height <= 1080 ? 1.0 : height / 1080;

  @override
  bool get screenSupported => !kIsWeb && (PlatformInfo.isAndroid || PlatformInfo.isMacOS || PlatformInfo.isWindows || PlatformInfo.isLinux);

  @override
  Future<List<ScreenSource>> screenSources() async {
    if (kIsWeb || PlatformInfo.isAndroid || PlatformInfo.isIOS) return const [];
    // The Mac asks for Screen Recording once (System Settings › Privacy); without it every picture is blank.
    if (PlatformInfo.isMacOS) await Helper.requestCapturePermission().catchError((_) => false);
    try {
      final found = await desktopCapturer.getSources(types: [SourceType.Screen, SourceType.Window], thumbnailSize: ThumbnailSize(320, 200));
      return [
        for (final s in found)
          ScreenSource(id: s.id, name: s.name.isEmpty ? (s.type == SourceType.Screen ? 'Screen' : 'Window') : s.name, window: s.type == SourceType.Window, thumbnail: s.thumbnail),
      ];
    } catch (e) {
      debugPrint('rtc: no screens to share: $e');
      return const [];
    }
  }

  @override
  Future<bool> setScreen(bool on, {String? source, void Function()? onEnded}) async {
    if (!on) {
      await _stopScreen();
      return true;
    }
    if (!screenSupported) return false;
    MediaStream stream;
    try {
      if (PlatformInfo.isAndroid) {
        // The system's question first, then the service, then the capture (CallService.kt says why).
        final yes = await Helper.requestCapturePermission();
        if (!yes) return false;
        await screenService?.call(true);
        stream = await navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': false});
      } else {
        if (source == null) return false;
        stream = await navigator.mediaDevices.getDisplayMedia({
          'video': {
            'deviceId': {'exact': source},
            'mandatory': {'frameRate': 30.0},
          },
          'audio': false,
        });
      }
    } catch (e) {
      debugPrint('rtc: the screen was not shared: $e');
      if (PlatformInfo.isAndroid) await screenService?.call(false);
      return false;
    }
    final track = stream.getVideoTracks().firstOrNull;
    if (track == null) {
      await stream.dispose();
      if (PlatformInfo.isAndroid) await screenService?.call(false);
      return false;
    }
    // Another share in this one's place: the old one goes.
    final old = _screen;
    _screen = stream;
    localScreen.value = stream;
    _screenHeight = null;
    try {
      final h = track.getSettings()['height'];
      if (h is num && h > 0) _screenHeight = h.toDouble();
    } catch (_) {}
    // Ended from outside the app (the system's own "Stop sharing", the shared window closed): stopped here too.
    track.onEnded = () {
      if (!identical(_screen, stream)) return;
      unawaited(_stopScreen().then((_) => onEnded?.call()));
    };
    for (final p in _peers.values) {
      await p.showCamera(_picture);
    }
    if (old != null) await _dispose(old);
    return true;
  }

  /// Stops sharing the screen and lets its capture go.
  Future<void> _stopScreen() async {
    final was = _screen;
    if (was == null) return;
    _screen = null;
    _screenHeight = null;
    localScreen.value = null;
    // The camera back in its place where video is on; else no picture.
    for (final p in _peers.values) {
      await p.showCamera(_picture);
    }
    // As with the camera: the renderer lets go first (GMFB-5).
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await _dispose(was);
    if (!kIsWeb && PlatformInfo.isAndroid) await screenService?.call(false);
  }

  /// Stops every track of a stream made here (the camera's or microphone's light goes out), then lets it go.
  static Future<void> _dispose(MediaStream s) async {
    for (final t in s.getTracks()) {
      await t.stop();
    }
    await s.dispose();
  }

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
      // The shared screen stays where there is one.
      for (final p in _peers.values) {
        await p.showCamera(_picture);
      }
      // Let the screen drop its renderer of this camera before the camera goes (GMFB-5: a renderer still holding a
      // disposed stream kept its last frame, on the Mac, in whichever tile it had moved to).
      await Future<void>.delayed(const Duration(milliseconds: 120));
      for (final t in cam.getTracks()) {
        await t.stop();
      }
      await cam.dispose();
      return;
    }
    for (final p in _peers.values) {
      await p.showCamera(_picture);
    }
  }

  /// How the connection to [id] stands, for the call to mend one that is not through (VoiceSession._mendAll).
  @override
  bool? linkUp(String id) => switch (links.value[id]) {
        PeerLink.connected || PeerLink.poor => true,
        PeerLink.connecting || PeerLink.reconnecting => false,
        _ => null,
      };

  @override
  VoicePeer peer(String id, {required void Function(Map<String, dynamic> candidate) onCandidate}) => peerWith(id, onCandidate: onCandidate, onFailed: () {});

  @override
  VoicePeer peerWith(String id, {required void Function(Map<String, dynamic> candidate) onCandidate, required void Function() onFailed, bool relayOnly = false}) {
    final had = _peers[id];
    if (had != null) return had;
    final made = _peers[id] = _RtcPeer(this, id, onCandidate, onFailed: onFailed, relayOnly: relayOnly);
    _link(id, PeerLink.connecting);
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

  /// [id]'s picture arrived: the stream their tile draws.
  void _heard(String id, MediaStream view) => remote.value = {...remote.value, id: view};

  /// [id]'s connection failed or closed: forgotten, and the others' pictures sized again.
  void _gone(String id) {
    if (_peers.remove(id) != null) _retune();
    remote.value = {...remote.value}..remove(id);
    // A failure is left showing until a new try begins ([peerWith]); anything else goes with the connection.
    if (links.value[id] != PeerLink.failed) _link(id, null);
  }
}

/// The WebRTC connection to one other person in the call, made when first needed.
class _RtcPeer implements VoicePeer {
  _RtcPeer(this.media, this.id, this.onCandidate, {required this.onFailed, this.relayOnly = false});
  final RtcMedia media;
  final String id;
  final void Function(Map<String, dynamic> candidate) onCandidate;

  /// No way through was found (VoiceSession starts over through the relay alone).
  final void Function() onFailed;

  /// Through the relay's TURN server alone: the second try, after a connection that tried every path failed.
  final bool relayOnly;
  Future<RTCPeerConnection>? _pc;
  /// Ways to connect that came before the other side's description was set; added once it is ([_settled]).
  final List<RTCIceCandidate> _early = [];
  bool _described = false;

  /// The sound tracks this connection receives ([RtcMedia._apply] sets their volume).
  final List<MediaStreamTrack> _sounds = [];

  /// A stream made on this device holding the picture this connection receives, which their tile draws. The track
  /// is put in one made here, never in the stream it arrived with: flutter_webrtc adds tracks only to streams made on
  /// the device (Android, the Mac and Windows all answer "stream is null" for a received one), and the picture
  /// arrives in no stream at all (its sender names none), so it was added to the sound's received stream, refused,
  /// and no tile ever drew another member's camera (Matt, 2026-11-21: "Video is not working on both ends it only
  /// shows our local video").
  MediaStream? _view;

  /// Received tracks are taken one at a time: two at once each made a stream of their own.
  Future<void> _taking = Future.value();

  /// Not connected this long after the descriptions are set: no way through ([onFailed]), as WebRTC itself can take
  /// half a minute or more to say, or never does on some networks.
  static const connectWithin = Duration(seconds: 15);
  Timer? _connectTimer;
  bool _connected = false, _failedSaid = false;

  /// Says, once, that no way through was found; never after it has connected.
  void _fail() {
    if (_failedSaid || _connected) return;
    _failedSaid = true;
    if (identical(media._peers[id], this)) media._link(id, PeerLink.failed);
    _connectTimer?.cancel();
    onFailed();
  }

  /// Starts the wait of [connectWithin], once.
  void _watchConnect() {
    if (_connected || _connectTimer != null) return;
    _connectTimer = Timer(connectWithin, _fail);
  }

  /// A track arrived: a sound is kept for its volume; a picture takes the place of the one before in [_view].
  Future<void> _took(RTCTrackEvent e) async {
    final track = e.track;
    if (track.kind == 'audio') {
      if (!_sounds.any((t) => t.id == track.id)) _sounds.add(track);
      if (identical(media._peers[id], this)) media._apply(id);
      return;
    }
    if (track.kind != 'video') return;
    var view = _view;
    if (view != null && view.getVideoTracks().any((t) => t.id == track.id)) return;
    if (view != null) {
      for (final t in view.getVideoTracks().toList()) {
        await view.removeTrack(t).catchError((_) {});
      }
    } else {
      view = _view = await createLocalMediaStream('ghost-view-$id-${identityHashCode(this)}');
    }
    await view.addTrack(track);
    // Not for a connection made in this one's place since (the same person in from another device).
    if (identical(media._peers[id], this) && identical(_view, view)) media._heard(id, view);
  }

  Future<RTCPeerConnection> get pc => _pc ??= _make();

  /// Makes the connection and wires what it finds to the session (candidates) and to [media] (their stream, their
  /// going).
  Future<RTCPeerConnection> _make() async {
    final pc = await createPeerConnection({'iceServers': media.iceServers, 'sdpSemantics': 'unified-plan', if (relayOnly) 'iceTransportPolicy': 'relay'});
    pc.onIceCandidate = (c) {
      if (c.candidate != null) onCandidate({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    pc.onTrack = (e) => _taking = _taking.then((_) => _took(e)).catchError((Object err) => debugPrint('rtc: track from $id not shown: $err'));
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connected = true;
        _connectTimer?.cancel();
      }
      if (identical(media._peers[id], this)) {
        final link = switch (s) {
          RTCPeerConnectionState.RTCPeerConnectionStateConnected => PeerLink.connected,
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => PeerLink.reconnecting,
          RTCPeerConnectionState.RTCPeerConnectionStateFailed => PeerLink.failed,
          RTCPeerConnectionState.RTCPeerConnectionStateNew || RTCPeerConnectionState.RTCPeerConnectionStateConnecting => PeerLink.connecting,
          _ => null,
        };
        if (link != null) media._link(id, link);
      }
      final failed = s == RTCPeerConnectionState.RTCPeerConnectionStateFailed;
      if ((failed || s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) && identical(media._peers[id], this)) {
        // Said before it is let go of, so the side that offered can start over (VoiceSession._failed).
        if (failed) _fail();
        media._gone(id);
      }
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
    if (media._picture != null) await showCamera(media._picture);
  }

  /// The side that answers takes the offer's sound and picture, and puts its own in them.
  Future<void> _fillOwn(RTCPeerConnection pc) async {
    for (final t in await pc.getTransceivers()) {
      final kind = t.receiver.track?.kind;
      if (kind == 'audio') {
        await t.sender.replaceTrack(media._mic!.getAudioTracks().first);
        await t.setDirection(TransceiverDirection.SendRecv);
      } else if (kind == 'video') {
        await t.sender.replaceTrack(media._picture);
        await t.setDirection(TransceiverDirection.SendRecv);
      }
    }
  }

  /// Sound at the rate Settings › Voice chose ([audioBitrate]); the picture as big as the number of others allows ([videoFor]).
  Future<void> _highest(RTCPeerConnection pc) async {
    final v = media.settings.sendTo(media._peers.length, videoFor(media._peers.length));
    for (final s in await pc.getSenders()) {
      final kind = s.track?.kind;
      final p = s.parameters;
      final encodings = p.encodings;
      if (encodings == null || encodings.isEmpty) continue;
      final screen = kind == 'video' && media.sharing;
      for (final e in encodings) {
        e.maxBitrate = kind == 'audio' ? media.audioBitrate : (screen ? RtcMedia.screenBitrate(v.bitrate) : v.bitrate);
        if (kind == 'video') e.scaleResolutionDownBy = screen ? RtcMedia.screenScale(media._screenHeight) : v.scale;
      }
      // A shared screen keeps its sharpness and gives up frames when the way is narrow; a camera balances the two.
      if (kind == 'video') p.degradationPreference = screen ? RTCDegradationPreference.MAINTAIN_RESOLUTION : RTCDegradationPreference.BALANCED;
      try {
        await s.setParameters(p);
      } catch (_) {}
    }
  }

  /// Sends [track] as this device's picture on this connection; null stops sending one.
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

  /// The other side's description is set: the candidates held back until now are added.
  Future<void> _settled(RTCPeerConnection c) async {
    _described = true;
    _watchConnect();
    for (final cand in _early) {
      // One that was another connection's (sent before it was let go) is no reason to fail this one.
      try {
        await c.addCandidate(cand);
      } catch (_) {}
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
    _connectTimer?.cancel();
    _failedSaid = true;
    final made = _pc;
    _pc = null;
    final stream = _view;
    _view = null;
    // Let go of at once, before the closing is waited for: a connection to the same id made meanwhile (their offer from
    // another device, right behind 'moved') is a new one, and this one's end must not take it away.
    if (identical(media._peers[id], this)) media._gone(id);
    if (made != null) await (await made).close();
    await stream?.dispose();
  }
}


/// How this device's connection to someone in a call stands (GMFB-4, @kevin: "show when users are connected to the
/// call so they and others know if they are having audio issues or if they are just not connected to the call").
enum PeerLink {
  /// Still finding a way through.
  connecting,

  /// Through, and sound goes both ways.
  connected,

  /// Through, but slow: what is said takes long to arrive, or breaks up.
  poor,

  /// Was through, and lost the way: WebRTC is trying again.
  reconnecting,

  /// No way through.
  failed;

  /// In a few words, for a person's row; null where nothing need be said.
  String? get words => switch (this) {
        PeerLink.connecting => 'Connecting…',
        PeerLink.connected => null,
        PeerLink.poor => 'Poor connection',
        PeerLink.reconnecting => 'Reconnecting…',
        PeerLink.failed => 'Can\'t connect',
      };
}
