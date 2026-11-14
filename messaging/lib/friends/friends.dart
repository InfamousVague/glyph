import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../net/carrier.dart';
import '../net/net.dart';
import '../net/packet.dart';
import '../net/switchboard.dart';
import '../sms.dart';

/// What [Friends] stands on: the app's routes (lib/net) and the phone. The app's own is [_AppPort]; a test gives two
/// of its own and lets what one sends reach the other.
abstract class FriendsPort {
  /// The install encryption is on with at [address], or null.
  Peer? peer(String address);

  /// Whether a route that costs nothing is up now: the relay server's, later the local network's or a peer's.
  bool get internet;

  Future<Delivery> send(Peer peer, Envelope envelope, {bool metered = false, bool sealed = true, Set<String>? only});

  /// What the routes bring, and the name of each thing sent as the other install says it has it, however late.
  Stream<Received> get received;
  Stream<String> get acked;

  /// Where encryption and friendship stand with everyone something has been exchanged with.
  Future<List<E2eState>> states();
  Future<void> setFriend(String address, String state);

  /// Sends this phone's key to [address] by text: what turns encryption on, or asks for it.
  Future<void> offerKeys(String address);

  /// A friend's words kept with the phone's messages (android Friends.kt): going, what became of them, taken back,
  /// and come.
  Future<int> storeOut(String address, String words);
  Future<void> rowState(int id, String state);
  Future<void> dropRow(int id);
  Future<void> storeIn(String address, String words, int at);

  /// Tells when the people or the routes change.
  Listenable get changed;

  /// Whether a relay server answers where the app would look for one. Asked before anyone is a friend, when the
  /// routes have had nobody to dial for.
  Future<bool> probe();
}

/// Friends (Matt, 2026-11-14: "Add a friend system that allows users to talk without using SMS or MMS but still
/// validate accounts by telephone numbers for now. If both users chatting are on ghost messenger show an 'add
/// friend' button").
///
/// **Who can be one.** Someone encryption is on with: the two phones exchanged keys by text, which is what proved
/// each number to the other. Add friend on someone who has the app and has not exchanged keys yet sends this
/// phone's key first ('want'), and asks as soon as theirs is here.
///
/// **Becoming friends** is said over the routes (lib/net), sealed, as an envelope of kind `friend`: `ask`, then
/// `yes` from the other, or `no`; `end` when one of them stops. Two who ask each other are friends at once. Where
/// the two stand is kept on the phone's encryption record for them (android E2e.friend): '', 'want', 'asked',
/// 'invited', 'yes'.
///
/// **What friends write** goes as an envelope of kind `text` by a route that costs nothing, and is kept with the
/// phone's own messages on both phones, so the conversation, the list, search and a paired computer show it as
/// they show a text, marked as having come by the internet. Where no such route is up it is not sent this way at
/// all ([sendText] says so) and goes as the encrypted text it would have been. Where the relay server is keeping it
/// for a friend who is away, one data text with nothing in it follows (`wake`, at most every ten minutes a
/// person), so a closed app's phone can say a message is waiting.
///
/// Nothing is offered until a relay server is known to answer ([available]): a build with none to reach offers
/// what it did before.
class Friends extends ChangeNotifier {
  Friends(this._port);

  static Friends? _instance;
  static Friends get instance => _instance ??= Friends(_AppPort());

  /// A stand-in for the app's own, for a test of a screen; null puts the app's own back.
  @visibleForTesting
  static set instance(Friends? f) => _instance = f;

  final FriendsPort _port;
  AppState? _app;
  final Map<String, E2eState> _by = {};
  final Map<String, int> _rows = {};
  final Map<String, DateTime> _woke = {};
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _soon;
  bool _started = false;
  bool? _answers;
  DateTime? _asked;

  /// How long before a friend who is away is sent another wake.
  static const wakeEvery = Duration(minutes: 10);

  /// A number as two phones agree on it whatever each wrote before it: its last ten digits.
  static String digits(String address) {
    final d = address.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 7 ? (d.length > 10 ? d.substring(d.length - 10) : d) : address.trim().toLowerCase();
  }

  /// Starts listening to the routes. Asked for once, as the app opens, after the routes are set up.
  Future<void> start([AppState? app]) async {
    if (_started) return;
    _started = true;
    _app = app;
    _subs.add(_port.received.listen(_received));
    _subs.add(_port.acked.listen(_acked));
    _port.changed.addListener(_changed);
    await refresh();
    // A request that never got an answer is said again, by a route that costs nothing: either was lost.
    for (final s in _by.values.where((s) => s.on && s.friend == 'asked')) {
      _say(s.address, 'ask');
    }
  }

