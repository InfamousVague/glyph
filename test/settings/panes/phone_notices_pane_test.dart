// Settings › Notifications › On this phone (lib/settings/panes/notifications_pane.dart; the page's
// `NotificationsPane.tsx`, lines 90-108): drawn only where the phone can raise the bell's rows as its own
// notifications, with the page's words, the switch that is this phone's alone, and Allow while Android is keeping
// them from showing, read again every second until it is not. Against a stand-in for the phone
// (test/support/fake_phone.dart) and the real module behind the rows (lib/sync/phone.dart).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/core/phone_notices.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/notifications_pane.dart';
import 'package:ghost_md/settings/panes/pane_parts.dart';
import 'package:ghost_md/settings/panes/settings_host.dart';
import 'package:ghost_md/sync/feed.dart';
import 'package:ghost_md/sync/phone.dart';
import 'package:glacier/glacier.dart';

import '../../account_ui/support.dart' show Device;
import '../../feed/signed.dart' show SignedAccount;
import '../../support/fake_crypto.dart';
import '../../support/fake_phone.dart';
import '../support.dart';

List<String> titles(WidgetTester tester) => [for (final section in tester.widgetList<PaneSection>(find.byType(PaneSection, skipOffstage: false))) section.title ?? ''];

String? hintOf(WidgetTester tester, String label) {
  final hint = tester.widget<SettingRow>(find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false)).hint;
  return hint is Text ? hint.data : null;
}

const _on = 'Team news, invitations and Claude’s changes, as the switches above say. Meetings have their own, under Recording.';
const _blocked = 'It’s on, but Android is not showing notifications from Ghost.md. Allow them below, or in the app’s system settings.';
const _footer = 'Within about fifteen minutes while Ghost.md is closed, and as they arrive while it runs in the background. Not while it is open in front of you: the bell has them.';

