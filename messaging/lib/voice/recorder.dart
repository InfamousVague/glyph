/// Recording a call (Matt, 2026-11-19: "I'd like to have a "record call" plugin where it records the call to an MP4
/// with multiple named audio tracks"): one MP4 per recording, its first track everyone mixed (what a player plays by
/// itself), then one track per person, each named for them.
///
/// **Whose voice.** A call is a mesh, so each other person's sound already comes to this device on its own; the native
/// half (android CallRecorder.kt, macos and ios CallRecorder.swift, windows/runner/call_recorder.cpp) taps it after WebRTC has decoded it, before this
/// device's volume for them. Only someone whose own device said yes to this recording is tapped ('ry' in their state,
/// VoiceSession): an older build, the browser page or the Discord bridge can't say yes and is never recorded. This
/// device's own voice is in it as sent (after the noise removal), silence while muted.
///
/// **Everyone is told.** The recording's id goes in this device's state ('r'), so every member's app shows that the
/// call is being recorded and asks whether their voice may be in it; a line in the space's chat says it too, for the
/// builds that show nothing else.
///
/// **On the device.** While the call runs each voice goes to a file of its own, kept in step with the others by the
/// clock (silence where someone came late, left or dropped out), so a crash loses only the file at the end. Stopping
/// mixes them, has the platform encode each as AAC into one MP4, and names the tracks (lib/voice/mp4_names.dart). The
/// recording stays on the device ([CallRecorder.folder]) until its maker shares it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../desktop/store.dart' show DeskStore;
import 'channels.dart';
import '../plugins/record_call.dart' show RecordCallPlugin;
import '../plugins/scribe.dart' show ScribePlugin;
import 'mp4_merge.dart';
import 'mp4_names.dart';
import 'plugin_note.dart';
import 'scribe.dart';
import 'voice.dart';

/// One recording kept on this device.
@immutable
class Recording {
  const Recording({required this.id, required this.path, required this.space, required this.at, required this.seconds, required this.people, this.by = '', this.seed = '', this.markers = const []});

  final String id;

  /// The MP4.
  final String path;

  /// The space's name, as it was.
  final String space;
  final DateTime at;
  final int seconds;

  /// Whose voices are in it, by name, in the file's track order (after the mix).
  final List<String> people;

  /// Who made it.
  final String by;

  /// The space's seed, to send it to that space's chat.
  final String seed;

  /// The moments its maker marked while recording, in seconds from its start.
  final List<double> markers;

  Map<String, Object?> toJson() => {'id': id, 'path': path, 'space': space, 'at': at.millisecondsSinceEpoch, 'seconds': seconds, 'people': people, 'by': by, 'seed': seed, if (markers.isNotEmpty) 'markers': markers};

  static Recording? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['path'] is! String || j['at'] is! int) return null;
    return Recording(
      id: j['id'] as String,
      path: j['path'] as String,
      space: '${j['space'] ?? ''}',
      at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      seconds: (j['seconds'] as num?)?.toInt() ?? 0,
      people: [for (final p in (j['people'] as List? ?? const [])) '$p'],
      by: '${j['by'] ?? ''}',
      seed: '${j['seed'] ?? ''}',
      markers: [for (final m in (j['markers'] as List? ?? const [])) if (m is num) m.toDouble()],
    );
  }
}

/// What is being recorded now.
class _Taking {
  _Taking(this.id, this.dir, this.space, this.seed, this.started);
  final String id;
  final String seed;
  final String dir;
  final String space;
  final DateTime started;

  /// Each voice's file key (`me`, or a member's id) and the name to give its track.
  final Map<String, String> names = {};

  /// The members tapped now.
  final Set<String> tapped = {};

  /// The moments marked, in seconds from the start.
  final List<double> markers = [];
}

/// How loud each voice is as it is recorded, a tenth of a second at a time: read from the files the native half
/// writes (48 kHz mono 16-bit, kept in step by the clock), so the recording's panel can draw each track's waveform as
/// it grows (lib/ui/recording_float.dart; Matt, 2026-11-20: "show the different audio tracks being recorded and the
/// sound waves from each audio track").
class RecordingMeter extends ChangeNotifier {
  /// Samples in one step of the waveform: a tenth of a second.
  static const step = 4800;

