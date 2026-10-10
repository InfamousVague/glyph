import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/audio.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/landing.dart';
import 'package:ghost_md/capture/place.dart' show Placing;
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/capture/refine.dart' show RefineJob;
import 'package:ghost_md/capture/simulated.dart';
import 'package:ghost_md/capture/spoken/extras.dart' show setLinkTitles;
import 'package:ghost_md/capture/spoken/inline.dart' show SpokenFormat, setSpokenFormats;
import 'package:ghost_md/capture/take_writer.dart';
import 'package:ghost_md/capture/ui/capture_cards.dart';
import 'package:ghost_md/capture/ui/capture_screen.dart';
import 'package:ghost_md/capture/ui/live_page.dart';
import 'package:ghost_md/capture/ui/say_card.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences, preferences;
import 'package:ghost_md/app/style_sheets.dart';
import 'package:glacier/glacier.dart' show debugFixturePixelRatio, loadTokenSheet;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/marks/wisp_motion.dart' show wispNow;
import 'package:ghost_md/editor/media/clip_refs.dart' show TapeIds;

import 'package:ghost_md/shell/root_stamps.dart';

/// What the web's recorder tests stand on, for the port of them (`src/app/capture/CaptureScreen.test.tsx`).
///
/// The web mocks three modules: `engine.ts` (a session it drives by hand, and lists of the recordings discarded and
/// moved), `refine.ts` (the jobs asked for) and `ai/summaries.ts` (the summaries asked for), over the real store on
/// `localStorage`. Here the same four are a [Recorder]'s own seams. The engine is a real `CaptureEngine` over a
/// [SimulatedBackend] - whose kept recordings are what `discardRecording` and `reassignRecording` are asked of - and
/// its `startCapture` is the hand-driven session the web's tests configure (`capture.session`, `capture.handlers`),
/// since a case says exactly which phrase was committed when and what the stop answered. The cases that let the
/// scripted voice speak on its clock, through the engine's own Whisper path, are in `simulated_voice_test.dart`.

/// The notes, in memory, as the web's store keeps them in `localStorage` (`core/store.ts`).
class MemoryNotes implements RecorderStore {
  final List<Note> _notes = [];
  int _clock = 0;
  int _ids = 0;

  /// Held, the notes a command can name are not read until it is let go.
  Future<void>? held;

  int _now() => _clock += 1;

  @override
  String newNoteId() => 'n-test-${_ids += 1}';

  @override
  Future<List<Note>> listNotes() async {
    if (held != null) await held;
    final sorted = <Note>[];
    for (final note in _notes) {
      var at = sorted.length;
      while (at > 0 && sorted[at - 1].updatedAt < note.updatedAt) {
        at -= 1;
      }
      sorted.insert(at, note);
    }
    return sorted;
  }

  /// The notes now, with nothing held: what a test reads.
  List<Note> get all => [..._notes]..sort((a, b) => b.updatedAt - a.updatedAt);
  List<String> get bodies => [for (final note in all) note.body];
  Note? note(String id) => _notes.where((note) => note.id == id).firstOrNull;
  String? body(String id) => note(id)?.body;

  @override
  Future<Note?> getNote(String id) async => note(id);

  @override
  Future<Note> createNote(String id, String body, [NoteSource source = NoteSource.editor]) async => create(id, body, source);

  /// `createNote`, at once, for a test setting up.
  Note create(String id, String body, [NoteSource source = NoteSource.editor]) {
    if (_notes.any((note) => note.id == id)) throw StateError('the note id already exists');
    final now = _now();
    final made = Note(id: id, body: body, createdAt: now, updatedAt: now, source: source);
    _notes.insert(0, made);
    return made;
  }

  @override
  Future<void> deleteNote(String id) async => _notes.removeWhere((note) => note.id == id);

