import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/style_sheets.dart';
import 'package:ghost_md/aside/aside.dart' show writeSidebarShown;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:glacier/glacier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/render.dart';

/// Pictures, not held, of the app's main screens as a device that has chosen nothing draws them since Grouped command
/// became the header toolbar's default (Matt, 2026-10-29: "make the grouped command the default header layout"): the
/// app put together and launched with nothing kept, at home, at home with the sidebar on a wide window, on a note, in
/// All notes' folders and in Settings, on a phone, the opened Fold and the Mac, light and dark.
///
/// `FEATURE_SHOTS=1 flutter test --update-goldens test/root/header_default_shots_test.dart` writes each into
/// build/feature-shots/header-default/, and then a contact sheet there for each theme, a window to a row.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  final shots = Platform.environment.containsKey('FEATURE_SHOTS');
  const folder = 'build/feature-shots/header-default';

  const windows = [
    (name: 'phone', size: Size(390, 844), mac: false),
    (name: 'unfolded', size: Size(880, 1000), mac: false),
    (name: 'mac', size: Size(1280, 800), mac: true),
  ];
  const screens = ['home', 'home-sidebar', 'note', 'folders', 'settings'];

  /// The screens a window is pictured at: the sidebar beside home only where there is room for it.
  List<String> screensOf(({String name, Size size, bool mac}) window) => [for (final screen in screens) if (screen != 'home-sidebar' || window.name != 'phone') screen];

  Future<void> pump(WidgetTester tester, [int times = 8]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The app launched as a device that has kept no bar of its own: the default's.
  Future<void> launch(WidgetTester tester, {required Size size, required String theme, required bool sidebar}) async {
    SharedPreferences.setMockInitialValues({
      PreferencesStore.storageKey: jsonEncode({'theme': theme, 'experience': 'advanced', 'experienceChosen': true}),
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    preferences.forget();
    debugDisableShadows = false;
    const ratio = 2.0;
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    tester.view.padding = const FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
    tester.view.viewPadding = const FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
    addTearDown(tester.view.reset);
    final stored = MemoryStored();
    if (sidebar) writeSidebarShown(true, stored);
    final sheet = await tester.runAsync(() => loadTokenSheet(more: appStyleSheets));
    await tester.pumpWidget(
      GhostApp(
        sheet: sheet!,
        home: GhostRoot(launch: false, library: SampleLibrary.seeded(), stored: stored, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
      ),
    );
    await pump(tester, 12);
  }

  for (final window in windows) {
    for (final theme in ['light', 'dark']) {
      for (final screen in screensOf(window)) {
        testWidgets('a picture: the default bar, $screen, ${window.name}, $theme', (tester) async {
          if (window.mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            await launch(tester, size: window.size, theme: theme, sidebar: screen == 'home-sidebar');
            expect(headerToolbarVersion, HeaderToolbarVersion.groupedCommand, reason: 'nothing kept is the default');
            final shell = tester.state<AppShellState>(find.byType(AppShell));
            switch (screen) {
              case 'note':
                shell.openNote(shell.notes.first.id);
              case 'folders':
                shell.showFolders();
              case 'settings':
                shell.openSettings();
            }
            await pump(tester, 10);
            await expectLater(find.byType(GhostApp), matchesGoldenFile('../../$folder/$screen-${window.name}-$theme.png'));
          } finally {
            debugDisableShadows = true;
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 2));
            debugDefaultTargetPlatformOverride = null;
          }
        }, skip: !shots);
      }
    }
  }

  // The contact sheets, one for each theme: a row for each window, its screens side by side at one height, each
  // named over it. Made from the pictures above, so they run after them.
  for (final theme in ['light', 'dark']) {
    testWidgets('a picture: the contact sheet of the default bar, $theme', (tester) async {
      await tester.runAsync(() async {
        const rowHeight = 760.0, band = 64.0, gap = 28.0, margin = 32.0;
        final paper = theme == 'light' ? const Color(0xFFF6F4EF) : const Color(0xFF151413);
        final ink = theme == 'light' ? const Color(0xFF1B1A18) : const Color(0xFFEDEAE4);
        // Each window's pictures, read and laid out first, for the sheet's width.
        final rows = <(String, List<(String, ui.Image)>)>[];
        for (final window in windows) {
          final images = <(String, ui.Image)>[];
          for (final screen in screensOf(window)) {
            final codec = await ui.instantiateImageCodec(File('$folder/$screen-${window.name}-$theme.png').readAsBytesSync());
            images.add((screen, (await codec.getNextFrame()).image));
          }
          rows.add((window.name, images));
        }
        double widthOf(List<(String, ui.Image)> images) => images.fold(0.0, (sum, each) => sum + each.$2.width * rowHeight / each.$2.height + gap) - gap;
        final width = margin * 2 + rows.map((row) => widthOf(row.$2)).reduce((a, b) => a > b ? a : b);
        final height = margin + rows.length * (band * 2 + rowHeight + margin);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = paper);
        void words(String text, Offset at, double size, FontWeight weight) {
          final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Inter Variable', fontSize: size, fontWeight: weight))
            ..pushStyle(ui.TextStyle(color: ink))
            ..addText(text);
          canvas.drawParagraph(builder.build()..layout(ui.ParagraphConstraints(width: width)), at);
        }

        var top = margin;
        for (final (name, images) in rows) {
          words({'phone': 'Phone, 390 x 844', 'unfolded': 'The opened Fold, 880 x 1000', 'mac': 'Mac, 1280 x 800'}[name]!, Offset(margin, top + 12), 30, FontWeight.w700);
          var left = margin;
          for (final (screen, image) in images) {
            final w = image.width * rowHeight / image.height;
            words(screen, Offset(left, top + band + 14), 22, FontWeight.w500);
            final at = Rect.fromLTWH(left, top + band * 2, w, rowHeight);
            canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), at, Paint()..filterQuality = FilterQuality.medium);
            canvas.drawRect(at, Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = ink.withValues(alpha: 0.18));
            left += w + gap;
          }
          top += band * 2 + rowHeight + margin;
        }
        final sheet = await recorder.endRecording().toImage(width.round(), height.round());
        final bytes = await sheet.toByteData(format: ui.ImageByteFormat.png);
        File('$folder/contact-sheet-$theme.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }, skip: !shots);
  }
}
