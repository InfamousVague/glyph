import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../net/carrier.dart';
import '../net/crypto.dart';
import '../net/net.dart';
import '../net/packet.dart';
import '../net/switchboard.dart';
import '../sms.dart';
import 'friends.dart';

/// One member of a group: who they are to the routes ([id], the name of their [key]), their number, and who they
/// are in this phone's contacts.
class GroupMember {
  const GroupMember({required this.id, required this.key, this.address = '', this.name, this.photo, this.admin = false, this.me = false});
  final String id;
  final String key;
  final String address;
  final String? name;
  final String? photo;
  final bool admin;
  final bool me;

  /// What they are called in a line about the group.
  String get label => me ? 'You' : (name ?? (address.isEmpty ? 'Someone' : address));

  Person get person => Person(address: address, name: name, photo: photo);

  factory GroupMember.from(Map m) => GroupMember(
        id: m['id'] as String,
        key: (m['key'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        name: m['name'] as String?,
        photo: m['photo'] as String?,
        admin: m['admin'] == true,
        me: m['me'] == true,
      );
}

/// A group of friends as this phone holds it (android Groups.view).
class Group {
  const Group({required this.id, required this.name, required this.v, required this.thread, required this.members, this.gone = false});
  final String id;
  final String name;

  /// How many times it has been changed: a later state is one with a higher count.
  final int v;

  /// Its conversation on this phone.
  final int thread;
  final List<GroupMember> members;

  /// This phone left it or was taken out: its conversation is kept, and nothing more is written in it.
  final bool gone;

  GroupMember? member(String id) => members.where((m) => m.id == id).firstOrNull;
  GroupMember? get mine => members.where((m) => m.me).firstOrNull;
  List<GroupMember> get others => members.where((m) => !m.me).toList();
  bool get amAdmin => !gone && (mine?.admin ?? false);

  /// What it goes by: its name, or its people where it has none.
  String get title => name.isNotEmpty ? name : Conversation.peopleTitle([for (final m in others) m.person]);

  factory Group.from(Map m) => Group(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        v: (m['v'] as num?)?.toInt() ?? 1,
        thread: (m['thread'] as num?)?.toInt() ?? -1,
        gone: m['gone'] == true,
        members: [for (final x in (m['members'] as List? ?? const [])) GroupMember.from(x as Map)],
      );

  /// As it is kept and told: `{id, name, v, members: [{i, k, a}], admins: [i]}`.
  Map<String, dynamic> state({String? name, int? v, List<Map<String, dynamic>>? members, List<String>? admins, bool? gone}) => {
        'id': id,
        'name': name ?? this.name,
        'v': v ?? this.v,
        'members': members ?? [for (final m in this.members) {'i': m.id, 'k': m.key, 'a': m.address}],
        'admins': admins ?? [for (final m in this.members.where((m) => m.admin)) m.id],
        if (gone ?? this.gone) 'gone': true,
      };
}

/// What [Groups] stands on: the routes and the phone. The app's own is [_AppPort]; a test gives several of its own.
abstract class GroupsPort {
  /// This phone's name to the routes; null until they are set up.
  String? get me;
  Peer? peer(String id);
  bool get internet;
  Future<Delivery> send(Peer peer, Envelope envelope);
  Stream<Received> get received;

  /// Whether [address] is a friend: a group is joined only at a friend's asking.
  bool isFriend(String? address);
  void wake(Peer peer);

  /// The records (android Groups.kt): read, a new one of this phone's making, a person as a member, kept.
  Future<List<Group>> groups();
  Future<Map<String, dynamic>> draft(String id, String name, List<String> addresses);
  Future<Map<String, dynamic>> member(String address);
  Future<Group> save(Map<String, dynamic> state);

  /// What is written in a group, kept in its conversation.
  Future<int> storeOut(String id, String words);
  Future<void> rowState(int row, String state);
  Future<void> storeIn(String id, String from, String words, int at);
  Future<void> note(String id, String words);
}

/// Groups of friends (Matt, 2026-11-14: "expand on the ability to create, name and manage groups like telegram").
///
/// **What one is.** A name, members, and admins, held on each member's phone and changed only by an admin. It is
/// made out of friends by one person, who is its first admin. It is not a group text: what is written in it goes to
/// each member by the app's routes (lib/net), sealed with that pair's key, and never as an MMS; its conversation on
/// the phone is its own (android Groups.kt).
///
/// **How it is told.** Envelopes of kind `group`, each naming the group (`g`):
/// - `state`: the whole group as it now is (`s`), from an admin, with a count that goes up by one each change. It
///   is how a group is joined (sent by a friend who is its admin), renamed, and how members are added and taken out
///   and admins made. A phone takes a state for a group it has only from someone who is an admin in the state it
///   holds, and only one with a higher count.
/// - `text`: words (`t`), from a member, to each of the others.
/// - `leave`: from a member who is going.
///
/// Two members need not be friends: each has the other's key from the state, and the phone makes their pair's key
/// from it (android Groups.peers), so the routes reach them.
///
/// With no route that costs nothing up, nothing is sent ([sendText] says so): a group has no text to fall back to.
class Groups extends ChangeNotifier {
  Groups(this._port);

  static Groups? _instance;
  static Groups get instance => _instance ??= Groups(_AppPort());

  /// A stand-in for the app's own, for a test of a screen; null puts the app's own back.
  @visibleForTesting
  static set instance(Groups? g) => _instance = g;

  final GroupsPort _port;
  final Map<String, Group> _by = {};
  StreamSubscription<Received>? _sub;
  bool _started = false;

  /// The most members a group can have: what one change of state can tell in a packet with room to spare.
  static const most = 50;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = _port.received.listen(_received);
    await refresh();
  }

  Future<void> shutdown() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
    _by.clear();
  }

