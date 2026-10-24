import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/aside/aside.dart' show writeSidebarShown;
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/desktop/mac_lights.dart';

import '../support/render.dart';

/// Pictures of advanced mode's sidebar on a wide window (Matt, 2026-10-24: "make the sidebar on advanced mode the
/// same as simple but just hide it by default"): the Mac app at 1280 x 800 and the Fold opened out (704 x 933 at
/// 2.625), each with a note open, the sidebar shut and shown, in the light and in the dark. Docked is chosen, so the
/// "before" pictures (taken from the tree before the change, `--dart-define=ADVANCED_SIDEBAR_SHOTS=before`) are the
/// tree's column and the "after" ones simple's list. Written to build/feature-shots/advanced-sidebar/*.png to be
/// looked at, not held as goldens.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const when = String.fromEnvironment('ADVANCED_SIDEBAR_SHOTS', defaultValue: 'after');

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
    File('build/feature-shots/advanced-sidebar/$when-$name.png')
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

  final lightsAt = ValueNotifier<double?>(null);

  for (final theme in ['light', 'dark']) {
    for (final (size, ratio, sized, mac) in [(const Size(1280, 800), 2.0, 'mac', true), (const Size(704, 933), 2.625, 'fold', false)]) {
      for (final shown in [false, true]) {
        final state = shown ? 'open' : 'closed';
        testWidgets('advanced, $sized, sidebar $state, $theme', (tester) async {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final library = SampleLibrary.seeded();
          final local = MemoryStored();
          writeSidebarShown(shown, local);
          await pumpApp(
            tester,
            size: size,
            ratio: ratio,
            prefs: Preferences(theme: theme, sidebarStyle: 'docked', experience: 'advanced', experienceChosen: true),
            home: Stack(
              children: [
                GhostRoot(launch: false, library: library, stored: local, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
                if (mac) _Lights(centre: lightsAt),
              ],
            ),
          );
          // A Mac window has no notch and no home bar.
          if (mac) {
            tester.view.padding = FakeViewPadding.zero;
            tester.view.viewPadding = FakeViewPadding.zero;
          }
          await tester.pump(const Duration(milliseconds: 300));
          tester.state<AppShellState>(find.byType(AppShell)).openNote(library.value.firstWhere((note) => noteTitle(note.body) == 'Groceries').id);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final rows = find.byType(MacLightsRow);
          lightsAt.value = mac ? (rows.evaluate().isEmpty ? 27 : tester.getCenter(rows.last).dy) : null;
          await tester.pump();
          await snap(tester, '$sized-$state-$theme');
        });
      }
    }
  }
}

/// The window's three buttons, drawn where the window would set them (16pt in, 20pt apart, 12pt across), since a
/// test has no window (test/simple/simple_mac_shots_test.dart has the same).
class _Lights extends StatelessWidget {
  const _Lights({required this.centre});
  final ValueListenable<double?> centre;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double?>(
        valueListenable: centre,
        builder: (context, at, _) => at == null
            ? const SizedBox.shrink()
            : Positioned(
                left: 16,
                top: at - 6,
                child: Row(
                  children: [
                    for (final (i, colour) in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)].indexed)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                        child: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: colour)),
                      ),
                  ],
                ),
              ),
      );
}