  Future<void> shutdown() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _soon?.cancel();
    if (_started) _port.changed.removeListener(_changed);
    _started = false;
    _by.clear();
    _rows.clear();
    _woke.clear();
  }

  void _changed() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 120), refresh);
  }

  /// Reads where everyone stands again, and asks those it was waiting to ask now that their key is here.
  Future<void> refresh() async {
    List<E2eState> all;
    try {
      all = await _port.states();
    } catch (_) {
      return;
    }
    _by
      ..clear()
      ..addEntries(all.map((s) => MapEntry(digits(s.address), s)));
    for (final s in all.where((s) => s.on && s.friend == 'want')) {
      await _ask(s.address);
    }
    if (_port.internet && _answers != true) {
      _answers = true;
      _app?.setFlag('friends_seen', true);
    }
    notifyListeners();
  }

  // --- what the screens ask -------------------------------------------------------------------------------------------

  /// Whether friends can be offered at all: a relay server has answered this phone, now or before.
  bool get available => _port.internet || _answers == true || (_app?.flag('friends_seen', fallback: false) ?? false);

  /// Looks whether a relay server answers, where that is not known: a conversation with someone who has the app
  /// asks as it opens. At most every ten minutes; listeners are told when the answer is yes.
  Future<void> look() async {
    if (available || !(_app?.flag('net_on') ?? true)) return;
    final last = _asked;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) return;
    _asked = DateTime.now();
    bool yes;
    try {
      yes = await _port.probe();
    } catch (_) {
      yes = false;
    }
    if (!yes) return;
    _answers = true;
    _app?.setFlag('friends_seen', true);
    notifyListeners();
  }

  E2eState? of(String address) => _by[digits(address)];
  String stateOf(String address) => of(address)?.friend ?? '';
  bool isFriend(String address) => of(address)?.isFriend ?? false;

  /// Everyone who is a friend.
  List<E2eState> get friends => _by.values.where((s) => s.isFriend).toList();

  /// Whether the conversation with someone who stands at [e] should offer Add friend: both have the app, nothing
  /// has been said about being friends, and friends can be offered.
  bool offers(E2eState e) => available && e.friend.isEmpty && (e.on || e.offerable);

  // --- becoming friends -----------------------------------------------------------------------------------------------

  /// Add friend. With no keys exchanged yet this phone's goes first, by text, and the asking waits for theirs.
  Future<void> add(String address) async {
    final s = of(address);
    if (s == null || !s.on) {
      await _port.offerKeys(address);
      await _port.setFriend(address, 'want');
      await refresh();
      return;
    }
    if (s.friend == 'invited') return accept(address);
    await _ask(address, metered: true);
  }

  Future<void> _ask(String address, {bool metered = false}) async {
    await _set(address, 'asked');
    await _say(address, 'ask', metered: metered);
  }

  /// Yes to someone who asked.
  Future<void> accept(String address) async {
    await _set(address, 'yes');
    await _say(address, 'yes', metered: true);
  }

  /// No to someone who asked.
  Future<void> decline(String address) async {
    await _set(address, '');
    await _say(address, 'no');
  }

  /// Stops being friends, or takes a request back. What is written to them goes as a text again.
  Future<void> remove(String address) async {
    await _set(address, '');
    await _say(address, 'end');
  }

  Future<void> _set(String address, String state) async {
    await _port.setFriend(address, state);
    final s = of(address);
    if (s != null) {
      _by[digits(address)] = E2eState(address: s.address, state: s.state, verified: s.verified, changed: s.changed, safety: s.safety, person: s.person, hasGhost: s.hasGhost, declined: s.declined, plain: s.plain, friend: state);
    }
    notifyListeners();
  }

  /// Says [what] about being friends to [address]. Asking and answering by hand may cost a text where no other
  /// route is up ([metered]); what is said again unasked may not.
  Future<void> _say(String address, String what, {bool metered = false}) async {
    final peer = _port.peer(address);
    if (peer == null) return;
    try {
      await _port.send(peer, Envelope(kind: 'friend', body: {'do': what}), metered: metered);
    } catch (_) {}
  }

  // --- what comes -----------------------------------------------------------------------------------------------------

  Future<void> _received(Received r) async {
    final address = r.peer.address;
    if (address == null || !r.sealed) return;
    switch (r.envelope.kind) {
      case 'friend':
        await _friend(address, r.envelope.body['do']);
      case 'text':
        await _text(address, r.envelope);
    }
  }

  Future<void> _friend(String address, Object? what) async {
    final mine = stateOf(address);
    switch (what) {
      case 'ask':
        if (mine == 'want' || mine == 'asked') {
          // Each asked the other: friends.
          await _set(address, 'yes');
          await _say(address, 'yes');
        } else if (mine == 'yes') {
          await _say(address, 'yes');
        } else {
          await _set(address, 'invited');
        }
      case 'yes':
        if (mine == 'want' || mine == 'asked' || mine == 'invited') {
          await _set(address, 'yes');
        } else if (mine.isEmpty) {
          // They hold this phone to have asked, and it has not (it took the request back, or was reset): theirs
          // stands as a request.
          await _set(address, 'invited');
        }
      case 'no':
        if (mine == 'want' || mine == 'asked') await _set(address, '');
      case 'end':
        if (mine.isNotEmpty) await _set(address, '');
    }
  }

  Future<void> _text(String address, Envelope e) async {
    final words = e.body['t'];
    if (words is! String || words.isEmpty) return;
    final mine = stateOf(address);
    if (mine == 'want' || mine == 'asked') {
      // They write as a friend to someone who asked them: their yes was lost on the way.
      await _set(address, 'yes');
    } else if (mine != 'yes') {
      // Not a friend here: they are told, so what they write goes as a text again. These words are still kept:
      // they came sealed from someone encryption is on with.
      await _say(address, 'end');
    }
    await _port.storeIn(address, words, e.at);
  }

  void _acked(String id) {
    final row = _rows.remove(id);
    if (row != null) _port.rowState(row, 'delivered').catchError((_) {});
  }

  // --- what goes ------------------------------------------------------------------------------------------------------

  /// Sends [words] to a friend by the routes. True when a route took them: they are kept with the conversation and
  /// nothing more is to be done. False when [address] is not a friend or no route that costs nothing is up: the
  /// caller sends them as a text.
  Future<bool> sendText(String address, String words) async {
    if (!_started || !isFriend(address) || !_port.internet) return false;
    final peer = _port.peer(address);
    if (peer == null) return false;
    final row = await _port.storeOut(address, words);
    final envelope = Envelope(kind: 'text', body: {'t': words});
    Delivery d;
    try {
      d = await _port.send(peer, envelope);
    } catch (_) {
      d = Delivery(envelope.id);
    }
    if (!d.sent) {
      await _port.dropRow(row);
      return false;
    }
    if (d.acked) {
      await _port.rowState(row, 'delivered');
      return true;
    }
    await _port.rowState(row, 'sent');
    _rows[envelope.id] = row;
    if (d.handed == Handed.held) _wake(peer);
    return true;
  }

  /// One data text, with nothing in it and in the clear, to a friend the relay server is keeping something for:
  /// their phone says a message is waiting (android Friends.woken). It is a text on this phone's plan, so it goes
  /// at most every [wakeEvery] a person.
  void _wake(Peer peer) {
    final last = _woke[peer.id];
    if (last != null && DateTime.now().difference(last) < wakeEvery) return;
    _woke[peer.id] = DateTime.now();
    _port.send(peer, Envelope(kind: 'wake', ack: false), metered: true, sealed: false, only: {'sms'}).catchError((_) => const Delivery(''));
  }
}

