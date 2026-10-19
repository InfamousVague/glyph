// An organization's dashboard against the service in memory. A port of `src/app/notes/OrganizationScreen.test.tsx`,
// case for case. Who is in the app now is handed in (the live service is not ported), so that case hands it a list
// where the web's test moved the room.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/home/home_organizations.dart';
import 'package:ghost_md/home/note_card.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/orgs/ui/organization_screen.dart';
import 'package:ghost_md/orgs/ui/parts.dart';
import 'package:ghost_md/settings/invite_actions.dart';
import 'package:ghost_md/settings/invite_links.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// What the page was asked to do.
class Asked {
  int back = 0, fresh = 0, allNotes = 0, settings = 0, log = 0, account = 0;
  final List<String> opened = [], organizations = [], jumps = [], followed = [];
}

Future<Asked> page(WidgetTester tester, Device device, String id, {List<Note> notes = const [], ValueNotifier<List<OrgPresence>>? seen, Size size = phone, bool services = true}) async {
  final asked = Asked();
  final here = seen ?? ValueNotifier<List<OrgPresence>>(const []);
  await device.pump(
    tester,
    ValueListenableBuilder<List<OrgPresence>>(
      valueListenable: here,
      builder: (context, seen, _) => OrganizationScreen(
        services: services ? device.services : null,
        orgId: id,
        notes: notes,
        seen: seen,
        wisp: false,
        onBack: () => asked.back += 1,
        onOpenNote: asked.opened.add,
        onNew: () => asked.fresh += 1,
        onAllNotes: (_) => asked.allNotes += 1,
        onSettings: () => asked.settings += 1,
        onOpenOrganization: asked.organizations.add,
        onLog: () => asked.log += 1,
        onAccount: () => asked.account += 1,
        onJumpTo: asked.jumps.add,
        onFollow: (here) => asked.followed.add(here.handle),
      ),
    ),
    size: size,
    scroll: false,
  );
  await settle(tester, 14);
  return asked;
}

/// Each member's row as its words run together, in the page's order.
List<String> members(WidgetTester tester) => [
      for (final row in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('member:')).evaluate())
        find.descendant(of: find.byWidget(row.widget), matching: find.byType(RichText)).evaluate().map((e) => (e.widget as RichText).text.toPlainText().replaceAll('￼', '')).join(),
    ];

/// Each AI's row as its words run together, in the page's order.
List<String> ais(WidgetTester tester) => [
      for (final row in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('ai:')).evaluate())
        find.descendant(of: find.byWidget(row.widget), matching: find.byType(RichText)).evaluate().map((e) => (e.widget as RichText).text.toPlainText().replaceAll('￼', '')).join(),
    ];

List<String> cards(WidgetTester tester) => [for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) card.note.body];

List<String> news(WidgetTester tester) => [
      for (final row in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('news:')).evaluate())
        find.descendant(of: find.byWidget(row.widget), matching: find.byType(RichText)).evaluate().map((e) => (e.widget as RichText).text.toPlainText()).join(' '),
    ];

/// The hue each member's initial wears, in the page's order; null for the page's own ink.
List<String?> avatars(WidgetTester tester) => [
      for (final avatar in find.byKey(const ValueKey('member-avatar')).evaluate())
        // An initial with no colour of its own stands on the ink's wash, whatever hue the page around it wears.
        ((avatar.widget as Container).decoration! as BoxDecoration).color == GlacierTheme.of(avatar).colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)') ? null : GlacierTheme.of(avatar).attrs['hue'],
    ];

Note note(String id, String body, {int updatedAt = 0, int? archivedAt}) => Note(id: id, body: body, createdAt: 0, updatedAt: updatedAt, archivedAt: archivedAt);

