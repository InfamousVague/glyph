import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/account/account.dart';
import 'package:ghost_messaging/desktop/platform.dart' show computerWord, desktopName;
import 'package:ghost_messaging/emoji_sets.dart';
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/looks.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/net.dart';
import 'package:ghost_messaging/platform_info.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/standalone/standalone.dart';
import 'package:ghost_messaging/ui/circles/circle_face.dart' show spaceKindsOffered;
import 'package:ghost_messaging/ui/circles/circle_screen.dart' show FilesNotHere, circleSpacePage;
import 'package:ghost_messaging/ui/composer_box.dart' show composerButtons;
import 'package:ghost_messaging/ui/files_space/files_screen.dart' show FilesSpaceScreen;
import 'package:ghost_messaging/ui/hangout_screen.dart' show HangoutScreen;
import 'package:ghost_messaging/ui/settings.dart';
import 'package:ghost_messaging/ui/settings_panes.dart';
import 'package:ghost_messaging/ui/settings_shortcuts.dart' show shortcutsSummary;
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/voice/channels.dart';
import 'package:ghost_messaging/voice/voice.dart';
import 'package:ghost_messaging/web/app.dart';
import 'package:ghost_messaging/web/browser.dart';
import 'package:ghost_messaging/web/settings.dart';
import 'package:ghost_messaging/web/store.dart';
import 'package:glacier/glacier.dart';

