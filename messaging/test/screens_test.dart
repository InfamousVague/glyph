import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/effects.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides, ghostTypography;
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/ui/background_picker.dart';
import 'package:ghost_messaging/ui/chat_settings.dart';
import 'package:ghost_messaging/ui/compose.dart';
import 'package:ghost_messaging/ui/conversations.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:ghost_messaging/ui/setup.dart';
import 'package:ghost_messaging/ui/thread.dart';
import 'package:glacier/glacier.dart';

/// The screens drawn with made-up conversations, in light and dark, written to test/shots/ (run with
/// `flutter test --update-goldens test/screens_test.dart`). Nothing here talks to Android: the channel is answered
/// below.
Future<void> _fonts() async {
  Future<void> family(String name, String file) async {
    final loader = FontLoader(name)..addFont(File(file).readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
    await loader.load();
  }

  await family('Inter Variable', 'assets/fonts/InterVariable-latin.ttf');
  await family('JetBrains Mono Variable', 'assets/fonts/JetBrainsMonoVariable-latin.ttf');
  await family('Ghost Emoji Noto', 'assets/emoji/NotoColor.ttf');
  await family('Ghost Emoji Twemoji', 'assets/emoji/Twemoji.ttf');
  await family('Ghost Emoji OpenMoji', 'assets/emoji/OpenMoji.ttf');
  await family('Ghost Emoji Outline', 'assets/emoji/NotoOutline.ttf');
}

final _now = DateTime.now();
int _ago({int days = 0, int hours = 0, int minutes = 0}) => _now.subtract(Duration(days: days, hours: hours, minutes: minutes)).millisecondsSinceEpoch;

Map<String, Object?> _p(String address, [String? name]) => {'address': address, 'name': name, 'photo': null};

final _conversations = [
  {'id': 1, 'date': _ago(minutes: 4), 'people': [_p('+15551230001', 'Maya Chen')], 'snippet': 'Sounds good, see you at 7! Bring the projector cable if you still have it', 'unread': true, 'error': false, 'archived': false},
  {'id': 2, 'date': _ago(minutes: 52), 'people': [_p('+15551230002', 'Jordan Park'), _p('+15551230003', 'Sam Rivera'), _p('+15551230004', 'Alex Kim')], 'snippet': 'Picture', 'unread': true, 'error': false, 'archived': false},
  {'id': 3, 'date': _ago(hours: 5), 'people': [_p('+15551230005', 'Dad')], 'snippet': 'Call me when you land', 'unread': false, 'error': false, 'archived': false, 'pinned': true},
  {'id': 4, 'date': _ago(days: 1, hours: 2), 'people': [_p('28849')], 'snippet': 'Your verification code is 482913. Don\'t share it with anyone.', 'unread': false, 'error': false, 'archived': false, 'muted': true},
  {'id': 5, 'date': _ago(days: 3), 'people': [_p('+15551230006', 'Priya Natarajan')], 'snippet': 'haha yes 😂', 'unread': false, 'error': true, 'archived': false},
  {'id': 6, 'date': _ago(days: 12), 'people': [_p('+15551230007')], 'snippet': 'Your package was delivered', 'unread': false, 'error': false, 'archived': false, 'draft': 'Thanks, I\'ll pick it up tom'},
  {'id': 7, 'date': _ago(days: 40), 'people': [_p('+15551230008', 'Old Thread')], 'snippet': 'ok', 'unread': false, 'error': false, 'archived': true},
  {'id': 8, 'date': _ago(minutes: 30), 'people': [_p('+15551230011', 'Riley Fox')], 'snippet': 'Only our two phones can read this now', 'unread': false, 'error': false, 'archived': false, 'encrypted': true},
  {'id': 9, 'date': _ago(hours: 2), 'people': [_p('+15551230012', 'Noor Haddad')], 'snippet': 'Encryption key', 'unread': false, 'error': false, 'archived': false},
];

/// Where encryption stands with each person (android/.../E2e.kt): on and verified with Riley, Noor's key waiting
/// for a yes, nothing with anyone else.
Map<String, Object?> _e2e(String address) => switch (address) {
      '+15551230011' => {'address': address, 'state': 'on', 'verified': true, 'changed': false, 'safety': '04821 77310 59264 10388 92745 36601', 'person': _p(address, 'Riley Fox')},
      '+15551230012' => {'address': address, 'state': 'pending', 'verified': false, 'changed': false, 'safety': '61120 08347 55902 73418 20056 94471', 'person': _p(address, 'Noor Haddad')},
      // Maya has the app too (its hello came from her), and nothing has been exchanged: the conversation offers it.
      '+15551230001' => {'address': address, 'state': 'none', 'verified': false, 'changed': false, 'hasGhost': true, 'declined': false},
      _ => {'address': address, 'state': 'none', 'verified': false, 'changed': false},
    };

List<Map<String, Object?>> _messages(int thread) {
  if (thread == 2) {
    return [
      {'id': 13, 'kind': 'mms', 'address': '+15551230004', 'body': '👍 to "Hike this weekend?"', 'date': _ago(minutes: 50), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
      {'id': 12, 'kind': 'mms', 'address': '+15551230003', 'body': 'Liked “Hike this weekend?”', 'date': _ago(minutes: 51), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
      {'id': 11, 'kind': 'mms', 'address': '+15551230003', 'body': 'Look at this view 🏔️', 'date': _ago(minutes: 52), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
      {'id': 10, 'kind': 'mms', 'address': '', 'body': 'Saturday works for me', 'date': _ago(hours: 1), 'outgoing': true, 'state': 'read', 'read': true, 'parts': []},
      {'id': 9, 'kind': 'mms', 'address': '+15551230004', 'body': 'Same, any time after noon', 'date': _ago(hours: 1, minutes: 5), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
      {'id': 8, 'kind': 'mms', 'address': '+15551230002', 'body': 'Hike this weekend?', 'date': _ago(hours: 1, minutes: 8), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
      {'id': 7, 'kind': 'mms', 'address': '+15551230002', 'body': 'Who\'s around Saturday', 'date': _ago(hours: 1, minutes: 9), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
    ];
  }
  if (thread == 8) {
    // An encrypted conversation: the two keys as lines, sealed texts opened with their locks, and one from before a
    // reinstall that this phone can no longer open.
    return [
      {'id': 27, 'kind': 'sms', 'address': '+15551230011', 'body': '', 'date': _ago(minutes: 29), 'outgoing': false, 'state': 'received', 'read': true, 'encrypted': true, 'notice': 'background'},
      {'id': 26, 'kind': 'sms', 'address': '+15551230011', 'body': 'Only our two phones can read this now', 'date': _ago(minutes: 30), 'outgoing': false, 'state': 'received', 'read': true, 'encrypted': true},
      {'id': 25, 'kind': 'sms', 'address': '', 'body': 'Door code is 4417, don\'t tell anyone 🤫', 'date': _ago(minutes: 31), 'outgoing': true, 'state': 'delivered', 'read': true, 'encrypted': true},
      {'id': 24, 'kind': 'sms', 'address': '+15551230011', 'body': '', 'date': _ago(minutes: 33), 'outgoing': false, 'state': 'received', 'read': true, 'notice': 'undecryptable'},
      {'id': 23, 'kind': 'sms', 'address': '+15551230011', 'body': '', 'date': _ago(minutes: 40), 'outgoing': false, 'state': 'received', 'read': true, 'notice': 'key'},
      {'id': 22, 'kind': 'sms', 'address': '', 'body': '', 'date': _ago(minutes: 41), 'outgoing': true, 'state': 'delivered', 'read': true, 'notice': 'key'},
      {'id': 21, 'kind': 'sms', 'address': '+15551230011', 'body': 'Did you get the app?', 'date': _ago(minutes: 50), 'outgoing': false, 'state': 'received', 'read': true},
    ];
  }
  if (thread == 9) {
    return [
      {'id': 31, 'kind': 'sms', 'address': '+15551230012', 'body': '', 'date': _ago(hours: 2), 'outgoing': false, 'state': 'received', 'read': true, 'notice': 'key'},
      {'id': 30, 'kind': 'sms', 'address': '+15551230012', 'body': 'Sending you my key, one sec', 'date': _ago(hours: 2, minutes: 1), 'outgoing': false, 'state': 'received', 'read': true},
    ];
  }
  return [
    {'id': 10, 'kind': 'sms', 'address': '+15551230001', 'body': '🎉🍿', 'date': _ago(minutes: 1), 'outgoing': false, 'state': 'received', 'read': true},
    {'id': 9, 'kind': 'sms', 'address': '', 'body': 'Laughed at “Sounds good, see you at 7! Bring the projector…”', 'date': _ago(minutes: 2), 'outgoing': true, 'state': 'delivered', 'read': true},
    {'id': 6, 'kind': 'sms', 'address': '+15551230001', 'body': 'Sounds good, see you at 7! Bring the projector cable if you still have it', 'date': _ago(minutes: 4), 'outgoing': false, 'state': 'received', 'read': true},
    {'id': 8, 'kind': 'sms', 'address': '+15551230001', 'body': '❤️ to “Dinner at mine first?”', 'date': _ago(minutes: 20), 'outgoing': false, 'state': 'received', 'read': true},
    {'id': 7, 'kind': 'sms', 'address': '', 'body': 'Correction: Dinner at mine first?', 'date': _ago(minutes: 29), 'outgoing': true, 'state': 'delivered', 'read': true},
    {'id': 5, 'kind': 'sms', 'address': '+15551230001', 'body': 'Dinner at mine first?', 'date': _ago(minutes: 30), 'outgoing': true, 'state': 'delivered', 'read': true, 'edited': true, 'original': 'Diner at mine frist?'},
    {'id': 4, 'kind': 'sms', 'address': '+15551230001', 'body': 'Movie night is still on for tonight right?', 'date': _ago(minutes: 31), 'outgoing': true, 'state': 'delivered', 'read': true},
    {'id': 3, 'kind': 'sms', 'address': '+15551230001', 'body': 'Here\'s the link https://example.com/tickets', 'date': _ago(days: 1, hours: 1), 'outgoing': false, 'state': 'received', 'read': true},
    {'id': 2, 'kind': 'sms', 'address': '+15551230001', 'body': 'Did you get the tickets?', 'date': _ago(days: 1, hours: 1, minutes: 2), 'outgoing': true, 'state': 'sent', 'read': true},
    {'id': 1, 'kind': 'sms', 'address': '+15551230001', 'body': 'Hey! Long time 👋', 'date': _ago(days: 1, hours: 3), 'outgoing': false, 'state': 'received', 'read': true},
  ];
}

void _answerChannel() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async {
    final args = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'status':
        return {'isDefault': true, 'contacts': true, 'notifications': false, 'phone': true};
      case 'conversations':
        return _conversations;
      case 'messages':
        return _messages((args['thread'] as num).toInt());
      case 'people':
        return (_conversations.firstWhere((c) => c['id'] == args['thread'])['people']);
      case 'searchContacts':
        return [
          {'name': 'Maya Chen', 'address': '+1 555-123-0001', 'photo': null, 'label': 'Mobile'},
          {'name': 'Mark Ortiz', 'address': '+1 555-123-0099', 'photo': null, 'label': 'Work'},
          {'name': 'Mom', 'address': '+1 555-123-0010', 'photo': null, 'label': 'Mobile'},
        ];
      case 'update':
        return {'phase': 'available', 'current': '0.6.0', 'available': '0.6.1', 'auto': true, 'canInstall': true, 'source': 'https://ghost-sms.com'};
      case 'ownNumber':
        return '+15551239999';
      case 'e2e':
        return _e2e(args['address'] as String);
      case 'e2eList':
        return [_e2e('+15551230011'), _e2e('+15551230012')];
      case 'e2eMine':
        return '9C41 D07A';
      case 'blockedNumbers':
        return [_p('+15551230090', 'Spam Likely'), _p('+18005550199')];
      case 'keyboardHere':
        return true;
      case 'arriving':
        // Coming from Google Messages, still on the phone; a copy from a file, on Android 16.
        return {'old': 'com.google.android.apps.messaging', 'oldLabel': 'Google Messages', 'oldInstalled': true, 'oldHasRcs': true, 'texts': 1204, 'recentTexts': 38, 'pictures': 56, 'lastReceived': _ago(minutes: 4), 'samsungChats': null, 'sideloaded': true, 'android': 36};
      case 'ghostPeers':
        // Riley is known to have the app (keys were exchanged); nobody else is.
        return (args['addresses'] as List).every((a) => a == '+15551230011');
      case 'prefs':
        return <String, String>{};
      default:
        return null;
    }
  });
}

Future<void> _shoot(WidgetTester tester, TokenSheet sheet, Widget screen, String name, {required bool dark, Map<String, String> prefs = const {}}) async {
  final state = AppState()..setTheme(dark ? 'dark' : 'light');
  for (final e in prefs.entries) {
    state.set(e.key, e.value);
  }
  await tester.pumpWidget(AppScope(
    state: state,
    child: WidgetsApp(
      color: const Color(0xFF4F5BD5),
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
      builder: (context, child) => GlacierTheme(
        sheet: sheet,
        attrs: {'platform': 'mobile', 'theme': state.theme},
        typography: ghostTypography('noto'),
        child: InkOverrides(child: GlacierToastProvider(child: child!)),
      ),
      home: KeyedSubtree(key: ValueKey(name), child: screen),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(milliseconds: 500));
  // The pictures hold the time of day, so they are written (--update-goldens), never compared: a plain run only
  // builds every screen and fails on an exception.
  if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('shots/$name-${dark ? 'dark' : 'light'}.png'));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _shootAgain(WidgetTester tester, String name, {required bool dark}) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // The pictures hold the time of day, so they are written (--update-goldens), never compared: a plain run only
  // builds every screen and fails on an exception.
  if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('shots/$name-${dark ? 'dark' : 'light'}.png'));
}

void main() {
  setUpAll(_fonts);
  testWidgets('screens', (tester) async {
    tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
    addTearDown(tester.view.reset);
    _answerChannel();
    final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
    installSettingsStyles(sheet);
    for (final dark in [false, true]) {
      await _shoot(tester, sheet, const ConversationsScreen(), '1-conversations', dark: dark);
      // Several chosen at once: a long press's Select, then a tap on another.
      await tester.longPress(find.text('Dad'));
      await _settle(tester);
      await tester.tap(find.text('Select'));
      await _settle(tester);
      await tester.tap(find.text('Priya Natarajan'));
      await _shootAgain(tester, '1-conversations-selecting', dark: dark);
      await _shoot(tester, sheet, const ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')]), '2-thread', dark: dark);
      await _shoot(tester, sheet, ThreadScreen(thread: 2, people: [for (final p in _conversations[1]['people'] as List) Person.from(p as Map)]), '3-group', dark: dark);
      await _shoot(tester, sheet, const ComposeScreen(), '4-compose', dark: dark);
      // Settings: its home, a search over it, and a few of its sections' pages.
      await _shoot(tester, sheet, const SettingsScreen(), '5-settings', dark: dark);
      await tester.enterText(find.byType(EditableText).first, 'read');
      await _shootAgain(tester, '5-settings-search', dark: dark);
      for (final id in ['appearance', 'encryption', 'notifications', 'effects', 'keyboard', 'android', 'updates']) {
        await _shoot(tester, sheet, SettingsSectionScreen(id), '5-settings-$id', dark: dark);
      }
      // Encryption in a conversation: on and verified, and a key waiting for a yes.
      await _shoot(tester, sheet, const ThreadScreen(thread: 8, people: [Person(address: '+15551230011', name: 'Riley Fox')]), '8-encrypted', dark: dark);
      await _shoot(tester, sheet, const ThreadScreen(thread: 9, people: [Person(address: '+15551230012', name: 'Noor Haddad')]), '8-encryption-asked', dark: dark);
      // A conversation's own settings, from its cog: its background and bubbles, encryption, mute and pin.
      await _shoot(tester, sheet, const ChatSettingsScreen(thread: 8, people: [Person(address: '+15551230011', name: 'Riley Fox')]), '9-chat-settings', dark: dark, prefs: const {'chat_bg_8': 'preset:rose', 'bubble_8': 'white'});
      // Your bubbles in white, with the line the light page needs round them.
      await _shoot(tester, sheet, const ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')]), '9-bubbles-white', dark: dark, prefs: const {'bubble': 'white'});
      // Chat backgrounds: the picker, and a conversation wearing a wash.
      await _shoot(tester, sheet, const BackgroundPicker(), '9-background-picker', dark: dark);
      // A conversation's own, synced with someone who has the app: the shared one worn, and the switch on.
      await _shoot(tester, sheet, const BackgroundPicker(thread: 8, who: 'Riley Fox', people: [Person(address: '+15551230011', name: 'Riley Fox')]), '9-background-sync', dark: dark, prefs: const {'chat_bg_8': 'preset:rose', 'chat_bg_synced_8': 'preset:rose'});
      await _shoot(tester, sheet, const ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')]), '9-background-dusk', dark: dark, prefs: const {'chat_bg': 'preset:dusk'});
      await _shoot(tester, sheet, SetupScreen(onDone: () {}), '0-setup', dark: dark);
      // Each effect at a moment of its run, over the conversation.
      const night = {ScreenEffect.fireworks, ScreenEffect.celebration, ScreenEffect.lasers, ScreenEffect.snow, ScreenEffect.goodNight, ScreenEffect.party, ScreenEffect.spotlight};
      for (final effect in ScreenEffect.values) {
        final at = switch (effect) { ScreenEffect.fireworks || ScreenEffect.celebration => 0.3, ScreenEffect.lasers => 0.4, ScreenEffect.wow => 0.35, _ => 0.5 };
        if (dark != night.contains(effect)) continue;
        await _shoot(
          tester,
          sheet,
          Stack(children: [
            const Positioned.fill(child: ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')])),
            Positioned.fill(
              child: IgnorePointer(
                child: Builder(
                  builder: (context) => CustomPaint(
                    painter: EffectPainter(effect, AlwaysStoppedAnimation(at), 7, style: context.tokens.textAt(26, color: context.tokens.color('app-ink')), text: 'See you at 7!'),
                  ),
                ),
              ),
            ),
          ]),
          '6-effect-${effect.name}',
          dark: dark,
        );
      }
    }
  });
}