  Future<void> refresh() async {
    try {
      final all = await _port.groups();
      _by
        ..clear()
        ..addEntries(all.map((g) => MapEntry(g.id, g)));
    } catch (_) {}
    notifyListeners();
  }

  // --- what the screens ask -------------------------------------------------------------------------------------------

  List<Group> get all => _by.values.toList();
  Group? of(String id) => _by[id];
  Group? ofThread(int thread) => _by.values.where((g) => g.thread == thread).firstOrNull;

  /// Whether what is written in a group can go now.
  bool get online => _port.internet;

  // --- making and changing --------------------------------------------------------------------------------------------

  /// Makes a group called [name] out of friends at [addresses]. This phone is its admin.
  Future<Group> create(String name, List<String> addresses) async {
    if (addresses.isEmpty) throw StateError('A group needs someone in it');
    if (addresses.length + 1 > most) throw StateError('A group can have $most people');
    final id = NetCrypto.hex(NetCrypto.randomBytes(16));
    final state = await _port.draft(id, name.trim(), addresses);
    final group = await _keep(state);
    await _port.note(id, name.trim().isEmpty ? 'You made the group' : 'You made the group "${name.trim()}"');
    await _tell(group, group.others.map((m) => m.id));
    return group;
  }

  Future<Group> _keep(Map<String, dynamic> state) async {
    final group = await _port.save(state);
    _by[group.id] = group;
    notifyListeners();
    return group;
  }

  /// Tells [to] the group as it now is.
  Future<void> _tell(Group group, Iterable<String> to) async {
    final wire = group.state()..remove('id');
    await Future.wait([
      for (final id in to.toSet())
        if (_port.peer(id) case final peer?)
          _port.send(peer, Envelope(kind: 'group', body: {'g': group.id, 'do': 'state', 's': wire})).then((d) {
            if (d.sent && !d.acked && d.handed == Handed.held) _port.wake(peer);
          }).catchError((_) {}),
    ]);
  }

  Group _mine(String id) {
    final g = _by[id];
    if (g == null || g.gone) throw StateError('Not in that group');
    return g;
  }

  Group _asAdmin(String id) {
    final g = _mine(id);
    if (!g.amAdmin) throw StateError('Only an admin of the group can change it');
    return g;
  }

  /// Names the group for everyone in it.
  Future<void> rename(String id, String name) async {
    final g = _asAdmin(id);
    final clean = name.trim();
    if (clean == g.name) return;
    final next = await _keep(g.state(name: clean, v: g.v + 1));
    await _port.note(id, clean.isEmpty ? 'You removed the group\'s name' : 'You named the group "$clean"');
    await _tell(next, next.others.map((m) => m.id));
  }

  /// Adds a friend at [address] to the group.
  Future<void> add(String id, String address) async {
    final g = _asAdmin(id);
    if (g.members.length >= most) throw StateError('A group can have $most people');
    final m = await _port.member(address);
    if (g.member(m['i'] as String) != null) return;
    final members = [...(g.state()['members'] as List).cast<Map<String, dynamic>>(), m];
    final next = await _keep(g.state(members: members, v: g.v + 1));
    await _port.note(id, 'You added ${next.member(m['i'] as String)?.label ?? address}');
    await _tell(next, next.others.map((x) => x.id));
  }

