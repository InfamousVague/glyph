import 'dart:convert';

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
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:ghost_md/simple/simple_home.dart';
import 'package:glacier/glacier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/render.dart';

/// The home page with the header toolbar's Grouped command chosen, in the app put together and launched with the
/// choice already kept on the device (Matt, 2026-10-28: "remove the search bar from the home page since it's
/// redundant", and on 2.3.62: "the search bar still shows up on the home page section"). No search field in any
/// home layout - the advanced home, the home filtered to a workspace, and the opened Fold's two panes, whose notes
/// column is simple mode's list with a field of its own - and the filters still there. The same launches with
/// nothing chosen keep every field, so each check here can fail.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const phone = Size(390, 844), unfolded = Size(880, 1000);

  /// The app launched as a device that has kept [kept] opens it: the preferences and the device's own words read
  /// before the first frame, by the app itself.
  Future<void> launch(WidgetTester tester, {required Size size, required String? version, Stored? stored, String? workspace}) async {
    SharedPreferences.setMockInitialValues({
      PreferencesStore.storageKey: jsonEncode({'theme': 'light', 'experience': 'advanced', 'experienceChosen': true}),
      'glyph-header-toolbar': ?version,
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
    headerToolbarChoice.set(HeaderToolbarVersion.today.id);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

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
    testWidgets('with Grouped command kept before launch: no search field in ${layout.name}, and the filters there', (tester) async {
      final semantics = tester.ensureSemantics();
      final stored = MemoryStored();
      if (layout.panes) writeSidebarShown(true, stored);
      await launch(tester, size: layout.size, version: HeaderToolbarVersion.groupedCommand.id, stored: stored, workspace: layout.workspace);
      expect(headerToolbarVersion, HeaderToolbarVersion.groupedCommand, reason: 'read from the device before the first frame');
      expect(find.byType(HomeScreen), findsOneWidget);
      if (layout.panes) expect(find.byType(SimpleHome), findsOneWidget, reason: 'the notes column beside the home page');
      // The bar's title pill is the search.
      expect(find.byKey(HeaderAct.keyOf('search')), findsOneWidget);
      expect(fields(), findsNothing);
      expect(find.byWidgetPredicate((widget) => widget is Semantics && (widget.properties.label ?? '').startsWith('Filters')), findsWidgets);
      semantics.dispose();
      await close(tester);
    });

    testWidgets('with nothing kept: ${layout.name} keeps its search field', (tester) async {
      final semantics = tester.ensureSemantics();
      final stored = MemoryStored();
      if (layout.panes) writeSidebarShown(true, stored);
      await launch(tester, size: layout.size, version: null, stored: stored, workspace: layout.workspace);
      expect(headerToolbarVersion, HeaderToolbarVersion.today);
      expect(fields(), layout.panes ? findsNWidgets(2) : findsOneWidget);
      semantics.dispose();
      await close(tester);
    });
  }

  testWidgets('chosen after launch, the opened Fold’s notes column loses its field too, and gets it back', (tester) async {
    final semantics = tester.ensureSemantics();
    final stored = MemoryStored();
    writeSidebarShown(true, stored);
    await launch(tester, size: unfolded, version: null, stored: stored);
    expect(fields(), findsNWidgets(2));
    headerToolbarChoice.set(HeaderToolbarVersion.groupedCommand.id);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(fields(), findsNothing);
    headerToolbarChoice.set(HeaderToolbarVersion.grouped.id);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(fields(), findsNWidgets(2));
    semantics.dispose();
    await close(tester);
  });
}
