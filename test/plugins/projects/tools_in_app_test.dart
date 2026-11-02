// The project tools in the app put together (docs/PM_PLUGINS.md; Matt, 2026-11-01): with one off, its markdown is
// drawn as written with a chip that turns it on, nothing of the note is rewritten, and its rows are gone; with it on,
// the note draws what it always drew; an organization's note asks its home page's `plugins:`, a personal note the
// person's own switches; and the banner over an organization's note writes the list.

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/page_tree.dart' show TeamspaceSettings, teamspaceHomeBody;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart' show ContextBand;
import 'package:ghost_md/editor/boards/boards.dart' show DrawnBoardBox;
import 'package:ghost_md/editor/gantt/gantt.dart' show DrawnGantt;
import 'package:ghost_md/editor/queries/queries.dart' show QueryView, queriesWatchMidnight;
import 'package:ghost_md/editor/tickets/tickets.dart' show TicketPanel;
import 'package:ghost_md/plugins/projects/suite.dart';
import 'package:ghost_md/plugins/projects/tool_chip.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../../support/render.dart';

const String ganttNote = '# Roadmap\n\n```gantt\ntitle: Project\n\n## Plan\n- Plan it [2026-09-28 → 2026-09-30]\n- Build it [+3d] after: Plan it\n```\n';
const String rulesNote = '# Kiln rules\n\n```rules\nWhen a ticket moves to Done, set priority to low\n```\n';
const String formNote = '# Bug form\n\n```form\nto: [[Product]]\n- Summary: short, required\n```\n';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  /// The person's own switches, [on] of the suite added.
  Registry switches(Set<String> on) => createRegistry(projectPlugins, store: MemorySwitches({for (final id in on) id: true}));

  setUp(() {
    ProjectSuite.debugAllOn = false;
    usePlugins(switches(const {}));
  });
  tearDown(() {
    ProjectSuite.debugAllOn = true;
    usePlugins(createRegistry(const []));
  });

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The sample library, with [extra] notes added and, where [acme] says, an organization Acme whose home page lists
  /// those tools and which holds the notes [filed].
  Future<SampleLibrary> open(WidgetTester tester, {Map<String, String> extra = const {}, List<String>? acme, List<String> filed = const []}) async {
    final library = SampleLibrary.seeded();
    for (final MapEntry(key: id, value: body) in extra.entries) {
      await library.createNote(body, id: id);
    }
    final seed = seedWorkspaces();
    var sheet = seed;
    if (acme != null) {
      final home = await library.createNote(teamspaceHomeBody('Acme', plugins: acme), id: 'acme-home');
      await library.apply(home.copyWith(path: () => 'orgs/Acme/Home.md'));
      sheet = WorkspaceSheet(
        list: [...seed.list, Workspace(id: orgWorkspaceId('acme'), name: 'Acme')],
        notes: {...seed.notes, 'acme-home': orgWorkspaceId('acme'), for (final id in filed) id: orgWorkspaceId('acme')},
      );
    }
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(sheet)), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  Note titled(SampleLibrary library, String title) => library.value.firstWhere((note) => noteTitle(note.body) == title);

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

  /// The words of the one chip on the open note.
  String chipWords(WidgetTester tester) => tester.widget<ToolChip>(find.byType(ToolChip)).words;

  group('with every tool off, for the person', () {
    testWidgets('a board is its fence, with a chip that turns Boards on, and the band offers no board', (tester) async {
      final library = await open(tester);
      final launch = titled(library, 'Launch week');
      await openNote(tester, launch.id);
      expect(find.byType(DrawnBoardBox), findsNothing);
      expect(chipWords(tester), 'Turn on Boards');
      expect(tester.widget<ContextBand>(find.byType(ContextBand)).boards, isFalse);
      // Nothing of the note was rewritten.
      expect(library.value.firstWhere((note) => note.id == launch.id).body, launch.body);
      // The chip turns Boards on for the person, and the open note draws its board at once.
      // Pressed as a tap on it presses it (the chip sits under the bar where a test's view is scrolled to it).
      tester.widget<ToolChip>(find.byType(ToolChip)).onPress!();
      await settle(tester);
      expect(plugins.isEnabled('boards'), isTrue);
      expect(find.byType(DrawnBoardBox), findsOneWidget);
      expect(find.byType(ToolChip), findsNothing);
      await close(tester);
    });

    testWidgets('a ticket is plain front matter, with a chip that turns Tickets on', (tester) async {
      final library = await open(tester);
      final ticket = library.value.firstWhere((note) => note.body.contains('type: ticket'));
      await openNote(tester, ticket.id);
      expect(find.byType(TicketPanel), findsNothing);
      expect(chipWords(tester), 'Turn on Tickets and Planning', reason: 'its estimate: is Planning’s');
      expect(library.value.firstWhere((note) => note.id == ticket.id).body, ticket.body);
      await close(tester);
    });

    testWidgets('a query of tickets on a board is its lines, with the chip for both in its place', (tester) async {
      final library = await open(tester);
      await openNote(tester, titled(library, 'This sprint').id);
      expect(find.byType(QueryView), findsNothing);
      expect(chipWords(tester), 'Turn on Tickets and Boards');
      await close(tester);
    });

    testWidgets('a gantt, a rules and a form fence are code blocks with their chips; Forms brings Tickets', (tester) async {
      final library = await open(tester, extra: {'gantt': ganttNote, 'rules': rulesNote, 'form': formNote});
      await openNote(tester, 'gantt');
      expect(find.byType(DrawnGantt), findsNothing);
      expect(chipWords(tester), 'Turn on Gantt');
      await openNote(tester, 'rules');
      expect(chipWords(tester), 'Turn on Tickets and Automations');
      await openNote(tester, 'form');
      expect(chipWords(tester), 'Turn on Tickets and Forms');
      for (final (id, body) in [('gantt', ganttNote), ('rules', rulesNote), ('form', formNote)]) {
        expect(library.value.firstWhere((note) => note.id == id).body, body, reason: 'nothing is rewritten');
      }
      await close(tester);
    });
  });

  group('with every tool on, for the person', () {
    testWidgets('the board, the panel, the query and the chart are drawn as before, and no chip', (tester) async {
      usePlugins(switches(projectTools.toSet()));
      final library = await open(tester, extra: {'gantt': ganttNote});
      await openNote(tester, titled(library, 'Launch week').id);
      expect(find.byType(DrawnBoardBox), findsOneWidget);
      expect(tester.widget<ContextBand>(find.byType(ContextBand)).boards, isTrue);
      await openNote(tester, library.value.firstWhere((note) => note.body.contains('type: ticket')).id);
      expect(find.byType(TicketPanel), findsOneWidget);
      await openNote(tester, titled(library, 'This sprint').id);
      expect(find.byType(QueryView), findsOneWidget);
      await openNote(tester, 'gantt');
      expect(find.byType(DrawnGantt), findsOneWidget);
      expect(find.byType(ToolChip), findsNothing);
      await close(tester);
    });
  });

  group('an organization’s note', () {
    testWidgets('asks its home page’s plugins:, not the person’s switches', (tester) async {
      // Acme turned Boards on; the person has nothing on.
      final library = await open(tester, acme: ['boards'], filed: ['launch', 'prd11']);
      await openNote(tester, 'launch');
      expect(find.byType(DrawnBoardBox), findsOneWidget, reason: 'Acme has Boards');
      await openNote(tester, 'prd11');
      expect(find.byType(TicketPanel), findsNothing, reason: 'Acme has no Tickets');
      expect(chipWords(tester), 'Turn on Tickets and Planning for Acme');
      // A personal ticket asks the person's own switches, which are off too.
      final mine = library.value.firstWhere((note) => note.body.contains('type: ticket') && note.id != 'prd11');
      await openNote(tester, mine.id);
      expect(chipWords(tester), 'Turn on Tickets and Planning', reason: 'its estimate: is Planning’s');
      await close(tester);
    });

    testWidgets('the banner names what its notes use and the team lacks, and its button writes the list', (tester) async {
      // The person has Boards on; Acme has none.
      usePlugins(switches(const {'boards'}));
      final library = await open(tester, acme: const [], filed: ['launch']);
      await openNote(tester, 'launch');
      expect(find.byType(DrawnBoardBox), findsNothing, reason: 'the person’s Boards is not Acme’s');
      final banner = tester.widget<ToolBanner>(find.byType(ToolBanner));
      expect(banner.tools, ['boards']);
      expect(banner.orgName, 'Acme');
      expect(find.text('Turn on for Acme'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-banner-turn-on')));
      await settle(tester, 10);
      final home = library.value.firstWhere((note) => note.id == 'acme-home');
      expect(home.body, contains('plugins: [boards]\n'));
      expect(TeamspaceSettings.of(home.body).plugins, {'boards'});
      expect(find.byType(DrawnBoardBox), findsOneWidget);
      expect(find.byType(ToolBanner), findsNothing);
      await close(tester);
    });

    testWidgets('the banner put away stays away on this device for that list', (tester) async {
      final library = await open(tester, acme: const [], filed: ['launch']);
      await openNote(tester, 'launch');
      expect(find.byType(ToolBanner), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-banner-put-away')));
      await settle(tester);
      expect(find.byType(ToolBanner), findsNothing);
      expect(projectSuite.bannerPutAway('acme', const ['boards']), isTrue);
      expect(library.value.firstWhere((note) => note.id == 'acme-home').body, isNot(contains('plugins:')), reason: 'putting it away writes nothing');
      await close(tester);
    });
  });
}
