// An organization's own screen against the service in memory. A port of
// `src/app/settings/OrganizationSheet.test.tsx`, case for case, and of `InviteLinks.test.tsx`.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/workspace_swatch.dart';
import 'package:ghost_md/orgs/ui/parts.dart';
import 'package:ghost_md/settings/invite_links.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/organization_sheet.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// The card titled [title] on the page.
Finder card(String title) => find.byWidgetPredicate((w) => w is PaneSection && w.title == title);

/// An AI's row on Members, by name, with its chip's words, its hint and the words under it.
({String? chip, String? hint, List<String> words})? ai(WidgetTester tester, String name) {
  final row = find.byWidgetPredicate((w) => w is AiRow && w.ai.name == name);
  if (row.evaluate().isEmpty) return null;
  final chip = find.descendant(of: row, matching: find.descendant(of: find.byType(RoleChip), matching: find.byType(Text)));
  final setting = tester.widget<SettingRow>(find.descendant(of: row, matching: find.byType(SettingRow)));
  return (
    chip: chip.evaluate().isEmpty ? null : tester.widget<Text>(chip.first).data,
    hint: (setting.hint as Text?)?.data,
    words: [for (final action in tester.widgetList<RowAction>(find.descendant(of: row, matching: find.byType(RowAction)))) (action.child as Text).data!],
  );
}

/// Presses Remove under the AI called [name].
Future<void> removeAi(WidgetTester tester, String name) async {
  final target = find.descendant(of: find.byWidgetPredicate((w) => w is AiRow && w.ai.name == name), matching: find.text('Remove'));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await settle(tester, 10);
}

String? footerOf(WidgetTester tester, String title) => (tester.widget<PaneSection>(card(title)).footer as Text?)?.data;

