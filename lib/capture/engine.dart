/// The transcriber, behind one interface, whichever one is running. A port of `src/app/capture/engine.ts`.
///
/// Three engines answer it. On the phone it is Whisper in the Rust core: samples are streamed in and partial and
/// committed text come back as events, and the recording is kept as the note's tape. Where there is no core it is a
/// speech recogniser the platform lends, when it has one - good enough to develop the capture screen against with a
/// real voice. And when a simulation is asked for it is a script that speaks a fixed note on a timer
/// (simulated.dart), which is what makes the screen testable with no microphone.
///
/// The caller never learns which one it got beyond `kind`, which is shown so a person can tell a real on-device
/// transcription from a fallback.
///
/// No always-on microphone: an engine listens between [CaptureEngine.startCapture] and its session's `stop` or
/// `cancel`, and at no other time. Nothing here opens anything when the app does, but the voice model's download
/// ([CaptureEngine.ensureModel]), which is a file and not a microphone.
///
/// What differs:
/// - The web calls Tauri: `invoke('capture_start')` and its friends, and `listenTo('capture://partial', …)`. Here
///   that bridge is the abstract [CaptureBackend], one method a command with the web's arguments, and one stream of
///   [CaptureEvent]s, each carrying the web's event name. A test passes a fake; the app will pass the Rust core
///   (pieces 8C and 8D).
/// - The web's module functions (`startCapture`, `ensureModel`, `reassignRecording`, `discardRecording`) are the
///   methods of a [CaptureEngine], which is made with what the web reads from other modules and from the page:
///   the backend (null where the web's `isTauri()` is false), `hasNativeGeneration`, the preferences, the page's
///   query (`?simulate`), its clock (`performance.now`), and the recogniser's constructor
///   (`window.webkitSpeechRecognition`).
/// - The web listens three times, once an event; here it is one subscription to the one stream, cancelled where the
///   web calls its three unlisteners. A failed model check leaves it listening, as it leaves the web's three.
/// - Which session owns the native capture is the library's own to know, as it is the module's on the web: there is
///   one native capture however many engines are made.
library;

import 'dart:async';
import 'dart:typed_data';

import '../core/bytes.dart';
import '../core/preferences.dart' as core show preferences;
import '../core/preferences.dart' show Preferences;
import 'markdown.dart' show Segment;
import 'simulated.dart';

/// Which engine is listening; `name` is the web's word for it.
enum EngineKind { whisper, browser, simulated }

/// What a session tells whoever started it.
class CaptureHandlers {
  const CaptureHandlers({required this.onPartial, required this.onSegment, required this.onError, this.onModelProgress, this.guesses = true});

  /// Whether the words still being said are guessed at as they come ([onPartial]). A meeting recorded with its live
  /// transcript off is not (Settings › Recording › Live transcript during meetings; meeting_live_words.dart): each
  /// phrase is heard once, when it is finished, which is a fraction of the work. A backend that cannot say so
  /// ([GuessFreeStart]) guesses as before.
  final bool guesses;

  /// Best guess for speech not yet committed; replaces the previous one.
  final void Function(String text) onPartial;

  /// Committed text, appended.
  final void Function(Segment segment) onSegment;
  final void Function(String message) onError;

  /// Model download progress, only ever reported by the Whisper engine.
  final void Function(int receivedBytes, int totalBytes)? onModelProgress;
}

/// How a session is stopped.
class StopOptions {
  const StopOptions({this.recordAs, this.append});

  /// Keep the audio as this note's tape.
  final String? recordAs;

  /// Add to the note's existing tape rather than start it over.
  final bool? append;

  @override
  bool operator ==(Object other) => other is StopOptions && other.recordAs == recordAs && other.append == append;

  @override
  int get hashCode => Object.hash(recordAs, append);

  @override
  String toString() => 'StopOptions(recordAs: $recordAs, append: $append)';
}

/// What a stopped session answers.
class Stopped {
  const Stopped({required this.recordedMs, required this.transcript});

