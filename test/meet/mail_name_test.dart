// A mail address of one's own name, on Settings › Meetings' invite card (lib/meet/ui/meet_card.dart,
// lib/mail/mail_name.dart; Matt, 2026-10-24: "i'd like you to add the ability to create our own custom name for the
// email if the name is available like matt@in.ghostmarkdown.com"): the rules checked before the service is asked,
// "Available", "Taken" or the reason in words once a pause in typing is 400 ms, an answer to a name typed over
// dropped, the question with the refresh's warning before switching, the new address in the old one's place, a
// refusal said under the field, an older service with no names, and Simple.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/mail/mail_name.dart';
import 'package:ghost_md/meet/ui/meet_card.dart';
import 'package:ghost_md/settings/panes/meetings_pane.dart';

import '../account_ui/support.dart';
import 'support.dart';

const String field = 'A name of your own for the address';

/// A device with an address and Ghost in meetings; with [hold], each name asked about waits for the test to let it
/// through ([Held.release]).
Future<Device> made({Held? hold}) async {
  final meet = FakeMeet();
  final service = await FakeService.start(seed: seeded);
  final over = meet.over(service.fetcher);
  final device = await Device.make(
    service: service,
    publishing: true,
    meeting: true,
    fetcher: (request) async {
      if (hold != null && request.url.path.endsWith('/mail/address/available')) await hold.wait();
      return over(request);
    },
  );
  await device.mailIn!.newAddress();
  return device;
}

class Held {
  final List<Completer<void>> waiting = [];
  Future<void> wait() {
    final gate = Completer<void>();
    waiting.add(gate);
    return gate.future;
  }

  void release(int i) => waiting[i].complete();
}

/// How many times the service was asked about a name.
int asked(Device d) => d.service.calls.where((c) => c == 'POST mail/address/available').length;

/// What is said under the field.
String said(WidgetTester tester) => tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('meet-name-said')), matching: find.byType(Text))).data!;

/// Whether Use this name can be pressed.
bool usable(WidgetTester tester) => pressableOf(tester, 'Use this name').onPressed != null;

Future<void> opened(WidgetTester tester, Device d, {Size size = const Size(390, 1600), bool dark = false}) async {
  await d.pump(tester, MeetingsPane(services: d.services), size: size, dark: dark);
  await settle(tester, 10);
  await tapKey(tester, 'meet-name-open');
  await settle(tester);
}

