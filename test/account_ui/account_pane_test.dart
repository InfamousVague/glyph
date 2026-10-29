// Settings › Account against the real account over the service in memory. A port of
// `src/app/settings/AccountPane.test.tsx`, case for case, where the page's own modules are the objects of
// test/account_ui/support.dart; then this port's own: the three ways in run for real, the recovery codes shown once,
// the password changed, signing out, and that with no services the page is what it was before there was an account.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/notes/workspace_swatch.dart';
import 'package:ghost_md/settings/account_forms.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/account_pane.dart';
import 'package:ghost_md/settings/panes/recording_pane.dart' show recordingFindable;
import 'package:ghost_md/settings/panes/settings_host.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// Where each of [things] first shows down the page, in order.
List<double> placesOf(WidgetTester tester, List<String> things) => [for (final thing in things) tester.getTopLeft(find.text(thing).first).dy];

/// The checked dot of the colour swatch, by its name.
String? chosenHue(WidgetTester tester) => tester.widget<WorkspaceSwatch>(find.byType(WorkspaceSwatch)).hue;

void main() {
  setUpAll(loadAppFonts);

  group('Delete account', () {
    testWidgets('says what goes, asks for the password, and lands signed out with the notes kept', (tester) async {
      final device = await Device.make();
      device.keep('n1', '# Kept\nwords');
      await device.pump(tester, AccountPane(services: device.services));
      await press(tester, 'Delete account');
      expect(find.textContaining("every link you've shared"), findsOneWidget);
      expect(find.textContaining('The notes on this device stay here.'), findsOneWidget);
      expect(pressableOf(tester, 'Delete my account').onPressed, isNull);
      await typeInto(tester, 'Password', 'wrong');
      await press(tester, 'Delete my account');
      // The service's own words for a wrong password.
      expect(find.text('That is not the password.'), findsOneWidget);
      expect(device.services.signedIn, isTrue);
      expect(device.service.hasAccount(), isTrue);
      await typeInto(tester, 'Password', seeded.password);
      await press(tester, 'Delete my account');
      expect(device.service.hasAccount(), isFalse);
      expect(device.services.signedIn, isFalse);
      expect(find.text('Your account is deleted. The notes on this device are still here.'), findsOneWidget);
      expect(device.notes.held.keys, ['n1']);
      await endSettings(tester);
    });
  });

  group('Signed out', () {
    testWidgets('opens on the ghost and the way in, then Privacy and Location', (tester) async {
      final device = await Device.make(signedIn: false);
      await device.pump(tester, AccountPane(services: device.services));
      expect(titlesOf(tester), ['Sign in', 'Privacy', 'Location']);
      final ghost = find.byWidgetPredicate((widget) => widget is Ghost && widget.scene == GhostScene.signedOut);
      expect(ghost, findsOneWidget);
      expect(tester.getTopLeft(ghost).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('account-submit'))).dy));
      final places = placesOf(tester, ['SIGN IN', 'Create an account', "Your password never leaves this device, and nobody can reset it for you. Without it or a recovery code, the notes in an account can't be opened by anyone. Notes on this device stay here either way.", 'PRIVACY', 'LOCATION']);
      expect([...places]..sort(), places);
      await endSettings(tester);
    });

    testWidgets('says Local only holds the sync off, and the words go to its card on this page', (tester) async {
      final device = await Device.make(signedIn: false);
      preferences.update((now) => now.copyWith(localOnly: true));
      var opened = 0;
      await device.pump(tester, AccountPane(services: device.services, onOpenPrivacy: () => opened += 1));
      expect(find.byType(SettingsCallout), findsOneWidget);
      expect(find.textContaining(' is on, so nothing syncs until it is off.', findRichText: true), findsOneWidget);
      expect(tester.widget<GlacierSwitch>(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'Local only')).checked, isTrue);
      await tester.tap(find.descendant(of: find.byType(SettingsCallout), matching: find.byType(GoWord)));
      expect(opened, 1);
      await endSettings(tester);
    });
  });

  group('Signed in', () {
    testWidgets('has Sync, then Your colour, Privacy and Location, then Delete account', (tester) async {
      final device = await Device.make();
      await device.pump(tester, AccountPane(services: device.services));
      expect(titlesOf(tester), ['Sync', 'Your colour', 'Privacy', 'Location']);
      final places = placesOf(tester, ['Sync now', 'Local only', 'Map on a tagged note', 'Delete account']);
      expect([...places]..sort(), places);
      await endSettings(tester);
    });

    testWidgets('picks your colour from the seven, ink being none, and sends it to the service', (tester) async {
      final device = await Device.make();
      await device.orgs.setAccountColour('sea');
      await device.pump(tester, AccountPane(services: device.services));
      expect(chosenHue(tester), 'sea');
      await tester.ensureVisible(find.bySemanticsLabel('Rose'));
      await tester.tap(find.bySemanticsLabel('Rose'));
      await settle(tester);
      expect((await device.orgs.listOrgs()).colour, 'rose');
      expect(chosenHue(tester), 'rose');
      await tester.tap(find.bySemanticsLabel('Ink'));
      await settle(tester);
      expect((await device.orgs.listOrgs()).colour, isNull);
      expect(chosenHue(tester), 'ink');
      await endSettings(tester);
    });

    testWidgets('has no Organizations row', (tester) async {
      final device = await Device.make();
      await device.pump(tester, AccountPane(services: device.services));
      expect(find.text('Organizations'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('says Local only holds the sync off, and the words go to its card', (tester) async {
      final device = await Device.make();
      preferences.update((now) => now.copyWith(localOnly: true));
      var opened = 0;
      await device.pump(tester, AccountPane(services: device.services, onOpenPrivacy: () => opened += 1));
      expect(find.textContaining(' is on, so nothing syncs until it is off.', findRichText: true), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(SettingsCallout), matching: find.byType(GoWord)));
      expect(opened, 1);
      await endSettings(tester);
    });

    testWidgets('keeps the words Local only as a plain word while a form has the Privacy card off the page', (tester) async {
      final device = await Device.make();
      preferences.update((now) => now.copyWith(localOnly: true));
      var opened = 0;
      await device.pump(tester, AccountPane(services: device.services, onOpenPrivacy: () => opened += 1));
      GoWord word() => tester.widget<GoWord>(find.descendant(of: find.byType(SettingsCallout), matching: find.byType(GoWord)));
      for (final form in ['Delete account', 'Password and recovery codes']) {
        await press(tester, form);
        expect(titlesOf(tester), isNot(contains('Privacy')));
        expect(find.textContaining(' is on, so nothing syncs until it is off.', findRichText: true), findsOneWidget);
        expect(word().onPress, isNull);
        await press(tester, 'Cancel');
        expect(word().onPress, isNotNull);
      }
      await endSettings(tester);
    });
  });

  group('Sync', () {
    testWidgets('has no meeting recordings: their switch and their count are on Meetings (meet_card_test.dart)', (tester) async {
      final device = await Device.make();
      Note taped(String id, String body, int ms) => device.notes.held[id] = Note(id: id, body: body, createdAt: 0, updatedAt: 0, source: NoteSource.capture, recordingMs: ms, segments: const []);
      taped('m', '# Meeting, 26 Sep 14:05', 60000);
      preferences.update((now) => now.copyWith(meetings: const {'m': 1}, syncMeetingRecordings: false, syncMeetingRecordingsChosen: true));
      await device.pump(tester, AccountPane(services: device.services));
      await settle(tester);
      final switches = tester.widgetList<GlacierSwitch>(find.byType(GlacierSwitch)).map((w) => w.ariaLabel).toList();
      expect(switches, isNot(contains('Sync meeting recordings')));
      expect(switches, contains('Live typing'));
      expect(find.textContaining("A meeting is other people's voices"), findsNothing);
      expect(find.textContaining('stayed on this phone'), findsNothing);
      expect(find.text('Notes, their recordings and pictures, and your settings. The model you downloaded and Developer settings stay on each device.'), findsOneWidget);
      expect(accountFindable(signedIn: true, ported: true).map((found) => found.name), isNot(contains('Sync meeting recordings')));
      await endSettings(tester);
    });

    testWidgets('on an iPhone, which records nothing, has no such switch and says nothing of recordings or a model', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final device = await Device.make();
      await device.pump(tester, AccountPane(services: device.services));
      final switches = tester.widgetList<GlacierSwitch>(find.byType(GlacierSwitch)).map((w) => w.ariaLabel).toList();
      final footer = find.text('Notes, their pictures, and your settings. Developer settings stay on each device.').evaluate().length;
      final spoken = find.textContaining('The model you downloaded').evaluate().length;
      final listed = accountFindable(signedIn: true, ported: true).map((found) => found.name).toList();
      final onRecording = recordingFindable(android: false, signedIn: true).map((found) => found.name).toList();
      debugDefaultTargetPlatformOverride = null;
      expect(switches, isNot(contains('Sync meeting recordings')));
      expect(switches, contains('Live typing'));
      expect(footer, 1);
      expect(spoken, 0);
      expect(listed, isNot(contains('Sync meeting recordings')));
      expect(listed, contains('Sync now'));
      // Settings › Recording's Meetings card, where the switch is now (22ffc160), lists it only where the device records.
      expect(onRecording, isNot(contains('Sync meeting recordings')));
      expect(recordingFindable(android: true, signedIn: true).map((found) => found.name), contains('Sync meeting recordings'));
      await endSettings(tester);
    });

    testWidgets('says how many notes the last sync could not send, and why', (tester) async {
      // A real pass whose two notes the service would not take: the engine's own status, not a stand-in.
      final service = await FakeService.start(seed: seeded);
      final device = await Device.make(
        service: service,
        fetcher: (request) async =>
            request.method == 'PUT' && request.url.path.contains('/notes/') ? FetchResponse.json(500, {'error': 'The sync service could not be reached.'}) : service.fetcher(request),
      );
      device.keep('a', '# One', at: 1);
      device.keep('b', '# Two', at: 2);
      await device.pump(tester, AccountPane(services: device.services));
      await press(tester, 'Sync now');
      await settle(tester, 12);
      expect(device.services.status.unsent, 2);
      expect(find.text('2 notes not synced. The sync service could not be reached.'), findsOneWidget);
      expect(syncSummary('matt', device.services.status), 'matt · 2 notes not synced');
      await endSettings(tester);
    });
  });

  // --- this port's own -----------------------------------------------------------------------------------------------

  group('The ways in, for real', () {
    testWidgets('signing in with the password lands on the account’s page, synced', (tester) async {
      final device = await Device.make(signedIn: false);
      await device.pump(tester, AccountPane(services: device.services));
      expect(pressableOf(tester, 'Sign in').onPressed, isNull);
      await typeInto(tester, 'Handle', seeded.handle);
      await typeInto(tester, 'Password', 'not it');
      await tapKey(tester, 'account-submit');
      await settle(tester);
      expect(device.services.signedIn, isFalse);
      expect(find.byType(FormProblem), findsOneWidget);
      await typeInto(tester, 'Password', seeded.password);
      await tapKey(tester, 'account-submit');
      await settle(tester, 12);
      expect(device.services.signedIn, isTrue);
      expect(find.text('matt'), findsOneWidget);
      expect(find.text('End-to-end encrypted'), findsOneWidget);
      expect(titlesOf(tester).first, 'Sync');
      // The sync the way in asked for ran against the fake service, and the hero says so.
      expect(device.services.status.phase, 'idle');
      expect(find.text('Synced just now'), findsOneWidget);
      expect(device.service.calls.any((call) => call.contains('notes')), isTrue);
      await endSettings(tester);
    });

    testWidgets('a bad handle is said before any round trip', (tester) async {
      final device = await Device.make(signedIn: false);
      await device.pump(tester, AccountPane(services: device.services));
      final before = device.service.calls.length;
      await typeInto(tester, 'Handle', 'a');
      await typeInto(tester, 'Password', 'whatever');
      await tapKey(tester, 'account-submit');
      await settle(tester);
      expect(find.text('A handle is 3 to 24 letters, digits, . _ or -, starting with a letter or digit.'), findsOneWidget);
      expect(device.service.calls.length, before);
      await endSettings(tester);
    });

    testWidgets('signing up shows the recovery sheet once, eight codes to copy, and then the account', (tester) async {
      final service = await FakeService.start();
      final device = await Device.make(service: service, signedIn: false);
      final copied = Clipped(tester);
      await device.pump(tester, AccountPane(services: device.services));
      await press(tester, 'Create an account');
      expect(titlesOf(tester).first, 'New account');
      await typeInto(tester, 'Handle', 'newbie');
      await typeInto(tester, 'Password', 'short');
      await tapKey(tester, 'account-submit');
      await settle(tester);
      expect(find.text('A password is at least 8 characters.'), findsOneWidget);
      await typeInto(tester, 'Password', 'long enough');
      await tapKey(tester, 'account-submit');
      await settle(tester, 12);
      expect(service.hasAccount(), isTrue);
      expect(titlesOf(tester), ['Recovery codes']);
      final codes = [for (final text in tester.widgetList<Text>(find.byType(Text))) if (RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$').hasMatch(text.data ?? '')) text.data!];
      expect(codes, hasLength(8));
      expect(service.codesLeft(), 8);
      await press(tester, 'Copy all');
      expect(copied.text, codes.join('\n'));
      await press(tester, "I've kept them");
      expect(titlesOf(tester).first, 'Sync');
      expect(find.text('newbie'), findsOneWidget);
      // Shown this once and never again: nothing on the page holds a code now.
      expect(find.text(codes.first), findsNothing);
      await endSettings(tester);
    });

    testWidgets('a recovery code and a new password open the account, with a fresh sheet', (tester) async {
      final service = await FakeService.start();
      final first = await Device.make(service: service, signedIn: false);
      final made = await first.account.signUp('robin', 'first password');
      final device = await Device.make(service: service, signedIn: false);
      await device.pump(tester, AccountPane(services: device.services));
      await press(tester, 'Lost the password');
      expect(titlesOf(tester).first, 'Recover');
      await typeInto(tester, 'Handle', 'robin');
      expect(pressableOf(tester, 'Recover and set password').onPressed, isNull);
      await typeInto(tester, 'Recovery code', made.codes.first);
      await typeInto(tester, 'New password', 'second password');
      await tapKey(tester, 'account-submit');
      await settle(tester, 12);
      expect(titlesOf(tester), ['Recovery codes']);
      expect(device.services.signedIn, isTrue);
      // The new password is the account's now.
      final third = await Device.make(service: service, signedIn: false);
      await third.account.signIn('robin', 'second password');
      expect(third.services.signedIn, isTrue);
      await expectLater(Device.make(service: service, signedIn: false).then((d) => d.account.signIn('robin', 'first password')), throwsA(isA<ApiError>()));
      await endSettings(tester);
    });
  });

  group('Password and recovery codes', () {
    testWidgets('changes the password with the current one, and says when that is not it', (tester) async {
      final device = await Device.make();
      await device.pump(tester, AccountPane(services: device.services));
      await press(tester, 'Password and recovery codes');
      expect(titlesOf(tester), ['Change password']);
      expect(pressableOf(tester, 'Change password').onPressed, isNull);
      await typeInto(tester, 'Current password', 'nope nope');
      await typeInto(tester, 'New password', 'another one');
      await press(tester, 'Change password');
      expect(find.text('That is not the password.'), findsOneWidget);
      await typeInto(tester, 'Current password', seeded.password);
      await press(tester, 'Change password');
      expect(titlesOf(tester).first, 'Sync');
      final other = await Device.make(service: device.service, signedIn: false);
      await other.account.signIn(seeded.handle, 'another one');
      expect(other.services.signedIn, isTrue);
      await endSettings(tester);
    });

    testWidgets('makes a new sheet of recovery codes instead, shown once', (tester) async {
      final device = await Device.make();
      await device.pump(tester, AccountPane(services: device.services));
      await press(tester, 'Password and recovery codes');
      await press(tester, 'Make new recovery codes instead');
      expect(titlesOf(tester), ['New recovery codes']);
      expect(find.byWidgetPredicate((w) => w is GlacierInput && w.ariaLabel == 'New password'), findsNothing);
      await typeInto(tester, 'Current password', seeded.password);
      await press(tester, 'Make new codes');
      expect(titlesOf(tester), ['Recovery codes']);
      expect(device.service.codesLeft(), 8);
      await press(tester, "I've kept them");
      expect(titlesOf(tester).first, 'Sync');
      await endSettings(tester);
    });
  });

  group('Sync now and Sign out', () {
    testWidgets('Sync now runs a pass against the service, and the hero says when', (tester) async {
      final device = await Device.make();
      await device.pump(tester, AccountPane(services: device.services));
      expect(find.text('Waiting to sync'), findsOneWidget);
      final before = device.service.calls.length;
      await press(tester, 'Sync now');
      await settle(tester, 12);
      expect(device.service.calls.length, greaterThan(before));
      expect(find.text('Synced just now'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('Local only holds Sync now off: nothing is asked of the service', (tester) async {
      final device = await Device.make();
      preferences.update((now) => now.copyWith(localOnly: true));
      await device.pump(tester, AccountPane(services: device.services));
      final before = device.service.calls.length;
      await press(tester, 'Sync now');
      await settle(tester, 12);
      expect(device.service.calls.length, before);
      await endSettings(tester);
    });

    testWidgets('Sign out leaves the notes and lands on the ways in', (tester) async {
      final device = await Device.make();
      device.keep('n1', '# Mine');
      await device.pump(tester, AccountPane(services: device.services));
      await press(tester, 'Sign out');
      await settle(tester, 12);
      expect(device.services.signedIn, isFalse);
      expect(await device.keys.accountKey(), isNull);
      expect(titlesOf(tester), ['Sign in', 'Privacy', 'Location']);
      expect(device.notes.held.keys, ['n1']);
      await endSettings(tester);
    });
  });

  group('Without services', () {
    testWidgets('the page is what it was before there was an account', (tester) async {
      await pumpSettings(tester, const SingleChildScrollView(child: AccountPane()));
      expect(titlesOf(tester), ['Sign in', 'Privacy', 'Location']);
      expect(pressableOf(tester, 'Sign in').onPressed, isNull);
      await endSettings(tester);
      await pumpSettings(tester, const SingleChildScrollView(child: AccountPane(features: SettingsFeatures(signedIn: true))));
      expect(find.byType(SettingsNotPortedCard), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('the row reads the account’s line with one, and "Not signed in" without', (tester) async {
      final device = await Device.make();
      expect(accountSummary(const Preferences()), 'Not signed in');
      expect(accountSummary(const Preferences(localOnly: true)), 'Not signed in · Local only');
      expect(accountSummary(const Preferences(), device.services), 'matt');
      await device.services.syncNow();
      expect(accountSummary(const Preferences(localOnly: true), device.services), 'matt · synced just now · Local only');
      await device.services.signOut();
      expect(accountSummary(const Preferences(), device.services), 'Not signed in');
    });
  });
}
