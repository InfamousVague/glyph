// Write meeting summaries with Claude, on the Claude plugin's page (lib/plugins/claude/claude_in_app.dart, lib/claude/
// claude_settings.dart `meetings`; Matt, 2026-10-28: "We should be using Claude to generate the meeting summaries not
// the local processor on the Mac when the anthropic API key is set"). On by default, so a key is all it takes; the card
// says honestly that the transcript goes to Anthropic under the person's own key; off is the device's model; Simple
// shows the switch with a shorter word; Settings' search finds it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/claude/claude.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_search.dart' show wordsFound;

import '../../settings/support.dart';

void main() {
  late ClaudeSettings settings;
  late PreferencesStore prefs;

  Future<void> page(WidgetTester tester, {bool key = true, bool simple = false}) async {
    settings = ClaudeSettings(MemorySecureStore());
    if (key) await settings.setKey('sk-ant-test');
    prefs = PreferencesStore();
    prefs.value = Preferences.defaults.copyWith(experience: simple ? 'simple' : 'advanced');
    await pumpSettings(tester, SingleChildScrollView(child: ClaudeInApp(settings: settings, phone: false, prefs: prefs)), size: const Size(390, 4000));
  }

  GlacierSwitch meetingsSwitch(WidgetTester tester) => tester.widget<GlacierSwitch>(find.descendant(of: find.byKey(const ValueKey('claude-meetings')), matching: find.byType(GlacierSwitch)));

  const privacy = 'On, a meeting’s transcript is sent from this device to Anthropic under your own API key, and Anthropic bills the key. It goes nowhere else: not through Ghost.md’s server. Off, nothing of a meeting goes to Anthropic.';

  testWidgets('is on by default with a key, says where the transcript goes, and off is the device’s model', (tester) async {
    await page(tester);
    expect(find.byWidgetPredicate((w) => w is PaneSection && w.title == 'Meeting summaries'), findsOneWidget);
    expect(meetingsSwitch(tester).checked, isTrue);
    expect(find.text(privacy), findsOneWidget);
    expect(find.textContaining('Sonnet 5.5 writes them'), findsOneWidget);
    meetingsSwitch(tester).onCheckedChange!(false);
    await tester.pump();
    expect(settings.meetings, isFalse);
    expect(find.text('Off: the summary model on your device writes them, and the transcript stays on your devices.'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('without a key, says to add one', (tester) async {
    await page(tester, key: false);
    expect(find.text('Add your API key above, and Claude writes your meetings up.'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('in Simple, the switch and the plain word, with the same privacy line', (tester) async {
    await page(tester, simple: true);
    expect(meetingsSwitch(tester).checked, isTrue);
    expect(find.text('On: Claude writes them.'), findsOneWidget);
    expect(find.text(privacy), findsOneWidget);
    await endSettings(tester);
  });

  test('Settings’ search finds it by meetings, summaries and transcript', () {
    for (final query in ['meeting', 'summaries', 'transcript', 'meeting summaries']) {
      final found = [for (final f in claudeInAppFindable) if (wordsFound(query, [f.name, f.words])) f.name];
      expect(found, contains('Meeting summaries'), reason: query);
    }
  });
}