  /// Steps a second.
  static const perSecond = 10;

  /// Samples in what a meter shows as "now": a twentieth of a second, so a meter moves as the voice does.
  static const window = 2400;

  /// At or over this a sample is at the top of what the file holds: the voice is clipping.
  static const clipAt = 0.985;

  /// Each voice's loudness by step, 0 to 1 (the loudest sample in it), from the recording's start.
  final Map<String, List<double>> levels = {};
  final Map<String, int> _read = {};

  /// Each voice now (Matt, 2026-11-20: "show audio tracks being recorded in real time with meters and whatnot as well
  /// as voice level changing"): the loudest sample and the average power (RMS) of the newest twentieth of a second
  /// written, both 0 to 1 as the file holds them, before any fader. Zero for a voice that has stopped being written.
  final Map<String, ({double peak, double rms})> now = {};
  final Map<String, int> _length = {};

  /// Voices that have clipped since the lamp was last cleared ([clearClip]).
  final Set<String> clipped = {};

  void clear() {
    levels.clear();
    _read.clear();
    now.clear();
    _length.clear();
    clipped.clear();
    notifyListeners();
  }

  /// Puts a voice's clip lamp out (all of them where [key] is null).
  void clearClip([String? key]) {
    if (key == null ? clipped.isEmpty : !clipped.remove(key)) return;
    if (key == null) clipped.clear();
    notifyListeners();
  }

  /// Reads what has been written to each of [files] (a voice's key and its file) since the last look: whole steps
  /// for the waveform, and the newest [window] for the meters.
  void read(Map<String, String> files) {
    var any = false;
    for (final e in files.entries) {
      final f = File(e.value);
      if (!f.existsSync()) continue;
      final length = f.lengthSync();
      final from = _read[e.key] ?? 0;
      final grew = length != (_length[e.key] ?? -1);
      _length[e.key] = length;
      RandomAccessFile? raf;
      try {
        // Now: the newest window, or silence where nothing has been written since the last look.
        final was = now[e.key];
        if (grew && length >= 2) {
          raf = f.openSync();
          final take = (length < window * 2 ? length : window * 2) & ~1;
          raf.setPositionSync((length - take) & ~1);
          final d = ByteData.sublistView(raf.readSync(take));
          var peak = 0;
          var sum = 0.0;
          final n = d.lengthInBytes ~/ 2;
          for (var i = 0; i < n; i++) {
            final v = d.getInt16(i * 2, Endian.little);
            final a = v.abs();
            if (a > peak) peak = a;
            sum += v * v;
          }
          final level = (peak: peak / 32768, rms: n == 0 ? 0.0 : math.sqrt(sum / n) / 32768);
          now[e.key] = level;
          if (level.peak >= clipAt && clipped.add(e.key)) any = true;
          if (was != level) any = true;
        } else if (was != null && (was.peak != 0 || was.rms != 0)) {
          now[e.key] = (peak: 0, rms: 0);
          any = true;
        }
        // Whole steps only: what is past the last whole one is read next time.
        final whole = ((length - from) ~/ (step * 2)) * step * 2;
        if (whole <= 0) continue;
        raf ??= f.openSync();
        raf.setPositionSync(from);
        final bytes = raf.readSync(whole);
        final d = ByteData.sublistView(bytes);
        final out = levels.putIfAbsent(e.key, () => <double>[]);
        for (var at = 0; at + step * 2 <= bytes.length; at += step * 2) {
          var peak = 0;
          for (var i = at; i < at + step * 2; i += 2) {
            final v = d.getInt16(i, Endian.little).abs();
            if (v > peak) peak = v;
          }
          out.add(peak / 32768);
        }
        _read[e.key] = from + bytes.length;
        any = true;
      } finally {
        raf?.closeSync();
      }
    }
    if (any) notifyListeners();
  }

