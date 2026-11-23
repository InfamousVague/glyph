// GMFB-53 (@kevin): "Upon logging in on web, none of my messages appear in the sidebar and only my circles appear."
// The account's backup carries friends and circles, never conversations, and the copies an account's devices pass
// each other (Friends.copyKind) carry only what is said from then on: so any device signed in on (a browser, an iPhone
// or a computer of its own) had its friends and an empty list. Now a device asks its account's other devices for
// the conversations they hold, once, and keeps them in place (Friends.historyAsk, historyKind; UsernameChats
// history and keepHistory).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/friends/buddies.dart';
import 'package:ghost_messaging/friends/friends.dart';
import 'package:ghost_messaging/standalone/chats.dart';

import 'support/fake_friends.dart';

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('a device signed in on asks its account\'s other devices once, and keeps their conversations; nobody else does', () async {
    final phone = FakePort('@kevin'), browser = FakePort('@kevin'), friend = FakePort('@ben');
    for (final p in [phone, browser]) {
      p.other = friend;
      p.stand('@ben', friend: 'yes');
    }
    friend.other = phone;
    phone.pastHeld['@ben'] = [(t: 'Dinner at 8?', at: 1000, o: true), (t: 'Sure!', at: 2000, o: false)];
    // A conversation too long for one answer: it comes in parts, the newest [historyMost] of it.
    phone.pastHeld['@amy'] = [for (var i = 0; i < 400; i++) (t: 'line $i ${'x' * 400}', at: 10000 + i, o: i.isEven)];
    // The phone is the account's only device, and was open first: its asking goes nowhere, and is not asked again.
    final onPhone = Friends(phone);
    addTearDown(onPhone.shutdown);
    await onPhone.start();
    await until(() => phone.mineSent.isNotEmpty);
    expect(phone.mineSent.single.kind, Friends.historyAsk);
    // Then the browser is signed in on: it asks, the phone answers it, and it keeps what the phone holds.
    phone.twin = browser;
    browser.twin = phone;
    final onBrowser = Friends(browser);
    addTearDown(onBrowser.shutdown);
    await onBrowser.start();
    await until(() => (browser.pastKept['@amy']?.length ?? 0) >= Friends.historyMost);
    expect(browser.pastKept['@ben'], phone.pastHeld['@ben']);
    expect(browser.pastKept['@amy'], phone.pastHeld['@amy']!.sublist(400 - Friends.historyMost));
    final answers = phone.mineSent.where((e) => e.kind == Friends.historyKind).toList();
    expect(answers.length, greaterThan(2), reason: 'Amy\'s conversation in parts');
    // The phone kept nothing of its own answer, and asked only the once.
    expect(phone.pastKept, isEmpty);
    expect(phone.mineSent.where((e) => e.kind == Friends.historyAsk).length, 1);
    // The same asking again (the relay handing it over twice) is answered once; another device's asking is not taken.
    final sentBefore = phone.mineSent.length;
    final ask = browser.mineSent.firstWhere((e) => e.kind == Friends.historyAsk);
    browser.twin!.arriveFrom('mine', '', ask);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(phone.mineSent.length, sentBefore);
  });

  test('kept in place by when each was written, once each, as past messages: nothing unread', () {
    final chats = UsernameChats(save: () {}, buddies: () => const <Buddy>[]);
    chats.textIn('@ben', 'live, after sign-in', 5000);
    final t = chats.threadWith('@ben')..unread = false;
    final past = <PastRow>[(t: 'first', at: 1000, o: true), (t: 'second', at: 2000, o: false), (t: 'live, after sign-in', at: 5000, o: false)];
    expect(chats.keepHistory('@ben', past), 2);
    expect([for (final r in t.rows) r.body], ['first', 'second', 'live, after sign-in']);
    expect(t.rows.first.state, 'sent');
    expect(t.unread, isFalse);
    // Two devices answering: nothing twice.
    expect(chats.keepHistory('@ben', past), 0);
    expect(t.rows.length, 3);
    // Only conversations with friends by username; and what this device hands over leaves out calls and failures.
    expect(chats.keepHistory('+15550001111', past), 0);
    chats.callNote('@ben', 'Missed call', 6000, out: false);
    expect(chats.history().single.rows.map((r) => r.t), ['first', 'second', 'live, after sign-in']);
    expect(UsernameChats.pastRows([['a', 1, 1], ['b', 2, 0], 'junk', [3, 4, 5]]), [(t: 'a', at: 1, o: true), (t: 'b', at: 2, o: false)]);
  });
}
