import 'dart:convert';
import 'dart:io';

import 'package:ghost_relay/federation.dart';
import 'package:ghost_relay/home_record.dart';
import 'package:ghost_relay/p256.dart';
import 'package:test/test.dart';

import 'fed_support.dart';

/// What an app says to its relay of home records, and every limit federation keeps (lib/federation.dart): nothing
/// someone else can grow is without one.
void main() {
  late FakeNet net;
  setUp(() => net = FakeNet());

  group('an app gives and asks for home records', () {
    late TestRelay a;
    late Install alice;
    setUp(() async {
      a = TestRelay(net, 'a.test');
      alice = Install();
      await alice.signIn(a);
    });

    Future<Map> give(Object? rec, {Install? as}) async {
      final who = as ?? alice;
      who.say({'dir': 'home', 'rec': rec});
      await pumpEventQueue();
      return who.said.last;
    }

    test('its own record is kept, and answered with the count held', () async {
      final rec = alice.record([a.url]);
      expect(await give(rec), {'dir': 'home', 'a': alice.id, 'ok': true, 'n': 1});
      expect([a.fed.homes.own, a.fed.homes.others, a.fed.homes.isOwn(alice.id)], [1, 0, true]);
      alice.say({'dir': 'home?', 'a': alice.id});
      await pumpEventQueue();
      expect(alice.said.last, {'dir': 'home?', 'a': alice.id, 'rec': rec});
    });

    test('a friend\'s record is kept too, apart from the relay\'s own people\'s', () async {
      final bob = Install();
      final rec = bob.record(['wss://b.test/hub']);
      expect(await give(rec), {'dir': 'home', 'a': bob.id, 'ok': true, 'n': 1});
      expect([a.fed.homes.own, a.fed.homes.others, a.fed.homes.isOwn(bob.id)], [0, 1, false]);
    });

    test('the highest count wins: an older record is passed over, and the answer says what is held', () async {
      final bob = Install();
      final first = bob.record(['wss://b.test/hub'], n: 4), newer = bob.record(['wss://c.test/hub'], n: 5), older = bob.record(['wss://old.test/hub'], n: 3), same = bob.record(['wss://other.test/hub'], n: 5);
      expect((await give(first))['n'], 4);
      expect((await give(newer))['n'], 5);
      expect(await give(older), {'dir': 'home', 'a': bob.id, 'ok': true, 'n': 5});
      expect(await give(first), {'dir': 'home', 'a': bob.id, 'ok': true, 'n': 5});
      expect(await give(same), {'dir': 'home', 'a': bob.id, 'ok': true, 'n': 5}, reason: 'the same count again is not newer');
      expect(a.fed.homes.of(bob.id)!.h, ['wss://c.test/hub']);
    });

    test('what is not a record is refused: changed, signed by another key, too many or too long addresses, made in the future', () async {
      final bob = Install();
      final good = bob.record(['wss://b.test/hub']);
      Map<String, Object?> but(Map<String, Object?> changes) => {...good, ...changes};
      final cases = <String, Object?>{
        'an address changed after signing': but({'h': ['wss://evil.test/hub']}),
        'the count changed': but({'n': 2}),
        'the time changed': but({'t': (good['t'] as int) + 1}),
        'signed by another key': homeRecord(bob.scalar, ['wss://b.test/hub'], signWith: someBytes(32)),
        'another key under her name': but({'k': base64Encode(alice.key)}),
        'her name, over a key that is not hers but did sign it': () {
          // Mallory signs, with her own key, a record that says it is Bob's: every byte of it checks out but the name.
          final mallory = Install();
          final t = DateTime.utc(2026, 11, 22, 11).millisecondsSinceEpoch;
          final sig = P256.sign(mallory.scalar, HomeRecord.signedBytes(a: bob.id, n: 7, t: t, h: ['wss://evil.test/hub']), someBytes(32));
          return {'v': 1, 'a': bob.id, 'k': base64Encode(mallory.key), 'h': ['wss://evil.test/hub'], 'n': 7, 't': t, 's': base64Encode(sig)};
        }(),
        'another name over her key': but({'a': alice.id}),
        'four addresses': bob.record(['wss://1.test/hub', 'wss://2.test/hub', 'wss://3.test/hub', 'wss://4.test/hub'], n: 1),
        'no address': bob.record([], n: 1),
        'an address of 201 characters': bob.record(['wss://b.test/${'x' * 184}/hub'], n: 1),
        'an address with a space in it': bob.record(['wss://b.test/hub x'], n: 1),
        'made an hour from now': bob.record(['wss://b.test/hub'], n: 1, at: net.clock.add(const Duration(hours: 1))),
        'a count of nothing': bob.record(['wss://b.test/hub'], n: 0),
        'a count past four bytes': bob.record(['wss://b.test/hub'], n: 0x100000000),
        'another version': but({'v': 2}),
        'not a map': 'record',
        'nothing': null,
      };
      for (final e in cases.entries) {
        final said = await give(e.value);
        expect([said['dir'], said['ok'], said['err']], ['home', false, 'bad'], reason: e.key);
      }
      expect(a.fed.homes.of(bob.id), isNull);
      // An address of exactly 200 characters, three of them, and a time a few minutes ahead are all taken.
      final long = 'wss://b.test/${'x' * 183}/hub';
      expect(long.length, 200);
      expect((await give(bob.record([long, 'wss://2.test/hub', 'wss://3.test/hub'], n: 1, at: net.clock.add(const Duration(minutes: 4)))))['ok'], isTrue);
    });

    test('home? says what is held of anyone, or that nothing is; asking after others is a lookup, counted as one', () async {
      final bob = Install();
      alice.say({'dir': 'home?', 'a': bob.id});
      alice.say({'dir': 'home?', 'a': 'not a name'});
      await pumpEventQueue();
      expect(alice.said, [{'dir': 'home?', 'a': bob.id, 'none': true}, {'dir': 'home?', 'a': 'not a name', 'none': true}]);
      final rec = bob.record(['wss://b.test/hub']);
      await give(rec);
      alice.say({'dir': 'home?', 'a': bob.id});
      await pumpEventQueue();
      expect(alice.said.last, {'dir': 'home?', 'a': bob.id, 'rec': rec});
      // 120 lookups an hour, as for usernames; one's own record is not a lookup.
      alice.said.clear();
      for (var i = 0; i < 120; i++) {
        alice.say({'dir': 'home?', 'a': bob.id});
      }
      await pumpEventQueue();
      expect(alice.said.last, {'dir': 'err', 'about': 'home?', 'err': 'Too many lookups. Try again in a while.'});
      expect(alice.said.where((m) => m['rec'] != null), hasLength(118));
      alice.say({'dir': 'home?', 'a': alice.id});
      await pumpEventQueue();
      expect(alice.said.last, {'dir': 'home?', 'a': alice.id, 'none': true});
    });

    test('the same record given again costs no check; a new one does, and an install has only so many an hour', () async {
      net = FakeNet();
      a = TestRelay(net, 'a.test', checksAnHour: 3);
      await alice.signIn(a);
      final others = [for (var i = 0; i < 4; i++) Install().record(['wss://b.test/hub'])];
      for (var i = 0; i < 3; i++) {
        expect((await give(others[i]))['ok'], isTrue);
      }
      for (var i = 0; i < 20; i++) {
        expect((await give(others[i % 3]))['ok'], isTrue, reason: 'held already: nothing to check');
      }
      expect(await give(others[3]), {'dir': 'home', 'a': others[3]['a'], 'ok': false, 'err': 'busy'});
      expect(a.fed.homes.others, 3);
      // Someone else's count is their own.
      final carol = Install();
      await carol.signIn(a);
      expect((await give(others[3], as: carol))['ok'], isTrue);
      await net.pass(const Duration(hours: 1));
      expect((await give(Install().record(['wss://b.test/hub'])))['ok'], isTrue);
    });

    test('and the relay checks only so many in any one second, for everyone together', () async {
      net = FakeNet();
      a = TestRelay(net, 'a.test', checksASecond: 2);
      await alice.signIn(a);
      final carol = Install();
      await carol.signIn(a);
      expect((await give(Install().record(['wss://b.test/hub'])))['ok'], isTrue);
      expect((await give(Install().record(['wss://b.test/hub']), as: carol))['ok'], isTrue);
      final third = Install().record(['wss://b.test/hub']);
      expect((await give(third))['err'], 'busy');
      await net.pass(const Duration(seconds: 1));
      expect((await give(third))['ok'], isTrue);
    });

    test('the relay\'s own people\'s records are at most so many: one more lets go of whoever gave theirs longest ago', () async {
      net = FakeNet();
      a = TestRelay(net, 'a.test', maxOwn: 2);
      final people = [for (var i = 0; i < 3; i++) Install()];
      for (final p in people) {
        await p.signIn(a);
      }
      await people[0].giveHome(a);
      await people[1].giveHome(a);
      // The first gives theirs again (their app signed in again): now the second is the one longest ago.
      people[0].say({'dir': 'home', 'rec': people[0].record([a.url], n: 1)});
      await pumpEventQueue();
      await people[2].giveHome(a);
      expect(a.fed.homes.own, 2);
      expect([for (final p in people) a.fed.homes.isOwn(p.id)], [true, false, true]);
    });

    test('and others\' are the so many used most lately', () async {
      net = FakeNet();
      a = TestRelay(net, 'a.test', maxOthers: 2);
      await alice.signIn(a);
      final friends = [for (var i = 0; i < 3; i++) Install()];
      await give(friends[0].record(['wss://b.test/hub']));
      await give(friends[1].record(['wss://b.test/hub']));
      // The first is used (a packet is routed by it): the second is now the one used longest ago.
      net.down.add('wss://b.test/hub');
      alice.send(friends[0].id, [1]);
      await pumpEventQueue();
      await give(friends[2].record(['wss://b.test/hub']));
      expect(a.fed.homes.others, 2);
      expect([for (final f in friends) a.fed.homes.of(f.id) != null], [true, false, true]);
    });

    test('a friend\'s newer copy of one of the relay\'s own people\'s takes the older one\'s place, and they stay its own', () async {
      await alice.giveHome(a);
      final carol = Install();
      await carol.signIn(a);
      final newer = alice.record(['wss://b.test/hub']);
      expect(await give(newer, as: carol), {'dir': 'home', 'a': alice.id, 'ok': true, 'n': 2});
      expect([a.fed.homes.of(alice.id)!.n, a.fed.homes.isOwn(alice.id), a.fed.homes.own, a.fed.homes.others], [2, true, 1, 0]);
    });
  });

  group('what is kept across restarts', () {
    test('the records of people who gave theirs here are; others\' are not', () async {
      final dir = Directory.systemTemp.createTempSync('ghost-fed-homes-');
      addTearDown(() => dir.deleteSync(recursive: true));
      var a = TestRelay(net, 'a.test', dataDir: dir);
      final alice = Install(), bob = Install();
      await alice.signIn(a);
      final mine = await alice.giveHome(a);
      alice.say({'dir': 'home', 'rec': bob.record(['wss://b.test/hub'])});
      await pumpEventQueue();
      expect([a.fed.homes.own, a.fed.homes.others], [1, 1]);
      a.fed.stop();
      expect(jsonDecode(File('${dir.path}/homes.json').readAsStringSync()), {'v': 1, 'own': [mine]});
      final id = a.id;
      a = TestRelay(net, 'a.test', dataDir: dir, seed: 9);
      expect(a.id, id, reason: 'and it is the same relay: its key was kept');
      expect([a.fed.homes.own, a.fed.homes.others, a.fed.homes.of(alice.id)!.toJson(), a.fed.homes.of(bob.id)], [1, 0, mine, isNull]);
      a.fed.stop();
    });

    test('a homes.json that can\'t be read is started again from nothing, and one with a record that isn\'t one passes over it', () async {
      final dir = Directory.systemTemp.createTempSync('ghost-fed-homes-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/homes.json').writeAsStringSync('{not json');
      expect(TestRelay(net, 'a.test', dataDir: dir).fed.homes.own, 0);
      final bob = Install();
      File('${dir.path}/homes.json').writeAsStringSync(jsonEncode({'v': 1, 'own': [{'v': 1, 'a': 'nobody'}, bob.record(['wss://a.test/hub']), 7]}));
      final b = TestRelay(net, 'a.test', dataDir: dir);
      expect([b.fed.homes.own, b.fed.homes.isOwn(bob.id)], [1, true]);
    });
  });

  group('what one linked relay may send', () {
    late TestRelay b;
    late HandRelay h;
    late Install pat, bob;

    /// A relay played by hand, linked to b, speaking for Pat; Bob is on b.
    Future<void> linked(TestRelay Function() make) async {
      b = make();
      h = HandRelay();
      await h.link(b);
      pat = Install();
      bob = Install();
      await bob.signIn(b);
      h.say({'fed': 'home', 'rec': pat.record(['ghost-relay://${h.id}'])});
      await pumpEventQueue();
    }

    test('so many packets a minute: one more is refused, and taken again once the minute is over', () async {
      await linked(() => TestRelay(net, 'b.test', packetsAMinute: 3));
      final sent = [for (var i = 0; i < 4; i++) h.send(bob.id, pat.id, [i])];
      await pumpEventQueue();
      expect([for (final n in sent) h.answerTo(n)], [{'ack': 1, 'here': true}, {'ack': 2, 'here': true}, {'ack': 3, 'here': true}, {'nak': 4, 'err': 'limit'}]);
      expect(bob.frames, hasLength(3));
      await net.pass(const Duration(seconds: 59));
      var n = h.send(bob.id, pat.id, [9]);
      await pumpEventQueue();
      expect(h.answerTo(n), {'nak': n, 'err': 'limit'});
      await net.pass(const Duration(seconds: 1));
      n = h.send(bob.id, pat.id, [9]);
      await pumpEventQueue();
      expect(h.answerTo(n), {'ack': n, 'here': true});
      // Another relay's count is its own.
      final other = HandRelay();
      await other.link(b);
      final pam = Install();
      other.say({'fed': 'home', 'rec': pam.record(['ghost-relay://${other.id}'])});
      for (var i = 0; i < 2; i++) {
        h.send(bob.id, pat.id, [i]);
      }
      final theirs = other.send(bob.id, pam.id, [1]);
      await pumpEventQueue();
      expect(other.answerTo(theirs), {'ack': theirs, 'here': true});
    });

    test('so many bytes a day', () async {
      await linked(() => TestRelay(net, 'b.test', bytesADay: 300));
      final first = h.send(bob.id, pat.id, List.filled(100, 1)), second = h.send(bob.id, pat.id, List.filled(100, 2)), third = h.send(bob.id, pat.id, List.filled(100, 3));
      await pumpEventQueue();
      expect([h.answerTo(first), h.answerTo(second), h.answerTo(third)], [{'ack': first, 'here': true}, {'ack': second, 'here': true}, {'nak': third, 'err': 'limit'}], reason: 'two of 137 bytes each fit in 300; a third does not');
      // (An idle link is closed meanwhile; the count is the relay's, not the link's.)
      await net.pass(const Duration(hours: 23, minutes: 59));
      expect((await h.link(b))['ok'], isTrue);
      var n = h.send(bob.id, pat.id, List.filled(100, 3));
      await pumpEventQueue();
      expect(h.answerTo(n), {'nak': n, 'err': 'limit'});
      await net.pass(const Duration(minutes: 1));
      n = h.send(bob.id, pat.id, List.filled(100, 3));
      await pumpEventQueue();
      expect(h.answerTo(n), {'ack': n, 'here': true});
    });

    test('so many records a minute', () async {
      await linked(() => TestRelay(net, 'b.test', recordsAMinute: 3));
      final people = [for (var i = 0; i < 4; i++) Install()];
      // Pat's was the first; two more are taken, and the fourth is not.
      for (final p in people.take(3)) {
        h.say({'fed': 'home', 'rec': p.record(['ghost-relay://${h.id}'])});
      }
      await pumpEventQueue();
      expect([for (final p in people) b.fed.homes.of(p.id) != null], [true, true, false, false]);
      await net.pass(const Duration(minutes: 1));
      h.say({'fed': 'home', 'rec': people[3].record(['ghost-relay://${h.id}'])});
      await pumpEventQueue();
      expect(b.fed.homes.of(people[3].id), isNotNull);
    });

    test('and so many record checks an hour, as an install has', () async {
      await linked(() => TestRelay(net, 'b.test', checksAnHour: 2));
      final people = [for (var i = 0; i < 2; i++) Install()];
      for (final p in people) {
        h.say({'fed': 'home', 'rec': p.record(['ghost-relay://${h.id}'])});
      }
      await pumpEventQueue();
      expect([for (final p in people) b.fed.homes.of(p.id) != null], [true, false], reason: 'Pat\'s and one more');
    });

    test('a relay told it is over the limit keeps the packet and sends it again in a while: the sender is told it is kept', () async {
      b = TestRelay(net, 'b.test', seed: 2, packetsAMinute: 2);
      final a = TestRelay(net, 'a.test');
      final alice = Install();
      bob = Install();
      await alice.signIn(a);
      await bob.signIn(b);
      await alice.giveHome(a);
      alice.say({'dir': 'home', 'rec': await bob.giveHome(b)});
      await pumpEventQueue();
      alice.said.clear();
      final sent = [for (var i = 0; i < 3; i++) alice.send(bob.id, [i])];
      await net.settle();
      expect(bob.frames, hasLength(2));
      expect(alice.answerTo(sent.last), isNull);
      expect(a.fed.waitingFor(b.url), 1);
      await net.pass(Federation.answerWithin);
      expect(alice.answerTo(sent.last), {'ack': sent.last, 'here': false, 'fed': true});
      await net.pass(const Duration(seconds: 56));
      await net.settle();
      expect(bob.frames, [for (var i = 0; i < 3; i++) handed(alice.id, [i])]);
      expect(a.fed.waiting, 0);
    });

    test('what is not a frame or a message of a link\'s is passed over: nothing is answered, nothing breaks', () async {
      await linked(() => TestRelay(net, 'b.test'));
      h.socket.add([5]);
      h.socket.add([5, 0, 0, 0, 1]);
      h.socket.add([6, ...List.filled(40, 0)]);
      h.socket.add([9, ...List.filled(60, 0)]);
      h.socket.add(<int>[]);
      h.socket.add('not json');
      h.socket.add(jsonEncode([1, 2]));
      h.socket.add(jsonEncode({'fed': 'what'}));
      h.socket.add(jsonEncode({'ack': 99, 'here': true}));
      h.socket.add(jsonEncode({'fed': 'home', 'rec': 'nothing'}));
      h.socket.add('x' * 9000);
      await pumpEventQueue();
      expect(h.said, isEmpty);
      expect([h.socket.isOpen, b.fed.linkedWith(h.id)], [true, true]);
      final n = h.send(bob.id, pat.id, [1]);
      await pumpEventQueue();
      expect(h.answerTo(n), {'ack': n, 'here': true});
    });
  });

  test('a record the store holds is read for its shape alone when it is read back: HomeBook keeps what it is given', () {
    final book = HomeBook(maxOwn: 2, maxOthers: 2);
    HomeRecord rec(Install who, int n) => HomeRecord.read(who.record(['wss://x.test/hub'], n: n), now: DateTime.utc(2026, 11, 22, 12)).rec!;
    final p = Install(), q = Install();
    expect(book.keep(rec(p, 2)), isTrue);
    expect(book.keep(rec(p, 2)), isFalse);
    expect(book.keep(rec(p, 1)), isFalse);
    expect(book.holds(p.id, 2, book.of(p.id)!.s), isTrue);
    expect(book.holds(p.id, 3, book.of(p.id)!.s), isFalse);
    expect(book.holds(q.id, 2, book.of(p.id)!.s), isFalse);
    expect([book.own, book.others, book.dirty], [0, 1, false], reason: 'others\' are not written anywhere');
    expect(book.keep(rec(p, 2), byOwner: true), isFalse, reason: 'nothing newer, but it is one of the relay\'s own from now on');
    expect([book.own, book.others, book.dirty], [1, 0, true]);
  });
}
