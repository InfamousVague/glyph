import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
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
import 'package:ghost_md/editor/media/clip_refs.dart' show TapeIds;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/root/capture_route.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/voice_wiring.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';

import '../support/render.dart';

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

  @override
  Future<bool> isLocked() async => false;

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

/// Speak in the app put together (lib/root): the dock's microphone, a note's own, the capture and meeting screens
/// through the shell's builders, the + sheet's Meeting, and where each begins and ends (`shell/useCaptureRoute.ts`).
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late SampleLibrary library;
  late _Service service;
  late MeetingLive live;
  late StreamController<void> keys;
  CaptureHandlers? handlers;
  late int cancels;
  String? stopSays;

  /// A voice over a session the test speaks into by hand, and a service that answers as the test says.
  Voice voiceFor(SampleLibrary notes, {bool assistant = false, String launch = '', bool canMeet = true}) {
    service = _Service();
    live = MeetingLive(host: service, writeUpRunningNow: () => false);
    keys = StreamController<void>.broadcast(sync: true);
    handlers = null;
    cancels = 0;
    stopSays = null;
    var prefs = Preferences.defaults.copyWith(review: false, refine: false);
    return Voice(
      recorder: Recorder(
        engine: CaptureEngine(backend: null, hasNativeGeneration: (_) async => true, preferences: () => prefs),
        store: LibraryRecorderStore(notes),
        host: const RecorderHost(isAndroid: true),
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
      service: service,
      assistant: assistant,
      launch: launch,
      captureKey: keys.stream,
      canMeet: canMeet,
    );
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, {bool voice = true, bool assistant = false, String launch = '', bool canMeet = true}) async {
    library = SampleLibrary.seeded();
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
        voice: voice ? voiceFor(library, assistant: assistant, launch: launch, canMeet: canMeet) : null,
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

  group('a meeting', () {
    testWidgets('from the + is the note first, then the service asked, then its screen; Done stops it', (tester) async {
      await open(tester);
      final before = library.value.length;
      expect(sheetOf(tester).onMeeting, isNotNull);
      await tester.runAsync(() async => sheetOf(tester).onMeeting!());
      await until(tester, () => shellOf(tester).screen is ScreenMeeting, 'the meeting did not start');
      expect(library.value.length, before + 1);
      final (id, title, otherApps) = service.starts.single;
      final made = library.noteOf(id)!;
      expect(made.body, '# $title\n');
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
      expect(homeOf(tester).sideKey, isFalse);
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
  });

  group('Settings', () {
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
  });

  group('where a model comes from', () {
    test('a build that is not a release has no mirror unless it is given its own, and never the real ones', () {
      expect(voiceMirrors('', debug: true), isEmpty);
      expect(voiceMirrors('http://10.0.2.2:8765/', debug: true), ['http://10.0.2.2:8765']);
      for (final real in ['https://attack.fm/glyph/models', 'https://ghostmarkdown.com/models', 'https://www.ghostmarkdown.com/m', 'https://huggingface.co/x', 'ftp://10.0.2.2', 'nonsense']) {
        expect(voiceMirrors(real, debug: true), isEmpty, reason: real);
      }
    });

    test('a release with none given has the web app\'s own', () {
      expect(voiceMirrors('', debug: false), isNull);
      expect(voiceMirrors('https://attack.fm/glyph/models', debug: false), ['https://attack.fm/glyph/models']);
    });
  });
}