  @override
  Future<Note> updateNote(String id, String body, int expectedRevision) async {
    final at = _notes.indexWhere((note) => note.id == id);
    if (at < 0 || _notes[at].revision != expectedRevision) throw StateError('the note was deleted or changed');
    return _notes[at] = _with(_notes[at], body: body, updatedAt: _now(), revision: expectedRevision + 1);
  }

  @override
  Future<CommandMutationResult> applyCommandMutation(CommandMutationRequest request) async {
    final at = _notes.indexWhere((note) => note.id == request.noteId);
    final current = at < 0 ? null : _notes[at];
    final matches = request.beforeRevision == null
        ? current == null && request.beforeBody == null
        : current != null && current.revision == request.beforeRevision && current.body == request.beforeBody;
    if (!matches) return CommandMutationResultConflict(current: current);
    final now = _now();
    final saved = current != null
        ? _with(current, body: request.afterBody, updatedAt: now, revision: current.revision + 1)
        : Note(id: request.noteId, body: request.afterBody, createdAt: now, updatedAt: now, source: request.source);
    if (at >= 0) _notes.removeAt(at);
    _notes.insert(0, saved);
    return CommandMutationResultApplied(mutationId: request.mutationId, note: saved);
  }

  @override
  Future<Note?> setNoteRecording(String id, int? recordingMs, List<Segment> segments) async => record(id, recordingMs, segments);

  /// `setNoteRecording`, at once, for a test setting up.
  Note? record(String id, int? recordingMs, List<Segment> segments) {
    final at = _notes.indexWhere((note) => note.id == id);
    if (at < 0) return null;
    return _notes[at] = _with(_notes[at], recordingMs: () => recordingMs, segments: () => [...segments]);
  }

  static Note _with(Note note, {String? body, int? updatedAt, int? revision, int? Function()? recordingMs, List<Segment>? Function()? segments}) => Note(
        id: note.id,
        body: body ?? note.body,
        createdAt: note.createdAt,
        updatedAt: updatedAt ?? note.updatedAt,
        source: note.source,
        sourceName: note.sourceName,
        starred: note.starred,
        archivedAt: note.archivedAt,
        recordingMs: recordingMs == null ? note.recordingMs : recordingMs(),
        segments: segments == null ? note.segments : segments(),
        path: note.path,
        revision: revision ?? note.revision,
      );
}

/// The scripted voice as the native capture, keeping count of what the recorder asked of its recordings.
class CountingBackend extends SimulatedBackend {
  CountingBackend({super.search, super.now});

  /// The sound of a take nobody kept, by the note id it was recorded under.
  final List<String> discarded = [];

  /// A take's sound moved to the note a command went to: from, to, and whether it went on the end.
  final List<(String, String, bool)> reassigned = [];

  @override
  Future<void> discardRecording({required String id}) async {
    discarded.add(id);
    await super.discardRecording(id: id);
  }

  @override
  Future<int?> reassignRecording({required String fromId, required String toId, required bool append}) async {
    reassigned.add((fromId, toId, append));
    await super.reassignRecording(fromId: fromId, toId: toId, append: append);
    return 3000;
  }
}

/// One call of `onFinish`.
typedef Finished = ({Note? note, bool locked, ReviewHandoff? review, SpokenAsk? ask, CaptureLanding? landing});

/// The stand-in session's stop: what it was asked, and what it answers.
typedef StopAnswer = FutureOr<Stopped> Function(StopOptions? options);

/// A recorder under test: the web file's `capture` object, its mocks and its `beforeEach`.
class Capture {
  /// [script] is the scripted voice's query (`simulate`, `say`): given, nothing is driven by hand. The engine's own
  /// Whisper path runs over the [SimulatedBackend] speaking that script on the test's clock, with a microphone that
  /// hands it silence a tenth of a second at a time, so the counter runs.
  Capture(this.tester, {this.script}) {
    backend = CountingBackend(search: script ?? const {}, now: clock);
    wispNow = clock;
    setSpokenFormats(const []);
    setLinkTitles(const []);
    addTearDown(() {
      setSpokenFormats(const []);
      setLinkTitles(const []);
    });
  }

