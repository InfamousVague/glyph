/// Recording a call (Matt, 2026-11-19: "I'd like to have a "record call" plugin where it records the call to an MP4
/// with multiple named audio tracks"): one MP4 per recording, its first track everyone mixed (what a player plays by
/// itself), then one track per person, each named for them.
///
/// **Whose voice.** A call is a mesh, so each other person's sound already comes to this device on its own; the native
/// half (android CallRecorder.kt, macos and ios CallRecorder.swift) taps it after WebRTC has decoded it, before this
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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../desktop/store.dart' show DeskStore;
import 'channels.dart';
import '../plugins/record_call.dart' show RecordCallPlugin;
import '../plugins/scribe.dart' show ScribePlugin;
import 'mp4_names.dart';
import 'scribe.dart';
import 'voice.dart';

/// One recording kept on this device.
@immutable
class Recording {
  const Recording({required this.id, required this.path, required this.space, required this.at, required this.seconds, required this.people, this.by = '', this.seed = ''});

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

  Map<String, Object?> toJson() => {'id': id, 'path': path, 'space': space, 'at': at.millisecondsSinceEpoch, 'seconds': seconds, 'people': people, 'by': by, 'seed': seed};

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
}

class CallRecorder extends ChangeNotifier {
  CallRecorder._();
  static final CallRecorder instance = CallRecorder._();

  static const _channel = MethodChannel('ghost/recorder');

  /// Whether this platform records calls: a phone and a Mac or iPhone; not Windows yet (its WebRTC library's sink for
  /// another person's sound is not checked), nor a browser.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isMacOS || Platform.isIOS);

  _Taking? _now;

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
    v.hangoutFor(s.channel)?.send('🔴 ${t.names['me']} started recording this call. Only the voices of people who say yes are in it.');
    _watch = _changes(s).listen((_) => _follow(s));
    _follow(s);
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
    await _watch?.cancel();
    _watch = null;
    final s = Voice.instance.session;
    if (s != null && s.recording == t.id) s.setRecording(null);
    finishing = true;
    notifyListeners();
    try {
      final counts = ((await _channel.invokeMethod<Map>('stop')) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt()));
      // Every voice that has any sound, 'me' first, in the order they came.
      final keys = [for (final k in t.names.keys) if ((counts[k] ?? 0) > 0) k];
      if (keys.isEmpty) return null;
      final paths = [for (final k in keys) '${t.dir}/${_safe(k)}.pcm'];
      final mix = '${t.dir}/mix.pcm';
      await Isolate.run(() => mixPcm(paths, mix));
      final out = '${folder().path}/${t.id}.mp4';
      await _channel.invokeMethod('mux', {
        'out': out,
        'inputs': [mix, ...paths],
      });
      final names = ['Everyone', for (final k in keys) t.names[k]!];
      await Mp4Names.apply(out, names);
      final seconds = (counts.values.fold<int>(0, (a, b) => a > b ? a : b) / 48000).round();
      final r = Recording(id: t.id, path: out, space: t.space, at: t.started, seconds: seconds, people: names.skip(1).toList(), by: t.names['me']!, seed: t.seed);
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
      notifyListeners();
      final room = s == null ? null : Voice.instance.hangoutFor(s.channel);
      room?.send('⏹ ${t.names['me']} stopped recording.');
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
void mixPcm(List<String> inputs, String out) {
  final files = [for (final p in inputs) File(p).openSync()];
  final sink = File(out).openSync(mode: FileMode.write);
  try {
    const block = 48000; // A second at a time.
    while (true) {
      final reads = [for (final f in files) f.readSync(block * 2)];
      final longest = reads.fold<int>(0, (n, b) => b.length > n ? b.length : n);
      if (longest == 0) break;
      final n = longest ~/ 2;
      final sum = Int32List(n);
      for (final b in reads) {
        final d = ByteData.sublistView(b);
        for (var i = 0; i < b.length ~/ 2; i++) {
          sum[i] += d.getInt16(i * 2, Endian.little);
        }
      }
      final o = ByteData(n * 2);
      for (var i = 0; i < n; i++) {
        o.setInt16(i * 2, sum[i].clamp(-32768, 32767), Endian.little);
      }
      sink.writeFromSync(o.buffer.asUint8List());
    }
  } finally {
    for (final f in files) {
      f.closeSync();
    }
    sink.closeSync();
  }
}
