// The palette's "This note" commands in the app put together (lib/root/ghost_root.dart `_commandsPart`), where
// they differed from Ghost.md's (docs/PARITY.md, Differs 30): App.tsx hands the palette
// `archive: (id) => actions.archive(note, true)` and `pin: (id) => actions.pin(note)`, so archiving leaves the
// note's tab where it is and says so with an Undo, and a pin is the note actions' pin, which gives the tick.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../commands/support.dart' show settle, type;
import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Archive this note leaves the note’s tab open and offers its Undo; Pin is the note actions’ pin', (tester) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    AppShellState shell() => tester.state<AppShellState>(find.byType(AppShell));
    shell().openNote('groceries');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> choose(String query, String row) async {
      tester.state<CommandBarState>(find.byType(CommandBar)).show();
      await settle(tester);
      await type(tester, query);
      await tester.tap(find.text(row, findRichText: true).last);
      await settle(tester);
    }

    await choose('pin', 'Pin it to the top');
    expect(library.noteOf('groceries')!.starred, isTrue);
    expect(shell().shown, 'groceries');

    await choose('archive', 'Archive this note');
    expect(library.noteOf('groceries')!.archivedAt, isNotNull);
    expect(shell().tabs.open, contains('groceries'), reason: 'the page’s palette leaves the tab');
    expect(shell().shown, 'groceries');
    expect(find.text('Archived “Groceries”.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    shell().backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  });
}