  final WidgetTester tester;
  final Map<String, String>? script;
  final MemoryNotes notes = MemoryNotes();
  late final CountingBackend backend;
  late final TapeIds tapes = TapeIds(MemoryStored());
  Preferences prefs = Preferences.defaults;

  /// The handlers the session was started with, once it has been (`capture.handlers`).
  CaptureHandlers? handlers;

  /// Whether a session can be had at all (`capture.session = null` on the web).
  bool configured = true;
  bool keepsAudio = false;
  num Function() positionMs = () => 2600;

  /// Native stop drains the final decode after the page has stopped receiving phrase events. This is intentionally
  /// longer than the event.
  StopAnswer stop = (_) => const Stopped(recordedMs: null, transcript: 'add to the note labeled Go pack sunscreen');
  final List<StopOptions?> stops = [];
  int cancels = 0;

  /// The better words' jobs asked for at Done, and the summaries.
  final List<RefineJob> refines = [];
  final List<(String, String)> summaries = [];

  /// The phone: locked or not, a phone or the Mac, and the plugins' said formattings and shared notes.
  bool locked = false;
  bool android = false;
  bool review = false;
  List<SpokenFormat> formats = const [SpokenFormat(word: 'spoiler', delimiter: '||')];
  final Set<String> shared = {};
  VoidCallback? screenOff;

  final List<Finished> finished = [];
  int meetings = 0;

  /// The phone's status bar and its foot, as `pumpApp` gives them; a case held to the web page, which has neither,
  /// sets none.
  EdgeInsets insets = const EdgeInsets.only(top: 36, bottom: 20);

  /// The window's device pixels to the logical one, and the ratio of the page the case's rectangles were read from
  /// (`pumpScreen`): a desktop Chromium's unless a case was measured on a phone.
  double ratio = 2;
  double measuredAt = 1;

  /// Set, the recorder's clock stands still there: the scripted voice says no more and the microphone hands nothing
  /// on, as the measuring script stops the page's clock at the moment it reads.
  double? frozen;

  double clock() => frozen ?? tester.binding.clock.now().microsecondsSinceEpoch / 1000;
  void freeze() => frozen = clock();

  /// `keeping(recordedMs, transcript)`: the stand-in keeps its sound, as Whisper does on a binary that keeps
  /// recordings.
  void keeping(int recordedMs, String? transcript) {
    keepsAudio = true;
    stop = (_) => Stopped(recordedMs: recordedMs, transcript: transcript);
  }

  /// The stop answers this transcript and keeps no sound.
  void stopSays(String? transcript) => stop = (_) => Stopped(recordedMs: null, transcript: transcript);

  late final Recorder recorder = Recorder(
    engine: CaptureEngine(backend: backend, hasNativeGeneration: (_) async => true, preferences: () => prefs, now: clock),
    store: notes,
    host: RecorderHost(
      isLocked: () => locked,
      setCapturing: (_) => false,
      endCapture: (_) {},
      onScreenOff: (listener) {
        screenOff = listener;
        return () => screenOff = null;
      },
      isAndroid: false,
    ),
    preferences: () => prefs,
    setPreferences: (change) => prefs = change(prefs),
    tapes: tapes,
    native: script != null,
    simulate: false,
    openMicrophone: script == null
        ? null
        : (given) async {
            final chunks = Timer.periodic(const Duration(milliseconds: 100), (_) {
              if (frozen != null) return;
              given.onChunk(Float32List(1600));
              given.onLevel(0);
            });
            return Microphone(stop: chunks.cancel, deviceRate: 16000, state: () => AudioContextState.running);
          },
    startCapture: script != null ? null : (given) async {
      handlers = given;
      if (!configured) throw Exception('test capture session was not configured');
      return CaptureSession(
        kind: EngineKind.whisper,
        wantsSamples: false,
        keepsAudio: keepsAudio,
        push: (_) {},
        positionMs: () => positionMs(),
        stop: ([options]) async {
          stops.add(options);
          return stop(options);
        },
        cancel: () => cancels += 1,
      );
    },
    enqueueRefine: refines.add,
    setRecorderLive: (_) {},
    reviewAvailable: () async => review,
    enqueueSummary: (id, kind) => summaries.add((id, kind)),
    spokenFormats: () => formats,
    published: shared.contains,
    now: clock,
    wallNow: () => tester.binding.clock.now().millisecondsSinceEpoch,
  );

