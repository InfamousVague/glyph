// The way into an account as the first screen. Ports of what `src/app/shell/useAccountGate.ts` decides and what
// `src/app/shell/AccountGate.tsx` and `SignInFlow` (settings/AccountPane.tsx) draw; the web has no test file of
// either on its own, so these are this port's, against the real account over the service in memory.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/account_pane.dart';
import 'package:ghost_md/shell/account_gate.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

Future<int Function()> gate(WidgetTester tester, Device device, {Size size = phone}) async {
  var done = 0;
  await device.pump(tester, AccountGate(services: device.services, onDone: () => done += 1), size: size, scroll: false);
  await settle(tester);
  return () => done;
}

/// A device's memory that will not answer.
class Refusing extends MemoryStored {
  @override
  String? getItem(String key) => throw StateError('no storage');
}

void main() {
  setUpAll(loadAppFonts);

  group('whether the gate comes up', () {
    testWidgets('on an open that is signed out, once: closing it marks it seen', (tester) async {
      final device = await Device.make(signedIn: false);
      final first = AccountGateState(services: device.services);
      expect(first.open, isTrue);
      var told = 0;
      first.addListener(() => told += 1);
      first.close();
      expect(first.open, isFalse);
      expect(told, 1);
      expect(device.kept.getItem(accountGateSeenKey), '1');
      expect(AccountGateState(services: device.services).open, isFalse);
    });

    testWidgets('not for someone signed in, nor under Local only, nor an open by the side key, nor with no account to sign in to', (tester) async {
      final signedIn = await Device.make();
      expect(AccountGateState(services: signedIn.services).open, isFalse);
      final out = await Device.make(signedIn: false);
      expect(AccountGateState(services: out.services, launchedByKey: true).open, isFalse);
      preferences.update((now) => now.copyWith(localOnly: true));
      expect(AccountGateState(services: out.services).open, isFalse);
      preferences.update((now) => now.copyWith(localOnly: false));
      expect(AccountGateState(services: out.services).open, isTrue);
      expect(AccountGateState(services: null).open, isFalse);
      // No storage: asking on every open would be worse than never asking.
      expect(AccountGateState(services: out.services, kept: Refusing()).open, isFalse);
    });
  });

  group('the gate', () {
    testWidgets('is one card that asks to sign in or sign up, with the way on without an account under it', (tester) async {
      final device = await Device.make(signedIn: false);
      final done = await gate(tester, device);
      expect(find.text('Sign in to Ghost.md'), findsOneWidget);
      expect(find.text('Your notes, the same on every device, encrypted before they leave this one.'), findsOneWidget);
      expect(tester.widget<GlacierSegmentedControl>(find.byType(GlacierSegmentedControl)).value, 'in');
      expect(find.text('Lost the password?'), findsOneWidget);
      // No graphic on it (Matt: "remove the graphic on the sign in page").
      expect(find.byType(PaneSection), findsNothing);
      await press(tester, 'Use without an account');
      expect(done(), 1);
      await endSettings(tester);
    });

    testWidgets('signing in closes it at once', (tester) async {
      final device = await Device.make(signedIn: false);
      final done = await gate(tester, device);
      await typeInto(tester, 'Handle', seeded.handle);
      await typeInto(tester, 'Password', seeded.password);
      await tapKey(tester, 'account-submit');
      await settle(tester, 12);
      expect(device.services.signedIn, isTrue);
      expect(done(), 1);
      await endSettings(tester);
    });

    testWidgets('signing up shows the recovery codes first, and closes only once they are put away', (tester) async {
      final service = await FakeService.start();
      final device = await Device.make(service: service, signedIn: false);
      final done = await gate(tester, device);
      tester.widget<GlacierSegmentedControl>(find.byType(GlacierSegmentedControl)).onValueChange!('up');
      await tester.pump();
      expect(find.text('Create an account'), findsOneWidget);
      await typeInto(tester, 'Handle', 'newbie');
      await typeInto(tester, 'Password', 'long enough');
      await tapKey(tester, 'account-submit');
      await settle(tester, 12);
      expect(service.hasAccount(), isTrue);
      expect(done(), 0);
      expect(titlesOf(tester), ['Recovery codes']);
      await press(tester, "I've kept them");
      expect(done(), 1);
      await endSettings(tester);
    });

    testWidgets('a lost password turns the card to recovery, and back', (tester) async {
      final device = await Device.make(signedIn: false);
      await gate(tester, device);
      await tapKey(tester, 'sign-in-other');
      expect(find.text('Recover an account'), findsOneWidget);
      expect(find.text('A recovery code and a new password open it again.'), findsOneWidget);
      expect(find.byType(GlacierSegmentedControl), findsNothing);
      expect(find.byWidgetPredicate((w) => w is GlacierInput && w.ariaLabel == 'Recovery code'), findsOneWidget);
      expect(find.text('Back to sign in'), findsOneWidget);
      await tapKey(tester, 'sign-in-other');
      expect(find.text('Sign in to Ghost.md'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('says what went wrong under the fields, in the service’s words', (tester) async {
      final device = await Device.make(signedIn: false);
      final done = await gate(tester, device);
      await typeInto(tester, 'Handle', seeded.handle);
      await typeInto(tester, 'Password', 'not the one');
      await tapKey(tester, 'account-submit');
      await settle(tester, 12);
      expect(device.services.signedIn, isFalse);
      expect(done(), 0);
      expect(find.byType(SignInFlow), findsOneWidget);
      expect(tester.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('sign-in-card')), matching: find.byType(Text))).map((t) => t.data), contains(isNotNull));
      await endSettings(tester);
    });

    testWidgets('is a card’s width in the middle of a wide window', (tester) async {
      final device = await Device.make(signedIn: false);
      await gate(tester, device, size: wideWindow);
      final card = tester.getRect(find.byKey(const ValueKey('sign-in-card')));
      expect(card.center.dx, closeTo(640, 0.5));
      expect(card.width, lessThanOrEqualTo(26 * 16));
      await endSettings(tester);
    });
  });
}
