import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../net/carrier.dart';
import '../net/hub_link.dart';
import '../net/net.dart';
import '../net/packet.dart';
import '../net/switchboard.dart';
import '../sms.dart';
import '../sounds.dart';

/// What [Friends] stands on: the app's routes (lib/net) and the phone. The app's own is [_AppPort]; a test gives two
/// of its own and lets what one sends reach the other.
abstract class FriendsPort {
  /// The install encryption is on with at [address], or null.
  Peer? peer(String address);

  /// Whether a route that costs nothing is up now: the relay server's, later the local network's; the direct route's
  /// only while a link to someone's device is open.
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
  Future<int> storeOut(String address, String words, {int? at});

  /// Sends [envelope] to this account's other devices (the same identity, here under other connections): sealed with
  /// the account's own key, so only they open it. A delivery with nothing sent where there is no account here
  /// (GMFB-21).
  Future<Delivery> sendMine(Envelope envelope);

  /// Whether [peer] is this account's own other devices: what [sendMine] reaches, and what it comes from.
  bool isMine(Peer peer);
  Future<void> rowState(int id, String state);
  Future<void> dropRow(int id);
  Future<void> storeIn(String address, String words, int at);

  /// Tells when the people or the routes change.
  Listenable get changed;

  /// Whether a relay server answers where the app would look for one. Asked before anyone is a friend, when the
  /// routes have had nobody to dial for.
  Future<bool> probe();

  /// Whether what was last sent to [address] waits on this app's relay for theirs to be reached (it said so: `waiting`
  /// in its answer): what is unanswered for them is sent again only now and then meanwhile, since every copy would
  /// wait beside the first (found in the review, 2026-11-23).
  bool waitingAtRelay(String address);
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

  /// What went out and has had no answer yet, by its envelope's id: sent again until the friend's app says it has
  /// it ([_resend]). Kept with the app's choices (`friends_out`), so an app closed meanwhile goes on after.
  final Map<String, _Out> _out = {};

  /// The ids of what friends wrote that is kept already (`friends_in`, the newest [keepSeen]): what is sent again
  /// because an answer was lost is not kept twice.
  final List<String> _seen = [];
  Timer? _again;

  /// How long something unanswered is sent again for before it is said to have failed.
  static const giveUpAfter = Duration(days: 3);
  static const keepSeen = 500;

  /// When something unanswered is next sent: twenty seconds after, then twice as long each time, five minutes at most.
  static Duration resendAfter(int tries) => Duration(seconds: (20 * (1 << (tries - 1).clamp(0, 10))).clamp(20, 300));

  /// How long between copies while this app's relay says what was sent waits there for the friend's relay.
  static const waitingResendAfter = Duration(hours: 1);

