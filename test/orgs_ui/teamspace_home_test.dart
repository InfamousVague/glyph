// The teamspace home on an organization's dashboard (lib/orgs/ui/teamspace_home.dart; docs/TEAMSPACES.md, "Teamspace
// home"; Matt, 2026-10-31: "Build first: all four: the sidebar and page tree, the doc page UI, the teamspace home and
// members, presence"): the organization's own Home.md drawn as its page with its icon on the hero, the members strip
// with who is here, the pinned pages as cards, Create the home page where there is none, Pages open in: Read or Edit
// (behind More in simple mode), and a member's page from the strip with their open tickets, owned pages and edits.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;
import 'package:ghost_md/book/book_view.dart' show BookWords;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/page_tree.dart' show DocsMode;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/home/home_organizations.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/orgs/ui/member_page.dart';
import 'package:ghost_md/orgs/ui/organization_screen.dart';
import 'package:ghost_md/orgs/ui/teamspace_home.dart';
import 'package:ghost_md/plugins/projects/suite.dart';
import 'package:ghost_md/plugins/projects/tool_chip.dart' show ToolBanner;
import 'package:ghost_md/plugins/projects/tool_switches.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;

import 'support.dart';

/// What the page was asked to do.
class Asked {
  final List<String> opened = [], members = [];
  final List<DocsMode> docs = [];
  int created = 0;
  int ask = 0;
}

Note at(String id, String path, String body) => Note(id: id, body: body, createdAt: 0, updatedAt: 0, path: path);

const String homeBody = '---\ntitle: Home\ntype: teamspace\ndocs: read\nicon: 🚀\npins: ["[[Roadmap]]", "[[Nowhere]]"]\n---\n# Ghost\n\nRead the roadmap first.\n';

Future<Asked> page(WidgetTester tester, Device device, String id, {List<Note> notes = const [], List<OrgPresence> seen = const [], bool create = true}) async {
  final asked = Asked();
  for (final note in notes) {
    device.workspaces.fileNote(note.id, orgWorkspaceId(id));
  }
  await device.pump(
    tester,
    OrganizationScreen(
      services: device.services,
      orgId: id,
      notes: notes,
      seen: seen,
      wisp: false,
      onBack: () {},
      onOpenNote: asked.opened.add,
      onNew: () {},
      onAllNotes: (_) {},
      onSettings: () {},
      onOpenOrganization: (_) {},
      onLog: () {},
      onAccount: () {},
      onMember: asked.members.add,
      onCreateHome: create ? () async => asked.created += 1 : null,
      onSetDocs: (mode) async => asked.docs.add(mode),
      onAsk: () => asked.ask += 1,
    ),
    scroll: false,
  );
  await settle(tester, 14);
  return asked;
}

