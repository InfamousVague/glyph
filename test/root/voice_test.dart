import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/ui_state.dart' show AccountServices;
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/claude/claude_runner.dart' show debugClaudeApi;
import 'package:ghost_md/claude/claude_settings.dart' show claudeSettings;
import 'package:ghost_md/claude/claude_tools.dart' show ClaudeTool;
import 'package:ghost_md/claude/claude_voice.dart' show claudeLinger;
import 'package:ghost_md/capture/meeting_live.dart';
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/capture/system_sound.dart' show SoundSupport;
import 'package:ghost_md/capture/ui/capture_screen.dart';
import 'package:ghost_md/capture/ui/meeting_screen.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/untouched.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart' show ChangeSpec, TransactionSpec;
import 'package:ghost_md/editor/media/clip_refs.dart' show TapeIds, tapeIdOf, withTapeId;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/note/open_screen.dart' show openNoteScreen;
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/registry.dart' show MemorySwitches, createRegistry, plugins, usePlugins;
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/root/capture_route.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/voice_wiring.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/account_gate.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';
import 'package:ghost_md/tapes/note_tape.dart';
import 'package:ghost_md/tapes/player.dart' show TapePlayer, markAudioRemoved;

import '../account_ui/support.dart' show Device;
import '../support/claude_script.dart';
import '../support/header_bar.dart';
import '../support/render.dart';
import '../tapes/fake_player.dart';

/// A library whose first read has not answered (`useNotes().loading`), until the test says it has.
class _Unread extends SampleLibrary {
  _Unread() : super(seedLibrary());
  bool unread = true;

  @override
  bool get loading => unread;

  void read() {
    unread = false;
    notifyListeners();
  }
}

/// The phone's service, as a test answers for it.
class _Service implements MeetingService, MeetingHost {
  /// What the next start answers, and every start asked: the note, its title, and whether other apps' sound was.
  String answer = 'started';
  final List<(String, String, bool)> starts = [];
  int stops = 0;
  final List<String> forgotten = [];
  Map<String, Object?>? state;
  bool notify = false;
  SoundSupport? sound;

  void recording(String noteId) => state = {'recording': true, 'noteId': noteId, 'title': 'Meeting', 'startedAt': 1, 'elapsedMs': 0, 'silenced': false, 'writingUp': null, 'discarded': <String>[]};

  @override
  Future<String> startMeeting(String noteId, String title, {bool otherApps = false}) async {
    starts.add((noteId, title, otherApps));
    if (answer == 'started') recording(noteId);
    return answer;
  }

  @override
  Future<void> stopMeeting() async {
    stops += 1;
    state = null;
  }

  @override
  Future<void> discardMeeting() async => state = null;

  @override
  Future<String> requestNotifications() async => 'blocked';

  @override
  Future<void> forgetDiscarded(String noteId) async => forgotten.add(noteId);

  @override
  Future<SoundSupport?> meetingSound() async => sound;

  /// What the phone answers about its lock.
  bool lockedNow = false;

  @override
  Future<bool> isLocked() async => lockedNow;

  @override
  Future<void> endCapture({required bool leave}) async {}

  @override
  bool get hasMeetings => true;

  @override
  String? meetingStateJson() => jsonEncode(state ?? {'recording': false, 'noteId': null, 'title': null, 'startedAt': null, 'elapsedMs': 0, 'silenced': false, 'writingUp': null, 'discarded': <String>[]});

  @override
  bool canNotify() => notify;

  @override
  bool visible = true;
}

/// A player whose files say which of them are not on this device, and which were asked.
class _Files extends FakeTapePlayer {
  _Files(this.elsewhere);
  final Set<String> elsewhere;
  final List<String> asked = [];

  @override
  Future<bool?> onDevice(String noteId) async {
    asked.add(noteId);
    return !elsewhere.contains(noteId);
  }
}

