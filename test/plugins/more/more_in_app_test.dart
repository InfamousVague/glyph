// The more tools in the app put together (docs/PM_PLUGINS.md §10; Matt, 2026-11-01: "think about other things that
// can be plugins that might be overwhelming for a new user as well"): with one off, its markdown is drawn as plain
// code or text with a chip that turns it on, nothing of the note is rewritten, and its rows and shelves are gone;
// with it on, the note draws what it always drew.

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/canvas_view.dart' show CanvasView;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart' show DrawnDiagram;
import 'package:ghost_md/editor/maths/maths.dart' show DrawnMaths;
import 'package:ghost_md/editor/media/map_card.dart' show MapCard;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/meeting_shelf.dart' show MeetingShelf;
import 'package:ghost_md/plugins/more/more_tools.dart';
import 'package:ghost_md/plugins/more/tool_off.dart' show MoreToolOff;
import 'package:ghost_md/plugins/projects/suite.dart' show projectPlugins;
import 'package:ghost_md/plugins/projects/tool_chip.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../../support/render.dart';

const String diagramNote = '# Trip\n\n```mermaid\nflowchart LR\n  A[Friday] --> B[Saturday]\n```\n';
const String formulaNote = '# Areas\n\n\$\$\na^2 + b^2 = c^2\n\$\$\n\nThe end.\n';
const String codeNote = '# Snippet\n\n```dart\nvoid main() => print(1);\n```\n';
const String placedNote = '---\nlocation: 52.3731,4.8922\nplace: "Dam Square, Amsterdam"\n---\n# Lunch on the square\n\nWords.\n';
const String canvasNote = '---\ntitle: Cards\n---\n{"nodes":[{"id":"a","type":"text","text":"Hello","x":0,"y":0,"width":240,"height":120}],"edges":[]}\n';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  /// The person's own switches, [on] of the more tools added; the project tools as every test has them, on.
  Registry switches(Set<String> on) => createRegistry([...projectPlugins, ...morePlugins], store: MemorySwitches({for (final id in on) id: true}));

  /// Every check of the one-time adoption made, as on a device that has run this build: the switches are the test's.
  void checked() => stored.write(moreToolsAdoptedKey, ['canvas', 'diagrams', 'email', 'meetings', 'meetings:notes', 'places', 'publishing']);

  setUp(() {
    MoreTools.debugAllOn = false;
    usePlugins(switches(const {}));
    checked();
  });
  tearDown(() {
    MoreTools.debugAllOn = true;
    usePlugins(createRegistry(const []));
  });

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<SampleLibrary> open(WidgetTester tester, {Map<String, String> extra = const {}, Stored? kept}) async {
    final library = SampleLibrary.seeded();
    for (final MapEntry(key: id, value: body) in extra.entries) {
      await library.createNote(body, id: id);
    }
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: kept),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

  Future<void> openNote(WidgetTester tester, String id) async {
    shellOf(tester).openNote(id);
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  List<String> chips(WidgetTester tester) => [for (final chip in tester.widgetList<ToolChip>(find.byType(ToolChip))) chip.words];
  String bodyOf(SampleLibrary library, String id) => library.value.firstWhere((note) => note.id == id).body;

  group('Diagrams and math off', () {
    testWidgets('a mermaid fence is plain code with a chip, untouched, and the chip draws it', (tester) async {
      final library = await open(tester, extra: {'trip': diagramNote});
      await openNote(tester, 'trip');
      expect(find.byType(DrawnDiagram), findsNothing);
      expect(chips(tester), ['Turn on Diagrams']);
      expect(bodyOf(library, 'trip'), diagramNote);
      tester.widget<ToolChip>(find.byType(ToolChip)).onPress!();
      await settle(tester);
      expect(plugins.isEnabled(diagramsTool), isTrue);
      expect(find.byType(DrawnDiagram), findsOneWidget);
      expect(find.byType(ToolChip), findsNothing);
      expect(bodyOf(library, 'trip'), diagramNote);
      await close(tester);
    });

    testWidgets('a formula is its words with a chip, and a language’s block is plain code with one', (tester) async {
      final library = await open(tester, extra: {'areas': formulaNote, 'snippet': codeNote});
      await openNote(tester, 'areas');
      expect(find.byType(DrawnMaths), findsNothing);
      expect(chips(tester), ['Turn on Diagrams']);
      expect(bodyOf(library, 'areas'), formulaNote);
      await openNote(tester, 'snippet');
      expect(chips(tester), ['Turn on Diagrams']);
      expect(bodyOf(library, 'snippet'), codeNote);
      await close(tester);
    });

    testWidgets('on, the formula is drawn and no chip is', (tester) async {
      usePlugins(switches({diagramsTool}));
      await open(tester, extra: {'areas': formulaNote});
      await openNote(tester, 'areas');
      expect(find.byType(DrawnMaths), findsWidgets);
      expect(find.byType(ToolChip), findsNothing);
      await close(tester);
    });
  });

  group('Canvas off', () {
    testWidgets('a canvas opens to its chip, its JSON untouched, and the chip draws its cards', (tester) async {
      final library = await open(tester, extra: {'cards': canvasNote});
      await openNote(tester, 'cards');
      expect(find.byType(CanvasView), findsNothing);
      expect(find.byType(MoreToolOff), findsOneWidget);
      expect(chips(tester), ['Turn on Canvas']);
      expect(bodyOf(library, 'cards'), canvasNote);
      tester.widget<ToolChip>(find.byType(ToolChip)).onPress!();
      await settle(tester);
      expect(plugins.isEnabled(canvasTool), isTrue);
      expect(find.byType(CanvasView), findsOneWidget);
      expect(find.byType(MoreToolOff), findsNothing);
      await close(tester);
    });
  });

  group('Places off', () {
    testWidgets('a tagged note has no map, its location: kept as written', (tester) async {
      final library = await open(tester, extra: {'lunch': placedNote});
      await openNote(tester, 'lunch');
      expect(find.byType(MapCard), findsNothing);
      expect(bodyOf(library, 'lunch'), placedNote);
      await close(tester);
    });
  });

  group('adopting, as the library is opened', () {
    testWidgets('turns on what the notes use, once: the sample note’s diagrams and the canvas, and not Places', (tester) async {
      final kept = MemoryStored();
      await open(tester, extra: {'trip': diagramNote}, kept: kept);
      await settle(tester);
      expect(plugins.isEnabled(diagramsTool), isTrue);
      expect(plugins.isEnabled(canvasTool), isTrue, reason: 'the seeded library holds a canvas');
      expect(plugins.isEnabled(placesTool), isFalse, reason: 'no note of it has a place');
      expect(plugins.isEnabled(emailTool), isFalse);
      expect(moreToolChecked(placesTool, store: kept), isTrue);
      await openNote(tester, 'trip');
      expect(find.byType(DrawnDiagram), findsOneWidget);
      await close(tester);
    });
  });

  group('Meetings off', () {
    testWidgets('the home page has no shelf of meetings', (tester) async {
      await open(tester);
      await settle(tester);
      expect(find.byType(MeetingShelf), findsNothing);
      await close(tester);
    });
  });
}