/// The app's own: the routes as the app holds them (lib/net/net.dart) and the phone.
class _AppPort implements FriendsPort {
  _AppPort() {
    Net.instance.listen(_in.add);
  }

  final _in = StreamController<Received>.broadcast();
  final _acks = StreamController<String>.broadcast();
  StreamSubscription<String>? _boardAcks;
  Switchboard? _board;

  /// The switchboard is made as the routes are set up, and again where they are set up again.
  void _follow() {
    final board = Net.instance.board;
    if (identical(board, _board)) return;
    _boardAcks?.cancel();
    _board = board;
    _boardAcks = board?.acked.listen(_acks.add);
  }

  @override
  Peer? peer(String address) => Net.instance.byAddress(address);

  @override
  bool get internet {
    _follow();
    final board = Net.instance.board;
    if (board == null || !Net.instance.on) return false;
    return board.carriers.any((c) => !c.traits.metered && c.state.value == CarrierState.up);
  }

  @override
  Future<Delivery> send(Peer peer, Envelope envelope, {bool metered = false, bool sealed = true, Set<String>? only}) {
    final board = Net.instance.board;
    if (board == null) return Future.value(Delivery(envelope.id, tried: const ['the routes are not set up']));
    return board.send(peer, envelope, metered: metered, sealed: sealed, only: only);
  }

  @override
  Stream<Received> get received => _in.stream;

  @override
  Stream<String> get acked {
    _follow();
    return _acks.stream;
  }

  @override
  Future<List<E2eState>> states() => Sms.instance.e2eList();

  @override
  Future<void> setFriend(String address, String state) => Sms.instance.friendSet(address, state);

  @override
  Future<void> offerKeys(String address) => Sms.instance.e2eOffer(address);

  @override
  Future<int> storeOut(String address, String words) => Sms.instance.netTextOut(address, words);

  @override
  Future<void> rowState(int id, String state) => Sms.instance.netTextState(id, state);

  @override
  Future<void> dropRow(int id) => Sms.instance.netTextDrop(id);

  @override
  Future<void> storeIn(String address, String words, int at) => Sms.instance.netTextIn(address, words, at);

  @override
  Listenable get changed => Net.instance;

  @override
  Future<bool> probe() async {
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(Net.instance.hubUrl).timeout(const Duration(seconds: 5));
      // A hub says hello first (relay/lib/hub.dart).
      final first = await socket.first.timeout(const Duration(seconds: 5));
      return first is String && first.contains('"hello"');
    } catch (_) {
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }
}
