// The more tools in the Market (docs/PM_PLUGINS.md §10): the six together on a shelf of their own, added or not, as the
// project tools are; Google Meet and Zoom, which ship on but stand on Meetings, are not added while it is off, and
// adding either adds Meetings.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_items.dart' show MarketShelf;
import 'package:ghost_md/market/market_plugins.dart';
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/more/more_tools.dart';
import 'package:ghost_md/plugins/registry.dart';

import '../../settings/panes/support.dart' hide tapOn;

void main() {
  setUpAll(loadAppFonts);
  setUp(() => MoreTools.debugAllOn = false);
  tearDown(() => MoreTools.debugAllOn = true);

  Finder shelfOf(String name) => find.byKey(ValueKey('shelf $name'), skipOffstage: false);
  List<String> onShelf(WidgetTester tester, String name) => [
        for (final each in tester.widgetList<MarketPluginCard>(find.descendant(of: shelfOf(name), matching: find.byType(MarketPluginCard, skipOffstage: false), skipOffstage: false))) each.plugin.manifest.id,
      ];

  Future<Registry> pumpMarket(WidgetTester tester, [Map<String, bool>? switches]) async {
    final registry = createRegistry(builtIn, store: MemorySwitches(switches));
    await pumpSettings(
      tester,
      MarketScreen(onBack: () {}, registry: registry, shelf: MarketShelf.plugins, offerSetup: false),
      size: const Size(390, 6000),
      prefs: const Preferences(theme: 'light'),
    );
    return registry;
  }

  testWidgets('the six are on More tools, added or not, and on no other shelf', (tester) async {
    await pumpMarket(tester, {canvasTool: true});
    expect(onShelf(tester, 'more tools'), moreTools);
    for (final id in moreTools) {
      expect(onShelf(tester, 'added'), isNot(contains(id)));
      expect(onShelf(tester, 'discover'), isNot(contains(id)));
    }
    final canvas = tester.widgetList<MarketPluginCard>(find.byType(MarketPluginCard, skipOffstage: false)).firstWhere((card) => card.plugin.manifest.id == canvasTool);
    expect(canvas.added, isTrue);
    await endSettings(tester);
  });

  testWidgets('Google Meet is not added while Meetings is off, and its Add adds Meetings', (tester) async {
    final registry = await pumpMarket(tester);
    expect(onShelf(tester, 'added'), isNot(contains('google-meet')));
    expect(onShelf(tester, 'discover'), contains('google-meet'));
    final add = find.byKey(const ValueKey('market-add-google-meet'), skipOffstage: false);
    unawaited(Scrollable.ensureVisible(tester.element(add.first), alignment: 0.5));
    await tester.pump();
    await tester.tap(add.first);
    await tester.pump();
    await settleSettings(tester);
    expect(registry.isEnabled(meetingsTool), isTrue);
    expect(registry.isEnabled('google-meet'), isTrue);
    expect(onShelf(tester, 'added'), contains('google-meet'));
    await endSettings(tester);
  });
}
