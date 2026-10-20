// Spending limit on the Claude plugin's page (lib/plugins/claude/claude_in_app.dart, lib/claude/claude_spend.dart).
// Matt, 2026-10-20: "Also enable setting spending limits in claude settings in the app". Off by default; on, a
// monthly amount (the presets or one typed), Warn me at 80%, the month so far with Reset count, and the card saying
// the count is this device's. Settings' search finds it by spending, limit, budget and cost.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/claude_spend.dart';
import 'package:ghost_md/plugins/claude/claude.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_search.dart' show wordsFound;

import '../../settings/support.dart';

void main() {
  late ClaudeSettings settings;

  Future<void> page(WidgetTester tester) async {
    settings = ClaudeSettings(MemorySecureStore());
    settings.spend.now = () => DateTime(2026, 10, 20);
    await pumpSettings(tester, SingleChildScrollView(child: ClaudeInApp(settings: settings, phone: false)), size: const Size(390, 4000));
  }

  GlacierSwitch switchOf(WidgetTester tester, String key) => tester.widget<GlacierSwitch>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlacierSwitch)));

  testWidgets('is off by default, says the count is this device’s, and shows the month so far', (tester) async {
    await page(tester);
    expect(find.byWidgetPredicate((w) => w is PaneSection && w.title == 'Spending limit'), findsOneWidget);
    expect(switchOf(tester, 'claude-spend-on').checked, isFalse);
    expect(find.text('Off: Claude is asked whatever it costs.'), findsOneWidget);
    expect(find.text('Counted on this device from what Claude reports for each request; other apps or devices using the same key aren’t included.'), findsOneWidget);
    expect(find.byKey(const ValueKey('claude-spend-limit:10')), findsNothing);
    expect(find.text('This month: \$0.00 · 0 requests'), findsOneWidget);
    // Counted whether or not the limit is on.
    settings.spend.record('claude-opus-5-5', ClaudeUsage(output: 61500));
    await tester.pump();
    expect(find.text('This month: \$1.23 · 1 request'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('on, takes a preset or a typed amount, warns at 80% by its switch, and resets the count', (tester) async {
    await page(tester);
    switchOf(tester, 'claude-spend-on').onCheckedChange!(true);
    await tester.pump();
    expect(settings.spend.on, isTrue);
    expect(find.text('On: \$10 a month, from the 1st.'), findsOneWidget);
    for (final amount in ['5', '10', '25', '50']) {
      expect(find.byKey(ValueKey('claude-spend-limit:$amount')), findsOneWidget);
    }
    expect(tester.widget<Pick>(find.descendant(of: find.byKey(const ValueKey('claude-spend-limit:10')), matching: find.byType(Pick))).checked, isTrue);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('claude-spend-limit:25')), matching: find.byType(Pick)));
    await tester.pump();
    expect(settings.spend.limit, 25);

    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('claude-spend-custom')), matching: find.byType(EditableText)), '\$12.5');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('claude-spend-custom')), matching: find.text('Set')));
    await tester.pump();
    expect(settings.spend.limit, 12.5);
    expect(find.text('Now \$12.50 a month.'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('claude-spend-custom')), matching: find.byType(EditableText)), 'lots');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('claude-spend-custom')), matching: find.text('Set')));
    await tester.pump();
    expect(settings.spend.limit, 12.5);
    expect(find.text('Type the monthly limit in US dollars, such as 15 or 12.50.'), findsOneWidget);

    expect(switchOf(tester, 'claude-spend-warn').checked, isTrue);
    switchOf(tester, 'claude-spend-warn').onCheckedChange!(false);
    await tester.pump();
    expect(settings.spend.warn, isFalse);

    // $12.50 spent: reached, said, and Reset count lifts it.
    settings.spend.record('claude-opus-5-5', ClaudeUsage(output: 625000));
    await tester.pump();
    expect(find.text('This month: \$12.50 of \$12.50 · 1 request'), findsOneWidget);
    expect(find.text('The limit is reached: Claude isn’t asked until the 1st, or until you raise it.'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('claude-spend-month')), matching: find.text('Reset count')));
    await tester.pump();
    expect(settings.spend.reached, isFalse);
    expect(find.text('This month: \$0.00 of \$12.50 · 0 requests'), findsOneWidget);
    await endSettings(tester);
  });

  test('Settings’ search finds it by spending, limit, budget and cost', () {
    for (final query in ['spending', 'limit', 'budget', 'cost', 'spending limit']) {
      final found = [for (final f in claudeInAppFindable) if (wordsFound(query, [f.name, f.words])) f.name];
      expect(found, contains('Spending limit'), reason: query);
    }
  });
}
