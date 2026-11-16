import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/inbox/td_json.dart';
import 'package:ghost_messaging/inbox/telegram.dart';

/// TDLib as these tests have it: what Telegram (lib/inbox/telegram.dart) sends is kept, and each test says what TDLib
/// answers. Requests that carry an "@extra" are answered by [answer], with the same "@extra".
class FakeTd implements TdTransport {
  final sent = <Map<String, Object?>>[];
  final _in = StreamController<Map<String, Object?>>.broadcast();
  Map<String, Object?>? Function(Map<String, Object?> request) answer = (_) => {'@type': 'ok'};

  void say(Map<String, Object?> m) => _in.add(m);
  void auth(String state, [Map<String, Object?> more = const {}]) => say({'@type': 'updateAuthorizationState', 'authorization_state': {'@type': state, ...more}});

  @override
  Stream<Map<String, Object?>> get received => _in.stream;

  @override
  void send(Map<String, Object?> request) {
    sent.add(request);
    final extra = request['@extra'];
    if (extra == null) return;
    final a = answer(request);
    if (a != null) scheduleMicrotask(() => _in.add({...a, '@extra': extra}));
  }

  @override
  void close() {}

  Iterable<String> get types => sent.map((r) => r['@type'] as String);
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async => null);
  });

  test('without an app id this build has no Telegram', () async {
    final tg = Telegram(apiId: 0, apiHash: '', transport: () async => FakeTd());
    await tg.start(AppState());
    expect(tg.state, InboxState.unavailable);
    expect(tg.configured, isFalse);
  });

  test('TDLib is not loaded until someone starts signing in', () async {
    var made = 0;
    final tg = Telegram(apiId: 1, apiHash: 'h', folder: '/tmp/x', transport: () async {
      made++;
      return FakeTd();
    });
    await tg.start(AppState());
    expect(tg.state, InboxState.signedOut);
    expect(made, 0);
  });

  test('signs in by number, code and two-step password, then lists the chats it can write in', () async {
    final td = FakeTd();
    final app = AppState();
    final tg = Telegram(apiId: 12345, apiHash: 'hash', folder: '/tmp/tg', transport: () async => td);
    await tg.start(app);
    await tg.begin();
    expect(app.flag('tg_used', fallback: false), isTrue);
    expect(td.types, contains('getAuthorizationState'));

    td.auth('authorizationStateWaitTdlibParameters');
    await settle();
    final params = td.sent.firstWhere((r) => r['@type'] == 'setTdlibParameters');
    expect(params['api_id'], 12345);
    expect(params['database_directory'], '/tmp/tg/db');
    expect(params['use_secret_chats'], false);

    td.auth('authorizationStateWaitPhoneNumber');
    await settle();
    expect(tg.state, InboxState.signingIn);
    expect(tg.step, InboxStep.phone);

    td.answer = (r) => r['@type'] == 'setAuthenticationPhoneNumber' && r['phone_number'] == '+15550100199' ? {'@type': 'ok'} : {'@type': 'error', 'code': 400, 'message': 'PHONE_NUMBER_INVALID'};
    await tg.sendPhone('12');
    expect(tg.error, contains('country code'));
    await tg.sendPhone(' +15550100199 ');
    expect(tg.error, isNull);

    td.auth('authorizationStateWaitCode', {
      'code_info': {'phone_number': '+15550100199', 'type': {'@type': 'authenticationCodeTypeTelegramMessage', 'length': 5}},
    });
    await settle();
    expect(tg.step, InboxStep.code);
    expect(tg.codeWhere, 'your Telegram app on another device');

    td.answer = (r) => {'@type': 'ok'};
    await tg.sendCode('12345');
    td.auth('authorizationStateWaitPassword', {'password_hint': 'dog'});
    await settle();
    expect(tg.step, InboxStep.password);
    expect(tg.passwordHint, 'dog');

    td.answer = (r) => switch (r['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Matt', 'last_name': '', 'usernames': {'active_usernames': ['matt']}},
          _ => {'@type': 'ok'},
        };
    await tg.sendPassword('hunter2');
    td.auth('authorizationStateReady');
    await settle();
    await settle();
    expect(tg.state, InboxState.ready);
    expect(tg.account, '@matt');
    expect(td.types, contains('loadChats'));

    // Three chats: a person, a group, and a channel, which can't be written in and so is left out.
    td.say({'@type': 'updateUser', 'user': {'id': 7, 'first_name': 'Jo', 'last_name': 'Park'}});
    for (final (id, title, type, order) in [
      (10, 'Jo Park', {'@type': 'chatTypePrivate', 'user_id': 7}, '300'),
      (20, 'Weekend crew', {'@type': 'chatTypeBasicGroup', 'basic_group_id': 2}, '200'),
      (30, 'News', {'@type': 'chatTypeSupergroup', 'supergroup_id': 3, 'is_channel': true}, '400'),
    ]) {
      td.say({
        '@type': 'updateNewChat',
        'chat': {
          'id': id,
          'title': title,
          'type': type,
          'unread_count': id == 10 ? 2 : 0,
          'positions': [
            {'list': {'@type': 'chatListMain'}, 'order': order},
          ],
          'last_message': {'id': 1, 'chat_id': id, 'is_outgoing': false, 'date': 1763200000, 'content': {'@type': 'messageText', 'text': {'text': 'hi from $title'}}},
        },
      });
    }
    await settle();
    expect(tg.chats.map((c) => c.title), ['Jo Park', 'Weekend crew']);
    expect(tg.chats.first.unread, 2);
    expect(tg.chats.last.group, isTrue);
    expect(tg.unreadChats, 1);
    tg.dispose();
  });

  // Matt, 2026-11-15: "import telegram chats sorted by most recent with the profile pictures and all".
  test('every chat is loaded, the newest first, each with its picture once brought down', () async {
    final td = FakeTd();
    var loads = 0;
    td.answer = (r) => switch (r['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Matt'},
          // Three lots of chats, then none left.
          'loadChats' when (r['chat_list'] as Map)['@type'] == 'chatListMain' => ++loads <= 3 ? {'@type': 'ok'} : {'@type': 'error', 'code': 404, 'message': 'Not Found'},
          'loadChats' => {'@type': 'error', 'code': 404, 'message': 'Not Found'},
          _ => {'@type': 'ok'},
        };
    final tg = Telegram(apiId: 12345, apiHash: 'hash', folder: '/tmp/tg', transport: () async => td);
    await tg.start(AppState());
    await tg.begin();
    td.auth('authorizationStateReady');
    for (var i = 0; i < 12; i++) {
      await settle();
    }
    final lists = [for (final r in td.sent) if (r['@type'] == 'loadChats') (r['chat_list'] as Map)['@type']];
    expect(lists.where((l) => l == 'chatListMain').length, 4, reason: 'asked again until there were no more');
    expect(lists, contains('chatListArchive'), reason: 'and the archive');

    Map<String, Object?> chat(int id, String title, int date, String order, {Map<String, Object?>? small}) => {
          '@type': 'updateNewChat',
          'chat': {
            'id': id,
            'title': title,
            'type': {'@type': 'chatTypePrivate', 'user_id': id},
            'positions': [
              {'list': {'@type': 'chatListMain'}, 'order': order},
            ],
            'photo': ?(small == null ? null : {'small': small}),
            'last_message': {'id': 1, 'chat_id': id, 'is_outgoing': false, 'date': date, 'content': {'@type': 'messageText', 'text': {'text': 'hi'}}},
          },
        };
    // A pinned chat (the highest order) that is old, and a newer one with a picture not yet brought down.
    td.say(chat(10, 'Old but pinned', 1700000000, '900'));
    td.say(chat(20, 'Jo Park', 1763200000, '100', small: {'id': 55, 'local': {'path': '', 'is_downloading_completed': false}}));
    await settle();
    expect(tg.chats.map((c) => c.title), ['Jo Park', 'Old but pinned'], reason: 'the newest first, as among the texts');
    expect(tg.chats.first.avatar, isNull);
    final asked = td.sent.where((r) => r['@type'] == 'downloadFile').toList();
    expect(asked.single['file_id'], 55);

    td.say({'@type': 'updateFile', 'file': {'id': 55, 'local': {'path': '/data/tg/photos/55.jpg', 'is_downloading_completed': true}}});
    await settle();
    expect(tg.chats.first.avatar, '/data/tg/photos/55.jpg');
    expect(td.sent.where((r) => r['@type'] == 'downloadFile').length, 1, reason: 'asked for once');
    tg.dispose();
  });

  // Matt, 2026-11-15: "if possible proxy the archive and delete messages too".
  test('archiving and deleting go to Telegram itself', () async {
    final td = FakeTd();
    td.answer = (r) => r['@type'] == 'getMe' ? {'@type': 'user', 'id': 1, 'first_name': 'Matt'} : (r['@type'] == 'loadChats' ? {'@type': 'error', 'code': 404, 'message': 'Not Found'} : {'@type': 'ok'});
    final tg = Telegram(apiId: 12345, apiHash: 'hash', folder: '/tmp/tg', transport: () async => td);
    await tg.start(AppState());
    await tg.begin();
    td.auth('authorizationStateReady');
    for (var i = 0; i < 6; i++) {
      await settle();
    }
    Map<String, Object?> chat(int id, String title, String list, {Map<String, Object?> type = const {'@type': 'chatTypePrivate', 'user_id': 7}}) => {
          '@type': 'updateNewChat',
          'chat': {
            'id': id, 'title': title, 'type': type,
            'positions': [
              {'list': {'@type': list}, 'order': '5'},
            ],
            'last_message': {'id': 1, 'chat_id': id, 'is_outgoing': false, 'date': 1763200000, 'content': {'@type': 'messageText', 'text': {'text': 'hi'}}},
          },
        };
    td.say(chat(10, 'Jo Park', 'chatListMain'));
    td.say(chat(20, 'Old crew', 'chatListArchive', type: const {'@type': 'chatTypeBasicGroup', 'basic_group_id': 2}));
    await settle();
    expect(tg.chats.map((c) => c.title), ['Jo Park']);
    expect(tg.archivedChats.map((c) => c.title), ['Old crew'], reason: 'Telegram\'s archive is Ghost\'s Archived');

    await tg.archive('10', true);
    final add = td.sent.lastWhere((r) => r['@type'] == 'addChatToList');
    expect(add['chat_id'], 10);
    expect((add['chat_list'] as Map)['@type'], 'chatListArchive');

    await tg.deleteChat('20');
    expect(td.types, containsAllInOrder(['leaveChat', 'deleteChatHistory']), reason: 'a group is left, then its history goes');
    final del = td.sent.lastWhere((r) => r['@type'] == 'deleteChatHistory');
    expect(del['remove_from_chat_list'], true);
    expect(del['revoke'], false);
    expect(tg.archivedChats, isEmpty);

    // A message: for this account, or for everyone where Telegram allows it.
    td.say({'@type': 'updateNewMessage', 'message': {'id': 77, 'chat_id': 10, 'is_outgoing': true, 'date': 1763200100, 'can_be_deleted_for_all_users': true, 'content': {'@type': 'messageText', 'text': {'text': 'oops'}}}});
    await settle();
    final oops = tg.messagesOf('10').single;
    expect(tg.canDeleteForEveryone('10', oops), isTrue);
    await tg.deleteMessage('10', '77', forEveryone: true);
    final dm = td.sent.lastWhere((r) => r['@type'] == 'deleteMessages');
    expect(dm['message_ids'], [77]);
    expect(dm['revoke'], true);
    expect(tg.messagesOf('10'), isEmpty);
    tg.dispose();
  });

  test('a chat\'s messages, a reply sent and confirmed, and reading it', () async {
    final td = FakeTd();
    final tg = Telegram(apiId: 1, apiHash: 'h', folder: '/tmp/tg', transport: () async => td);
    await tg.start(AppState());
    await tg.begin();
    td.auth('authorizationStateReady');
    await settle();
    td.say({'@type': 'updateUser', 'user': {'id': 7, 'first_name': 'Jo'}});
    td.say({
      '@type': 'updateNewChat',
      'chat': {
        'id': 10,
        'title': 'Jo',
        'type': {'@type': 'chatTypePrivate', 'user_id': 7},
        'positions': [
          {'list': {'@type': 'chatListMain'}, 'order': '5'},
        ],
      },
    });
    Map<String, Object?> msg(int id, String text, {bool out = false, int date = 1763200000, Map<String, Object?>? content}) => {
          '@type': 'message',
          'id': id,
          'chat_id': 10,
          'is_outgoing': out,
          'date': date,
          'sender_id': {'@type': 'messageSenderUser', 'user_id': out ? 1 : 7},
          'content': content ?? {'@type': 'messageText', 'text': {'@type': 'formattedText', 'text': text}},
        };
    var history = 0;
    td.answer = (r) {
      if (r['@type'] == 'getChatHistory') {
        // First a single message, as TDLib does, then the ones before it, then nothing.
        history++;
        return switch (history) {
          1 => {'@type': 'messages', 'messages': [msg(3, 'and you?', date: 1763200300)]},
          2 => {'@type': 'messages', 'messages': [msg(2, '', date: 1763200200, content: {'@type': 'messagePhoto', 'caption': {'text': 'the view'}}), msg(1, 'hi', out: true, date: 1763200100)]},
          _ => {'@type': 'messages', 'messages': []},
        };
      }
      if (r['@type'] == 'sendMessage') {
        return {...msg(99, ((r['input_message_content'] as Map)['text'] as Map)['text'] as String, out: true, date: 1763200400), 'sending_state': {'@type': 'messageSendingStatePending'}};
      }
      return {'@type': 'ok'};
    };
    tg.watching = '10';
    expect(td.sent.last, {'@type': 'openChat', 'chat_id': 10});
    await tg.load('10');
    expect(tg.messagesOf('10').map((m) => m.text), ['hi', 'Photo: the view', 'and you?']);
    expect(tg.messagesOf('10').first.mine, isTrue);
    expect(tg.hasOlder('10'), isFalse);

    await tg.send('10', 'all good');
    expect(tg.messagesOf('10').last.state, 'sending');
    td.say({'@type': 'updateMessageSendSucceeded', 'old_message_id': 99, 'message': msg(100, 'all good', out: true, date: 1763200401)});
    await settle();
    expect(tg.messagesOf('10').where((m) => m.text == 'all good').single.state, 'sent');
    expect(tg.messagesOf('10').last.id, '100');

    await tg.markRead('10');
    final viewed = td.sent.lastWhere((r) => r['@type'] == 'viewMessages');
    expect(viewed['message_ids'], [2, 3]);

    tg.watching = null;
    expect(td.sent.last, {'@type': 'closeChat', 'chat_id': 10});

    // Something new arrives while the list is open.
    td.say({'@type': 'updateNewMessage', 'message': msg(101, 'great', date: 1763200500)});
    await settle();
    expect(tg.messagesOf('10').last.text, 'great');
    tg.dispose();
  });

  test('signing out logs out of Telegram and forgets the chats', () async {
    final td = FakeTd();
    final app = AppState();
    final tg = Telegram(apiId: 1, apiHash: 'h', folder: '/tmp/tg', transport: () async => td);
    await tg.start(app);
    await tg.begin();
    td.auth('authorizationStateReady');
    await settle();
    await tg.signOut();
    expect(td.types, contains('logOut'));
    expect(tg.state, InboxState.signedOut);
    expect(tg.chats, isEmpty);
    expect(app.flag('tg_used', fallback: false), isFalse);
    tg.dispose();
  });

  test('errors in plain words', () {
    expect(telegramPlain({'message': 'PHONE_CODE_INVALID'}), 'That code isn\'t right.');
    expect(telegramPlain({'message': 'FLOOD_WAIT_30'}), contains('wait'));
    expect(telegramPlain({'message': 'SOMETHING_NEW'}), 'SOMETHING_NEW');
  });

  // The real library (tool/build-tdlib.sh mac), where it has been built: TDLib starts in this process and asks for
  // its parameters, which is the first thing a new client always says.
  final lib = File('build/tdlib/mac/libtdjson.dylib');
  test('TDLib itself answers through td_json.dart', () async {
    final td = await TdJson.start();
    expect(td, isNotNull);
    final first = td!.received.firstWhere((m) => m['@type'] == 'updateAuthorizationState');
    td.send({'@type': 'getAuthorizationState', '@extra': 'x'});
    final state = await first.timeout(const Duration(seconds: 20));
    expect((state['authorization_state'] as Map)['@type'], 'authorizationStateWaitTdlibParameters');
    td.close();
  }, skip: Platform.isMacOS && lib.existsSync() ? false : 'TDLib is not built on this computer (sh tool/build-tdlib.sh mac)');

  // Two clients at once (a sign-out and a new sign-in overlap): TDLib aborts the process if td_receive is ever called
  // from two threads, so both must be served by the one receiving isolate, each getting only its own.
  test('two TDLib clients share the one receiver', () async {
    final a = (await TdJson.start())!, b = (await TdJson.start())!;
    Future<String> stateOf(TdJson td, String extra) async {
      final got = td.received.firstWhere((m) => m['@extra'] == extra);
      td.send({'@type': 'getAuthorizationState', '@extra': extra});
      return ((await got.timeout(const Duration(seconds: 20)))['@type']) as String;
    }

    expect(await Future.wait([stateOf(a, 'a'), stateOf(b, 'b')]), ['authorizationStateWaitTdlibParameters', 'authorizationStateWaitTdlibParameters']);
    a.close();
    b.close();
  }, skip: Platform.isMacOS && lib.existsSync() ? false : 'TDLib is not built on this computer (sh tool/build-tdlib.sh mac)');
}