  /// The kept tape's whole length, or null when nothing was kept.
  final int? recordedMs;

  /// The final decoder result, when the engine has one. Whisper produces this from its stop after it has drained
  /// the last audio; phrase events can still be in flight when the listeners are removed. The other engines, and
  /// older native hosts, do not have an authoritative final result.
  final String? transcript;

  @override
  bool operator ==(Object other) => other is Stopped && other.recordedMs == recordedMs && other.transcript == transcript;

  @override
  int get hashCode => Object.hash(recordedMs, transcript);

  @override
  String toString() => 'Stopped(recordedMs: $recordedMs, transcript: $transcript)';
}

/// A running transcriber, whichever engine it is.
class CaptureSession {
  const CaptureSession({
    required this.kind,
    required this.wantsSamples,
    required this.keepsAudio,
    required this.push,
    required this.positionMs,
    required this.stop,
    required this.cancel,
  });

  final EngineKind kind;

  /// Whether this engine wants the microphone's samples.
  final bool wantsSamples;

  /// Whether `stop` can keep the recording (Whisper on a generation-6 binary).
  final bool keepsAudio;
  final void Function(Float32List samples) push;

  /// How much has been recorded, in ms, on the timeline segment times use.
  final num Function() positionMs;

  /// Commit what remains and return the authoritative final transcript where the engine has one.
  final Future<Stopped> Function([StopOptions? options]) stop;

  /// Drop it; resolves once the engine has let go (the Whisper session is gone), where that takes a trip to Rust.
  final FutureOr<void> Function() cancel;
}

// ---- the backend ---------------------------------------------------------------------------------------------------

/// What the core says without being asked, under the web's event names (`core/events.ts` `listenTo`).
sealed class CaptureEvent {
  const CaptureEvent();

  /// The event's name on the web: `capture://partial` and the rest.
  String get name;
}

/// `capture://partial { text }`: REPLACES the partial line; an empty `text` clears it.
final class CaptureEventPartial extends CaptureEvent {
  const CaptureEventPartial(this.text);
  final String text;

  @override
  String get name => 'capture://partial';
}

/// `capture://segment { text, startMs, endMs }`: appends.
final class CaptureEventSegment extends CaptureEvent {
  const CaptureEventSegment(this.segment);
  final Segment segment;

  @override
  String get name => 'capture://segment';
}

/// `capture://rewound { toMs, segments }`: the tape was wound back, and `segments` is every committed segment that
/// still stands - the listener REPLACES its list with it. (The web's contract lists it; no web caller listens yet.)
final class CaptureEventRewound extends CaptureEvent {
  const CaptureEventRewound({required this.toMs, required this.segments});
  final int toMs;
  final List<Segment> segments;

  @override
  String get name => 'capture://rewound';
}

/// `capture://error { message }`: the capture stopped transcribing; its stop will then reject with the same message.
final class CaptureEventError extends CaptureEvent {
  const CaptureEventError(this.message);
  final String message;

  @override
  String get name => 'capture://error';
}

/// `capture://model-progress { receivedBytes, totalBytes }`: the voice model's download.
final class CaptureEventModelProgress extends CaptureEvent {
  const CaptureEventModelProgress({required this.receivedBytes, required this.totalBytes});
  final int receivedBytes;
  final int totalBytes;

  @override
  String get name => 'capture://model-progress';
}

/// `capture://refine-model-progress { receivedBytes, totalBytes }`: the larger model's download (refine.dart).
final class CaptureEventRefineModelProgress extends CaptureEvent {
  const CaptureEventRefineModelProgress({required this.receivedBytes, required this.totalBytes});
  final int receivedBytes;
  final int totalBytes;

  @override
  String get name => 'capture://refine-model-progress';
}

/// `capture://refine-progress { id, percent }`: how far a pass over note `id`'s recording has got (refine.dart).
final class CaptureEventRefineProgress extends CaptureEvent {
  const CaptureEventRefineProgress({required this.id, required this.percent});
  final String id;
  final num percent;