void main() {
  setUpAll(loadAppFonts);

  group('the screen', () {
    testWidgets('opens on Members, with the hero and the sentence about the workspace, under the organization’s name and without a search', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await pumpSheet(tester, device, id);
      expect(display(tester), 'Members');
      expect(find.byKey(const ValueKey('settings-search')), findsNothing);
      expect(tester.widget<PaneHero>(find.byType(PaneHero)).title, 'Ghost');
      expect(heroMeta(tester), '1 member · You are owner');
      expect(tester.widget<HueRound>(find.descendant(of: find.byType(PaneHero), matching: find.byType(HueRound))).hue, 'sea');
      expect((tester.widget<PaneSection>(find.ancestor(of: find.byType(PaneHero), matching: find.byType(PaneSection))).footer! as Text).data, 'Notes filed here are the team’s: everyone in it reads and edits them, and edits made apart merge.');
      expect(member(tester, 'matt')?.chip, 'Owner');
      // The owner's own row offers nothing: leaving is the last section, and nobody removes the owner.
      expect(member(tester, 'matt')?.words, isEmpty);
      await endSettings(tester);
    });

    testWidgets('has Your colour here under the members: the account’s until one is picked, then that one alone, with the way back', (tester) async {
      final device = await Device.make();
      await device.orgs.setAccountColour('moss');
      final id = await ghost(device);
      await pumpSheet(tester, device, id);
      expect(member(tester, 'matt')?.chip, 'Owner');
      expect(footerOf(tester, 'Your colour here'), contains('Your account’s colour'));
      final rose = find.descendant(of: card('Your colour here'), matching: find.bySemanticsLabel('Rose'));
      await tester.ensureVisible(rose);
      await tester.pump();
      await tester.tap(rose);
      await settle(tester, 10);
      expect(device.service.orgs[id]!.rows['matt']!.hue, 'rose');
      expect(footerOf(tester, 'Your colour here'), contains('Worn in this organization alone'));
      expect(tester.widget<WorkspaceSwatch>(find.descendant(of: card('Your colour here'), matching: find.byType(WorkspaceSwatch))).hue, 'rose');
      await press(tester, 'Use your account’s colour');
      await settle(tester, 10);
      expect(device.service.orgs[id]!.rows['matt']!.hue, isNull);
      expect(footerOf(tester, 'Your colour here'), contains('Your account’s colour'));
      await endSettings(tester);
    });

    testWidgets('steps back from Members to the six sections, Delete last for the owner, and closes from there', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      var closed = 0;
      await pumpSheet(tester, device, id, onClose: () => closed += 1);
      await goBack(tester);
      expect(display(tester), isNull);
      expect(labels(tester), ['General', 'Members', 'Workspace', 'Notifications', 'Report', 'Delete']);
      expect(tester.getSemantics(headWord).label, 'Back to your notes');
      await goBack(tester);
      expect(closed, 1);
      await endSettings(tester);
    });

    testWidgets('says “← Organizations” when opened from Settings, and closing is that', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      var closed = 0;
      await pumpSheet(tester, device, id, from: OrganizationFrom.settings, onClose: () => closed += 1);
      await tester.tap(headWord);
      await settle(tester, 10);
      expect(headWords(tester), 'Organizations');
      await tester.tap(headWord);
      await settle(tester, 10);
      expect(closed, 1);
      await endSettings(tester);
    });

    testWidgets('opens on its sections from the dashboard’s cog, its head the organization’s name, which closes back to it', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      var closed = 0;
      await pumpSheet(tester, device, id, from: OrganizationFrom.dashboard, landOnMembers: false, onClose: () => closed += 1);
      expect(display(tester), isNull);
      expect(labels(tester), contains('Members'));
      // The word is the place it goes, the dashboard, named as the organization is; not "Back to your notes".
      expect(headWords(tester), 'Ghost');
      await tester.tap(headWord);
      await settle(tester, 10);
      expect(closed, 1);
      await endSettings(tester);
    });

    testWidgets('shows the list beside Members on a wide window, with Members’ row current', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await pumpSheet(tester, device, id, size: wideWindow);
      expect(display(tester), 'Members');
      expect(labels(tester), ['General', 'Members', 'Workspace', 'Notifications', 'Report', 'Delete']);
      // The pane wears Members' blue.
      expect(tokensAt(tester, find.byType(PaneHero)).attrs['hue'], 'blue');
      await endSettings(tester);
    });
  });

  group('Members', () {
    testWidgets('invites by handle, draws the invitee with a dashed chip, and says in the service’s words when nobody has the handle', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await pumpSheet(tester, device, id);
      expect(member(tester, 'matt'), isNotNull);
      await tester.ensureVisible(find.byKey(const ValueKey('organization-invite')));
      await typeInto(tester, 'Handle', 'nobody');
      await tapKey(tester, 'organization-invite');
      await settle(tester, 10);
      expect(find.text('No one has that handle.'), findsOneWidget);
      await typeInto(tester, 'Handle', 'sam');
      await tapKey(tester, 'organization-invite');
      await settle(tester, 10);
      expect(member(tester, 'sam')?.chip, 'Invited');
      expect(tester.widget<RoleChip>(find.descendant(of: find.byKey(const ValueKey('member:sam')), matching: find.byType(RoleChip))).member?.state, 'invited');
      expect(find.text('sam is invited. They see it in their notifications.'), findsOneWidget);
      expect(member(tester, 'sam')?.hint, startsWith('Invited by matt'));
      // An invitee can be withdrawn, not made anything.
      expect(member(tester, 'sam')?.words, ['Withdraw']);
      await pressOn(tester, 'sam', 'Withdraw');
      expect(member(tester, 'sam'), isNull);
      expect(device.service.orgs[id]?.rows['sam']?.state ?? 'gone', isNot('invited'));
      await endSettings(tester);
    });

    testWidgets('lets the owner make an admin, remove a member, and hand over on a second tap, after which Delete is Leave', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await sam(device, id, joined: true);
      await pumpSheet(tester, device, id);
      expect(member(tester, 'sam')?.chip, 'Member');
      expect(member(tester, 'sam')?.words, ['Make admin', 'Hand over', 'Remove']);
      expect(heroMeta(tester), '2 members · You are owner');
      await pressOn(tester, 'sam', 'Make admin');
      expect(member(tester, 'sam')?.chip, 'Admin');
      expect(member(tester, 'sam')?.words, ['Make member', 'Hand over', 'Remove']);
      // Handing over asks twice.
      await pressOn(tester, 'sam', 'Hand over');
      expect(member(tester, 'sam')?.words, contains('Tap again to hand over'));
      expect(device.service.orgs[id]?.rows['sam']?.role, 'admin');
      await pressOn(tester, 'sam', 'Tap again to hand over');
      expect(member(tester, 'sam')?.chip, 'Owner');
      expect(member(tester, 'matt')?.chip, 'Admin');
      expect(heroMeta(tester), '2 members · You are admin');
      // An admin removes members, never the owner, and the last section is Leave now.
      expect(member(tester, 'sam')?.words, isEmpty);
      await goBack(tester);
      expect(labels(tester), ['General', 'Members', 'Workspace', 'Notifications', 'Report', 'Leave']);
      await endSettings(tester);
    });

    // Matt: "when an AI has accessed an ORG add it as a member labeled as (AI)".
    testWidgets('lists an AI seen through a member’s connector after the members, with whose it came through, and removes it for the owner', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await sam(device, id, joined: true);
      final now = DateTime.now().millisecondsSinceEpoch;
      const day = 24 * 60 * 60000;
      final mine = device.service.peerAi(id, 'Claude', via: 'matt', firstSeen: now - 3 * day, lastSeen: now);
      device.service.peerAi(id, 'Cursor', via: 'sam', firstSeen: now - 3 * day, lastSeen: now - day);
      await pumpSheet(tester, device, id);
      expect(ai(tester, 'Claude')?.chip, 'AI');
      expect(ai(tester, 'Claude')?.hint, 'Through you · last seen just now');
      expect(ai(tester, 'Claude')?.words, ['Remove']);
      expect(ai(tester, 'Cursor')?.chip, 'AI');
      expect(ai(tester, 'Cursor')?.hint, 'Through sam · last seen yesterday');
      expect(ai(tester, 'Cursor')?.words, ['Remove']);
      // After the people, and not counted with them.
      final order = [for (final row in tester.widgetList<SettingRow>(find.descendant(of: card('Members'), matching: find.byType(SettingRow)))) row.label];
      expect(order, ['matt', 'sam', 'Claude', 'Cursor']);
      expect(heroMeta(tester), '2 members · You are owner');
      expect(footerOf(tester, 'Members'), 'An AI reads and writes through its member’s own access, with their connector. Removing it takes it off this list, not out of the notes: it is listed again when it next reads them.');
      await removeAi(tester, 'Cursor');
      expect(ai(tester, 'Cursor'), isNull);
      expect(device.service.calls.where((call) => call.startsWith('DELETE orgs/$id/ais/')), hasLength(1));
      expect(device.service.aisOf(id).map((ai) => ai['id']), [mine]);
      // sam is still a member: an AI's row going is no person going.
      expect(member(tester, 'sam')?.chip, 'Member');
      await endSettings(tester);
    });

    testWidgets('lets a member remove the AI that came through them and no one else’s, and says nothing of AIs where there are none', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await sam(device, id, joined: true);
      await pumpSheet(tester, device, id);
      expect(member(tester, 'sam')?.chip, 'Member');
      expect(footerOf(tester, 'Members'), isNull);
      expect(find.textContaining('An AI reads and writes'), findsNothing);
      await endSettings(tester);
      device.service.peerAi(id, 'Claude', via: 'matt');
      device.service.peerAi(id, 'Cursor', via: 'sam');
      // matt as a plain member: sam owns it now.
      device.service.orgs[id]!.rows['matt']!.role = 'member';
      device.service.orgs[id]!.rows['sam']!.role = 'owner';
      await listed(device);
      await pumpSheet(tester, device, id);
      expect(ai(tester, 'Cursor')?.chip, 'AI');
      expect(ai(tester, 'Cursor')?.hint, 'Through sam · last seen just now');
      expect(ai(tester, 'Cursor')?.words, isEmpty);
      expect(ai(tester, 'Claude')?.words, ['Remove']);
      await removeAi(tester, 'Claude');
      expect(ai(tester, 'Claude'), isNull);
      expect(device.service.aisOf(id).map((ai) => ai['name']), ['Cursor']);
      await endSettings(tester);
    });

    testWidgets('shows the service’s refusal under the AI’s row it was asked on', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final mine = device.service.peerAi(id, 'Claude', via: 'matt');
      await pumpSheet(tester, device, id);
      expect(ai(tester, 'Claude')?.words, ['Remove']);
      // Gone from another device meanwhile.
      device.service.orgs[id]!.ais.remove(mine);
      await removeAi(tester, 'Claude');
      expect(ai(tester, 'Claude')?.hint, 'No such AI in this organization.');
      await endSettings(tester);
    });

    testWidgets('shows the service’s refusal under the row it was asked on', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await sam(device, id, joined: false);
      // The fake refuses a role for someone who has not joined, as the service does.
      final row = device.service.orgs[id]!.rows['sam']!;
      row.state = 'member';
      await pumpSheet(tester, device, id);
      expect(member(tester, 'sam')?.chip, 'Member');
      row.state = 'invited';
      await pressOn(tester, 'sam', 'Make admin');
      expect(member(tester, 'sam')?.hint, 'They have not joined yet.');
      await endSettings(tester);
    });

    testWidgets('makes an invite link, copies it as it is made, lists it with its terms, and turns it off', (tester) async {
      final device = await Device.make();
      final copied = Clipped(tester);
      final id = await ghost(device);
      await pumpSheet(tester, device, id);
      expect(find.text('No links yet. Make one to send to people who should join.'), findsOneWidget);
      await tapKey(tester, 'invite-link-new');
      await settle(tester);
      // A day, for one person.
      final lasts = find.byWidgetPredicate((w) => w is GlacierSegmentedControl && w.ariaLabel == 'How long the link lasts');
      final who = find.byWidgetPredicate((w) => w is GlacierSegmentedControl && w.ariaLabel == 'How many can join by it');
      await tester.ensureVisible(who);
      await tester.pump();
      tester.widget<GlacierSegmentedControl>(lasts).onValueChange!('day');
      tester.widget<GlacierSegmentedControl>(who).onValueChange!('one');
      await tester.pump();
      await press(tester, 'Make the link');
      await settle(tester, 10);
      final link = device.service.links.values.single;
      expect(find.byKey(ValueKey('invite-link:${link.id}')), findsOneWidget);
      expect(copied.text, 'https://ghostmarkdown.com/read.html#join=${link.code}');
      expect(find.text('The link is made and copied. Anyone signed in who has it can join.'), findsOneWidget);
      expect(find.text('Stops in 24 hours · 0 of 1 used'), findsOneWidget);
      expect(link.maxUses, 1);
      await tester.tap(find.bySemanticsLabel('Turn the link off'));
      await settle(tester, 10);
      expect(find.text('No links yet. Make one to send to people who should join.'), findsOneWidget);
      expect(device.service.links, isEmpty);
      expect(find.text('The link is turned off. No one else can join by it.'), findsOneWidget);
      await endSettings(tester);
    });

    // InviteLinks.test.tsx: "invite links on an older service draw nothing".
    testWidgets('draws no "Invite by link" section, heading and all, on a service from before invite links', (tester) async {
      final service = await FakeService.start(seed: seeded);
      // The live service before its deploy: the organization's routes answer, the links' are not there.
      final device = await Device.make(service: service, fetcher: (request) async => request.url.path.contains('/links') ? FetchResponse(404) : service.fetcher(request));
      final id = await ghost(device);
      await pumpSheet(tester, device, id);
      expect(find.text('Reading the links…'), findsNothing);
      expect(find.text('INVITE BY LINK'), findsNothing);
      expect(find.textContaining('Anyone signed in who has the link'), findsNothing);
      expect(find.byType(InviteLinks), findsOneWidget);
      // The card by handle is still there.
      expect(find.text('INVITE'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('shows no invite links to a member who does not manage the organization', (tester) async {
      final device = await Device.make();
      final id = await boo(device);
      await pumpSheet(tester, device, id);
      expect(member(tester, 'sam'), isNotNull);
      expect(find.text('INVITE BY LINK'), findsNothing);
      expect(device.service.calls.any((call) => call.contains('/links')), isFalse);
      await endSettings(tester);
    });

    testWidgets('draws an invitation with Accept and Decline when the account is only invited', (tester) async {
      final device = await Device.make();
      final id = await boo(device, member: false);
      await pumpSheet(tester, device, id);
      expect(heroMeta(tester), '1 member · You are invited');
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is GlacierInput && w.ariaLabel == 'Handle'), findsNothing);
      await goBack(tester);
      expect(headWords(tester), 'Boo');
      await endSettings(tester);
    });
  });

  group('General', () {
    testWidgets('renames and recolours for the owner, the workspace following', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      await pumpSheet(tester, device, id);
      expect(member(tester, 'matt'), isNotNull);
      await goBack(tester);
      await openSection(tester, 'General');
      expect(display(tester), 'General');
      expect(tester.widget<GlacierInput>(find.byWidgetPredicate((w) => w is GlacierInput && w.ariaLabel == 'Organization name')).value, 'Ghost');
      expect(pressableOf(tester, 'Rename').onPressed, isNull);
      await typeInto(tester, 'Organization name', 'Boo');
      await tapKey(tester, 'organization-rename');
      await settle(tester, 10);
      await goBack(tester);
      expect(find.text('Boo'), findsWidgets);
      expect(device.workspaces.value.list, [Workspace(id: 'org-$id', name: 'Boo', hue: 'sea')]);
      await openSection(tester, 'General');
      await tester.tap(find.bySemanticsLabel('Rose'));
      await settle(tester, 10);
      expect(device.workspaces.value.list.first.hue, 'rose');
      expect(device.service.orgs[id]?.hue, 'rose');
      await endSettings(tester);
    });

    testWidgets('only shows the name and the colour to a member', (tester) async {
      final device = await Device.make();
      final id = await boo(device);
      await pumpSheet(tester, device, id);
      expect(member(tester, 'sam')?.chip, 'Owner');
      expect(find.byWidgetPredicate((w) => w is GlacierInput && w.ariaLabel == 'Handle'), findsNothing);
      await goBack(tester);
      await openSection(tester, 'General');
      expect(find.byWidgetPredicate((w) => w is GlacierInput && w.ariaLabel == 'Organization name'), findsNothing);
      expect(find.byType(WorkspaceSwatch), findsNothing);
      expect(find.text('Only the owner or an admin can rename it.'), findsOneWidget);
      await endSettings(tester);
    });
  });

  group('the rest', () {
    testWidgets('goes to the notes filed in its workspace, and mutes the organization', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      var notes = 0;
      await pumpSheet(tester, device, id, onNotes: () => notes += 1);
      await goBack(tester);
      await openSection(tester, 'Workspace');
      expect(find.textContaining('Notes filed here are the team’s'), findsOneWidget);
      await press(tester, 'Notes filed here');
      expect(notes, 1);
      await goBack(tester);
      await openSection(tester, 'Notifications');
      final mute = find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'Mute this organization');
      await tester.tap(mute);
      await settle(tester);
      expect(preferences.value.notifications.mutedOrgs, [id]);
      await tester.tap(mute);
      await settle(tester);
      expect(preferences.value.notifications.mutedOrgs, isEmpty);
      await endSettings(tester);
    });

    testWidgets('opens an email to the maker from Report, naming the organization and who reports', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final opened = <String>[];
      await pumpSheet(tester, device, id, onOpenLink: opened.add);
      await goBack(tester);
      await openSection(tester, 'Report');
      expect(find.textContaining('Team notes are sealed'), findsOneWidget);
      await press(tester, 'Report a member or a note');
      expect(opened, hasLength(1));
      final mail = Uri.parse(opened.single);
      expect(mail.scheme, 'mailto');
      expect(mail.path, 'infamousvaguerat@gmail.com');
      expect(mail.queryParameters['subject'], 'Ghost.md report: Ghost ($id)');
      expect(mail.queryParameters['body'], contains('Reported by: matt'));
      await endSettings(tester);
    });

    testWidgets('deletes on a second tap, the workspace going with it, and closes', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      var closed = 0;
      await pumpSheet(tester, device, id, onClose: () => closed += 1);
      await goBack(tester);
      await openSection(tester, 'Delete');
      await tester.tap(find.widgetWithText(RowAction, 'Delete'));
      await tester.pump();
      expect(find.text('Tap again'), findsOneWidget);
      expect(device.service.orgs.containsKey(id), isTrue);
      await tester.tap(find.text('Tap again'));
      await settle(tester, 10);
      expect(closed, 1);
      expect(device.service.orgs.containsKey(id), isFalse);
      expect(device.workspaces.value.list, isEmpty);
      await endSettings(tester);
    });

    testWidgets('leaves on a second tap, for a member', (tester) async {
      final device = await Device.make();
      final id = await boo(device);
      expect([for (final w in device.workspaces.value.list) w.id], ['org-$id']);
      var closed = 0;
      await pumpSheet(tester, device, id, onClose: () => closed += 1);
      await goBack(tester);
      await openSection(tester, 'Leave');
      await tester.tap(find.widgetWithText(RowAction, 'Leave'));
      await tester.pump();
      await tester.tap(find.text('Tap again'));
      await settle(tester, 10);
      expect(closed, 1);
      expect(device.service.rowIn(id), isNull);
      expect(device.workspaces.value.list, isEmpty);
      await endSettings(tester);
    });
  });
}