  /// The recorder for a phone, where "Meeting instead" hands over to the service.
  Recorder get _forPlatform => android
      ? Recorder(
          engine: recorder.engine,
          store: notes,
          host: RecorderHost(isLocked: () => locked, isAndroid: true),
          preferences: recorder.preferences,
          setPreferences: recorder.setPreferences,
          tapes: tapes,
          native: false,
          simulate: false,
          startCapture: recorder.startCapture,
          enqueueRefine: refines.add,
          setRecorderLive: (_) {},
          reviewAvailable: recorder.reviewAvailable,
          enqueueSummary: recorder.enqueueSummary,
          spokenFormats: recorder.spokenFormats,
          published: recorder.published,
          now: clock,
          wallNow: recorder.wallNow,
        )
      : recorder;

  /// `render(<CaptureScreen … />)`, and the session started.
  Future<void> open({String? noteId, Placing? placing, bool meeting = false, bool offersMeeting = false, bool fromAssistant = false, int stopRequests = 0, Size size = const Size(390, 844), String theme = 'light', bool wait = true}) async {
    handlers = null;
    final screen = CaptureScreen(
      key: ValueKey('capture-${_opened += 1}'),
      recorder: _forPlatform,
      fromAssistant: fromAssistant,
      stopRequests: stopRequests,
      noteId: noteId,
      placing: placing,
      meeting: meeting,
      onMeeting: offersMeeting ? () => meetings += 1 : null,
      onFinish: (note, locked, {review, ask, landing}) => finished.add((note: note, locked: locked, review: review, ask: ask, landing: landing)),
    );
    await pumpScreen(tester, screen, size: size, prefs: prefs.copyWith(theme: theme), insets: insets, ratio: ratio, measuredAt: measuredAt);
    if (wait && script == null) await until(() => handlers != null);
    await settle();
  }

  int _opened = 0;

