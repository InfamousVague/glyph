// An invite link that opened the app. A port of `src/app/notes/JoinSheet.test.tsx`, case for case, and the new
// organization's sheet beside it (the web has no test of `home/NewOrganizationSheet.tsx`; these are this port's).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/orgs/join_links.dart';
import 'package:ghost_md/orgs/ui/join_sheet.dart';
import 'package:ghost_md/orgs/ui/new_organization_sheet.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';

import 'support.dart';

class Asked {
  final List<String> opened = [];
  int account = 0;
}

Future<Asked> host(WidgetTester tester, Device device, String code, {ValueNotifier<bool>? hold}) async {
  final asked = Asked();
  final held = hold ?? ValueNotifier<bool>(false);
  await device.pump(
    tester,
    ValueListenableBuilder<bool>(
      valueListenable: held,
      builder: (context, hold, _) => Stack(
        children: [JoinInvites(services: device.services, request: JoinRequest(code, 1), hold: hold, onOpen: asked.opened.add, onAccount: () => asked.account += 1)],
      ),
    ),
    scroll: false,
  );
  await settle(tester, 12);
  return asked;
}

/// The sheet's title, or null when there is no sheet.
String? title(WidgetTester tester) {
  final found = find.byType(SheetTitle);
  if (found.evaluate().isEmpty) return null;
  return find.descendant(of: found, matching: find.byType(RichText)).evaluate().map((e) => (e.widget as RichText).text.toPlainText().replaceAll('￼', '')).join();
}

Future<void> pressRow(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(SheetRow, label));
  await settle(tester, 14);
}