  @override
  String get name => 'capture://refine-progress';
}

/// A voice model's file, as the core says it (`capture_model_status`).
class ModelStatus {
  const ModelStatus({required this.present, required this.name, required this.path, required this.bytes});

  final bool present;
  final String name;
  final String path;
  final int bytes;

  @override
  bool operator ==(Object other) => other is ModelStatus && other.present == present && other.name == name && other.path == path && other.bytes == bytes;

  @override
  int get hashCode => Object.hash(present, name, path, bytes);

  @override
  String toString() => 'ModelStatus(present: $present, name: $name, path: $path, bytes: $bytes)';
}

/// What `capture_stop` answers on a binary that keeps recordings.
class CaptureStopped {
  const CaptureStopped({required this.transcript, required this.recordedMs});

  final String? transcript;
  final int? recordedMs;
}

/// The native capture, as the engine asks for it: the web's Tauri commands, one method each with the web's
/// arguments, and the web's events as one stream.
///
/// [SimulatedBackend] (simulated.dart) is the one in this folder, and it is for tests. THE REAL ONE COMES LATER
/// (pieces 8C, native commands, and 8D, the dictation microphone), over the Rust core. What it will have to do:
///
/// - [events]: a broadcast stream of what the core emits, in the order it emits it, through
///   `NativeCallable.listener` (docs/STAGES_5_6_8_9.md, stage 8: Rust allocates each buffer, Dart frees it). Every
///   listener hears every event; a listener that comes late hears only what follows.
/// - [start] (`capture_start`): loads the model on the first press after launch, opens a new native session and
///   closes any the last one left (and the Mac's system-audio tap with it). Resolves only once the session can take
///   samples. Rejects with the core's words when it cannot start.
/// - [push] (`capture_push { pcm }`): 16 kHz mono f32 little-endian samples as standard base64 (core/bytes.dart).
///   The engine AWAITS EACH PUSH BEFORE SENDING THE NEXT, because PCM applied out of order is noise; the backend must
///   apply them in the order they were awaited and reject, not drop, one it refuses. If 8D's Kotlin `AudioRecord`
///   pushes into Rust itself over JNI, the session it backs says `wantsSamples: false` and this is never called.
/// - [rewind] (`capture_rewind { toMs }`): winds the tape back; resolves once [CaptureEventRewound] has gone out. It
///   applies to the audio pushed before it, and what is pushed after it records from `toMs`.
/// - [stop] (`capture_stop { recordAs, append }`): drains the last audio, answers the final transcript and, when
///   `recordAs` names a note, keeps the recording as that note's tape (appended to the one it has when `append`) and
///   answers its whole length. Called with no options it is the stop of a binary from before recordings were kept
///   (generation below 6), whose answer is not read. After [CaptureEventError] it rejects with the same message.
/// - [cancel] (`capture_cancel`): drops the session and its audio.
/// - [modelStatus], [fetchModel] (`capture_model_status`, `capture_fetch_model`): the small model's file, and its
///   download, which says [CaptureEventModelProgress] as it comes.
/// - [reassignRecording], [discardRecording] (`capture_reassign_recording`, `capture_discard_recording`): a
///   temporary recording given to the note a command was confirmed for, or thrown away.
/// - [refineModelStatus], [fetchRefineModel], [refine] (`capture_refine_model_status`, `capture_fetch_refine_model`,
///   `capture_refine { id, fromMs, promptTail }`): the larger model and its pass over a kept recording
///   (refine.dart), saying [CaptureEventRefineModelProgress] and [CaptureEventRefineProgress]. A pass asked for
///   while the core is busy rejects with words that say "busy" or "cancelled", which the queue reads.
///
/// It must never open a microphone outside [start] … [stop]/[cancel].
abstract class CaptureBackend {
  Stream<CaptureEvent> get events;

  /// `capture_start`.
  Future<void> start();