/// Ghost Messaging in a web page (lib/web; Matt: "the full web client"), as far as it can be held without a browser:
/// what the page keeps and how, being the one tab, where its hub is, what it says in the app's place, and what the
/// screens leave out and call themselves there. The page itself in real browser engines is tool/web/e2e.mjs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final c in ['ghost_desktop/system', 'ghost_messaging/sms']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
  });

  group('what the page keeps', () {
    Future<StandaloneCalls> page(MemoryBrowserProfile profile) async {
      final c = StandaloneCalls.on(WebStandaloneStore(profile.store));
      await c.load();
      return c;
    }

    test('who it is stays who it is when the page is loaded again', () async {
      final profile = MemoryBrowserProfile();
      final first = await (await page(profile)).invokeMethod<Map>('netIdentity');
      final again = await (await page(profile)).invokeMethod<Map>('netIdentity');
      expect(again, first);
      expect(first!['id'], NetCrypto.idOf(base64Decode(first['key'] as String)));
      // Another browser is someone else.
      expect((await (await page(MemoryBrowserProfile())).invokeMethod<Map>('netIdentity'))!['id'], isNot(first['id']));
    });

    test('the key and every secret are sealed; only the one JSON record is plain', () async {
      final profile = MemoryBrowserProfile();
      final c = await page(profile);
      final scalar = NetCrypto.hex(((await c.invokeMethod<List>('identityExport'))!).cast<int>());
      await c.invokeMethod('secretKeep', {'name': 'account-words', 'value': 'twelve words nobody else has'});
      await c.invokeMethod('setPref', {'key': 'theme', 'value': 'dark'});
      await c.flushed();
      expect(profile.store.plain.keys, [WebStandaloneStore.stateName]);
      expect(profile.store.sealed.keys, unorderedEquals([WebStandaloneStore.identityName, 'secret:account-words']));
      // Neither is anywhere as it was given: not in the plain record, not in what the store holds.
      for (final kept in [...profile.store.plain.values, ...profile.store.sealed.values]) {
        expect(kept, isNot(contains(scalar)));
        expect(kept, isNot(contains('twelve words nobody else has')));
      }
      expect(await c.invokeMethod('secretRead', {'name': 'account-words'}), 'twelve words nobody else has');
      // The choices are in the JSON, and there after a reload; a secret given as nothing is taken away.
      expect((jsonDecode(profile.store.plain[WebStandaloneStore.stateName]!) as Map)['prefs'], {'theme': 'dark'});
      expect((await (await page(profile)).invokeMethod<Map>('prefs'))!['theme'], 'dark');
      await c.invokeMethod('secretKeep', {'name': 'account-words', 'value': ''});
      expect(profile.store.sealed.keys, [WebStandaloneStore.identityName]);
      expect(await c.invokeMethod('secretRead', {'name': 'account-words'}), isNull);
    });

    test('a key that will not open (the browser\'s store cleared in part) is as if none were kept', () async {
      final profile = MemoryBrowserProfile();
      final first = await (await page(profile)).invokeMethod<Map>('netIdentity');
      profile.store.sealed[WebStandaloneStore.identityName] = 'not what was sealed';
      final next = await (await page(profile)).invokeMethod<Map>('netIdentity');
      expect(next!['id'], isNot(first!['id']));
      // And the new one is kept.
      expect((await (await page(profile)).invokeMethod<Map>('netIdentity'))!['id'], next['id']);
    });

    test('an account kept in a restored key is who the page is from then on', () async {
      final profile = MemoryBrowserProfile();
      final c = await page(profile);
      final other = NetKeys.generate();
      await c.invokeMethod('identityImport', {'scalar': other.scalar});
      final again = await (await page(profile)).invokeMethod<Map>('netIdentity');
      expect(again!['id'], other.id);
    });
  });

  group('one tab at a time', () {
    test('a second tab is refused while the first is the app, and has it once that one is gone', () async {
      final profile = MemoryBrowserProfile();
      final one = MemoryBrowser(profile: profile), two = MemoryBrowser(profile: profile);
      expect(await one.holdTab(onAsked: () async {}), isNotNull);
      expect(await two.holdTab(onAsked: () async {}), isNull);
      profile.tabGone();
      expect(await two.holdTab(onAsked: () async {}), isNotNull);
    });

    test('taking over asks the tab that is it to finish first, and then it is the other\'s', () async {
      final profile = MemoryBrowserProfile();
      final one = MemoryBrowser(profile: profile), two = MemoryBrowser(profile: profile);
      final order = <String>[];
      await one.holdTab(onAsked: () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add('the first finished writing');
      });
      await two.takeTab(onAsked: () async {});
      order.add('the second has it');
      expect(order, ['the first finished writing', 'the second has it']);
      expect(await one.holdTab(onAsked: () async {}), isNull);
    });
  });

  test('the hub is beside the app: the page\'s own address, /hub where the page is /app/', () {
    expect(hubFor(Uri.parse('https://gogho.st/app/')), 'wss://gogho.st/hub');
    expect(hubFor(Uri.parse('https://gogho.st/app/index.html')), 'wss://gogho.st/hub');
    expect(hubFor(Uri.parse('https://gogho.st/app/#anything')), 'wss://gogho.st/hub');
    expect(hubFor(Uri.parse('https://gogho.st/app')), 'wss://gogho.st/hub');
    expect(hubFor(Uri.parse('http://127.0.0.1:8787/app/')), 'ws://127.0.0.1:8787/hub');
    expect(hubFor(Uri.parse('https://example.org:8443/ghost/app/')), 'wss://example.org:8443/ghost/hub');
    // Served from somewhere else: still its own address, never another.
    expect(hubFor(Uri.parse('https://example.org/')), 'wss://example.org/hub');
    // And nothing is changed where the app is no page: the relay it always had.
    expect(Net.homeHub, Net.defaultHub);
  });

  test('a browser is named by what it says it is, and never as one of the five platforms', () {
    expect(browserNameOf('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'), 'Browser · Chrome · Mac');
    expect(browserNameOf('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15'), 'Browser · Safari · Mac');
    expect(browserNameOf('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0'), 'Browser · Firefox · Windows');
    expect(browserNameOf('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0'), 'Browser · Edge · Windows');
    expect(browserNameOf('Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36'), 'Browser · Chrome · Android');
    expect(browserNameOf('Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1'), 'Browser · Safari · iOS');
    expect(browserNameOf('Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0'), 'Browser · Firefox · Linux');
    expect(browserNameOf('something else entirely'), 'Browser');
    expect(browserNameOf(''), 'Browser');
  });

  group('in the app\'s place', () {
    testWidgets('a browser that can\'t run it is told why, and nothing is started', (tester) async {
      await webMain(browser: MemoryBrowser(unfit: 'Ghost Messaging needs a secure address to run in a browser: one that starts with https.'));
      await tester.pump();
      expect(find.text('Ghost Messaging needs a secure address to run in a browser: one that starts with https.'), findsOneWidget);
      expect(find.byKey(const ValueKey('web-notice-action')), findsNothing);
      expect(Sms.browser, isFalse);
      expect(Sms.standalone, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second tab says the app is open in another, and offers to have it here', (tester) async {
      final profile = MemoryBrowserProfile();
      await MemoryBrowser(profile: profile).holdTab(onAsked: () async {});
      await webMain(browser: MemoryBrowser(profile: profile));
      await tester.pump();
      expect(find.text('Ghost Messaging is open in another tab.'), findsOneWidget);
      expect(find.text('Use it here'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const ValueKey('web-notice-action')).first), isNotNull);
      // Nothing was started, and nothing of the other tab's was touched.
      expect(Sms.browser, isFalse);
      expect(profile.store.plain, isEmpty);
      expect(profile.store.sealed, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a browser that keeps nothing for the page is told so', (tester) async {
      final browser = MemoryBrowser()..noStore = true;
      await webMain(browser: browser);
      await tester.pump();
      expect(find.text('This browser won\'t keep anything for this page.'), findsOneWidget);
      expect(Sms.browser, isFalse);
      expect(browser.reloads, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the button is pressed once while what it does runs', (tester) async {
      var runs = 0;
      await tester.pumpWidget(WebNotice(
        words: 'Ghost Messaging is open in another tab.',
        action: 'Use it here',
        onAction: () async {
          runs++;
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
      ));
      await tester.tap(find.byKey(const ValueKey('web-notice-action')));
      await tester.pump();
      expect(find.text('Opening…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('web-notice-action')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(runs, 1);
      expect(find.text('Use it here'), findsOneWidget);
    });
  });

  // What a browser can't do is absent from its screens, not broken in them, and it is called a browser. Each of these
  // asks the app's own questions (Sms.browser, Sms.callsHere), which are false and true on every phone and computer.
  group('in a browser', () {
    late SmsCalls before;
    setUp(() => before = Sms.calls);
    tearDown(() {
      Sms.browser = false;
      Sms.browserWide = false;
      Sms.browserName = 'Browser';
      Sms.standalone = false;
      Sms.calls = before;
      SettingsSources.remove(browserSettings);
    });

    /// As lib/web/app.dart leaves things once the page has started.
    void asAPage({bool wide = true}) {
      Sms.calls = StandaloneCalls.on(WebStandaloneStore(MemoryBrowserStore()));
      Sms.standalone = true;
      Sms.browser = true;
      Sms.browserWide = wide;
      Sms.browserName = 'Browser · Safari · Mac';
      SettingsSources.add(browserSettings);
    }

    test('nowhere else is anything a browser\'s', () {
      expect(Sms.browser, isFalse);
      expect(Sms.callsHere, isTrue);
      expect(computerWord, isNot('browser'));
      expect(spaceKindsOffered, SpaceKind.values);
      expect(offeredEmojiSets, emojiSets);
      expect(emojiFamilyOf('system'), isNull);
      expect(emojiSetInUse('system').id, 'system');
      expect(settingsSectionsOn(SettingsWhere.computer).map((s) => s.id), isNot(contains('browser-about')));
      expect(circleSpacePage(const VoiceChannel(seed: 'aa', name: 'Shelf', kind: SpaceKind.files)), isA<FilesSpaceScreen>());
    });

    test('it is called a browser: in Settings, and in the account\'s list of devices', () {
      asAPage();
      expect(computerWord, 'browser');
      expect(desktopName, 'a browser');
      expect(settingsGroupLabel('app'), 'This browser');
      expect(Account.instance.profiles.deviceName, 'Browser · Safari · Mac');
    });

    test('it reads at a computer\'s sizes in a wide window and a phone\'s in a narrow one', () {
      asAPage(wide: true);
      expect(Sms.computer, isTrue);
      // Narrow: a phone's, in a browser, where the device is none of the three kinds of computer. This test runs on one
      // of them, which is a computer whatever its window: only that much can be held here.
      asAPage(wide: false);
      expect(Sms.computer, PlatformInfo.isMacOS || PlatformInfo.isWindows || PlatformInfo.isLinux);
    });

    test('Settings has its own About, and none of what it has nothing to set for', () {
      asAPage();
      final model = SettingsModel(AppState());
      final shown = [for (final s in settingsSections) if (s.when?.call(model) ?? true) s.id];
      expect(shown, contains('browser-about'));
      // No calls, no sounds: nothing to set. And what is the phone's alone was never a computer's.
      expect(shown, isNot(contains('voice')));
      expect(shown, isNot(contains('sounds')));
      for (final phones in ['notifications', 'receipts', 'android', 'keyboard', 'computers', 'network', 'updates', 'about', 'api']) {
        expect(shown, isNot(contains(phones)), reason: phones);
      }
      // What it does have.
      expect(shown, containsAll(['me', 'appearance', 'emoji', 'messages', 'blocked']));
      final about = settingsSections.firstWhere((s) => s.id == 'browser-about');
      expect(about.summary!(model), 'Ghost Messaging in a browser $appVersion');
      // Keyboard shortcuts with no push to talk, and none of the calls' commands.
      expect(shortcutsSummary(model), 'Every command and its keys');
      // On a phone or a computer they are there as they were.
      Sms.browser = false;
      final elsewhere = [for (final s in settingsSectionsOn(SettingsWhere.computer)) if (s.when?.call(model) ?? true) s.id];
      expect(elsewhere, containsAll(['voice', 'sounds']));
      expect(shortcutsSummary(model), 'Push to talk off');
    });

    test('there are no calls: nothing joins one, and a space is offered without Files', () async {
      asAPage();
      expect(Sms.callsHere, isFalse);
      const lounge = VoiceChannel(seed: 'aa', name: 'Lounge');
      await expectLater(Voice.instance.join(lounge), throwsA(isA<StateError>().having((e) => e.message, 'what it says', 'Calls aren\'t in the browser yet.')));
      expect(spaceKindsOffered, [SpaceKind.voice, SpaceKind.text]);
      // A Files space made elsewhere says where it opens, in its page's place; the others are their chat.
      expect(circleSpacePage(const VoiceChannel(seed: 'aa', name: 'Shelf', kind: SpaceKind.files)), isA<FilesNotHere>());
      expect(circleSpacePage(lounge), isA<HangoutScreen>());
    });

    testWidgets('a Files space says it isn\'t in the browser yet', (tester) async {
      final sheet = await _sheet(tester);
      asAPage();
      await tester.pumpWidget(_Themed(sheet: sheet, child: const FilesNotHere(channel: VoiceChannel(seed: 'aa', name: 'Shelf', kind: SpaceKind.files))));
      expect(find.text('Files spaces aren\'t in the browser yet. This one opens in Ghost Messaging on a phone or a computer.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the composer has Send where the microphone is, since nothing is recorded there', (tester) async {
      final sheet = await _sheet(tester);
      Future<List<String>> keys({required bool something}) async {
        late List<String> found;
        await tester.pumpWidget(_Themed(
          sheet: sheet,
          child: Builder(builder: (context) {
            final b = composerButtons(context.tokens, hasSomething: something, onAttach: null, onSticker: () {}, onRecord: null, onSend: something ? () {} : null);
            found = [for (final w in [...b.ends, ...b.below]) if (w.key is ValueKey<String>) (w.key! as ValueKey<String>).value];
            return Row(children: [b.plus, ...b.ends]);
          }),
        ));
        return found;
      }

      expect(await keys(something: false), contains('composer-mic'));
      asAPage();
      expect(await keys(something: false), isNot(contains('composer-mic')));
      expect(await keys(something: false), contains('composer-send'));
      expect(await keys(something: true), contains('composer-send'));
      expect(tester.takeException(), isNull);
    });
  });
}

/// The app's own stylesheet, as its start loads it.
Future<TokenSheet> _sheet(WidgetTester tester) async {
  final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
  installSettingsStyles(sheet);
  return sheet;
}

/// A widget of the app's with the app round it: its choices, and the theme it reads its sizes and colours from.
class _Themed extends StatelessWidget {
  const _Themed({required this.sheet, required this.child});
  final TokenSheet sheet;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = AppState();
    return AppScope(
      state: state,
      child: WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
        builder: (c, child) => GlacierTheme(sheet: sheet, attrs: ghostAttrs(state, 'desktop'), child: GlacierToastProvider(child: child!)),
        home: child,
      ),
    );
  }
}