Future<void> press(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  expect(target, findsOneWidget, reason: '$key');
  await bringIntoView(tester, target);
  await tester.tap(target);
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('draws Home.md as the space’s page, its icon on the hero, the members with who is here, and its pins', (tester) async {
    final device = await Device.make();
    final id = await ghost(device);
    await sam(device, id, joined: true);
    final notes = [at('home', 'orgs/Ghost/Home.md', homeBody), at('road', 'orgs/Ghost/Roadmap.md', '---\nicon: 🗺️\n---\n# Roadmap\n')];
    final asked = await page(tester, device, id, notes: notes, seen: const [OrgPresence(client: '1', handle: 'sam')]);
    expect(find.byKey(const ValueKey('org-hero-icon')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('org-hero-icon'))).data, '🚀');
    final words = tester.widget<BookWords>(find.byKey(TeamspaceHome.pageKey)).words;
    expect(words, 'Read the roadmap first.\n', reason: 'no front matter, and no first heading: the hero says the name');
    // The members strip: matt and sam, sam here now.
    expect(find.byKey(TeamspaceHome.memberKey('matt')), findsOneWidget);
    expect(find.byKey(TeamspaceHome.memberKey('sam')), findsOneWidget);
    expect(find.byKey(TeamspaceHome.onlineKey('sam')), findsOneWidget);
    await press(tester, TeamspaceHome.memberKey('sam'));
    expect(asked.members, ['sam']);
    // The pins: the one that answers to a note, as a card that opens it.
    expect(find.byKey(TeamspaceHome.pinsKey), findsOneWidget);
    await press(tester, TeamspaceHome.pinKey('road'));
    expect(asked.opened, ['road']);
    await press(tester, TeamspaceHome.editKey);
    expect(asked.opened, ['road', 'home']);
    // Ask the space's notes, with receipts (docs/ASK_THE_ORG.md; Matt, 2026-11-02): over the members.
    expect(tester.getTopLeft(find.byKey(TeamspaceHome.askKey)).dy, lessThan(tester.getTopLeft(find.byKey(TeamspaceHome.stripKey)).dy));
    await press(tester, TeamspaceHome.askKey);
    expect(asked.ask, 1);
    // What was there stays under it.
    expect(find.byKey(const ValueKey('org-heading-members')), findsOneWidget);
    expect(find.byKey(const ValueKey('org-heading-activity')), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('with no home page, offers to make one; and Pages open in writes docs:', (tester) async {
    final device = await Device.make();
    final id = await ghost(device);
    final asked = await page(tester, device, id, notes: [at('road', 'orgs/Ghost/Roadmap.md', '# Roadmap\n')]);
    expect(find.byKey(TeamspaceHome.pageKey), findsNothing);
    await press(tester, TeamspaceHome.createKey);
    expect(asked.created, 1);
    // Edit is the default with no home page; Read is the other word.
    await press(tester, TeamspaceHome.docsChoiceKey(DocsMode.read));
    expect(asked.docs, [DocsMode.read]);
    await endSettings(tester);
  });

  testWidgets('says how the space’s pages open as its home page says, and the other word writes it', (tester) async {
    final device = await Device.make();
    final id = await ghost(device);
    final asked = await page(tester, device, id, notes: [at('home', 'orgs/Ghost/Home.md', homeBody)]);
    expect(find.byKey(TeamspaceHome.createKey), findsNothing);
    await press(tester, TeamspaceHome.docsChoiceKey(DocsMode.read));
    expect(asked.docs, isEmpty, reason: 'read is chosen already');
    await press(tester, TeamspaceHome.docsChoiceKey(DocsMode.edit));
    expect(asked.docs, [DocsMode.edit]);
    await endSettings(tester);
  });

  testWidgets('in simple mode the setting waits behind More, which opens in place', (tester) async {
    final device = await Device.make();
    preferences.value = preferences.value.copyWith(experience: 'simple');
    final id = await ghost(device);
    await page(tester, device, id, notes: [at('home', 'orgs/Ghost/Home.md', homeBody)]);
    expect(find.byKey(TeamspaceHome.docsKey), findsNothing);
    await press(tester, TeamspaceHome.moreKey);
    expect(find.byKey(TeamspaceHome.docsKey), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('a member’s page lists their open tickets, the pages they own, and opens each', (tester) async {
    final device = await Device.make();
    final id = await ghost(device);
    await sam(device, id, joined: true);
    final notes = [
      at('t1', 'orgs/Ghost/Fix login.md', '---\ntype: ticket\nid: GHO-1\nstatus: In progress\nassignee: sam\n---\n# Fix login\n'),
      at('t2', 'orgs/Ghost/Done one.md', '---\ntype: ticket\nid: GHO-2\nstatus: Done\nassignee: sam\n---\n# Done one\n'),
      at('d1', 'orgs/Ghost/Roadmap.md', '---\nowner: "@sam"\n---\n# Roadmap\n'),
    ];
    for (final note in notes) {
      device.workspaces.fileNote(note.id, orgWorkspaceId(id));
    }
    final opened = <String>[];
    await device.pump(tester, MemberPage(services: device.services, orgId: id, handle: 'sam', notes: notes, onBack: () {}, onOpenNote: opened.add, wisp: false), scroll: false);
    await settle(tester, 14);
    expect(find.byKey(MemberPage.rowKey('ticket', 't1')), findsOneWidget);
    expect(find.byKey(MemberPage.rowKey('ticket', 't2')), findsNothing, reason: 'done');
    expect(find.byKey(MemberPage.rowKey('owned', 'd1')), findsOneWidget);
    expect(find.text('Not in the app now'), findsOneWidget);
    // Their role, read from the organization.
    expect(find.text('Member'), findsOneWidget);
    await press(tester, MemberPage.rowKey('ticket', 't1'));
    await press(tester, MemberPage.rowKey('owned', 'd1'));
    expect(opened, ['t1', 'd1']);
    await endSettings(tester);
  });

  group('the team’s tools (docs/PM_PLUGINS.md)', () {
    /// A suite whose organization [id] lists [listed] and whose notes use [used]; what it writes is kept in [written].
    ProjectSuite suiteFor(String id, Set<String> listed, Set<String> used, List<Set<String>> written) {
      var now = listed;
      return ProjectSuite(
        orgOfNote: (_) => id,
        listOf: (org) => org == id ? now : null,
        orgIds: () => [id],
        orgName: (_) => 'Ghost',
        usedIn: (org) => org == id ? used : const {},
        writeOrg: (org, tools) async {
          written.add(tools);
          now = tools;
          return true;
        },
        stored: MemoryStored(),
      );
    }

    setUp(() => ProjectSuite.debugAllOn = false);
    tearDown(() {
      ProjectSuite.debugAllOn = true;
      useProjectSuite(ProjectSuite());
    });

    testWidgets('a banner over the home names what the notes use and the team has not turned on, and turns it on', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final written = <Set<String>>[];
      useProjectSuite(suiteFor(id, const {'gantt'}, const {'gantt', 'forms'}, written));
      await page(tester, device, id, notes: [at('home', 'orgs/Ghost/Home.md', homeBody)]);
      final banner = tester.widget<ToolBanner>(find.byKey(TeamspaceHome.toolBannerKey));
      expect(banner.tools, ['tickets', 'forms'], reason: 'Forms brings Tickets');
      expect(banner.orgName, 'Ghost');
      await press(tester, const ValueKey('tool-banner-turn-on'));
      expect(written, [
        {'tickets', 'gantt', 'forms'},
      ]);
      expect(find.byKey(TeamspaceHome.toolBannerKey), findsNothing);
      await endSettings(tester);
    });

    testWidgets('Tools lists the suite with a switch each; Tickets off first says what goes with it', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final written = <Set<String>>[];
      useProjectSuite(suiteFor(id, const {'tickets', 'planning'}, const {}, written));
      await page(tester, device, id, notes: [at('home', 'orgs/Ghost/Home.md', homeBody)]);
      expect(find.byKey(TeamspaceHome.toolsKey), findsOneWidget);
      for (final tool in projectTools) {
        expect(find.byKey(ToolSwitches.rowKey(tool)), findsOneWidget, reason: tool);
      }
      // Boards on: written with what was there.
      await bringIntoView(tester, find.byKey(ToolSwitches.rowKey('boards')));
      await tester.tap(find.descendant(of: find.byKey(ToolSwitches.rowKey('boards')), matching: find.byType(GlacierSwitch)));
      await settle(tester);
      expect(written.last, {'tickets', 'planning', 'boards'});
      // Tickets off: the warning names Planning, and Turn off takes both.
      await tester.tap(find.descendant(of: find.byKey(ToolSwitches.rowKey('tickets')), matching: find.byType(GlacierSwitch)));
      await settle(tester);
      expect(find.byKey(ToolSwitches.warningKey), findsOneWidget);
      expect(find.textContaining('Planning needs Tickets'), findsOneWidget);
      expect(written, hasLength(1), reason: 'nothing is written until Turn off');
      await press(tester, const ValueKey('tool-switch-turn-off'));
      expect(written.last, {'boards'});
      await endSettings(tester);
    });
  });
}
