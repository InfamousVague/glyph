import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/standalone/standalone.dart';

/// An iPhone of its own (lib/standalone; Matt, 2026-11-15: "roll a version of the app that works without sms"): who
/// it is, the friends it reaches and the key each pair seals with, and the conversations it keeps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final c in ['ghost_desktop/system', 'ghost_messaging/sms']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
  });

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('standalone'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<StandaloneCalls> install(String name) async {
    final c = StandaloneCalls(Directory('${root.path}/$name'), keychain: false);
    await c.load();
    return c;
  }

  Map<String, Object> buddy(String username, Map me, String state) => {'u': username, 'i': me['id'] as String, 'k': me['key'] as String, 'n': '', 'b': '', 's': state, 'a': 0};

  test('who it is stays who it is', () async {
    final a = await install('a');
    final first = await a.invokeMethod<Map>('netIdentity');
    final again = await (await install('a')).invokeMethod<Map>('netIdentity');
    expect(again, first);
    expect(base64Decode(first!['key'] as String), hasLength(33));
    expect(first['id'], NetCrypto.idOf(base64Decode(first['key'] as String)));
  });

  test('two iPhones who are friends seal with the same key, as each works it out', () async {
    final a = await install('a'), b = await install('b');
    final ida = (await a.invokeMethod<Map>('netIdentity'))!, idb = (await b.invokeMethod<Map>('netIdentity'))!;
    // a asked b; b was asked: each has the other.
    await a.invokeMethod('buddiesKeep', {'json': jsonEncode([buddy('bee', idb, 'asked')])});
    await b.invokeMethod('buddiesKeep', {'json': jsonEncode([buddy('ay', ida, 'invited')])});
    final pa = (await a.invokeMethod<List>('netPeers'))!, pb = (await b.invokeMethod<List>('netPeers'))!;
    expect(pa, hasLength(1));
    expect(pb, hasLength(1));
    expect((pa.single as Map)['id'], idb['id']);
    expect((pb.single as Map)['id'], ida['id']);
    expect((pa.single as Map)['key'] as Uint8List, (pb.single as Map)['key'] as Uint8List);
    // Only a friend who said yes is a conversation.
    expect((pa.single as Map)['address'], '');
    await a.invokeMethod('buddiesKeep', {'json': jsonEncode([buddy('bee', idb, 'yes')])});
    expect(((await a.invokeMethod<List>('netPeers'))!.single as Map)['address'], '@bee');
    await a.flushed();
    await b.flushed();
  });

  test('a friend\'s words, kept and shown as a conversation, newest first; pinned ones come too', () async {
    final a = await install('a');
    await a.invokeMethod('netTextIn', {'address': '@bee', 'body': 'first', 'at': 1000});
    await a.invokeMethod('netTextIn', {'address': '@bee', 'body': 'second', 'at': 2000});
    final out = await a.invokeMethod<int>('netTextOut', {'address': '@cee', 'body': 'to cee'});
    await a.invokeMethod('netTextState', {'id': out, 'state': 'delivered'});
    final page = Map<String, Object?>.from((await a.invokeMethod<Map>('conversationsPage', {'limit': 1, 'offset': 0, 'pinned': true}))!);
    final items = [for (final c in page['items'] as List) Conversation.from(c as Map)];
    expect(items.single.people.single.address, '@cee', reason: 'the newest');
    expect(page['next'], 1);
    final bee = (await a.invokeMethod<int>('threadFor', {'addresses': ['@bee']}))!;
    await a.invokeMethod('threadFlag', {'name': 'pinned', 'thread': bee, 'on': true});
    final again = (await a.invokeMethod<Map>('conversationsPage', {'limit': 1, 'offset': 0, 'pinned': true}))!;
    expect([for (final c in again['items'] as List) (c as Map)['id']], containsAll([bee]), reason: 'a pinned one heads the list however old');
    final messages = [for (final m in (await a.invokeMethod<List>('messages', {'thread': bee, 'limit': 50}))!) Message.from(m as Map)];
    expect(messages.map((m) => m.body), ['second', 'first'], reason: 'newest first, as the phone gives them');
    expect(messages.first.via, 'net');
    final c = Conversation.from((await a.invokeMethod<Map>('conversation', {'thread': bee}))!);
    expect(c.unread, isTrue);
    await a.invokeMethod('markRead', {'thread': bee});
    expect(Conversation.from((await a.invokeMethod<Map>('conversation', {'thread': bee}))!).unread, isFalse);
    // Kept across a restart.
    await a.flushed();
    final back = await install('a');
    expect([for (final m in (await back.invokeMethod<List>('messages', {'thread': bee, 'limit': 50}))!) (m as Map)['body']], ['second', 'first']);
  });

  test('where it lives: Application Support beside tmp, not inside it (iOS gives the app no HOME)', () {
    final dir = StandaloneCalls.defaultDir().path;
    expect(dir, endsWith('/Library/Application Support/Ghost Messaging'));
    expect(dir.startsWith(Directory.systemTemp.path) && Platform.environment['HOME'] == null, isFalse);
  });
}
