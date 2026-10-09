import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/academy_screen.dart';
import 'package:ghost_md/account/api.dart' show FetchRequest;
import 'package:ghost_md/core/link_preview.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/note_desk.dart';
import 'package:ghost_md/root/plugin_ground.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';

import '../support/render.dart';

/// Stage 9's pieces in the app put together (lib/root): the Academy through the shell, the titles of linked pages,
/// Developer's benches, and the plugins put on the phone.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late List<String> asked;

  Future<SampleLibrary> open(WidgetTester tester, {bool previews = false}) async {
    final library = SampleLibrary.seeded();
    asked = [];
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: MemoryStored(),
        previewFetch: previews
            ? (url) async {
                asked.add(url);
                return LinkPreview(url: url, title: 'An example', site: 'Example');
              }
            : null,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  group('the Academy', () {
    testWidgets('takes the whole window from Settings, and its arrow goes home', (tester) async {
      await open(tester);
      tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onAcademy!();
      await settle(tester);
      expect(shellOf(tester).screen, isA<ScreenAcademy>());
      expect(find.byType(AcademyScreen), findsOneWidget);
      expect(tester.widget<SettingsSheet>(find.byType(SettingsSheet)).open, isFalse);
      tester.widget<AcademyScreen>(find.byType(AcademyScreen)).onDone();
      await settle(tester);
      expect(shellOf(tester).screen, isA<ScreenList>());
      await close(tester);
    });

    testWidgets('sends its contents\' cheat sheet to Settings at that page', (tester) async {
      await open(tester);
      shellOf(tester).show(const Screen.academy());
      await settle(tester);
      tester.widget<AcademyScreen>(find.byType(AcademyScreen)).onCheatSheet();
      await settle(tester);
      final sheet = tester.widget<SettingsSheet>(find.byType(SettingsSheet));
      expect(sheet.open, isTrue);
      expect(sheet.toPage?.id, 'cheatsheet');
      expect(shellOf(tester).screen, isA<ScreenList>());
      tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onClose();
      await settle(tester, 3);
      await close(tester);
    });
  });

  group('a linked page\'s title', () {
    testWidgets('is asked for a note\'s links only with Link previews on and nothing kept to the phone', (tester) async {
      await open(tester, previews: true);
      shellOf(tester).openNote(SampleLibrary.seeded().value.first.id);
      await settle(tester);
      final previewer = tester.widget<NoteDesk>(find.byType(NoteDesk)).world.previewer!;
      expect(previewer, isA<KeptLinkPreviews>());
      preferences.value = preferences.value.copyWith(localOnly: true);
      previewer.wantPreview('https://example.com/a');
      await settle(tester, 2);
      expect(asked, isEmpty, reason: 'nothing leaves the phone');
      preferences.value = preferences.value.copyWith(localOnly: false, linkPreviews: false);
      previewer.wantPreview('https://example.com/a');
      await settle(tester, 2);
      expect(asked, isEmpty, reason: 'Link previews is off');
      preferences.value = preferences.value.copyWith(linkPreviews: true);
      previewer.wantPreview('https://example.com/a');
      await settle(tester, 2);
      expect(asked, ['https://example.com/a']);
      expect(previewer.previewFor('https://example.com/a')?.title, 'An example');
      await close(tester);
    });

    testWidgets('is asked of nowhere in a build given no reader', (tester) async {
      await open(tester);
      shellOf(tester).openNote(SampleLibrary.seeded().value.first.id);
      await settle(tester);
      final previewer = tester.widget<NoteDesk>(find.byType(NoteDesk)).world.previewer!;
      previewer.wantPreview('https://example.com/a');
      await settle(tester, 2);
      expect(previewer.previewFor('https://example.com/a'), isNull);
      await close(tester);
    });
  });

  group('Developer\'s benches', () {
    testWidgets('can be pressed', (tester) async {
      await open(tester);
      final features = tester.widget<SettingsSheet>(find.byType(SettingsSheet)).features;
      expect(features.onSmokeBench, isNotNull);
      expect(features.onPlayScene, isNotNull);
      expect(features.onReset, isNull, reason: 'starting over is not wired');
      await close(tester);
    });
  });

  group('the plugins on the phone', () {
    tearDown(() {
      usePlugins(createRegistry(const []));
      usePluginGround(PluginGround());
    });

    test('are the five that ship, over the ground they are given', () {
      final ground = PluginGround();
      final registry = installPlugins(ground: ground, prefs: PreferencesStore());
      expect(identical(pluginGround, ground), isTrue);
      expect(identical(plugins, registry), isTrue);
      expect(registry.all().map((plugin) => plugin.manifest.id), ['notion', 'github', 'marks', 'claude', 'slack']);
    });

    test('never ask the real service from a build that is not a release', () async {
      final fetch = pluginFetcher(debug: true);
      for (final url in ['https://ghostmarkdown.com/api/x', 'https://attack.fm/glyph/api/x', 'https://www.ghostmarkdown.com/']) {
        await expectLater(fetch(FetchRequest(method: 'GET', url: Uri.parse(url))), throwsStateError, reason: url);
      }
    });
  });
}
