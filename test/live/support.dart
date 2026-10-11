// What the live tests share: a relay in memory that keeps the real one's promises (server/src/live.rs),
// as the web's own tests have one (core/live/session.test.ts, team.test.ts), and the Mac's core for the REAL crypto
// and the REAL CRDT (tool/build-native.sh host).
import 'dart:async';

import 'package:ghost_md/live/transport.dart';

export '../team_sync/support.dart' show coreBuilt, coreLibrary, coreSkip, openCore;

/// How many rounds of messages a room may trade before settling is given up on as a room that never goes quiet.
const int _rounds = 200;

/// Rooms per account or per organization, the first into a room told so, a count of the others on every join and
/// leave, messages to everyone else or to one device; and delivered a turn later, as a network would, never in the
/// same breath they were sent.
class Relay {
  final Map<String, List<RelayLine>> _rooms = {};
  final List<RelayLine> lines = [];
  int _next = 1;

  /// Every delivery scheduled and not yet done.
  final Set<Future<void>> _deliveries = {};

  /// What each device waits on besides: a session's or a room's `sent`.
  final List<Future<void> Function()> waits = [];

  /// A device's connection, telling [events]. [account] keeps one account's own rooms apart from another's.
  RelayLine line(LiveEvents events, {String account = 'a'}) {
    final line = RelayLine._(this, _next++, events, account);
    lines.add(line);
    return line;
  }

  String _key(RelayLine line, String room, String? org) => org != null ? 'org:$org/$room' : 'acct:${line.account}/$room';

  void _join(RelayLine line, String room, String? org) {
    final members = _rooms.putIfAbsent(_key(line, room, org), () => []);
    if (members.contains(line)) members.remove(line);
    final first = members.isEmpty;
    members.add(line);
    final count = members.length - 1;
    _later(() => line.events.joined(room, first, count, org));
    for (final other in members) {
      if (other != line) _later(() => other.events.peers(room, count, org, null));
    }
  }

  void _leave(RelayLine line, String room, String? org) {
    final members = _rooms[_key(line, room, org)];
    if (members == null || !members.remove(line)) return;
    for (final other in members.toList()) {
      _later(() => other.events.peers(room, members.length - 1, org, line.id));
    }
  }

  void _send(RelayLine line, String room, String data, int? to, String? org) {
    for (final other in (_rooms[_key(line, room, org)] ?? const <RelayLine>[]).toList()) {
      if (other == line || (to != null && other.id != to)) continue;
      _later(() => other.events.message(room, line.id, data, org));
    }
  }

  void _later(void Function() run) {
    late final Future<void> delivery;
    delivery = Future<void>.delayed(Duration.zero).then((_) => run()).whenComplete(() => _deliveries.remove(delivery));
    _deliveries.add(delivery);
  }

  /// Lets every message in flight arrive, and every answer to one be sealed and sent, until the rooms have nothing
  /// left to say: asked of the relay and of the sessions, never timed.
  Future<void> settled() async {
    for (var round = 0; round < _rounds; round += 1) {
      while (_deliveries.isNotEmpty) {
        await Future.wait(_deliveries.toList());
      }
      await Future.wait([for (final wait in waits) wait()]);
      await Future<void>.delayed(Duration.zero);
      if (_deliveries.isEmpty) return;
    }
    throw StateError('The room was still talking after $_rounds rounds of messages.');
  }
}

/// One device's connection to the [Relay].
class RelayLine implements LiveTransport {
  RelayLine._(this._relay, this.id, this.events, this.account);

  final Relay _relay;
  final int id;
  final LiveEvents events;
  final String account;
  final Set<(String, String?)> _in = {};
  bool closed = false;

  /// Every frame this device sent into a room, as `room[@org]:data`.
  final List<String> sent = [];

  @override
  void join(String room, [String? org]) {
    _in.add((room, org));
    _relay._join(this, room, org);
  }

  @override
  void leave(String room, [String? org]) {
    if (_in.remove((room, org))) _relay._leave(this, room, org);
  }

  @override
  void send(String room, String data, {int? to, String? org}) {
    if (!_in.contains((room, org))) return;
    sent.add('$room${org == null ? '' : '@$org'}:$data');
    _relay._send(this, room, data, to, org);
  }

  /// The socket dropped and came back: out of every room, and into each again.
  void dropped() {
    final rooms = _in.toList();
    for (final (room, org) in rooms) {
      _relay._leave(this, room, org);
    }
    for (final (room, org) in rooms) {
      _relay._join(this, room, org);
    }
  }

  @override
  void wake() {}

  @override
  void rest() {}

  @override
  void close() {
    closed = true;
    for (final (room, org) in _in.toList()) {
      _relay._leave(this, room, org);
    }
    _in.clear();
  }
}
