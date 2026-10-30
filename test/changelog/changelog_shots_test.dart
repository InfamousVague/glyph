// Review pictures of What's new and the Changelog (lib/changelog; Matt, 2026-10-30: "Add a changelog popup modal that
// shows after every update with iconography"): the card over the app after an update to the newest release, the card
// for several versions skipped, and Settings › About › Changelog; on a phone, the opened Fold and the Mac, light and
// dark.
//
// Not held: `FEATURE_SHOTS=1 flutter test --update-goldens test/changelog/changelog_shots_test.dart` writes them into
// build/feature-shots/changelog/.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/style_sheets.dart';
import 'package:ghost_md/changelog/changelog.dart';
import 'package:ghost_md/changelog/whats_new.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:glacier/glacier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  final shots = Platform.environment.containsKey('FEATURE_SHOTS');
  const folder = '../../build/feature-shots/changelog';
  final changelog = Changelog.parse(File(changelogAsset).readAsStringSync());
  final newest = changelog.newest!.version;
  setUp(() {
    useStored(MemoryStored());
    debugUseChangelog(changelog);
  });
  tearDown(() => debugUseChangelog(null));

  const windows = [(name: 'phone', size: Size(390, 844), mac: false), (name: 'fold', size: Size(880, 1000), mac: false), (name: 'mac', size: Size(1280, 800), mac: true)];

  Future<void> pump(WidgetTester tester, [int times = 6]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> launch(WidgetTester tester, {required Size size, required bool mac, required String theme, required String lastSeen}) async {
    SharedPreferences.setMockInitialValues({
      PreferencesStore.storageKey: jsonEncode({'theme': theme, 'experience': 'advanced', 'experienceChosen': true}),
      'glyph-header-toolbar': HeaderToolbarVersion.groupedCommand.id,
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    preferences.forget();
    if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    debugDisableShadows = false;
    const ratio = 2.0;
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    tester.view.padding = const FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
    tester.view.viewPadding = const FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
    addTearDown(tester.view.reset);
    final sheet = await tester.runAsync(() => loadTokenSheet(more: appStyleSheets));
    await tester.pumpWidget(
      GhostApp(
        sheet: sheet!,
        home: GhostRoot(
          launch: false,
          library: SampleLibrary.seeded(),
          stored: MemoryStored(),
          workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
          clock: () => seedNow,
          whatsNew: WhatsNew(store: MemoryStored({whatsNewSeenKey: lastSeen}), usedBefore: true, runningVersion: newest),
        ),
      ),
    );
    await pump(tester, 14);
    // The ghost's picture read from the bundle, which takes real time.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await pump(tester, 4);
  }

  Future<void> close(WidgetTester tester) async {
    headerToolbarChoice.set(HeaderToolbarVersion.fallback.id);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  }

  for (final window in windows) {
    for (final theme in ['light', 'dark']) {
      final look = '${window.name}-$theme';
      testWidgets('a picture: What\'s new after an update, $look', (tester) async {
        await launch(tester, size: window.size, mac: window.mac, theme: theme, lastSeen: changelog.releases[1].version);
        await expectLater(find.byType(GhostApp), matchesGoldenFile('$folder/whats-new-$look.png'));
        await close(tester);
      }, skip: !shots);

      testWidgets('a picture: What\'s new with versions skipped, $look', (tester) async {
        await launch(tester, size: window.size, mac: window.mac, theme: theme, lastSeen: changelog.releases[4].version);
        await expectLater(find.byType(GhostApp), matchesGoldenFile('$folder/whats-new-skipped-$look.png'));
        await close(tester);
      }, skip: !shots);

      testWidgets('a picture: the Changelog page, $look', (tester) async {
        await launch(tester, size: window.size, mac: window.mac, theme: theme, lastSeen: changelog.releases[1].version);
        await tester.tap(find.byKey(WhatsNewCard.seeAllKey));
        await pump(tester, 16);
        await expectLater(find.byType(GhostApp), matchesGoldenFile('$folder/changelog-page-$look.png'));
        await close(tester);
      }, skip: !shots);
    }
  }

  testWidgets('a picture: What\'s new in Calm, on a phone', (tester) async {
    await launch(tester, size: windows.first.size, mac: false, theme: 'light', lastSeen: changelog.releases[4].version);
    preferences.update((now) => now.copyWith(calm: true));
    await pump(tester, 4);
    await expectLater(find.byType(GhostApp), matchesGoldenFile('$folder/whats-new-skipped-phone-calm.png'));
    await close(tester);
  }, skip: !shots);
}
