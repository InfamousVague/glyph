import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/meeting_live.dart';
import 'package:ghost_md/capture/meeting_live_words.dart';
import 'package:ghost_md/capture/ui/meeting_screen.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/meet/live_transcript.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// Pictures of a meeting's transcript live (Matt, 2026-10-30: "If possible add real time transcriptions for
/// meetings"): the phone's meeting screen with its words under the cassette, and a meeting Ghost is in at its
/// Transcript, the turns named and timed as the captions come, the line being said lighter, the Live badge, on a phone
/// and the Mac's window; light and dark. Written only by `flutter test --update-goldens
/// test/root/live_transcript_shots_test.dart`, into build/feature-shots/live-transcript/*.png (not committed), to be
/// looked at, not held as goldens.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });
  tearDown(liveTranscripts.clear);

  Future<void> snap(WidgetTester tester, String name) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/feature-shots/live-transcript/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> end(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  }

  const said = [
    ('Sam Lee', 'Good morning everyone. Let’s start with the launch checklist, then pricing.'),
    ('Daniel', 'Thanks. The pricing page is drafted, and legal has the terms since yesterday.'),
    ('Priya', 'The release notes are half done. I need the list of fixes from the last two weeks.'),
    ('Sam Lee', 'I’ll send that after this. Kevin, how is the settlement job?'),
    ('Kevin Ortiz', 'It failed twice overnight. It was the retry window again, so I raised it to five minutes.'),
    ('Dana Reyes', 'Compliance wants the audit export by Monday. It has to include the cancelled orders.'),
  ];

  for (final dark in [false, true]) {
    final shade = dark ? 'dark' : 'light';
    for (final (size, ratio, where, mac) in [(const Size(390, 844), 3.0, 'phone', false), (const Size(1280, 800), 2.0, 'mac', true)]) {
      testWidgets('a meeting Ghost is in, its Transcript live, $where, $shade', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        useStored(MemoryStored());
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        const meeting = 'standup';
        final id = meetLiveNoteId(meeting);
        final library = SampleLibrary.seeded();
        await tester.runAsync(() => library.apply(Note(id: id, body: '${liveNoteBody('Engineering Standup')}\nAsk Kevin about the retry window.\n', createdAt: seedNow - 600000, updatedAt: seedNow - 600000, source: NoteSource.capture)));
        liveTranscripts.heard(
          id,
          from: LiveFrom.bot,
          meeting: meeting,
          lines: [for (final (i, (who, words)) in said.indexed) LiveLine(at: 4000 + i * 19000, speaker: who, text: words)],
          saying: LiveLine(at: 4000 + said.length * 19000, speaker: 'Matt', text: 'Shipping the activity tray today, and'),
        );
        await pumpApp(
          tester,
          size: size,
          ratio: ratio,
          prefs: Preferences(theme: shade, meetings: {id: seedNow - 600000}),
          home: GhostRoot(launch: false, library: library, stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
        );
        if (mac) {
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
        }
        await tester.pump(const Duration(milliseconds: 300));
        tester.state<AppShellState>(find.byType(AppShell)).openNote(id);
        await settle(tester);
        await snap(tester, 'note-$where-$shade');
        await tester.tap(find.byKey(const ValueKey('live-transcript-pill')));
        await settle(tester);
        await snap(tester, 'transcript-$where-$shade');
        tester.state<AppShellState>(find.byType(AppShell)).backToList();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await end(tester);
      });
    }

    testWidgets('the phone’s meeting screen with its words live, $shade', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      useStored(MemoryStored());
      const now = 1790000000000;
      final service = _Service(now);
      final live = MeetingLive(host: service, writeUpRunningNow: () => false, now: () => now)..readMeetingState();
      final model = _Model();
      final store = LiveTranscripts();
      final words = MeetingLiveWords(meeting: live, host: _Feed(), recogniser: model, setting: LiveWordsSetting(phone: true)..value = LiveWordsChoice.on, charging: () => true, inFront: () => true, dictating: () => false, now: () => now, store: store);
      await pumpApp(
        tester,
        size: const Size(390, 844),
        ratio: 3,
        prefs: Preferences(theme: shade),
        home: BackScope(
          stack: BackStack(),
          child: MeetingScreen(
            noteId: 'm1',
            fromAssistant: false,
            onLeave: () {},
            live: live,
            host: MeetingScreenHost(isLocked: () => false, endCapture: (_) {}, stopMeeting: () {}, discardMeeting: () {}, requestNotifications: () => NotificationsAnswer.allowed, deleteNote: (_) async {}, dropSummary: (_) {}, forgetMeeting: (_) {}, haptic: (_) {}),
            liveWords: words,
            words: store,
          ),
        ),
      );
      await settle(tester, 4);
      for (final (i, text) in const [
        'so the plan for the launch is to keep the pricing page as it is.',
        'and move the release notes to Thursday morning.',
        'does anyone need more time on the audit export?',
        'I think Monday is fine if we start on it today.',
      ].indexed) {
        model.say(i * 7000, text);
      }
      await settle(tester, 4);
      await snap(tester, 'meeting-screen-phone-$shade');
      unawaited(words.close());
      await end(tester);
    });
  }
}

class _Service implements MeetingHost {
  _Service(this.now);
  final int now;
  @override
  bool visible = true;
  @override
  bool get hasMeetings => true;
  @override
  String? meetingStateJson() => jsonEncode({'recording': true, 'noteId': 'm1', 'title': 'Meeting, 30 Oct 10:00', 'startedAt': now - 754000, 'elapsedMs': 754000, 'silenced': false, 'writingUp': null, 'discarded': <String>[]});
  @override
  bool canNotify() => true;
}

class _Feed implements LiveWordsHost {
  @override
  Future<bool> feed(bool on) async => true;
}

class _Model implements LiveRecogniser {
  final StreamController<CaptureEvent> said = StreamController<CaptureEvent>.broadcast(sync: true);
  @override
  Stream<CaptureEvent> get events => said.stream;
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
  void say(int at, String text) => said.add(CaptureEventSegment(Segment(startMs: at, endMs: at + 2500, text: text)));
}