void main() {
  setUpAll(loadAppFonts);

  group('an organization’s dashboard', () {
    testWidgets('is the organization: its name in the bar, the hero, the members read from the service, and the feed taken on opening', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await sam(device, id, joined: true);
      await page(tester, device, id);
      expect(tester.widget<Text>(find.byKey(const ValueKey('organization-title'))).data, 'Ghost');
      expect(GlacierTheme.of(tester.element(find.byKey(const ValueKey('organization-title')))).attrs['hue'], 'sea');
      expect(find.text('Notes filed here are the team’s: everyone in it reads and edits them, and edits made apart merge.'), findsOneWidget);
      expect(members(tester), hasLength(2));
      expect(members(tester)[0], contains('matt'));
      expect(members(tester)[0], contains('Owner'));
      expect(members(tester)[0], contains('You, owner since'));
      expect(members(tester)[1], contains('samMember'));
      // The hero counts who has joined, once the service has said.
      expect(tester.widget<Text>(find.byKey(const ValueKey('org-hero-meta'))).data, '2 members · You are owner');
      // One whole pass as the page opened.
      expect(device.services.status.lastAt, isNotNull);
      expect(device.service.calls.where((call) => call.startsWith('GET notifications')), hasLength(1));
      await endSettings(tester);
    });

    // Matt: "when an AI has accessed an ORG add it as a member labeled as (AI)".
    testWidgets('lists an AI seen through a member’s connector under the members, labelled AI, and counts only the people', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await sam(device, id, joined: true);
      device.service.peerAi(id, 'Claude', via: 'matt');
      device.service.peerAi(id, 'Cursor', via: 'sam', lastSeen: DateTime.now().millisecondsSinceEpoch - 24 * 60 * 60000);
      await page(tester, device, id);
      expect(members(tester), hasLength(2));
      expect(ais(tester), ['CClaudeAIThrough you · last seen just now', 'CCursorAIThrough sam · last seen yesterday']);
      // After the people, in the one list.
      final list = find.bySemanticsLabel('Members');
      final rows = [
        for (final row in find.descendant(of: list, matching: find.byWidgetPredicate((w) => w.key is ValueKey<String> && RegExp('^(member|ai):').hasMatch((w.key! as ValueKey<String>).value))).evaluate())
          (row.widget.key! as ValueKey<String>).value.split(':').first,
      ];
      expect(rows, ['member', 'member', 'ai', 'ai']);
      // A line that opens nothing: there is no one to find in the app.
      final first = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('ai:')).first;
      expect(find.descendant(of: first, matching: find.byType(GlacierPressable)), findsNothing);
      expect(tester.widget<Text>(find.descendant(of: first, matching: find.descendant(of: find.byType(RoleChip), matching: find.byType(Text)))).data, 'AI');
      // Its initial in an outline, not a fill.
      expect((tester.widget<Container>(find.descendant(of: first, matching: find.byKey(const ValueKey('ai-avatar')))).decoration), isNull);
      // One thing to a reader: the name, that it is an AI, and its line.
      expect(tester.getSemantics(find.descendant(of: first, matching: find.byType(MergeSemantics))).label.replaceAll('\n', ' '), 'Claude AI Through you · last seen just now');
      expect(tester.widget<Text>(find.byKey(const ValueKey('org-hero-meta'))).data, '2 members · You are owner');
      expect(find.descendant(of: find.byKey(const ValueKey('org-heading-members')), matching: find.text('2')), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('lists no AI from a service before them', (tester) async {
      final device = await Device.make(service: await FakeService.start(seed: seeded, ais: false));
      final id = await ghost(device);
      await page(tester, device, id);
      expect(members(tester), hasLength(1));
      expect(ais(tester), isEmpty);
      await endSettings(tester);
    });

    testWidgets('puts its settings behind a cog in the bar, and the + and the way home on the page', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final asked = await page(tester, device, id);
      await tester.tap(find.bySemanticsLabel('Organization settings'));
      expect(asked.settings, 1);
      await tester.tap(find.bySemanticsLabel('New in this organization'));
      expect(asked.fresh, 1);
      await tester.tap(find.bySemanticsLabel('Back to home'));
      expect(asked.back, 1);
      await endSettings(tester);
    });

    testWidgets('shows the notes filed in its workspace, newest first, and not the others or the archived', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final notes = [note('a', '# Roadmap', updatedAt: 10), note('b', '# Standup', updatedAt: 20), note('c', '# Groceries', updatedAt: 30), note('d', '# Old plan', updatedAt: 40, archivedAt: 41)];
      for (final each in ['a', 'b', 'd']) {
        device.workspaces.fileNote(each, orgWorkspaceId(id));
      }
      final asked = await page(tester, device, id, notes: notes);
      expect(cards(tester), ['# Standup', '# Roadmap']);
      await tapKey(tester, 'org-all-notes');
      expect(asked.allNotes, 1);
      await tester.tap(find.byType(NoteCard).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(asked.opened, ['b']);
      await endSettings(tester);
    });

    testWidgets('says so when nothing is filed in its workspace yet', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await page(tester, device, id, notes: [note('c', '# Groceries')]);
      expect(cards(tester), isEmpty);
      expect(find.textContaining('Nothing is filed here yet.'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('invites by handle for an owner, with the service’s words when it refuses, and the new invitee in the list', (tester) async {
      final device = await Device.make(peers: const ['sam', 'lee']);
      final id = await ghost(device);
      await page(tester, device, id);
      expect(members(tester), hasLength(1));
      await typeInto(tester, 'Invite by handle', 'nobody');
      await tapKey(tester, 'org-invite-submit');
      await settle(tester, 10);
      expect(find.text('No one has that handle.'), findsOneWidget);
      await typeInto(tester, 'Invite by handle', 'lee');
      await tapKey(tester, 'org-invite-submit');
      await settle(tester, 10);
      expect(find.text('lee is invited. They see it in their notifications.'), findsOneWidget);
      expect(members(tester), hasLength(2));
      expect(members(tester)[1], contains('Invited'));
      await endSettings(tester);
    });

    testWidgets('offers no invitation to a member who is neither owner nor admin', (tester) async {
      final device = await Device.make();
      final id = await boo(device);
      await page(tester, device, id);
      expect(find.byKey(const ValueKey('org-invite')), findsNothing);
      expect(find.byWidgetPredicate((w) => w is GlacierInput && w.ariaLabel == 'Invite by handle'), findsNothing);
      expect(find.byType(InviteLinks), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('org-hero-meta'))).data, contains('You are member'));
      await endSettings(tester);
    });

    testWidgets('opens the audit log from the clock in the bar and from the Activity heading', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final asked = await page(tester, device, id);
      await tester.tap(find.byKey(const ValueKey('organization-log')));
      await tapKey(tester, 'org-audit-log');
      expect(asked.log, 2);
      await endSettings(tester);
    });

    testWidgets('wears each member’s colour on their initial, and picks yours here, in this organization alone', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await sam(device, id, joined: true);
      device.service.peerColour('sam', 'rose');
      await page(tester, device, id);
      expect(members(tester), hasLength(2));
      expect(avatars(tester), [null, 'rose']);
      expect(find.text('Your account’s, from Settings.'), findsOneWidget);
      // Sea, here alone: the service keeps it on matt's row, the initial wears it, and the way back is offered.
      await bringIntoView(tester, find.bySemanticsLabel('Sea'));
      await tester.tap(find.bySemanticsLabel('Sea'));
      await settle(tester, 12);
      expect(device.service.orgs[id]!.rows['matt']!.hue, 'sea');
      expect(avatars(tester), ['sea', 'rose']);
      expect(find.text('In this organization alone.'), findsOneWidget);
      await press(tester, 'Use your account’s colour');
      await settle(tester, 12);
      expect(device.service.orgs[id]!.rows['matt']!.hue, isNull);
      expect(avatars(tester), [null, 'rose']);
      await endSettings(tester);
    });

    testWidgets('says who is in the app and what they are editing, and opens the note from their profile', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await sam(device, id, joined: true);
      final seen = ValueNotifier<List<OrgPresence>>(const []);
      final asked = await page(tester, device, id, seen: seen);
      expect(members(tester), hasLength(2));
      expect(members(tester)[1], contains('joined'));
      seen.value = const [OrgPresence(client: '1', handle: 'sam', hue: 'rose', editingNote: 'n-road', editingTitle: 'Roadmap')];
      await tester.pump();
      expect(members(tester)[1], contains('editing Roadmap'));
      expect(members(tester)[1], isNot(contains('joined')));
      // A dot on each: sam's from the room, and yours, since this device is reading the page.
      expect(find.byKey(const ValueKey('member-here')), findsNWidgets(2));
      expect(members(tester)[0], contains('You, owner since'));
      // Their profile, from the row: where they are, and the way to the note.
      await bringIntoView(tester, find.byKey(const ValueKey('member:sam')));
      await tester.tap(find.byKey(const ValueKey('member:sam')));
      await tester.pump();
      final profile = find.byKey(const ValueKey('member-profile'));
      expect(find.descendant(of: profile, matching: find.text('Editing Roadmap now')), findsOneWidget);
      await tapKey(tester, 'member-jump');
      expect(asked.jumps, ['n-road']);
      // Differs 24 (docs/PARITY.md): the button said "Open the note" whatever it opened, and a canvas with no name
      // was "an untitled note" (notes/OrganizationScreen.tsx:395,419-422).
      String jump() => tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('member-jump')), matching: find.byType(Text))).data!;
      expect(jump(), 'Open the note');
      seen.value = const [OrgPresence(client: '1', handle: 'sam', hue: 'rose', editingNote: 'n-road', editingTitle: 'Roadmap', editingPlace: true)];
      await tester.pump();
      expect(jump(), 'Jump to cursor');
      seen.value = const [OrgPresence(client: '1', handle: 'sam', hue: 'rose', editingNote: 'n-map', editingTitle: '', editingCanvas: true)];
      await tester.pump();
      expect(members(tester)[1], contains('editing an untitled canvas'));
      expect(find.descendant(of: profile, matching: find.text('Editing an untitled canvas now')), findsOneWidget);
      expect(jump(), 'Open the canvas');
      seen.value = const [OrgPresence(client: '1', handle: 'sam', hue: 'rose', editingNote: 'n-map', editingTitle: '', editingCanvas: true, editingPlace: true)];
      await tester.pump();
      expect(jump(), 'Jump to cursor');
      seen.value = const [OrgPresence(client: '1', handle: 'sam', hue: 'rose', editingNote: 'n-new', editingTitle: '')];
      await tester.pump();
      expect(members(tester)[1], contains('editing an untitled note'));
      // In the app with nothing open: here, and the profile says so without a jump.
      seen.value = const [OrgPresence(client: '1', handle: 'sam', hue: 'rose')];
      await tester.pump();
      expect(members(tester)[1], contains('here now'));
      expect(find.descendant(of: profile, matching: find.text('In the app now')), findsOneWidget);
      expect(find.byKey(const ValueKey('member-jump')), findsNothing);
      // Gone: the row says since when again.
      seen.value = const [];
      await tester.pump();
      expect(members(tester)[1], contains('joined'));
      expect(find.byKey(const ValueKey('member-here')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('member:matt')));
      await tester.pump();
      expect(find.text('In the app now, on this device'), findsOneWidget);
      await endSettings(tester);
    });

    // docs/CLAUDE_LIVE.md: "Claude online", on its AI row and never as a member.
    testWidgets('shows an AI online on its own row, editing or reading, with Jump and Follow, and never as a member, even under a member’s handle', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await sam(device, id, joined: true);
      device.service.peerAi(id, 'Claude', via: 'matt');
      final seen = ValueNotifier<List<OrgPresence>>(const []);
      final asked = await page(tester, device, id, seen: seen);
      expect(ais(tester), ['CClaudeAIThrough you · last seen just now']);
      expect(find.byKey(const ValueKey('ai-here')), findsNothing);

      // Claude editing Roadmap at its caret; and an AI that calls itself sam, online on no note.
      seen.value = const [
        OrgPresence(client: '7', handle: 'Claude', hue: 'violet', ai: true, via: 'matt', editingNote: 'n-road', editingTitle: 'Roadmap', editingPlace: true, doing: 'editing'),
        OrgPresence(client: '8', handle: 'sam', ai: true, via: 'matt'),
      ];
      await tester.pump();
      // sam the member is not here: the AI under that name is not them.
      expect(members(tester)[1], contains('joined'));
      expect(find.byKey(const ValueKey('member-here')), findsOneWidget);
      // Each AI on its row, online: Claude's listed one, and a row made for the one not listed yet.
      expect(ais(tester), ['CClaudeAIediting RoadmapJump to cursorFollow', 'SsamAIonlineFollow']);
      expect(find.byKey(const ValueKey('ai-here')), findsNWidgets(2));
      expect(find.byKey(const ValueKey('ai-jump')), findsOneWidget);
      await tapKey(tester, 'ai-jump');
      expect(asked.jumps, ['n-road']);
      await bringIntoView(tester, find.byKey(const ValueKey('ai-follow')).first);
      await tester.tap(find.byKey(const ValueKey('ai-follow')).first);
      await tester.pump();
      expect(asked.followed, ['Claude']);

      // Reading, with no caret: the note opened, not jumped into.
      seen.value = const [OrgPresence(client: '7', handle: 'Claude', ai: true, via: 'matt', editingNote: 'n-road', editingTitle: 'Roadmap', doing: 'reading')];
      await tester.pump();
      expect(ais(tester), ['CClaudeAIreading RoadmapOpen the noteFollow']);
      // Gone: last seen again, and nothing to press.
      seen.value = const [];
      await tester.pump();
      expect(ais(tester), ['CClaudeAIThrough you · last seen just now']);
      expect(find.byKey(const ValueKey('ai-follow')), findsNothing);
      await endSettings(tester);
    });

    testWidgets('shows the organization’s own news, newest first, and not another’s or an invitation', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      device.service.notifies(kind: 'member-joined', from: 'sam', org: (id: id, name: 'Ghost'), body: {'name': 'Ghost'}, at: 1000);
      device.service.notifies(kind: 'role-changed', from: 'matt', org: (id: id, name: 'Ghost'), body: {'name': 'Ghost', 'role': 'admin'}, at: 2000);
      device.service.notifies(kind: 'member-joined', from: 'lee', org: (id: 'elsewhere', name: 'Elsewhere'), body: {'name': 'Elsewhere'}, at: 3000);
      device.service.notifies(kind: 'invite', from: 'sam', org: (id: id, name: 'Ghost'), body: {'name': 'Ghost'}, state: 'pending', at: 4000);
      // The pass the page runs as it opens brings them.
      await page(tester, device, id);
      expect(news(tester), hasLength(2));
      expect(news(tester)[0], contains('admin'));
      expect(news(tester)[1], contains('sam'));
      await endSettings(tester);
    });

    testWidgets('is the invitation when the person is invited and not yet in, with Accept and Decline', (tester) async {
      // No engine here: this list is the device's own, and a pass would take the service's.
      final lone = await Device.make(engine: false);
      lone.orgs.saveOrgs(lone.account.session!.accountId, const OrgState(list: [OrgRow(id: 'inv', name: 'Studio', role: 'member', state: 'invited', members: 3, invitedBy: 'sam', createdAt: 1)], at: 1));
      await page(tester, lone, 'inv');
      expect(tester.widget<Text>(find.byKey(const ValueKey('org-hero-meta'))).data, 'sam invited you · 3 members');
      expect(find.byType(InviteActions), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.bySemanticsLabel('Members'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('moves to another organization by its pill', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final other = await ghost(device, name: 'Studio', hue: 'rose');
      final asked = await page(tester, device, id);
      final pills = tester.widgetList<OrgPill>(find.byType(OrgPill)).toList();
      expect([for (final pill in pills) pill.label], ['Ghost', 'Studio']);
      expect(pills.first.pressed, isTrue);
      expect(pills.first.onPressed, isNull);
      await tester.tap(find.byKey(ValueKey('org-pill:$other')));
      expect(asked.organizations, [other]);
      await endSettings(tester);
    });

    testWidgets('says so when the organization is no longer in the list, with no cog', (tester) async {
      final device = await Device.make();
      await page(tester, device, 'gone');
      expect(find.text('This organization is not in your list any more.'), findsOneWidget);
      expect(find.byKey(const ValueKey('organization-cog')), findsNothing);
      await endSettings(tester);
    });

    testWidgets('says what is missing when signed out, and asks for nothing', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await device.services.signOut();
      final before = device.service.calls.length;
      final asked = await page(tester, device, id);
      expect(find.textContaining('Organizations come with an account. Sign in under ', findRichText: true), findsOneWidget);
      expect(device.service.calls.length, before);
      await tester.tap(find.text('Account'));
      expect(asked.account, 1);
      await endSettings(tester);
    });

    // This port's own: the page with no services at all is the signed-out one.
    testWidgets('with no services is the signed-out page', (tester) async {
      final device = await Device.make();
      await page(tester, device, 'any', services: false);
      expect(find.textContaining('Organizations come with an account.', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('organization-cog')), findsNothing);
      await endSettings(tester);
    });

    testWidgets('on a wide page the members stand beside the notes and the activity', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await page(tester, device, id, size: wideWindow);
      final notes = tester.getTopLeft(find.text('Notes'));
      final membersAt = tester.getTopLeft(find.text('Members'));
      final activity = tester.getTopLeft(find.text('Activity'));
      expect(membersAt.dy, closeTo(notes.dy, 1));
      expect(membersAt.dx, greaterThan(notes.dx + 400));
      expect(activity.dx, closeTo(notes.dx, 1));
      expect(activity.dy, greaterThan(notes.dy));
      await endSettings(tester);
    });
  });
}