  /// Takes a member out of the group.
  Future<void> remove(String id, String member) async {
    final g = _asAdmin(id);
    final gone = g.member(member);
    if (gone == null || gone.me) return;
    final members = (g.state()['members'] as List).cast<Map<String, dynamic>>().where((m) => m['i'] != member).toList();
    final admins = (g.state()['admins'] as List).cast<String>().where((a) => a != member).toList();
    final next = await _keep(g.state(members: members, admins: admins, v: g.v + 1));
    await _port.note(id, 'You removed ${gone.label}');
    // The one taken out is told too: it is how their phone learns of it.
    await _tell(next, [...next.others.map((x) => x.id), member]);
  }

  /// Makes a member an admin, or no longer one.
  Future<void> setAdmin(String id, String member, bool admin) async {
    final g = _asAdmin(id);
    final who = g.member(member);
    if (who == null || who.me || who.admin == admin) return;
    final before = (g.state()['admins'] as List).cast<String>();
    final next = await _keep(g.state(admins: admin ? [...before, member] : before.where((a) => a != member).toList(), v: g.v + 1));
    await _port.note(id, admin ? 'You made ${who.label} an admin' : '${who.label} is no longer an admin');
    await _tell(next, next.others.map((x) => x.id));
  }

  /// Leaves the group. Its conversation is kept.
  Future<void> leave(String id) async {
    final g = _mine(id);
    await Future.wait([
      for (final m in g.others)
        if (_port.peer(m.id) case final peer?) _port.send(peer, Envelope(kind: 'group', body: {'g': id, 'do': 'leave'})).catchError((_) => const Delivery('')),
    ]);
    await _keep(g.state(gone: true));
    await _port.note(id, 'You left the group');
  }

  // --- what goes ------------------------------------------------------------------------------------------------------

  /// Sends [words] to a group. False, with nothing kept, where this phone is not in it or no route that costs
  /// nothing is up: the caller says so. True once they are kept in its conversation: sent where a route took them
  /// for at least one member (or there is nobody else in it), failed where none did.
  Future<bool> sendText(String id, String words) async {
    final g = _by[id];
    if (!_started || g == null || g.gone || !_port.internet) return false;
    final row = await _port.storeOut(id, words);
    var took = g.others.isEmpty;
    await Future.wait([
      for (final m in g.others)
        if (_port.peer(m.id) case final peer?)
          _port.send(peer, Envelope(kind: 'group', body: {'g': id, 'do': 'text', 't': words})).then((d) {
            if (d.sent) took = true;
            if (d.sent && !d.acked && d.handed == Handed.held) _port.wake(peer);
          }).catchError((_) {}),
    ]);
    await _port.rowState(row, took ? 'sent' : 'failed');
    return true;
  }

  // --- what comes -----------------------------------------------------------------------------------------------------

  Future<void> _received(Received r) async {
    if (r.envelope.kind != 'group' || !r.sealed) return;
    final id = r.envelope.body['g'];
    if (id is! String) return;
    try {
      switch (r.envelope.body['do']) {
        case 'state':
          await _state(id, r);
        case 'text':
          await _text(id, r);
        case 'leave':
          await _left(id, r.peer.id);
      }
    } catch (_) {}
  }

  Future<void> _text(String id, Received r) async {
    final g = _by[id];
    final words = r.envelope.body['t'];
    if (g == null || g.gone || words is! String || words.isEmpty || g.member(r.peer.id) == null) return;
    await _port.storeIn(id, r.peer.id, words, r.envelope.at);
  }

  Future<void> _left(String id, String who) async {
    final g = _by[id];
    final gone = g?.member(who);
    if (g == null || g.gone || gone == null) return;
    final members = (g.state()['members'] as List).cast<Map<String, dynamic>>().where((m) => m['i'] != who).toList();
    var admins = (g.state()['admins'] as List).cast<String>().where((a) => a != who).toList();
    // The last admin went: the member whose name sorts first is one now, which every phone works out alike.
    if (admins.isEmpty && members.isNotEmpty) admins = [(members.map((m) => m['i'] as String).toList()..sort()).first];
    await _keep(g.state(members: members, admins: admins));
    await _port.note(id, '${gone.label} left');
  }

