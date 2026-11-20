import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/art/app_icon.dart';
import 'package:ghost_messaging/market/listing_plugin.dart';
import 'package:ghost_messaging/market/market_models.dart';
import 'package:ghost_messaging/market/market_state.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/plugins/codes.dart';
import 'package:ghost_messaging/plugins/pack/pack.dart';
import 'package:ghost_messaging/plugins/registry.dart';
import 'package:ghost_messaging/plugins/settings.dart';
import 'package:ghost_messaging/plugins/spam.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/ui/market/market_flows.dart';
import 'package:ghost_messaging/ui/plugins_page/plugin_art.dart';

import 'support/list_harness.dart';
import 'support/market_fakes.dart';

/// Discover, Added and In development with plugins from other developers (lib/ui/plugins_page; Matt, 2026-11-20: "I
/// would like users to be able to develop and submit their own plugins to our plugin marketplace and I'd like to be able
/// to verify them for the store through a review process"): a checked listing's card and page drawn from its package,
/// adding it after its consent sheet, the chips and shelves for packs, a store pack's Remove, a stuck pack's words,
/// Updates, a new developer, a computer with no texts, an iPhone, the catalog's lines, pictures and screenshots.
Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  late Directory dir;
  late FakeChecks checks;
  late FakeInstalled installed;
  late FakeRelay relay;
  late MarketState market;
  late AppState state;
  final oldInstalled = InstalledPlugins.instance, oldMarket = MarketState.instance, oldRegistry = PluginRegistry.instance;

  setUp(() {
    ListPhone(const []).install();
    dir = Directory.systemTemp.createTempSync('market-discover-');
    checks = FakeChecks();
    PluginRegistry.instance = PluginRegistry(const [CodesPlugin(), SpamPlugin()]);
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
    Sms.standalone = false;
    dir.deleteSync(recursive: true);
  });

  /// Lists [packs] on the relay and has the Marketplace check them, as a refresh does (real I/O, outside the fake clock).
  Future<void> listed(WidgetTester tester, List<PluginPack> packs, {Map<String, CatalogEntry> entries = const {}}) async {
    for (final p in packs) {
      checks.know(p);
      relay.list(p, entry: entries[p.id]);
    }
    await tester.runAsync(() => market.refresh(force: true));
  }

  Future<void> page(WidgetTester tester, Widget screen, {Size size = const Size(412, 892)}) async {
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, screen, state, size: size);
  }

  testWidgets('a checked listing\'s card: drawn from its package, Reviewed, its tags; an unchecked entry isn\'t shown', (tester) async {
    final bills = billsPack();
    final forged = billsPack(id: 'receipts', name: 'Receipts');
    await listed(tester, [bills, forged], entries: {'receipts': entryOf(forged, sig: 'forged')});
    await page(tester, marketPluginsScreen());
    final card = _key('plugins-card-xbills');
    await tester.ensureVisible(card);
    await settle(tester);
    // Its name, and its first tag (Bills) on its source line with the second (Money).
    expect(find.descendant(of: card, matching: find.text('Bills')), findsNWidgets(2));
    expect(find.descendant(of: card, matching: find.textContaining('By @maya')), findsOneWidget);
    expect(_key('plugins-reviewed-xbills'), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Money')), findsOneWidget, reason: 'its tags on its source line');
    expect(find.descendant(of: card, matching: find.text('Sorting')), findsNothing, reason: 'two tags at most');
    expect(_key('plugins-card-xreceipts'), findsNothing, reason: 'its approval didn\'t verify');
    // In More to add, not Added: a leftover switch never makes a listing read as added.
    state.set('plugin_xbills', 'on');
    await settle(tester);
    expect(find.descendant(of: _key('plugins-shelf-discover'), matching: card), findsOneWidget);
    expect(find.text('More to add'), findsOneWidget);
  });

  testWidgets('the consent sheet is the package\'s own lines; Add installs it, it moves to Added, and the toast names its tab', (tester) async {
    await listed(tester, [billsPack()]);
    await page(tester, marketPluginsScreen());
    await tester.ensureVisible(_key('plugins-add-xbills'));
    await settle(tester);
    await tester.tap(_key('plugins-add-xbills'));
    await settle(tester);
    final consent = _key('market-consent');
    expect(consent, findsOneWidget);
    for (final line in ['By @maya', 'Reviewed by Ghost Messaging', 'Reads texts from numbers not in your contacts', 'Sorts texts into its own tabs and kinds', 'Copies to your clipboard when you ask', 'It adds:', 'A Bills tab in the list', 'A kind in the list\'s filter: Receipts']) {
      expect(find.descendant(of: consent, matching: find.text(line)), findsOneWidget, reason: line);
    }
    expect(_key('market-consent-dev'), findsNothing);
    await tester.ensureVisible(find.text('Add Bills'));
    await settle(tester);
    await tester.tap(find.text('Add Bills'));
    await settle(tester);
    expect(installed.installs.single.on, isTrue);
    expect(installed.installs.single.bytes, packBytes(billsPack()), reason: 'the bytes that were checked');
    expect(find.text('Bills added. Its Bills tab is in Messages.'), findsOneWidget);
    await tester.ensureVisible(_key('plugins-shelf-added'));
    await settle(tester);
    expect(find.descendant(of: _key('plugins-shelf-added'), matching: _key('plugins-card-xbills')), findsOneWidget);
    expect(_key('plugins-added-xbills'), findsOneWidget);
  });

  testWidgets('a listing that needs a newer app, and one on a computer with no texts, can\'t be added, and say why', (tester) async {
    await listed(tester, [billsPack(minApp: '9.0.0')]);
    expect(market.listings.single.needsNewerApp, isTrue);
    await page(tester, marketPluginsScreen(open: 'xbills'));
    expect(_key('plugins-detail-xbills'), findsOneWidget);
    expect(find.text('Needs a newer Ghost Messaging'), findsOneWidget);
    await tester.tap(find.descendant(of: _key('plugins-detail-xbills'), matching: _key('plugins-add-xbills')), warnIfMissed: false);
    await settle(tester);
    expect(_key('market-consent'), findsNothing);
    // A computer of its own, with no phone's texts.
    Sms.standalone = true;
    final fine = billsPack(id: 'parcels', name: 'Parcels');
    await listed(tester, [fine]);
    await page(tester, marketPluginsScreen(open: 'xparcels'));
    expect(_key('plugins-detail-nohere'), findsOneWidget);
    expect(find.text(marketNoTextsWords), findsWidgets);
    await tester.tap(find.descendant(of: _key('plugins-detail-xparcels'), matching: _key('plugins-add-xparcels')), warnIfMissed: false);
    await settle(tester);
    expect(_key('market-consent'), findsNothing);
  });

  testWidgets('From developers and In development chips; Added and In development alone, and their empty words', (tester) async {
    await listed(tester, [billsPack()]);
    await page(tester, marketPluginsScreen());
    expect(_key('plugins-chip-store'), findsOneWidget);
    expect(_key('plugins-chip-dev'), findsNothing);
    await tester.ensureVisible(_key('plugins-chip-store'));
    await settle(tester);
    await tester.tap(_key('plugins-chip-store'));
    await settle(tester);
    expect(find.descendant(of: _key('plugins-shelf-store'), matching: _key('plugins-card-xbills')), findsOneWidget);
    expect(find.descendant(of: _key('plugins-shelf-store'), matching: _key('plugins-card-codes')), findsNothing);
    installed.putDev(billsPack(id: 'tickets', name: 'Tickets'));
    await settle(tester);
    expect(_key('plugins-chip-dev'), findsOneWidget);
    await tester.ensureVisible(_key('plugins-chip-dev'));
    await settle(tester);
    await tester.tap(_key('plugins-chip-dev'));
    await settle(tester);
    expect(find.descendant(of: _key('plugins-shelf-dev'), matching: _key('plugins-card-xtickets')), findsOneWidget);
    expect(_key('plugins-dev-xtickets'), findsOneWidget);
    // In development alone: the dev packs, no band, no chips, no search.
    await page(tester, marketPluginsScreen(title: 'In development', shelf: 'dev', head: false));
    expect(find.descendant(of: _key('plugins-shelf-dev'), matching: _key('plugins-card-xtickets')), findsOneWidget);
    expect(_key('plugins-chips'), findsNothing);
    expect(_key('plugins-search'), findsNothing);
    await installed.removeDev('tickets');
    await settle(tester);
    expect(find.text('Nothing loaded yet. Load one in Settings › Developer › Plugins in development.'), findsOneWidget);
    expect(find.text('Show every plugin'), findsNothing);
    // Added alone, with nothing on.
    state
      ..setFlag('plugin_codes', false)
      ..setFlag('plugin_spam', false);
    await page(tester, marketPluginsScreen(title: 'Added', shelf: 'added', head: false));
    expect(find.text('Nothing added yet.'), findsOneWidget);
    expect(_key('plugins-card-xbills'), findsNothing, reason: 'a listing isn\'t added');
  });

  testWidgets('search finds a plugin by who made it and by its tag', (tester) async {
    await listed(tester, [billsPack()]);
    await page(tester, marketPluginsScreen());
    Future<void> search(String words) async {
      await tester.enterText(find.descendant(of: _key('plugins-search'), matching: find.byType(EditableText)), words);
      await settle(tester);
    }

    await search('maya');
    expect(find.descendant(of: _key('plugins-shelf-found'), matching: _key('plugins-card-xbills')), findsOneWidget);
    expect(find.descendant(of: _key('plugins-shelf-found'), matching: _key('plugins-card-codes')), findsNothing);
    await search('money');
    expect(find.descendant(of: _key('plugins-shelf-found'), matching: _key('plugins-card-xbills')), findsOneWidget);
    await search('nobody');
    expect(find.text('Nothing called “nobody”.'), findsOneWidget);
  });

  testWidgets('a tag pressed on a plugin\'s page searches for it', (tester) async {
    await listed(tester, [billsPack()]);
    await page(tester, marketPluginsScreen(open: 'xbills'), size: const Size(1180, 860));
    await tester.tap(_key('plugins-detail-label-money'));
    await settle(tester);
    expect(_key('plugins-shelf-found'), findsOneWidget);
    expect(find.descendant(of: _key('plugins-shelf-found'), matching: _key('plugins-card-xbills')), findsOneWidget);
  });

  testWidgets('a store pack\'s page: Reviewed by Ghost Messaging; Remove asks, then removes', (tester) async {
    installed.putStore(billsPack(support: 'help@example.com'));
    await page(tester, marketPluginsScreen(open: 'xbills'));
    expect(_key('plugins-detail-xbills'), findsOneWidget);
    expect(tester.widget<Text>(_key('plugins-detail-source')).data, 'By @maya\nReviewed by Ghost Messaging');
    expect(_key('plugins-detail-reviewed'), findsOneWidget);
    expect(_key('plugins-detail-dev'), findsNothing);
    expect(find.text('Built-in plugins sort first: a text Codes, Spam filter or a kind of Kinds of text takes stays theirs.'), findsOneWidget);
    expect(_key('plugins-report-xbills'), findsOneWidget);
    // Its help, an email address, is copied.
    await tester.ensureVisible(_key('plugins-detail-support'));
    await settle(tester);
    await tester.tap(find.descendant(of: _key('plugins-detail-support'), matching: find.text('help@example.com')));
    await settle(tester);
    expect(find.text('Address copied'), findsOneWidget);
    await tester.ensureVisible(find.descendant(of: _key('plugins-detail-xbills'), matching: _key('plugins-remove-xbills')));
    await settle(tester);
    await tester.tap(find.descendant(of: _key('plugins-detail-xbills'), matching: _key('plugins-remove-xbills')));
    await settle(tester);
    expect(_key('market-remove-confirm'), findsOneWidget);
    expect(installed.calls, isEmpty, reason: 'asks first');
    await tester.ensureVisible(find.text('Remove Bills'));
    await settle(tester);
    await tester.tap(find.text('Remove Bills'));
    await settle(tester);
    expect(installed.calls, ['removeStore bills']);
  });

  testWidgets('a withdrawn pack and one whose key isn\'t trusted show on Added as stuck, with their words, and go with Remove', (tester) async {
    final why = PackRevocation(plugin: 'bills', sha256: sha256Hex(packBytes(billsPack())), at: 1, why: 'It copied texts it shouldn\'t have', key: reviewKey, sig: 'x');
    installed.putStore(billsPack(), running: false, problem: 'revoked', revoked: why);
    installed.putStore(billsPack(id: 'parcels', name: 'Parcels'), running: false, problem: 'untrusted_key');
    await page(tester, marketPluginsScreen(title: 'Added', shelf: 'added', head: false));
    final stuck = _key('plugins-shelf-stuck');
    expect(find.descendant(of: stuck, matching: _key('plugins-card-xbills')), findsOneWidget);
    expect(find.descendant(of: stuck, matching: _key('plugins-card-xparcels')), findsOneWidget);
    expect(find.descendant(of: _key('plugins-problem-xbills'), matching: find.text('Withdrawn')), findsOneWidget);
    expect(find.descendant(of: _key('plugins-problem-xparcels'), matching: find.text('Not working')), findsOneWidget);
    expect(_key('plugins-add-xbills'), findsNothing, reason: 'nothing to add: its page has Remove');
    await tester.tap(_key('plugins-card-xbills'));
    await settle(tester);
    expect(find.descendant(of: _key('plugins-detail-withdrawn'), matching: find.text('Withdrawn from the Marketplace: It copied texts it shouldn\'t have. It\'s off, and does nothing until you remove it.')), findsOneWidget);
    expect(_key('plugins-report-xbills'), findsNothing);
    await tester.tap(find.descendant(of: _key('plugins-detail-xbills'), matching: _key('plugins-remove-xbills')));
    await settle(tester);
    await tester.ensureVisible(find.text('Remove Bills'));
    await settle(tester);
    await tester.tap(find.text('Remove Bills'));
    await settle(tester);
    expect(installed.calls, ['removeStore bills']);
    await page(tester, marketPluginsScreen(open: 'xparcels'));
    expect(find.descendant(of: _key('plugins-detail-withdrawn'), matching: find.text('This version of Ghost Messaging can\'t check its review, so it\'s off. An update may fix it.')), findsOneWidget);
  });

  testWidgets('Updates: Update replaces it keeping the switch off; where it can do more, it asks first, the new host shown', (tester) async {
    installed.putStore(billsPack(), on: false);
    await listed(tester, [billsPack(version: '1.1.0', whatsNew: 'Faster.')]);
    expect(market.updates, hasLength(1));
    await page(tester, const MarketUpdatesPage());
    expect(_key('market-update-bills'), findsOneWidget);
    expect(find.textContaining('1.0.0 → 1.1.0'), findsOneWidget);
    await tester.tap(find.descendant(of: _key('market-update-bills'), matching: find.text('Update')));
    await settle(tester);
    expect(installed.installs.single.on, isFalse, reason: 'an update leaves the switch as it was');
    expect(state.flag('plugin_xbills', fallback: false), isFalse);
    expect(installed.store.single.version, '1.1.0');
    expect(_key('market-updates-none'), findsOneWidget, reason: 'it stays, saying so');
    // A version that opens a page of its own asks first, saying where.
    await listed(tester, [billsPack(version: '1.2.0', links: const ['https://bills.example/pay'], permissions: const {PackPermission.sort, PackPermission.copy, PackPermission.markRead, PackPermission.links})]);
    await settle(tester);
    await tester.tap(find.descendant(of: _key('market-update-bills'), matching: find.text('Update')));
    await settle(tester);
    expect(_key('market-update-grew'), findsOneWidget);
    expect(find.text('It can now:'), findsOneWidget);
    expect(find.text('Opens bills.example in your browser'), findsOneWidget);
    expect(find.text('Reads texts from numbers not in your contacts'), findsNothing, reason: 'only what is new');
    await tester.ensureVisible(find.text('Update Bills'));
    await settle(tester);
    await tester.tap(find.text('Update Bills'));
    await settle(tester);
    expect(installed.store.single.version, '1.2.0');
  });

  testWidgets('a newer version by another developer is offered as a new plugin, never as an update', (tester) async {
    installed.putStore(billsPack());
    await listed(tester, [billsPack(version: '1.2.0', developer: 'someoneelse')]);
    expect(market.updates, isEmpty);
    await page(tester, marketPluginsScreen());
    await tester.ensureVisible(find.descendant(of: _key('plugins-shelf-discover'), matching: _key('plugins-card-xbills')));
    await settle(tester);
    expect(find.descendant(of: _key('plugins-shelf-discover'), matching: _key('plugins-card-xbills')), findsOneWidget);
    expect(find.descendant(of: _key('plugins-shelf-added'), matching: _key('plugins-card-xbills')), findsOneWidget, reason: 'the copy here, by @maya');
    await tester.tap(find.descendant(of: _key('plugins-shelf-discover'), matching: _key('plugins-card-xbills')), warnIfMissed: true);
    await settle(tester);
    expect(find.text('This is now by @someoneelse. Adding it removes your copy by @maya, and your choices for it.'), findsOneWidget);
    expect(_key('plugins-update-xbills'), findsNothing);
    await tester.tap(find.descendant(of: _key('plugins-detail-xbills'), matching: _key('plugins-add-xbills')));
    await settle(tester);
    await tester.ensureVisible(find.text('Add Bills'));
    await settle(tester);
    await tester.tap(find.text('Add Bills'));
    await settle(tester);
    expect(installed.calls, ['removeStore bills forget']);
    expect(installed.installs.single.bytes, packBytes(billsPack(version: '1.2.0', developer: 'someoneelse')));
  });

  testWidgets('on an iPhone nothing from other developers, and a line saying so', (tester) async {
    InstalledPlugins.instance = FakeInstalled(root: Directory('${dir.path}/ios'), checks: checks, storeAllowed: false);
    market.debugListings = [ListingPlugin(entryOf(billsPack()), billsPack(), market)];
    await page(tester, marketPluginsScreen());
    expect(_key('market-ios'), findsOneWidget);
    expect(find.text('Plugins from other developers aren\'t on iPhone.'), findsOneWidget);
    expect(_key('plugins-card-xbills'), findsNothing);
    expect(_key('plugins-chip-store'), findsNothing);
  });

  testWidgets('the catalog\'s lines: unreachable with Try again, off, untrusted, and still checking', (tester) async {
    relay.down = true;
    await tester.runAsync(() => market.refresh(force: true));
    await page(tester, marketPluginsScreen());
    expect(find.descendant(of: _key('market-catalog-problem'), matching: find.text('Plugins from other developers couldn\'t be loaded.')), findsOneWidget);
    expect(find.descendant(of: _key('market-catalog-problem'), matching: find.text('Try again')), findsOneWidget);
    relay
      ..down = false
      ..answers['GET /market/catalog'] = (status: 503, body: {'ok': false, 'error': 'off', 'message': 'The Marketplace isn\'t open on this server.'});
    await tester.runAsync(() => market.refresh(force: true));
    await settle(tester);
    expect(find.text('The Marketplace isn\'t open just now.'), findsOneWidget);
    relay.answers.clear();
    final elsewhere = billsPack();
    await listed(tester, [elsewhere], entries: {'bills': entryOf(elsewhere, key: base64Encode(NetKeys.generate().public))});
    await settle(tester);
    expect(find.text('This version of Ghost Messaging can\'t check plugins from other developers. Update it to see them.'), findsOneWidget);
    // The line is All's and From developers', not a shelf's of the app's own.
    await tester.tap(_key('plugins-chip-added'));
    await settle(tester);
    expect(_key('market-catalog-problem'), findsNothing);
    await tester.tap(_key('plugins-chip-all'));
    await settle(tester);
    market
      ..problem = null
      ..checking = 3
      ..debugListings = const [];
    await settle(tester);
    expect(find.descendant(of: _key('market-catalog-checking'), matching: find.text('Checking 3 plugins from other developers…')), findsOneWidget);
  });

  testWidgets('a pack\'s picture in its tile; a broken one falls back to its symbol', (tester) async {
    final good = billsPack(icon: billsIcon);
    final broken = billsPack(id: 'parcels', name: 'Parcels', icon: Uint8List.fromList(List.filled(80, 7)));
    market.debugListings = [ListingPlugin(entryOf(good), good, market), ListingPlugin(entryOf(broken), broken, market)];
    await page(tester, marketPluginsScreen());
    await tester.ensureVisible(_key('plugins-card-xparcels'));
    await settle(tester);
    Finder tile(String id) => find.descendant(of: _key('plugins-card-$id'), matching: find.byType(PluginTile));
    expect(find.descendant(of: tile('xbills'), matching: find.byType(Image)), findsOneWidget);
    expect(find.descendant(of: tile('xbills'), matching: find.byType(AppIcon)), findsNothing);
    // Decoded by the engine on a real gap: waited for until the broken one's error has come back and its symbol is
    // drawn in its place (however busy the machine), not for a fixed time.
    final symbol = find.descendant(of: tile('xparcels'), matching: find.byType(AppIcon));
    for (var i = 0; i < 500 && symbol.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(symbol, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screenshots: only those whose bytes are the ones its package names', (tester) async {
    final a = sha256Hex(billsIcon);
    final b = 'b' * 64;
    final pack = billsPack(shots: [a, b]);
    relay.shots[a] = billsIcon;
    // Another picture's bytes under b's name: not the one the package names, so not shown.
    relay.shots[b] = billsIcon;
    market.debugListings = [ListingPlugin(entryOf(pack), pack, market)];
    await page(tester, marketPluginsScreen(open: 'xbills'));
    await settle(tester);
    expect(_key('plugins-detail-shots'), findsOneWidget);
    await tester.ensureVisible(_key('plugins-detail-shots'));
    await settle(tester);
    expect(_key('plugins-detail-shot-$a'), findsOneWidget);
    expect(_key('plugins-detail-shot-$b'), findsNothing);
  });

  testWidgets('a plugin in development switched on the first time asks first, saying nobody reviewed it', (tester) async {
    installed.putDev(billsPack());
    await page(tester, marketPluginsScreen(open: 'xbills'));
    expect(_key('plugins-detail-dev'), findsOneWidget);
    expect(tester.widget<Text>(_key('plugins-detail-source')).data, 'By @maya · In development · not reviewed');
    expect(_key('plugins-detail-reviewed'), findsNothing);
    expect(_key('plugins-report-xbills'), findsNothing);
    await tester.tap(find.descendant(of: _key('plugins-detail-xbills'), matching: _key('plugins-add-xbills')));
    await settle(tester);
    expect(_key('market-consent'), findsOneWidget);
    expect(_key('market-consent-dev'), findsOneWidget);
    expect(find.text('Reviewed by Ghost Messaging'), findsNothing);
    await tester.ensureVisible(find.text('Switch it on'));
    await settle(tester);
    await tester.tap(find.text('Switch it on'));
    await settle(tester);
    expect(installed.calls, ['agreeDev bills']);
    expect(state.flag('plugin_xbills', fallback: false), isTrue);
  });

  testWidgets('Report: a reason, a few words, the username only where asked, signed', (tester) async {
    installed.putStore(billsPack());
    await page(tester, marketPluginsScreen(open: 'xbills'));
    await tester.ensureVisible(_key('plugins-report-xbills'));
    await settle(tester);
    await tester.tap(_key('plugins-report-xbills'));
    await settle(tester);
    expect(_key('market-report'), findsOneWidget);
    await tester.ensureVisible(find.text('It\'s spam'));
    await settle(tester);
    await tester.tap(find.text('It\'s spam'));
    await settle(tester);
    await tester.enterText(find.descendant(of: _key('market-report-words'), matching: find.byType(EditableText)), 'Every bill is a scam.');
    await tester.tap(_key('market-report-send'));
    await settle(tester);
    final sent = relay.asked.where((r) => r.url.path == '/market/report').single;
    expect(String.fromCharCodes(sent.body), '{"plugin":"bills","version":"1.0.0","reason":"spam","text":"Every bill is a scam."}');
    expect(sent.headers['x-ghost-sig'], isNotNull);
    expect(find.text('Thanks: it will be looked at.'), findsOneWidget);
  });
}