  /// [levels] as given, for a picture or a test; [live] is each voice now where it is not its last step.
  @visibleForTesting
  void seed(Map<String, List<double>> given, {Map<String, ({double peak, double rms})>? live, Set<String> clipping = const {}}) {
    levels
      ..clear()
      ..addAll(given);
    now
      ..clear()
      ..addAll(live ?? {for (final e in given.entries) e.key: (peak: e.value.isEmpty ? 0.0 : e.value.last, rms: e.value.isEmpty ? 0.0 : e.value.last * 0.6)});
    clipped
      ..clear()
      ..addAll(clipping);
    notifyListeners();
  }
}

/// A point where a voice's loudness in the mix changes: from [sample] of the recording on it is [gain] (0 silent, 1
/// as recorded, up to [RecordingMix.most]).
typedef GainPoint = ({int sample, double gain});

/// The recording's mixer (Matt, 2026-11-20: "voice level changing and more"): how loud each voice is in the track of
/// everyone mixed, its fader, and whether it is muted or soloed there. Moved while recording, the mix follows as it
/// was moved: each change is kept with the moment it was made and played back into the mix when the recording stops
/// ([mixPcm]). Each person's own track is left as it was recorded, so the recording can always be mixed again.
class RecordingMix extends ChangeNotifier {
  /// The most a fader gives: twice as loud, +6 dB.
  static const most = 2.0;

  final Map<String, double> _fader = {};
  final Set<String> _muted = {};
  final Set<String> _solo = {};
  final Map<String, List<GainPoint>> _points = {};

  /// Goes up with every change, for whoever keeps something worked out from the points.
  int revision = 0;

  /// How loud [key] was in the mix at [sample] of the recording.
  double gainAt(String key, int sample) {
    var g = 1.0;
    for (final p in _points[key] ?? const <GainPoint>[]) {
      if (p.sample > sample) break;
      g = p.gain;
    }
    return g;
  }

  /// A voice's fader, 0 to [most]; 1 where it has not been moved.
  double fader(String key) => _fader[key] ?? 1;
  bool muted(String key) => _muted.contains(key);
  bool soloed(String key) => _solo.contains(key);
  bool get anySolo => _solo.isNotEmpty;

  /// How loud a voice is in the mix now: its fader, or nothing while it is muted or another voice is soloed.
  double gain(String key) => _muted.contains(key) || (_solo.isNotEmpty && !_solo.contains(key)) ? 0 : fader(key);

  /// Every change made to [key]'s loudness in the mix, in order; empty where it was never other than as recorded.
  List<GainPoint> points(String key) => List.unmodifiable(_points[key] ?? const <GainPoint>[]);

  void clear() {
    _fader.clear();
    _muted.clear();
    _solo.clear();
    _points.clear();
    revision++;
    notifyListeners();
  }

  /// Sets [key]'s fader at [sample] of the recording.
  void setFader(String key, double value, int sample, {Iterable<String> among = const []}) {
    final v = value.clamp(0.0, most).toDouble();
    if (v == fader(key)) return;
    _change(sample, [key, ...among], () => v == 1 ? _fader.remove(key) : _fader[key] = v);
  }

  /// Mutes or unmutes [key] in the mix at [sample].
  void setMuted(String key, bool on, int sample, {Iterable<String> among = const []}) {
    if (on == muted(key)) return;
    _change(sample, [key, ...among], () => on ? _muted.add(key) : _muted.remove(key));
  }

  /// Solos [key] at [sample]: while any voice is soloed only the soloed are in the mix, so every one of [among] (the
  /// voices there are) may change.
  void setSolo(String key, bool on, int sample, {Iterable<String> among = const []}) {
    if (on == soloed(key)) return;
    _change(sample, [key, ...among], () => on ? _solo.add(key) : _solo.remove(key));
  }

