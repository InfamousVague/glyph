/// The native capture: [CaptureBackend] (engine.dart) over the Rust core, which is Whisper in native/src/capture.rs.
/// What `invoke('capture_start')` and `listenTo('capture://partial', …)` were to the web app's `capture/engine.ts`.
///
/// One method a command, with the web's arguments; one stream for the web's events. The core's commands that take
/// longer than a moment are long jobs there (they answer an id and end with an event, since the worker isolate is
/// serial), and here each is awaited to its end, so every method resolves when the Tauri command resolved and with
/// what it resolved with. A refusal is thrown as the core's own sentence ([CoreError]): "busy", "cancelled", "No
/// capture is running." and the rest are the words the Tauri app's page read.
///
/// No always-on microphone: nothing here opens one. Audio is what the recorder pushes ([push]) between [start] and
/// [stop] or [cancel]; the core refuses a push at any other time.
///
/// ```dart
/// final core = await GhostCore.open();
/// await core.init(dataDir: paths.dataDir, cacheDir: paths.cacheDir);
/// final engine = CaptureEngine(backend: NativeCaptureBackend(core), hasNativeGeneration: hasNativeGeneration);
/// ```
///
/// [mirrors] is where the two voice models are downloaded from: null for the two the web app names (attack.fm, then
/// Hugging Face), or a list that is then the WHOLE list (a test's server on 127.0.0.1). Nothing else of the capture
/// leaves the device.
library;

import 'dart:async';

import '../core/native/events.dart';
import '../core/native/ghost_core.dart';
import 'engine.dart';
import 'markdown.dart' show Segment;

class NativeCaptureBackend implements CaptureBackend {
  NativeCaptureBackend(this.core, {this.mirrors});

  final GhostCore core;

  /// The base URLs a voice model is fetched from, each tried as `<mirror>/<file>`; null for the web app's own.
  final List<String>? mirrors;

  /// The core's capture events, in the order it emitted them. A broadcast stream: every listener hears every
  /// event, and one that comes late hears only what follows.
  @override
  late final Stream<CaptureEvent> events = core.events.map(captureEventOf).where((event) => event != null).cast<CaptureEvent>();

  /// A command that is a long job in the core, awaited to its end: the value the Tauri command resolved with.
  Future<Object?> _job(String command, [Map<String, Object?> args = const {}]) async => (await core.startJob(command, args)).done;

  Map<String, Object?> get _from => {if (mirrors != null) 'mirrors': mirrors};

  @override
  Future<void> start() => _job('capture_start');

  @override
  Future<void> push(String pcm) => core.invoke('capture_push', {'pcm': pcm});

  @override
  Future<void> rewind(int toMs) => _job('capture_rewind', {'toMs': toMs});

  @override
  Future<CaptureStopped?> stop([StopOptions? options]) async {
    final answer = await _job('capture_stop', {
      if (options?.recordAs != null) 'recordAs': options!.recordAs,
      if (options?.append != null) 'append': options!.append,
    });
    if (answer is! Map) return null;
    return CaptureStopped(transcript: answer['transcript'] as String?, recordedMs: (answer['recordedMs'] as num?)?.toInt());
  }

  @override
  Future<void> cancel() => _job('capture_cancel');

  @override
  Future<ModelStatus> modelStatus() async => _status(await core.invoke('capture_model_status'));

  @override
  Future<ModelStatus> fetchModel() async => _status(await _job('capture_fetch_model', _from));

  @override
  Future<int?> reassignRecording({required String fromId, required String toId, required bool append}) async =>
      (await _job('capture_reassign_recording', {'fromId': fromId, 'toId': toId, 'append': append}) as num?)?.toInt();

  @override
  Future<void> discardRecording({required String id}) => core.invoke('capture_discard_recording', {'id': id});

  @override
  Future<({bool present, int bytes})> refineModelStatus() async {
    final status = _status(await core.invoke('capture_refine_model_status'));
    return (present: status.present, bytes: status.bytes);
  }

  @override
  Future<({bool present, int bytes})> fetchRefineModel() async {
    final status = _status(await _job('capture_fetch_refine_model', _from));
    return (present: status.present, bytes: status.bytes);
  }

  @override
  Future<List<Segment>> refine({required String id, required int fromMs, required String promptTail}) async {
    final phrases = await _job('capture_refine', {'id': id, 'fromMs': fromMs, 'promptTail': promptTail});
    return [for (final phrase in phrases as List) _segment(phrase)];
  }

  /// `transcribe_wav { path }`: a whole 16 kHz WAV file in one pass with the loaded model, for measuring a device.
  /// Not part of [CaptureBackend]; the web app's benchmark asked for it by name.
  Future<({String text, int audioMs, int elapsedMs, String model})> transcribeWav(String path) async {
    final said = (await _job('transcribe_wav', {'path': path}) as Map).cast<String, Object?>();
    return (text: said['text'] as String, audioMs: (said['audioMs'] as num).toInt(), elapsedMs: (said['elapsedMs'] as num).toInt(), model: said['model'] as String);
  }
}

ModelStatus _status(Object? json) {
  final status = (json as Map).cast<String, Object?>();
  return ModelStatus(present: status['present'] == true, name: status['name'] as String? ?? '', path: status['path'] as String? ?? '', bytes: (status['bytes'] as num?)?.toInt() ?? 0);
}

Segment _segment(Object? json) {
  final phrase = (json as Map).cast<String, Object?>();
  return Segment(text: phrase['text'] as String? ?? '', startMs: (phrase['startMs'] as num?)?.toInt() ?? 0, endMs: (phrase['endMs'] as num?)?.toInt() ?? 0);
}

/// One event of the core's as the capture reads it, or null for an event that is not the capture's (or one this
/// build cannot read): the web's seven names, each with the payload native/src/capture.rs lists.
CaptureEvent? captureEventOf(CoreEvent event) {
  final said = event.map;
  int whole(String key) => (said[key] as num?)?.toInt() ?? 0;
  switch (event.event) {
    case 'capture://partial':
      return CaptureEventPartial(said['text'] as String? ?? '');
    case 'capture://segment':
      return CaptureEventSegment(_segment(said));
    case 'capture://rewound':
      final segments = said['segments'];
      return CaptureEventRewound(toMs: whole('toMs'), segments: [if (segments is List) for (final segment in segments) _segment(segment)]);
    case 'capture://error':
      return CaptureEventError(said['message'] as String? ?? '');
    case 'capture://model-progress':
      return CaptureEventModelProgress(receivedBytes: whole('receivedBytes'), totalBytes: whole('totalBytes'));
    case 'capture://refine-model-progress':
      return CaptureEventRefineModelProgress(receivedBytes: whole('receivedBytes'), totalBytes: whole('totalBytes'));
    case 'capture://refine-progress':
      return CaptureEventRefineProgress(id: said['id'] as String? ?? '', percent: said['percent'] as num? ?? 0);
    default:
      return null;
  }
}
