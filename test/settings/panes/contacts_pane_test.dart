// Settings › Contacts (lib/settings/panes/contacts_pane.dart): off until turned on, which asks; refused, it stays off
// and says so, with the device's settings where it was refused for good; on, the people the notes name, each with the
// contact they are, chosen, unlinked or matched by name again by hand. Against a stand-in for the address book.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/integrations/contacts/contact_book.dart';
import 'package:ghost_md/integrations/contacts/contacts.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/contacts_pane.dart';
import 'package:glacier/glacier.dart';

import '../../integrations/contacts/support.dart';
import '../support.dart';

List<String> titles(WidgetTester tester) => [for (final section in tester.widgetList<PaneSection>(find.byType(PaneSection, skipOffstage: false))) section.title ?? ''];

String? hintOf(WidgetTester tester, String label) {
  final hint = tester.widget<SettingRow>(find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false)).hint;
  return hint is Text ? hint.data : null;
}

GlacierSwitch switchOf(WidgetTester tester) => tester.widget<GlacierSwitch>(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'Use my contacts', skipOffstage: false));

void main() {
  setUpAll(loadAppFonts);

  late FakeContactBook book;
  late ContactsStore store;

  setUp(() {
    book = FakeContactBook();
    store = ContactsStore(book: book, kept: MemoryStored())..start(bodies: () => <String>['- [ ] Fix the stove @sam\n- [ ] Lunch with @ana', '- [ ] Pay @matt']);
  });

  Future<void> open(WidgetTester tester) async {
    await pumpSettings(tester, SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: ContactsPane(store: store))), size: const Size(390, 1400));
  }

  Future<void> turn(WidgetTester tester, bool on) async {
    switchOf(tester).onCheckedChange!(on);
    await tester.pump();
    await tester.pump();
    await settleSettings(tester);
  }

  testWidgets('is off until it is turned on, and asks nothing', (tester) async {
    await open(tester);
    expect(titles(tester), ['Contacts']);
    expect(switchOf(tester).checked, isFalse);
    expect(hintOf(tester, 'Use my contacts'), 'Off. Turning it on asks to read your contacts.');
    expect(book.asked, 0);
    expect(find.text('Nothing about a contact leaves this device or goes into a note, but the name you pick.'), findsOneWidget);
    expect(contactsSummary(store), 'Off');
    await endSettings(tester);
  });

  testWidgets('turned on, asks, and lists the people the notes name with the contact each is', (tester) async {
    await open(tester);
    await turn(tester, true);
    expect(book.asked, 1);
    expect(switchOf(tester).checked, isTrue);
    expect(titles(tester), ['Contacts', 'People in your notes']);
    expect(hintOf(tester, '@sam'), 'Sam Ortiz · Matched by name');
    // Two Anas: nobody, until one is chosen.
    expect(hintOf(tester, '@ana'), 'No contact by this name');
    expect(hintOf(tester, '@matt'), 'No contact by this name');
    expect(contactsSummary(store), '1 of 3 matched');
    await endSettings(tester);
  });

  testWidgets('refused, stays off and says so; refused for good, offers the device’s settings', (tester) async {
    book.answer = ContactsAccess.denied;
    await open(tester);
    await turn(tester, true);
    expect(switchOf(tester).checked, isFalse);
    expect(find.text('Ghost.md was not allowed to read your contacts. Turn this on to be asked again.'), findsOneWidget);
    expect(find.text('Open settings'), findsNothing);
    expect(titles(tester), ['Contacts']);
    book.answer = ContactsAccess.blocked;
    await turn(tester, true);
    expect(switchOf(tester).checked, isFalse);
    expect(find.text('Ghost.md is not allowed to read your contacts. Allow it in your device’s settings, then turn this on.'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(book.settingsOpened, 1);
    await endSettings(tester);
  });

  testWidgets('a device with no address book cannot turn it on, and says why', (tester) async {
    store = ContactsStore(book: const NoContactBook(), kept: MemoryStored());
    await store.read();
    await open(tester);
    await turn(tester, true);
    expect(switchOf(tester).checked, isFalse);
    expect(switchOf(tester).disabled, isTrue);
    expect(find.text('This device has no contacts Ghost.md can read.'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('chooses a contact by hand, unlinks one, and takes it back to the name', (tester) async {
    await open(tester);
    await turn(tester, true);
    // Choose: the contacts, searched, and the one pressed kept for Ana.
    await tester.tap(find.byKey(const ValueKey('contacts-choose:ana')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Contact for @ana'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'silva');
    await tester.pump();
    expect(find.text('Ana Lima'), findsNothing);
    await tester.tap(find.text('Ana Silva'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(hintOf(tester, '@ana'), 'Ana Silva · Chosen by you');
    // Unlink: Sam is no contact, by hand.
    await tester.tap(find.byKey(const ValueKey('contacts-unlink:sam')));
    await tester.pump();
    expect(hintOf(tester, '@sam'), 'No contact · Chosen by you');
    expect(store.contactOf('sam'), isNull);
    // By name: matched as before.
    await tester.tap(find.byKey(const ValueKey('contacts-by-name:sam')));
    await tester.pump();
    expect(hintOf(tester, '@sam'), 'Sam Ortiz · Matched by name');
    expect(store.settings.links, {'ana': 'c-ana2'});
    await endSettings(tester);
  });

  testWidgets('turned off, lists no one and keeps what was chosen for next time', (tester) async {
    await open(tester);
    await turn(tester, true);
    store.link('ana', ana);
    await turn(tester, false);
    expect(titles(tester), ['Contacts']);
    expect(store.everyone, isEmpty);
    expect(store.settings.links, {'ana': 'c-ana'});
    await endSettings(tester);
  });

  test('is found by the switch, and by its people once it is on', () async {
    expect([for (final each in contactsFindable(store)) each.name], ['Use my contacts']);
    await store.turnOn();
    expect([for (final each in contactsFindable(store)) each.name], ['Use my contacts', 'People in your notes']);
  });
}
