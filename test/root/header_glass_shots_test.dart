import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/style_sheets.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:glacier/glacier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/render.dart';

/// Pictures, not held, of the header's glass with the page run up under it (Matt, 2026-11-01: "the header is a mix of
/// glass and not glass elements, make the header 50% darker glass and make sure all components in the header support
/// glass"): the app launched with nothing kept (Grouped command), the home page scrolled so its cards pass under the
/// bar, on a phone and the Mac, light and dark. With nothing under it the glass is only its tint; these show the blur
/// and every control's glass over what scrolls.
///
/// `FEATURE_SHOTS=1 flutter test --update-goldens test/root/header_glass_shots_test.dart` writes each into
/// build/feature-shots/header-glass/.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  final shots = Platform.environment.containsKey('FEATURE_SHOTS');
  const folder = 'build/feature-shots/header-glass';

  const windows = [
    (name: 'phone', size: Size(390, 844), mac: false),
    (name: 'mac', size: Size(1280, 800), mac: true),
  ];

  Future<void> pump(WidgetTester tester, [int times = 8]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final window in windows) {
    for (final theme in ['light', 'dark']) {
      testWidgets('a picture: the header over the scrolled home page, ${window.name}, $theme', (tester) async {
        if (window.mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          SharedPreferences.setMockInitialValues({
            PreferencesStore.storageKey: jsonEncode({'theme': theme, 'experience': 'advanced', 'experienceChosen': true}),
          });
          addTearDown(() => SharedPreferences.setMockInitialValues({}));
          preferences.forget();
          debugDisableShadows = false;
          const ratio = 2.0;
          tester.view.physicalSize = window.size * ratio;
          tester.view.devicePixelRatio = ratio;
          tester.view.padding = const FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
          tester.view.viewPadding = const FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
          addTearDown(tester.view.reset);
          final sheet = await tester.runAsync(() => loadTokenSheet(more: appStyleSheets));
          await tester.pumpWidget(
            GhostApp(
              sheet: sheet!,
              home: GhostRoot(launch: false, library: SampleLibrary.seeded(), stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
            ),
          );
          await pump(tester, 12);
          // The page's own scroller, the tallest: run it up a third of the window, so its cards are under the bar.
          final scrollers = tester.widgetList<Scrollable>(find.byType(Scrollable)).toList();
          ScrollableState? tallest;
          var most = 0.0;
          for (final each in find.byType(Scrollable).evaluate()) {
            final state = (each as StatefulElement).state as ScrollableState;
            if (state.position.axis != Axis.vertical) continue;
            final height = each.size?.height ?? 0;
            if (height > most) {
              most = height;
              tallest = state;
            }
          }
          expect(scrollers, isNotEmpty);
          tallest!.position.jumpTo((tallest.position.maxScrollExtent).clamp(0, window.size.height / 3));
          await pump(tester, 10);
          await expectLater(find.byType(GhostApp), matchesGoldenFile('../../$folder/home-scrolled-${window.name}-$theme.png'));
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
