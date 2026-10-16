// Settings › Account's two cards for what the account publishes and takes in (lib/settings/published_sites.dart,
// lib/mail/ui/mail_card.dart): every published site with its link and Unpublish, and the private mail address with
// Copy, a new one and off, saying plainly that the server reads each mail as it arrives. Each is drawn only when it
// has something to say, on the Account page itself.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/mail/ui/mail_card.dart';
import 'package:ghost_md/settings/panes/account_pane.dart';
import 'package:ghost_md/settings/published_sites.dart';

import '../account_ui/support.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the Account page lists the published sites, copies a link and unpublishes one', (tester) async {
    final device = await Device.make(publishing: true);
    final copied = Clipped(tester);
    final walk = await device.sites!.publish(device.keep('n', '# Walk'), device.notes.held.values.toList());
    await device.sites!.publish(device.keep('b', '---\nbook: true\n---\n# Field guide\n'), device.notes.held.values.toList());
    device.sites!.forget();
    await device.pump(tester, AccountPane(services: device.services));
    await settle(tester, 10);
    expect(titlesOf(tester), containsAllInOrder(['Published sites', 'Email to a note']));
    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('A notebook. Published just\u00A0now.'), findsOneWidget);
    await bringIntoView(tester, find.byKey(ValueKey('site:${walk.id}')));
    await tester.tap(find.descendant(of: find.byKey(ValueKey('site:${walk.id}')), matching: find.text('Copy')));
    await settle(tester);
    expect(copied.text, walk.link);
    await tester.tap(find.descendant(of: find.byKey(ValueKey('site:${walk.id}')), matching: find.text('Unpublish')));
    await settle(tester, 10);
    expect(device.service.sites.keys, isNot(contains(walk.id)));
    expect(find.text('“Walk” is unpublished.'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('with nothing published and a service that takes no mail, neither card is drawn', (tester) async {
    final service = await FakeService.start(seed: seeded);
    service.takesMail = false;
    final device = await Device.make(service: service, publishing: true);
    await device.pump(tester, AccountPane(services: device.services));
    await settle(tester, 10);
    expect(titlesOf(tester), isNot(contains('Published sites')));
    expect(titlesOf(tester), isNot(contains('Email to a note')));
    expect(find.byType(MailCard), findsNothing);
    expect(find.byType(PublishedSites), findsNothing);
    await endSettings(tester);
  });

  testWidgets('email to a note says what the server sees, turns on an address, copies it, makes a new one and turns it off', (tester) async {
    final device = await Device.make(publishing: true);
    final copied = Clipped(tester);
    await device.pump(tester, AccountPane(services: device.services));
    await settle(tester, 10);
    expect(find.text(mailCardFooter), findsOneWidget);
    expect(mailCardFooter, contains('The server reads each mail as it arrives'));
    expect(mailCardFooter, contains('keeps only the sealed copy'));
    await press(tester, 'Turn on an address');
    await settle(tester, 10);
    final first = device.service.mailAddress!;
    expect(find.text(first.replaceFirst('@', '@\u200B')), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('mail-address')), matching: find.text('Copy')));
    await settle(tester);
    expect(copied.text, first);
    await press(tester, 'Make a new address');
    await settle(tester, 10);
    final second = device.service.mailAddress!;
    expect(second, isNot(first));
    expect(find.text(second.replaceFirst('@', '@\u200B')), findsOneWidget);
    expect(find.text('A new address. The old one takes no more mail.'), findsOneWidget);
    await press(tester, 'Turn off');
    await settle(tester, 10);
    expect(device.service.mailAddress, isNull);
    expect(find.text('Turn on an address'), findsOneWidget);
    await endSettings(tester);
  });
}
