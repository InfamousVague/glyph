/// The recorder, as the app holds it: one object that `lib/root` constructs and the recorder's screens are drawn
/// over. It carries the engine (engine.dart), the better words' queue (refine.dart), the meeting's store
/// (meeting_live.dart) and the voice model's fetch (voice_model.dart), and everything else the web's recorder reaches
/// by importing a module: the note store, the phone's host, the preferences, the tapes' ids, the review, the
/// summaries, the plugins' spoken formattings and tips, the shared links and the on-device reader of a command.
///
/// There is no one web file this ports. On the web each of those is a module the screen imports
/// (`src/app/capture/CaptureScreen.tsx`'s first sixty lines), wired to the page as it loads; `App.tsx` starts the
/// voice model's fetch (`useVoiceModel`) and the refine queue (`startRefining`), and `shell/useCaptureRoute.ts` opens
/// the screens. Here the modules are this object's fields, each with the web's name, so the screen reads
/// `recorder.store.getNote(…)` where the web reads `getNote(…)`, and a test passes a [Recorder] made over
/// `SimulatedBackend` and a store in memory.
///
/// No always-on microphone: making a [Recorder] opens nothing. [Recorder.start] fetches the voice model, which is a
/// file, and wires the refine queue; a microphone is opened only by a recorder screen that is on screen
/// (capture_session.dart), and "Hey Ghost" is read only from what that screen hears (live_route.dart).
///
/// What is not here yet, and what stands in:
/// - the native capture and the Kotlin microphone (pieces 8C and 8D): [Recorder.engine]'s backend and
///   [Recorder.openMicrophone] are whatever `lib/root` passes; with neither, the screen says it could not start;
/// - a note's tape in the library (`lib/core/library.dart` says it is the recorder's still): [RecorderStore] is the
///   seam, and [LibraryRecorderStore] answers it over a `NoteLibrary` with the library's `apply`, until the core's
///   `set_note_recording` is asked from Dart;
/// - the review after a recording and the summaries (`lib/ai`): [Recorder.reviewAvailable] answers no and
///   [Recorder.enqueueSummary] does nothing unless given.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../core/library.dart';
import '../core/note.dart';
import '../core/preferences.dart' as core show preferences;
import '../core/preferences.dart' show Preferences;
import '../editor/media/clip_refs.dart' show TapeIds, freshTapeId;
import 'audio.dart';
import 'engine.dart';
import 'instruction_intent.dart' show InferenceRun;
import 'landing.dart';
import 'meeting_live.dart';
import 'refine.dart';
import 'spoken/inline.dart' show SpokenFormat;
import 'system_sound.dart';
import 'take_writer.dart';
import 'tips.dart' show Tip;
import 'voice_model.dart';

/// The note store, as the recorder asks it (`core/store.ts`): the take writer's six, the list the commands' names
/// are read from, and a tape's length and phrases written beside its note.
abstract class RecorderStore implements TakeStore {
  /// Every note (`listNotes`).
  Future<List<Note>> listNotes();

  /// The recording's length and its phrases, kept with the note (`setNoteRecording`): the note as stored, or null
  /// when there is no such note.
  Future<Note?> setNoteRecording(String id, int? recordingMs, List<Segment> segments);
}

/// [RecorderStore] over the app's library (`lib/core/library.dart`).
///
/// A command's change is the library's own `applyCommandMutation` (the core's `apply_command`), which keeps it for
/// the Undo a landing offers in the note that opens after Done (`lib/root/note_desk.dart`, through the library's
/// `undoCommandMutation`).
///
/// What differs from the web's store: a tape's length and phrases are written with the library's `apply` (the web's
/// `applyNote`) onto the note read whole, where the web has `set_note_recording`, a write of its own that touches
/// nothing else.
class LibraryRecorderStore implements RecorderStore {
  LibraryRecorderStore(this.library, {String Function()? newId}) : _newId = newId;

  final NoteLibrary library;
  final String Function()? _newId;
  int _ids = 0;

