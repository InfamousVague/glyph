import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/plugins/list.dart';
import 'package:ghost_messaging/plugins/registry.dart';
import 'package:ghost_messaging/plugins/settings.dart';
import 'package:ghost_messaging/plugins/ui.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/ui/common.dart' show IconTap;
import 'package:ghost_messaging/ui/conversations.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:glacier/glacier.dart';

import 'support/list_harness.dart';
import 'support/test_plugins.dart';

/// The list of conversations and Settings › Plugins with a plugin made up for the purpose
/// (test/support/test_plugins.dart): its section's chip and rows, what it puts in the list's slots, a conversation
/// filed by hand, a rule run on a message that has just come, and its switch.
List<Map<String, Object?>> _phone() => [
      ListPhone.conversation(1, '+15551230001', 'Sounds good, see you at 7', name: 'Maya Chen', minutes: 4),
      ListPhone.conversation(2, '70001', 'Your ticket 4411 is ready', minutes: 9, unread: true),
      ListPhone.conversation(3, '+15551230005', 'Call me when you land', name: 'Dad', minutes: 50),
      ListPhone.conversation(4, '70002', 'ticket 5522 was closed', minutes: 120),
      ListPhone.conversation(5, '+15551230006', 'I have ticket 77 for you', name: 'Priya Natarajan', minutes: 300),
      ListPhone.conversation(6, '70003', 'ticket 9000, long ago', minutes: 9000, archived: true),
    ];

Finder _chip(String label) => find.descendant(of: find.byType(SectionChips), matching: find.text(label));
Finder _icon(String label) => find.byWidgetPredicate((w) => w is IconTap && w.label == label);

