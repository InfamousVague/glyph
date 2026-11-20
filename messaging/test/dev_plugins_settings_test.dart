import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/plugins/codes.dart';
import 'package:ghost_messaging/plugins/pack/pack.dart';
import 'package:ghost_messaging/plugins/plugin.dart';
import 'package:ghost_messaging/plugins/registry.dart';
import 'package:ghost_messaging/ui/conversations.dart';
import 'package:ghost_messaging/ui/files_space/share_in.dart';
import 'package:ghost_messaging/ui/market/dev_plugins.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import 'support/list_harness.dart';
import 'support/market_fakes.dart';

/// Settings › Developer › Plugins in development (lib/ui/market/dev_plugins.dart; Matt, 2026-11-20: "please add a
/// developer setting for users to be able to manually upload plugins for development testing"): there in developer
/// mode and never in an App Store build; pasting a plugin adds its row, and its first switch-on asks first; words that
/// aren't a plugin say what is wrong and add nothing; a pack's own screen reloads, lists what it threw, tries a text and
/// removes it; the list says while one is on; and a shared .ghostplugin loads.
Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  late Directory dir;
  late FakeChecks checks;
  late FakeInstalled installed;
  late AppState state;
  late ListPhone phone;
  String? clipboard;
  final oldInstalled = InstalledPlugins.instance, oldRegistry = PluginRegistry.instance;

  setUp(() {
    phone = ListPhone(const [])..install();
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return clipboard == null ? null : {'text': clipboard};
      if (call.method == 'Clipboard.setData') phone.copied.add(((call.arguments as Map)['text'] as String?) ?? '');
      return null;
    });
    dir = Directory.systemTemp.createTempSync('dev-plugins-');
    checks = FakeChecks();
    PluginRegistry.instance = PluginRegistry(const [CodesPlugin()]);
    installed = FakeInstalled(root: Directory('${dir.path}/plugins'), checks: checks);
    InstalledPlugins.instance = installed;
    state = AppState()..setFlag('dev_mode', true);
    installed.switches = AppStore(state);
  });
  tearDown(() {
    InstalledPlugins.instance = oldInstalled;
    PluginRegistry.instance = oldRegistry;
    dir.deleteSync(recursive: true);
  });

  Future<void> developer(WidgetTester tester) async {
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const SettingsSectionScreen('developer'), state, size: const Size(412, 2400));
  }

  testWidgets('only in developer mode, and never in an App Store build', (tester) async {
    await developer(tester);
    expect(_key('dev-plugins'), findsOneWidget);
    for (final k in ['dev-plugin-paste', 'dev-plugin-link', 'dev-plugin-docs']) {
      expect(_key(k), findsOneWidget, reason: k);
    }
    expect(find.text('Shows Settings › API, Plugins in development below, and the Marketplace\'s In development.'), findsOneWidget);
    state.setFlag('dev_mode', false);
    await developer(tester);
    expect(_key('dev-plugins'), findsNothing, reason: 'Developer itself is hidden');
    state.setFlag('dev_mode', true);
    InstalledPlugins.instance = FakeInstalled(root: Directory('${dir.path}/store-build'), checks: checks, devAllowed: false);
    await developer(tester);
    expect(find.text('Developer mode'), findsOneWidget);
    expect(_key('dev-plugins'), findsNothing);
  });

  testWidgets('Paste adds its row with its switch; the first switch-on asks, and agreeing switches it on', (tester) async {
    final bills = billsPack();
    checks.know(bills);
    clipboard = utf8.decode(packBytes(bills));
    await developer(tester);
    await tester.tap(_key('dev-plugin-paste'));
    await settle(tester);
    expect(installed.calls.single, startsWith('loadDev paste'));
    expect(find.text('Bills loaded. Switch it on to agree to what it can do now.'), findsOneWidget);
    expect(_key('dev-plugin-bills'), findsOneWidget);
    expect(find.descendant(of: _key('dev-plugin-bills'), matching: find.textContaining('1.0.0 · pasted · needs your OK')), findsOneWidget);
    // The toast gone (fake time), so it isn't over the sheet's last choice.
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    final toggle = _key('dev-plugin-switch-bills');
    expect(tester.widget<GlacierSwitch>(toggle).checked, isFalse);
    await tester.tap(toggle);
    await settle(tester);
    expect(_key('market-consent'), findsOneWidget);
    expect(_key('market-consent-dev'), findsOneWidget);
    expect(installed.calls, hasLength(1), reason: 'nothing switched on before the sheet is answered');
    await tester.ensureVisible(find.text('Switch it on'));
    await settle(tester);
    await tester.tap(find.text('Switch it on'));
    await settle(tester);
    expect(installed.calls.last, 'agreeDev bills');
    expect(state.flag('plugin_xbills', fallback: false), isTrue);
    expect(tester.widget<GlacierSwitch>(_key('dev-plugin-switch-bills')).checked, isTrue);
    // Agreed to, it switches off and on again without asking.
    await tester.tap(_key('dev-plugin-switch-bills'));
    await settle(tester);
    expect(state.flag('plugin_xbills', fallback: true), isFalse);
    await tester.tap(_key('dev-plugin-switch-bills'));
    await settle(tester);
    expect(_key('market-consent'), findsNothing);
    expect(state.flag('plugin_xbills', fallback: false), isTrue);
  });

  testWidgets('words that aren\'t a plugin say what is wrong, add no row, and copy', (tester) async {
    clipboard = 'not a plugin at all';
    await developer(tester);
    await tester.tap(_key('dev-plugin-paste'));
    await settle(tester);
    expect(_key('dev-plugin-problems'), findsOneWidget);
    expect(find.descendant(of: _key('dev-plugin-problems'), matching: find.textContaining('bad_json')), findsOneWidget);
    expect(installed.dev, isEmpty);
    await tester.ensureVisible(find.text('Copy the problems'));
    await settle(tester);
    await tester.tap(find.text('Copy the problems'));
    await settle(tester);
    expect(phone.copied.last, contains('bad_json'));
    expect(_key('dev-plugin-bills'), findsNothing);
  });

  testWidgets('its own screen: where it came from, what it threw, Reload, Try it on s01, Remove', (tester) async {
    final bills = billsPack();
    installed.putDev(bills, source: const DevSource('link', url: 'https://example.com/bills.ghostplugin'), errors: [DevError(DateTime(2026, 11, 20, 9, 30), 'refused move: only into its own tabs')], issues: const [PackIssue('broad_phrase', 'rules.tags[1].any[0]', '"payment received" is broad.', severity: PackSeverity.warning)]);
    PackTrial trial(PluginPack pack, {required String text, String from = '72975', bool switchesOn = false, PluginStore? store}) => text.contains('Amount due')
        ? const PackTrial(seen: true, tags: {'bill': r'$45.20'}, section: 'bills', row: RowLook(value: r'$45.20', caption: 'A bill'), actions: {'row': ['Copy the amount'], 'list.conversation.menu': ['Copy the amount']}, took: Duration(microseconds: 420))
        : const PackTrial(seen: true, took: Duration(microseconds: 90));
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, DevPluginScreen(packId: 'bills', trial: trial), state, size: const Size(412, 3000));
    expect(_key('dev-plugin-screen-bills'), findsOneWidget);
    expect(find.textContaining('from a link'), findsOneWidget);
    expect(find.descendant(of: _key('dev-plugin-issues-bills'), matching: find.textContaining('broad_phrase')), findsOneWidget);
    expect(find.descendant(of: _key('dev-plugin-errors-bills'), matching: find.textContaining('refused move')), findsOneWidget);
    // Try it, with the bill of the samples.
    await tester.enterText(find.descendant(of: _key('dev-plugin-try-text-bills'), matching: find.byType(EditableText)), packSamples.first.text);
    await tester.tap(_key('dev-plugin-try-bills'));
    await settle(tester);
    final result = _key('dev-plugin-try-result-bills');
    expect(find.descendant(of: result, matching: find.text(r'Tags: bill=$45.20')), findsOneWidget);
    expect(find.descendant(of: result, matching: find.text('It goes to Bills')), findsOneWidget);
    expect(find.descendant(of: result, matching: find.text('On its row: Copy the amount')), findsOneWidget);
    expect(find.descendant(of: result, matching: find.text(r'Its row: $45.20 · A bill')), findsOneWidget);
    // Every sample, a line each.
    await tester.tap(find.text('Try the samples'));
    await settle(tester);
    final samples = _key('dev-plugin-samples-bills');
    expect(find.descendant(of: samples, matching: find.textContaining(r's01 · Bills · bill=$45.20')), findsOneWidget);
    expect(find.descendant(of: samples, matching: find.textContaining('s12 · nothing')), findsOneWidget);
    // Reload fetches it again; Remove takes it away.
    await tester.tap(_key('dev-plugin-reload-bills'));
    await settle(tester);
    expect(installed.calls, ['reloadDev bills']);
    await tester.tap(_key('dev-plugin-remove-bills'));
    await settle(tester);
    expect(installed.calls.last, 'removeDev bills');
    expect(installed.dev, isEmpty);
  });

  testWidgets('a pasted copy can\'t be reloaded; one from a link can', (tester) async {
    installed.putDev(billsPack());
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const DevPluginScreen(packId: 'bills'), state, size: const Size(412, 3000));
    expect(_key('dev-plugin-reload-bills'), findsNothing);
    expect(_key('dev-plugin-remove-bills'), findsOneWidget);
  });

  testWidgets('the list says while a plugin in development is on', (tester) async {
    installed.putDev(billsPack());
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const ConversationsScreen(), state);
    expect(_key('dev-plugins-on'), findsNothing, reason: 'loaded, not on');
    state.set('plugin_xbills', 'on');
    await settle(tester);
    expect(_key('dev-plugins-on'), findsOneWidget);
    expect(find.text('A plugin in development is on · Settings › Developer'), findsOneWidget);
  });

  testWidgets('a .ghostplugin shared in loads in development, the rest are left for a Files space', (tester) async {
    final bills = billsPack();
    checks.know(bills);
    final sheet = await loadSheet(tester);
    late BuildContext context;
    await pumpScreen(tester, sheet, Builder(builder: (c) {
      context = c;
      return const SizedBox.expand();
    }), state);
    final files = [const IncomingFile(source: 'content://share/bills.ghostplugin', name: 'bills.ghostplugin'), const IncomingFile(source: 'content://share/photo.jpg', name: 'photo.jpg')];
    late List<IncomingFile> left;
    await tester.runAsync(() async {
      left = await FilesShareIn.takePlugins(context, files, read: (source) async => packBytes(bills));
    });
    await settle(tester);
    expect([for (final f in left) f.name], ['photo.jpg']);
    expect(installed.calls.single, startsWith('loadDev file'));
    expect(installed.dev.single.source.name, 'bills.ghostplugin');
    expect(find.text('Bills loaded. Switch it on to agree to what it can do now.'), findsOneWidget);
    // With developer mode off it is a file like any other.
    state.setFlag('dev_mode', false);
    final again = await FilesShareIn.takePlugins(context, files, read: (source) async => packBytes(bills));
    expect(again, hasLength(2));
  });
}
