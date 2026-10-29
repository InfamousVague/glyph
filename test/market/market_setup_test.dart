// A plugin's setup, offered as it is added in the Market (lib/market/market_screen.dart `_add`; lib/plugins/onboarding/;
// Matt, 2026-10-28: "For each of the plugins add a small onboarding flow start with the lovart and Claude plugins walk
// the user through setting up an account and getting their keys"): Lovart added with no keys opens its setup at once,
// from its card or its page; with its keys already kept (from another device), or a plugin with no setup, nothing
// opens; Skip puts it away and the plugin stays added. Over the plugins that ship, in a registry of the test's own,
// and a plugins' ground of the test's own: nothing is asked of the network.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';
import 'package:ghost_md/plugins/registry.dart';

import '../plugins/github/support.dart' show TestGround, useGround;
import '../settings/panes/support.dart' hide tapOn;

void main() {
  setUpAll(loadAppFonts);

  late TestGround ground;
  setUp(() => ground = useGround());
  tearDown(() => usePluginGround(PluginGround()));

  Registry shipped() => createRegistry(builtIn, store: MemorySwitches(), localOnly: () => preferences.value.localOnly);

  Future<Registry> pumpMarket(WidgetTester tester, {bool offer = true, String? plugin}) async {
    final registry = shipped();
    await pumpSettings(tester, MarketScreen(onBack: () {}, registry: registry, plugin: plugin, offerSetup: offer), size: const Size(390, 3000), prefs: const Preferences(theme: 'light'));
    return registry;
  }

  Future<void> press(WidgetTester tester, Finder finder) async {
    unawaited(Scrollable.ensureVisible(tester.element(finder.first), alignment: 0.5));
    await tester.pump();
    await tester.tap(finder.first);
    await tester.pump();
    await settleSettings(tester);
  }

  Finder addOn(String id) => find.descendant(of: find.byKey(ValueKey('market-plugin-$id'), skipOffstage: false), matching: find.byKey(ValueKey('market-add-$id')));

  testWidgets('Lovart added with no keys opens its setup at once; Skip puts it away, Lovart still added', (tester) async {
    final registry = await pumpMarket(tester);
    expect(find.byType(PluginSetupSheet), findsNothing);
    await press(tester, addOn('lovart'));
    expect(registry.switchedOn('lovart'), isTrue);
    expect(find.byType(PluginSetupSheet), findsOneWidget);
    expect(find.text('Images by Lovart'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('setup-skip')));
    await settleSettings(tester);
    expect(find.byType(PluginSetupSheet), findsNothing);
    expect(registry.switchedOn('lovart'), isTrue);
    await endSettings(tester);
  });

  testWidgets('from a plugin’s own page, Add to Ghost.md opens it too', (tester) async {
    await pumpMarket(tester, plugin: 'lovart');
    await press(tester, find.byKey(const ValueKey('market-add-lovart')));
    expect(find.byType(PluginSetupSheet), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('with its keys already kept, or with no setup, nothing opens', (tester) async {
    await ground.secrets.write(lovart.accessKeySecret, 'ak-1');
    await ground.secrets.write(lovart.secretKeySecret, 'sk-1');
    final registry = await pumpMarket(tester);
    await press(tester, addOn('lovart'));
    expect(registry.switchedOn('lovart'), isTrue);
    expect(find.byType(PluginSetupSheet), findsNothing);
    // Webhooks has nothing to set up (test/plugins/onboarding/plugin_setups_test.dart); Slack, which this was, has a
    // setup since Matt's 2026-10-29 "add the voiceover onboarding for the rest of the plugins".
    await press(tester, addOn('webhooks'));
    expect(registry.switchedOn('webhooks'), isTrue);
    expect(find.byType(PluginSetupSheet), findsNothing);
    await endSettings(tester);
  });

  testWidgets('a Market told not to offer one opens nothing', (tester) async {
    await pumpMarket(tester, offer: false);
    await press(tester, addOn('lovart'));
    expect(find.byType(PluginSetupSheet), findsNothing);
    await endSettings(tester);
  });
}
