import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/effects.dart';
import 'package:ghost_messaging/friends/friends.dart';
import 'package:ghost_messaging/friends/groups.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides, ghostTypography;
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/net.dart';
import 'package:ghost_messaging/plugins/ui.dart' show PluginRow, SectionChips;
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/stickers.dart';
import 'package:ghost_messaging/ui/background_picker.dart';
import 'package:ghost_messaging/ui/chat_settings.dart';
import 'package:ghost_messaging/ui/common.dart' show GhostLogo, IconTap;
import 'package:ghost_messaging/ui/compose.dart';
import 'package:ghost_messaging/ui/computers.dart';
import 'package:ghost_messaging/ui/contacts.dart';
import 'package:ghost_messaging/ui/conversations.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:ghost_messaging/ui/nav_bar.dart';
import 'package:ghost_messaging/ui/new_group.dart';
import 'package:ghost_messaging/ui/network.dart' show inviteText;
import 'package:ghost_messaging/ui/setup.dart';
import 'package:ghost_messaging/ui/shell.dart';
import 'package:ghost_messaging/ui/sticker_picker.dart';
import 'package:ghost_messaging/ui/thread.dart';
import 'package:ghost_messaging/ui/update_banner.dart';
import 'package:glacier/glacier.dart';

import 'support/fake_friends.dart';
import 'support/fake_groups.dart';

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

/// The warning that Sam's texts are coming without encryption: put away, or encryption turned off with him.
bool _plainSeen = false;

/// The lines about a group of friends kept in conversation 2 (android Groups.note), for the groups' test alone.
final List<String> _groupNotes = [];

/// Where being friends with Maya stands (android E2e.friend), for the friends' test alone: '' everywhere else.
String _mayaFriend = '';
bool _plainOff = false;

/// What the plugins sort (lib/plugins), added to the list for their own pictures: sign-in codes from short numbers,
/// and two texts that look like spam.
final _sortable = <Map<String, Object>>[
  {'id': 101, 'date': _ago(minutes: 2), 'people': [_p('70220')], 'snippet': '771-204 is your login code. It expires in 10 minutes.', 'unread': true, 'error': false, 'archived': false},
  {'id': 102, 'date': _ago(hours: 3), 'people': [_p('+18005550142')], 'snippet': 'Use PIN 9041 to sign in to your account', 'unread': false, 'error': false, 'archived': false},
  {'id': 103, 'date': _ago(minutes: 20), 'people': [_p('+15559870002')], 'snippet': 'Congratulations! You\'ve won a \$1,000 gift card. Claim now: http://prize.example/win', 'unread': true, 'error': false, 'archived': false},
  {'id': 104, 'date': _ago(days: 2), 'people': [_p('+15559870004')], 'snippet': 'Your package could not be delivered. Reschedule here: bit.ly/3xYz', 'unread': false, 'error': false, 'archived': false},
];

/// Where encryption stands with each person (android/.../E2e.kt): on and verified with Riley, Noor's key waiting
/// for a yes, nothing with anyone else.
Map<String, Object?> _e2e(String address) => switch (address) {
      '+15551230011' => {'address': address, 'state': 'on', 'verified': true, 'changed': false, 'safety': '04821 77310 59264 10388 92745 36601', 'person': _p(address, 'Riley Fox')},
      '+15551230012' => {'address': address, 'state': 'pending', 'verified': false, 'changed': false, 'safety': '61120 08347 55902 73418 20056 94471', 'person': _p(address, 'Noor Haddad')},
      // Encryption is on with Sam, whose last two texts came without it (or it was turned off, or the warning put away).
      '+15551230013' => {'address': address, 'state': _plainOff ? 'none' : 'on', 'verified': false, 'changed': false, 'person': _p(address, 'Sam Rivera'), 'plain': _plainOff || _plainSeen ? 0 : 2, 'declined': _plainOff},
      // Maya has the app too (its hello came from her), and nothing has been exchanged: the conversation offers it.
      // Adding her as a friend sends this phone's key ('want'), and being asked or being friends means keys are exchanged.
      '+15551230001' => {'address': address, 'state': switch (_mayaFriend) { '' => 'none', 'want' => 'offered', _ => 'on' }, 'verified': false, 'changed': false, 'hasGhost': true, 'declined': false, 'friend': _mayaFriend, 'person': _p(address, 'Maya Chen')},
      _ => {'address': address, 'state': 'none', 'verified': false, 'changed': false},
    };

