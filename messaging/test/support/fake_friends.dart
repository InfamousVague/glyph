import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ghost_messaging/friends/friends.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/packet.dart';
import 'package:ghost_messaging/net/switchboard.dart';
import 'package:ghost_messaging/sms.dart';

// A stand-in for what Friends stands on (lib/friends/friends.dart, FriendsPort): the routes and the phone of one
// install, with what it sends handed to another's. For test/friends_test.dart and the screens' pictures.

typedef Sent = ({String to, Envelope envelope, bool metered, bool sealed, Set<String>? only});

class FakePort implements FriendsPort {
  FakePort(this.me);

  /// This phone's number.
  final String me;
  late FakePort other;

  /// Where this phone stands with the other, as android E2e keeps it.
  final Map<String, E2eState> book = {};

  /// The relay server's route is up; the other phone is connected to it; it takes what it is given.
  bool up = true;
  bool otherHere = true;
  bool refuses = false;
  bool answers = false;

  final sent = <Sent>[];
  final held = <Envelope>[];
  final rows = <int, ({String address, String words, String state})>{};
  final dropped = <int>[];
  final came = <({String address, String words})>[];
  final keysSent = <String>[];
  final _in = StreamController<Received>.broadcast();
  final _acks = StreamController<String>.broadcast();
  final _changed = ValueNotifier<int>(0);

  void stand(String address, {String state = 'on', String friend = '', bool hasGhost = true}) {
    book[address] = E2eState(address: address, state: state, friend: friend, hasGhost: hasGhost);
    _changed.value++;
  }

  @override
  Peer? peer(String address) => book[address]?.on == true ? Peer(id: 'name-of-$address', key: Uint8List(32), address: address) : null;

  @override
  bool get internet => up;

  @override
  Future<Delivery> send(Peer peer, Envelope envelope, {bool metered = false, bool sealed = true, Set<String>? only}) async {
    sent.add((to: peer.address!, envelope: envelope, metered: metered, sealed: sealed, only: only));
    // A data text: on its way, and nothing more is known.
    if (only != null && only.contains('sms')) return Delivery(envelope.id, via: 'sms', handed: Handed.passed);
    if (!up || refuses) {
      if (!metered) return Delivery(envelope.id, tried: const ['hub: not up']);
      other._arrive(me, envelope, sealed);
      return Delivery(envelope.id, via: 'sms', handed: Handed.passed);
    }
    if (!otherHere) {
      held.add(envelope);
      return Delivery(envelope.id, via: 'hub', handed: Handed.held);
    }
    other._arrive(me, envelope, sealed);
    return Delivery(envelope.id, via: 'hub', handed: Handed.passed, acked: envelope.ack);
  }

  void _arrive(String from, Envelope envelope, bool sealed) => _in.add(Received(Peer(id: 'name-of-$from', address: from), envelope, 'hub', sealed: sealed));

  /// The other phone's app opens: what the relay server kept is handed over, and each is answered.
  void otherBack() {
    otherHere = true;
    for (final e in held) {
      other._arrive(me, e, true);
      _acks.add(e.id);
    }
    held.clear();
  }

  @override
  Stream<Received> get received => _in.stream;
  @override
  Stream<String> get acked => _acks.stream;
  @override
  Future<List<E2eState>> states() async => book.values.toList();

  @override
  Future<void> setFriend(String address, String state) async {
    final s = book[address];
    if (s == null) return;
    book[address] = E2eState(address: address, state: s.state, friend: state, hasGhost: s.hasGhost);
  }

  @override
  Future<void> offerKeys(String address) async {
    keysSent.add(address);
    // android E2e.offered: on where their key is already here, waiting for it where it is not.
    final s = book[address];
    book[address] = E2eState(address: address, state: s?.state == 'pending' ? 'on' : 'offered', friend: s?.friend ?? '', hasGhost: true);
  }

  @override
  Future<int> storeOut(String address, String words) async {
    final id = rows.length + 1;
    rows[id] = (address: address, words: words, state: 'sending');
    return id;
  }

  @override
  Future<void> rowState(int id, String state) async => rows[id] = (address: rows[id]!.address, words: rows[id]!.words, state: state);
  @override
  Future<void> dropRow(int id) async {
    rows.remove(id);
    dropped.add(id);
  }

  @override
  Future<void> storeIn(String address, String words, int at) async => came.add((address: address, words: words));
  @override
  Listenable get changed => _changed;
  @override
  Future<bool> probe() async => answers;
}