  /// `capture_push { pcm }`.
  Future<void> push(String pcm);

  /// `capture_rewind { toMs }`.
  Future<void> rewind(int toMs);

  /// `capture_stop`, with `{ recordAs, append }` or, for an older binary, with nothing.
  Future<CaptureStopped?> stop([StopOptions? options]);

  /// `capture_cancel`.
  Future<void> cancel();

  /// `capture_model_status`.
  Future<ModelStatus> modelStatus();

  /// `capture_fetch_model`.
  Future<ModelStatus> fetchModel();

  /// `capture_reassign_recording { fromId, toId, append }`.
  Future<int?> reassignRecording({required String fromId, required String toId, required bool append});

  /// `capture_discard_recording { id }`.
  Future<void> discardRecording({required String id});

  /// `capture_refine_model_status`.
  Future<({bool present, int bytes})> refineModelStatus();

  /// `capture_fetch_refine_model`.
  Future<({bool present, int bytes})> fetchRefineModel();

  /// `capture_refine { id, fromMs, promptTail }`.
  Future<List<Segment>> refine({required String id, required int fromMs, required String promptTail});
}

/// A backend that can start a capture that guesses at nothing ([CaptureHandlers.guesses]): `capture_start {partials:
/// false}`, the tape kept as a dictation's is. A core from before takes it as a dictation.
abstract interface class GuessFreeStart {
  Future<void> startWithoutGuesses();
}

// ---- the platform's own recogniser ---------------------------------------------------------------------------------

/// One result of a recogniser: its best transcript, and whether it is final (the web's `results[i][0].transcript`
/// and `results[i].isFinal`).
class SpeechResult {
  const SpeechResult({required this.transcript, required this.isFinal});
  final String transcript;
  final bool isFinal;
}

/// A recogniser the platform lends, in the shape of Chrome's `webkitSpeechRecognition`: the engine sets the three
/// switches and the three handlers, and starts and stops it.
abstract class SpeechRecognition {
  set continuous(bool value);
  set interimResults(bool value);
  set lang(String value);
  set onresult(void Function(int resultIndex, List<SpeechResult> results)? handler);
  set onerror(void Function(String error) handler);
  set onend(void Function()? handler);
  void start();
  void stop();
}

// ---- the engine ----------------------------------------------------------------------------------------------------

/// The binary generation whose `capture_stop` keeps the recording (`RECORDING_GENERATION`).
const int _recordingGeneration = 6;

/// The Whisper session that owns the native capture, which there is only one of: every session's pushes land in the
/// same recording. A session that has been replaced (a start that was called off, capture_session.dart) must not
/// keep pushing, or its audio is interleaved chunk by chunk with the live session's, and the tape plays back as a
/// stutter of two copies a few milliseconds apart that Whisper can't make sense of.
Object? _owner;

/// Whether a dictation holds the native capture now: a meeting's live words (meeting_live_words.dart) never take it
/// from one, and never let it go under one.
bool get dictationCapturing => _owner != null;

final Stopwatch _sinceLoad = Stopwatch()..start();
double _performanceNow() => _sinceLoad.elapsedMicroseconds / 1000;

/// The engines, and the voice model, over what this device has.
class CaptureEngine {
  CaptureEngine({
    required this.backend,
    required this.hasNativeGeneration,
    Preferences Function()? preferences,
    Map<String, String> Function()? search,
    double Function()? now,
    this.recognition,
  })  : preferences = preferences ?? (() => core.preferences.value),
        search = search ?? (() => const <String, String>{}),
        now = now ?? _performanceNow;

  /// The native capture, or null where there is none (the web's `isTauri()` false).
  final CaptureBackend? backend;

  /// `core/nativeGeneration.ts` `hasNativeGeneration`: whether the binary is generation `wanted` or newer.
  final Future<bool> Function(int wanted) hasNativeGeneration;

  /// `core/preferences.ts` `preferences()`; the app's own unless another is given.
  final Preferences Function() preferences;