  /// Makes a change and writes down each of [keys] whose loudness in the mix it moved.
  void _change(int sample, Iterable<String> keys, void Function() make) {
    final all = keys.toSet();
    final before = {for (final k in all) k: gain(k)};
    make();
    for (final k in all) {
      final g = gain(k);
      if (g == before[k]) continue;
      final list = _points.putIfAbsent(k, () => <GainPoint>[]);
      final at = sample < 0 ? 0 : sample;
      // A fader dragged makes many changes in a moment: one at the same place replaces the last.
      if (list.isNotEmpty && list.last.sample >= at) {
        list[list.length - 1] = (sample: list.last.sample, gain: g);
      } else {
        list.add((sample: at, gain: g));
      }
    }
    revision++;
    notifyListeners();
  }
}

class CallRecorder extends ChangeNotifier {
  CallRecorder._();
  static final CallRecorder instance = CallRecorder._();

  /// Recording as given, for a picture of the recording's panel: [names] by key ('me' first), those in [left] no
  /// longer taken. It takes nothing and writes nothing.
  @visibleForTesting
  CallRecorder.standing({required Map<String, String> names, required DateTime since, Set<String> left = const {}, List<double> markers = const []}) {
    final t = _now = _Taking('rec-standing', Directory.systemTemp.path, 'general', 'standing', since);
    t.names.addAll(names);
    t.tapped.addAll(names.keys.where((k) => k != 'me' && !left.contains(k)));
    t.markers.addAll(markers);
  }

  /// For a test: the standing recording over, as a Stop or the call's end leaves it.
  @visibleForTesting
  void endForTest() {
    _now = null;
    notifyListeners();
  }

  static const _channel = MethodChannel('ghost/recorder');

  /// Whether this platform records calls: a phone, a Mac or iPhone, and Windows (windows/runner/call_recorder.cpp;
  /// Matt, 2026-11-21: "my friend is not able to see plugins added for recording calls on his pc"); not a browser.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isMacOS || Platform.isIOS || Platform.isWindows);

  _Taking? _now;

  /// Each voice's loudness as it is recorded (RecordingMeter), read every tenth of a second while recording.
  final RecordingMeter meter = RecordingMeter();
  Timer? _metering;

  /// The recording's mixer: each voice's fader, mute and solo in the mix (RecordingMix).
  final RecordingMix mix = RecordingMix();

  /// Where the recording is now, in samples from its start (the voices' files are kept in step by the clock).
  int get position {
    final t = _now;
    return t == null ? 0 : (DateTime.now().difference(t.started).inMicroseconds * 48 ~/ 1000);
  }

  /// The keys of the voices there are, for a solo, which moves every one of them.
  Iterable<String> get _keys => _now?.names.keys ?? const <String>[];

  void setFader(String key, double value) => mix.setFader(key, value, position);
  void setMuted(String key, bool on) => mix.setMuted(key, on, position, among: _keys);
  void setSolo(String key, bool on) => mix.setSolo(key, on, position, among: _keys);

  /// The moments marked so far, in seconds from the start.
  List<double> get markers => List.unmodifiable(_now?.markers ?? const <double>[]);

  /// Marks this moment of the recording, to find again afterwards; the second marked, or null where nothing records.
  double? mark() {
    final t = _now;
    if (t == null) return null;
    final at = DateTime.now().difference(t.started).inMilliseconds / 1000;
    t.markers.add(at);
    notifyListeners();
    return at;
  }

  /// The tracks being recorded, 'me' first: each voice's key, its name, and whether it is being taken now (false for
  /// someone who left or took back their yes; their track keeps what it has).
  List<({String key, String name, bool live})> get tracks {
    final t = _now;
    if (t == null) return const [];
    return [
      for (final k in t.names.keys)
        if (k == 'me' || t.tapped.contains(k) || meter.levels.containsKey(k)) (key: k, name: t.names[k]!, live: k == 'me' || t.tapped.contains(k)),
    ];
  }

  Map<String, String> _files(_Taking t) => {for (final k in t.names.keys) k: '${t.dir}/${_safe(k)}.pcm'};

  /// Being made into a file after stopping.
  bool finishing = false;

