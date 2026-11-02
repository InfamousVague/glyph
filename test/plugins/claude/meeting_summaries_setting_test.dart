// Meeting summaries, on the Claude plugin's page (lib/plugins/claude/claude_in_app.dart; Matt, 2026-10-28: "We should
// be using Claude to generate the meeting summaries not the local processor on the Mac when the anthropic API key is
// set"). A key is all it takes, Settings › AI › Meeting summaries being Automatic; the card says honestly that the
// transcript goes to Anthropic under the person's own key, and its row opens that choice, the one place it is made
// since its own "Write meeting summaries with Claude" switch went (Matt, 2026-11-01: "see if there are other settings
// that can be simplified removed"). Settings' search finds it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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

  const privacy = 'Where Claude writes them, a meeting’s transcript is sent from this device to Anthropic under your own API key, and Anthropic bills the key. It goes nowhere else: not through Ghost.md’s server.';

  testWidgets('says where the transcript goes, and its row is the way to who writes them, with no switch of its own', (tester) async {
    await page(tester);
    expect(find.byWidgetPredicate((w) => w is PaneSection && w.title == 'Meeting summaries'), findsOneWidget);
    expect(find.text(privacy), findsOneWidget);
    final row = tester.widget<SettingRow>(find.byKey(const ValueKey('claude-meetings')));
    expect(row.label, 'Who writes them');
    expect(find.text('Chosen in Settings › AI › Meeting summaries. Automatic is Claude.'), findsOneWidget);
    expect(find.bySemanticsLabel('Write meeting summaries with Claude'), findsNothing);
    await endSettings(tester);
  });

  testWidgets('without a key, says to add one', (tester) async {
    await page(tester, key: false);
    expect(find.text('Add your API key above, and Claude writes your meetings up.'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('in Simple, the same card and the same privacy line', (tester) async {
    await page(tester, simple: true);
    expect(find.byKey(const ValueKey('claude-meetings')), findsOneWidget);
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
