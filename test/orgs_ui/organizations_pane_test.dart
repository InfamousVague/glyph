// Settings › Organizations, Accept and Decline, Settings › Notifications' mutes, the notifications drawer and the
// home page's organizations, each fed from the real organizations and feed over the service in memory. The web has
// no test of `OrganizationsPane.tsx` or `InviteActions.tsx` on their own; `NotificationsPane.test.tsx`'s "muting an
// organization" and `HomeOrganizations.test.tsx` / `HomeOrgEvents.test.tsx` are ported where they read the account
// (what those pages draw from data handed in is test/settings/panes and test/home).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/home/home_organizations.dart';
import 'package:ghost_md/notes/notifications_drawer.dart';
import 'package:ghost_md/orgs/ui/fed_notifications.dart';
import 'package:ghost_md/orgs/ui/org_news.dart';
import 'package:ghost_md/settings/invite_actions.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/notifications_pane.dart';
import 'package:ghost_md/settings/panes/organizations_pane.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/sync/feed.dart' show InviteMark;
import 'package:glacier/glacier.dart';

import 'support.dart';

List<String> rowLabels(WidgetTester tester, String title) => [
      for (final row in tester.widgetList<SettingRow>(find.descendant(of: find.byWidgetPredicate((w) => w is PaneSection && w.title == title), matching: find.byType(SettingRow)))) row.label,
    ];

