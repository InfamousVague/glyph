import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../support.dart';

export '../support.dart';

/// The workspaces the web page was measured over (the store pack's seed): Work in moss with ten notes filed, Home
/// in sea with three.
WorkspaceStore seededSpaces() => WorkspaceStore(
      storage: MemoryWorkspaceStorage(
        WorkspaceSheet(
          list: const [Workspace(id: 'work', name: 'Work', hue: 'moss'), Workspace(id: 'home', name: 'Home', hue: 'sea')],
          notes: {for (var i = 0; i < 10; i++) 'w$i': 'work', for (var i = 0; i < 3; i++) 'h$i': 'home'},
        ),
      ),
    );

/// The build the web page said it was when About was measured inside the app.
SettingsUpdates measuredUpdates({VoidCallback? onCheck}) => SettingsUpdates(version: '1.15.0', built: 'Oct 8, 02:55 AM', onCheck: onCheck ?? () {});

/// The web app's own test report, as its build of 2026-10-09 baked it in (../glyph
/// src/app/diag/testReport.generated.json at its commit 05dd0efc: 6084 passed, 149 skipped), kept in this
/// repository. It was read from the web app's checkout, which writes that file again every time its tests are run:
/// the picture drawn over it was red against its own reference the day after it was drawn, and both tests were
/// skipped wherever that checkout was not beside this one. Every suite's counts, which are what the page adds up,
/// are the report's own; each suite's list of tests is cut to its first six, all a shut card needs.
Map<String, Object?> webTestReport() => (jsonDecode(File('test/settings/panes/fixtures/web_test_report.json').readAsStringSync()) as Map).cast<String, Object?>();

/// Settings open at [page] (and through About for a sub-page, which is how a person gets there), over the real
/// sheet, on [size].
Future<void> openPane(
  WidgetTester tester,
  String page, {
  Size size = phone,
  Preferences prefs = const Preferences(theme: 'light'),
  WorkspaceStore? workspaces,
  SettingsUpdates? updates,
  SettingsFeatures features = const SettingsFeatures(),
  VoidCallback? onGuide,
  VoidCallback? onSample,
  VoidCallback? onGuideBook,
  VoidCallback? onBoard,
  VoidCallback? onCanvas,
  VoidCallback? onHowCanvas,
  VoidCallback? onAcademy,
  void Function(String)? onOrganization,
  void Function(String)? onOpenLink,
  List<String> Function(String)? notesInWorkspace,
  void Function(List<String>)? onTrashNotes,
  String? setting,
  bool developer = false,
}) async {
  // The hidden pages are sections only once they are unlocked, and a launch forgets the switch: so Settings comes up
  // first, and is sent to the page after.
  final target = ValueNotifier<SettingsTarget?>(developer ? null : SettingsTarget(page, setting: setting, nonce: 1));
  addTearDown(target.dispose);
  await pumpSettings(
    tester,
    ValueListenableBuilder<SettingsTarget?>(
      valueListenable: target,
      builder: (context, toPage, _) => SettingsSheet(
        open: true,
        onClose: () {},
        toPage: toPage,
        workspaces: workspaces,
        updates: updates,
        features: features,
        onGuide: onGuide,
        onSample: onSample,
        onGuideBook: onGuideBook,
        onBoard: onBoard,
        onCanvas: onCanvas,
        onHowCanvas: onHowCanvas,
        onAcademy: onAcademy,
        onOrganization: onOrganization,
        onOpenLink: onOpenLink,
        notesInWorkspace: notesInWorkspace,
        onTrashNotes: onTrashNotes,
      ),
    ),
    size: size,
    prefs: prefs,
  );
  if (developer) {
    developerMode.set(true);
    addTearDown(() => developerMode.set(false));
    await tester.pump();
    target.value = SettingsTarget(page, setting: setting, nonce: 1);
    await tester.pump();
    await settleSettings(tester);
  }
}

/// The page's title, or null on the list.
String? display(WidgetTester tester) {
  final found = find.byKey(const ValueKey('settings-display'));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

/// The cards' titles, in the page's order.
List<String?> cardTitles(WidgetTester tester) => [for (final card in tester.widgetList<PaneSection>(find.byType(PaneSection, skipOffstage: false))) card.title];

/// The rows' labels, of the whole page or of the card called [card].
List<String> rowLabels(WidgetTester tester, [String? card]) => [
      for (final row in tester.widgetList<SettingRow>(
        card == null ? find.byType(SettingRow, skipOffstage: false) : find.descendant(of: cardCalled(card), matching: find.byType(SettingRow, skipOffstage: false), skipOffstage: false),
      ))
        row.label,
    ];

Finder cardCalled(String title) => find.byWidgetPredicate((w) => w is PaneSection && w.title == title, skipOffstage: false);

/// The row whose label is [label].
Finder rowCalled(String label) => find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false);

/// Something inside the row called [label].
Finder inRow(String label, Finder what) => find.descendant(of: rowCalled(label), matching: what, skipOffstage: false);

/// The card's own surface: the rounded box its rows share (`.setk__card`).
Finder surfaceOf(Finder card) => find.descendant(of: card, matching: find.byType(ClipRRect, skipOffstage: false), skipOffstage: false).first;

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await settleSettings(tester);
}

/// Waits for the pictures on the screen (the ghost's), which a test's clock never loads by itself.
Future<void> loadPictures(WidgetTester tester) async {
  for (final element in find.byType(Image, skipOffstage: false).evaluate().toList()) {
    final image = (element.widget as Image).image;
    await tester.runAsync(() => precacheImage(image, element));
  }
  await tester.pump();
}
