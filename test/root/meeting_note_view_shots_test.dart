import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/meet/meet_note.dart' show withSpeakers;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/tapes/tape.dart' show counter;

import '../support/render.dart';
import '../tapes/fake_player.dart';

/// Pictures of a meeting's note in its two views (Matt, 2026-10-30: "Also use a button to switch to the transcript in
/// the note don't show the transcript on the note section"; "some of the meeting transcripts still go into one giant
/// block instead of maintaining the name (timestamp): prefix on each line"): Note, the summary and the meeting's line
/// with the transcript folded away, and Transcript, the turns, a speaker and a time over each one's words, one lit
/// as the tape plays. On a phone and the Mac's window, light. The transcript is written up as the meeting step writes
/// it now, from the write-up's one block and the captions (lib/meet/meet_note.dart `withSpeakers`). Written only by
/// `flutter test --update-goldens test/root/meeting_note_view_shots_test.dart`, into
/// build/feature-shots/meeting-note-view/*.png (not committed), to be looked at, not held as goldens.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const id = 'engineering-standup';
  const said = [
    ('Phil Mulliken', 'Oh yeah, we can talk about it. I was discussing the matching engine with Kevin yesterday, and the order book rebuild is slower than we thought.'),
    ('Kevin Ortiz', 'The settlement job failed twice overnight. It was the retry window again, so I raised it to five minutes.'),
    ('Matt', 'Shipping the activity tray today. The ring has its badge now, and updates only show in the drawer.'),
    ('Dana Reyes', 'Compliance wants the audit export by Monday. It has to include the cancelled orders, in UTC.'),
    ('Sam Lee', 'Hiring: two interviews this week, one backend and one design. Feedback in the doc please.'),
  ];
  final turns = [for (var i = 0; i < 20; i++) said[i % said.length]];
  final phrases = [for (final (i, (_, words)) in turns.indexed) Segment(text: words, startMs: 2000 + i * 14000, endMs: 2000 + (i + 1) * 14000)];
  final captions = [for (final (i, (who, words)) in turns.indexed) '**$who (${counter(3000 + i * 14000)}):** $words'].join('\n\n');
  const head = '# Engineering Standup\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06.';
  const summary = '## Summary\n\nThe team agreed to ship the activity tray today and to profile the order book before Friday.\n\n- [ ] Phil: profile the order book rebuild\n- [ ] Dana: the audit export by Monday\n- [ ] Kevin: watch the settlement job through the weekend';
  final filed = '$head It is being written up on your device.\n\n$summary\n\n## Captions\n\n$captions\n\n## Transcript\n\n${phrases.map((p) => p.text).join(' ')}\n';
  final body = withSpeakers(filed, phrases)!;

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
    File('build/feature-shots/meeting-note-view/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final (size, ratio, where, mac) in [(const Size(390, 844), 3.0, 'phone', false), (const Size(1280, 800), 2.0, 'mac', true)]) {
    testWidgets('a meeting\'s note in Note and in Transcript, $where', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      useStored(MemoryStored());
      if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final library = SampleLibrary.seeded();
      await tester.runAsync(() => library.apply(Note(id: id, body: body, createdAt: seedNow - 3600000, updatedAt: seedNow - 3600000, source: NoteSource.capture, recordingMs: 38 * 60000, segments: phrases)));
      final player = FakeTapePlayer(lengths: const {id: 38 * 60000});
      await pumpApp(
        tester,
        size: size,
        ratio: ratio,
        prefs: Preferences(theme: 'light', meetings: {id: seedNow - 3600000}),
        home: GhostRoot(launch: false, library: library, stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, tapePlayer: player),
      );
      if (mac) {
        tester.view.padding = FakeViewPadding.zero;
        tester.view.viewPadding = FakeViewPadding.zero;
      }
      await tester.pump(const Duration(milliseconds: 300));
      tester.state<AppShellState>(find.byType(AppShell)).openNote(id);
      await settle(tester);
      await snap(tester, 'note-$where');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('meeting-view')), matching: find.text('Transcript')));
      await settle(tester);
      // The third turn pressed: the tape plays from it, and it is lit.
      await tester.tap(find.textContaining('Shipping the activity tray today.').first);
      await settle(tester, 12);
      await snap(tester, 'transcript-$where');
      if (player.playing.value) await tester.tap(find.bySemanticsLabel('Pause the recording'));
      tester.state<AppShellState>(find.byType(AppShell)).backToList();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 500));
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