void main() {
  setUpAll(loadAppFonts);

  group('Settings › Organizations', () {
    testWidgets('signed out, sends the person to Account, with or without services', (tester) async {
      final device = await Device.make(signedIn: false);
      var account = 0;
      await device.pump(tester, OrganizationsPane(services: device.services, onOpenAccount: () => account += 1));
      expect(find.textContaining('Organizations come with an account. Sign in under ', findRichText: true), findsOneWidget);
      await tester.tap(find.byType(GoWord));
      expect(account, 1);
      expect(find.byType(PaneSection), findsNothing);
      await endSettings(tester);
      await pumpSettings(tester, const OrganizationsPane());
      expect(find.textContaining('Organizations come with an account.', findRichText: true), findsOneWidget);
      await endSettings(tester);
      // A build that says it is signed in with nothing behind it still says the page waits.
      await pumpSettings(tester, const OrganizationsPane(signedIn: true));
      expect(find.byType(SettingsNotPorted), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('lists the ones joined with the role and the count, and says None yet with none', (tester) async {
      final device = await Device.make();
      await device.pump(tester, OrganizationsPane(services: device.services));
      expect(titlesOf(tester), ['Your organizations', 'New organization']);
      expect(rowLabels(tester, 'Your organizations'), ['None yet']);
      await endSettings(tester);
      final id = await ghost(device);
      await sam(device, id, joined: true);
      await boo(device);
      final opened = <String>[];
      await device.pump(tester, OrganizationsPane(services: device.services, onOrganization: opened.add));
      expect(rowLabels(tester, 'Your organizations'), ['Ghost', 'Boo']);
      expect(find.text('Owner · 2 members'), findsOneWidget);
      expect(find.text('Member · 2 members'), findsOneWidget);
      await press(tester, 'Ghost');
      expect(opened, [id]);
      await endSettings(tester);
    });

    testWidgets('makes a new one by name, which opens as soon as the service answers', (tester) async {
      final device = await Device.make();
      final opened = <String>[];
      await device.pump(tester, OrganizationsPane(services: device.services, onOrganization: opened.add));
      expect(pressableOf(tester, 'Create').onPressed, isNull);
      await typeInto(tester, 'Organization name', 'Studio');
      await tapKey(tester, 'new-organization-submit');
      await settle(tester, 10);
      final id = device.service.orgs.keys.single;
      expect(opened, [id]);
      expect(rowLabels(tester, 'Your organizations'), ['Studio']);
      expect([for (final w in device.workspaces.value.list) w.name], ['Studio']);
      await endSettings(tester);
    });

    testWidgets('draws an invitation with who sent it, and Accept joins, opens it and makes its workspace', (tester) async {
      final device = await Device.make();
      final id = device.service.invited('Boo', 'sam');
      await device.services.syncNow();
      final opened = <String>[];
      await device.pump(tester, OrganizationsPane(services: device.services, onOrganization: opened.add));
      expect(titlesOf(tester), ['Invitations', 'Your organizations', 'New organization']);
      expect(find.text('Invited by sam · 1 member'), findsOneWidget);
      expect(device.workspaces.value.list, isEmpty);
      await tapKey(tester, 'invite-accept');
      await settle(tester, 14);
      expect(device.service.rowIn(id), (role: 'member', state: 'member'));
      expect(opened, [id]);
      expect(titlesOf(tester), ['Your organizations', 'New organization']);
      expect(rowLabels(tester, 'Your organizations'), ['Boo']);
      expect([for (final w in device.workspaces.value.list) w.id], ['org-$id']);
      await endSettings(tester);
    });

    testWidgets('Decline answers no, the invitation goes and nothing is opened', (tester) async {
      final device = await Device.make();
      final id = device.service.invited('Boo', 'sam');
      await device.services.syncNow();
      final opened = <String>[];
      await device.pump(tester, OrganizationsPane(services: device.services, onOrganization: opened.add));
      await tapKey(tester, 'invite-decline');
      await settle(tester, 14);
      expect(device.service.rowIn(id)?.state, isNot('member'));
      expect(opened, isEmpty);
      expect(titlesOf(tester), ['Your organizations', 'New organization']);
      expect(device.workspaces.value.list, isEmpty);
      await endSettings(tester);
    });
  });

  group('Accept and Decline', () {
    testWidgets('say the sync’s own words when the answer did not arrive, and it is still queued', (tester) async {
      final service = await FakeService.start(seed: seeded);
      var down = false;
      final device = await Device.make(service: service, fetcher: (request) async => down ? FetchResponse.json(500, {'error': 'The service is down.'}) : service.fetcher(request));
      final id = service.invited('Boo', 'sam');
      await device.services.syncNow();
      final answered = <bool>[];
      await device.pump(tester, InviteActions(services: device.services, orgId: id, onAnswered: answered.add));
      down = true;
      await tapKey(tester, 'invite-accept');
      await settle(tester, 14);
      expect(answered, isEmpty);
      expect(find.textContaining('The service is down.'), findsOneWidget);
      expect(device.feed.feedState(device.account.session!.accountId).marks.whereType<InviteMark>(), hasLength(1));
      // Back up: the queued answer goes with the next pass.
      down = false;
      await device.services.syncNotificationsNow();
      expect(service.rowIn(id), (role: 'member', state: 'member'));
      await endSettings(tester);
    });
  });

  group('muting an organization', () {
    testWidgets('offers no card without one, and a row for each the account has joined, never one it is only invited to', (tester) async {
      final device = await Device.make();
      await device.pump(tester, NotificationsPane(services: device.services));
      expect(titlesOf(tester), ['What reaches you']);
      await endSettings(tester);
      final id = await ghost(device);
      device.service.invited('Boo', 'sam');
      await device.services.syncNow();
      await device.pump(tester, NotificationsPane(services: device.services));
      expect(titlesOf(tester), ['What reaches you', 'Mute an organization']);
      expect(rowLabels(tester, 'Mute an organization'), ['Ghost']);
      expect(find.text('1 member'), findsOneWidget);
      await tester.tap(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'Mute Ghost'));
      await settle(tester);
      expect(preferences.value.notifications.mutedOrgs, [id]);
      await endSettings(tester);
    });

    testWidgets('sends a signed-out person to Account, by a word that goes there', (tester) async {
      final device = await Device.make(signedIn: false);
      var account = 0;
      await device.pump(tester, NotificationsPane(services: device.services, onOpenAccount: () => account += 1));
      expect(find.textContaining('Notifications come with an account. Sign in under ', findRichText: true), findsOneWidget);
      await tester.tap(find.byType(GoWord));
      expect(account, 1);
      await endSettings(tester);
      await device.account.signIn(seeded.handle, seeded.password);
      await device.pump(tester, NotificationsPane(services: device.services));
      expect(find.byType(SettingsCallout), findsNothing);
      await endSettings(tester);
    });
  });

  group('Settings, with the account over it', () {
    testWidgets('its rows read the account: who is signed in and how many organizations are joined', (tester) async {
      final device = await Device.make();
      await ghost(device);
      await device.pump(tester, SettingsSheet(open: true, onClose: () {}, split: false), scroll: false);
      await settle(tester, 12);
      final summaries = [for (final text in tester.widgetList<Text>(find.byKey(const ValueKey('settings-row-summary')))) text.data];
      // The first two rows: Account's and Organizations' lines (Simple or advanced is Appearance's line now).
      expect(summaries.take(2), ['matt', '1 joined']);
      await device.services.signOut();
      await settle(tester, 12);
      final after = [for (final text in tester.widgetList<Text>(find.byKey(const ValueKey('settings-row-summary')))) text.data];
      expect(after.take(2), ['Not signed in', 'Signed out']);
      await endSettings(tester);
    });

    testWidgets('and with none over it they read as before there was an account', (tester) async {
      await pumpSettings(tester, SettingsSheet(open: true, onClose: () {}, split: false));
      await settle(tester, 12);
      final summaries = [for (final text in tester.widgetList<Text>(find.byKey(const ValueKey('settings-row-summary')))) text.data];
      expect(summaries.take(2), ['Not signed in', 'Signed out']);
      await endSettings(tester);
    });

    test('the search finds the signed-in page’s rows only when there is a page to land on', () {
      const prefs = Preferences();
      SettingsFacts facts({AccountServices? services, SettingsFeatures features = const SettingsFeatures()}) =>
          SettingsFacts(prefs: prefs, wide: false, haptics: false, android: true, ios: false, developer: false, services: services, features: features);
      final account = settingsSections.firstWhere((spec) => spec.id == 'account');
      expect([for (final found in account.settings!(facts())) found.name].take(3), ['I have an account', 'Create an account', 'Lost the password']);
      expect(account.settings!(facts(features: const SettingsFeatures(signedIn: true))), isEmpty);
    });
  });

  group('the notifications drawer, fed', () {
    Future<List<String>> drawer(WidgetTester tester, Device device) async {
      final opened = <String>[];
      await device.pump(
        tester,
        Stack(children: [FedNotificationsDrawer(services: device.services, onClose: () {}, onOpenNote: (id, at) => opened.add('note:$id'), onOpenOrganization: (id) => opened.add('org:$id'), onAccount: () {})]),
        scroll: false,
      );
      await settle(tester, 14);
      return opened;
    }

    NotificationsDrawer drawn(WidgetTester tester) => tester.widget<NotificationsDrawer>(find.byType(NotificationsDrawer));

    testWidgets('takes the feed as it opens, lists its rows, and marks all read on the service', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      device.service.notifies(kind: 'member-joined', from: 'sam', org: (id: id, name: 'Ghost'), body: {'name': 'Ghost'});
      device.service.notifies(kind: 'role-changed', from: 'sam', org: (id: id, name: 'Ghost'), body: {'name': 'Ghost', 'role': 'admin'});
      await drawer(tester, device);
      // Opened: a pass of the notifications brought both.
      expect(drawn(tester).notifications, hasLength(2));
      expect(drawn(tester).memberOf, {id});
      expect(unreadNotifications(device.services, preferences.value.notifications), 2);
      await tapKey(tester, 'mark-all-read');
      await settle(tester);
      expect(unreadNotifications(device.services, preferences.value.notifications), 0);
      await device.services.syncNotificationsNow();
      expect(device.service.feed.values.every((n) => n.readAt != null), isTrue);
      await endSettings(tester);
    });

    testWidgets('clears every row, here at once and on the service by the next pass', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      device.service.notifies(kind: 'member-joined', from: 'sam', org: (id: id, name: 'Ghost'), body: {'name': 'Ghost'});
      await drawer(tester, device);
      expect(drawn(tester).notifications, hasLength(1));
      await tapKey(tester, 'clear-all');
      await settle(tester);
      expect(drawn(tester).notifications, isEmpty);
      await device.services.syncNotificationsNow();
      expect(device.service.feed.values.every((n) => n.hidden), isTrue);
      await endSettings(tester);
    });

    testWidgets('answers an invitation inline: accepted on the service, its workspace here', (tester) async {
      final device = await Device.make();
      final id = device.service.invited('Boo', 'sam');
      await drawer(tester, device);
      expect(drawn(tester).notifications.single.kind, 'invite');
      expect(isPendingInvite(drawn(tester).notifications.single), isTrue);
      await tester.tap(find.text('Accept'));
      await settle(tester, 14);
      expect(device.service.rowIn(id), (role: 'member', state: 'member'));
      expect(drawn(tester).notifications.single.state, 'accepted');
      expect([for (final w in device.workspaces.value.list) w.id], ['org-$id']);
      await endSettings(tester);
    });

    testWidgets('signed out, or with no services, is the drawer that says so', (tester) async {
      final device = await Device.make(signedIn: false);
      await drawer(tester, device);
      expect(drawn(tester).signedIn, isFalse);
      expect(drawn(tester).notifications, isEmpty);
      await endSettings(tester);
    });
  });

  group('the home page’s organizations and news, from the account', () {
    testWidgets('are the ones joined, never one only invited to, and none signed out', (tester) async {
      final device = await Device.make();
      expect(homeOrganizations(null), isEmpty);
      expect(homeOrganizations(device.services), isEmpty);
      final id = await ghost(device);
      await sam(device, id, joined: true);
      device.service.invited('Boo', 'sam');
      await device.services.syncNow();
      final orgs = homeOrganizations(device.services, here: {id: const [OrgPresence(client: '1', handle: 'sam')]});
      expect([for (final org in orgs) (org.id, org.name, org.hue, org.members, org.here.length)], [(id, 'Ghost', 'sea', 2, 1)]);
      await device.services.signOut();
      expect(homeOrganizations(device.services), isEmpty);
    });

    testWidgets('and an organization’s news is its own rows as sentences, newest first, in their kinds’ colours', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      device.service.notifies(kind: 'member-joined', from: 'sam', org: (id: id, name: 'Ghost'), body: {'name': 'Ghost'}, at: 1000);
      device.service.notifies(kind: 'member-left', from: 'lee', org: (id: id, name: 'Ghost'), body: {'name': 'Ghost'}, at: 2000);
      device.service.notifies(kind: 'member-joined', from: 'lee', org: (id: 'elsewhere', name: 'Elsewhere'), body: {'name': 'Elsewhere'}, at: 3000);
      device.service.notifies(kind: 'invite', from: 'sam', org: (id: id, name: 'Ghost'), body: {'name': 'Ghost'}, state: 'pending', at: 4000);
      await device.services.syncNow();
      final news = homeOrgNews(device.services, id);
      expect([for (final n in news) n.words], ['lee left Ghost', 'sam joined Ghost']);
      expect([for (final n in news) n.hue], [kindHues['member-left'], kindHues['member-joined']]);
      expect(homeOrgNews(device.services, null), isEmpty);
      expect(homeOrgNews(null, id), isEmpty);
    });
  });
}