void main() {
  late PluginRegistry shipped;
  setUp(() => shipped = PluginRegistry.instance);
  tearDown(() => PluginRegistry.instance = shipped);

  testWidgets('with no plugin the list is as it was: no chips, every conversation in it', (tester) async {
    PluginRegistry.instance = PluginRegistry(const []);
    final phone = ListPhone(_phone())..install();
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const ConversationsScreen(), AppState());
    expect(find.byType(SectionChips), findsNothing);
    expect(find.byType(ConversationRow), findsNWidgets(5));
    expect(find.byType(PluginRow), findsNothing);
    expect(phone.asked, isEmpty);
  });

  testWidgets('a section has a chip while it has conversations, its own rows, and leaves the main list without them', (tester) async {
    PluginRegistry.instance = PluginRegistry([TicketsPlugin()]);
    final phone = ListPhone(_phone())..install();
    final sheet = await loadSheet(tester);
    final state = AppState();
    await pumpScreen(tester, sheet, const ConversationsScreen(), state);

    // The main list: the two tickets from numbers that are not contacts have left it; a contact's has not, and the
    // archived one is nobody's.
    expect(_chip('Messages'), findsOneWidget);
    expect(_chip('Tickets'), findsOneWidget);
    expect(_chip('2'), findsOneWidget);
    expect(find.byType(ConversationRow), findsNWidgets(3));
    expect(find.text('Your ticket 4411 is ready'), findsNothing);
    expect(find.text('I have ticket 77 for you'), findsOneWidget);
    // The plugin's button in the header, before New message.
    expect(_icon('Ticket desk'), findsOneWidget);
    expect(tester.getCenter(_icon('Ticket desk')).dx, lessThan(tester.getCenter(_icon('New message')).dx));
    expect(find.text('Tickets wait here.'), findsNothing);

    // Its chip: its own list, the newest first, each row with the number large, and its note over the list.
    await tester.tap(_chip('Tickets'));
    await settle(tester);
    expect(find.byType(PluginRow), findsNWidgets(2));
    expect(find.byType(ConversationRow), findsNothing);
    expect(tester.getCenter(find.text('4411')).dy, lessThan(tester.getCenter(find.text('5522')).dy));
    expect(find.text('Tickets wait here.'), findsOneWidget);
    expect(find.textContaining('Archived ('), findsNothing, reason: 'the way to Archived is the main list\'s');

    // A tap is the row's own: it copies, and says so. The button at its end does the same.
    await tester.tap(find.text('4411'));
    await settle(tester);
    expect(phone.copied, ['4411']);
    expect(find.text('Copied 4411'), findsOneWidget);
    await tester.tap(_icon('Copy 5522'));
    await settle(tester);
    expect(phone.copied, ['4411', '5522']);

    // Its long press offers to open it, since a tap does not, and has the plugin's own line.
    await tester.longPress(find.text('5522'));
    await settle(tester);
    expect(find.text('Open conversation'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    await tester.tap(find.text('Keep in Messages').last);
    await settle(tester);
    // Filed in the main list: one left in the section, and the choice is kept with the person's others.
    expect(find.byType(PluginRow), findsOneWidget);
    expect(_chip('1'), findsOneWidget);
    expect(phone.prefs[Filing.key], '4:');

    // The word on the last row does the same: the section is empty, its chip goes, and the list is the main one.
    await tester.tap(find.text('Keep in Messages'));
    await settle(tester);
    expect(find.byType(SectionChips), findsNothing);
    expect(find.byType(ConversationRow), findsNWidgets(5));
    expect(find.text('ticket 5522 was closed'), findsOneWidget);
    expect(phone.prefs[Filing.key], '4:,2:');

    // From the main list a conversation can be filed back: its menu has the plugin's line for that.
    await tester.longPress(find.text('ticket 5522 was closed'));
    await settle(tester);
    expect(find.text('Open conversation'), findsNothing);
    await tester.tap(find.text('Move to Tickets'));
    await settle(tester);
    expect(_chip('1'), findsOneWidget);
    expect(phone.prefs[Filing.key], '2:', reason: 'it is where its words put it anyway: nothing is kept for it');
  });

  testWidgets('a search from the main list looks through the sections too; from a section, through that section', (tester) async {
    PluginRegistry.instance = PluginRegistry([TicketsPlugin()]);
    ListPhone(_phone()).install();
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const ConversationsScreen(), AppState());
    await tester.enterText(find.byType(EditableText).first, 'ticket');
    await settle(tester);
    expect(find.byType(ConversationRow), findsNWidgets(3));
    expect(find.text('Your ticket 4411 is ready'), findsOneWidget);
    await tester.tap(_chip('Tickets'));
    await settle(tester);
    expect(find.byType(PluginRow), findsNWidgets(2));
    await tester.enterText(find.byType(EditableText).first, 'closed');
    await settle(tester);
    expect(find.byType(PluginRow), findsOneWidget);
    expect(find.text('5522'), findsOneWidget);
  });

  testWidgets('several can be chosen in a section, where a tap then chooses', (tester) async {
    PluginRegistry.instance = PluginRegistry([TicketsPlugin()]);
    final phone = ListPhone(_phone())..install();
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const ConversationsScreen(), AppState());
    await tester.tap(_chip('Tickets'));
    await settle(tester);
    await tester.longPress(find.text('4411'));
    await settle(tester);
    await tester.tap(find.text('Select'));
    await settle(tester);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byType(SectionChips), findsNothing, reason: 'the chips give way while choosing');
    await tester.tap(find.text('5522'));
    await settle(tester);
    expect(find.text('2 selected'), findsOneWidget);
    expect(phone.copied, isEmpty);
  });

  testWidgets('switched off, the plugin leaves the list as it was; switched on again, its section is back', (tester) async {
    final plugin = TicketsPlugin();
    PluginRegistry.instance = PluginRegistry([plugin]);
    ListPhone(_phone()).install();
    final sheet = await loadSheet(tester);
    final state = AppState();
    await pumpScreen(tester, sheet, const ConversationsScreen(), state);
    await tester.tap(_chip('Tickets'));
    await settle(tester);
    expect(find.byType(PluginRow), findsNWidgets(2));

    state.setFlag(PluginRegistry.switchKey(plugin), false);
    await settle(tester);
    expect(find.byType(SectionChips), findsNothing);
    expect(find.byType(PluginRow), findsNothing);
    expect(find.byType(ConversationRow), findsNWidgets(5));
    expect(_icon('Ticket desk'), findsNothing);

    state.setFlag(PluginRegistry.switchKey(plugin), true);
    await settle(tester);
    expect(_chip('2'), findsOneWidget);
    expect(find.byType(ConversationRow), findsNWidgets(3));
  });

  testWidgets('a rule is run on an unread conversation as it is first seen, and a mute it asked for is undone when the conversation leaves', (tester) async {
    PluginRegistry.instance = PluginRegistry([TicketsPlugin()]);
    final phone = ListPhone(_phone())..install();
    final sheet = await loadSheet(tester);
    final state = AppState()
      ..setFlag('plugin_tickets_read', true)
      ..setFlag('plugin_tickets_quiet', true);
    await pumpScreen(tester, sheet, const ConversationsScreen(), state);
    // The unread ticket, and no other: marked as read and muted, once.
    expect(phone.asked, ['markRead 2', 'muted 2 true']);
    expect(phone.prefs[ListPlugins.mutedKey], '2:tickets:tickets');
    // Read again, with the same words: nothing more is asked.
    Sms.instance.changes.add(2);
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(phone.asked, ['markRead 2', 'muted 2 true']);

    // Filed back in the main list: the mute the plugin asked for is taken off.
    await tester.tap(_chip('Tickets'));
    await settle(tester);
    await tester.longPress(find.text('4411'));
    await settle(tester);
    await tester.tap(find.text('Keep in Messages').last);
    await settle(tester);
    expect(phone.asked.last, 'muted 2 false');
    expect(phone.prefs[ListPlugins.mutedKey], '');
  });

  testWidgets('a mute a plugin asked for is undone when the plugin is switched off', (tester) async {
    final plugin = TicketsPlugin();
    PluginRegistry.instance = PluginRegistry([plugin]);
    final phone = ListPhone(_phone())..install();
    final sheet = await loadSheet(tester);
    final state = AppState()..setFlag('plugin_tickets_quiet', true);
    await pumpScreen(tester, sheet, const ConversationsScreen(), state);
    expect(phone.asked, ['muted 2 true']);
    state.setFlag(PluginRegistry.switchKey(plugin), false);
    await settle(tester);
    expect(phone.asked, ['muted 2 true', 'muted 2 false']);
  });

  testWidgets('Settings › Plugins: each plugin with its switch, and its own settings while it is on', (tester) async {
    final plugin = TicketsPlugin();
    final registry = PluginRegistry([plugin]);
    final phone = ListPhone(_phone())..install();
    final sheet = await loadSheet(tester);
    final state = AppState();
    final model = SettingsModel(state);
    addTearDown(model.dispose);
    final section = pluginsSection(registry);
    await pumpScreen(tester, sheet, SectionPage(section: section, model: model), state);

    expect(section.summary!(model), 'Tickets');
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('Texts with a ticket number get a section of their own.'), findsOneWidget);
    // Its own card: the rows it describes in words, then what it put in the settings slot.
    expect(find.text('Mark tickets as read'), findsOneWidget);
    expect(find.text('What a ticket is'), findsOneWidget);
    expect(find.text('A row of its own'), findsOneWidget);
    expect(find.byType(GlacierSwitch), findsNWidgets(2));

    // Its own switch is kept under its name.
    await tester.tap(find.byType(GlacierSwitch).last);
    await settle(tester);
    expect(phone.prefs['plugin_tickets_read'], 'on');

    // Switched off: its card goes, and Settings' list says none is on.
    await tester.tap(find.byType(GlacierSwitch).first);
    await settle(tester);
    expect(phone.prefs['plugin_tickets'], 'off');
    expect(find.text('Mark tickets as read'), findsNothing);
    expect(find.byType(GlacierSwitch), findsOneWidget);
    expect(section.summary!(model), 'None on');

    // Settings' search reads the page as it reads every other: the plugin and its setting are found by name.
    state.setFlag('plugin_tickets', true);
    await settle(tester);
    final context = tester.element(find.byType(SectionPage));
    final found = [for (final h in searchSettings(context, model, [section], 'ticket')) h.setting ?? h.section.label];
    expect(found, containsAll(['Tickets', 'Mark tickets as read', 'What a ticket is']));
  });

  test('sorting five thousand conversations into sections takes a few milliseconds, and is not done again for the same list', () async {
    final plugin = TicketsPlugin();
    final list = ListPlugins(changed: () {}, open: (_) {}, refresh: () async {}, registry: PluginRegistry([plugin]));
    addTearDown(list.dispose);
    list.bind(AppState());
    final all = [
      for (var i = 0; i < 5000; i++)
        Conversation.from({'id': i, 'date': 9000000 - i, 'people': [ListPhone.person('7${1000 + i}')], 'snippet': i % 9 == 0 ? 'Your ticket $i is ready' : 'A text of ordinary words, number $i'}),
    ];
    list.take(all);
    while (list.tags.waiting > 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final clock = Stopwatch()..start();
    final sorted = list.sort(all);
    final first = clock.elapsedMicroseconds;
    expect(sorted.counts['tickets'], 556);
    clock.reset();
    expect(list.sort(all), same(sorted));
    final again = clock.elapsedMicroseconds;
    // ignore: avoid_print
    print('5000 conversations sorted in ${(first / 1000).toStringAsFixed(1)} ms; asked again, ${(again / 1000).toStringAsFixed(3)} ms');
    expect(first, lessThan(60000));
    expect(list.pick(all, null, searching: false), hasLength(5000 - 556));
    expect(list.pick(all, 'tickets', searching: false), hasLength(556));
  });
}
