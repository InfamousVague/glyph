import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/kit/settings_kit.dart' show SettingsFindableMark;
import 'package:ghost_messaging/looks.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides;
import 'package:ghost_messaging/market/listing_plugin.dart';
import 'package:ghost_messaging/market/market_api.dart';
import 'package:ghost_messaging/market/market_state.dart';
import 'package:ghost_messaging/me/me.dart';
import 'package:ghost_messaging/plugins/pack/pack.dart';
import 'package:ghost_messaging/plugins/registry.dart';
import 'package:ghost_messaging/ui/conversations.dart';
import 'package:ghost_messaging/ui/market/marketplace_screen.dart';
import 'package:ghost_messaging/ui/nav_bar.dart';
import 'package:ghost_messaging/ui/nav_style.dart';
import 'package:ghost_messaging/ui/plugins_page/plugins_page.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:ghost_messaging/ui/shell.dart';
import 'package:glacier/glacier.dart';

import 'support/list_harness.dart';
import 'support/market_fakes.dart';

/// The Marketplace's ring and its place in the frame (lib/ui/shell.dart, lib/ui/market/marketplace_screen.dart; Matt,
/// 2026-11-20: "Move plugins out of settings into a marketplace button on the navigation rail with a marketplace
/// icon"): the ring in every navigation, its list in the list's place with Discover beside it or its rows' pages over
/// it, the sections offered as the device and its choices stand, the way it and Settings, Archive and Messages give way
/// to each other, and Settings' plugins found and opened in it.
Finder _key(String k) => find.byKey(ValueKey(k));

const _phone = Size(412, 892), _wide = Size(1000, 760);

