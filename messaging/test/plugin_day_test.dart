import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/plugins/day.dart';
import 'package:ghost_messaging/plugins/kinds.dart';
import 'package:ghost_messaging/plugins/plugin.dart';
import 'package:ghost_messaging/plugins/quiet.dart';
import 'package:ghost_messaging/plugins/registry.dart';
import 'package:ghost_messaging/plugins/strangers.dart';

import 'support/list_harness.dart';

/// Your day, Quiet hours and Unknown numbers (Matt, 2026-11-14: "let's add all of the additional ones to a plugins,
/// some can be grouped into the same plugin").
void main() {
  testWidgets('Your day: what is waiting, each line opening its list, put away for the day', (tester) async {
    final registry = PluginRegistry([DayPlugin(now: () => DateTime(2026, 11, 14, 8))]);
    final store = MemoryStore();
    final sheet = await loadSheet(tester);
    String? shown;
    Widget card(Map<String, int> counts) => Builder(builder: (context) => Column(children: registry.widgets(Slots.aboveList, context, ListPlace(counts: counts, show: (s) => shown = s), store)));
    await pumpScreen(tester, sheet, card({'reply': 3, 'deliveries': 2, 'reminders': 1, 'codes': 4}), AppState());
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Saturday, November 14'), findsOneWidget);
    expect(find.textContaining('waiting on you'), findsNothing, reason: 'Needs a reply was taken out (Matt, 2026-11-16)');
    expect(find.text('2 deliveries'), findsOneWidget);
    expect(find.text('1 bill or payment'), findsOneWidget);
    expect(find.textContaining('appointment'), findsNothing, reason: 'none waiting');
    await tester.tap(find.text('2 deliveries'));
    expect(shown, 'deliveries');
    // Put away: gone for today, back when something more is waiting.
    await tester.tap(find.bySemanticsLabel('Put away for today'));
    await pumpScreen(tester, sheet, card({'deliveries': 2, 'reminders': 1}), AppState());
    expect(find.text('Good morning'), findsNothing);
    await pumpScreen(tester, sheet, card({'deliveries': 3, 'reminders': 1}), AppState());
    expect(find.text('3 deliveries'), findsOneWidget);
    // Nothing waiting: no card.
    await pumpScreen(tester, sheet, card({'codes': 2, 'reply': 5}), AppState());
    expect(find.byType(DayCard), findsNothing);
  });

  test('Quiet hours: the hidden kinds are muted as they come, while chosen', () {
    final registry = PluginRegistry(const [KindsPlugin(), QuietPlugin()]);
    final store = MemoryStore();
    MessageFacts f(String text) => MessageFacts(thread: 1, senders: const ['+15559870000'], text: text, contact: false);
    List<IncomingAction> asked(MessageFacts facts) => [for (final b in registry.incoming(facts, registry.classify(facts, store), store)) b.action];
    expect(asked(f('Election day is Tuesday. Paid for by Friends of Pat')).whereType<MuteNotification>(), hasLength(1));
    expect(asked(f('Your package is out for delivery')), isEmpty, reason: 'a kind that is shown is not muted');
    store.write('plugin_quiet_kinds', 'off');
    expect(asked(f('Election day is Tuesday. Paid for by Friends of Pat')), isEmpty);
  });

  test('Unknown numbers: a guess from the number and the words', () {
    expect(strangerGuess('+15559870000', 'Congratulations! You\'ve won a gift card. Claim now: http://prize.example/win'), 'spam');
    expect(strangerGuess('28777', 'USPS: your package is out for delivery'), 'business');
    expect(strangerGuess('+15559870000', 'Thanks for choosing us. Reply STOP to opt out'), 'business');
    expect(strangerGuess('+15559870000', 'hey it\'s Sam from the gym, got your number from Jess'), 'person');
    for (final p in [QuietPlugin, StrangersPlugin]) {
      expect(shippedPlugins.where((s) => s.runtimeType == p), hasLength(1), reason: '$p ships');
    }
    // Your day is kept but not shipped for now (Matt, 2026-11-14: "remove the plugin that gives you the digest for now").
    expect(shippedPlugins.whereType<DayPlugin>(), isEmpty);
  });
}
