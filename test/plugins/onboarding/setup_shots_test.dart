// Pictures of the plugins' setups (lib/plugins/onboarding/; Matt, 2026-10-28: "For each of the plugins add a small
// onboarding flow start with the lovart and Claude plugins"), for the eye: written only by `flutter test
// --update-goldens test/plugins/onboarding/setup_shots_test.dart`, into build/feature-shots/plugin-onboarding/ (not
// committed). Every step of Lovart's and Claude's, on a phone and the Mac's window, light and dark; the checks as they
// fail (Lovart's keys refused, Claude's account with no credit); a step in Simple; and the Set up card on each plugin's
// page. Lovart and Anthropic are the test's own: nothing is asked of the network.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/claude/claude.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/onboarding/setup_card.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';

import '../github/support.dart' show useGround;
import '../../settings/support.dart';

const String _out = '../../../build/feature-shots/plugin-onboarding';

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => usePluginGround(PluginGround()));

  const places = [('phone', Size(390, 844), false), ('mac', Size(1280, 800), true)];

  /// The page under the sheet: a plain ground, as the Market's or the plugin page's would be dimmed.
  Future<void> picture(WidgetTester tester, Widget sheet, {required String name, required Size size, required bool mac, required String theme, bool simple = false}) async {
    if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpSettings(tester, sheet, size: size, prefs: Preferences(theme: theme, experience: simple ? 'simple' : 'advanced', experienceChosen: true));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await expectLater(find.byType(GhostApp), matchesGoldenFile('$_out/$name.png'));
    await endSettings(tester);
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> lovartKeys() async {
    await lovart.host.secrets.write(accessKeySecret, 'ak-1');
    await lovart.host.secrets.write(secretKeySecret, 'sk-1');
  }

  for (final (where, size, mac) in places) {
    testWidgets('Lovart’s steps on the $where, light and dark', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      for (final theme in ['light', 'dark']) {
        for (final step in lovartSetup().steps) {
          useGround((request) async => FetchResponse.json(200, {'code': 0, 'data': {}}));
          if (step is SetupCheck || step is SetupDone) await tester.runAsync(lovartKeys);
          final memory = SetupMemory(MemoryStored())..at('lovart', step.id);
          await picture(tester, PluginSetupSheet(key: UniqueKey(), setup: lovartSetup(), memory: memory, onClose: () {}), name: 'lovart-${step.id}-$where-$theme', size: size, mac: mac, theme: theme);
        }
        // The keys refused.
        useGround((request) async => FetchResponse.json(401, const {}));
        await tester.runAsync(lovartKeys);
        await picture(tester, PluginSetupSheet(key: UniqueKey(), setup: lovartSetup(), memory: SetupMemory(MemoryStored())..at('lovart', 'check'), onClose: () {}), name: 'lovart-check-refused-$where-$theme', size: size, mac: mac, theme: theme);
      }
    });

    testWidgets('Claude’s steps on the $where, light and dark', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      for (final theme in ['light', 'dark']) {
        for (final (name, answer) in [('', null), ('-credit', errorOf(429, '{}'))]) {
          for (final step in claudeSetup().steps) {
            if (name.isNotEmpty && step is! SetupCheck) continue;
            final settings = ClaudeSettings(MemorySecureStore());
            if (step is SetupCheck || step is SetupDone) await tester.runAsync(() => settings.setKey('sk-ant-api03-abcdefghijklmnopqrstuvwxyz'));
            final memory = SetupMemory(MemoryStored())..at('claude', step.id);
            final setup = claudeSetup(settings: settings, check: (key) async => answer);
            await picture(tester, PluginSetupSheet(key: UniqueKey(), setup: setup, memory: memory, onClose: () {}), name: 'claude-${step.id}$name-$where-$theme', size: size, mac: mac, theme: theme);
          }
        }
      }
    });
  }

  testWidgets('a step in Simple, and the Set up card on each plugin’s page, on a phone', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    for (final theme in ['light', 'dark']) {
      useGround();
      await picture(tester, PluginSetupSheet(key: UniqueKey(), setup: lovartSetup(), memory: SetupMemory(MemoryStored()), onClose: () {}), name: 'lovart-intro-simple-phone-$theme', size: const Size(390, 844), mac: false, theme: theme, simple: true);
      await picture(tester, SingleChildScrollView(key: UniqueKey(), child: const LovartPane()), name: 'lovart-page-card-phone-$theme', size: const Size(390, 900), mac: false, theme: theme);
      final settings = ClaudeSettings(MemorySecureStore());
      await picture(
        tester,
        SingleChildScrollView(key: UniqueKey(), child: ClaudePane(inApp: ClaudeInApp(settings: settings, phone: false), setup: PluginSetupCard(setup: claudeSetup(settings: settings)))),
        name: 'claude-page-card-phone-$theme',
        size: const Size(390, 900),
        mac: false,
        theme: theme,
      );
    }
  });
}
