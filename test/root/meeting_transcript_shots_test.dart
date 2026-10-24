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

import '../support/render.dart';
import '../tapes/fake_player.dart';

/// Pictures of a meeting opened from Settings › Meetings (Matt, 2026-10-24: "when clicking on meetings it doesn't
/// load the transcript"): the note at its tape with its transcript on the page and the tape still, as the Meetings
/// list's row opens it (the sheet's `onOpenNote`, which the row calls), on a phone and the Mac's window, light and
/// dark. Three of each: the phrases on a device without the meeting's audio (the strip says so), the transcript the
/// note's words keep where no phrases came (a Meet note), and the place while the write-up is still to come. Written
/// only by `flutter test --update-goldens test/root/meeting_transcript_shots_test.dart`, into
/// build/feature-shots/meeting-transcript/*.png (not committed), to be looked at, not held as goldens.
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
  final transcript = '\n\n## Transcript\n\n${[for (final (who, words) in said) '**$who:** $words'].join('\n\n')}\n';
  final phrases = [for (final (i, (_, words)) in said.indexed) Segment(text: words, startMs: i * 6000, endMs: (i + 1) * 6000)];
  final kinds = <String, (String body, List<Segment> segments)>{
    'phrases': ('$head$summary$transcript', phrases),
    'written': ('$head$summary$transcript', const []),
    'writing-up': ('$head It is being written up on your device.\n\n## Captions\n\n${[for (final (i, (who, words)) in said.take(3).indexed) '**$who (0:${(i * 6).toString().padLeft(2, '0')}):** $words'].join('\n\n')}\n', const []),
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
    File('build/feature-shots/meeting-transcript/$name.png')
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
      for (final MapEntry(key: kind, value: (body, segments)) in kinds.entries) {
        testWidgets('a meeting opened from Settings › Meetings, $kind, $where, $theme', (tester) async {
          if (!autoUpdateGoldenFiles) return;
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final library = SampleLibrary.seeded();
          await tester.runAsync(() => library.apply(Note(id: id, body: body, createdAt: seedNow - 3600000, updatedAt: seedNow - 3600000, source: NoteSource.capture, recordingMs: 45 * 60000, segments: segments)));
          // The meeting's audio stayed on the device that recorded it.
          final player = FakeTapePlayer(lengths: const {}, here: false);
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
          // The Meetings list's row: Settings shut and the note opened (lib/meet/ui/meet_card.dart `onOpenNote`).
          tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onOpenNote!(id);
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
            await tester.pump(const Duration(milliseconds: 100));
          }
          await snap(tester, '$kind-$where-$theme');
        });
      }
    }
  }
}