  /// The page's query (`new URLSearchParams(window.location.search)`), by name: `simulate` there at all asks for the
  /// scripted voice, and `say` gives it its phrases (simulated.dart). Empty unless given.
  final Map<String, String> Function() search;

  /// The page's clock in milliseconds (`performance.now()`), for the two engines that keep their own time.
  final double Function() now;

  /// The platform's recogniser, made new for each session (`window.webkitSpeechRecognition`); null where it has none.
  final SpeechRecognition Function()? recognition;

  /// Transfer a stopped temporary recording only after final confirmation.
  Future<int?> reassignRecording(String fromId, String toId, bool append) async {
    final backend = this.backend;
    if (backend == null) return null;
    return backend.reassignRecording(fromId: fromId, toId: toId, append: append);
  }

  /// A cancelled/rejected command has no note to own its temporary recording.
  Future<void> discardRecording(String id) async {
    await backend?.discardRecording(id: id);
  }

  // ---- the model ---------------------------------------------------------------------------------------------------

  /// Make sure the model is on the phone, downloading it if not.
  ///
  /// Called when the app opens as well as when a capture starts, so the download - about 60 MB - happens the first
  /// time the app is opened rather than the first time the side key is held. A note started on a whim that has to
  /// wait for a download is a note that does not get started.
  Future<ModelStatus?> ensureModel([void Function(int received, int total)? onProgress]) async {
    final backend = this.backend;
    if (backend == null) return null;
    final status = await backend.modelStatus();
    if (status.present) return status;
    // Local only: nothing is downloaded, and the recorder says why.
    if (preferences().localOnly) {
      throw Exception('Local only is on, so the voice model was not downloaded. Turn it off in Settings to get it.');
    }

    final unlisten = backend.events.listen((event) {
      if (event is CaptureEventModelProgress) onProgress?.call(event.receivedBytes, event.totalBytes);
    });
    try {
      return await backend.fetchModel();
    } finally {
      unawaited(unlisten.cancel());
    }
  }

  // ---- engines -----------------------------------------------------------------------------------------------------

  Future<CaptureSession> startCapture(CaptureHandlers handlers) async {
    final query = search();
    if (query.containsKey('simulate')) return simulated(handlers, search: query, now: now);
    if (backend != null) return _whisper(handlers, backend!);
    return _browser(handlers);
  }

  Future<CaptureSession> _whisper(CaptureHandlers handlers, CaptureBackend backend) async {
    final listening = backend.events.listen((event) {
      switch (event) {
        case CaptureEventPartial(:final text):
          handlers.onPartial(text);
        case CaptureEventSegment(:final segment):
          handlers.onSegment(segment);
        case CaptureEventError(:final message):
          handlers.onError(message);
        case CaptureEventRewound() || CaptureEventModelProgress() || CaptureEventRefineModelProgress() || CaptureEventRefineProgress():
          break;
      }
    });
    void unlistenAll() => unawaited(listening.cancel());

    await ensureModel(handlers.onModelProgress);

    /*
     * No sample can arrive before the start resolves: the session is only handed back after it. Starting loads the
     * model on the first press after launch, which takes long enough to swallow the first words - and the first
     * words of a note are usually its subject - so the recorder holds what the microphone hears until then and hands
     * it all over at once (capture_session.dart).
     */
    /// Samples handed over, which is exactly the recording Rust holds once the chain drains.
    var recorded = 0;
    // Pushes are chained so they reach Rust in order; two in flight are not guaranteed to land in the order they
    // were sent.
    var chain = Future<void>.value();
    final me = Object();
    void send(Float32List samples) {
      if (!identical(_owner, me)) return;
      recorded += samples.length;
      // Bytes as base64 (core/bytes.dart), which is what the core's `capture_push` reads.
      final pcm = toBase64(samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes));
      // Asked again when its turn comes: a push still queued when the session was cancelled or stopped is one Rust
      // would refuse, or, if another session has started since, land in the wrong recording.
      chain = chain.then<void>((_) async {
        if (identical(_owner, me)) await backend.push(pcm);
      }).catchError((Object error) => handlers.onError(_thrown(error)));
    }