  @override
  Future<List<Note>> listNotes() async => List<Note>.of(library.value);

  @override
  Future<Note?> getNote(String id) => library.get(id);

  @override
  String newNoteId() => _newId?.call() ?? 'n-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_ids += 1).toRadixString(36)}';

  @override
  Future<Note> createNote(String id, String body, [NoteSource source = NoteSource.editor]) async {
    if (await library.get(id) != null) throw StateError('the note id already exists');
    return library.createNote(body, source: source, id: id);
  }

  @override
  Future<void> deleteNote(String id) => library.destroy(id);

  @override
  Future<Note> updateNote(String id, String body, int expectedRevision) => library.update(id, body, expectedRevision);

  @override
  Future<CommandMutationResult> applyCommandMutation(CommandMutationRequest request) => library.applyCommandMutation(request);

  @override
  Future<Note?> setNoteRecording(String id, int? recordingMs, List<Segment> segments) async {
    final note = await library.get(id);
    if (note == null) return null;
    return library.apply(Note(
      id: note.id,
      body: note.body,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      source: note.source,
      sourceName: note.sourceName,
      starred: note.starred,
      archivedAt: note.archivedAt,
      recordingMs: recordingMs,
      segments: List<Segment>.unmodifiable(segments),
      formatted: note.formatted,
      formattedFor: note.formattedFor,
      formattedModel: note.formattedModel,
      path: note.path,
      revision: note.revision,
    ));
  }
}

/// The phone, as the recorder asks it (`core/host.ts`, `core/platform.ts`, `core/haptics.ts`): each a function, each
/// with an answer for a device that has no host.
class RecorderHost {
  const RecorderHost({
    this.isLocked = _no,
    this.setCapturing = _setCapturing,
    this.endCapture = _endCapture,
    this.onScreenOff = _never,
    this.haptic = _quiet,
    this.isAndroid = false,
  });

  /// Whether the phone is locked, the recorder drawn over its lock screen (`isLocked`).
  final bool Function() isLocked;

  /// The screen stays on while a recording runs, and pressing the side key (which turns it off) stops it
  /// (`setCapturing`): answers whether this phone stops a recording that way.
  final bool Function(bool on) setCapturing;

  /// The recording is over: a locked phone goes back behind its lock screen (`endCapture`).
  final void Function(bool locked) endCapture;

  /// Hears the screen going off while a recording runs (`answerHost('screenOff', …)`); answers the way to stop.
  final VoidCallback Function(VoidCallback listener) onScreenOff;

  /// The phone's buzz, by the web's word for it: `light`, `medium`, `selection`, `success`, `warning`, `error`
  /// (`fireNativeHaptic`).
  final void Function(String kind) haptic;

  /// `core/platform.ts` `isAndroid`: a phone's "Meeting instead" hands the microphone to the service, a Mac's turns
  /// the recorder into the meeting.
  final bool isAndroid;

  static bool _no() => false;
  static bool _setCapturing(bool on) => false;
  static void _endCapture(bool locked) {}
  static VoidCallback _never(VoidCallback listener) => () {};
  static void _quiet(String kind) {}
}

/// A spoken instruction about the note being continued ("hey Ghost, fix the spelling"): run on it once it is open
/// (`SpokenAsk`, `src/app/capture/CaptureScreen.tsx`). [kind] is the web's word for the run (`RunKind`), `ask` for
/// free words, which are [instruction].
@immutable
class SpokenAsk {
  const SpokenAsk({required this.kind, this.instruction});

  final String kind;
  final String? instruction;

  @override
  bool operator ==(Object other) => other is SpokenAsk && other.kind == kind && other.instruction == instruction;

  @override
  int get hashCode => Object.hash(kind, instruction);

  @override
  String toString() => '{kind: $kind${instruction == null ? '' : ', instruction: $instruction'}}';
}

