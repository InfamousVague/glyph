// What's new in the app put together (lib/changelog/whats_new.dart; Matt, 2026-10-30: "Add a changelog popup modal that
// shows after every update with iconography"): shown once after an update and never on a fresh install; the versions
// skipped grouped; waiting for the walkthrough, a recording and any other sheet; Got it keeping the version; See all changes, the
// command search ("changelog", "what's new") and Settings › About opening the Changelog page; in Simple too; on a phone
// and on a desktop's window, where it is a card in the middle.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/activity/activity_cost.dart';
import 'package:ghost_md/app/style_sheets.dart';
import 'package:ghost_md/changelog/changelog.dart';
import 'package:ghost_md/changelog/changelog_pane.dart';
import 'package:ghost_md/changelog/whats_new.dart';
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/core/background_jobs.dart' show JobEstimate;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/guide/guide_state.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:ghost_md/shell/screen.dart';
import 'package:glacier/glacier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  final changelog = Changelog.parse(File(changelogAsset).readAsStringSync());
  final newest = changelog.newest!.version;
  setUp(() {
    useStored(MemoryStored());
    debugUseChangelog(changelog);
  });
  tearDown(() => debugUseChangelog(null));

  const phone = Size(390, 844), desktop = Size(1280, 800);

  Future<void> pump(WidgetTester tester, [int times = 6]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder card() => find.byKey(const ValueKey('whats-new'));

  /// The app launched on [newest] with [whatsNew]; [guide] up over it where given.
  Future<void> launch(WidgetTester tester, {required WhatsNew whatsNew, Size size = phone, GuideController? guide, String experience = 'advanced', bool mac = false}) async {
    SharedPreferences.setMockInitialValues({
      PreferencesStore.storageKey: jsonEncode({'theme': 'light', 'experience': experience, 'experienceChosen': true}),
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
        home: GhostRoot(launch: false, library: SampleLibrary.seeded(), stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, guide: guide, whatsNew: whatsNew),
      ),
    );
    await pump(tester, 12);
  }

  Future<void> close(WidgetTester tester) async {
    headerToolbarChoice.set(HeaderToolbarVersion.fallback.id);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  }

  String? shownPage(WidgetTester tester) => tester.state<SettingsScreenState>(find.byType(SettingsScreen)).activeId;

  WhatsNew updatedFrom(MemoryStored store) => WhatsNew(store: store, usedBefore: true, runningVersion: newest);

  for (final size in [phone, desktop]) {
    final at = size == phone ? 'a phone' : 'a desktop';
    final mac = size == desktop;

    testWidgets('on $at: after an update, shown once; Got it keeps the version and the next launch shows nothing', (tester) async {
      final store = MemoryStored({whatsNewSeenKey: changelog.releases[1].version});
      await launch(tester, whatsNew: updatedFrom(store), size: size, mac: mac);
      expect(card(), findsOneWidget);
      expect(find.text("What's new in Ghost.md $newest"), findsOneWidget);
      for (final item in changelog.newest!.items) {
        expect(find.text(item.words), findsOneWidget);
      }
      final panel = tester.getRect(find.byKey(const ValueKey('sheet-panel')));
      if (mac) {
        expect(panel.center.dx, moreOrLessEquals(size.width / 2, epsilon: 1), reason: 'a card in the middle');
      } else {
        expect(panel.bottom, moreOrLessEquals(size.height, epsilon: 1), reason: 'a sheet from the foot');
      }
      await tester.tap(find.byKey(WhatsNewCard.gotItKey));
      await pump(tester, 6);
      expect(card(), findsNothing);
      expect(store.readText(whatsNewSeenKey), newest);
      await close(tester);
      await launch(tester, whatsNew: updatedFrom(store), size: size, mac: mac);
      expect(card(), findsNothing, reason: 'seen once');
      await close(tester);
    });
  }

  testWidgets('a fresh install: nothing, and the version kept so the next update is the first shown', (tester) async {
    final store = MemoryStored();
    await launch(tester, whatsNew: WhatsNew(store: store, runningVersion: newest));
    expect(card(), findsNothing);
    expect(store.readText(whatsNewSeenKey), newest);
    await close(tester);
  });

  testWidgets('versions skipped: each under its own heading, newest first, five and then "and earlier changes"', (tester) async {
    final store = MemoryStored({whatsNewSeenKey: '2.3.70'});
    await launch(tester, whatsNew: updatedFrom(store), size: const Size(390, 844));
    expect(card(), findsOneWidget);
    final versions = [for (final release in changelog.releases.take(5)) release.version];
    final tops = <double>[];
    for (final version in versions) {
      final heading = find.descendant(of: card(), matching: find.text(version), skipOffstage: false);
      expect(heading, findsOneWidget, reason: version);
      tops.add(tester.getTopLeft(heading).dy);
    }
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.text(changelog.releases[5].version, skipOffstage: false), findsNothing, reason: 'five at most');
    expect(find.text('…and earlier changes', skipOffstage: false), findsOneWidget);
    await close(tester);
  });

  testWidgets('waits for the walkthrough, and comes once it is closed', (tester) async {
    final guide = GuideController()..show(0);
    await launch(tester, whatsNew: updatedFrom(MemoryStored({whatsNewSeenKey: changelog.releases[1].version})), guide: guide);
    expect(card(), findsNothing, reason: 'never over the walkthrough');
    guide.close();
    await pump(tester, 6);
    expect(card(), findsOneWidget);
    await close(tester);
  });

  testWidgets('waits for a recording, and comes once it is over', (tester) async {
    // The version told only once a recording is on screen (no version of its own: the root's is the development
    // build's, which has no entry), as a phone's answer can come while one records.
    final whatsNew = WhatsNew(store: MemoryStored({whatsNewSeenKey: changelog.releases[1].version}), usedBefore: true);
    await launch(tester, whatsNew: whatsNew);
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    shell.show(ScreenCapture.fresh(false));
    await pump(tester, 2);
    expect(shell.screen.isRecording, isTrue);
    whatsNew.settle(changelog: changelog, running: newest);
    await pump(tester, 6);
    expect(whatsNew.waiting, isNotNull);
    expect(card(), findsNothing, reason: 'never over a recording');
    shell.show(const Screen.list());
    await pump(tester, 6);
    expect(card(), findsOneWidget);
    await close(tester);
  });

  testWidgets('waits for any sheet over the app (a question, a plugin\'s setup), and comes once it is put away', (tester) async {
    final whatsNew = WhatsNew(store: MemoryStored({whatsNewSeenKey: changelog.releases[1].version}), usedBefore: true);
    await launch(tester, whatsNew: whatsNew);
    final asked = askJobCost(tester.element(find.byType(AppShell)), const JobEstimate(credits: 72, provider: 'Lovart', count: 12, one: 'header image', many: 'header images'), title: 'Make header images?');
    await pump(tester, 3);
    expect(Sheet.shown.value, 1);
    whatsNew.settle(changelog: changelog, running: newest);
    await pump(tester, 6);
    expect(card(), findsNothing, reason: 'never over another sheet');
    await tester.tap(find.byKey(const ValueKey('cost-ask-cancel')));
    expect(await asked, isFalse);
    await pump(tester, 6);
    expect(card(), findsOneWidget);
    await close(tester);
  });

  testWidgets('in Simple too', (tester) async {
    await launch(tester, whatsNew: updatedFrom(MemoryStored({whatsNewSeenKey: changelog.releases[1].version})), experience: 'simple');
    expect(card(), findsOneWidget);
    await close(tester);
  });

  testWidgets('See all changes keeps the version and opens the Changelog page in Settings', (tester) async {
    final store = MemoryStored({whatsNewSeenKey: changelog.releases[1].version});
    await launch(tester, whatsNew: updatedFrom(store));
    await tester.tap(find.byKey(WhatsNewCard.seeAllKey));
    await pump(tester, 10);
    expect(card(), findsNothing);
    expect(store.readText(whatsNewSeenKey), newest);
    expect(shownPage(tester), 'changelog');
    expect(find.byType(ChangelogPane), findsOneWidget);
    await close(tester);
  });

  for (final query in ['changelog', "what's new"]) {
    testWidgets('the command search finds the Changelog by "$query"', (tester) async {
      await launch(tester, whatsNew: updatedFrom(MemoryStored({whatsNewSeenKey: newest})));
      expect(card(), findsNothing);
      tester.state<CommandBarState>(find.byType(CommandBar)).show();
      await pump(tester);
      await tester.enterText(find.descendant(of: find.byType(GlacierCommandPalette), matching: find.byType(EditableText)), query);
      await pump(tester);
      final row = find.descendant(of: find.byType(GlacierCommandPalette), matching: find.textContaining('What’s new', findRichText: true));
      // Under the app's own commands, first; Settings' Changelog page after it.
      expect(row, findsWidgets);
      await tester.tap(row.first);
      await pump(tester, 10);
      expect(shownPage(tester), 'changelog');
      await close(tester);
    });
  }

  testWidgets('Settings › About › Changelog opens the page', (tester) async {
    await launch(tester, whatsNew: updatedFrom(MemoryStored({whatsNewSeenKey: newest})), size: const Size(390, 1600));
    tester.state<CommandBarState>(find.byType(CommandBar)).show();
    await pump(tester);
    await tester.enterText(find.descendant(of: find.byType(GlacierCommandPalette), matching: find.byType(EditableText)), 'about');
    await pump(tester);
    // Settings, at About, as its own row opens it.
    final about = find.descendant(of: find.byType(GlacierCommandPalette), matching: find.text('About', findRichText: true));
    expect(about, findsWidgets);
    await tester.tap(about.first);
    await pump(tester, 10);
    expect(shownPage(tester), 'about');
    final changelogRow = find.byWidgetPredicate((w) => w is SettingRow && w.label == 'Changelog');
    await tester.ensureVisible(changelogRow);
    await tester.tap(changelogRow);
    await pump(tester, 10);
    expect(shownPage(tester), 'changelog');
    await close(tester);
  });
}
