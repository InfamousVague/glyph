// The Contacts plugin's page (lib/plugins/contacts/contacts_pane.dart) over its switch, which is the plugin's card's
// (lib/plugins/contacts/contacts.dart `contactsSwitch`): off until switched on, which asks; refused, it reads nothing
// and says so, with Allow, or the device's settings where it was refused for good; on, the people the notes name, each
// with the contact they are, chosen, unlinked or matched by name again by hand. Against a stand-in for the address book.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/integrations/contacts/contact_book.dart';
import 'package:ghost_md/integrations/contacts/contacts.dart';
import 'package:ghost_md/plugins/contacts/contacts.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';

import '../../integrations/contacts/support.dart';
import '../support.dart';

List<String> titles(WidgetTester tester) => [for (final section in tester.widgetList<PaneSection>(find.byType(PaneSection, skipOffstage: false))) section.title ?? ''];

String? hintOf(WidgetTester tester, String label) {
  final hint = tester.widget<SettingRow>(find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false)).hint;
  return hint is Text ? hint.data : null;
}

void main() {
  setUpAll(loadAppFonts);

  late FakeContactBook book;
  late ContactsStore store;
  late MemorySwitches switches;
  late Registry registry;
  late Registry before;

  ContactsStore storeOver(ContactBook book, {MemoryStored? kept}) => ContactsStore(book: book, kept: kept ?? MemoryStored())
    ..start(bodies: () => <String>['- [ ] Fix the stove @sam\n- [ ] Lunch with @ana', '- [ ] Pay @matt'], switched: contactsSwitch());

  setUp(() {
    before = plugins;
    switches = MemorySwitches();
    registry = createRegistry([contactsPlugin], store: switches);
    usePlugins(registry);
    book = FakeContactBook();
    store = storeOver(book);
  });
  tearDown(() {
    store.dispose();
    usePlugins(before);
  });

  Future<void> open(WidgetTester tester) async {
    await pumpSettings(tester, SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: ContactsPane(store: store))), size: const Size(390, 1400));
  }

  /// The plugin's card's switch, as Settings › Plugins moves it.
  Future<void> turn(WidgetTester tester, bool on) async {
    registry.setEnabled(contactsManifest.id, on);
    await tester.pump();
    await tester.pump();
    await settleSettings(tester);
  }

  Future<void> press(WidgetTester tester, String word) async {
    await tester.tap(find.text(word));
    await tester.pump();
    await tester.pump();
    await settleSettings(tester);
  }

  testWidgets('is off until the plugin is switched on, and asks nothing', (tester) async {
    await open(tester);
    expect(titles(tester), ['Contacts']);
    expect(store.on, isFalse);
    expect(hintOf(tester, 'Your contacts'), 'Off. Turning it on asks to read your contacts.');
    // The page has no switch of its own: the plugin's card is it.
    expect(find.byType(RowAction), findsOneWidget);
    expect(book.asked, 0);
    expect(find.text('Nothing about a contact leaves this device or goes into a note, but the name you pick.'), findsOneWidget);
    expect(contactsSummary(store), 'Off');
    await endSettings(tester);
  });

  testWidgets('switched on, asks, and lists the people the notes name with the contact each is', (tester) async {
    await open(tester);
    await turn(tester, true);
    expect(book.asked, 1);
    expect(store.on, isTrue);
    expect(hintOf(tester, 'Your contacts'), 'Read on this device only.');
    expect(titles(tester), ['Contacts', 'People in your notes']);
    expect(hintOf(tester, '@sam'), 'Sam Ortiz · Matched by name');
    // Two Anas: nobody, until one is chosen.
    expect(hintOf(tester, '@ana'), 'No contact by this name');
    expect(hintOf(tester, '@matt'), 'No contact by this name');
    expect(contactsSummary(store), '1 of 3 matched');
    await endSettings(tester);
  });

  testWidgets('Turn on on the page by itself switches the plugin on, as the card does', (tester) async {
    await open(tester);
    await press(tester, 'Turn on');
    expect(book.asked, 1);
    expect(registry.isEnabled(contactsManifest.id), isTrue);
    expect(switches.held, {'contacts': true});
    expect(titles(tester), ['Contacts', 'People in your notes']);
    await endSettings(tester);
  });

  testWidgets('refused, reads nothing and says so with Allow; refused for good, offers the device’s settings', (tester) async {
    book.answer = ContactsAccess.denied;
    await open(tester);
    await turn(tester, true);
    expect(store.on, isTrue);
    expect(store.ready, isFalse);
    expect(hintOf(tester, 'Your contacts'), 'Not allowed.');
    expect(contactsSummary(store), 'Not allowed');
    expect(find.text('Ghost.md was not allowed to read your contacts. Allow asks again.'), findsOneWidget);
    expect(find.text('Open settings'), findsNothing);
    expect(titles(tester), ['Contacts']);
    book.answer = ContactsAccess.blocked;
    await press(tester, 'Allow');
    expect(book.asked, 2);
    expect(find.text('Ghost.md is not allowed to read your contacts. Allow it in your device’s settings, then come back here.'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(book.settingsOpened, 1);
    // Allowed at last: the people.
    book.answer = ContactsAccess.granted;
    book.granted = ContactsAccess.granted;
    await store.read();
    await tester.pump();
    expect(titles(tester), ['Contacts', 'People in your notes']);
    await endSettings(tester);
  });

  testWidgets('a device with no address book says why, and offers no way on', (tester) async {
    store.dispose();
    store = storeOver(const NoContactBook());
    await store.read();
    await open(tester);
    await turn(tester, true);
    expect(store.ready, isFalse);
    expect(find.text('Turn on'), findsNothing);
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

  testWidgets('switched off, matches no one and keeps what was chosen for next time', (tester) async {
    await open(tester);
    await turn(tester, true);
    store.link('ana', ana);
    expect(store.contactOf('ana'), ana);
    await turn(tester, false);
    expect(titles(tester), ['Contacts']);
    expect(store.on, isFalse);
    expect(store.everyone, isEmpty);
    // No chip is a contact's, and A person has none to offer.
    expect(store.contactOf('sam'), isNull);
    expect(store.ready, isFalse);
    expect(store.settings.links, {'ana': 'c-ana'});
    await endSettings(tester);
  });

  test('is found by what the phone allows, and by its people once it allows it', () async {
    expect([for (final each in contactsFindable(store)) each.name], ['Your contacts']);
    await store.turnOn();
    expect([for (final each in contactsFindable(store)) each.name], ['Your contacts', 'People in your notes']);
  });

  test('a device that had its own switch on before it was a plugin finds the plugin on, once', () async {
    final kept = MemoryStored()..write(contactSettingsKey, const ContactSettings(on: true, links: {'sam': 'c-sam'}).toJson());
    final adopted = storeOver(FakeContactBook(granted: ContactsAccess.granted), kept: kept);
    addTearDown(adopted.dispose);
    expect(registry.isEnabled(contactsManifest.id), isTrue);
    expect(adopted.on, isTrue);
    // The store's own is the plugin's now: off, and the matches kept.
    expect(adopted.settings, const ContactSettings(links: {'sam': 'c-sam'}));
    registry.setEnabled(contactsManifest.id, false);
    final again = storeOver(FakeContactBook(granted: ContactsAccess.granted), kept: kept);
    addTearDown(again.dispose);
    expect(registry.isEnabled(contactsManifest.id), isFalse);
  });

  test('keeps its own switch where the app’s registry has no Contacts plugin', () async {
    usePlugins(createRegistry(const [], store: MemorySwitches()));
    expect(contactsSwitch(), isNull);
    final own = ContactsStore(book: FakeContactBook(), kept: MemoryStored())..start(switched: contactsSwitch());
    addTearDown(own.dispose);
    await own.turnOn();
    expect(own.on, isTrue);
    expect(own.settings.on, isTrue);
  });
}
