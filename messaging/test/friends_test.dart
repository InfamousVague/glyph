import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/friends/friends.dart';
import 'package:ghost_messaging/net/packet.dart';

import 'support/fake_friends.dart';

// Friends (lib/friends/friends.dart) between two phones that are not there: each has a stand-in for the routes and
// the phone, and what one sends reaches the other. The routes themselves are tried in test/net_test.dart.

const ann = '+15550001111', ben = '+15550002222';

Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

/// Waits, a little at a time and for five seconds at most, until [done]: no fixed sleep, which a busy machine outruns.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakePort a, b;
  late Friends annsPhone, bensPhone;

  /// Two phones; encryption is on between them unless [keys] says where each stands with the other.
  Future<void> two({String keys = 'on', String annIs = '', String benIs = ''}) async {
    a = FakePort(ann);
    b = FakePort(ben);
    a.other = b;
    b.other = a;
    a.stand(ben, state: keys, friend: annIs);
    b.stand(ann, state: keys, friend: benIs);
    annsPhone = Friends(a);
    bensPhone = Friends(b);
    await annsPhone.start();
    await bensPhone.start();
    await settle();
  }

  tearDown(() async {
    await annsPhone.shutdown();
    await bensPhone.shutdown();
  });

  test('one asks, the other accepts, and they are friends', () async {
    await two();
    expect(annsPhone.offers(annsPhone.of(ben)!), isTrue);
    await annsPhone.add(ben);
    await settle();
    expect(annsPhone.stateOf(ben), 'asked');
    expect(bensPhone.stateOf(ann), 'invited');
    expect(annsPhone.isFriend(ben), isFalse);
    // Asking by hand may cost a text where the relay server is not reached; it went sealed.
    expect(a.sent.single.metered, isTrue);
    expect(a.sent.single.sealed, isTrue);
    expect(a.sent.single.envelope.kind, 'friend');
    await bensPhone.accept(ann);
    await settle();
    expect(annsPhone.isFriend(ben), isTrue);
    expect(bensPhone.isFriend(ann), isTrue);
    expect(annsPhone.friends.single.address, ben);
    // Neither is offered Add friend again.
    expect(annsPhone.offers(annsPhone.of(ben)!), isFalse);
  });

  test('two who ask each other are friends at once', () async {
    await two();
    a.otherHere = false;
    b.otherHere = false;
    await annsPhone.add(ben);
    await bensPhone.add(ann);
    expect(annsPhone.stateOf(ben), 'asked');
    expect(bensPhone.stateOf(ann), 'asked');
    a.otherBack();
    b.otherBack();
    await settle();
    expect(annsPhone.isFriend(ben), isTrue);
    expect(bensPhone.isFriend(ann), isTrue);
  });

  test('with no keys exchanged yet the key goes first, and the asking waits for theirs', () async {
    await two(keys: 'none');
    expect(annsPhone.offers(annsPhone.of(ben)!), isTrue, reason: 'they have the app: offered');
    await annsPhone.add(ben);
    await settle();
    expect(a.keysSent, [ben]);
    expect(annsPhone.stateOf(ben), 'want');
    expect(a.sent, isEmpty, reason: 'nobody to say it to yet');
    // Ben accepts encryption: both are on, and Ann's phone hears that something changed.
    a.stand(ben, friend: 'want');
    b.stand(ann);
    await settle();
    expect(annsPhone.stateOf(ben), 'asked');
    expect(bensPhone.stateOf(ann), 'invited');
  });

  test('no, and taking it back, and stopping', () async {
    await two();
    await annsPhone.add(ben);
    await settle();
    await bensPhone.decline(ann);
    await settle();
    expect(annsPhone.stateOf(ben), '');
    expect(bensPhone.stateOf(ann), '');
    // Asked again and taken back before an answer.
    await annsPhone.add(ben);
    await settle();
    await annsPhone.remove(ben);
    await settle();
    expect(bensPhone.stateOf(ann), '');
    // Friends, then one stops.
    await annsPhone.add(ben);
    await settle();
    await bensPhone.accept(ann);
    await settle();
    await bensPhone.remove(ann);
    await settle();
    expect(annsPhone.isFriend(ben), isFalse);
    expect(bensPhone.isFriend(ann), isFalse);
    expect(await annsPhone.sendText(ben, 'still there?'), isFalse, reason: 'it goes as a text again');
  });

  test('what a friend writes goes by the routes and is kept on both phones', () async {
    await two(annIs: 'yes', benIs: 'yes');
    expect(await annsPhone.sendText(ben, 'See you at seven'), isTrue);
    await settle();
    expect(b.came.single, (address: ann, words: 'See you at seven'));
    expect(a.rows.values.single, (address: ben, words: 'See you at seven', state: 'delivered'));
    final text = a.sent.single;
    expect(text.envelope.kind, 'text');
    expect(text.metered, isFalse, reason: 'never as a data text');
    expect(text.sealed, isTrue);
  });

  test('a friend who is away: kept for them, one wake, and marked when their app has it', () async {
    await two(annIs: 'yes', benIs: 'yes');
    a.otherHere = false;
    expect(await annsPhone.sendText(ben, 'one'), isTrue);
    expect(await annsPhone.sendText(ben, 'two'), isTrue);
    await settle();
    expect(a.rows.values.map((r) => r.state), ['sent', 'sent']);
    expect(b.came, isEmpty);
    // One wake for the two: a data text, in the clear, with nothing in it and no answer wanted.
    final wakes = a.sent.where((s) => s.envelope.kind == 'wake').toList();
    expect(wakes, hasLength(1));
    expect(wakes.single.only, {'sms'});
    expect(wakes.single.sealed, isFalse);
    expect(wakes.single.metered, isTrue);
    expect(wakes.single.envelope.body, isEmpty);
    expect(wakes.single.envelope.ack, isFalse);
    // Ben opens the app.
    a.otherBack();
    await settle();
    expect(b.came.map((c) => c.words), ['one', 'two']);
    expect(a.rows.values.map((r) => r.state), ['delivered', 'delivered']);
  });

  test('where no route that costs nothing is up, or the route refuses, it is left to go as a text', () async {
    await two(annIs: 'yes', benIs: 'yes');
    a.up = false;
    expect(await annsPhone.sendText(ben, 'hello'), isFalse);
    expect(a.rows, isEmpty);
    expect(a.sent, isEmpty);
    a.up = true;
    a.refuses = true;
    expect(await annsPhone.sendText(ben, 'hello'), isFalse);
    expect(a.rows, isEmpty, reason: 'what was kept for it is taken back');
    expect(a.dropped, [1]);
    expect(b.came, isEmpty);
  });

  test('words from someone who is not a friend here are kept, and they are told', () async {
    await two(annIs: 'yes');
    expect(await annsPhone.sendText(ben, 'are we friends?'), isTrue);
    await settle();
    expect(b.came.single.words, 'are we friends?');
    expect(annsPhone.isFriend(ben), isFalse, reason: 'Ben\'s phone said it is over');
    // And where this phone had asked, their writing as a friend is their yes.
    await two(annIs: 'yes', benIs: 'asked');
    expect(await annsPhone.sendText(ben, 'yes!'), isTrue);
    await settle();
    expect(bensPhone.isFriend(ann), isTrue);
  });

  test('the wake is a whole packet in the clear that the phone can know without the app (android Friends.isWake)', () async {
    await two();
    final bytes = Packet.wrap(from: '00112233445566778899aabbccddeeff', sealed: false, payload: Envelope(kind: 'wake', ack: false).encode());
    // A byte of version and flags, neither sealed nor a piece; the sender's name; then the envelope as JSON.
    expect(bytes[0], 0x10);
    expect(jsonDecode(utf8.decode(bytes.sublist(17)))['k'], 'wake');
    expect(bytes.length, lessThanOrEqualTo(133), reason: 'one data text');
  });

  test('nothing is offered until a relay server is known to answer', () async {
    await two();
    final c = FakePort('+15550003333')
      ..up = false
      ..stand(ben, state: 'none');
    c.other = b;
    final phone = Friends(c);
    await phone.start();
    expect(phone.available, isFalse);
    expect(phone.offers(phone.of(ben)!), isFalse);
    await phone.look();
    expect(phone.available, isFalse, reason: 'nothing answered');
    await phone.shutdown();
    // One answers: offered from then on, with the route itself not up (nobody to dial for yet).
    final d = FakePort('+15550004444')
      ..up = false
      ..answers = true
      ..stand(ben, state: 'none');
    d.other = b;
    final second = Friends(d);
    await second.start();
    var told = 0;
    second.addListener(() => told++);
    await second.look();
    expect(second.available, isTrue);
    expect(second.offers(second.of(ben)!), isTrue);
    expect(told, 1);
    await second.shutdown();
  });

  // Matt, 2026-11-16: "Yes, fix delivery". A message the relay server handed to a connection that had just died was
  // lost, with nothing to say so: now what has had no answer goes again until it has one.
  test('handed on and never answered: sent again with the same id when a route comes up, and kept once', () async {
    await two(annIs: 'yes', benIs: 'yes');
    a.lost = true;
    expect(await annsPhone.sendText(ben, 'are you there'), isTrue);
    await settle();
    expect(b.came, isEmpty);
    expect(a.rows.values.single.state, 'sent');
    expect(annsPhone.unanswered, 1);
    // The connection is made again (the app came back): it goes again, arrives and is answered.
    a.lost = false;
    a.bump();
    await until(() => b.came.isNotEmpty && annsPhone.unanswered == 0);
    expect(b.came.map((c) => c.words), ['are you there']);
    expect(a.rows.values.single.state, 'delivered');
    expect(annsPhone.unanswered, 0);
    final texts = a.sent.where((x) => x.envelope.kind == 'text').toList();
    expect(texts, hasLength(2));
    expect(texts.last.envelope.id, texts.first.envelope.id, reason: 'the same id, so it is known for the same one');
  });

  test('the same message twice (its answer was lost) is kept once', () async {
    await two(annIs: 'yes', benIs: 'yes');
    final e = Envelope(kind: 'text', body: {'t': 'once'});
    b.arriveAgain(ann, e);
    b.arriveAgain(ann, e);
    await settle();
    expect(b.came.map((c) => c.words), ['once']);
  });

  test('sent again later and later: twenty seconds, then twice as long, five minutes at most', () {
    expect([for (var t = 1; t <= 6; t++) Friends.resendAfter(t).inSeconds], [20, 40, 80, 160, 300, 300]);
  });

  test('what waits for an answer is kept with the app\'s choices: an app closed meanwhile sends it after', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (_) async => null);
    final app = AppState();
    a = FakePort(ann);
    b = FakePort(ben);
    a.other = b;
    b.other = a;
    a.stand(ben, friend: 'yes');
    b.stand(ann, friend: 'yes');
    annsPhone = Friends(a);
    bensPhone = Friends(b);
    await annsPhone.start(app);
    await bensPhone.start();
    a.lost = true;
    await annsPhone.sendText(ben, 'before closing');
    await settle();
    expect(app.choice('friends_out', '[]'), contains('before closing'));
    // The app closes and opens again.
    await annsPhone.shutdown();
    a.lost = false;
    annsPhone = Friends(a);
    await annsPhone.start(app);
    expect(annsPhone.unanswered, 1);
    a.bump();
    await until(() => b.came.isNotEmpty && annsPhone.unanswered == 0);
    expect(b.came.map((c) => c.words), ['before closing']);
    expect(annsPhone.unanswered, 0);
    expect(app.choice('friends_out', '[]'), '[]');
  });

  // GMFB-21 (Matt, Windows 0.12.5: "I sent a DM on my phone and it didn't sync the chat history across my mac and PC").
  test('a friend by username: what one device sends or is sent reaches the account\'s other devices, once', () async {
    final phone = FakePort('@ann'), mac = FakePort('@ann'), friend = FakePort('@ben');
    phone.other = friend;
    mac.other = friend;
    friend.other = phone;
    phone.twin = mac;
    mac.twin = phone;
    phone.stand('@ben', friend: 'yes');
    mac.stand('@ben', friend: 'yes');
    friend.stand('@ann', friend: 'yes');
    final onPhone = Friends(phone), onMac = Friends(mac), bens = Friends(friend);
    annsPhone = onPhone;
    bensPhone = bens;
    addTearDown(onMac.shutdown);
    await onPhone.start();
    await onMac.start();
    await bens.start();
    await settle();

    expect(await onPhone.sendText('@ben', 'Dinner at 8?'), isTrue);
    await until(() => mac.rows.isNotEmpty);
    expect(friend.came.single.words, 'Dinner at 8?');
    expect(mac.rows.values.single, (address: '@ben', words: 'Dinner at 8?', state: 'sent'), reason: 'kept on the Mac as sent by Ann');
    expect(mac.keptAt.values.single, isNonZero, reason: 'in its place by when it was written');
    await settle();
    expect(phone.rows.length, 1, reason: 'the Mac passes it on, and the phone knows it already');

    expect(await bens.sendText('@ann', 'Sure!'), isTrue);
    await until(() => mac.came.isNotEmpty);
    expect(phone.came.single.words, 'Sure!');
    expect(mac.came.single, (address: '@ben', words: 'Sure!'), reason: 'what reached the phone reaches the Mac');
    await settle();
    expect(phone.came.length, 1, reason: 'once');

    // A phone-number friend's messages are the phone's own: no copies.
    final before = phone.mineSent.length;
    phone.stand(ben, friend: 'yes');
    await onPhone.sendText(ben, 'hello');
    await settle();
    expect(phone.mineSent.length, before);
  });
}