  /// Where the last recording went beyond this device, or why it didn't: a circle's Files space (Record call's choice,
  /// lib/plugins/record_call.dart); null outside a circle.
  String? savedTo;

  /// The recording being made now, by its id.
  String? get recording => _now?.id;
  DateTime? get since => _now?.started;

  /// Whose voices are being recorded now, by name ('You' first).
  List<String> get recordedNames => [for (final k in _now?.names.keys ?? const <String>[]) if (k == 'me' || (_now?.tapped.contains(k) ?? false)) _now!.names[k]!];

  /// Where recordings are kept: the app's own folder (a phone's is cleared only with the app).
  static Directory folder() {
    if (!kIsWeb && Platform.isAndroid) return Directory('${Directory.systemTemp.parent.path}/files/recordings');
    return Directory('${DeskStore.defaultDir().path}/recordings');
  }

  final List<Recording> _kept = [];
  bool _read = false;

  /// The recordings kept here, the newest first.
  List<Recording> get kept {
    _readKept();
    return List.unmodifiable(_kept);
  }

  File get _index => File('${folder().path}/recordings.json');

  void _readKept() {
    if (_read) return;
    _read = true;
    try {
      final list = jsonDecode(_index.readAsStringSync()) as List;
      _kept
        ..clear()
        ..addAll([for (final j in list) ?Recording.fromJson(j)].where((r) => File(r.path).existsSync()));
    } catch (_) {}
  }

  void _writeKept() {
    try {
      folder().createSync(recursive: true);
      _index.writeAsStringSync(jsonEncode([for (final r in _kept) r.toJson()]));
    } catch (_) {}
  }

  /// Deletes [r] from this device.
  void delete(Recording r) {
    CallScribe.instance.forget(r);
    _readKept();
    _kept.removeWhere((k) => k.id == r.id);
    try {
      File(r.path).deleteSync();
    } catch (_) {}
    _writeKept();
    notifyListeners();
  }

  StreamSubscription<void>? _watch;

