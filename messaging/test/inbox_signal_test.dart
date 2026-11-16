import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/inbox/signal.dart';

/// A stand-in for the Signal helper (sidecar/signal/PROTOCOL.md): answers what it is asked, and says what Signal would.
class FakeHelper implements SignalLink {
  final asked = <Map<String, Object?>>[];
  final _out = StreamController<Map<String, Object?>>.broadcast();
  Object? Function(Map<String, Object?> r) answer = (_) => null;
  bool linked = false;

  void event(Map<String, Object?> e) => _out.add(e);

  @override
  Stream<Map<String, Object?>> get heard => _out.stream;

  @override
  void say(Map<String, Object?> line) {
    asked.add(line);
    final r = line['op'] == 'status' ? {'linked': linked, 'number': linked ? '+15550100199' : null} : answer(line);
    scheduleMicrotask(() => _out.add({'id': line['id'], 'ok': true, 'result': r}));
  }

  @override
  Future<void> close() async {}
}

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Signal through mautrix-signal (lib/inbox/signal.dart; Matt, 2026-11-15: "Lets wire it up for signal through the
/// mautrix"): linked by the QR code the helper gives, its messages kept here as they come, sent, read, deleted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async => null);
  });

  test('linked by the QR code; a message comes, is kept, answered, read and deleted; kept across a restart', () async {
    final dir = Directory.systemTemp.createTempSync('signal');
    addTearDown(() => dir.deleteSync(recursive: true));
    final helper = FakeHelper();
    helper.answer = (r) => switch (r['op']) {
          'contacts' => [{'aci': 'aci-jo', 'name': 'Jo Park', 'number': '+15550100'}],
          'groups' => [{'id': 'grp1', 'title': 'Weekend crew', 'members': ['aci-jo']}],
          'send' => {'ts': 1763200500000},
          _ => null,
        };
    final s = Signal(link: () async => helper, folder: dir.path);
    await s.start(AppState());
    await settle();
    expect(s.state, InboxState.signedOut);

    await s.begin();
    expect(helper.asked.last, containsPair('op', 'link'));
    helper.event({'ev': 'qr', 'url': 'sgnl://linkdevice?uuid=abc&pub_key=def'});
    await settle();
    expect(s.qr, startsWith('sgnl://linkdevice'));
    helper.event({'ev': 'linked', 'aci': 'aci-me', 'number': '+15550100199'});
    await settle();
    expect(s.state, InboxState.ready);
    expect(s.account, '+15550100199');
    expect(s.qr, isNull);

    helper.event({'ev': 'message', 'chat': 'aci-jo', 'group': false, 'from': 'aci-jo', 'mine': false, 'ts': 1763200000000, 'text': 'are you coming tonight?', 'media': []});
    helper.event({
      'ev': 'message', 'chat': 'grp1', 'group': true, 'from': 'aci-jo', 'name': 'Jo Park', 'mine': false, 'ts': 1763200100000, 'text': '',
      'media': [{'pointer': {'cdnKey': 'k1'}, 'mime': 'image/jpeg', 'name': 'beach.jpg', 'size': 2048, 'width': 800, 'height': 600}],
    });
    await settle();
    final chats = {for (final c in s.chats) c.id: c};
    expect((chats['aci-jo']!.title, chats['aci-jo']!.snippet, chats['aci-jo']!.unread), ('Jo Park', 'are you coming tonight?', 1));
    expect((chats['grp1']!.title, chats['grp1']!.group, chats['grp1']!.snippet), ('Weekend crew', true, 'Photo'));
    expect(s.messagesOf('grp1').single.media.single.kind, 'photo');

    await s.send('aci-jo', 'on my way');
    final sent = helper.asked.lastWhere((r) => r['op'] == 'send');
    expect((sent['to'], sent['text']), ('aci-jo', 'on my way'));
    final mine = s.messagesOf('aci-jo').last;
    expect((mine.id, mine.mine, mine.state), ('1763200500000', true, 'sent'));

    await s.markRead('aci-jo');
    final read = helper.asked.lastWhere((r) => r['op'] == 'read');
    expect((read['to'], read['author']), ('aci-jo', 'aci-jo'));
    expect(read['ts'], [1763200000000]);
    expect(s.chats.firstWhere((c) => c.id == 'aci-jo').unread, 0);

    expect(s.canDeleteForEveryone('aci-jo', mine), isTrue);
    await s.deleteMessage('aci-jo', mine.id, forEveryone: true);
    expect(helper.asked.lastWhere((r) => r['op'] == 'delete')['ts'], 1763200500000);
    expect(s.messagesOf('aci-jo').map((m) => m.text), ['are you coming tonight?']);

    s.flush();
    s.dispose();
    final again = Signal(link: () async => FakeHelper()..linked = true, folder: dir.path);
    await again.start(AppState());
    await settle();
    expect(again.state, InboxState.ready);
    expect(again.chats.map((c) => c.title), containsAll(['Jo Park', 'Weekend crew']));
    expect(again.messagesOf('aci-jo').single.text, 'are you coming tonight?');
    again.dispose();
  });

  test('without the helper Signal is not in this build; offered from 0.7.40', () async {
    expect(Inbox.of([Signal(soon: true)]).ready, isEmpty);
    Inbox.instance = null;
    expect(Inbox.instance.named('signal')!.soon, isFalse);
    final none = Signal(link: () async => null);
    await none.start(AppState());
    expect(none.state, InboxState.unavailable);
  });

  // Matt, 2026-11-16: "Show telegram and signal contacts when linked".
  test('Signal\'s contacts once linked, without the person themself; a chat with one is named by their ACI', () async {
    final dir = Directory.systemTemp.createTempSync('signal-contacts');
    addTearDown(() => dir.deleteSync(recursive: true));
    final helper = FakeHelper();
    helper.answer = (r) => switch (r['op']) {
          'contacts' => [
              {'aci': 'aci-me', 'name': 'Matt', 'number': '+15550100199'},
              {'aci': 'aci-riley', 'name': 'Riley Fox', 'number': '+447700900123', 'avatar': '/tmp/riley.jpg'},
              {'aci': 'aci-jo', 'name': 'Jo Park', 'number': ''},
            ],
          'groups' => const [],
          _ => null,
        };
    final s = Signal(link: () async => helper, folder: dir.path);
    await s.start(AppState());
    await s.begin();
    helper.event({'ev': 'linked', 'aci': 'aci-me', 'number': '+15550100199'});
    await settle();
    expect([for (final c in s.contacts) (c.id, c.name, c.number, c.avatar)], [('aci-jo', 'Jo Park', null, null), ('aci-riley', 'Riley Fox', '+447700900123', '/tmp/riley.jpg')]);
    expect(await s.chatWith(s.contacts.last), 'aci-riley');

    await s.signOut();
    expect(s.contacts, isEmpty);
  });

  // Matt, 2026-11-16: "Sending signal messages get stuck on sending... and the group titles are not coming through".
  test('a group is named when it is first heard from, and groups are asked for again when Signal is back', () async {
    final dir = Directory.systemTemp.createTempSync('signal-groups');
    addTearDown(() => dir.deleteSync(recursive: true));
    final helper = FakeHelper();
    var groupsAsked = 0;
    // On linking the store has no groups yet: a group is known only from its first message.
    helper.answer = (r) => switch (r['op']) {
          'contacts' => const [],
          'groups' => (groupsAsked++ == 0) ? const [] : [{'id': 'R3JvdXAtd2Vla2VuZC1jcmV3LWlkLTAwMDAwMDAwMDA=', 'title': 'Weekend crew', 'members': const []}],
          _ => null,
        };
    final s = Signal(link: () async => helper, folder: dir.path);
    await s.start(AppState());
    await s.begin();
    helper.event({'ev': 'linked', 'aci': 'aci-me', 'number': '+15550100199'});
    await settle();
    const gid = 'R3JvdXAtd2Vla2VuZC1jcmV3LWlkLTAwMDAwMDAwMDA=';
    helper.event({'ev': 'message', 'chat': gid, 'group': true, 'from': 'aci-jo', 'name': 'Jo Park', 'ts': 1763300000000, 'text': 'tent is packed'});
    await settle();
    expect(s.chats.single.title, 'Signal group', reason: 'nothing known of it yet');

    // The helper tells its name as soon as it has looked it up.
    helper.event({'ev': 'group', 'id': gid, 'title': 'Hiking crew', 'members': ['aci-jo'], 'avatar': null});
    await settle();
    expect(s.chats.single.title, 'Hiking crew');
    expect(s.chats.single.group, isTrue);

    // Reconnected: groups asked for again (and the store now has the group).
    final before = groupsAsked;
    helper.event({'ev': 'connected'});
    await settle();
    expect(groupsAsked, before, reason: 'not again within a minute of the last time');
  });

  test('the helper\'s log: its own send lines and warnings go to the Developer log, nothing else', () {
    String? keep(Map<String, Object?> m) => SignalLog.keep(jsonEncode(m));
    expect(keep({'level': 'info', 'op': 'send', 'req': 7, 'took': 61.2, 'message': 'answered'}), 'info answered op=send req=7 took=61.2');
    expect(keep({'level': 'info', 'message': 'sent to group', 'sent_to': 0, 'failed': 3, 'error': 'context deadline exceeded'}), 'info sent to group sent_to=0 failed=3 error=context deadline exceeded');
    expect(keep({'level': 'warn', 'component': 'signalmeow', 'message': 'Failed to fetch prekeys'}), 'warn Failed to fetch prekeys component=signalmeow');
    expect(keep({'level': 'info', 'component': 'signalmeow', 'message': 'Websocket connected'}), isNull);
    expect(keep({'level': 'debug', 'message': 'anything'}), isNull);
  });
}