  /// Why the last words to a friend weren't taken by any route, as the routes said it (their relay refused them, or
  /// can't be reached from this app's): shown in the conversation in place of a reason of its own. Null where nothing
  /// was refused.
  String? lastRefusal;
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
    _loadOut();
    _watchOut();
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
    _again?.cancel();
    if (_started) _port.changed.removeListener(_changed);
    _started = false;
    _by.clear();
    _rows.clear();
    _woke.clear();
    _out.clear();
    _seen.clear();
  }

  void _changed() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 120), () async {
      await refresh();
      // A route that has just come up: what is waiting for an answer goes now, not at its next turn.
      if (_port.internet) _resend(all: true);
    });
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
    // A copy from another device of this account (GMFB-21).
    if (r.envelope.kind == copyKind && r.sealed && _port.isMine(r.peer)) return _mine(r.envelope);
    final address = r.peer.address;
    if (address == null || !r.sealed) return;
    final kind = r.envelope.kind;
    if (kind != 'friend' && kind != 'text') return;
    // Only from someone encryption is on with. The routes also reach the members of a group this phone is in
    // (groups.dart), who are not for that people it has exchanged keys with.
    if (!(of(address)?.on ?? false)) {
      await refresh();
      if (!(of(address)?.on ?? false)) return;
    }
    switch (kind) {
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
          if (mine != 'invited') Sounds.instance.play(UiSound.friendRequest);
          await _set(address, 'invited');
        }
      case 'yes':
        if (mine == 'want' || mine == 'asked' || mine == 'invited') {
          if (mine != 'invited') Sounds.instance.play(UiSound.friendAccepted);
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
    // Sent again because the answer to it was lost: it is here already.
    if (_seen.contains(e.id)) return;
    _seen.add(e.id);
    if (_seen.length > keepSeen) _seen.removeRange(0, _seen.length - keepSeen);
    _app?.set('friends_in', _seen.join(','));
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
    // And for this account's other devices: one closed when it came, or whose copy the relay gave to another.
    unawaited(_copy(address, e.id, words, e.at, out: false));
  }

  // --- this account's other devices -------------------------------------------------------------------------------------

  /// What a copy of a conversation with a friend by username is sent as, to this account's other devices (GMFB-21,
  /// Matt, Windows 0.12.5: "I sent a DM on my phone and it didn't sync the chat history across my mac and PC"). Each
  /// device kept only what it sent and what reached it: the relay hands a friend's message to the devices that are
  /// connected, and one kept for them to whichever comes first, and nothing that one device sent reached the others.
  ///
  /// So every message to or from a friend by username is sent on to the account's own name, sealed with the account's
  /// key; the relay gives it to every other device of the account that is connected and keeps it for those that are
  /// not. A device that takes a copy it hasn't seen keeps it and passes it on once, so one that was closed hears of it
  /// from whichever device got the copy the relay kept. The message's own name tells copies of one message apart.
  static const copyKind = 'mine';

  /// Sends a message with [address] (to them where [out], from them otherwise) to this account's other devices. Only
  /// friends by username: a phone-number friend's messages are the phone's, and its computer shows the phone's.
  Future<void> _copy(String address, String id, String words, int at, {required bool out}) async {
    if (!address.startsWith('@')) return;
    try {
      await _port.sendMine(Envelope(kind: copyKind, body: {'a': address, 't': words, 'i': id, 'at': at, 'o': out}));
    } catch (_) {}
  }

  /// A copy from another device of this account: kept with the conversation, once, and passed on.
  Future<void> _mine(Envelope e) async {
    final b = e.body;
    final address = b['a'], words = b['t'], id = b['i'], at = b['at'];
    if (address is! String || !address.startsWith('@') || words is! String || words.isEmpty || id is! String || at is! num) return;
    if (_seen.contains(id)) return;
    _seen.add(id);
    if (_seen.length > keepSeen) _seen.removeRange(0, _seen.length - keepSeen);
    _app?.set('friends_in', _seen.join(','));
    final out = b['o'] == true;
    if (out) {
      final row = await _port.storeOut(address, words, at: at.toInt());
      await _port.rowState(row, 'sent');
    } else {
      await _port.storeIn(address, words, at.toInt());
    }
    unawaited(_copy(address, id, words, at.toInt(), out: out));
  }

  void _acked(String id) {
    final row = _rows.remove(id) ?? _out[id]?.row;
    if (_out.remove(id) != null) _saveOut();
    if (row != null) _port.rowState(row, 'delivered').catchError((_) {});
  }

  void _loadOut() {
    _out.clear();
    _seen
      ..clear()
      ..addAll((_app?.choice('friends_in', '') ?? '').split(',').where((x) => x.isNotEmpty));
    try {
      for (final j in jsonDecode(_app?.choice('friends_out', '[]') ?? '[]') as List) {
        final o = _Out.fromJson(j as Map);
        if (o != null) _out[o.id] = o;
      }
    } catch (_) {}
  }

  void _saveOut() {
    _app?.set('friends_out', jsonEncode([for (final o in _out.values) o.toJson()]));
    _watchOut();
  }

  /// Looked at every ten seconds while anything waits for an answer, what is due going again (and at once whenever
  /// the routes change, [_changed]); nothing runs while nothing waits.
  void _watchOut() {
    if (_out.isEmpty) {
      _again?.cancel();
      _again = null;
    } else {
      _again ??= Timer.periodic(const Duration(seconds: 10), (_) => _resend());
    }
  }

  /// Sends again what is due ([all]: everything waiting), with the id it first went with, so the friend's app keeps
  /// it once and answers. What has waited [giveUpAfter] is said to have failed.
  Future<void> _resend({bool all = false}) async {
    if (!_started || _out.isEmpty || !_port.internet) return;
    final now = DateTime.now();
    var changed = false;
    for (final o in _out.values.toList()) {
      if (now.difference(o.first) > giveUpAfter) {
        _out.remove(o.id);
        changed = true;
        unawaited(_port.rowState(o.row, 'failed').catchError((_) {}));
        continue;
      }
      if (!all && now.isBefore(o.next)) continue;
      final peer = _port.peer(o.address);
      if (peer == null) continue;
      o.tries++;
      // Waiting on this app's relay for theirs: an hour between copies, not minutes; the one that waits goes when it can.
      o.next = now.add(_port.waitingAtRelay(o.address) ? waitingResendAfter : resendAfter(o.tries));
      changed = true;
      try {
        final d = await _port.send(peer, Envelope(id: o.id, kind: 'text', body: {'t': o.words}, at: o.first.millisecondsSinceEpoch));
        if (d.acked) _acked(o.id);
      } catch (_) {}
    }
    if (changed) _saveOut();
  }

  /// What a route said when it refused a packet (`hub: their relay can't be reached from yours`), without the route's
  /// name; null where none said anything but that it was down.
  static String? _refusalIn(List<String> tried) {
    for (final t in tried) {
      final colon = t.indexOf(': ');
      if (colon <= 0) continue;
      final why = t.substring(colon + 2);
      if (why.contains('relay') && !why.contains('could not be reached') && !why.contains('not connected')) return why;
    }
    return null;
  }

  /// When what went out as [id] is next sent again, for a test; null where it is not waiting for an answer.
  @visibleForTesting
  DateTime? nextResendOf(String id) => _out[id]?.next;

  /// What is waiting for an answer, for a test.
  @visibleForTesting
  int get unanswered => _out.length;

  // --- what goes ------------------------------------------------------------------------------------------------------

  /// Sends [words] to a friend by the routes. True when a route took them: they are kept with the conversation and
  /// nothing more is to be done. False when [address] is not a friend or no route that costs nothing is up: the
  /// caller sends them as a text.
  Future<bool> sendText(String address, String words) async {
    lastRefusal = null;
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
      // A route that said why (their relay, or this app's, refused it) is what the conversation shows.
      lastRefusal = _refusalIn(d.tried);
      await _port.dropRow(row);
      return false;
    }
    if (d.acked) {
      await _port.rowState(row, 'delivered');
      _seen.add(envelope.id);
      unawaited(_copy(address, envelope.id, words, envelope.at, out: true));
      return true;
    }
    await _port.rowState(row, 'sent');
    _rows[envelope.id] = row;
    _seen.add(envelope.id);
    unawaited(_copy(address, envelope.id, words, envelope.at, out: true));
    // Handed on but not yet answered: it may have gone down a connection that had just died, so it goes again until
    // the friend's app says it has it.
    final first = DateTime.fromMillisecondsSinceEpoch(envelope.at);
    _out[envelope.id] = _Out(id: envelope.id, address: address, words: words, row: row, first: first, next: DateTime.now().add(resendAfter(1)));
    _saveOut();
    if (d.handed == Handed.held) _wake(peer);
    return true;
  }

  /// Whether a route that costs nothing is up now, for groups of friends too (groups.dart).
  bool get online => _port.internet;

  /// The wake, for a member of a group the relay server is keeping something for (groups.dart).
  void wake(Peer peer) => _wake(peer);

  /// One data text, with nothing in it and in the clear, to a friend the relay server is keeping something for:
  /// their phone says a message is waiting (android Friends.woken). It is a text on this phone's plan, so it goes
  /// at most every [wakeEvery] a person.
  void _wake(Peer peer) {
    // A friend by username has no number to text (lib/standalone): the relay server keeps it until they come.
    if ((peer.address ?? '').startsWith('@')) return;
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

  /// A route of live links (the direct route) counts only while it reaches someone: a link to a friend's device open
  /// now. Up and ready to dial is not reaching anyone, and a text then waited five seconds on it before going as SMS
  /// (second review, S5).
  @override
  bool get internet {
    _follow();
    final board = Net.instance.board;
    if (board == null || !Net.instance.on) return false;
    return board.carriers.any((c) => !c.traits.metered && c.state.value == CarrierState.up && (c is! LiveLinks || (c as LiveLinks).linkedToSomeone));
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
  Future<int> storeOut(String address, String words, {int? at}) => Sms.instance.netTextOut(address, words, at: at);

  @override
  Future<Delivery> sendMine(Envelope envelope) async {
    final board = Net.instance.board;
    final me = await Net.instance.mine();
    if (board == null || me == null) return Delivery(envelope.id, tried: const ['no account here to send to']);
    // By the relay, which keeps it for the devices that are away; and straight to one that is linked, or to all of
    // them where the relay can't be reached (the direct route, lib/net/p2p).
    return board.send(me, envelope, only: const {'hub', 'p2p'});
  }

  @override
  bool isMine(Peer peer) => peer.id == Net.instance.id && peer.key != null;

  @override
  Future<void> rowState(int id, String state) => Sms.instance.netTextState(id, state);

  @override
  Future<void> dropRow(int id) => Sms.instance.netTextDrop(id);

  @override
  Future<void> storeIn(String address, String words, int at) => Sms.instance.netTextIn(address, words, at);

  @override
  Listenable get changed => Net.instance;

  @override
  bool waitingAtRelay(String address) {
    final peer = Net.instance.byAddress(address);
    return peer != null && (Net.instance.hub?.waitingFor.contains(peer.id) ?? false);
  }

  @override
  Future<bool> probe() async {
    HubLink? socket;
    try {
      socket = await dialHub(Net.instance.hubUrl).timeout(const Duration(seconds: 5));
      // A hub says hello first (relay/lib/hub.dart).
      final first = await socket.said.first.timeout(const Duration(seconds: 5));
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

/// Something sent to a friend and not answered yet ([Friends._resend]).
class _Out {
  _Out({required this.id, required this.address, required this.words, required this.row, required this.first, required this.next, this.tries = 1});
  final String id;
  final String address;
  final String words;
  final int row;
  final DateTime first;
  DateTime next;
  int tries;

  Map<String, Object> toJson() => {'i': id, 'a': address, 'w': words, 'r': row, 'f': first.millisecondsSinceEpoch, 'n': next.millisecondsSinceEpoch, 't': tries};

  static _Out? fromJson(Map j) {
    final id = j['i'], address = j['a'], words = j['w'], row = j['r'], first = j['f'], next = j['n'];
    if (id is! String || address is! String || words is! String || row is! num || first is! num || next is! num) return null;
    return _Out(id: id, address: address, words: words, row: row.toInt(), first: DateTime.fromMillisecondsSinceEpoch(first.toInt()), next: DateTime.fromMillisecondsSinceEpoch(next.toInt()), tries: (j['t'] as num?)?.toInt() ?? 1);
  }
}
