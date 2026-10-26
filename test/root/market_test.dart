import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/commands/palette.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/notes/notes_drawer.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';

import '../support/render.dart';
import 'part_of.dart';

/// The Market in the app put together (Matt, 2026-10-26: "Make the plugins a dedicated "Market" section in the
/// app"): a place of the shell's, reached from the sidebar's row, the palette and Settings' row, each of which
/// shuts what it was in; a link to what was Settings › Plugins lands there; its way out is home; and simple mode has
/// none of the ways in.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Future<void> open(WidgetTester tester, {String experience = 'advanced'}) async {
    await pumpApp(
      tester,
      prefs: Preferences(theme: 'light', experience: experience, experienceChosen: true),
      home: GhostRoot(launch: false, library: SampleLibrary.seeded(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: MemoryStored()),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  AppShell shellWidget(WidgetTester tester) => tester.widget<AppShell>(find.byType(AppShell));
  List<PaletteCommand> palette(WidgetTester tester) {
    final bar = tester.widget<CommandBar>(find.byType(CommandBar));
    return paletteCommands(bar.worldNow!(), bar.doingNow!());
  }

  testWidgets('the sidebar’s row opens the Market, a place with the tab row, and its arrow goes home', (tester) async {
    await open(tester);
    final shell = shellOf(tester);
    final drawer = partOf<NotesDrawer>(shell.context, shellWidget(tester).sidebarBuilder!(shell.context, shell, () {}));
    drawer.onMarket!();
    await settle(tester);
    expect(shell.screen, const ScreenMarket());
    expect(shell.screen.isPlace, isTrue);
    expect(find.byType(MarketScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('market-back')));
    await settle(tester);
    expect(shell.screen, const ScreenList());
    await close(tester);
  });

  testWidgets('the palette’s Market opens it', (tester) async {
    await open(tester);
    palette(tester).singleWhere((command) => command.descriptor.id == 'market').run();
    await settle(tester);
    expect(shellOf(tester).screen, const ScreenMarket());
    expect(find.byType(MarketScreen), findsOneWidget);
    await close(tester);
  });

  testWidgets('Settings’ row, and a link to a plugin’s old page, shut Settings and open the Market there', (tester) async {
    // The plugins that ship, a fresh install's, as the app's.
    final before = plugins;
    addTearDown(() => usePlugins(before));
    usePlugins(createRegistry(builtIn, store: MemorySwitches()));
    await open(tester);
    final sheet = tester.widget<SettingsSheet>(find.byType(SettingsSheet));
    expect(sheet.onMarket, isNotNull);
    sheet.onMarket!(plugin: 'notion');
    await settle(tester);
    expect(shellOf(tester).screen, const ScreenMarket(plugin: 'notion'));
    expect(find.byKey(const ValueKey('market-detail-notion')), findsOneWidget);
    expect(tester.widget<SettingsSheet>(find.byType(SettingsSheet)).open, isFalse);
    // A plugin's Settings, from its page in the Market, opens Settings over it at the plugin's own page.
    tester.widget<MarketScreen>(find.byType(MarketScreen)).onPluginSettings!('notion');
    await settle(tester);
    final over = tester.widget<SettingsSheet>(find.byType(SettingsSheet));
    expect((over.open, over.toPage?.id), (true, 'plugin:notion'));
    expect(shellOf(tester).screen, const ScreenMarket(plugin: 'notion'));
    await close(tester);
  });

  testWidgets('simple mode has no way in', (tester) async {
    await open(tester, experience: 'simple');
    final shell = shellOf(tester);
    final drawer = partOf<NotesDrawer>(shell.context, shellWidget(tester).sidebarBuilder!(shell.context, shell, () {}));
    expect(drawer.onMarket, isNull);
    expect([for (final command in palette(tester)) command.descriptor.id], isNot(contains('market')));
    await close(tester);
  });
}
