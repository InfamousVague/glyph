/// A meeting's sound kept on the device, and its write-up asked for (docs/MEET.md, "On the device"): the app's
/// [MeetDevice].
///
/// **The sound.** The write-up (tauri/src-tauri/src/write_up.rs, in the core) already transcribes a FILE: a
/// meeting's `recordings/<note id>.wav`, 16 kHz mono 16-bit PCM, read a span at a time, Whisper over each. So a
/// take's sound needs only to become that file, and the rest is the write-up a meeting recorded here gets. The bot's
/// sound is Opus in WebM; Dart reads the container (webm.dart) and hands the packets to the device's own Opus
/// decoder over `ghost_md/meet_audio`, which writes the WAV:
///
/// - `opusToWav {packets, wav}` -> `{ms}`: [packets] is a file laid out by `packedForDecoder` (`GOP1`), [wav] where
///   the 16 kHz mono WAV is to be written. An error where the sound will not decode.
///   macOS: macos/Runner/MeetAudio.swift (AVAudioConverter, Opus to 48 kHz, then to 16 kHz mono).
///   Android: android/…/ghost_md/MeetAudio.kt (MediaCodec's Opus decoder, then 48 kHz to 16 kHz mono).
///
/// The WAV is then moved into place as the note's recording by the core (`CoreFiles.adopt`), under the rules a
/// recording that came by sync is kept by, and plays on the note's tape like any meeting's.
///
/// **The write-up**, asked as a meeting recorded here asks for it, with Write up straight away honoured: on Android
/// the meeting service's (`ghost_md/meeting` `writeUp`, WorkManager, which keeps to the battery rule itself); on the
/// Mac the core's own `write_up_run`, run here ([CoreWriteUps]), the Mac counting as plugged in. The summary is the
/// summary queue's native job (lib/ai/summaries.dart), landed in the note when the write-up's result is there.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/native/core.dart' show CoreInvoke;
import '../core/native/files.dart';
import 'meet_in.dart';
import 'webm.dart';

/// The device's Opus decoder (see the header).
const MethodChannel meetAudioChannel = MethodChannel('ghost_md/meet_audio');

/// The app's [MeetDevice]: the sound decoded to the note's WAV, and the write-up asked for by [askWriteUp].
class DeviceMeetTapes implements MeetDevice {
  DeviceMeetTapes({required this.dataDir, required this.invoke, required this.askWriteUp, this.channel = meetAudioChannel});

  /// The app's data directory, where the core keeps `recordings/`.
  final String dataDir;
  final CoreInvoke invoke;
  final void Function(String noteId) askWriteUp;
  final MethodChannel channel;

  @override
  Future<int?> keepTape(String noteId, Uint8List audio, String mime) async {
    if (!mime.contains('webm')) return null;
    final Uint8List packed;
    try {
      packed = await Isolate.run(() => packedForDecoder(readWebmOpus(audio)));
    } on WebmError catch (failure) {
      debugPrint('[meet] $failure');
      return null;
    }
    final dir = Directory('$dataDir/meet');
    await dir.create(recursive: true);
    final packets = File('${dir.path}/$noteId.gop');
    final wav = '${dir.path}/$noteId.wav';
    await packets.writeAsBytes(packed, flush: true);
    final Map<String, Object?>? said;
    try {
      said = await channel.invokeMapMethod<String, Object?>('opusToWav', {'packets': packets.path, 'wav': wav});
    } on MissingPluginException {
      return null;
    } finally {
      if (await packets.exists()) await packets.delete();
    }
    final ms = said?['ms'];
    if (ms is! num) return null;
    try {
      await CoreFiles(invoke).adopt(CoreFileKind.recording, noteId, wav);
    } finally {
      final left = File(wav);
      if (await left.exists()) await left.delete();
    }
    return ms.toInt();
  }

  @override
  void writeUp(String noteId) => askWriteUp(noteId);
}

/// A long job in the core, as `GhostCore.startJob` starts one: answers its end.
typedef StartCoreJob = Future<Future<Object?>> Function(String command, Map<String, Object?> args);

/// The Mac's write-ups, run by the app: the core's `write_up_run` for a note, as Android's WorkManager runs it
/// (native/src/recording.rs). One at a time; a hold (a capture going, the engine busy, an error short of the third)
/// is tried again a minute later while the app is open, and at the latest when the summary queue asks again.
class CoreWriteUps {
  CoreWriteUps({required this.startJob, required this.onDone, this.retry = const Duration(minutes: 1)});

  final StartCoreJob startJob;

  /// The note's transcript is in it: what follows a write-up (a sync, which names its speakers and sends it on).
  final void Function(String noteId) onDone;
  final Duration retry;

  final Map<String, ({bool now, bool fresh})> _asked = {};
  final Map<String, Timer> _again = {};
  bool _running = false;

  /// Writes up note [id]: [now] past the battery rule, [fresh] a failed or cancelled one asked again.
  void run(String id, {bool now = false, bool fresh = false}) {
    _again.remove(id)?.cancel();
    final was = _asked[id];
    _asked[id] = (now: now || (was?.now ?? false), fresh: fresh || (was?.fresh ?? false));
    unawaited(_next());
  }

  Future<void> _next() async {
    if (_running || _asked.isEmpty) return;
    final id = _asked.keys.first;
    final asked = _asked.remove(id)!;
    _running = true;
    try {
      final done = await startJob('write_up_run', {
        'id': id,
        'options': {'now': asked.now, 'fresh': asked.fresh, 'requestedAt': DateTime.now().millisecondsSinceEpoch, 'charging': true, 'batteryPercent': 100, 'thermal': 'none', 'appInFront': true},
      });
      final answer = await done;
      if (answer is Map && (answer['done'] == true || answer['alreadyDone'] == true)) {
        onDone(id);
      } else if (answer is Map && answer['retry'] != null) {
        _again[id] = Timer(retry, () {
          _again.remove(id);
          run(id, now: asked.now);
        });
      }
    } catch (failure) {
      debugPrint('[meet] the write-up did not run: $failure');
    } finally {
      _running = false;
      unawaited(_next());
    }
  }

  void dispose() {
    for (final timer in _again.values) {
      timer.cancel();
    }
    _again.clear();
    _asked.clear();
  }
}