    // Asked rather than assumed: this can run on a binary from before recordings were kept, whose stop takes no
    // arguments.
    final keepsAudio = await hasNativeGeneration(_recordingGeneration);

    try {
      if (!handlers.guesses && backend is GuessFreeStart) {
        await (backend as GuessFreeStart).startWithoutGuesses();
      } else {
        await backend.start();
      }
    } catch (_) {
      unlistenAll();
      rethrow;
    }
    // The native capture is this session's from here; any earlier session's pushes stop landing in it.
    _owner = me;

    return CaptureSession(
      kind: EngineKind.whisper,
      wantsSamples: true,
      keepsAudio: keepsAudio,
      push: send,
      positionMs: () => (recorded * 1000) / 16000,
      stop: ([options]) async {
        await chain;
        if (identical(_owner, me)) _owner = null;
        try {
          if (!keepsAudio) {
            await backend.stop();
            return const Stopped(recordedMs: null, transcript: null);
          }
          final finished = await backend.stop(StopOptions(recordAs: options?.recordAs, append: options?.append ?? false));
          final transcript = finished?.transcript?.trim() ?? '';
          return Stopped(recordedMs: finished?.recordedMs, transcript: transcript.isEmpty ? null : transcript);
        } finally {
          unlistenAll();
        }
      },
      cancel: () {
        unlistenAll();
        // A session that no longer owns the native capture leaves it alone: cancelling would end the newer
        // session's.
        if (!identical(_owner, me)) return Future<void>.value();
        _owner = null;
        return backend.cancel().then<void>((_) {}, onError: (Object _) {});
      },
    );
  }

  /// The platform's own recogniser, for developing on a laptop.
  CaptureSession _browser(CaptureHandlers handlers) {
    final make = this.recognition;
    if (make == null) throw Exception('Voice notes need the Ghost.md app; this browser has no speech recognition.');

    final recognition = make();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = 'en-US';
    final startedAt = now();
    num lastEnd = 0;
    var running = true;
    void Function()? settle;
    double since() => now() - startedAt;

    recognition.onresult = (resultIndex, results) {
      var interim = '';
      for (var i = resultIndex; i < results.length; i += 1) {
        final result = results[i];
        final text = result.transcript;
        if (result.isFinal) {
          final at = since();
          handlers.onSegment(Segment(text: text.trim(), startMs: _ms(lastEnd), endMs: _ms(at)));
          lastEnd = at;
        } else {
          interim += text;
        }
      }
      handlers.onPartial(interim.trim());
    };
    recognition.onerror = (error) => handlers.onError(error);
    // A "continuous" session ends on its own after a silence; restart it until the person actually stops.
    recognition.onend = () {
      if (running) {
        recognition.start();
      } else {
        settle?.call();
      }
    };
    recognition.start();

    return CaptureSession(
      kind: EngineKind.browser,
      wantsSamples: false,
      keepsAudio: false,
      push: (_) {},
      positionMs: since,
      stop: ([options]) {
        final stopped = Completer<Stopped>();
        running = false;
        settle = () {
          if (!stopped.isCompleted) stopped.complete(const Stopped(recordedMs: null, transcript: null));
        };
        recognition.stop();
        return stopped.future;
      },
      cancel: () {
        running = false;
        recognition.stop();
      },
    );
  }
}

/// A time on a recording's timeline as a phrase carries it: whole milliseconds.
int _ms(num at) => at.round();

/// A thrown thing as JavaScript's `String(error)` says it: a string as it is, an error as "Error: " and its message.
String _thrown(Object failure) {
  if (failure is String) return failure;
  final text = failure.toString();
  for (final lead in const ['Exception: ', 'Bad state: ']) {
    if (text.startsWith(lead)) return 'Error: ${text.substring(lead.length)}';
  }
  return text;
}