/// [name] typed, and the pause after it.
Future<void> typed(WidgetTester tester, String name) async {
  await typeInto(tester, field, name);
  await tester.pump(meetNameSettle + const Duration(milliseconds: 20));
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  test('the rules, checked here before the service is asked, and the words for each answer', () {
    expect(mailNameNormal('  Matt.Smith '), 'matt.smith');
    for (final fit in ['matt', 'sam-lee', 'sam_lee', 'a.b-c_d', 'x2024', 'k7m2q3xh4t5vbn61', 'a' * 30]) {
      expect(mailNameUnfit(fit), isNull, reason: fit);
    }
    for (final (name, why) in [
      ('ma', MailNameUnfit.short),
      ('a' * 31, MailNameUnfit.long),
      ('matt smith', MailNameUnfit.characters),
      ('matt+tag', MailNameUnfit.characters),
      ('mätt', MailNameUnfit.characters),
      ('.matt', MailNameUnfit.separators),
      ('matt-', MailNameUnfit.separators),
      ('ma..tt', MailNameUnfit.separators),
      ('k7m2q3xh4t5vbn6p', MailNameUnfit.generated),
      ('postmaster', MailNameUnfit.reserved),
      ('no-reply', MailNameUnfit.reserved),
      ('ghost.md', MailNameUnfit.reserved),
    ]) {
      expect(mailNameUnfit(name), why, reason: name);
    }
    expect([MailNameUnfit.characters, MailNameUnfit.short, MailNameUnfit.reserved].map((u) => u.words), ['Only letters, numbers, dots, dashes and underscores', 'At least 3 characters', 'That name is reserved']);
    String words(bool available, [String? reason, String? message]) => MailNameCheck(name: 'x', available: available, reason: reason, message: message).words;
    expect(words(true), 'Available');
    expect(words(false, 'taken'), 'Taken');
    expect(words(false, 'yours'), 'That is your address already');
    expect(words(false, 'generated', 'ignored.'), 'That looks like a name Ghost.md makes up. Choose one of your own', reason: 'the made shape only the service knows the words of');
    expect(words(false, 'something-new', 'A reason from a newer service.'), 'A reason from a newer service', reason: 'its own words, for a reason this app does not know');
  });

  testWidgets('the field has the domain after it and says Available, Taken or what is wrong once a pause in typing is 400 ms', (tester) async {
    final d = await made();
    d.service.mailNamesTaken.add('sam');
    await opened(tester, d);
    expect(find.text('@in.ghostmarkdown.com'), findsOneWidget);
    expect(said(tester), 'Anyone who guesses a name can send mail to it. What arrives is still sealed to your account.');
    expect(usable(tester), isFalse);

    // What is wrong is said after the pause, and the service is not asked.
    await typeInto(tester, field, 'ma');
    await tester.pump(const Duration(milliseconds: 300));
    expect(said(tester), isNot('At least 3 characters'), reason: 'not before the pause');
    await tester.pump(const Duration(milliseconds: 150));
    expect(said(tester), 'At least 3 characters');
    await typed(tester, 'Matt Smith');
    expect(said(tester), 'Only letters, numbers, dots, dashes and underscores');
    await typed(tester, 'postmaster');
    expect(said(tester), 'That name is reserved');
    await typed(tester, 'matt..smith');
    expect(said(tester), 'A dot, dash or underscore goes between letters or numbers, one at a time');
    expect(asked(d), 0, reason: 'a name that breaks the rules is never asked about');

    // Typed a letter at a time, quicker than the pause: asked once, for the whole name.
    for (final so in ['m', 'ma', 'mat', 'Matt']) {
      await typeInto(tester, field, so);
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(asked(d), 0);
    await tester.pump(meetNameSettle);
    await settle(tester);
    expect(asked(d), 1);
    expect(said(tester), 'Available');
    expect(usable(tester), isTrue);

    await typed(tester, 'sam');
    expect(said(tester), 'Taken');
    expect(usable(tester), isFalse);
    await endSettings(tester);
  });

  testWidgets('an answer about a name since typed over is dropped', (tester) async {
    final hold = Held();
    final d = await made(hold: hold);
    d.service.mailNamesTaken.add('sam');
    await opened(tester, d);
    await typed(tester, 'sam');
    expect(said(tester), 'Checking…');
    await typed(tester, 'samuel');
    hold.release(1);
    await settle(tester);
    expect(said(tester), 'Available');
    hold.release(0);
    await settle(tester);
    expect(said(tester), 'Available', reason: 'sam’s Taken came last, and is about a name no longer in the field');
    await endSettings(tester);
  });

  testWidgets('Use this name asks first with the refresh’s warning, then the new address is drawn in the old one’s place', (tester) async {
    final d = await made();
    final first = d.service.mailAddress!;
    await opened(tester, d);
    await typed(tester, 'Matt.Smith');
    await tapKey(tester, 'meet-name-use');
    await settle(tester);
    expect(find.text('Switch to matt.smith@​in.ghostmarkdown.com?'), findsOneWidget);
    expect(find.text(meetNewAddressWarning), findsOneWidget);
    expect(find.text('Invites and mail sent to the old one are turned away from then on. A Calendar invite with it as a guest needs the new one.'), findsOneWidget);
    // Cancel goes back to the field, the name still in it.
    await press(tester, 'Cancel');
    expect(find.text('Switch to matt.smith@​in.ghostmarkdown.com?'), findsNothing);
    expect(usable(tester), isTrue);
    expect(d.service.mailAddress, first);

    await tapKey(tester, 'meet-name-use');
    await settle(tester);
    await press(tester, 'Switch');
    await settle(tester, 10);
    expect(d.service.mailAddress, 'matt.smith@in.ghostmarkdown.com');
    expect(d.service.calls, contains('PUT mail/address'));
    expect(find.text('matt.smith@​in.ghostmarkdown.com'), findsOneWidget);
    expect(find.text(first.replaceFirst('@', '@​')), findsNothing);
    expect(find.text('Your address is now matt.smith@in.ghostmarkdown.com. The old one takes no more invites or mail.'), findsOneWidget);
    expect(find.byKey(const ValueKey('meet-name')), findsNothing, reason: 'the field shut');
    await endSettings(tester);
  });

  testWidgets('a refusal is said under the field, and the old address stays', (tester) async {
    final d = await made();
    final first = d.service.mailAddress!;
    await opened(tester, d);
    await typed(tester, 'matt');
    expect(said(tester), 'Available');
    // Taken in the moment between the check and the press.
    d.service.mailNameRefusal = (status: 409, error: 'That name is taken.', reason: 'taken');
    await tapKey(tester, 'meet-name-use');
    await settle(tester);
    await press(tester, 'Switch');
    await settle(tester, 10);
    expect(said(tester), 'Taken');
    expect(usable(tester), isFalse);
    expect(d.service.mailAddress, first);
    expect(find.text(first.replaceFirst('@', '@​')), findsOneWidget);
    // A service no longer taking mail says so in its own words.
    await typed(tester, 'matthew');
    d.service.takesMail = false;
    await tapKey(tester, 'meet-name-use');
    await settle(tester);
    await press(tester, 'Switch');
    await settle(tester, 10);
    expect(said(tester), 'Email to a note is not set up on this service yet.');
    expect(d.service.mailAddress, first);
    await endSettings(tester);
  });

  testWidgets('an older service, with no names yet, says so rather than failing', (tester) async {
    final d = await made();
    d.service.mailNames = false;
    await opened(tester, d);
    await typed(tester, 'matt');
    expect(said(tester), mailNamesNotYet);
    expect(usable(tester), isFalse);
    await expectLater(d.mailIn!.chooseAddress('matt'), throwsA(isA<ApiError>().having((e) => e.message, 'words', mailNamesNotYet)));
    await endSettings(tester);
  });

  testWidgets('the refresh and the name shut each other, and Cancel shuts the field', (tester) async {
    final d = await made();
    await opened(tester, d);
    expect(find.byKey(const ValueKey('meet-name')), findsOneWidget);
    await tapKey(tester, 'meet-new');
    await settle(tester);
    expect(find.byKey(const ValueKey('meet-name')), findsNothing);
    expect(find.text('Make a new address?'), findsOneWidget);
    await tapKey(tester, 'meet-name-open');
    await settle(tester);
    expect(find.byKey(const ValueKey('meet-name')), findsOneWidget);
    expect(find.text('Make a new address?'), findsNothing);
    await press(tester, 'Cancel');
    expect(find.byKey(const ValueKey('meet-name')), findsNothing);
    await endSettings(tester);
  });

  testWidgets('offered in Simple too', (tester) async {
    final d = await made();
    preferences.update((was) => was.copyWith(experience: 'simple', experienceChosen: true));
    expect(preferences.value.simple, isTrue);
    await opened(tester, d);
    await typed(tester, 'matt');
    expect(said(tester), 'Available');
    await endSettings(tester);
  });

  for (final (name, size, dark) in [('a phone, dark', const Size(390, 1600), true), ('a wide window, light', const Size(1200, 1600), false)]) {
    testWidgets('drawn whole on $name, asking', (tester) async {
      final d = await made();
      await opened(tester, d, size: size, dark: dark);
      await typed(tester, 'a-name-that-is-thirty-letters');
      await tapKey(tester, 'meet-name-use');
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Switch to a-name-that-is-thirty-letters@​in.ghostmarkdown.com?'), findsOneWidget);
      await endSettings(tester);
    });
  }
}