/// Speak in the app put together (lib/root): the dock's microphone, a note's own, the capture and meeting screens
/// through the shell's builders, the + sheet's Meeting, and where each begins and ends (`shell/useCaptureRoute.ts`).
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
    // The app's Claude settings read once, here on the real clock: read first by a root inside a test, the read runs on
    // that test's clock and is never done for the tests after it, which wait on it for the key.
    await claudeSettings.load();
  });

  late SampleLibrary library;
  late _Service service;
  late MeetingLive live;
  late StreamController<void> keys;
  late StreamController<void> assists;
  CaptureHandlers? handlers;
  late int cancels;
  String? stopSays;

  /// A voice over a session the test speaks into by hand, and a service that answers as the test says.
  Voice voiceFor(SampleLibrary notes, {bool assistant = false, String launch = '', bool canMeet = true, bool mac = false}) {
    service = _Service();
    live = MeetingLive(host: service, writeUpRunningNow: () => false);
    keys = StreamController<void>.broadcast(sync: true);
    assists = StreamController<void>.broadcast(sync: true);
    handlers = null;
    cancels = 0;
    stopSays = null;
    var prefs = Preferences.defaults.copyWith(review: false, refine: false);
    return Voice(
      recorder: Recorder(
        engine: CaptureEngine(backend: null, hasNativeGeneration: (_) async => true, preferences: () => prefs),
        store: LibraryRecorderStore(notes),
        host: RecorderHost(isAndroid: !mac),
        meetingLive: live,
        preferences: () => prefs,
        setPreferences: (change) => prefs = change(prefs),
        tapes: TapeIds(MemoryStored()),
        native: false,
        simulate: false,
        startCapture: (given) async {
          handlers = given;
          return CaptureSession(
            kind: EngineKind.whisper,
            wantsSamples: false,
            keepsAudio: false,
            push: (_) {},
            positionMs: () => 2600,
            stop: ([options]) async => Stopped(recordedMs: null, transcript: stopSays),
            cancel: () => cancels += 1,
          );
        },
        enqueueRefine: (_) {},
        setRecorderLive: (_) {},
        canRecordMeeting: canMeet,
      ),
      // A Mac has no meeting service: its recorder records a meeting itself.
      service: mac ? null : service,
      assistant: assistant,
      launch: launch,
      captureKey: keys.stream,
      assistKey: assists.stream,
      canMeet: canMeet,
    );
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, {bool voice = true, bool assistant = false, String launch = '', bool canMeet = true, bool mac = false, TapePlayer? tapePlayer, AccountServices? services, SampleLibrary? notes}) async {
    library = notes ?? SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: MemoryStored(),
        untouched: UntouchedNotes(kept: MemoryStored()),
        voice: voice ? voiceFor(library, assistant: assistant, launch: launch, canMeet: canMeet, mac: mac) : null,
        tapePlayer: tapePlayer,
        services: services,
      ),
    );
    await settle(tester, 3);
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  HomeScreen homeOf(WidgetTester tester) => tester.widget<HomeScreen>(find.byType(HomeScreen));
  NewSheet sheetOf(WidgetTester tester) => tester.widget<NewSheet>(find.byType(NewSheet));

  Future<void> until(WidgetTester tester, bool Function() holds, String reason) async {
    for (var waited = 0; waited < 8000 && !holds(); waited += 50) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(holds(), isTrue, reason: reason);
    // What held is drawn.
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> close(WidgetTester tester) async {
    if (shellOf(tester).screen is ScreenCapture) {
      await tester.tap(find.byKey(CaptureScreen.discardKey), warnIfMissed: false);
      await until(tester, () => shellOf(tester).screen is! ScreenCapture, 'the capture did not end');
    }
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  group('a build with no voice', () {
    testWidgets('offers Speak nowhere and no Meeting', (tester) async {
      await open(tester, voice: false);
      expect(homeOf(tester).onCapture, isNull);
      expect(tester.widget<AppShell>(find.byType(AppShell)).captureBuilder, isNull);
      expect(tester.widget<AppShell>(find.byType(AppShell)).meetingBuilder, isNull);
      expect(sheetOf(tester).onMeeting, isNull);
      shellOf(tester).openNote(library.value.first.id);
      await settle(tester);
      expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).onSpeak, isNull);
      await close(tester);
    });
  });

  group('the dock\'s microphone', () {
    testWidgets('opens the recorder over the whole window, and Done files the note said and goes home', (tester) async {
      await open(tester);
      final before = library.value.length;
      homeOf(tester).onCapture!();
      await until(tester, () => handlers != null, 'the capture did not start');
      expect(shellOf(tester).screen, isA<ScreenCapture>());
      expect(find.byType(CaptureScreen), findsOneWidget);
      expect(tester.widget<CaptureScreen>(find.byType(CaptureScreen)).fromAssistant, isFalse);
      handlers!.onSegment(const Segment(text: 'The ferry leaves at nine tomorrow', startMs: 0, endMs: 900));
      await settle(tester, 2);
      stopSays = 'The ferry leaves at nine tomorrow';
      await tester.tap(find.byKey(CaptureScreen.doneKey), warnIfMissed: false);
      await until(tester, () => shellOf(tester).screen is ScreenList, 'the capture did not finish');
      expect(library.value.length, before + 1);
      final made = library.value.firstWhere((note) => note.body.contains('ferry leaves at nine'));
      expect(made.source, NoteSource.capture);
      expect(find.byType(CaptureScreen), findsNothing);
      await close(tester);
    });

    testWidgets('Discard keeps nothing', (tester) async {
      await open(tester);
      final before = [for (final note in library.value) note.id];
      homeOf(tester).onCapture!();
      await until(tester, () => handlers != null, 'the capture did not start');
      handlers!.onSegment(const Segment(text: 'Never mind this', startMs: 0, endMs: 900));
      await settle(tester, 2);
      await tester.tap(find.byKey(CaptureScreen.discardKey), warnIfMissed: false);
      await until(tester, () => shellOf(tester).screen is ScreenList, 'the capture did not end');
      expect([for (final note in library.value) note.id], before);
      expect(cancels, 1);
      await close(tester);
    });
  });

  group('a note\'s own Speak', () {
    testWidgets('aims the recorder at the note, writes the words on its end and comes back to it', (tester) async {
      await open(tester);
      final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
      shellOf(tester).openNote(note.id);
      await settle(tester);
      tester.widget<NoteScreen>(find.byType(NoteScreen)).onSpeak!(note.id);
      await until(tester, () => handlers != null, 'the capture did not start');
      final screen = shellOf(tester).screen as ScreenCapture;
      expect(screen.noteId, note.id);
      handlers!.onSegment(const Segment(text: 'Bring the long lens', startMs: 0, endMs: 900));
      await settle(tester, 2);
      stopSays = 'Bring the long lens';
      await tester.tap(find.byKey(CaptureScreen.doneKey), warnIfMissed: false);
      await until(tester, () => shellOf(tester).screen is ScreenNote, 'the capture did not finish');
      expect(shellOf(tester).shown, note.id);
      expect(library.noteOf(note.id)!.body, contains('long lens'));
      await close(tester);
    });
  });

  // Differs 11 (docs/PARITY.md): a note's own mic stayed when the note had a tape, and the tape's Add did not save
  // what was typed first (NoteScreen.tsx `speakWords = tape.length > 0 || !speakHere ? null : …`, `speakHere`).
  group('a note that wears its tape', () {
    Future<Note> taped(WidgetTester tester) async {
      final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
      await tester.runAsync(() => library.apply(Note(id: note.id, body: note.body, createdAt: note.createdAt, updatedAt: note.updatedAt, source: NoteSource.capture, recordingMs: 4000, segments: const [Segment(text: 'Bring the long lens', startMs: 0, endMs: 2000)], revision: note.revision)));
      await settle(tester, 2);
      return library.noteOf(note.id)!;
    }

    // More from whichever bar is drawn: today's ring, or Grouped command's row under its ••• on a phone.
    Future<void> more(WidgetTester tester) => pressInBar(tester, 'more', label: 'More for this note');

    testWidgets('has no mic of its own in More: it is talked into from its tape\'s Add, where any other note has the mic', (tester) async {
      await open(tester, tapePlayer: FakeTapePlayer(lengths: const {}));
      final note = await taped(tester);
      shellOf(tester).openNote(note.id);
      await settle(tester);
      expect(tester.widget<NoteTape>(find.byType(NoteTape, skipOffstage: false)).onSpeak, isNotNull);
      await more(tester);
      expect(find.text('Talk into this note'), findsNothing);
      await tester.tapAt(const Offset(10, 60));
      await settle(tester, 4);
      shellOf(tester).openNote(library.value.firstWhere((note) => noteTitle(note.body) == 'Launch week').id);
      await settle(tester);
      await more(tester);
      expect(find.text('Talk into this note'), findsOneWidget);
      await tester.tapAt(const Offset(10, 60));
      await settle(tester, 4);
      await close(tester);
    });

    testWidgets('saves what is typed before its Add opens the recorder at it', (tester) async {
      await open(tester, tapePlayer: FakeTapePlayer(lengths: const {}));
      final note = await taped(tester);
      shellOf(tester).openNote(note.id);
      await settle(tester);
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: '\nTyped a moment before.\n'), userEvent: 'input.type'));
      expect(library.noteOf(note.id)!.body, isNot(contains('Typed a moment before.')));
      tester.widget<NoteTape>(find.byType(NoteTape, skipOffstage: false)).onSpeak!();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      expect(library.noteOf(note.id)!.body, contains('Typed a moment before.'), reason: 'saved by the press, not by the debounce');
      await until(tester, () => shellOf(tester).screen is ScreenCapture, 'the capture did not start');
      expect((shellOf(tester).screen as ScreenCapture).noteId, note.id);
      await close(tester);
    });
  });

  group('words a recording put into a note that was already there', () {
    testWidgets('open that note, say so, and are taken out again by Undo, as an edit in its editor', (tester) async {
      await open(tester);
      final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
      homeOf(tester).onCapture!();
      await until(tester, () => handlers != null, 'the capture did not start');
      handlers!.onSegment(const Segment(text: 'Add to the note labeled Packing bring the long lens', startMs: 0, endMs: 900));
      await settle(tester, 2);
      stopSays = 'Add to the note labeled Packing bring the long lens';
      await tester.tap(find.byKey(CaptureScreen.doneKey), warnIfMissed: false);
      // The card after Done asks first, where the live reader did not place it; confirmed, the note opens.
      await until(tester, () => shellOf(tester).screen is ScreenNote || find.text('Add').evaluate().isNotEmpty, 'neither a card nor the note');
      if (shellOf(tester).screen is! ScreenNote) {
        await tester.tap(find.text('Add').first, warnIfMissed: false);
        await until(tester, () => shellOf(tester).screen is ScreenNote, 'the capture did not finish');
      }
      expect(shellOf(tester).shown, note.id);
      await settle(tester, 4);
      expect(find.text('Added to Packing'), findsOneWidget);
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      expect(view.state.doc.toString(), contains('long lens'));
      await tester.tap(find.text('Undo'));
      await settle(tester, 3);
      expect(view.state.doc.toString(), isNot(contains('long lens')));
      await tester.pump(const Duration(seconds: 2));
      expect(library.noteOf(note.id)!.body, isNot(contains('long lens')));
      await close(tester);
    });
  });

  group('a meeting', () {
    testWidgets('on a Mac is the recorder itself in meeting mode: no service asked, and no note made before a word', (tester) async {
      await open(tester, mac: true);
      final before = library.value.length;
      expect(sheetOf(tester).onMeeting, isNotNull);
      await tester.runAsync(() async => sheetOf(tester).onMeeting!());
      await until(tester, () => shellOf(tester).screen is ScreenCapture, 'the recorder did not open');
      expect((shellOf(tester).screen as ScreenCapture).meeting, isTrue);
      expect(tester.widget<CaptureScreen>(find.byType(CaptureScreen)).meeting, isTrue);
      expect(find.byType(MeetingScreen), findsNothing);
      expect(service.starts, isEmpty);
      expect(library.value.length, before);
      expect(preferences.value.meetings, isEmpty);
      await close(tester);
    });

    testWidgets('from the + is the note first, then the service asked, then its screen; Done stops it', (tester) async {
      await open(tester);
      final before = library.value.length;
      expect(sheetOf(tester).onMeeting, isNotNull);
      await tester.runAsync(() async => sheetOf(tester).onMeeting!());
      await until(tester, () => shellOf(tester).screen is ScreenMeeting, 'the meeting did not start');
      expect(library.value.length, before + 1);
      final (id, title, otherApps) = service.starts.single;
      final made = library.noteOf(id)!;
      // Its tape named in its own front matter from the start (lib/editor/media/clip_refs.dart), the title its words.
      expect(tapeIdOf(made.body), isNotNull);
      expect(withTapeId(made.body, null), '# $title\n');
      expect(title, startsWith('Meeting, '));
      expect(made.source, NoteSource.capture);
      expect(otherApps, isFalse);
      expect(preferences.value.meetings.keys, contains(id));
      expect((shellOf(tester).screen as ScreenMeeting).noteId, id);
      expect(find.byType(MeetingScreen), findsOneWidget);
      // The service says it has started, as it does a moment after answering.
      live.heard(jsonEncode({'event': 'started', 'noteId': id, 'elapsedMs': 0}));
      // The row of the note being recorded says so, and opens the meeting, not the note.
      shellOf(tester).backToList();
      await settle(tester, 3);
      expect(homeOf(tester).recording, id);
      homeOf(tester).onOpen(id);
      await settle(tester, 3);
      expect(shellOf(tester).screen, isA<ScreenMeeting>());
      // And every way into a capture is the way to the meeting while it holds the microphone.
      shellOf(tester).backToList();
      await settle(tester, 2);
      homeOf(tester).onCapture!();
      await settle(tester, 3);
      expect(shellOf(tester).screen, isA<ScreenMeeting>());
      expect(handlers, isNull, reason: 'no second microphone');
      live.heard(jsonEncode({'event': 'stopped', 'noteId': id, 'elapsedMs': 4000}));
      await settle(tester, 3);
      expect(shellOf(tester).screen, isA<ScreenList>());
      expect(library.noteOf(id), isNotNull);
      await close(tester);
    });

    testWidgets('waits for the microphone to be granted and asks again; refused, everything made is taken back', (tester) async {
      await open(tester);
      final before = [for (final note in library.value) note.id];
      service.answer = 'permission';
      await tester.runAsync(() async => sheetOf(tester).onMeeting!());
      await until(tester, () => service.starts.length == 1, 'the service was not asked');
      expect(shellOf(tester).screen, isA<ScreenList>());
      final id = service.starts.single.$1;
      service.answer = 'started';
      live.heard(jsonEncode({'event': 'permission', 'granted': true}));
      await until(tester, () => shellOf(tester).screen is ScreenMeeting, 'the meeting did not start once granted');
      expect(service.starts.map((start) => start.$1), [id, id]);
      await close(tester);

      await open(tester);
      service.answer = 'permission';
      await tester.runAsync(() async => sheetOf(tester).onMeeting!());
      await until(tester, () => service.starts.length == 1, 'the service was not asked');
      final refused = service.starts.single.$1;
      live.heard(jsonEncode({'event': 'permission', 'granted': false}));
      await until(tester, () => library.noteOf(refused) == null, 'the note was not taken back');
      expect(preferences.value.meetings.keys, isNot(contains(refused)));
      expect(find.text(microphoneRefused), findsOneWidget);
      expect(shellOf(tester).screen, isA<ScreenList>());
      expect(before.length, library.value.length);
      await tester.pump(const Duration(seconds: 6));
      await close(tester);
    });

    testWidgets('that could not start, or failed after it said it had, is undone with the reason said', (tester) async {
      await open(tester);
      final before = library.value.length;
      service.answer = 'The phone is on a call.';
      await tester.runAsync(() async => sheetOf(tester).onMeeting!());
      await until(tester, () => find.text('The phone is on a call.').evaluate().isNotEmpty, 'the reason was not said');
      expect(library.value.length, before);
      expect(preferences.value.meetings, isEmpty);
      await tester.pump(const Duration(seconds: 6));

      service.answer = 'started';
      await tester.runAsync(() async => sheetOf(tester).onMeeting!());
      await until(tester, () => shellOf(tester).screen is ScreenMeeting, 'the meeting did not start');
      final id = service.starts.last.$1;
      service.state = null;
      live.heard(jsonEncode({'event': 'failed', 'noteId': id, 'elapsedMs': 0}));
      await until(tester, () => library.noteOf(id) == null, 'the failed meeting was not undone');
      expect(shellOf(tester).screen, isA<ScreenList>());
      expect(find.text(meetingFailed), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await close(tester);
    });

    testWidgets('already being recorded is the one opened, and no second note is left for it', (tester) async {
      await open(tester);
      final before = library.value.length;
      service.answer = 'recording';
      final running = library.value.first.id;
      await tester.runAsync(() async {
        sheetOf(tester).onMeeting!();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        service.recording(running);
      });
      await until(tester, () => service.starts.isNotEmpty && library.value.length == before, 'the second note was not taken back');
      await close(tester);
    });

    testWidgets('is not offered where none can be recorded, nor from an organization\'s +', (tester) async {
      await open(tester, canMeet: false);
      expect(sheetOf(tester).onMeeting, isNull);
      expect(tester.widget<SettingsSheet>(find.byType(SettingsSheet)).features.meetings, isFalse);
      await close(tester);
    });
  });

  group('the side key', () {
    testWidgets('is nothing in a build without the assistant: no capture at launch, none from the key', (tester) async {
      await open(tester, launch: 'capture');
      expect(shellOf(tester).screen, isA<ScreenList>());
      keys.add(null);
      await settle(tester, 3);
      expect(shellOf(tester).screen, isA<ScreenList>());
      expect(handlers, isNull);
      // The empty page's hint is the page's own on any Android phone (`isAndroid`), whether or not the key answers.
      expect(homeOf(tester).sideKey, isTrue);
      await close(tester);
    });

    testWidgets('in a build with the assistant starts a capture, and pressed again asks it to stop', (tester) async {
      await open(tester, assistant: true);
      expect(shellOf(tester).screen, isA<ScreenList>(), reason: 'a launch that was not for a capture opens no microphone');
      keys.add(null);
      await until(tester, () => handlers != null, 'the capture did not start');
      final first = shellOf(tester).screen as ScreenCapture;
      expect(first.fromAssistant, isTrue);
      expect(first.stop, 0);
      keys.add(null);
      final again = shellOf(tester).screen;
      expect(again, isA<ScreenCapture>());
      expect((again as ScreenCapture).key, first.key, reason: 'the same capture, not a second microphone');
      expect(again.stop, 1);
      await until(tester, () => shellOf(tester).screen is! ScreenCapture, 'the key did not stop the capture');
      await close(tester);
    });

    testWidgets('that launched the app starts the capture once the notes are read', (tester) async {
      await open(tester, assistant: true, launch: 'capture');
      await until(tester, () => handlers != null, 'the capture did not start');
      expect((shellOf(tester).screen as ScreenCapture).fromAssistant, isTrue);
      await close(tester);
    });

    testWidgets('that launched a signed-out app is not met by the way into an account: the recording comes first', (tester) async {
      final device = await tester.runAsync(() => Device.make(signedIn: false));
      await open(tester, assistant: true, launch: 'capture', services: device!.services);
      await until(tester, () => handlers != null, 'the capture did not start');
      expect(find.byType(AccountGate), findsNothing);
      // Nor after the take: an open by the key never asks (shell/useAccountGate.ts), and the way in is Settings'.
      await tester.tap(find.byKey(CaptureScreen.discardKey), warnIfMissed: false);
      await until(tester, () => shellOf(tester).screen is! ScreenCapture, 'the capture did not end');
      expect(find.byType(AccountGate), findsNothing);
      await close(tester);
    });

    testWidgets('pressed while the way into an account is up records over it, and the way in is back when the take ends', (tester) async {
      final device = await tester.runAsync(() => Device.make(signedIn: false));
      await open(tester, assistant: true, services: device!.services);
      await settle(tester, 3);
      expect(find.byType(AccountGate), findsOneWidget, reason: 'a signed-out open by the icon asks first');
      keys.add(null);
      await until(tester, () => handlers != null, 'the capture did not start');
      expect(shellOf(tester).screen, isA<ScreenCapture>());
      expect(find.byType(AccountGate), findsNothing, reason: 'never drawn over a recorder (App.tsx: !isRecording(screen))');
      await tester.tap(find.byKey(CaptureScreen.discardKey), warnIfMissed: false);
      await until(tester, () => shellOf(tester).screen is! ScreenCapture, 'the capture did not end');
      await settle(tester, 2);
      expect(find.byType(AccountGate), findsOneWidget, reason: 'it was held back, not answered');
      await close(tester);
    });

    testWidgets('a phone unlocked during a take is asked about its lock again, so the take ends as on an unlocked phone', (tester) async {
      await open(tester, assistant: true);
      final voice = tester.widget<GhostRoot>(find.byType(GhostRoot)).voice!;
      service.lockedNow = true;
      await tester.runAsync(voice.readLocked);
      expect(voice.locked, isTrue);
      // Unlocked by the person mid-take: the phone says so (MeetingBridge.kt `unlocked`), and nothing else does.
      service.lockedNow = false;
      await tester.runAsync(() => voice.phoneSaid('screenOff'));
      expect(voice.locked, isTrue, reason: 'only its unlocking is about the lock');
      await tester.runAsync(() => voice.phoneSaid('unlocked'));
      expect(voice.locked, isFalse);
      await close(tester);
    });
  });

  // Matt, 2026-10-17: "Add the AI voice input back in add a microphone icon to the dock bar ... When talking show the
  // sound ripples then show claudes or whatever AI agent were using thought process and then follow along
  // automatically also add the setting back in to be able to bind ghost as the agent on the phone".
  group('Talk to Claude', () {
    Future<void> key(WidgetTester tester, String? key) => tester.runAsync(() => claudeSettings.setKey(key));
    Finder talk() => find.byKey(const ValueKey('dock-claude-talk'));

    testWidgets('is under Claude on every dock while Claude is on with a key, the one microphone there, and nowhere while Claude is off, has no key, or nothing can hear', (tester) async {
      await key(tester, 'sk-ant-test-0000000000');
      addTearDown(() => claudeSettings.setKey(null));
      await open(tester);
      final home = find.descendant(of: find.byType(HomeScreen), matching: talk());
      expect(home, findsOneWidget);
      final claude = find.descendant(of: find.byType(HomeScreen), matching: find.byKey(const ValueKey('dock-claude')));
      expect(tester.getRect(home).top, greaterThan(tester.getRect(claude).top));
      // One microphone (GHST-104, Matt 2026-10-18): with Talk to Claude on a dock, Speak is left off.
      expect(find.descendant(of: find.byType(HomeScreen), matching: find.byKey(const ValueKey('dock-speak'))), findsNothing);
      // A note's dock has it too.
      shellOf(tester).openNote(library.value.first.id);
      await settle(tester);
      expect(find.descendant(of: find.byType(NoteScreen), matching: talk()), findsOneWidget);
      await close(tester);

      // Claude's plugin off: no Talk to Claude, as no Claude.
      final before = plugins;
      addTearDown(() => usePlugins(before));
      usePlugins(createRegistry(builtIn, store: MemorySwitches({'claude': false})));
      await open(tester);
      expect(talk(), findsNothing);
      expect(find.byKey(const ValueKey('dock-speak')), findsOneWidget);
      await close(tester);
      usePlugins(before);

      // Nothing to hear with: none.
      await open(tester, voice: false);
      expect(find.byKey(const ValueKey('dock-claude')), findsOneWidget);
      expect(talk(), findsNothing);
      await close(tester);

      // No API key (Matt, 2026-10-19: "the claude icon should only show up if the user has entered the antrhopic api
      // key"): neither Claude nor Talk to Claude, and Speak is the microphone again.
      await key(tester, null);
      await open(tester);
      expect(find.byKey(const ValueKey('dock-claude')), findsNothing);
      expect(talk(), findsNothing);
      expect(find.byKey(const ValueKey('dock-speak')), findsOneWidget);
      await close(tester);
    });

    testWidgets('listens with the ripples and the words as they come', (tester) async {
      // Only with a key is there a Talk to Claude to press (2026-10-19); the words' sending is the next tests'.
      await key(tester, 'sk-ant-test-0000000000');
      addTearDown(() => claudeSettings.setKey(null));
      await open(tester);
      await tester.tap(talk());
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('claude-voice-listening')), findsOneWidget);
      expect(find.byKey(const Key('voice-waves')), findsOneWidget);
      expect(handlers, isNotNull, reason: 'the ear is the recorder\'s transcriber');
      expect(shellOf(tester).screen, isA<ScreenList>(), reason: 'no recording, no note of its own');
      handlers!.onPartial('add milk');
      await tester.pump();
      expect(find.text('add milk'), findsOneWidget);
      handlers!.onSegment(const Segment(startMs: 0, endMs: 900, text: 'Add milk to the groceries.'));
      await tester.pump();
      expect(find.text('Add milk to the groceries.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('claude-voice-close')));
      await settle(tester, 2);
      await close(tester);
      await key(tester, null);
    });

    // Matt, 2026-10-18: a note Claude made was never opened. Asked aloud, the sheet makes way, down to its strip, and
    // the new note is opened under it and typed into as Claude writes.
    testWidgets('a note Claude is asked aloud to make is opened under the strip and typed into', (tester) async {
      await key(tester, 'sk-ant-test-0000000000');
      addTearDown(() => claudeSettings.setKey(null));
      const body = '# Packing list\n\n- [ ] Passport\n- [ ] Charger\n- [ ] Rain jacket\n';
      debugClaudeApi = (_) => ScriptedClaudeApi([
            scriptedTurn(words: 'Making it.', tool: ClaudeTool.create, pieces: scriptedPieces(jsonEncode({'body': body}), 6)),
            scriptedTurn(words: 'Wrote [[Packing list]].'),
          ]);
      addTearDown(() => debugClaudeApi = null);
      await open(tester);
      final before = {for (final note in library.value) note.id};
      await tester.tap(talk());
      await settle(tester, 3);
      handlers!.onSegment(const Segment(startMs: 0, endMs: 900, text: 'Make me a packing list.'));
      stopSays = 'Make me a packing list.';
      await tester.tap(find.byKey(const ValueKey('claude-voice-mic')));
      Note? made() => library.value.where((note) => !before.contains(note.id)).firstOrNull;
      final seen = <String>[];
      var strip = false;
      bool typed() {
        final note = made();
        strip = strip || find.byKey(const ValueKey('claude-voice-following')).evaluate().isNotEmpty;
        if (note == null) return false;
        final words = openNoteScreen(tester.element(find.byType(AppShell)), note.id)?.view?.state.doc.toString();
        if (words != null && (seen.isEmpty || seen.last != words)) seen.add(words);
        return seen.contains(body) || note.body == body;
      }

      await until(tester, typed, 'Claude did not write the note');
      expect(shellOf(tester).shown, made()!.id, reason: 'the new note was not opened');
      expect(strip, isTrue, reason: 'the sheet did not make way');
      expect(seen, contains(body));
      expect(seen.where((words) => words.isNotEmpty && words.length < body.length && body.startsWith(words)), isNotEmpty, reason: 'not typed as it came: $seen');
      await tester.pump(claudeLinger + const Duration(seconds: 1));
      await close(tester);
      await key(tester, null);
    });

    testWidgets('closes on its close while it listens, and the microphone goes with it', (tester) async {
      await key(tester, 'sk-ant-test-0000000000');
      addTearDown(() => claudeSettings.setKey(null));
      await open(tester);
      await tester.tap(talk());
      await settle(tester, 3);
      expect(handlers, isNotNull);
      await tester.tap(find.byKey(const ValueKey('claude-voice-close')));
      await settle(tester, 2);
      expect(find.byKey(const ValueKey('claude-voice')), findsNothing);
      expect(cancels, 1);
      await close(tester);
    });

    testWidgets('is what the phone\'s assistant does where Claude can answer, and a recording where it cannot', (tester) async {
      // No key: the assistant records, as it always has, launched by it or pressed while open.
      await key(tester, null);
      await open(tester, assistant: true, launch: 'assist');
      await until(tester, () => handlers != null && shellOf(tester).screen is ScreenCapture, 'the assistant did not record');
      expect(find.byKey(const ValueKey('claude-voice')), findsNothing);
      await close(tester);

      // A key: Claude listens instead, and the assistant pressed again is "done".
      await key(tester, 'sk-ant-test-0000000000');
      addTearDown(() => claudeSettings.setKey(null));
      await open(tester, assistant: true);
      assists.add(null);
      await until(tester, () => find.byKey(const ValueKey('claude-voice-listening')).evaluate().isNotEmpty, 'the assistant did not talk to Claude');
      expect(shellOf(tester).screen, isA<ScreenList>());
      // Record note, from the icon, is still a recording.
      await tester.tap(find.byKey(const ValueKey('claude-voice-close')));
      await settle(tester, 2);
      keys.add(null);
      await until(tester, () => shellOf(tester).screen is ScreenCapture, 'Record note did not record');
      await close(tester);

      // The phone locked: a recording, which knows the lock screen; a note Claude opens is not for it.
      await open(tester, assistant: true);
      service.lockedNow = true;
      assists.add(null);
      await until(tester, () => shellOf(tester).screen is ScreenCapture, 'the locked phone did not record');
      expect(find.byKey(const ValueKey('claude-voice')), findsNothing);
      await close(tester);
      await key(tester, null);
    });
  });

  group('Settings', () {
    // Differs 16 (docs/PARITY.md): Settings' Allow always answered yes, so a phone that blocks notifications could
    // never be said to (settings/RecordingPane.tsx `if (requestNotifications() === 'blocked') setBlocked(true)`).
    testWidgets('is told the phone\'s own answer when it asks to notify of a meeting written up: blocked is no', (tester) async {
      await open(tester);
      final allow = tester.widget<SettingsSheet>(find.byType(SettingsSheet)).features.onAllowMeetingNotices!;
      // The phone here blocks it outright (the service this file plays answers `blocked`).
      expect(await tester.runAsync(() async => allow()), isFalse);
      await close(tester);
    });

    testWidgets('is told the room the tapes take from their lengths, and the Meetings card where the phone has the service', (tester) async {
      await open(tester);
      final features = tester.widget<SettingsSheet>(find.byType(SettingsSheet)).features;
      final ms = library.value.fold<int>(0, (sum, note) => sum + (note.recordingMs ?? 0));
      expect(features.tapes, ms * 32);
      expect(features.meetings, isTrue);
      expect(features.onRemoveOldAudio, isNull, reason: 'nothing here can remove audio');
      expect(features.models, isNull, reason: 'no engine in a test');
      await close(tester);
    });

    // Differs 32 (docs/PARITY.md): "Your tapes are being counted." until the notes have been read, where the card was
    // told nothing of it and said there were no tapes (RecordingPane.tsx `notes === null`).
    testWidgets('is told the tapes are being counted until the notes have been read', (tester) async {
      final notes = _Unread();
      await open(tester, notes: notes);
      SettingsFeatures features() => tester.widget<SettingsSheet>(find.byType(SettingsSheet)).features;
      expect(features().countingTapes, isTrue);
      notes.read();
      await settle(tester, 2);
      expect(features().countingTapes, isFalse);
      await close(tester);
    });

    testWidgets('counts only the tapes whose audio is on this device, once the Tapes card has had each file asked', (tester) async {
      useStored(MemoryStored());
      final files = _Files({'synced'});
      await open(tester, tapePlayer: files);
      // An hour and a minute made here two months ago, and a minute that came by sync and left its audio behind.
      final then = DateTime.now().millisecondsSinceEpoch - 60 * 24 * 60 * 60 * 1000;
      Note tape(String id, int ms) => Note(id: id, body: '# $id', createdAt: then, updatedAt: then, source: NoteSource.capture, recordingMs: ms);
      await tester.runAsync(() async {
        for (final note in [tape('hour', 3600000), tape('minute', 60000), tape('synced', 60000)]) {
          await library.apply(note);
        }
      });
      await settle(tester, 2);
      SettingsFeatures features() => tester.widget<SettingsSheet>(find.byType(SettingsSheet)).features;
      // Until a file has answered it counts, as on the page until its HEAD does; and nothing is asked before the card.
      expect(files.asked, isEmpty);
      expect((features().tapes, features().oldTapes), ((3600000 + 60000 + 60000) * 32, 3));
      features().onCountTapes!();
      await settle(tester, 2);
      expect(files.asked.toSet(), {'hour', 'minute', 'synced'});
      expect((features().tapes, features().oldTapes), ((3600000 + 60000) * 32, 2));
      // What the row removed here is not counted either, and its file is not asked after again.
      markAudioRemoved(['hour']);
      files.asked.clear();
      features().onCountTapes!();
      await settle(tester, 2);
      expect(files.asked.toSet(), {'minute', 'synced'});
      expect((features().tapes, features().oldTapes), (60000 * 32, 1));
      await close(tester);
    });
  });

  group('where a model comes from', () {
    test('a build that is not a release has no mirror unless it is given its own, and never the real ones', () {
      // Never an empty list, which the core reads as none given and answers with the web app's own two.
      expect(voiceMirrors('', debug: true), [noMirror]);
      expect(Uri.parse(noMirror).host, '127.0.0.1');
      expect(voiceMirrors('http://10.0.2.2:8765/', debug: true), ['http://10.0.2.2:8765']);
      for (final real in ['https://attack.fm/glyph/models', 'https://ghostmarkdown.com/models', 'https://www.ghostmarkdown.com/m', 'https://huggingface.co/x', 'ftp://10.0.2.2', 'nonsense']) {
        expect(voiceMirrors(real, debug: true), [noMirror], reason: real);
      }
    });

    test('a release with none given has the web app\'s own', () {
      expect(voiceMirrors('', debug: false), isNull);
      expect(voiceMirrors('https://attack.fm/glyph/models', debug: false), ['https://attack.fm/glyph/models']);
    });
  });
}