void main() {
  setUpAll(loadAppFonts);

  late FakePhone phone;
  late MemoryStored kept;
  late SignedAccount account;
  late NotificationFeed feed;
  late PhoneNotices notices;

  setUp(() {
    phone = FakePhone();
    kept = MemoryStored();
    account = SignedAccount(session: const Session(token: 'tok', handle: 'matt', accountId: 7));
    feed = NotificationFeed(account: account, crypto: FakeCrypto(), kept: kept);
    notices = PhoneNotices(host: phone, account: account, feed: feed, prefs: preferences, base: 'http://service.test/api', kept: kept, hidden: () => false);
    addTearDown(() {
      notices.dispose();
      feed.dispose();
    });
  });

  Future<void> open(WidgetTester tester, {PhoneNotices? given}) async {
    await pumpSettings(tester, SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: NotificationsPane(signedIn: true, phone: given ?? notices))));
  }

  Finder theSwitch() => find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'Phone notifications', skipOffstage: false);

  testWidgets('is not drawn where nothing can raise them: no account service, or a phone with no half', (tester) async {
    // A build with no account service makes no notices at all.
    await pumpSettings(tester, const SingleChildScrollView(child: Padding(padding: EdgeInsets.all(16), child: NotificationsPane(signedIn: true))));
    expect(titles(tester), ['What reaches you', 'Ticket digest']);
    await endSettings(tester);
    // A desktop, an iPhone, an Android build from before them: the phone answers nothing.
    phone.there = false;
    await open(tester);
    expect(titles(tester), ['What reaches you', 'Ticket digest']);
    expect(find.text('Allow notifications'), findsNothing);
    await endSettings(tester);
  });

  testWidgets('is drawn once the phone has answered, in the page’s words, after the switches and before the footnote', (tester) async {
    await open(tester);
    expect(titles(tester), ['What reaches you', 'Ticket digest', 'On this phone']);
    expect(hintOf(tester, 'Phone notifications'), _on);
    expect(find.text(_footer, skipOffstage: false), findsOneWidget);
    expect(tester.widget<GlacierSwitch>(theSwitch()).checked, isTrue, reason: 'on unless it was turned off');
    expect(find.text('Allow notifications', skipOffstage: false), findsNothing);
    expect(find.text('Ghost.md looks when it opens; the bell shows what arrived.', skipOffstage: false), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('its switch is this phone’s own: off takes the watch back, on hands it again', (tester) async {
    await open(tester);
    await tester.ensureVisible(theSwitch());
    await tester.tap(theSwitch());
    await settleSettings(tester);
    expect(kept.readText(phoneNoticesKey), 'off');
    expect(phone.watches.last, '');
    expect(tester.widget<GlacierSwitch>(theSwitch()).checked, isFalse);
    // Not a synced preference: the four above are, this is not.
    final synced = preferences.value.notifications;
    expect((synced.team, synced.claude, synced.summaries, synced.conflicts, synced.mutedOrgs), (true, true, true, true, const <String>[]));
    await tester.tap(theSwitch());
    await settleSettings(tester);
    expect(kept.readText(phoneNoticesKey), isNull);
    expect(phone.watches.last, isNot(''));
    expect(tester.widget<GlacierSwitch>(theSwitch()).checked, isTrue);
    await endSettings(tester);
  });

  testWidgets('says when Android is keeping them from showing, offers Allow, and takes the answer within a second', (tester) async {
    phone.current = NoticesState.blocked;
    await open(tester);
    expect(hintOf(tester, 'Phone notifications'), _blocked);
    final allow = find.text('Allow notifications', skipOffstage: false);
    expect(allow, findsOneWidget);
    expect(find.ancestor(of: allow, matching: find.byType(PaneActions, skipOffstage: false)), findsOneWidget);
    await tester.ensureVisible(allow);
    await tester.tap(allow);
    await tester.pump();
    expect(phone.allows, 1, reason: 'the phone itself is asked for its prompt');
    // Still refused: still said, however long the prompt is up.
    await tester.pump(const Duration(seconds: 3));
    expect(hintOf(tester, 'Phone notifications'), _blocked);
    // Android's prompt answered yes: nobody tells the page, it looks again.
    phone.current = NoticesState.on;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(hintOf(tester, 'Phone notifications'), _on);
    expect(find.text('Allow notifications', skipOffstage: false), findsNothing);
    // And stops looking once they show: nothing more is asked of the phone.
    final asks = phone.asked;
    await tester.pump(const Duration(seconds: 5));
    expect(phone.asked, asks);
    await endSettings(tester);
  });

  // docs/PARITY.md, "Regressions found on 2026-10-11", found beside, 3. Allow was the meeting screen's asking,
  // handed to Settings by voice (`SettingsFeatures.onAllowMeetingNotices`): until voice was made, and for good on a
  // phone with no meeting service, the row was drawn and could not be pressed. The page asks the phone itself
  // (NotificationsPane.tsx `requestNotifications()`), and so does this: the notices' own channel, as soon as the
  // app is up.
  testWidgets('Allow can be pressed wherever it is drawn: in Settings with no voice and no meeting service, the phone is asked', (tester) async {
    phone.current = NoticesState.blocked;
    // An account as the app has one (signed out here: the row is this phone's, whoever is in), with its notices.
    final device = (await tester.runAsync(() => Device.make(signedIn: false, engine: false, shares: false)))!;
    final services = AccountServices(account: device.account, phoneNotices: notices, prefs: preferences, kept: kept);
    // Settings as the root hands it before voice is made: nothing of a meeting, nothing to ask a meeting's host with.
    await pumpSettings(
      tester,
      AccountScope(
        services: services,
        child: SettingsHost(
          features: const SettingsFeatures(),
          go: (_, {setting}) {},
          workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage()),
          child: Builder(builder: (context) => SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: NotificationsPane.hosted(context)))),
        ),
      ),
    );
    final allow = find.text('Allow notifications', skipOffstage: false);
    expect(allow, findsOneWidget);
    expect(tester.widget<RowAction>(find.ancestor(of: allow, matching: find.byType(RowAction, skipOffstage: false))).disabled, isFalse);
    await tester.ensureVisible(allow);
    await tester.tap(allow);
    await tester.pump();
    expect(phone.allows, 1);
    await endSettings(tester);
  });

  testWidgets('Allow where no prompt can change it (refused twice, or off in the phone’s settings) asks, and the page goes on saying so', (tester) async {
    phone
      ..current = NoticesState.blocked
      ..prompts = false;
    await open(tester);
    final allow = find.text('Allow notifications', skipOffstage: false);
    await tester.ensureVisible(allow);
    await tester.tap(allow);
    await tester.pump();
    expect(phone.allows, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(hintOf(tester, 'Phone notifications'), _blocked);
    expect(allow, findsOneWidget);
    await endSettings(tester);
  });
}
