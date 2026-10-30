// What a screen reader is given of two things a walk on the emulator did not find in `uiautomator`'s list (README,
// "What stage 7 left open"): the rows of the + sheet, and (test/account_ui/reference_test.dart) the organization's
// New. Each is in the semantics tree the app hands the phone, reached from its root: a button, pressed by a tap,
// called by its words.
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/notes/daily_notes.dart' show dailyTitle;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// Every node the phone is handed, from the root down, in the order it is handed them.
List<SemanticsData> handed(WidgetTester tester) {
  final nodes = <SemanticsData>[];
  void walk(SemanticsNode node) {
    nodes.add(node.getSemanticsData());
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return nodes;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  testWidgets('the + sheet is a dialog called New, and each of its rows a button called by its words and its line', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: SampleLibrary.seeded(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.widget<AppShell>(find.byType(AppShell)).onNew!();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final nodes = handed(tester);
    final sheet = nodes.firstWhere((node) => node.flagsCollection.scopesRoute);
    expect(sheet.label, 'New');
    final rows = [for (final node in nodes) if (node.flagsCollection.isButton && node.hasAction(SemanticsAction.tap)) node.label];
    expect(rows, [
      'Note\nA page of markdown, typed or said.',
      // One of your templates, chosen (lib/root/root_templates.dart; Matt, 2026-10-30).
      'New from template…\nOne of your templates, its date, time and name filled in.',
      // Today's note (lib/notes/daily_notes.dart), the port's own, named by the phone's day.
      'Today\nThe note for ${dailyTitle(DateTime.now())}, opened, or made the first time.',
      'Canvas\nCards on a page with lines between them.',
      'Notebook\nNotes in an order with an index, or a journal of dated entries.',
    ]);
    // And what is under the sheet is not offered while it is up: the sheet is the whole of what can be pressed.
    expect(nodes.where((node) => node.hasAction(SemanticsAction.tap) && !node.flagsCollection.isButton && node.label.isNotEmpty), isEmpty);
    handle.dispose();
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
