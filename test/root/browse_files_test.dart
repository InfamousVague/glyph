import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/library_folder.dart' show filesChannel;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// The notes' folder in the phone's Files app, in the app put together (lib/root; lib/core/library_files.dart): the
/// sidebar's Browse files is there once the phone has said it can show the folder, as NoteTree.tsx's was once
/// `canBrowseFiles()` had answered, and its press asks the phone. The activity is stood in for on its channel.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  /// Every call the activity was asked, in order.
  late List<String> asked;

  /// The activity as FilesBridge.kt answers it.
  void phone(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(filesChannel, (call) async {
      asked.add(call.method);
      return switch (call.method) { 'canBrowseFiles' => true, 'browseFiles' => null, _ => throw MissingPluginException() };
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(filesChannel, null));
  }

  Future<void> open(WidgetTester tester) async {
    asked = [];
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: SampleLibrary.seeded(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: MemoryStored()),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The notes' card, from the tab row's icon, at rest.
  Future<void> openSidebar(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('All your notes'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NoteTree), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  Finder tool() => find.bySemanticsLabel('Browse files');

  testWidgets('the sidebar offers Browse files once the phone has said it can, and a press opens the phone’s Files app', (tester) async {
    phone(tester);
    await open(tester);
    expect(asked, isEmpty, reason: 'nothing is asked until a sidebar is up');
    await openSidebar(tester);
    expect(tool(), findsOneWidget);
    await tester.tap(tool());
    await tester.pump();
    expect(asked, ['canBrowseFiles', 'browseFiles']);
    // Asked once: the card closed and opened again has its tool at once.
    tester.state<AppShellState>(find.byType(AppShell)).closeSidebar();
    await tester.pump(const Duration(milliseconds: 600));
    await openSidebar(tester);
    expect(tool(), findsOneWidget);
    expect(asked, ['canBrowseFiles', 'browseFiles']);
    await close(tester);
  });

  testWidgets('the sidebar has no Browse files where nothing answers for the phone', (tester) async {
    await open(tester);
    await openSidebar(tester);
    expect(tool(), findsNothing);
    await close(tester);
  });
}
