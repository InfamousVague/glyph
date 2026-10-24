import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/desktop/mac_lights.dart';
import 'package:ghost_md/simple/simple_home.dart';

import '../notes/bar_support.dart' show appSheet, spaces;
import '../organize/support.dart' show organizeSpaces;
import '../support/render.dart';

/// Pictures of simple mode's home page in the Mac app (Matt, 2026-10-24: "in simple mode we need to move the title
/// under the traffic lights there is a bunch of empty white space on the left"): the column beside the note at the
/// window he sent (1000 x 700), the page alone in a narrow window (480 x 760), and a phone's (390 x 844) and a
/// wide Android window's, which are not the Mac's and keep their layout, each in the light and in the dark. Written
/// to build/feature-shots/simple-mac/*.png to be looked at, not held as goldens.
void main() {
  setUpAll(loadAppFonts);

  Future<void> snap(WidgetTester tester, String name) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(
        boundary.paintBounds,
        pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/feature-shots/simple-mac/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  }

  final lightsAt = ValueNotifier<double?>(null);

  Future<void> page(
    WidgetTester tester, {
    required Size size,
    required String theme,
    required bool mac,
    bool simple = true,
  }) async {
    if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final sheet = await appSheet(tester);
    final notes = SampleLibrary.seeded(clock: () => seedNow).value;
    await pumpApp(
      tester,
      size: size,
      prefs: Preferences(theme: theme),
      home: Stack(
        children: [
          AppShell(
            sheet: sheet,
            notes: notes,
            workspaces: spaces,
            simple: simple,
            mobile: !mac && size.width < 600,
            finePointer: mac,
            backStack: BackStack(),
            homeBuilder: (context, shell) => simple
                ? SimpleHome(
                    notes: shell.notes,
                    clock: () => seedNow,
                    onOpen: (_) {},
                    onNew: () {},
                    onSpeak: () {},
                    onSettings: () {},
                    onTab: (_) {},
                    pane: shell.listPane(context),
                  )
                : HomeScreen(
                    notes: shell.notes,
                    workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces())),
                    onOpen: (_) {},
                    onNew: () {},
                    onAllNotes: () {},
                    onSettings: () {},
                    clock: () => seedNow,
                    stored: MemoryStored(),
                  ),
            onSettings: () {},
            onNew: () {},
          ),
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
    // The row the page says the buttons sit on; with none, where the window puts them before it is told
    // (macos/Runner/MainFlutterWindow.swift `lightsCentre`).
    final rows = find.byType(MacLightsRow);
    lightsAt.value = mac ? (rows.evaluate().isEmpty ? 27 : tester.getCenter(rows.last).dy) : null;
    await tester.pump();
  }

  for (final theme in ['light', 'dark']) {
    for (final (size, sized, mac) in [
      (const Size(1000, 700), 'mac-wide', true),
      (const Size(480, 760), 'mac-narrow', true),
      (const Size(390, 844), 'phone', false),
      (const Size(1000, 700), 'android-wide', false),
    ]) {
      testWidgets('simple home, $sized, $theme', (tester) async {
        await page(tester, size: size, theme: theme, mac: mac);
        expect(find.byType(SimpleHome), findsOneWidget);
        await snap(tester, 'simple-$sized-$theme');
      });
    }

    testWidgets('advanced, for its sidebar beside the lights, mac-wide, $theme', (tester) async {
      await page(tester, size: const Size(1000, 700), theme: theme, mac: true, simple: false);
      await snap(tester, 'advanced-mac-wide-$theme');
    });
  }
}

/// The window's three buttons, drawn where the window would set them (16pt in, 20pt apart, 12pt across), since a
/// test has no window: the picture shows what the title has to clear.
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
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
                    ),
                  ),
              ],
            ),
          ),
  );
}
