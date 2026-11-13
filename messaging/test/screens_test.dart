import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/effects.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides, ghostTypography;
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/sms.dart';
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
];

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
        return {'phase': 'available', 'current': '0.3.0', 'available': '0.3.1', 'auto': true, 'canInstall': true, 'source': 'https://ghost-sms.com'};
      case 'ownNumber':
        return '+15551239999';
      default:
        return null;
    }
  });
}

Future<void> _shoot(WidgetTester tester, TokenSheet sheet, Widget screen, String name, {required bool dark}) async {
  final state = AppState()..setTheme(dark ? 'dark' : 'light');
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
      await _shoot(tester, sheet, const ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')]), '2-thread', dark: dark);
      await _shoot(tester, sheet, ThreadScreen(thread: 2, people: [for (final p in _conversations[1]['people'] as List) Person.from(p as Map)]), '3-group', dark: dark);
      await _shoot(tester, sheet, const ComposeScreen(), '4-compose', dark: dark);
      await _shoot(tester, sheet, const SettingsScreen(), '5-settings', dark: dark);
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await _shootAgain(tester, '5-settings-more', dark: dark);
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
