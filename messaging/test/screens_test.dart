import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/effects.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides, ghostTypography;
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/stickers.dart';
import 'package:ghost_messaging/ui/background_picker.dart';
import 'package:ghost_messaging/ui/chat_settings.dart';
import 'package:ghost_messaging/ui/common.dart' show GhostLogo, IconTap;
import 'package:ghost_messaging/ui/compose.dart';
import 'package:ghost_messaging/ui/computers.dart';
import 'package:ghost_messaging/ui/conversations.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:ghost_messaging/ui/setup.dart';
import 'package:ghost_messaging/ui/sticker_picker.dart';
import 'package:ghost_messaging/ui/thread.dart';
import 'package:ghost_messaging/ui/update_banner.dart';
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
  if (thread == 4) {
    // Voice messages (android Voice.kt): one that came, one sent, each a picture message with sound in it.
    return [
      if (_voiceMore) {'id': 54, 'kind': 'mms', 'address': '+15551230001', 'body': '', 'date': _ago(minutes: 1), 'outgoing': false, 'state': 'received', 'read': true, 'parts': [{'id': 913, 'type': 'audio/mp4', 'name': 'voice-20261113-194730.m4a'}]},
      {'id': 53, 'kind': 'mms', 'address': '', 'body': '', 'date': _ago(minutes: 3), 'outgoing': true, 'state': 'sent', 'read': true, 'parts': [{'id': 912, 'type': 'audio/mp4', 'name': 'voice-20261113-194502.m4a'}]},
      {'id': 52, 'kind': 'mms', 'address': '+15551230001', 'body': '', 'date': _ago(minutes: 5), 'outgoing': false, 'state': 'received', 'read': true, 'parts': [{'id': 911, 'type': 'audio/amr', 'name': 'recording.amr'}]},
      {'id': 51, 'kind': 'sms', 'address': '+15551230001', 'body': 'Too much to type, one sec', 'date': _ago(minutes: 6), 'outgoing': false, 'state': 'received', 'read': true},
    ];
  }
  if (thread == 3) {
    // Two picture messages the carrier announced: one that could not be brought down, one coming down now.
    return [
      {'id': 43, 'kind': 'mms', 'address': '+15551230005', 'body': '', 'date': _ago(minutes: 2), 'outgoing': false, 'state': 'downloading', 'read': true, 'parts': []},
      {'id': 42, 'kind': 'mms', 'address': '+15551230005', 'body': '', 'date': _ago(hours: 4), 'outgoing': false, 'state': 'pending_download', 'read': true, 'parts': []},
      {'id': 41, 'kind': 'sms', 'address': '+15551230005', 'body': 'Call me when you land', 'date': _ago(hours: 5), 'outgoing': false, 'state': 'received', 'read': true},
    ];
  }
  if (thread == 2) {
    return [
      // Two of the app's stickers (android Stickers.kt names them): one sent, one from someone else with the app.
      // One that did not go, with why (android MmsWhy.kt).
      {'id': 16, 'kind': 'mms', 'address': '', 'body': 'Trailhead at 9', 'date': _ago(minutes: 47), 'outgoing': true, 'state': 'failed', 'read': true, 'parts': [], 'why': 'mobile data is off. Picture messages need it, even on Wi-Fi'},
      {'id': 15, 'kind': 'mms', 'address': '', 'body': '', 'date': _ago(minutes: 48), 'outgoing': true, 'state': 'sent', 'read': true, 'parts': [{'id': 902, 'type': 'image/png', 'name': 'ghost-sticker-party-03.png'}]},
      {'id': 14, 'kind': 'mms', 'address': '+15551230002', 'body': '', 'date': _ago(minutes: 49), 'outgoing': false, 'state': 'received', 'read': true, 'parts': [{'id': 901, 'type': 'image/png', 'name': 'ghost-sticker-sweet-01.png'}]},
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

/// The pairing with a computer being made, as Android would say it stands (android/.../Desk.kt): set before the
/// pairing screen is drawn at each of its steps.
Map<String, Object?> _pairing = {'phase': 'none'};

int _voiceBeat = 0;

/// A third voice message has arrived in the voice conversation.
bool _voiceMore = false;

/// What the screens asked the phone to do, and the ticks they asked of it: looked at after a row is dragged.
final _asked = <String>[];
final _ticks = <String>[];

void _answerChannel() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') _ticks.add('${call.arguments}');
    return null;
  });
  messenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async {
    final args = (call.arguments as Map?) ?? const {};
    if (call.method == 'archive' || call.method == 'threadFlag' || call.method == 'deleteThread') _asked.add('${call.method} $args');
    switch (call.method) {
      case 'status':
        return {'isDefault': true, 'contacts': true, 'notifications': false, 'phone': true};
      case 'conversations':
        return _conversations;
      case 'conversationsPage':
        // A lot at a time, as the phone hands them over: the archived ones alone, or from a row on.
        if (args['archived'] == true) return {'items': _conversations.where((c) => c['archived'] == true).toList(), 'next': null};
        final from = (args['offset'] as num?)?.toInt() ?? 0;
        final limit = (args['limit'] as num?)?.toInt() ?? 0;
        final to = limit == 0 ? _conversations.length : (from + limit).clamp(0, _conversations.length);
        return {'items': _conversations.sublist(from.clamp(0, _conversations.length), to), 'next': to < _conversations.length ? to : null};
      case 'conversation':
        return _conversations.where((c) => c['id'] == args['thread']).firstOrNull;
      case 'archivedCount':
        return _conversations.where((c) => c['archived'] == true).length;
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
        return {'phase': 'available', 'current': '0.6.1', 'available': '0.6.2', 'auto': true, 'canInstall': true, 'source': 'https://ghost-sms.com'};
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
      // Paired computers: one connected over the local network, one last seen yesterday through the relay.
      case 'deskList':
        return [
          {'id': 'd387c0690aec58b7', 'name': 'Matt\'s MacBook Pro', 'mode': 'both', 'relay': 'wss://ghost-sms.com/relay', 'since': _ago(days: 9), 'seen': _ago(minutes: 1), 'via': 'local'},
          {'id': '0f1e2d3c4b5a6978', 'name': 'Studio iMac', 'mode': 'relay', 'relay': 'wss://ghost-sms.com/relay', 'since': _ago(days: 30), 'seen': _ago(days: 1, hours: 3), 'via': null},
        ];
      case 'deskState':
        return _pairing;
      case 'deskPeek':
        return {'name': 'Matt\'s MacBook Pro', 'mode': 'both', 'relay': 'wss://ghost-sms.com/relay'};
      case 'deskUnrestricted':
        return false;
      case 'deskAddresses':
        return ['192.168.1.20:47811'];
      // Voice messages: how long each runs, and a recording that hears a voice rise and fall.
      case 'voiceLength':
        return switch ((args['part'] as num).toInt()) { 911 => 7400, 913 => 41000, _ => 23000 };
      case 'voiceStart':
        _voiceBeat = 0;
        return {'ok': true, 'seconds': 91};
      case 'voiceLevel':
        _voiceBeat++;
        return 0.04 + 0.5 * ((_voiceBeat * 37) % 17) / 17 * (_voiceBeat % 9 < 6 ? 1 : 0.15);
      case 'devLogRead':
        // The app's own log, as Settings › Developer reads it: a photo that went, and one the carrier refused.
        const lines = [
          '11-13 19:05:02 mms   send to 1: 4000x3000 2143 KB image/jpeg -> 1200x1600 q85 302 KB (HDR left off), words 0, carrier\'s limit 1024 KB',
          '11-13 19:05:04 mms   sent, 310 KB, the carrier\'s id for it fake-1@mmsc',
          '11-13 19:12:40 mms   send to 3: 8160x6120 5210 KB image/heic -> 1600x1200 q85 412 KB, words 14, carrier\'s limit 1024 KB',
          '11-13 19:12:43 mms   not sent, 420 KB: the carrier\'s server refused it (HTTP 413) (result 4, HTTP 413)',
          '11-13 19:13:10 call  send: IllegalStateException: that picture couldn\'t be read (Android no longer lets this app read it; choose it again)',
        ];
        return {'lines': lines, 'report': 'Ghost Messaging 0.6.2\nsamsung SM-F966U, Android 16 (API 36)\n\n${lines.join('\n')}'};
      case 'mmsStatus':
        // Picture messages as the phone reports them: nothing in the way, one sent, one that could not be fetched.
        return {
          'dataOn': true, 'carrier': 'T-Mobile', 'sim': true, 'allowed': true, 'maxBytes': 1048576, 'waiting': 1,
          'lastSend': {'at': _ago(minutes: 12), 'ok': true, 'detail': 'sent, 294 KB'},
          'lastDownload': {'at': _ago(hours: 3), 'ok': false, 'detail': 'the carrier\'s server couldn\'t be reached. Check mobile data'},
        };
      case 'part':
        // The two stickers in the group conversation, as the phone would hand a picture message's part over.
        return switch ((args['id'] as num).toInt()) {
          901 => File('assets/stickers/sweet/01.webp').readAsBytesSync(),
          902 => File('assets/stickers/party/03.webp').readAsBytesSync(),
          _ => null,
        };
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
      // A newer version is waiting: the banner over the page, on every page.
      await _shoot(tester, sheet, const UpdateBanner(child: ConversationsScreen()), '1-update-banner', dark: dark);
      expect(find.textContaining('is out'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      // A row dragged sideways (lib/ui/swipe_actions.dart): to the left past Archive, on past Delete, back to
      // Archive and let go; then to the right past Pin. The phone ticks at each detent it passes into.
      _asked.clear();
      _ticks.clear();
      final left = await tester.startGesture(tester.getCenter(find.text('Dad')));
      await left.moveBy(const Offset(-30, 0));
      await left.moveBy(const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await _shootAgain(tester, '1-conversations-swipe-archive', dark: dark);
      await left.moveBy(const Offset(-180, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await _shootAgain(tester, '1-conversations-swipe-delete', dark: dark);
      await left.moveBy(const Offset(180, 0));
      await left.up();
      await _settle(tester);
      expect(_ticks, ['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.heavyImpact', 'HapticFeedbackType.mediumImpact'], reason: 'a tick into Archive, a knock into Delete, a tick back into Archive');
      expect(_asked.single, startsWith('archive'), reason: 'let go at Archive, it archives and nothing else');
      _asked.clear();
      _ticks.clear();
      // The archive's toast is let pass before the next drag.
      await tester.pump(const Duration(seconds: 6));
      await _settle(tester);
      final right = await tester.startGesture(tester.getCenter(find.text('Dad')));
      await right.moveBy(const Offset(30, 0));
      await right.moveBy(const Offset(90, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await _shootAgain(tester, '1-conversations-swipe-pin', dark: dark);
      await right.up();
      await _settle(tester);
      expect(_ticks, ['HapticFeedbackType.mediumImpact']);
      expect(_asked.single, startsWith('threadFlag'), reason: 'let go at Pin, it changes the pin');
      // A short drag comes to nothing: no tick, nothing asked.
      _asked.clear();
      _ticks.clear();
      final short = await tester.startGesture(tester.getCenter(find.text('Dad')));
      await short.moveBy(const Offset(-30, 0));
      await short.moveBy(const Offset(-20, 0));
      await short.up();
      await _settle(tester);
      expect(_ticks, isEmpty);
      expect(_asked, isEmpty);
      // Several chosen at once: a long press's Select, then a tap on another.
      await tester.longPress(find.text('Dad'));
      await _settle(tester);
      await tester.tap(find.text('Select'));
      await _settle(tester);
      await tester.tap(find.text('Priya Natarajan'));
      await _shootAgain(tester, '1-conversations-selecting', dark: dark);
      await _shoot(tester, sheet, const ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')]), '2-thread', dark: dark);
      // A message held: its reactions under it, the screen effects under those, then what else can be done.
      await tester.longPress(find.text('Movie night is still on for tonight right?'));
      await _shootAgain(tester, '2-thread-held', dark: dark);
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('🎈'), findsOneWidget, reason: 'the screen effects are offered beside the reactions');
      expect(find.text('Copy text'), findsOneWidget);
      // An incoming one near the top: the same, on its own side.
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);
      expect(find.text('Copy text'), findsNothing);
      await tester.longPress(find.text('Hey! Long time 👋'));
      await _shootAgain(tester, '2-thread-held-theirs', dark: dark);
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);
      // A picture that could not be downloaded, shown where it would be with a way to ask for it again; and one
      // being brought down.
      await _shoot(tester, sheet, const ThreadScreen(thread: 3, people: [Person(address: '+15551230005', name: 'Dad')]), '2-thread-picture-failed', dark: dark);
      expect(find.text('This picture couldn\'t be downloaded'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Downloading picture…'), findsOneWidget);
      // Voice messages: each drawn as a player that says how long it runs; the microphone stands where Send would.
      await _shoot(tester, sheet, const ThreadScreen(thread: 4, people: [Person(address: '+15551230001', name: 'Maya Chen')]), '2-thread-voice', dark: dark);
      expect(find.text('0:07'), findsOneWidget);
      expect(find.text('0:23'), findsOneWidget);
      final mic = find.byWidgetPredicate((w) => w is IconTap && w.label == 'Record a voice message');
      expect(mic, findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Send'), findsNothing);
      // One playing: where it has got to, and Pause where Play was.
      Sms.instance.voice.add(const VoicePlayback(part: 911, position: Duration(seconds: 3), length: Duration(milliseconds: 7400), playing: true));
      await _settle(tester);
      expect(find.text('0:03'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is GlacierPressable && w.semanticLabel == 'Pause voice message'), findsOneWidget);
      // Another starts: the first is back at its start.
      Sms.instance.voice.add(const VoicePlayback(part: 912, position: Duration(seconds: 1), length: Duration(seconds: 23), playing: true));
      await _settle(tester);
      expect(find.text('0:07'), findsOneWidget);
      expect(find.text('0:01'), findsOneWidget);
      Sms.instance.voice.add(const VoicePlayback(part: 912, position: Duration.zero, length: Duration(seconds: 23), playing: false));
      // Another arrives: each still says its own length (the list hands a player's place to another message, and
      // every one once wore the length of the first drawn there).
      _voiceMore = true;
      Sms.instance.changes.add(4);
      await _settle(tester);
      expect(find.text('0:41'), findsOneWidget);
      expect(find.text('0:23'), findsOneWidget);
      expect(find.text('0:07'), findsOneWidget);
      _voiceMore = false;
      // The microphone tapped: the composer is the recording, with its clock, how loud it is, and Send.
      await tester.tap(mic);
      for (var i = 0; i < 44; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _shootAgain(tester, '2-thread-voice-recording', dark: dark);
      expect(find.text('0:04'), findsOneWidget, reason: 'the clock counts while it records');
      expect(find.text('1:31'), findsOneWidget, reason: 'how long one may run on this carrier');
      expect(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Send voice message'), findsOneWidget);
      expect(mic, findsNothing);
      // Thrown away: the composer is as it was.
      await tester.tap(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Discard the recording'));
      await _settle(tester);
      expect(mic, findsOneWidget);
      // Words written: Send is back where the microphone stood.
      await tester.enterText(find.byType(EditableText), 'On my way');
      await _settle(tester);
      expect(mic, findsNothing);
      expect(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Send'), findsOneWidget);
      await _shoot(tester, sheet, ThreadScreen(thread: 2, people: [for (final p in _conversations[1]['people'] as List) Person.from(p as Map)]), '3-group', dark: dark);
      await _shoot(tester, sheet, const ComposeScreen(), '4-compose', dark: dark);
      // The banner over a conversation: under its header, over its messages, with its cross.
      await _shoot(tester, sheet, const UpdateBanner(child: ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')])), '1-update-banner-thread', dark: dark);
      expect(find.bySemanticsLabel('Not now'), findsWidgets);
      // Nothing to show (here, nothing a search finds): the app's logo stands where the list would be.
      await _shoot(tester, sheet, const ConversationsScreen(), '1-conversations-none', dark: dark);
      await tester.enterText(find.byType(EditableText).first, 'zzzz');
      // The empty screen is built, then its picture is given the real time it takes to be read.
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await _shootAgain(tester, '1-conversations-none', dark: dark);
      expect(find.byType(GhostLogo), findsOneWidget);
      // The stickers' sheet over a conversation: the first pack, then the pastel one, in an encrypted conversation.
      final packs = (await tester.runAsync(stickerPacks))!;
      expect(packs.map((p) => p.name), ['Ghost', 'Love', 'Party', 'Sweet', 'Mischief']);
      for (final (pack, encrypted) in [('ghost', false), ('sweet', true), ('mischief', false)]) {
        await _shoot(
          tester,
          sheet,
          Stack(children: [
            const Positioned.fill(child: ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')])),
            const Positioned.fill(child: ColoredBox(color: Color(0x66000000))),
            Positioned.fill(child: StickerSheet(packs: packs, encrypted: encrypted)),
          ]),
          '4-stickers-$pack',
          dark: dark,
          prefs: {'sticker_pack': pack},
        );
        // The pictures are decoded off the fake clock.
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await _shootAgain(tester, '4-stickers-$pack', dark: dark);
      }
      // Settings: its home, a search over it, and a few of its sections' pages.
      await _shoot(tester, sheet, const SettingsScreen(), '5-settings', dark: dark);
      await tester.enterText(find.byType(EditableText).first, 'read');
      await _shootAgain(tester, '5-settings-search', dark: dark);
      for (final id in ['appearance', 'encryption', 'notifications', 'effects', 'keyboard', 'android', 'updates', 'computers', 'developer']) {
        await _shoot(tester, sheet, SettingsSectionScreen(id), '5-settings-$id', dark: dark);
      }
      // Pairing with a computer, step by step: before a code is scanned, while the computer is looked for, the six
      // digits to compare, and paired.
      const mac = {'name': 'Matt\'s MacBook Pro', 'mode': 'both', 'offered': 'both', 'relay': 'wss://ghost-sms.com/relay'};
      for (final (name, state) in <(String, Map<String, Object?>)>[
        ('start', {'phase': 'none'}),
        ('waiting', {...mac, 'phase': 'waiting'}),
        ('code', {...mac, 'phase': 'code', 'code': '874151'}),
        ('done', {...mac, 'phase': 'done', 'code': '874151', 'mine': true, 'theirs': true}),
      ]) {
        _pairing = state;
        await _shoot(tester, sheet, const PairComputerScreen(), '10-pair-$name', dark: dark);
      }
      _pairing = {'phase': 'none'};
      // The phone's camera opened a computer's pairing link: asked first, before anything is done with it.
      await _shoot(tester, sheet, const PairComputerScreen(offered: 'ghostmsg://pair/abc'), '10-pair-asked', dark: dark);
      expect(find.text('Pair with Matt\'s MacBook Pro?'), findsOneWidget);
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
        // The effect's own pictures (assets/effects/, cut by tool/effect_sprites.py), decoded off the fake clock.
        final sprites = await tester.runAsync(() => EffectSprites.of(effect));
        expect(sprites, isNotNull, reason: '${effect.name} has no pictures in assets/effects/');
        expect(sprites!.heroes, isNotEmpty, reason: '${effect.name} has no characters');
        expect(sprites.props, isNotEmpty, reason: '${effect.name} has no props');
        // Its characters move (tool/effect_anims.py): all four, but for the two Matt has not drawn yet.
        expect(sprites.animated, effect == ScreenEffect.balloons || effect == ScreenEffect.confetti ? 3 : 4, reason: '${effect.name} has ${sprites.animated} moving characters');
        await _shoot(
          tester,
          sheet,
          Stack(children: [
            const Positioned.fill(child: ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')])),
            Positioned.fill(
              child: IgnorePointer(
                child: Builder(
                  builder: (context) => CustomPaint(
                    painter: EffectPainter(effect, AlwaysStoppedAnimation(at), 7, style: context.tokens.textAt(26, color: context.tokens.color('app-ink')), text: 'See you at 7!', sprites: sprites),
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