  /// Starts recording the call [Voice] is in; the reason in words where it can't.
  Future<String?> start() async {
    final v = Voice.instance;
    final s = v.session;
    if (s == null) return 'There is no call to record.';
    if (!supported) return 'Calls can\'t be recorded on this device yet.';
    if (_now != null || finishing) return 'A recording is already being made.';
    final id = _hexId();
    final dir = Directory('${folder().path}/$id.parts');
    try {
      dir.createSync(recursive: true);
      await _channel.invokeMethod('start', {'mic': '${dir.path}/me.pcm', 'muted': s.muted || s.deafened});
    } catch (e) {
      return 'The recording couldn\'t start: $e';
    }
    final t = _now = _Taking(id, dir.path, s.channel.name, s.channel.seed, DateTime.now());
    t.names['me'] = s.name.isEmpty ? 'You' : s.name;
    s.setRecording(id);
    s.answerRecording(id, true);
    // A line every build shows, the browser page and older apps among them.
    // With Record call's note, which draws it as a card with its icon (lib/plugins/record_call.dart); the words are what
    // a build without it shows.
    v.hangoutFor(s.channel)?.sendWith(
      text: '🔴 ${t.names['me']} started recording this call. Only the voices of people who say yes are in it.',
      note: PluginChatNote('recordcall', 'started', {'by': t.names['me']!}),
    );
    _watch = _changes(s).listen((_) => _follow(s));
    _follow(s);
    meter.clear();
    mix.clear();
    // Twenty times a second: the meters move as the voices do.
    _metering = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = _now;
      if (now != null) meter.read(_files(now));
    });
    notifyListeners();
    return null;
  }

  Stream<void> _changes(VoiceSession s) {
    final c = StreamController<void>();
    void tell() => c.add(null);
    s.addListener(tell);
    final media = Voice.instance.media;
    media?.remote.addListener(tell);
    c.onCancel = () {
      s.removeListener(tell);
      media?.remote.removeListener(tell);
    };
    return c.stream;
  }

  /// Taps whoever has said yes and whose sound has come; lets go of whoever has said no or gone; says this device's mute.
  Future<void> _follow(VoiceSession s) async {
    final t = _now;
    if (t == null) return;
    if (Voice.instance.session != s || !s.joined) {
      unawaited(stop());
      return;
    }
    unawaited(_channel.invokeMethod('muted', {'on': s.muted || s.deafened}).catchError((_) {}));
    final remote = Voice.instance.media?.remote.value ?? const <String, MediaStream>{};
    for (final m in s.members.values) {
      final yes = m.agreed.contains(t.id) && !m.declined.contains(t.id);
      final track = remote[m.id]?.getAudioTracks().firstOrNull;
      if (yes && track?.id != null && !t.tapped.contains(m.id)) {
        t.tapped.add(m.id);
        t.names[m.id] = Voice.instance.nameOf(m.id);
        try {
          await _channel.invokeMethod('add', {'key': m.id, 'track': track!.id, 'path': '${t.dir}/${_safe(m.id)}.pcm'});
        } catch (_) {
          t.tapped.remove(m.id);
        }
      } else if (!yes && t.tapped.contains(m.id)) {
        t.tapped.remove(m.id);
        unawaited(_channel.invokeMethod('remove', {'key': m.id}).catchError((_) {}));
      }
      if (yes) t.names[m.id] = Voice.instance.nameOf(m.id);
    }
    for (final gone in t.tapped.where((k) => !s.members.containsKey(k)).toList()) {
      t.tapped.remove(gone);
      unawaited(_channel.invokeMethod('remove', {'key': gone}).catchError((_) {}));
    }
    notifyListeners();
  }

  /// Stops the recording and makes its MP4; the recording, or null where nothing could be made.
  Future<Recording?> stop() async {
    final t = _now;
    if (t == null) return null;
    _now = null;
    savedTo = null;
    _metering?.cancel();
    _metering = null;
    meter.clear();
    await _watch?.cancel();
    _watch = null;
    final s = Voice.instance.session;
    if (s != null && s.recording == t.id) s.setRecording(null);
    finishing = true;
    notifyListeners();
    // What the "stopped" card says (lib/plugins/record_call.dart): how long, how many voices, where it went.
    var seconds = DateTime.now().difference(t.started).inSeconds;
    var voices = 0;
    try {
      final counts = ((await _channel.invokeMethod<Map>('stop')) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt()));
      // Every voice that has any sound, 'me' first, in the order they came.
      final keys = [for (final k in t.names.keys) if ((counts[k] ?? 0) > 0) k];
      if (keys.isEmpty) return null;
      final paths = [for (final k in keys) '${t.dir}/${_safe(k)}.pcm'];
      final mix = '${t.dir}/mix.pcm';
      // The mix as its faders, mutes and solos were moved while it recorded; each voice's own track as recorded.
      final moved = [for (final k in keys) this.mix.points(k)];
      await Isolate.run(() => mixPcm(paths, mix, gains: moved));
      final out = '${folder().path}/${t.id}.mp4';
      if (!kIsWeb && Platform.isWindows) {
        // Windows makes each voice an AAC file of its own; they are put together here (lib/voice/mp4_merge.dart).
        final parts = <String>[];
        for (final (i, p) in [mix, ...paths].indexed) {
          final part = '${t.dir}/track$i.m4a';
          await _channel.invokeMethod('encode', {'in': p, 'out': part});
          parts.add(part);
        }
        await Mp4Merge.merge(parts, out);
      } else {
        await _channel.invokeMethod('mux', {
          'out': out,
          'inputs': [mix, ...paths],
        });
      }
      final names = ['Everyone', for (final k in keys) t.names[k]!];
      await Mp4Names.apply(out, names);
      seconds = (counts.values.fold<int>(0, (a, b) => a > b ? a : b) / 48000).round();
      voices = keys.length;
      final r = Recording(id: t.id, path: out, space: t.space, at: t.started, seconds: seconds, people: names.skip(1).toList(), by: t.names['me']!, seed: t.seed, markers: List.of(t.markers));
      _readKept();
      _kept.insert(0, r);
      _writeKept();
      try {
        Directory(t.dir).deleteSync(recursive: true);
      } catch (_) {}
      // Into its circle's Files space, in the folder the circle chose (lib/plugins/record_call.dart).
      try {
        savedTo = RecordCallPlugin.saveInCircle(r);
      } catch (e) {
        savedTo = 'Kept on this device: it couldn\'t be saved to the circle ($e)';
      }
      // Written out at once where Scribe is on for it and says so (lib/plugins/scribe.dart).
      if (ScribePlugin.autoFor(r)) unawaited(CallScribe.instance.transcribe(r));
      return r;
    } catch (e) {
      debugPrint('recorder: $e');
      return null;
    } finally {
      finishing = false;
      mix.clear();
      notifyListeners();
      final room = s == null ? null : Voice.instance.hangoutFor(s.channel);
      room?.sendWith(
        text: '⏹ ${t.names['me']} stopped recording.',
        note: PluginChatNote('recordcall', 'stopped', {
          'by': t.names['me']!,
          'seconds': '$seconds',
          if (voices > 0) 'voices': '$voices',
          'savedTo': ?savedTo,
        }),
      );
    }
  }

  /// A file name for a member's key: their id is hex already; 'me' is 'me'.
  static String _safe(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String _hexId() {
    final r = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'rec$r';
  }
}