/// What the review after a recording is handed (`ReviewHandoff`, `src/app/ai/review.ts`): the note, the better
/// words' job it runs in place of the queue, every phrase heard, what each command did, and the other notes touched.
@immutable
class ReviewHandoff {
  const ReviewHandoff({required this.noteId, required this.job, required this.heard, required this.commands, required this.touched});

  final String noteId;
  final RefineJob? job;
  final String heard;
  final List<String> commands;
  final List<String> touched;
}

/// How a recording ended, as the recorder tells whoever opened it (`onFinish`): [note] is the saved note, or null
/// when the capture was cancelled or nothing was said.
typedef CaptureFinish = void Function(Note? note, bool locked, {ReviewHandoff? review, SpokenAsk? ask, CaptureLanding? landing});

final Stopwatch _sinceLoad = Stopwatch()..start();
double _performanceNow() => _sinceLoad.elapsedMicroseconds / 1000;
bool _never(String id) => false;
List<Tip> _noTips(String? recent) => const [];
List<SpokenFormat> _noFormats() => const [];

/// The recorder: see the library's comment.
class Recorder {
  Recorder({
    required this.engine,
    required this.store,
    this.host = const RecorderHost(),
    this.refining,
    this.meetingLive,
    VoiceModel? voiceModel,
    Preferences Function()? preferences,
    void Function(Preferences Function(Preferences now) change)? setPreferences,
    this.tapes,
    this.openMicrophone,
    bool? native,
    bool? simulate,
    Future<CaptureSession> Function(CaptureHandlers handlers)? startCapture,
    void Function(RefineJob job)? enqueueRefine,
    void Function(bool live)? setRecorderLive,
    Future<bool> Function()? reviewAvailable,
    void Function(String id, String kind)? enqueueSummary,
    this.spokenFormats = _noFormats,
    this.pluginTips = _noTips,
    this.published = _never,
    this.startInference,
    this.systemSound,
    this.canRecordMeeting = false,
    double Function()? now,
    int Function()? wallNow,
    this.locale,
    this.warn,
  })  : voiceModel = voiceModel ?? VoiceModel(native: engine.backend != null, ensureModel: engine.ensureModel),
        preferences = preferences ?? (() => core.preferences.value),
        setPreferences = setPreferences ?? core.preferences.update,
        native = native ?? engine.backend != null,
        simulate = simulate ?? engine.search().containsKey('simulate'),
        startCapture = startCapture ?? engine.startCapture,
        enqueueRefine = enqueueRefine ?? refining?.enqueueRefine ?? ((_) {}),
        setRecorderLive = setRecorderLive ?? refining?.setRecorderLive ?? ((_) {}),
        reviewAvailable = reviewAvailable ?? (() async => false),
        enqueueSummary = enqueueSummary ?? ((_, _) {}),
        now = now ?? _performanceNow,
        wallNow = wallNow ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// The transcriber (engine.dart): Whisper in the core, or the scripted voice.
  final CaptureEngine engine;

  /// The notes (`core/store.ts`).
  final RecorderStore store;

  /// The phone (`core/host.ts`).
  final RecorderHost host;

  /// The better words' queue (refine.dart), or null where there is none to run.
  final Refining? refining;

  /// The meeting the phone's service is recording (meeting_live.dart), or null where there is no service.
  final MeetingLive? meetingLive;

  /// The voice model's fetch, which the launch screen and Settings follow (voice_model.dart).
  final VoiceModel voiceModel;

  /// `preferences()` and `setPreferences()` (`core/preferences.ts`); the app's own unless others are given.
  final Preferences Function() preferences;
  final void Function(Preferences Function(Preferences now) change) setPreferences;

  /// The tape each note holds (`core/clips.ts` `tapeId`, `setTapeId`), or null where nothing keeps them.
  final TapeIds? tapes;

  /// Opens the microphone (audio.dart `openMicrophone` over the native input), or null where there is none: then the
  /// engine must be one that wants no samples (the scripted voice).
  final Future<Microphone> Function(MicrophoneHandlers handlers)? openMicrophone;

