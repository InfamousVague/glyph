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
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/tapes/tape.dart' show counter;
import 'package:ghost_md/tapes/transcript_words.dart';

import '../support/render.dart';
import '../tapes/fake_player.dart';

/// Pictures of a meeting's transcript lit as its tape plays (Matt, 2026-10-25: "the transcript for the meeting should
/// highlight the section of audio that's playing"), opened from Settings › Meetings as
/// meeting_transcript_shots_test.dart opens it, then a line tapped and Play pressed: on a phone and the Mac's window,
/// light and dark. Three of each: the phrases of a written-up meeting, Meet's captions lit by the times they were
/// kept with while the write-up is to come, and the phrases scrolled away from by hand, with Follow over the
/// transcript's foot. Written only by `flutter test --update-goldens test/root/transcript_highlight_shots_test.dart`,
/// into build/feature-shots/transcript-highlight/*.png (not committed), to be looked at, not held as goldens.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const id = 'launch-sync';
  const head = '# Launch sync\n\nGhost was in this meeting on 23 Oct, 14:00 to 14:45.';
  const summary = '\n\n## Summary\n\n- The pricing page is drafted; the copy is with legal.\n- Every item on the launch checklist has an owner.\n- Daniel sends the press note on Thursday.';
  const said = [
    ('Sam Lee', 'Good morning everyone. Let\'s start with the launch checklist.'),
    ('Daniel', 'Thanks. The pricing page is drafted, and the copy is with legal now.'),
    ('Sam Lee', 'Great. Who has the press note?'),
    ('Daniel', 'I do. It goes out on Thursday, once legal has signed off.'),
    ('Priya', 'The onboarding emails are ready too. I\'ll schedule them for launch morning.'),
    ('Sam Lee', 'Perfect. Then every item has an owner. Anything blocking?'),
    ('Priya', 'Only the screenshots for the store listing. I need the final build for those.'),
    ('Daniel', 'I can have a build for you by tomorrow afternoon.'),
  ];
  // The meeting said over six times, so there is a transcript to scroll.
  final turns = [for (var i = 0; i < 48; i++) said[i % said.length]];
  final transcript = '\n\n## Transcript\n\n${[for (final (who, words) in turns) '**$who:** $words'].join('\n\n')}\n';
  final phrases = [for (final (i, (_, words)) in turns.indexed) Segment(text: words, startMs: i * 6000, endMs: (i + 1) * 6000)];
  final captions = '$head It is being written up on your device.\n\n## Captions\n\n${[for (final (i, (who, words)) in turns.indexed) '**$who (${counter(i * 6000)}):** $words'].join('\n\n')}\n';
  final kinds = <String, (String body, List<Segment> segments, bool scroll)>{
    'phrases': ('$head$summary$transcript', phrases, false),
    'captions': (captions, const [], false),
    'follow': ('$head$summary$transcript', phrases, true),
  };

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
    File('build/feature-shots/transcript-highlight/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  }

  for (final theme in ['light', 'dark']) {
    for (final (size, ratio, where, mac) in [(const Size(390, 844), 3.0, 'phone', false), (const Size(1280, 800), 2.0, 'mac', true)]) {
      for (final MapEntry(key: kind, value: (body, segments, scroll)) in kinds.entries) {
        testWidgets('a meeting\'s transcript lit as its tape plays, $kind, $where, $theme', (tester) async {
          if (!autoUpdateGoldenFiles) return;
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final library = SampleLibrary.seeded();
          await tester.runAsync(() => library.apply(Note(id: id, body: body, createdAt: seedNow - 3600000, updatedAt: seedNow - 3600000, source: NoteSource.capture, recordingMs: 45 * 60000, segments: segments)));
          // The meeting's audio is on this device.
          final player = FakeTapePlayer(lengths: const {id: 45 * 60000});
          await pumpApp(
            tester,
            size: size,
            ratio: ratio,
            prefs: Preferences(theme: theme, meetings: {id: seedNow - 3600000}),
            home: GhostRoot(launch: false, library: library, stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, tapePlayer: player),
          );
          if (mac) {
            tester.view.padding = FakeViewPadding.zero;
            tester.view.viewPadding = FakeViewPadding.zero;
          }
          await tester.pump(const Duration(milliseconds: 300));
          tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onOpenNote!(id);
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
            await tester.pump(const Duration(milliseconds: 100));
          }
          // A meeting opens at Note (Matt, 2026-10-30): its Transcript, chosen.
          await tester.tap(find.descendant(of: find.byKey(const ValueKey('meeting-view')), matching: find.text('Transcript')));
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
            await tester.pump(const Duration(milliseconds: 100));
          }
          // The press note's question, tapped: the tape goes there, and plays from it.
          await tester.tap(find.textContaining('Who has the press note?', findRichText: true).first);
          await tester.pump();
          // A turn pressed plays from it already; Play where it did not.
          if (!player.playing.value) await tester.tap(find.bySemanticsLabel('Play').first);
          for (var i = 0; i < 40; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (scroll) {
            await tester.drag(find.byType(TranscriptWords), const Offset(0, -260));
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(find.text('Follow'), findsOneWidget);
          }
          await snap(tester, '$kind-$where-$theme');
        });
      }
    }
  }
}