/// Mixes [inputs] (48 kHz mono 16-bit files, the shorter ones read as silence past their end) into [out], each voice at
/// its own loudness and the sum held under clipping.
///
/// [gains] gives, for each input in order, the changes made to its loudness while it was recorded (RecordingMix): it
/// is as recorded until its first point, then each point's gain from that sample on, reached over a hundredth of a
/// second so a mute or a fader's move is never a click. An input with no points, or no [gains] at all, is as recorded.
void mixPcm(List<String> inputs, String out, {List<List<GainPoint>>? gains}) {
  final files = [for (final p in inputs) File(p).openSync()];
  final sink = File(out).openSync(mode: FileMode.write);
  // Where each input is in its points, and how loud it is and is heading.
  const ramp = 480;
  final next = List<int>.filled(inputs.length, 0);
  final at = List<double>.filled(inputs.length, 1);
  final goal = List<double>.filled(inputs.length, 1);
  try {
    const block = 48000; // A second at a time.
    var done = 0;
    while (true) {
      final reads = [for (final f in files) f.readSync(block * 2)];
      final longest = reads.fold<int>(0, (n, b) => b.length > n ? b.length : n);
      if (longest == 0) break;
      final n = longest ~/ 2;
      final sum = Float64List(n);
      for (var f = 0; f < reads.length; f++) {
        final b = reads[f];
        final d = ByteData.sublistView(b);
        final points = gains != null && f < gains.length ? gains[f] : const <GainPoint>[];
        final has = b.length ~/ 2;
        if (points.isEmpty) {
          for (var i = 0; i < has; i++) {
            sum[i] += d.getInt16(i * 2, Endian.little);
          }
          continue;
        }
        var g = at[f], to = goal[f], k = next[f];
        const stepBy = 1 / ramp;
        // Past this input's end too: its points still pass, so a later block starts from the right loudness.
        for (var i = 0; i < n; i++) {
          while (k < points.length && points[k].sample <= done + i) {
            to = points[k].gain;
            k++;
          }
          if (g != to) g = g < to ? math.min(to, g + stepBy * RecordingMix.most) : math.max(to, g - stepBy * RecordingMix.most);
          if (i < has) sum[i] += d.getInt16(i * 2, Endian.little) * g;
        }
        at[f] = g;
        goal[f] = to;
        next[f] = k;
      }
      final o = ByteData(n * 2);
      for (var i = 0; i < n; i++) {
        o.setInt16(i * 2, sum[i].round().clamp(-32768, 32767), Endian.little);
      }
      sink.writeFromSync(o.buffer.asUint8List());
      done += n;
    }
  } finally {
    for (final f in files) {
      f.closeSync();
    }
    sink.closeSync();
  }
}
