// Claude on the dock only with a key (Matt, 2026-10-19: "the claude icon should only show up if the user has entered
// the antrhopic api key"): the Claude plugin on and no Anthropic API key on the device, no Claude ring on the home
// page's dock; a key entered, the ring comes at once; the key taken away, it goes again.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/claude_settings.dart' show claudeSettings;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the dock has Claude only once an API key is entered, and loses it when the key is removed', (tester) async {
    await tester.runAsync(() async {
      await claudeSettings.load();
      await claudeSettings.setKey(null);
    });
    addTearDown(() => claudeSettings.setKey(null));
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: SampleLibrary.seeded(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: MemoryStored()),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    Finder ring() => find.descendant(of: find.byType(HomeScreen), matching: find.byKey(const ValueKey('dock-claude')));
    expect(find.descendant(of: find.byType(HomeScreen), matching: find.byKey(const ValueKey('dock-add'))), findsOneWidget, reason: 'the dock is there');
    expect(ring(), findsNothing, reason: 'no key, no Claude');

    await tester.runAsync(() => claudeSettings.setKey('sk-ant-test-not-a-key'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ring(), findsOneWidget, reason: 'a key entered: Claude on the dock');

    await tester.runAsync(() => claudeSettings.setKey(null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ring(), findsNothing, reason: 'the key removed: Claude gone');

    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