void main() {
  late Directory dir;
  late FakeChecks checks;
  late FakeInstalled installed;
  late FakeRelay relay;
  late MarketState market;
  late AppState state;
  final oldInstalled = InstalledPlugins.instance, oldMarket = MarketState.instance, oldRegistry = PluginRegistry.instance;

  setUp(() {
    ListPhone([
      ListPhone.conversation(1, '+15551230001', 'See you at 7', name: 'Maya Chen'),
      ListPhone.conversation(2, '+15551230002', 'The build is out', name: 'Sam Ortiz', archived: true),
    ]).install();
    dir = Directory.systemTemp.createTempSync('marketplace-');
    checks = FakeChecks();
    PluginRegistry.instance = PluginRegistry(shippedPlugins);
    installed = FakeInstalled(root: Directory('${dir.path}/plugins'), checks: checks);
    InstalledPlugins.instance = installed;
    relay = FakeRelay();
    market = marketOver(relay, installed, checks, Directory('${dir.path}/market'));
    MarketState.instance = market;
    state = AppState();
    installed.switches = AppStore(state);
  });
  tearDown(() {
    InstalledPlugins.instance = oldInstalled;
    MarketState.instance = oldMarket;
    PluginRegistry.instance = oldRegistry;
    dir.deleteSync(recursive: true);
  });

  AppShellState shell() => AppShellState.live!;

  Future<void> frame(WidgetTester tester, {Size size = _phone, NavStyle style = NavStyle.rail}) async {
    state.set(NavStyle.pref, style.name);
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const AppShell(), state, size: size);
  }

  testWidgets('the ring: between Archive and Settings on the rail, in the dock and classic pills, "Market" on Dial-Up\'s taskbar', (tester) async {
    await frame(tester);
    final archive = tester.getTopLeft(_key('rail-archive')).dy, ring = tester.getTopLeft(_key('rail-marketplace')).dy, settings = tester.getTopLeft(_key('rail-settings')).dy;
    expect(ring, greaterThan(archive));
    expect(ring, lessThan(settings));
    for (final style in [NavStyle.dock, NavStyle.classic]) {
      await frame(tester, style: style);
      expect(_key('nav-marketplace'), findsOneWidget, reason: style.name);
      expect(tester.widget<NavPill>(find.byType(NavPill)).items.map((i) => i.id), ['new', 'messages', 'contacts', 'archive', 'marketplace', 'settings']);
    }
    // Dial-Up's taskbar: six buttons, the Marketplace's said short.
    state.setLook(Look.dialup);
    await frame(tester, style: NavStyle.classic);
    expect(find.text('Market'), findsOneWidget);
  });

  testWidgets('the ring counts the updates waiting', (tester) async {
    installed.putStore(billsPack());
    final newer = billsPack(version: '1.1.0');
    market.debugListings = [ListingPlugin(entryOf(newer), newer, market)];
    await frame(tester);
    expect(tester.widget<NavRing>(_key('rail-marketplace')).item.count, 1);
    market.debugListings = const [];
    await settle(tester);
    expect(tester.widget<NavRing>(_key('rail-marketplace')).item.count, 0);
  });

  testWidgets('wide: its list in the list\'s place, Discover beside it, the ring lit, no band or search in the list', (tester) async {
    await frame(tester, size: _wide);
    await tester.tap(_key('rail-marketplace'));
    await settle(tester);
    expect(find.byType(MarketplaceScreen), findsOneWidget);
    expect(shell().marketOpen, isTrue);
    expect(shell().marketSection.value, 'discover');
    final discover = find.byWidgetPredicate((w) => w is PluginsPage && w.title == 'Discover');
    expect(discover, findsOneWidget);
    expect(tester.getRect(discover).left, greaterThanOrEqualTo(tester.getRect(find.byType(MarketplaceScreen)).right - 1), reason: 'beside the list, not over it');
    expect(tester.widget<NavRing>(_key('rail-marketplace')).shown, isTrue);
    expect(_key('plugins-entry'), findsNothing, reason: 'Discover beside it has the band');
    expect(_key('market-search'), findsNothing);
    expect(tester.widget<SettingsSectionRow>(_key('market-row-discover')).selected, isTrue);
    // A row's page takes the pane's place.
    await tester.tap(_key('market-row-added'));
    await settle(tester);
    expect(shell().marketSection.value, 'added');
    expect(find.byWidgetPredicate((w) => w is PluginsPage && w.title == 'Added'), findsOneWidget);
  });

  testWidgets('a phone: the list alone with the band and the search; a row\'s page over it, and back', (tester) async {
    await frame(tester);
    await tester.tap(_key('rail-marketplace'));
    await settle(tester);
    expect(find.byType(MarketplaceScreen), findsOneWidget);
    expect(_key('plugins-entry'), findsOneWidget);
    expect(_key('market-search'), findsOneWidget);
    expect(shell().marketSection.value, isNull, reason: 'on a phone it opens on its list');
    await tester.tap(_key('market-row-added'));
    await settle(tester);
    expect(find.byWidgetPredicate((w) => w is PluginsPage && w.title == 'Added'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back').last);
    await settle(tester);
    expect(find.byWidgetPredicate((w) => w is PluginsPage && w.title == 'Added'), findsNothing);
    expect(find.byType(MarketplaceScreen), findsOneWidget);
    // The band opens Discover.
    await tester.tap(_key('plugins-entry'));
    await settle(tester);
    expect(shell().marketSection.value, 'discover');
    await tester.tap(find.bySemanticsLabel('Back').last);
    await settle(tester);
    // Its search finds a section by its words.
    await tester.enterText(find.descendant(of: _key('market-search'), matching: find.byType(EditableText)), 'submit');
    await settle(tester);
    expect(_key('market-row-submit'), findsOneWidget);
    expect(_key('market-row-discover'), findsNothing);
    expect(_key('plugins-entry'), findsNothing);
    // And plugins, by name, tag or who made them: a listing among them, opening Discover at its page.
    final listing = billsPack();
    market.debugListings = [ListingPlugin(entryOf(listing), listing, market)];
    await tester.enterText(find.descendant(of: _key('market-search'), matching: find.byType(EditableText)), 'maya');
    await settle(tester);
    expect(_key('market-hit-xbills'), findsOneWidget);
    await tester.tap(_key('market-hit-xbills'));
    await settle(tester);
    await settle(tester);
    expect(_key('plugins-detail-xbills'), findsOneWidget);
    expect(_key('plugins-detail-reviewed'), findsOneWidget);
  });

  testWidgets('opened on a phone and widened, Discover is beside it', (tester) async {
    await frame(tester);
    shell().go('marketplace');
    await settle(tester);
    expect(shell().marketSection.value, isNull);
    tester.view.physicalSize = _wide * 2.0;
    await settle(tester);
    await settle(tester);
    expect(shell().marketSection.value, 'discover', reason: 'unfolding never leaves the pane empty');
    expect(find.byWidgetPredicate((w) => w is PluginsPage && w.title == 'Discover'), findsOneWidget);
  });

  testWidgets('In development only in developer mode; the Review queue only for the admin with an identity', (tester) async {
    await frame(tester, size: _wide);
    shell().marketplace();
    await settle(tester);
    expect(_key('market-row-dev'), findsNothing);
    expect(_key('market-row-review'), findsNothing);
    state.setFlag('dev_mode', true);
    await settle(tester);
    expect(_key('market-row-dev'), findsOneWidget);
    expect(_key('market-row-review'), findsNothing, reason: 'not the admin');
    await tester.runAsync(() => Me.instance.start(MemoryMeStore()..set('me_username', 'matt'), ValueNotifier(0), () => null));
    addTearDown(() => tester.runAsync(() => Me.instance.start(MemoryMeStore(), ValueNotifier(0), () => null)));
    await settle(tester);
    expect(_key('market-row-review'), findsOneWidget);
    expect(marketOffered('review', state), isTrue);
    // A computer that follows its phone has no identity of its own: no review from there.
    MarketState.instance = MarketState(api: () => MarketApi(hubUrl: 'https://relay.test', transport: relay.call), installed: installed, cache: dir);
    expect(marketOffered('review', state), isFalse);
    // Developer mode off: In development goes, and its page with it.
    MarketState.instance = market;
    shell().marketplace(section: 'dev');
    await settle(tester);
    expect(_key('market-dev-manage'), findsOneWidget);
    state.setFlag('dev_mode', false);
    await settle(tester);
    await settle(tester);
    expect(_key('market-row-dev'), findsNothing);
    expect(_key('market-dev-manage'), findsNothing);
    expect(shell().marketSection.value, 'discover', reason: 'beside the list Discover takes its place');
  });

  testWidgets('no Make your own on an iPhone, nor anything from other developers', (tester) async {
    InstalledPlugins.instance = FakeInstalled(root: Directory('${dir.path}/ios'), checks: checks, storeAllowed: false);
    state.setFlag('dev_mode', true);
    await frame(tester);
    shell().marketplace();
    await settle(tester);
    for (final k in ['market-row-submit', 'market-row-mine', 'market-row-dev', 'market-docs']) {
      expect(_key(k), findsNothing, reason: k);
    }
    expect(find.text('MAKE YOUR OWN'), findsNothing);
    expect(_key('market-row-discover'), findsOneWidget);
  });

  testWidgets('Messages closes it; Settings and the Marketplace close each other', (tester) async {
    await frame(tester, size: _wide);
    await tester.tap(_key('rail-marketplace'));
    await settle(tester);
    await tester.tap(_key('rail-home'));
    await settle(tester);
    expect(shell().marketOpen, isFalse);
    expect(find.byType(MarketplaceScreen), findsNothing);
    await tester.tap(_key('rail-marketplace'));
    await settle(tester);
    await tester.tap(_key('rail-settings'));
    await settle(tester);
    expect(shell().settingsOpen, isTrue);
    expect(shell().marketOpen, isFalse);
    expect(find.byType(MarketplaceScreen), findsNothing);
    await tester.tap(_key('rail-marketplace'));
    await settle(tester);
    expect(shell().marketOpen, isTrue);
    expect(shell().settingsOpen, isFalse);
    expect(find.byType(SettingsScreen), findsNothing);
    // Beside its page, back leaves it whole.
    expect(shell().marketSection.value, 'discover');
  });

  testWidgets('Archive, then the Marketplace, then Archive again is Archive', (tester) async {
    await frame(tester);
    await tester.tap(_key('rail-archive'));
    await settle(tester);
    await tester.tap(_key('rail-marketplace'));
    await settle(tester);
    expect(shell().marketOpen, isTrue);
    await tester.tap(_key('rail-archive'));
    await settle(tester);
    expect(shell().marketOpen, isFalse);
    expect(find.byWidgetPredicate((w) => w is ConversationsScreen && w.archived).hitTestable(), findsOneWidget);
    expect(find.byType(MarketplaceScreen), findsNothing);
    expect(tester.widget<NavRing>(_key('rail-archive')).shown, isTrue);
    expect(tester.widget<NavRing>(_key('rail-marketplace')).shown, isFalse);
  });

  testWidgets('in the classic style on a phone the pill goes under the Marketplace, as under Settings', (tester) async {
    await frame(tester, style: NavStyle.classic);
    final opacity = find.ancestor(of: find.byType(NavPill), matching: find.byType(AnimatedOpacity)).first;
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
    await tester.tap(_key('nav-marketplace'));
    await settle(tester);
    expect(shell().marketOpen, isTrue);
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
  });

  testWidgets('Settings › Plugins and a plugin\'s own section open Discover at it, from a link or the API', (tester) async {
    await frame(tester);
    // ui.openSettings('plugin-spam'), and any old link to it.
    shell().settings('plugin-spam');
    await settle(tester);
    await settle(tester);
    expect(shell().marketOpen, isTrue);
    expect(shell().settingsOpen, isFalse);
    expect(shell().marketSection.value, 'discover');
    expect(_key('plugins-detail-spam'), findsOneWidget);
    shell().go('messages');
    await settle(tester);
    // ui.openSettings('plugins'): Discover itself.
    shell().settings('plugins');
    await settle(tester);
    expect(shell().marketOpen, isTrue);
    expect(shell().marketSection.value, 'discover');
    expect(find.byWidgetPredicate((w) => w is PluginsPage && w.title == 'Discover'), findsOneWidget);
  });

  testWidgets('asked for before the first frame, it opens once there is a frame', (tester) async {
    final sheet = await loadSheet(tester);
    state.set(NavStyle.pref, NavStyle.rail.name);
    tester.view.physicalSize = _phone * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    // Built and not yet laid out: the frame's list is made as it is laid out, so there is no list to open it in.
    await tester.pumpWidget(_app(sheet, state, const AppShell()), phase: EnginePhase.build);
    shell().settings('plugin-spam');
    expect(shell().marketOpen, isFalse, reason: 'held until there is a list to open it in');
    await settle(tester);
    await settle(tester);
    expect(shell().marketOpen, isTrue);
    expect(_key('plugins-detail-spam'), findsOneWidget);
  });

  testWidgets('a Settings search hit for a plugin\'s setting opens the Marketplace at it', (tester) async {
    await frame(tester, size: _wide);
    await tester.tap(_key('rail-settings'));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).first, 'link previews');
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(SettingsScreen), matching: find.text('Link previews')).first);
    await settle(tester);
    await settle(tester);
    expect(shell().marketOpen, isTrue);
    expect(shell().settingsOpen, isFalse);
    expect(shell().marketSection.value, 'discover');
    expect(_key('plugins-detail-embeds'), findsOneWidget);
  });

  testWidgets('at 412x892: a hit in Plugins\' own rows opens its plugin; a pack\'s setting opens its page with the row lit', (tester) async {
    await frame(tester);
    Future<void> search(String words, String hit) async {
      await tester.tap(_key('rail-settings'));
      await settle(tester);
      await tester.enterText(find.byType(EditableText).first, words);
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(SettingsScreen), matching: find.text(hit)).first);
      await settle(tester);
      await settle(tester);
    }

    await search('watch together', 'Watch together');
    expect(shell().marketOpen, isTrue);
    expect(_key('plugins-detail-watch'), findsOneWidget);
    shell().go('messages');
    await settle(tester);
    // Bills, added from the Marketplace: its own settings are in the unlisted Plugins section Settings' search reads.
    installed.putStore(billsPack());
    await settle(tester);
    await search('more words for bills', 'More words for bills');
    expect(_key('plugins-detail-xbills'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    final lit = [for (final e in find.byKey(SettingsFindableMark.lightKey).evaluate()) SettingsFindableMark.isLit(e.widget)];
    expect(lit, contains(true), reason: 'the row the search found is lit');
  });

  testWidgets('beside Settings the first section is Me, now that Plugins is the Marketplace\'s', (tester) async {
    await frame(tester, size: _wide);
    await tester.tap(_key('rail-settings'));
    await settle(tester);
    expect(shell().settingsSection.value, 'me');
    expect(find.byType(PluginsPage), findsNothing);
  });

  testWidgets('the ring\'s menu: its sections offered now', (tester) async {
    state.setFlag('dev_mode', true);
    await frame(tester, size: _wide);
    await tester.tap(_key('rail-marketplace'), buttons: 2);
    await settle(tester);
    for (final label in ['Discover', 'Added', 'Submit a plugin', 'My submissions', 'In development']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Updates'), findsNothing, reason: 'none waiting');
  });

  testWidgets('Submit with a dev pack, and My submissions at a submission, slot in with their screens', (tester) async {}, skip: true); // Submit a plugin and My submissions (SPEC D.8, D.9) are part 2's: their screens and this check come with them.
}

/// The app's tree as pumpScreen (test/support/list_harness.dart) makes it, to pump only part of a frame.
Widget _app(TokenSheet sheet, AppState state, Widget screen) => AppScope(
      state: state,
      child: WidgetsApp(
        color: const Color(0xFF4F5BD5),
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
        builder: (context, child) => GlacierTheme(
          sheet: sheet,
          attrs: {'theme': 'light', ...ghostAttrs(state, 'mobile')},
          child: InkOverrides(child: GlacierToastProvider(child: child!)),
        ),
        home: screen,
      ),
    );
