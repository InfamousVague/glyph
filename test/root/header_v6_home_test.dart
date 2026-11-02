import 'dart:convert';

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
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart' show AllNotesScreen;
import 'package:ghost_md/notes/icon_browser.dart' show IconBrowser, browseViewKey;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/page_dock.dart' show dockScrolledScale;
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:ghost_md/simple/simple_home.dart';
import 'package:glacier/glacier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/render.dart';

/// The home page under the header toolbar's line, Grouped command, in the app put together and launched (Matt,
/// 2026-10-28: "remove the search bar from the home page since it's redundant", and on 2.3.62: "the search bar still
/// shows up on the home page section"). No search field in any home layout - the advanced home, the home filtered to a
/// workspace, and the opened Fold's two panes, whose notes column is simple mode's list with a field of its own - and
/// the filters in the bar. Since the contact sheet ended with Grouped command (Matt, 2026-11-01: "we currently have too
/// many appearance settings for different title bar layouts and stuff") it is the only line, and a device that had
/// kept another version's word (`glyph-header-toolbar`: today's bar, Command centre…) launches on it all the same.
/// Simple mode, with no bar, keeps its field (test/simple), so the check for none can fail.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const phone = Size(390, 844), unfolded = Size(880, 1000);

  /// The app launched as a device opens it: the preferences and the device's own words read before the first frame, by
  /// the app itself. [kept] is a header toolbar's word an older build kept (`glyph-header-toolbar`), which is read by
  /// nothing now.
  Future<void> launch(WidgetTester tester, {required Size size, String? kept, Stored? stored, String? workspace, String experience = 'advanced'}) async {
    SharedPreferences.setMockInitialValues({
      PreferencesStore.storageKey: jsonEncode({'theme': 'light', 'experience': experience, 'experienceChosen': true}),
      'glyph-header-toolbar': ?kept,
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
    final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces()));
    if (workspace != null) spaces.chooseWorkspace(workspace);
    final sheet = await tester.runAsync(() => loadTokenSheet(more: appStyleSheets));
    await tester.pumpWidget(
      GhostApp(
        sheet: sheet!,
        home: GhostRoot(launch: false, library: SampleLibrary.seeded(), stored: stored ?? MemoryStored(), workspaces: spaces, clock: () => seedNow),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  /// The filters' button, by what it says: "Filters", or "Filters: Notebooks" with one chosen.
  Finder filtersButton() => find.byWidgetPredicate((widget) => widget is Semantics && (widget.properties.button ?? false) && (widget.properties.label ?? '').startsWith('Filters'));

  /// A row of the filters' panel, by the start of what it says ("Notebooks, 3").
  Finder radio(String starts) => find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.checked != null && (widget.properties.label ?? '').startsWith(starts));

  /// Every search field a home page draws: the advanced page's, and simple mode's list's.
  Finder fields() => find.byWidgetPredicate(
        (widget) => widget is Semantics && (widget.properties.textField ?? false) && (widget.properties.label == 'Search notebooks and notes' || widget.properties.label == 'Search'),
      );

  final layouts = [
    (name: 'the advanced home on a phone', size: phone, workspace: null, panes: false),
    (name: 'the advanced home filtered to a workspace on a phone', size: phone, workspace: 'work', panes: false),
    (name: 'the advanced home on the opened Fold', size: unfolded, workspace: null, panes: false),
    (name: 'the advanced home filtered to a workspace on the opened Fold', size: unfolded, workspace: 'work', panes: false),
    (name: 'the opened Fold’s two panes, the notes column beside the home page', size: unfolded, workspace: null, panes: true),
  ];

  for (final layout in layouts) {
    // Nothing kept, and the words two of the old versions were kept as: Grouped command in each.
    for (final kept in [null, 'today', 'command']) {
      testWidgets('with ${kept ?? 'nothing'} kept before launch: no search field in ${layout.name}, and the filters in the bar', (tester) async {
        final semantics = tester.ensureSemantics();
        final stored = MemoryStored();
        if (layout.panes) writeSidebarShown(true, stored);
        await launch(tester, size: layout.size, kept: kept, stored: stored, workspace: layout.workspace);
        expect(tester.takeException(), isNull);
        expect(find.byKey(HeaderAct.keyOf('home')), findsOneWidget, reason: 'Home always');
        expect(find.byType(HomeScreen), findsOneWidget);
        if (layout.panes) expect(find.byType(SimpleHome), findsOneWidget, reason: 'the notes column beside the home page');
        // The bar's title pill is the search.
        expect(find.byKey(HeaderAct.keyOf('search')), findsOneWidget);
        expect(fields(), findsNothing);
        // The filters' button is the bar's, beside the title pill, and not the page's (Matt, 2026-10-29).
        expect(find.byKey(HeaderAct.keyOf('filters')), findsOneWidget);
        expect(find.descendant(of: find.byType(HomeScreen), matching: filtersButton()), findsNothing);
        semantics.dispose();
        await close(tester);
      });
    }
  }

  // Matt, 2026-10-29: "also remove this filter button on the home page, when on the homepage add it next to the command
  // search bar in the top bar".
  for (final size in [phone, unfolded]) {
    testWidgets('the bar’s Filters opens the page’s panel under it, and Notebooks filters the list (${size.width.round()})', (tester) async {
      final semantics = tester.ensureSemantics();
      await launch(tester, size: size);
      final bar = find.byKey(HeaderAct.keyOf('filters'));
      final button = tester.getRect(bar);
      await tester.tap(bar);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The same panel: Show with its counts and the chosen one ticked, and Workspace.
      final all = radio('All, ');
      expect(all, findsOneWidget);
      expect(tester.widget<Semantics>(all).properties.checked, isTrue);
      expect(radio('Notebooks, '), findsOneWidget);
      expect(find.text('Every workspace'), findsOneWidget);
      // Hung under the bar's button.
      expect(tester.getRect(all).top, greaterThan(button.bottom));
      await tester.tap(radio('Notebooks, '));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The page shows notebooks alone: its chip says so, and the bar's button says what is on.
      expect(find.bySemanticsLabel('Notebooks: show everything'), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.bySemanticsLabel('Filters: Notebooks')), findsOneWidget);
      semantics.dispose();
      await close(tester);
    });
  }

  testWidgets('on a note: no Filters in the bar', (tester) async {
    await launch(tester, size: unfolded);
    expect(find.byKey(HeaderAct.keyOf('filters')), findsOneWidget);
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    shell.openNote(shell.notes.first.id);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(HeaderAct.keyOf('view')), findsOneWidget, reason: 'a note is up');
    expect(find.byKey(HeaderAct.keyOf('filters')), findsNothing);
    await close(tester);
  });

  // Matt, 2026-10-29, of the opened Fold's notes column beside the home page: "remove these icons from the sidebar" -
  // its microphone and its +, which the home page's dock has.
  testWidgets('the advanced sidebar has no + and no microphone at its foot', (tester) async {
    final stored = MemoryStored();
    writeSidebarShown(true, stored);
    await launch(tester, size: unfolded, stored: stored);
    expect(find.byType(SimpleHome), findsOneWidget);
    expect(find.byKey(const ValueKey('simple-new')), findsNothing);
    expect(find.byKey(const ValueKey('simple-speak')), findsNothing);
    await close(tester);
  });

  testWidgets('simple mode’s own home keeps its + on the opened Fold', (tester) async {
    await launch(tester, size: unfolded, experience: 'simple');
    expect(find.byType(SimpleHome), findsOneWidget);
    expect(find.byKey(const ValueKey('simple-new')), findsOneWidget);
    await close(tester);
  });

  // Matt, 2026-10-29, on 2.3.66, of History in Grouped command's note pill: "the history dropdown starts too low not
  // under the buttons as expected". The side panel's card hangs from the control that opened it.
    for (final size in [unfolded, const Size(1280, 800)]) {
      // History opens the side panel on a desktop (on a phone it is the note's sheet, lib/root/ghost_root.dart
      // `_asideHistoryOf`); the side panel's own toggle opens it anywhere.
      final mac = size.width > 1000;
      testWidgets('on a note, ${mac ? 'the Mac' : 'the opened Fold'}: the side panel hangs just under the control that opened it${mac ? ', History' : ''}', (tester) async {
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await launch(tester, size: size);
        final shell = tester.state<AppShellState>(find.byType(AppShell));
        shell.openNote(shell.notes.first.id);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        Future<void> opens(Finder control, {Finder? menu}) async {
          final button = tester.getRect(control);
          await tester.tap(control);
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (menu != null) {
            await tester.tap(menu);
            for (var i = 0; i < 4; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          final card = tester.getRect(find.byKey(const ValueKey('floating-card')));
          expect(card.top - button.bottom, inInclusiveRange(0, 12), reason: 'the card at $card, the button at $button');
          expect(card.left >= 0 && card.right <= size.width, isTrue, reason: 'the card at $card in a ${size.width} window');
          // Shut again by the back gesture, for the next.
          await tester.binding.handlePopRoute();
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byKey(const ValueKey('floating-card')), findsNothing);
        }

        if (mac) {
          final history = find.byKey(HeaderAct.keyOf('history'));
          if (history.evaluate().isNotEmpty) {
            await opens(history);
          } else {
            // Where History is under •••, its card hangs from •••.
            await opens(find.byKey(HeaderAct.keyOf('overflow')).last, menu: find.byKey(HeaderAct.keyOf('history')).last);
          }
        }
        // The side panel itself: the aside's own circle, or its row under •••.
        final aside = find.byKey(HeaderAct.keyOf('aside'));
        if (aside.evaluate().isNotEmpty) {
          await opens(aside);
        } else {
          await opens(find.byKey(HeaderAct.keyOf('overflow')).last, menu: find.byKey(HeaderAct.keyOf('aside')).last);
        }
        await close(tester);
        debugDefaultTargetPlatformOverride = null;
      });
    }

  // Matt, 2026-10-29: "add a folder icon to the top near home and sidebar to show all notes in the folder / icon view".
    for (final size in [phone, unfolded]) {
      testWidgets('${size.width.round()} wide: the folder under the bar’s ••• opens All notes in its icon view, nothing kept', (tester) async {
        final semantics = tester.ensureSemantics();
        final stored = MemoryStored();
        await launch(tester, size: size, stored: stored);
        // Under •••, not in the row (Matt, 2026-10-29: "Put the all files folder icon under the more menu as well as
        // the + button in the header").
        final folder = find.byKey(HeaderAct.keyOf('folders'));
        expect(folder, findsNothing);
        expect(find.byKey(HeaderAct.keyOf('home')), findsOneWidget);
        await tester.tap(find.byKey(HeaderAct.keyOf('overflow')).last);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(folder, findsOneWidget);
        await tester.tap(folder);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(AllNotesScreen), findsOneWidget);
        expect(find.byType(IconBrowser), findsOneWidget, reason: 'the icon view, the folders first');
        // For this visit: the view the page keeps for itself is as it was.
        expect(stored.readText(browseViewKey), isNull);
        semantics.dispose();
        await close(tester);
      });
    }

  // Matt, 2026-10-29: "also on desktop the default size of the dock can be the size it collapses to".
  for (final mac in [false, true]) {
    testWidgets('the home page’s dock rests ${mac ? 'at the smaller size on the Mac' : 'whole on a phone'}', (tester) async {
      if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await launch(tester, size: mac ? const Size(1280, 800) : phone);
      final scale = tester.widget<ScaleTransition>(find.byKey(const ValueKey('page-dock-scale')).first).scale.value;
      expect(scale, mac ? dockScrolledScale : 1);
      if (mac) {
        // As the bar's own rings, which are the dock's at that scale.
        final t = GlacierTheme.of(tester.element(find.byType(HomeScreen)));
        expect((tester.getRect(find.byKey(HeaderAct.keyOf('filters'))).height - t.len('app-ring') * dockScrolledScale).abs(), lessThan(1));
      }
      await close(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  // Matt, 2026-11-01: the contact sheet ended with Grouped command, and its choice went. Every word an older build kept
  // (`glyph-header-toolbar`: the six versions' and one this build never knew) is read by nothing: the app launches on
  // Grouped command whichever it was, and nothing is thrown.
  for (final kept in ['today', 'grouped', 'tiles', 'command', 'labelled', 'groupedCommand', 'strip']) {
    testWidgets('a device that had kept $kept launches on Grouped command', (tester) async {
      await launch(tester, size: phone, kept: kept);
      expect(tester.takeException(), isNull);
      expect(find.byKey(HeaderAct.keyOf('search')), findsOneWidget, reason: 'the title pill');
      expect(find.byKey(HeaderAct.keyOf('you')), findsOneWidget, reason: 'the button for you');
      expect(fields(), findsNothing);
      await close(tester);
    });
  }
}