List<Map<String, Object?>> _messages(int thread) {
  if (thread == 6) {
    // Encryption is on with Sam: one text of his came sealed, then two came without it.
    return [
      {'id': 73, 'kind': 'sms', 'address': '+15551230013', 'body': 'You there?', 'date': _ago(minutes: 1), 'outgoing': false, 'state': 'received', 'read': true},
      {'id': 72, 'kind': 'sms', 'address': '+15551230013', 'body': 'New phone, who dis', 'date': _ago(minutes: 3), 'outgoing': false, 'state': 'received', 'read': true},
      {'id': 71, 'kind': 'sms', 'address': '+15551230013', 'body': 'See you Friday', 'date': _ago(days: 1), 'outgoing': false, 'state': 'received', 'read': true, 'encrypted': true},
    ];
  }
  if (thread == 5) {
    // Videos: one that came, which a picture can be made of, and one sent of a kind the phone cannot read.
    return [
      {'id': 63, 'kind': 'mms', 'address': '', 'body': 'You and Trin in that game', 'date': _ago(minutes: 2), 'outgoing': true, 'state': 'sent', 'read': true, 'parts': [{'id': 922, 'type': 'video/webm', 'name': '9864ade8-2512-4c3f-83b2-8d46dbb76b14.webm'}]},
      {'id': 62, 'kind': 'mms', 'address': '+15551230001', 'body': '', 'date': _ago(minutes: 4), 'outgoing': false, 'state': 'received', 'read': true, 'parts': [{'id': 921, 'type': 'video/mp4', 'name': 'clip.mp4'}]},
      {'id': 61, 'kind': 'sms', 'address': '+15551230001', 'body': 'Look at this', 'date': _ago(minutes: 5), 'outgoing': false, 'state': 'received', 'read': true},
    ];
  }
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

/// The videos asked to be played, by their parts.
final _videosPlayed = <int>[];

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
    if (call.method == 'archive' || call.method == 'threadFlag' || call.method == 'deleteThread' || call.method == 'openLink') _asked.add('${call.method} $args');
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
      case 'threadName':
        // android Store.setThreadName: kept trimmed, and an empty one takes the name away.
        final name = (args['name'] as String).trim();
        final named = _conversations.firstWhere((c) => c['id'] == args['thread']);
        if (name.isEmpty) {
          named.remove('name');
        } else {
          named['name'] = name;
        }
        return null;
      case 'archivedCount':
        return _conversations.where((c) => c['archived'] == true).length;
      case 'messages':
        final thread = (args['thread'] as num).toInt();
        // Between friends the last things said went by the internet, sealed.
        if (thread == 1 && _mayaFriend == 'yes') {
          final all = _messages(thread);
          return [for (final m in all) (m['id'] as int) >= 6 ? {...m, 'via': 'net', 'encrypted': true} : m];
        }
        // A group of friends' conversation holds lines about the group itself, newest first like the rest.
        if (thread == 2 && _groupNotes.isNotEmpty) {
          return [
            for (var i = _groupNotes.length - 1; i >= 0; i--)
              {'id': 900 + i, 'kind': 'mms', 'address': '', 'body': _groupNotes[i], 'notice': 'group', 'date': DateTime.now().millisecondsSinceEpoch - (_groupNotes.length - i), 'outgoing': true, 'state': 'sent', 'read': true},
            ..._messages(thread),
          ];
        }
        return _messages(thread);
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
      // A link pressed in a message: the browser took it.
      case 'openLink':
        return true;
      // The app's routes (lib/net): who this phone is, and the two people encryption is on with or waiting.
      case 'netIdentity':
        return {'id': '0f' * 16, 'key': 'AlFcPW655Ja5BNP+yn9U/c0MwemXvzddylFa0KbDtANf'};
      case 'netPeers':
        return [
          {'id': 'a1' * 16, 'address': '+15551230011', 'key': Uint8List.fromList(List.filled(32, 7))},
          {'id': 'b2' * 16, 'address': '+15551230012', 'key': Uint8List.fromList(List.filled(32, 9))},
        ];
      case 'contact':
        return _conversations.expand((c) => c['people'] as List).cast<Map>().firstWhere((p) => p['address'] == args['address'], orElse: () => _p(args['address'] as String));
      // A new chat's people have a conversation: the first one, here.
      case 'threadFor':
        return 1;
      case 'netSmsAvailable':
        return false;
      case 'netSmsDrain':
        return const <Object>[];
      case 'e2e':
        return _e2e(args['address'] as String);
      case 'e2ePlainSeen':
        _plainSeen = true;
        return null;
      case 'e2eOff':
        _plainOff = true;
        return null;
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
      // Videos: a picture of where one starts and how long it runs; none for the kind that cannot be read.
      case 'videoPreview':
        return (args['part'] as num).toInt() == 921
            ? {'picture': File('assets/stickers/party/03.webp').readAsBytesSync(), 'millis': 12400, 'width': 640, 'height': 360}
            : {'picture': null, 'millis': 0, 'width': 0, 'height': 0};
      case 'videoPlay':
        _videosPlayed.add((args['part'] as num).toInt());
        return null;
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
      // The list as the app shows it: in its frame (lib/ui/shell.dart), the pill at its foot.
      await _shoot(tester, sheet, const AppShell(), '1-conversations', dark: dark);
      expect(find.byType(NavPill), findsOneWidget);
      // A newer version is waiting: the banner over the page, on every page.
      await _shoot(tester, sheet, const UpdateBanner(child: AppShell()), '1-update-banner', dark: dark);
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
      // A link in a message opens in the browser when pressed (lib/links.dart): the address, and nothing else of
      // the message's words.
      _asked.clear();
      await tester.tapOnText(find.textRange.ofSubstring('https://example.com/tickets'));
      await _settle(tester);
      expect(_asked, ['openLink {url: https://example.com/tickets}']);
      _asked.clear();
      // A message held: its reactions under it, then what else can be done, the screen effects one item of that.
      await tester.longPress(find.text('Movie night is still on for tonight right?'));
      await _shootAgain(tester, '2-thread-held', dark: dark);
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('🎈'), findsNothing, reason: 'the effects are behind Effects, not a row of their pictures');
      expect(find.text('Copy text'), findsOneWidget);
      // Effects opens them in the menu's own place, each by its name, with the way back at the top.
      await tester.tap(find.text('Effects'));
      await _settle(tester);
      await _shootAgain(tester, '2-thread-held-effects', dark: dark);
      expect(find.text('Copy text'), findsNothing);
      expect(find.text('Confetti'), findsOneWidget);
      expect(find.text('🎈'), findsOneWidget);
      await tester.tap(find.text('Effects'));
      await _settle(tester);
      expect(find.text('Copy text'), findsOneWidget, reason: 'the way back is the sub-menu\'s own first row');
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
      // Encryption is on with someone whose texts have started coming without it: the conversation says so, with
      // Turn off beside it (Matt: "detect if a user is sending us unencrypted messages and let us know so we can
      // disable it"). Put away, it goes; turned off, the conversation is plain again.
      _plainSeen = false;
      _plainOff = false;
      const sam = [Person(address: '+15551230013', name: 'Sam Rivera')];
      await _shoot(tester, sheet, const ThreadScreen(thread: 6, people: sam), '2-thread-plain-warning', dark: dark);
      expect(find.textContaining('last 2 texts came without encryption'), findsOneWidget);
      final turnOff = find.byWidgetPredicate((w) => w is GlacierPressable && w.semanticLabel == 'Turn off');
      expect(turnOff, findsOneWidget);
      await tester.tap(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Not now'));
      await _settle(tester);
      expect(_plainSeen, isTrue);
      expect(find.textContaining('came without encryption'), findsNothing);
      _plainSeen = false;
      await _shoot(tester, sheet, const ThreadScreen(key: ValueKey('again'), thread: 6, people: sam), '2-thread-plain-warning', dark: dark);
      await tester.tap(turnOff);
      await _settle(tester);
      expect(_plainOff, isTrue);
      expect(find.textContaining('came without encryption'), findsNothing);
      // Videos: a picture of where each starts with Play over it and its length, where it was the file's name
      // and no more (Matt: "mp4 files are not loading it just shows up as a string of text for the filename").
      _videosPlayed.clear();
      await _shoot(tester, sheet, const ThreadScreen(thread: 5, people: [Person(address: '+15551230001', name: 'Maya Chen')]), '2-thread-video', dark: dark);
      final players = find.byWidgetPredicate((w) => w is GlacierPressable && w.semanticLabel == 'Play video');
      expect(players, findsNWidgets(2));
      expect(find.text('0:12'), findsOneWidget);
      expect(find.text('clip.mp4'), findsNothing, reason: 'one with a picture is not named');
      // One no picture can be made of is still named, and can still be tried.
      expect(find.text('9864ade8-2512-4c3f-83b2-8d46dbb76b14.webm'), findsOneWidget);
      await tester.tap(players.first);
      await _settle(tester);
      await tester.tap(players.last);
      await _settle(tester);
      expect(_videosPlayed.toSet(), {921, 922});
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
      // Settings › Network: the app's routes, with two people to reach, the relay server ready and SMS not allowed,
      // and a test sent to one of them.
      final hub = _Route('hub', 'Relay server', 'Through a server on the internet. Works between any two networks; the server sees who talks to whom, never what is said.');
      final sms = _Route('sms', 'SMS', 'As data texts over the phone network. Needs no internet and reaches a phone whose app is closed.', up: false, metered: true)
        ..problem = 'This phone cannot send data texts now: no SIM, or SMS is not allowed for this app';
      await tester.runAsync(() => Net.instance.start(AppState(), carriers: [hub, sms]));
      expect(Net.instance.people.map((p) => p.name), ['Riley Fox', 'Noor Haddad']);
      await tester.runAsync(() => Net.instance.test(Net.instance.people.first));
      await _shoot(tester, sheet, const SettingsSectionScreen('network'), '5-settings-network', dark: dark);
      expect(find.text('Relay server'), findsWidgets);
      expect(find.textContaining('Ready'), findsOneWidget);
      expect(find.textContaining('cannot send data texts'), findsOneWidget);
      expect(find.textContaining('A test was sent to Riley Fox'), findsOneWidget);
      expect(find.text('Invite someone by text'), findsOneWidget);
      expect(inviteText, contains('https://ghost-sms.com'));
      expect(hub.carried, 1, reason: 'the test went by the route that is up');
      expect(sms.carried, 0);
      await tester.runAsync(Net.instance.shutdown);
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

  // The plugins (lib/plugins): the list with its sections' chips, the Codes section, and Settings › Plugins.
  // Pictures 12-plugins-*.
  testWidgets('plugins: the list\'s sections and Settings › Plugins', (tester) async {
    tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
    addTearDown(tester.view.reset);
    _answerChannel();
    // More of what the plugins sort than the list above holds, for this test alone.
    _conversations.addAll(_sortable);
    addTearDown(() => _conversations.removeWhere((c) => (c['id'] as int) >= 100));
    final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
    installSettingsStyles(sheet);
    Finder chip(String label) => find.descendant(of: find.byType(SectionChips), matching: find.text(label));
    for (final dark in [false, true]) {
      // The list as it opens: the codes have left it for their chip, which counts them.
      await _shoot(tester, sheet, const ConversationsScreen(), '12-plugins-list', dark: dark);
      expect(chip('Messages'), findsOneWidget);
      expect(chip('Codes'), findsOneWidget);
      expect(find.textContaining('482913'), findsNothing);
      // Codes: the newest first, each code large over the words it came in, with Copy at the row's end.
      await tester.tap(chip('Codes'));
      await _shootAgain(tester, '12-plugins-codes', dark: dark);
      expect(find.byType(PluginRow), findsNWidgets(3));
      expect(find.text('482913'), findsOneWidget);
      // A tap copies, and says so.
      await tester.tap(find.text('771204'));
      await _shootAgain(tester, '12-plugins-codes-copied', dark: dark);
      expect(find.text('Copied 771204'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await _settle(tester);
      // Settings › Plugins: each plugin with its switch, and its own settings under it. The spam filter is off.
      await _shoot(tester, sheet, const SettingsSectionScreen('plugins'), '12-plugins-settings', dark: dark);
      expect(find.text('Mark as read when copied'), findsOneWidget);
      expect(find.text('Spam filter'), findsOneWidget);
      expect(find.text('Mute conversations in Spam'), findsNothing);
      // The spam filter switched on: Spam beside Codes, and in it each conversation with why it is there.
      await _shoot(tester, sheet, const ConversationsScreen(), '12-plugins-spam', dark: dark, prefs: const {'plugin_spam': 'on'});
      expect(find.textContaining('You\'ve won'), findsNothing, reason: 'spam has left the main list');
      await tester.tap(chip('Spam'));
      await _shootAgain(tester, '12-plugins-spam', dark: dark);
      expect(find.byType(PluginRow), findsNWidgets(2));
      expect(find.text('Looks like spam: a link, prize wording'), findsOneWidget);
      expect(find.text('Not spam'), findsNWidgets(2));
      // And its own settings, with what counts as spam said rule by rule.
      await _shoot(tester, sheet, const SettingsSectionScreen('plugins'), '12-plugins-settings-spam', dark: dark, prefs: const {'plugin_spam': 'on'});
      expect(find.text('Mute conversations in Spam'), findsOneWidget);
      await tester.drag(find.text('Mute conversations in Spam'), const Offset(0, -520));
      await _shootAgain(tester, '12-plugins-settings-spam-rules', dark: dark);
    }
  });

  // The app's frame (lib/ui/shell.dart): the list beside what is opened from it where the window is wide, under it
  // where it is narrow, and the same pages kept as the window changes. Pictures 11-frame-*.
  testWidgets('a group is given a name', (tester) async {
    tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
    addTearDown(tester.view.reset);
    _answerChannel();
    final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
    installSettingsStyles(sheet);
    const group = [Person(address: '+15551230002', name: 'Jordan Park'), Person(address: '+15551230003', name: 'Sam Rivera'), Person(address: '+15551230004', name: 'Alex Kim')];
    addTearDown(() => _conversations.firstWhere((c) => c['id'] == 2).remove('name'));
    for (final dark in [false, true]) {
      _conversations.firstWhere((c) => c['id'] == 2).remove('name');
      // The group's settings have a field for its name (Matt: "expand on the ability to create, name and manage
      // groups like telegram"), which shows what it goes by until one is given: its people's first names.
      await _shoot(tester, sheet, ChatSettingsScreen(key: ValueKey('group-$dark'), thread: 2, people: group), '14-group-name-settings', dark: dark);
      expect(find.textContaining(RegExp('group name', caseSensitive: false)), findsOneWidget);
      expect(find.text('Jordan, Sam, Alex'), findsWidgets);
      await tester.enterText(find.byType(EditableText).first, '  Weekend crew ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _shootAgain(tester, '14-group-name-settings', dark: dark);
      expect(_conversations.firstWhere((c) => c['id'] == 2)['name'], 'Weekend crew');
      // The page's own heading, the list and the conversation go by it from then on.
      expect(find.text('Weekend crew'), findsWidgets);
      await tester.pump(const Duration(seconds: 6));
      await _shoot(tester, sheet, ConversationsScreen(key: ValueKey('list-$dark')), '14-group-name-list', dark: dark);
      expect(find.text('Weekend crew'), findsOneWidget);
      expect(find.text('Jordan, Sam, Alex'), findsNothing);
      await _shoot(tester, sheet, ThreadScreen(key: ValueKey('named-$dark'), thread: 2, people: group), '14-group-name-thread', dark: dark);
      expect(find.text('Weekend crew'), findsOneWidget);
      // Emptied, the group goes by its people again. One person's conversation has no such field.
      await _shoot(tester, sheet, ChatSettingsScreen(key: ValueKey('group-again-$dark'), thread: 2, people: group), '14-group-name-settings', dark: dark);
      await tester.enterText(find.byType(EditableText).first, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(_conversations.firstWhere((c) => c['id'] == 2)['name'], isNull);
      await tester.pump(const Duration(seconds: 6));
      await _shoot(tester, sheet, const ChatSettingsScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')]), '9-chat-settings-one', dark: dark);
      expect(find.textContaining(RegExp('group name', caseSensitive: false)), findsNothing);
    }
  });

  testWidgets('groups of friends: made, written in, managed, left', (tester) async {
    tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
    addTearDown(tester.view.reset);
    _answerChannel();
    final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
    installSettingsStyles(sheet);
    const jordan = Person(address: '+15551230002', name: 'Jordan Park'), sam = Person(address: '+15551230003', name: 'Sam Rivera'), alex = Person(address: '+15551230004', name: 'Alex Kim');
    addTearDown(() {
      Friends.instance = null;
      Groups.instance = null;
      _groupNotes.clear();
    });
    for (final dark in [false, true]) {
      // This phone and three others, each a friend of this one; a relay server answers.
      final world = World();
      final mine = _GroupsPort(world, '+15550000000');
      for (final p in [jordan, sam, alex]) {
        FakeGroupsPort(world, p.address).friends.add(mine.number);
        mine.friends.add(p.address);
        mine.names[p.address] = p.name!;
      }
      _groupNotes.clear();
      final friends = Friends(_ThreeFriends('+15550000000', [jordan, sam, alex]));
      Friends.instance = friends;
      final groups = Groups(mine);
      Groups.instance = groups;
      await friends.start();
      await groups.start();
      // The address book offers New group where there is a friend to put in one.
      await _shoot(tester, sheet, ContactsScreen(key: ValueKey('contacts-$dark')), '15-groups-contacts', dark: dark);
      expect(find.text('New group'), findsOneWidget);
      // Its name, and who is in it; Create waits for someone to be chosen.
      await _shoot(tester, sheet, NewGroupScreen(key: ValueKey('new-$dark')), '15-groups-new', dark: dark);
      await tester.tap(find.text('Create'));
      await _settle(tester);
      expect(groups.all, isEmpty);
      await tester.enterText(find.byType(EditableText).first, 'Weekend crew');
      await tester.tap(find.text('Jordan Park'));
      await tester.tap(find.text('Sam Rivera'));
      await _shootAgain(tester, '15-groups-new', dark: dark);
      expect(find.text('2 chosen. You will be its admin.'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await _settle(tester);
      final made = groups.all.single;
      expect(made.name, 'Weekend crew');
      expect(made.members.length, 3);
      expect(made.amAdmin, isTrue);
      // Its conversation: its name, how many are in it, the line that says it was made, and words alone to write.
      mine.threads[made.id] = 2;
      await groups.refresh();
      await _shoot(tester, sheet, ThreadScreen(key: ValueKey('group-$dark'), thread: 2, people: const [jordan, sam]), '15-groups-thread', dark: dark);
      expect(find.text('Weekend crew'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
      expect(find.text('You made the group "Weekend crew"'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Add an attachment'), findsNothing);
      await tester.enterText(find.byType(EditableText).first, 'Hike on Saturday?');
      await tester.pump();
      await tester.tap(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Send'));
      await _settle(tester);
      expect(mine.rows.values.single, (group: made.id, words: 'Hike on Saturday?', state: 'sent'));
      // Its settings, for its admin: the name everyone sees, the members, adding a friend, making another admin,
      // taking someone out.
      await tester.pump(const Duration(seconds: 6));
      await _shoot(tester, sheet, ChatSettingsScreen(key: ValueKey('gs-$dark'), thread: 2, people: const [jordan, sam]), '15-groups-settings', dark: dark);
      expect(find.text('Everyone in the group sees this name.'), findsOneWidget);
      // Far enough down for the last of the members' rows, and no further.
      Scrollable.ensureVisible(tester.element(find.text('Leave group')), alignment: 0.85);
      await _settle(tester);
      await _shootAgain(tester, '15-groups-settings', dark: dark);
      expect(find.text('Admin'), findsOneWidget);
      await tester.tap(find.text('Add people'));
      await _settle(tester);
      await tester.tap(find.text('Alex Kim'));
      await _settle(tester);
      expect(groups.of(made.id)!.members.length, 4);
      expect(_groupNotes.last, 'You added Alex Kim');
      await tester.pump(const Duration(seconds: 6));
      await tester.tap(find.text('Sam Rivera'));
      await _shootAgain(tester, '15-groups-member', dark: dark);
      await tester.tap(find.text('Make admin'));
      await _settle(tester);
      expect(groups.of(made.id)!.members.where((m) => m.admin).length, 2);
      await tester.tap(find.text('Jordan Park'));
      await _settle(tester);
      await tester.tap(find.text('Remove from group'));
      await _settle(tester);
      expect(groups.of(made.id)!.members.map((m) => m.label), ['You', 'Sam Rivera', 'Alex Kim']);
      // Leaving: the conversation stays, and says nothing more can be written in it.
      await tester.tap(find.text('Leave group'));
      await _settle(tester);
      await tester.tap(find.text('Leave group').last);
      await _settle(tester);
      expect(groups.of(made.id)!.gone, isTrue);
      expect(find.text('You are no longer in this group.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await _shoot(tester, sheet, ThreadScreen(key: ValueKey('left-$dark'), thread: 2, people: const [sam, alex]), '15-groups-left', dark: dark);
      expect(find.text('You are no longer in this group.'), findsOneWidget);
      expect(find.text('You left the group'), findsOneWidget);
    }
  });

  testWidgets('friends: the offer, a request each way, friends', (tester) async {
    tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
    addTearDown(tester.view.reset);
    _answerChannel();
    final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
    installSettingsStyles(sheet);
    const maya = [Person(address: '+15551230001', name: 'Maya Chen')];
    // The routes and the phone under Friends, standing in: what it is told about Maya is what the phone then says.
    final port = _FriendsPort('+15550000000');
    port.other = FakePort('+15551230001')..other = port;
    addTearDown(() {
      Friends.instance = null;
      _mayaFriend = '';
    });
    for (final dark in [false, true]) {
      // No relay server is known to answer (a phone that has never reached one: once one has answered, friends
      // stay offered): the conversation offers encryption as it always did, and no friend.
      Friends.instance = Friends(port);
      _mayaFriend = '';
      port.up = false;
      await _shoot(tester, sheet, ThreadScreen(key: ValueKey('none-$dark'), thread: 1, people: maya), '13-friends-none', dark: dark);
      expect(find.text('Add friend'), findsNothing);
      expect(find.text('Turn on'), findsOneWidget);
      // One answers (Matt: "If both users chatting are on ghost messenger show an 'add friend' button"): Add friend
      // stands where the offer of encryption stood.
      port.up = true;
      await _shoot(tester, sheet, ThreadScreen(key: ValueKey('offer-$dark'), thread: 1, people: maya), '13-friends-offer', dark: dark);
      expect(find.text('Add friend'), findsOneWidget);
      expect(find.text('Turn on'), findsNothing);
      // Pressed: this phone's key goes to her first, and the asking waits for hers.
      port.keysSent.clear();
      await tester.tap(find.text('Add friend'));
      await _shootAgain(tester, '13-friends-asked', dark: dark);
      expect(port.keysSent, ['+15551230001']);
      expect(_mayaFriend, 'want');
      expect(find.text('Friend request sent. Waiting for Maya Chen to accept.'), findsOneWidget);
      expect(find.text('Add friend'), findsNothing);
      // She asked: said until it is answered. Accepted, the two are friends and the conversation says so; what was
      // last said went by the internet.
      _mayaFriend = 'invited';
      await _shoot(tester, sheet, ThreadScreen(key: ValueKey('invited-$dark'), thread: 1, people: maya), '13-friends-invited', dark: dark);
      expect(find.textContaining('wants to add you as a friend'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await _shootAgain(tester, '13-friends', dark: dark);
      expect(_mayaFriend, 'yes');
      expect(find.text('Friend · encrypted'), findsOneWidget);
      expect(find.textContaining('wants to add you as a friend'), findsNothing);
      // The conversation's settings say it, with the way to stop. (The words that said they are friends have gone
      // by then: they stand over the foot of the screen for a few seconds.)
      await tester.pump(const Duration(seconds: 6));
      await _settle(tester);
      await _shoot(tester, sheet, const ChatSettingsScreen(thread: 1, people: maya), '13-friends-settings', dark: dark);
      expect(find.text('Friend · encrypted'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Friends'), 300, scrollable: find.byType(Scrollable).first);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
      await _shootAgain(tester, '13-friends-settings', dark: dark);
      expect(find.text('Friends'), findsOneWidget);
      await tester.tap(find.text('Friends'));
      await _settle(tester);
      await tester.tap(find.text('Remove friend'));
      await _settle(tester);
      expect(_mayaFriend, '');
      expect(find.text('Add friend'), findsOneWidget);
    }
  });

  testWidgets('the frame, wide and narrow', (tester) async {
    // A folding phone opened out, then its cover.
    const open = Size(750 * 2.0, 832 * 2.0);
    const cover = Size(412 * 2.0, 892 * 2.0);
    tester.view.physicalSize = open;
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
    addTearDown(tester.view.reset);
    _answerChannel();
    final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
    installSettingsStyles(sheet);
    Finder seen(Finder f) => f.hitTestable();
    Finder icon(String label) => find.byWidgetPredicate((w) => w is IconTap && w.label == label);
    // One ring of the pill at the list's foot (lib/ui/nav_bar.dart).
    Finder ring(String id) => find.byKey(ValueKey('nav-$id'));
    String shown() => tester.widget<NavPill>(find.byType(NavPill)).active;
    for (final dark in [false, true]) {
      tester.view.physicalSize = open;
      await _shoot(tester, sheet, const AppShell(), '11-frame-wide', dark: dark);
      final side = AppShell.sideWidth(750);
      // Wide: the list down the side with the Mac's pill at its foot (a new chat, the messages, the contacts, the
      // archive with its number, Settings), and the pane saying to choose.
      expect(find.text('Choose a conversation'), findsOneWidget);
      for (final id in ['new', 'messages', 'contacts', 'archive', 'settings']) {
        expect(ring(id), findsOneWidget, reason: 'the pill has $id');
      }
      expect(shown(), 'messages');
      expect(tester.widget<NavPill>(find.byType(NavPill)).items.firstWhere((i) => i.id == 'archive').count, 1);
      expect(icon('New message'), findsNothing, reason: 'the header holds nothing the pill does');
      expect(tester.getTopRight(find.byType(ConversationsScreen)).dx, side);
      // A conversation opens beside the list, which stays, with no way back drawn: there is nowhere to go back to.
      await tester.tap(find.text('Maya Chen'));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await _shootAgain(tester, '11-frame-wide-thread', dark: dark);
      expect(find.byType(ThreadScreen), findsOneWidget);
      expect(tester.getTopLeft(find.byType(ThreadScreen)).dx, side + 1);
      expect(seen(find.text('Dad')), findsOneWidget);
      expect(icon('Back'), findsNothing);
      expect(find.text('Choose a conversation'), findsNothing);
      // A message held: what it brings up is beside its bubble, in the pane, not the list's width further over.
      final held = find.text('Movie night is still on for tonight right?');
      await tester.longPress(held);
      await _shootAgain(tester, '11-frame-wide-held', dark: dark);
      final copy = find.text('Copy text');
      expect(copy, findsOneWidget);
      final words = tester.getRect(held.first);
      expect(tester.getTopLeft(copy).dx, inInclusiveRange(words.left, words.right), reason: 'the menu is under the bubble it is for');
      await tester.tapAt(Offset(side + 20, 400));
      await _settle(tester);
      // Something half written in it.
      await tester.enterText(find.byType(EditableText).last, 'On my way');
      await _settle(tester);
      // The phone is folded: the conversation is still open, with what was written, and now covers the list and
      // has its way back.
      tester.view.physicalSize = cover;
      await _settle(tester);
      await _shootAgain(tester, '11-frame-narrow-thread', dark: dark);
      expect(find.text('On my way'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(ThreadScreen)).dx, 0);
      expect(seen(find.text('Dad')), findsNothing);
      expect(icon('Back'), findsWidgets);
      // And opened out again: beside the list once more, still with what was written.
      tester.view.physicalSize = open;
      await _settle(tester);
      expect(find.text('On my way'), findsOneWidget);
      expect(seen(find.text('Dad')), findsOneWidget);
      expect(icon('Back'), findsNothing);
      tester.view.physicalSize = cover;
      await _settle(tester);
      // Its way back closes it: the list alone.
      await tester.tap(icon('Back').first);
      await _settle(tester);
      await _shootAgain(tester, '11-frame-narrow', dark: dark);
      expect(find.byType(ThreadScreen), findsNothing);
      expect(seen(find.text('Dad')), findsOneWidget);
      expect(find.text('Choose a conversation'), findsNothing);
      // A new chat, from the pill, slides over the list; Android's back closes it.
      await tester.tap(ring('new'));
      await _settle(tester);
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(seen(find.text('Dad')), findsNothing);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(ComposeScreen), findsNothing);
      expect(seen(find.text('Dad')), findsOneWidget);
      // The pill's Archive opens the archive in the list's place; a conversation from it opens over it; back
      // closes the conversation first, then leaves the archive.
      expect(find.textContaining('Archived ('), findsNothing, reason: 'the way to the archive is the pill');
      await tester.tap(ring('archive'));
      await _settle(tester);
      await _shootAgain(tester, '11-frame-narrow-archive', dark: dark);
      expect(shown(), 'archive');
      expect(seen(find.text('Old Thread')), findsOneWidget);
      await tester.tap(find.text('Old Thread'));
      await _settle(tester);
      expect(find.byType(ThreadScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(ThreadScreen), findsNothing);
      expect(seen(find.text('Old Thread')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(seen(find.text('Old Thread')), findsNothing);
      expect(seen(find.text('Dad')), findsOneWidget);
      expect(shown(), 'messages');
      // The archive again, and the pill's Messages leaves it.
      await tester.tap(ring('archive'));
      await _settle(tester);
      expect(seen(find.text('Old Thread')), findsOneWidget);
      await tester.tap(ring('messages'));
      await _settle(tester);
      expect(seen(find.text('Old Thread')), findsNothing);
      expect(shown(), 'messages');
      // Wide again: the contacts open beside the list, and someone in them opens their conversation there.
      tester.view.physicalSize = open;
      await _settle(tester);
      await tester.tap(ring('contacts'));
      await _settle(tester);
      await _shootAgain(tester, '11-frame-wide-contacts', dark: dark);
      expect(find.byType(ContactsScreen), findsOneWidget);
      expect(shown(), 'contacts');
      expect(seen(find.text('Dad')), findsOneWidget);
      // Settings opens beside the list with no way back, and a section of it opens over it with one.
      await tester.tap(ring('settings'));
      await _settle(tester);
      await _shootAgain(tester, '11-frame-wide-settings', dark: dark);
      expect(find.byType(ContactsScreen), findsNothing);
      expect(shown(), 'settings');
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(seen(find.text('Dad')), findsOneWidget);
      expect(icon('Back'), findsNothing);
      await tester.tap(find.text('Appearance').first);
      await _settle(tester);
      expect(seen(icon('Back')), findsWidgets);
      expect(seen(find.text('Dad')), findsOneWidget);
      // Choosing a conversation puts it in Settings' place.
      await tester.tap(find.text('Dad'));
      await _settle(tester);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(ThreadScreen), findsOneWidget);
      expect(shown(), 'messages');
      // Settings › Network's invitation opens a new chat beside the list; choosing who opens the conversation with
      // the invitation written in its message field, to send as any text.
      tester.state<AppShellState>(find.byType(AppShell)).settings('network');
      await _settle(tester);
      await tester.tap(find.text('Invite someone by text'));
      await _settle(tester);
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(shown(), 'new');
      await tester.enterText(find.byType(EditableText).last, 'Mom');
      await _settle(tester);
      await tester.tap(find.text('Mom').last);
      await _settle(tester);
      await tester.tap(find.text('Next'));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await _settle(tester);
      await _shootAgain(tester, '11-frame-wide-invite', dark: dark);
      expect(find.byType(ThreadScreen), findsOneWidget);
      expect(find.textContaining('Join me on Ghost Messaging'), findsOneWidget);
      // A newer version waiting: beside a pane the banner is in the list's column, under its search field, with
      // the app's name left out so its words and its button fit; on a narrow screen it runs the screen's width and
      // says the name.
      tester.view.physicalSize = open;
      await _shoot(tester, sheet, const UpdateBanner(child: AppShell()), '11-frame-wide-banner', dark: dark);
      final button = tester.getRect(find.text('Update now'));
      expect(button.right, lessThan(side), reason: 'the banner is in the list\'s column, not across the window');
      expect(tester.getRect(find.textContaining('is out')).left, greaterThan(0));
      expect(find.text('0.6.2 is out'), findsOneWidget);
      expect(tester.getRect(find.text('0.6.2 is out')).top, greaterThan(tester.getRect(find.byType(GlacierSearchField).first).bottom - 1));
      tester.view.physicalSize = cover;
      await _settle(tester);
      expect(find.text('Ghost Messaging 0.6.2 is out'), findsOneWidget);
      expect(tester.getRect(find.text('Update now')).right, greaterThan(300));
      // The next round starts with a frame of its own.
      await tester.pumpWidget(const SizedBox());
    }
  });
}

/// A route that carries nothing anywhere: for the picture of Settings › Network.
class _Route implements Carrier {
  _Route(this.id, this.name, this.about, {bool up = true, bool metered = false})
      : state = ValueNotifier(up ? CarrierState.up : CarrierState.down),
        traits = CarrierTraits(maxPacket: 4096, metered: metered, live: false);
  @override
  final String id;
  @override
  final String name;
  @override
  final String about;
  @override
  final CarrierTraits traits;
  @override
  final ValueNotifier<CarrierState> state;
  @override
  String? problem;
  int carried = 0;
  @override
  Stream<Arrived> get arrived => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  bool reaches(Peer peer) => state.value == CarrierState.up;
  @override
  Future<Handed> send(Peer peer, Uint8List packet) async {
    carried++;
    return Handed.passed;
  }
}

/// The routes and the phone under Friends for the friends' pictures: what Friends tells the phone about Maya is
/// what the phone's answers (`_e2e`) then say.
class _FriendsPort extends FakePort {
  _FriendsPort(super.me);

  @override
  Future<void> setFriend(String address, String state) async => _mayaFriend = state;

  @override
  Future<void> offerKeys(String address) async => keysSent.add(address);

  @override
  Future<List<E2eState>> states() async => [E2eState.from(_e2e('+15551230001'))];
}

/// The routes and the phone under Groups for the groups' pictures: the lines about a group go into conversation 2.
class _GroupsPort extends FakeGroupsPort {
  _GroupsPort(super.world, super.number);

  @override
  Future<void> note(String id, String words) async => _groupNotes.add(words);
}

/// The routes and the phone under Friends for the groups' pictures: three people, each a friend.
class _ThreeFriends extends FakePort {
  _ThreeFriends(super.me, this.people);
  final List<Person> people;

  @override
  Future<List<E2eState>> states() async => [for (final p in people) E2eState(address: p.address, state: 'on', friend: 'yes', hasGhost: true, person: p)];
}
