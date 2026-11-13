import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/desktop/link/link.dart';
import 'package:ghost_messaging/desktop/link/session.dart';
import 'package:ghost_messaging/desktop/remote.dart';
import 'package:ghost_messaging/desktop/store.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_relay/relay.dart';

import 'support/fake_phone.dart';

/// The Mac's link to the phone, start to end, in one process: a stand-in phone (test/support/fake_phone.dart) on a
/// port of this machine as it would be on the local network, and the real relay (relay/) on another. Real sockets,
/// real sealing; only the phone is made up.
class MemoryStore implements LinkStore {
  PairedPhone? kept;
  @override
  Future<PairedPhone?> load() async => kept;
  @override
  Future<void> save(PairedPhone phone) async => kept = phone;
  @override
  Future<void> clear() async => kept = null;
}

Future<void> until(bool Function() test, {String? what, int ms = 6000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!test() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(test(), isTrue, reason: what ?? 'never happened');
}

void main() {
  late Relay relay;
  late String relayUrl;
  late FakePhone phone;
  final links = <PhoneLink>[];

  setUpAll(() {
    // The phone is looked for often, so a test does not wait as a person would.
    PhoneLink.lookEvery = const Duration(milliseconds: 80);
    PhoneLink.upgradeEvery = const Duration(milliseconds: 150);
    PhoneLink.connectTimeout = const Duration(milliseconds: 400);
    PhoneLink.helloTimeout = const Duration(seconds: 2);
  });

  setUp(() async {
    relay = Relay();
    relayUrl = 'ws://127.0.0.1:${await relay.start(port: 0)}/relay';
    phone = FakePhone();
    await phone.listen();
  });

  tearDown(() async {
    for (final l in links) {
      l.dispose();
    }
    links.clear();
    await phone.stop();
    await relay.stop();
  });

  PhoneLink mac(LinkStore store, {bool local = true}) {
    final link = PhoneLink(store: store, name: "Matt's MacBook", app: '0.7.0', given: local ? [phone.peer] : const []);
    links.add(link);
    return link;
  }

  /// Pairs [link] with the phone by [mode], as the two wizards would: the code shown, scanned, the digits compared
  /// and "They match" on both.
  Future<void> pair(PhoneLink link, String mode, {String? phoneMode}) async {
    await link.start();
    final attempt = link.beginPairing(mode: mode, relay: relayUrl);
    expect(attempt.phase, 'showing');
    phone.scan(attempt.offer.text, mode: phoneMode);
    if (mode != 'local') await phone.joinPairingRelay();
    await until(() => attempt.phase == 'code', what: 'the two never met');
    expect(attempt.code, phone.code);
    expect(attempt.code, hasLength(6));
    expect(attempt.phoneName, 'Fold');
    // Nothing is paired until both say so.
    expect(link.phone, isNull);
    link.confirmPairing();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(link.phone, isNull);
    expect(phone.keys, isEmpty);
    phone.confirm();
    await until(() => attempt.phase == 'done' && link.phone != null, what: 'never paired');
    link.pairingShown();
    expect(phone.keys.keys.single, link.phone!.id);
    // The phone lets go of the channel made for pairing, and joins the pairing's own (android DeskService.apply).
    await phone.leaveRelay();
    if (link.phone!.mode != 'local') await phone.joinPairedRelay(link.phone!.id, relayUrl);
    await until(() => link.online, what: 'never connected after pairing');
  }

  test('pairs over the local network, lists conversations, hears a new text, sends one', () async {
    final store = MemoryStore();
    final link = mac(store);
    await pair(link, 'local');
    expect(link.via, 'local');
    expect(link.phone!.mode, 'local');
    expect(store.kept!.host, '127.0.0.1');
    expect(store.kept!.port, phone.port);
    // The relay was never dialed.
    expect(relay.channelCount, 0);

    final list = (await link.request('conversations')) as List;
    expect(list.map((c) => (c as Map)['snippet']), ['See you at 7', 'Call me']);

    final heard = <int>[];
    link.events.stream.listen((e) => heard.add(e.args['thread'] as int));
    phone.arrive(7, 'Running late');
    await until(() => heard.contains(7), what: 'the new text was never said');
    final messages = (await link.request('messages', {'thread': 7})) as List;
    expect((messages.first as Map)['body'], 'Running late');

    final sent = (await link.request('send', {'key': 'k1', 'addresses': ['+15550100'], 'body': 'No rush'})) as Map;
    expect(sent['thread'], 7);
    expect(phone.sent.single.body, 'No rush');
    // What the phone will not do for a computer comes back as its words.
    await expectLater(link.request('deleteThread', {'thread': 7}), throwsA(isA<PhoneError>()));
  });

  test('pairs through the relay, and the same works there', () async {
    final link = mac(MemoryStore(), local: false);
    await pair(link, 'relay');
    expect(link.via, 'relay');
    expect(phone.via, 'relay');
    // The pairing's own channel is all the relay holds: the ten-minute one is gone with the pairing's connection.
    await until(() => relay.channelCount == 1);
    expect((await link.request('conversations') as List).length, 2);
    final heard = <int>[];
    link.events.stream.listen((e) => heard.add(e.args['thread'] as int));
    phone.arrive(7, 'Through the relay');
    await until(() => heard.contains(7));
    await link.request('send', {'key': 'k2', 'addresses': ['+15550100'], 'body': 'Got it'});
    expect(phone.sent.single.body, 'Got it');
    // A picture, in pieces, each smaller than a frame.
    final bridge = LinkCalls(link, DeskStore(Directory.systemTemp.createTempSync('ghost-desk-test'), keychain: false));
    final picture = await bridge.invokeMethod<Object>('part', {'id': 5});
    expect(picture, phone.picture);
  });

  test('with both, the local network is used first, the relay when it goes, and the local network again when it is back', () async {
    final link = mac(MemoryStore());
    await pair(link, 'both');
    // Both were there to use: local was taken, and the phone was not asked through the relay once paired.
    expect(link.via, 'local');
    expect(phone.hellos.last, 'local');
    final relayHellosBefore = phone.hellos.where((v) => v == 'relay').length;

    await phone.leaveLocal();
    await until(() => link.via == 'relay', what: 'never fell back to the relay');
    expect((await link.request('conversations') as List).length, 2);
    expect(phone.hellos.where((v) => v == 'relay').length, relayHellosBefore + 1);

    await phone.rejoinLocal();
    await until(() => link.via == 'local', what: 'never came back to the local network');
    await until(() => phone.via == 'local');
    // The Mac said it was leaving the relay's connection.
    expect(phone.heard, contains('bye'));
    expect((await link.request('conversations') as List).length, 2);
  });

  test('the phone\'s choice of how to connect is the pairing\'s, and a change later reaches the other', () async {
    final store = MemoryStore();
    final link = mac(store);
    // The Mac offered both; on the phone, local only was chosen before "They match".
    await pair(link, 'both', phoneMode: 'local');
    expect(link.phone!.mode, 'local');
    expect(link.via, 'local');
    final id = link.phone!.id;

    await link.setMode('both');
    await until(() => phone.modes[id] == 'both', what: 'the phone never heard the change');
    phone.setMode(id, 'relay');
    await until(() => link.phone!.mode == 'relay' && store.kept!.mode == 'relay', what: 'the Mac never heard the change');
  });

  test('what is typed while the phone is away waits, is shown as waiting, and is sent once when it is back', () async {
    final store = MemoryStore();
    final link = mac(store);
    await pair(link, 'local');
    final bridge = LinkCalls(link, DeskStore(Directory.systemTemp.createTempSync('ghost-desk-test'), keychain: false));
    await bridge.init();
    Sms.calls = bridge;
    final changes = <int>[];
    final sub = Sms.instance.changes.stream.listen(changes.add);
    addTearDown(sub.cancel);

    final before = await Sms.instance.conversations();
    expect(before.first.title, 'Maya');
    expect((await Sms.instance.messages(7)).single.body, 'See you at 7');

    await phone.leaveLocal();
    await until(() => !link.online);
    // Still shown from what was read last.
    expect((await Sms.instance.conversations()).length, 2);
    final thread = await Sms.instance.send(['+15550100'], 'Typed while you were away');
    expect(thread, 7);
    expect(bridge.waiting, 1);
    final shown = await Sms.instance.messages(7);
    expect(shown.first.body, 'Typed while you were away');
    expect(shown.first.state, 'waiting');
    expect(shown.first.outgoing, isTrue);
    expect(shown.last.body, 'See you at 7');
    expect(phone.sent, isEmpty);
    // A conversation the Mac has never seen cannot be started without the phone.
    await expectLater(Sms.instance.send(['+15559999'], 'Hello'), throwsA(isA<LinkDown>()));

    await phone.rejoinLocal();
    await until(() => phone.sent.isNotEmpty, what: 'the waiting text never went');
    await until(() => bridge.waiting == 0);
    expect(phone.sent.single.body, 'Typed while you were away');
    final after = await Sms.instance.messages(7);
    expect(after.first.body, 'Typed while you were away');
    expect(after.first.state, 'sent');
    expect(after.where((m) => m.body == 'Typed while you were away').length, 1);
    expect(changes, contains(-1));
  });

  test('a text whose answer was lost is asked for again under the same name, and sent once', () async {
    final link = mac(MemoryStore());
    await pair(link, 'local');
    await link.request('send', {'key': 'same', 'addresses': ['+15550100'], 'body': 'Once'});
    final again = (await link.request('send', {'key': 'same', 'addresses': ['+15550100'], 'body': 'Once'})) as Map;
    expect(again['again'], isTrue);
    expect(phone.sent.length, 1);
  });

  test('the pairing is kept: a Mac started again finds the phone without pairing', () async {
    final store = MemoryStore();
    await pair(mac(store), 'both');
    links.removeLast().dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final again = mac(store, local: false); // no address given: the one remembered is tried
    await again.start();
    await until(() => again.online, what: 'never reconnected from what was kept');
    expect(again.via, 'local');
    expect(again.phone!.name, 'Fold');
    expect((await again.request('conversations') as List).length, 2);
  });

  test('unpairing from the Mac tells the phone and the relay; unpairing from the phone tells the Mac', () async {
    final store = MemoryStore();
    final link = mac(store);
    await pair(link, 'both');
    await until(() => relay.channelCount == 1);
    await link.unpair();
    expect(link.phone, isNull);
    expect(store.kept, isNull);
    await until(() => phone.keys.isEmpty, what: 'the phone was never told');
    await until(() => relay.channelCount == 0, what: 'the relay still holds the channel');

    await phone.leaveRelay();
    final second = mac(MemoryStore());
    await pair(second, 'local');
    phone.unpair(second.phone!.id);
    await until(() => second.phone == null, what: 'the Mac was never told');
    expect(second.online, isFalse);
  });

  test('a phone that no longer has the pairing says so through the relay, and the Mac says it was refused', () async {
    final store = MemoryStore();
    final link = mac(store, local: false);
    await pair(link, 'relay');
    final id = link.phone!.id;
    links.removeLast().dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Unpaired on the phone while the Mac was closed. The phone is still on the channel (as if it had not yet let go).
    final key = phone.keys[id]!;
    phone.keys.remove(id);
    store.kept = PairedPhone(id: id, name: 'Fold', key: key, mode: 'relay', relay: relayUrl, since: DateTime.now());

    final again = mac(store, local: false);
    await again.start();
    await until(() => again.refused, what: 'never noticed it was unpaired');
    expect(again.online, isFalse);
  });

  test('a phone that scanned another code, or none, is not paired with', () async {
    final link = mac(MemoryStore());
    await link.start();
    final attempt = link.beginPairing(mode: 'local', relay: relayUrl);
    // The phone is listening and has scanned nothing: it knows no such pairing.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(attempt.phase, 'showing');
    expect(phone.hellos, isNotEmpty);
    // Another Mac's code.
    final other = PhoneLink(store: MemoryStore(), name: 'Another Mac');
    links.add(other);
    phone.scan(other.beginPairing(mode: 'local', relay: '').offer.text);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(attempt.phase, 'showing');
    expect(link.phone, isNull);
    // Cancelled on the Mac: the code is gone.
    await link.cancelPairing();
    expect(link.attempt, isNull);
  });

  test('the phone saying the digits differ ends the pairing on the Mac', () async {
    final link = mac(MemoryStore());
    await link.start();
    final attempt = link.beginPairing(mode: 'local', relay: relayUrl);
    phone.scan(attempt.offer.text);
    await until(() => attempt.phase == 'code');
    link.confirmPairing();
    // "They don't match" on the phone: its connection is dropped. The Mac goes back to showing the code, with
    // nothing confirmed.
    await phone.leaveLocal();
    await until(() => attempt.phase == 'showing');
    expect(attempt.mine, isFalse);
    expect(link.phone, isNull);
  });
}