  /// Whether there is a native core, whose engine wants the microphone's samples (`isTauri()`), and whether the
  /// scripted voice was asked for (`?simulate`).
  final bool native;
  final bool simulate;

  /// `startCapture` (engine.dart); the engine's own unless another is given.
  final Future<CaptureSession> Function(CaptureHandlers handlers) startCapture;

  /// `enqueueRefine` and `setRecorderLive` (refine.dart); [refining]'s own unless others are given.
  final void Function(RefineJob job) enqueueRefine;
  final void Function(bool live) setRecorderLive;

  /// Whether the review after a recording can run (`ai/review.ts` `reviewAvailable`). No, until `lib/ai` has one.
  final Future<bool> Function() reviewAvailable;

  /// Asks for a note's summary: `recording` or `meeting` (`ai/summaries.ts` `enqueueSummary`).
  final void Function(String id, String kind) enqueueSummary;

  /// The switched-on plugins' formattings that can be said like bold (`plugins.formats()`, each with a `cue`).
  final List<SpokenFormat> Function() spokenFormats;

  /// The switched-on plugins' tips for a pause (`plugins.tips(recent)`).
  final List<Tip> Function(String? recent) pluginTips;

  /// Whether a note has a shared link (`share/share.ts` `linkFor(id) !== null`): over the lock screen such a note
  /// is never written to.
  final bool Function(String id) published;

  /// The on-device model's reading of a command the rules could not place (`instructionIntent.ts`
  /// `inferInstruction`), or null where there is no model to ask: then the reader says it is unavailable.
  final InferenceRun Function(String words)? startInference;

  /// The Mac's own sound for a meeting (system_sound.dart), or null where it cannot be had.
  final SystemSound? systemSound;

  /// Whether a meeting can be recorded on this device (meeting.dart `canRecordMeeting`, asked once by `lib/root`):
  /// the card of things to say offers "Meeting instead" where it can.
  final bool canRecordMeeting;

  /// The page's clock in milliseconds (`performance.now()`), and the wall's (`Date.now()`).
  final double Function() now;
  final int Function() wallNow;

  /// The locale a meeting's title is written in (meeting.dart `meetingTitle`).
  final String? locale;

  /// Where a failure that loses nothing is written (`console.warn`).
  final void Function(String line)? warn;

  VoidCallback? _stopRefining;
  final Set<VoidCallback> _visible = <VoidCallback>{};

  /// A fresh tape id (`core/clips.ts` `freshTapeId`).
  String newTapeId() => freshTapeId();

  /// As the app opens: the voice model is fetched if it is not on the phone, and the better words' queue is wired to
  /// the notes ([notesChanged] is told when a pass rewrote one). Opens no microphone.
  void start({VoidCallback? notesChanged}) {
    voiceModel.start();
    _stopRefining = refining?.startRefining(notesChanged ?? () {});
  }

  /// The app's lifecycle, fed from `lib/root`'s `WidgetsBindingObserver`: back on screen, the meeting's state and
  /// whether Ghost.md may notify are read again (the web's `visibilitychange`), and whoever asked to hear of it is
  /// told.
  void lifecycle(AppLifecycleState state) {
    meetingLive?.visibilityChanged();
    if (state != AppLifecycleState.resumed) return;
    for (final listener in _visible.toList()) {
      listener();
    }
  }

  /// Calls [listener] each time the app comes back to the screen; answers the way to stop. What a [VoiceModel] and a
  /// [Refining] are given as their `onVisible`.
  VoidCallback onVisible(VoidCallback listener) {
    _visible.add(listener);
    return () => _visible.remove(listener);
  }

  /// The notes changed (`NOTES_CHANGED`): a meeting's note may have been written by the service.
  void notesChanged() => meetingLive?.notesChanged();

  void dispose() {
    _stopRefining?.call();
    _stopRefining = null;
    voiceModel.close();
    _visible.clear();
  }
}