  Future<void> _state(String id, Received r) async {
    final s = r.envelope.body['s'];
    final me = _port.me;
    if (s is! Map || me == null || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return;
    final from = r.peer.id;
    final members = [
      for (final m in (s['members'] as List? ?? const []))
        if (m is Map && m['i'] is String && m['k'] is String) {'i': m['i'] as String, 'k': m['k'] as String, 'a': (m['a'] as String?) ?? ''},
    ];
    final admins = [for (final a in (s['admins'] as List? ?? const [])) if (a is String) a];
    final v = (s['v'] as num?)?.toInt() ?? 1;
    if (members.isEmpty || members.length > most || !admins.contains(from) || !members.any((m) => m['i'] == from)) return;
    final mine = _by[id];
    final inIt = members.any((m) => m['i'] == me);
    if (mine == null || mine.gone) {
      // Joined, or joined again, only at the asking of a friend who is an admin of it.
      if (!inIt || !_port.isFriend(r.peer.address)) return;
    } else {
      // Changed only by someone who is an admin in the group as this phone holds it, and only forward.
      if (!(mine.member(from)?.admin ?? false) || v <= mine.v) return;
    }
    // Who sent it knows their own number least: this phone knows them by it.
    for (final m in members) {
      if (m['i'] == from && (m['a'] as String).isEmpty) m['a'] = r.peer.address ?? '';
    }
    final name = ((s['name'] as String?) ?? '').trim();
    final had = mine != null && !mine.gone;
    if (had && !inIt) {
      // Taken out: the group is kept as it was, marked as left.
      await _keep(mine.state(gone: true, v: v));
      await _port.note(id, '${mine.member(from)?.label ?? 'An admin'} removed you');
      return;
    }
    final next = await _keep({'id': id, 'name': name, 'v': v, 'members': members, 'admins': admins});
    final who = next.member(from)?.label ?? 'Someone';
    if (!had) {
      await _port.note(id, name.isEmpty ? '$who added you to a group' : '$who added you to "$name"');
      return;
    }
    if (name != mine.name) await _port.note(id, name.isEmpty ? '$who removed the group\'s name' : '$who named the group "$name"');
    for (final m in next.members.where((m) => mine.member(m.id) == null)) {
      await _port.note(id, '$who added ${m.label}');
    }
    for (final m in mine.members.where((m) => next.member(m.id) == null)) {
      await _port.note(id, '$who removed ${m.label}');
    }
    for (final m in next.members) {
      final before = mine.member(m.id);
      if (before != null && before.admin != m.admin) await _port.note(id, m.admin ? '$who made ${m.label} an admin' : '${m.label} is no longer an admin');
    }
  }
}

/// The app's own: the routes as the app holds them and the phone.
class _AppPort implements GroupsPort {
  _AppPort() {
    Net.instance.listen(_in.add);
  }

  final _in = StreamController<Received>.broadcast();

  @override
  String? get me => Net.instance.id;
  @override
  Peer? peer(String id) => Net.instance.byId(id);
  @override
  bool get internet => Friends.instance.online;

  @override
  Future<Delivery> send(Peer peer, Envelope envelope) {
    final board = Net.instance.board;
    if (board == null) return Future.value(Delivery(envelope.id, tried: const ['the routes are not set up']));
    return board.send(peer, envelope);
  }

  @override
  Stream<Received> get received => _in.stream;
  @override
  bool isFriend(String? address) => address != null && Friends.instance.isFriend(address);
  @override
  void wake(Peer peer) => Friends.instance.wake(peer);

  @override
  Future<List<Group>> groups() async => [for (final m in await Sms.instance.groups()) Group.from(m)];
  @override
  Future<Map<String, dynamic>> draft(String id, String name, List<String> addresses) async => (jsonDecode(await Sms.instance.groupDraft(id, name, addresses)) as Map).cast<String, dynamic>();
  @override
  Future<Map<String, dynamic>> member(String address) async => (jsonDecode(await Sms.instance.groupMember(address)) as Map).cast<String, dynamic>();

  @override
  Future<Group> save(Map<String, dynamic> state) async {
    final group = Group.from(await Sms.instance.groupSave(jsonEncode(state)));
    // Its members are people the routes reach from now on: read before anything is sent to one.
    await Net.instance.refresh();
    return group;
  }

  @override
  Future<int> storeOut(String id, String words) => Sms.instance.groupTextOut(id, words);
  @override
  Future<void> rowState(int row, String state) => Sms.instance.groupTextState(row, state);
  @override
  Future<void> storeIn(String id, String from, String words, int at) => Sms.instance.groupTextIn(id, from, words, at);
  @override
  Future<void> note(String id, String words) => Sms.instance.groupNote(id, words);
}