  /// `cleanup()`: the recorder taken off the screen.
  Future<void> close() async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// A few turns of the loop, for what was awaited to land and be drawn.
  Future<void> settle([int turns = 4]) async {
    for (var i = 0; i < turns; i += 1) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  /// `waitFor`: the clock run until [holds], or [timeout] ms.
  Future<void> until(bool Function() holds, {int timeout = 6000, String? reason}) async {
    for (var waited = 0; waited < timeout; waited += 20) {
      if (holds()) return;
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(holds(), isTrue, reason: reason ?? 'waited $timeout ms');
  }

  /// A phrase committed, as Whisper's `capture://segment` would hand it over.
  Future<void> say(String text, int startMs) async {
    handlers!.onSegment(Segment(text: text, startMs: startMs, endMs: startMs + 900));
    await settle();
  }

  /// Several phrases in one turn of the loop.
  Future<void> sayTogether(List<Segment> segments) async {
    segments.forEach(handlers!.onSegment);
    await settle();
  }

  Future<void> partial(String text) async {
    handlers!.onPartial(text);
    await settle(2);
  }

  Future<void> tap(Finder finder) async {
    await tester.tap(finder.first, warnIfMissed: false);
    await settle();
  }

  /// Done, tapped.
  Future<void> done() => tap(find.byKey(CaptureScreen.doneKey));
  Future<void> discard() => tap(find.byKey(CaptureScreen.discardKey));

  /// Done, and the recorder finished.
  Future<Finished> doneAndFinished({int timeout = 6000}) async {
    final before = finished.length;
    await done();
    await until(() => finished.length > before, timeout: timeout, reason: 'onFinish was not called');
    return finished.last;
  }

  Future<void> untilFinished([int times = 1, int timeout = 6000]) => until(() => finished.length >= times, timeout: timeout, reason: 'onFinish was not called');

  // ---- what is on the screen ---------------------------------------------------------------------------------------

  /// The page the recorder draws: the note's Markdown as it reads now.
  String page() {
    final found = find.byType(LivePage);
    return found.evaluate().isEmpty ? '' : tester.state<LivePageState>(found).document;
  }

  /// The line at the top, where the words are going (a button on the web, by its name).
  Finder where(String line) => find.descendant(of: find.byKey(CaptureScreen.whereKey), matching: find.text(line));
  bool isWhere(String line) => where(line).evaluate().isNotEmpty;

  /// The word after the line: New note, or Not this note.
  Finder get topAction => find.byKey(CaptureScreen.actionKey);
  bool hasTopAction(String word) => find.descendant(of: topAction, matching: find.text(word)).evaluate().isNotEmpty;

  /// Every word drawn under [of], joined by spaces.
  String textOf(Finder of) {
    final words = <String>[];
    for (final element in find.descendant(of: of, matching: find.byWidgetPredicate((widget) => widget is Text || widget is RichText), matchRoot: true).evaluate()) {
      final widget = element.widget;
      if (widget is Text) words.add(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    }
    return words.join(' ');
  }

  /// Everything the recorder says, as one string.
  String get screenText => textOf(find.byType(CaptureScreen));
  bool says(Pattern words) => screenText.contains(words);

  /// The card after Done, or the card asking which note, by its heading (a region on the web, by its name).
  Finder card(String heading) => find.ancestor(
        of: find.text(heading.toUpperCase()),
        matching: find.byWidgetPredicate((widget) => widget is ConfirmCard<Note> || widget is NoteChoiceCard<Note>),
      );
  bool hasCard(String heading) => card(heading).evaluate().isNotEmpty;
  bool get anyCard => find.byWidgetPredicate((widget) => widget is ConfirmCard<Note> || widget is NoteChoiceCard<Note>).evaluate().isNotEmpty;
  Finder inCard(String heading, String word) => find.descendant(of: card(heading), matching: find.text(word));

  /// The card of things to say.
  Finder get sayCard => find.byType(SayCard);
  bool get hasSayCard => sayCard.evaluate().isNotEmpty;
}

/// `pumpApp` (test/support/render.dart) with the phone's own insets given: the app's theme and token sheets round
/// one screen, on a window of [size]. [measuredAt] is the device pixel ratio of the page the recorder's rectangles
/// were read from (a desktop Chromium, 1), which is what a line of `line-height: normal` is rounded at.
Future<void> pumpScreen(WidgetTester tester, Widget home, {Size size = const Size(390, 844), required Preferences prefs, EdgeInsets insets = const EdgeInsets.only(top: 36, bottom: 20), double ratio = 2, double measuredAt = 1}) async {
  debugDisableShadows = false;
  debugFixturePixelRatio = measuredAt;
  addTearDown(() => debugFixturePixelRatio = null);
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  tester.view.padding = FakeViewPadding(top: insets.top * ratio, bottom: insets.bottom * ratio);
  tester.view.viewPadding = FakeViewPadding(top: insets.top * ratio, bottom: insets.bottom * ratio);
  addTearDown(tester.view.reset);
  preferences.startWithoutStorage();
  preferences.value = prefs;
  final sheet = await tester.runAsync(() => loadTokenSheet(more: appStyleSheets));
  // A whole screen has no tab bar over it: the shell takes its stamp off (`data-tabs`), as the page's does.
  await tester.pumpWidget(GhostApp(sheet: sheet!, home: RootStamps(sheet: sheet, stamps: const {'tabs': null}, child: home)));
  await tester.pump();
}

Segment seg(String text, int startMs, [int? endMs]) => Segment(text: text, startMs: startMs, endMs: endMs ?? startMs + 900);
