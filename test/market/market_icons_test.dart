import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_icons.dart';
import 'package:ghost_md/market/market_items.dart';
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/share/app_links.dart';

import '../settings/panes/support.dart' hide tapOn;

/// The Market's icon packs (lib/market/market_icons.dart; Matt, 2026-10-27: "I would like you to add three icon styles
/// (outline, solid and filled) and add a few different icon packs for the app to choose from"): the Icons shelf with a
/// card for each pack, the style under them, a pack's page with Use this pack, the search finding them, and a link
/// into the Market opening a pack's page.
void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpMarket(WidgetTester tester, {MarketShelf? shelf, MarketPlace? link, Size size = const Size(390, 3000), Preferences prefs = const Preferences(theme: 'light')}) => pumpSettings(
        tester,
        MarketScreen(onBack: () {}, registry: createRegistry(builtIn, store: MemorySwitches()), shelf: shelf, link: link, onPluginSettings: (_) {}, onLocalOnly: () {}),
        size: size,
        prefs: prefs,
      );

  Future<void> tapOn(WidgetTester tester, Finder finder) async {
    final at = finder.first;
    unawaited(Scrollable.ensureVisible(tester.element(at), alignment: 0.5));
    await tester.pump();
    await tester.tap(at);
    await tester.pump();
    await settleSettings(tester);
  }

  Finder card(String id) => find.byKey(ValueKey('market-icons-$id'), skipOffstage: false);

  testWidgets('the Icons shelf has a card for each pack, the one in use ticked, and the style under them', (tester) async {
    await pumpMarket(tester, shelf: MarketShelf.icons, prefs: const Preferences(theme: 'light', iconPack: 'tabler'));
    for (final pack in iconPacks) {
      expect(card(pack.id), findsOneWidget, reason: pack.id);
      // Twelve of the app's icons in each of the three styles, in the pack.
      for (final style in IconStyle.values) {
        final row = find.descendant(of: card(pack.id), matching: find.byKey(ValueKey('icon-preview-${pack.id}-${style.name}'), skipOffstage: false), skipOffstage: false);
        final drawn = tester.widgetList<AppIcon>(find.descendant(of: row, matching: find.byType(AppIcon, skipOffstage: false), skipOffstage: false)).toList();
        expect(drawn, hasLength(iconPreviewNames.length));
        expect(drawn.map((icon) => icon.look), everyElement(IconLook(pack.id, style)));
      }
    }
    MarketIconPackCard cardOf(String id) => tester.widgetList<MarketIconPackCard>(find.byType(MarketIconPackCard, skipOffstage: false)).firstWhere((each) => each.pack.id == id);
    expect(cardOf('tabler').selected, isTrue);
    expect(cardOf('lucide').selected, isFalse);
    expect(find.byKey(const ValueKey('market-icon-style'), skipOffstage: false), findsOneWidget);
    // The band counts the packs.
    expect(tester.widget<Text>(find.byKey(const ValueKey('market-band-count'))).data, endsWith('· 5 icon packs'));

    // The style chosen under the cards is the app's.
    await tapOn(tester, find.descendant(of: find.byKey(const ValueKey('market-icon-style')), matching: find.text('Filled')));
    expect(preferences.value.iconStyle, 'filled');
    expect(find.byKey(const ValueKey('icon-style-preview-tabler-filled'), skipOffstage: false), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('All shows the Icons shelf after the fonts, with the way to all of it', (tester) async {
    await pumpMarket(tester);
    expect(card('phosphor'), findsOneWidget);
    expect(find.text('Icons', skipOffstage: false), findsWidgets);
    await endSettings(tester);
  });

  testWidgets('a pack’s page: Use this pack, the style, all three, how much of the app it draws, whose it is', (tester) async {
    await pumpMarket(tester, shelf: MarketShelf.icons);
    await tapOn(tester, card('phosphor'));
    expect(find.byKey(const ValueKey('market-icons-detail-phosphor')), findsOneWidget);
    expect(find.text('Phosphor'), findsWidgets);
    expect(tester.widget<Text>(find.byKey(const ValueKey('market-icons-coverage'))).data, startsWith('217 of the app’s 228 icons.'));
    expect(find.textContaining('MIT', skipOffstage: false), findsWidgets);

    await tapOn(tester, find.byKey(const ValueKey('market-icons-use-phosphor')));
    expect(preferences.value.iconPack, 'phosphor');
    expect(find.byKey(const ValueKey('market-icons-in-use-phosphor')), findsOneWidget);

    await tapOn(tester, find.descendant(of: find.byKey(const ValueKey('market-icons-detail-phosphor')), matching: find.text('Solid')).first);
    expect(preferences.value.iconStyle, 'solid');
    // The Market's own icons are drawn in it at once: its bar's arrow among them.
    final back = tester.widget<AppIcon>(find.descendant(of: find.byKey(const ValueKey('market-back')), matching: find.byType(AppIcon)));
    expect(back.look, isNull);
    final painter = tester.widget<CustomPaint>(find.descendant(of: find.byKey(const ValueKey('market-back')), matching: find.byType(CustomPaint)).first).painter;
    expect(painter, isA<PackIconPainter>());
    // Back closes the page.
    testBack.goBack();
    await settleSettings(tester);
    expect(find.byKey(const ValueKey('market-icons-detail-phosphor')), findsNothing);
    await endSettings(tester);
  });

  testWidgets('a link opens a pack’s page, and one to a pack this build has not got says so', (tester) async {
    expect(readPlaceLink('ghostmd://market/icons/tabler'), const MarketPlace(kind: MarketKind.icons, id: 'tabler'));
    expect(readPlaceLink('ghostmd://market/icon/tabler'), const MarketPlace(kind: MarketKind.icons, id: 'tabler'));
    expect(const MarketPlace(kind: MarketKind.icons, id: 'remix').toString(), 'ghostmd://market/icons/remix');
    expect(marketLinkLanding(const MarketPlace(kind: MarketKind.icons), plugins: builtIn).shelf, MarketShelf.icons);
    expect(marketLinkLanding(const MarketPlace(id: 'material'), plugins: builtIn).icons, 'material');
    expect(marketLinkLanding(const MarketPlace(kind: MarketKind.icons, id: 'heroicons'), plugins: builtIn).missing, contains('no icon pack called “heroicons”'));

    await pumpMarket(tester, link: const MarketPlace(kind: MarketKind.icons, id: 'tabler'));
    expect(find.byKey(const ValueKey('market-icons-detail-tabler')), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('the search finds a pack by its name, and the word icons finds them all', (tester) async {
    await pumpMarket(tester);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('market-find')), matching: find.byType(EditableText)), 'phosphor');
    await tester.pump();
    await settleSettings(tester);
    expect(card('phosphor'), findsOneWidget);
    expect(card('remix'), findsNothing);
    expect(iconPacks.where((pack) => iconPackFound(pack, 'icons')), hasLength(iconPacks.length));
    await endSettings(tester);
  });
}