void main() {
  setUpAll(loadAppFonts);

  group('an invite link', () {
    testWidgets('names the organization and who sent it, and joins only on Join, opening it', (tester) async {
      final device = await Device.make();
      final code = device.service.peerLink('Ghost', by: 'sam');
      final asked = await host(tester, device, code);
      expect(title(tester), 'Join Ghost?');
      expect(find.textContaining('sam shared this invite link. 1 member so far.'), findsOneWidget);
      final orgId = device.service.orgs.keys.first;
      expect(device.service.rowIn(orgId), isNull);
      await pressRow(tester, 'Join Ghost');
      expect(asked.opened, [orgId]);
      expect(device.service.rowIn(orgId), (role: 'member', state: 'member'));
      expect([for (final row in device.orgs.orgsState().list) (row.name, row.state)], [('Ghost', 'member')]);
      expect([for (final w in device.workspaces.value.list) w.name], contains('Ghost'));
      expect(find.byType(Sheet), findsNothing);
      expect(heldJoin(kept: device.kept), isNull);
      await endSettings(tester);
    });

    testWidgets('is let go on Not now, with nothing joined', (tester) async {
      final device = await Device.make();
      final code = device.service.peerLink('Ghost', by: 'sam');
      await host(tester, device, code);
      expect(title(tester), 'Join Ghost?');
      await pressRow(tester, 'Not now');
      expect(find.byType(Sheet), findsNothing);
      expect(heldJoin(kept: device.kept), isNull);
      expect(device.service.rowIn(device.service.orgs.keys.first), isNull);
      await endSettings(tester);
    });

    testWidgets('that stopped working says so in the service’s words', (tester) async {
      final device = await Device.make();
      final code = device.service.peerLink('Ghost', by: 'sam', expiresAt: DateTime.now().millisecondsSinceEpoch - 1);
      await host(tester, device, code);
      expect(title(tester), 'This invite link doesn’t work');
      expect(find.text('That invite link has expired or was turned off.'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('for an organization already joined offers to open it', (tester) async {
      final device = await Device.make();
      final code = device.service.peerLink('Ghost', by: 'sam');
      final orgId = device.service.orgs.keys.first;
      device.service.orgs[orgId]!.rows['matt'] = OrgRowKept(handle: 'matt', role: 'member', state: 'member', since: 1, invitedBy: 'sam');
      final asked = await host(tester, device, code);
      expect(title(tester), 'You’re in Ghost');
      await pressRow(tester, 'Open Ghost');
      expect(asked.opened, [orgId]);
      await endSettings(tester);
    });

    testWidgets('followed signed out waits on this device, and is asked about once an account is signed in', (tester) async {
      final device = await Device.make(signedIn: false);
      final code = device.service.peerLink('Ghost', by: 'sam');
      final asked = await host(tester, device, code);
      expect(title(tester), 'Join a team');
      await pressRow(tester, 'Sign in or sign up');
      expect(asked.account, 1);
      expect(find.byType(Sheet), findsNothing);
      expect(heldJoin(kept: device.kept), code);
      await device.account.signIn(seeded.handle, seeded.password);
      await settle(tester, 14);
      expect(title(tester), 'Join Ghost?');
      await endSettings(tester);
    });

    testWidgets('waits while the way into an account is up', (tester) async {
      final device = await Device.make();
      final code = device.service.peerLink('Ghost', by: 'sam');
      final hold = ValueNotifier<bool>(true);
      await host(tester, device, code, hold: hold);
      expect(find.byType(Sheet), findsNothing);
      hold.value = false;
      await settle(tester, 14);
      expect(title(tester), 'Join Ghost?');
      await endSettings(tester);
    });
  });

  group('a new organization, from the home page’s filters', () {
    Future<List<String>> sheet(WidgetTester tester, Device device, {VoidCallback? onClose, List<(String, List<String>)>? tools}) async {
      final made = <String>[];
      await device.pump(
        tester,
        Stack(children: [NewOrganizationSheet(services: device.services, open: true, onClose: onClose ?? () {}, onMade: made.add, onTools: tools == null ? null : (id, chosen) => tools.add((id, chosen)))]),
        scroll: false,
      );
      await settle(tester, 12);
      return made;
    }

    testWidgets('is a name, then the team’s tools, made on the service and opened at once, with its workspace here', (tester) async {
      final device = await Device.make();
      var closed = 0;
      final tools = <(String, List<String>)>[];
      final made = await sheet(tester, device, onClose: () => closed += 1, tools: tools);
      expect(find.text('A team by name. You own it, can invite people by their handle, and each member gets its workspace.'), findsOneWidget);
      // Nothing to go on with until there is a name.
      await tester.tap(find.widgetWithText(SheetRow, 'Next'));
      await settle(tester);
      expect(find.text('Which tools does this team use?'), findsNothing);
      await tester.enterText(find.byType(EditableText), '  Studio ');
      await tester.pump();
      await pressRow(tester, 'Next');
      // The second step (docs/PM_PLUGINS.md): the suite, every one unchecked.
      expect(find.text('Which tools does this team use?'), findsOneWidget);
      for (final name in ['Tickets', 'Planning', 'Gantt and timelines', 'Boards', 'Automations', 'Time tracking', 'Forms']) {
        expect(tester.widget<SheetRow>(find.widgetWithText(SheetRow, name)).chosen, isFalse, reason: name);
      }
      expect(device.service.orgs, isEmpty, reason: 'nothing is made until Create');
      // Forms stands on Tickets: checking it checks Tickets; Gantt stands alone.
      await pressRow(tester, 'Forms');
      await pressRow(tester, 'Gantt and timelines');
      expect(tester.widget<SheetRow>(find.widgetWithText(SheetRow, 'Tickets')).chosen, isTrue);
      await pressRow(tester, 'Create');
      expect(device.service.orgs.values.single.name, 'Studio');
      expect(tools.single.$1, device.service.orgs.keys.single);
      expect(tools.single.$2, ['tickets', 'gantt', 'forms'], reason: 'in the suite’s order, with what they need');
      expect(made, [device.service.orgs.keys.single]);
      expect(closed, 1);
      expect([for (final w in device.workspaces.value.list) w.name], ['Studio']);
      await endSettings(tester);
    });

    testWidgets('Tickets unchecked takes the tools that stand on it, and Back keeps the name', (tester) async {
      final device = await Device.make();
      final tools = <(String, List<String>)>[];
      await sheet(tester, device, tools: tools);
      await tester.enterText(find.byType(EditableText), 'Studio');
      await tester.pump();
      await pressRow(tester, 'Next');
      await pressRow(tester, 'Planning');
      await pressRow(tester, 'Tickets');
      expect([for (final name in ['Tickets', 'Planning']) tester.widget<SheetRow>(find.widgetWithText(SheetRow, name)).chosen], [false, false]);
      await tester.ensureVisible(find.widgetWithText(SheetRow, 'Back'));
      await settle(tester);
      await pressRow(tester, 'Back');
      expect(find.text('A team by name. You own it, can invite people by their handle, and each member gets its workspace.'), findsOneWidget);
      await pressRow(tester, 'Next');
      await pressRow(tester, 'Create');
      expect(tools.single.$2, isEmpty, reason: 'none chosen is none on');
      await endSettings(tester);
    });

    testWidgets('says what the service refused under Create', (tester) async {
      final service = await FakeService.start(seed: seeded);
      final device = await Device.make(service: service, fetcher: (request) async => request.method == 'POST' && request.url.path.endsWith('/orgs') ? FetchResponse.json(409, {'error': 'You are in as many organizations as an account can be.'}) : service.fetcher(request));
      final made = await sheet(tester, device);
      await tester.enterText(find.byType(EditableText), 'Studio');
      await tester.pump();
      await pressRow(tester, 'Next');
      await pressRow(tester, 'Create');
      expect(find.text('You are in as many organizations as an account can be.'), findsOneWidget);
      expect(made, isEmpty);
      await endSettings(tester);
    });
  });
}
