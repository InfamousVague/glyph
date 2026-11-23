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
  /// The routes' peer for the install named [id], or null where they don't reach it. Friends asks by the id the record
  /// for an address names ([Friends.idOf]), never by an address: the routes' list can hold someone under an address
  /// that isn't theirs (on Android, a member of a group under whatever its admin wrote).
  Peer? peer(String id);

  /// Whether a route that costs nothing is up now: the relay server's, later the local network's; the direct route's
  /// only while a link to someone's device is open.
  bool get internet;

  Future<Delivery> send(Peer peer, Envelope envelope, {bool metered = false, bool sealed = true, Set<String>? only});

  /// What the routes bring, and the name of each thing sent as the other install says it has it, however late.
  Stream<Received> get received;
  Stream<String> get acked;

  /// Where encryption and friendship stand with everyone something has been exchanged with.
  Future<List<E2eState>> states();

  /// Whether this device keeps the records for numbers and acts on them: the Android phone. Every other device of an
  /// account (a computer paired with the phone, an iPhone or a computer of its own, a browser) carries friends by
  /// username alone, though what is sent to the account reaches it too: the phone's records for numbers, which a paired
  /// computer shows, are the phone's to act on, say nothing there of who an install is ([Friends.whoIs]), and are never
  /// asked again or answered for from there.
  bool get numbers;
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
///
/// **Who someone is** comes from the records that say so, by the name of their key (found in review, 2026-11-23):
/// a number friend is the encryption record for that number, whose key gives an id (android E2e.state); a friend by
/// username is the record their username stands for (UsernameChats.states), by the ids of their installs. What comes
/// is from whoever the record naming the id that sealed it is for ([addressOf]); what goes, goes to the id the record
/// for an address names ([idOf]). The address the routes have for someone is never asked: on Android they reach the
/// members of this phone's groups too, each under whatever address the group's admin wrote, which may be a friend's
/// number or "@friend".
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

  /// Who each install is: the record that names its id, by that record's address ([digits]), as [whoIs] decides.
  Map<String, String> _byId = {};
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
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _soon;
  bool _started = false;
  bool? _answers;
  DateTime? _asked;

  /// How long before a friend who is away is sent another wake.
  static const wakeEvery = Duration(minutes: 10);

  /// A number as two phones agree on it whatever each wrote before it: its last ten digits. A username (`@name`) is
  /// never read as a number, whatever digits it holds: usernames may (Me.goodUsername), and "@ben.5550002222" was read
  /// as Ben's number and stood in for him (found in review, 2026-11-23).
  static String digits(String address) {
    final t = address.trim();
    if (t.startsWith('@')) return t.toLowerCase();
    final d = address.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 7 ? (d.length > 10 ? d.substring(d.length - 10) : d) : t.toLowerCase();
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
    for (final s in _by.values.where((s) => s.on && s.friend == 'asked' && _actsOn(s))) {
      _say(s.address, 'ask');
    }
  }

  /// Whether this device acts on [s]: every record on the phone; elsewhere friends by username alone ([FriendsPort.numbers]).
  bool _actsOn(E2eState s) => _port.numbers || s.address.startsWith('@');

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
    _byId = {};
    _rows.clear();
    _woke.clear();
    _ended.clear();
    _lookedAt = null;
    _looking = null;
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
    // Off the phone, only friends by username say who an install is: what a paired computer's own routes bring is kept
    // with them, as before, never handed to the phone's conversation with the same person's number.
    _byId = whoIs(all.where(_actsOn));
    _failForOthers();
    for (final s in all.where((s) => s.on && s.friend == 'want' && _actsOn(s))) {
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

  /// The install the record for [address] names, while encryption is on with it: who that address is to the routes
  /// (a number's key, or the install a username stands for). Null where there is no such record, or it names no key.
  String? idOf(String address) {
    final s = of(address);
    return s != null && s.on ? s.id : null;
  }

  /// The address of the record that names the install [id] ([idOf] the other way): a number, or `@username`. Null
  /// where no record encryption is on with names it: a member of a group, say, is nobody's by an address an admin wrote.
  String? addressOf(String id) => _whose(id)?.address;

  /// Whether the install [id] is a friend, by the record that names it.
  bool isFriendId(String id) => _whose(id)?.isFriend ?? false;

  /// The record that names the install [id], while encryption is on with it; null for anyone else.
  E2eState? _whose(String id) {
    final key = _byId[id];
    final s = key == null ? null : _by[key];
    // The record kept for that address still names it (the two are read together; this holds them to each other).
    return s != null && s.on && (s.id == id || s.otherIds.contains(id)) ? s : null;
  }

  /// Who each install is, from [all] the records: the address ([digits]) of the record that names its id
  /// ([E2eState.id], and a friend by username's other installs). Where two name the same one (a person's number and
  /// username, both with the key of the one install; one person's two numbers on one phone; or a key someone sent from
  /// a number that isn't theirs), the record encryption is on with stands, then the one being friends has gone furthest
  /// with ([progress]), then a number's; two still alike go to the same one of them every time, the lower address. Never
  /// to nobody: a record's id seals for that key's own holder whatever address it is under, so the worst that can come
  /// of two alike is their words under the other of their numbers. Dropping them (as this did first) lost every word of
  /// someone with two SIMs while their phone was told each had arrived (found in review, 2026-11-23).
  @visibleForTesting
  static Map<String, String> whoIs(Iterable<E2eState> all) {
    int rank(E2eState s) => (s.on ? 16 : 0) + progress(s) * 2 + (s.address.startsWith('@') ? 0 : 1);
    final best = <String, E2eState>{};
    for (final s in all) {
      for (final id in {?s.id, ...s.otherIds}) {
        final had = best[id];
        if (had == null || rank(s) > rank(had) || (rank(s) == rank(had) && digits(s.address).compareTo(digits(had.address)) < 0)) best[id] = s;
      }
    }
    return {for (final e in best.entries) e.key: digits(e.value.address)};
  }

  /// How far being friends has gone with [s], encryption on with them: 3 friends, 2 asked or invited, 1 meant to ask
  /// (`want`), 0 nothing yet, or encryption off.
  @visibleForTesting
  static int progress(E2eState s) => !s.on ? 0 : switch (s.friend) { 'yes' => 3, 'asked' || 'invited' => 2, 'want' => 1, _ => 0 };

  /// Whether the record for [address] names the install [id], encryption on with it: their newest install or another.
  bool _names(String address, String id) {
    final s = of(address);
    return s != null && s.on && (s.id == id || s.otherIds.contains(id));
  }

  /// The routes' peer for whoever the record for [address] names ([idOf]), found by that id alone.
  Peer? _peerFor(String address) {
    final id = idOf(address);
    if (id == null) return null;
    final p = _port.peer(id);
    return p != null && p.id == id ? p : null;
  }

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
    if (s != null) _by[digits(address)] = s.withFriend(state);
    notifyListeners();
  }

  /// Says [what] about being friends to [address]: to the install its record names. Asking and answering by hand may
  /// cost a text where no other route is up ([metered]); what is said again unasked may not.
  Future<void> _say(String address, String what, {bool metered = false}) async {
    final peer = _peerFor(address);
    if (peer == null) return;
    try {
      await _port.send(peer, Envelope(kind: 'friend', body: {'do': what}), metered: metered);
    } catch (_) {}
  }

  // --- what comes -----------------------------------------------------------------------------------------------------

  Future<void> _received(Received r) async {
    // A copy from another device of this account (GMFB-21).
    if (r.envelope.kind == copyKind && r.sealed && _port.isMine(r.peer)) return _mine(r.envelope);
    if (!r.sealed) return;
    final kind = r.envelope.kind;
    if (kind != 'friend' && kind != 'text') return;
    // Who sent it is the install whose key sealed it ([Received.peer]'s id), and who that is to this phone is the
    // record that names that id, encryption on with it: a number's, whose key it is, or a friend by username's. Never
    // the address the routes have for them: they also reach the members of a group this phone is in (groups.dart),
    // each under whatever address the group's admin wrote, which may be a real friend's number or "@friend" (found in
    // review, 2026-11-23). Anyone no such record names is dropped, and told so ([_notAFriend]).
    var who = _whose(r.peer.id);
    if (who == null) {
      await _lookAgain();
      who = _whose(r.peer.id);
      if (who == null) {
        _notAFriend(r);
        return;
      }
    }
    switch (kind) {
      case 'friend':
        await _friend(who.address, r.envelope.body['do']);
      case 'text':
        await _text(who.address, r.envelope);
    }
  }

  /// When the records were last read again for something from an install none of them named, and that reading while it
  /// runs: once in [lookAgainAfter] at most, however many come. Any member of a group can send them, and each read is
  /// the phone's whole list of encryption records (found in review, 2026-11-23).
  DateTime? _lookedAt;
  Future<void>? _looking;
  static const lookAgainAfter = Duration(seconds: 15);

  /// Reads the records again for an install none of them names (a friend whose keys were just exchanged, before the
  /// change has been read), unless that was done a moment ago or is being done now.
  Future<void> _lookAgain() {
    final running = _looking;
    if (running != null) return running;
    final now = DateTime.now(), last = _lookedAt;
    if (last != null && now.difference(last) < lookAgainAfter) return Future.value();
    _lookedAt = now;
    return _looking = refresh().whenComplete(() => _looking = null);
  }

  /// When each install no record names was last answered `end` ([_notAFriend]).
  final Map<String, DateTime> _ended = {};

  /// Words, or an ask or a yes, came sealed from an install none of this phone's records names: a member of a group, or
  /// someone whose record is gone here while theirs still holds this phone a friend. The routes have already answered
  /// that it arrived, so it is answered `end` too, straight to the install that sealed it (by its id, [Received.peer]):
  /// their app stops writing to this phone as a friend's, and their words go as texts again rather than showing
  /// delivered (found in review, 2026-11-23). Only from the phone ([FriendsPort.numbers]): another device of the
  /// account doesn't hold the records for numbers, and would end a friendship that is the phone's. Never for an end or
  /// a no (two phones would answer each other for ever), never to an install some record names whatever it stands at,
  /// and at most every [wakeEvery] an install.
  void _notAFriend(Received r) {
    if (!_port.numbers) return;
    final what = r.envelope.body['do'];
    if (r.envelope.kind == 'friend' && what != 'ask' && what != 'yes') return;
    final id = r.peer.id;
    if (_by.values.any((s) => s.id == id || s.otherIds.contains(id))) return;
    final last = _ended[id];
    if (last != null && DateTime.now().difference(last) < wakeEvery) return;
    _ended[id] = DateTime.now();
    unawaited(_port.send(r.peer, Envelope(kind: 'friend', body: {'do': 'end'})).catchError((_) => Delivery(r.envelope.id)));
  }

  /// What waits for an answer from an install the record for its address no longer names (their key changed, and the
  /// record names the new one, or waits for the person's yes to it): what was sealed for the one it went to can't be read
  /// by another, and is said to have failed now, not three days on (found in review, 2026-11-23).
  void _failForOthers() {
    var changed = false;
    for (final o in _out.values.toList()) {
      final to = o.to, s = of(o.address);
      if (to == null || s == null || s.id == null || s.id == to || s.otherIds.contains(to)) continue;
      _out.remove(o.id);
      changed = true;
      unawaited(_port.rowState(o.row, 'failed').catchError((_) {}));
    }
    if (changed) _saveOut();
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
  /// it once and answers. What has waited [giveUpAfter] is said to have failed. Only ever to the install it first
  /// went to, while a record for that address still names it (a friend by username's other install as well): what was
  /// sealed for one key is never sealed again for another (a key changed since, or someone else listed under their
  /// address).
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
      // Kept by a build from before the install was remembered with it: the one its record names now, from here on.
      final to = o.to ?? idOf(o.address);
      if (to == null || !_names(o.address, to)) continue;
      final peer = _port.peer(to);
      if (peer == null || peer.id != to) continue;
      o.to = to;
      o.tries++;
      o.next = now.add(resendAfter(o.tries));
      changed = true;
      try {
        final d = await _port.send(peer, Envelope(id: o.id, kind: 'text', body: {'t': o.words}, at: o.first.millisecondsSinceEpoch));
        if (d.acked) _acked(o.id);
      } catch (_) {}
    }
    if (changed) _saveOut();
  }

  /// What is waiting for an answer, for a test.
  @visibleForTesting
  int get unanswered => _out.length;

  // --- what goes ------------------------------------------------------------------------------------------------------

  /// Sends [words] to a friend by the routes. True when a route took them: they are kept with the conversation and
  /// nothing more is to be done. False when [address] is not a friend or no route that costs nothing is up: the
  /// caller sends them as a text.
  Future<bool> sendText(String address, String words) async {
    if (!_started || !isFriend(address) || !_port.internet) return false;
    // To the install the friend's record names, by its id: never whoever else the routes hold under that address.
    final peer = _peerFor(address);
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
    _out[envelope.id] = _Out(id: envelope.id, address: address, to: peer.id, words: words, row: row, first: first, next: DateTime.now().add(resendAfter(1)));
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
  ///
  /// Only to the number this phone's own record gives that install: the record encryption is on with at that number,
  /// whose key it is (found in review, 2026-11-23). Someone known only through a group has the number its admin wrote,
  /// and an admin could list made-up members under anyone's numbers for every member's phone to text on its own plan,
  /// telling whoever is at each number this phone's own. They are woken by the members whose records do know them (the
  /// admin who added them does), and have what was written when their app opens. A friend by username has no number to
  /// text (lib/standalone): the relay server keeps it until they come.
  void _wake(Peer peer) {
    final vouched = addressOf(peer.id);
    if (vouched == null || vouched.startsWith('@')) return;
    final last = _woke[peer.id];
    if (last != null && DateTime.now().difference(last) < wakeEvery) return;
    _woke[peer.id] = DateTime.now();
    // To the record's number, whatever address the routes have for them.
    final to = Peer(id: peer.id, key: peer.key, address: vouched, name: peer.name);
    _port.send(to, Envelope(kind: 'wake', ack: false), metered: true, sealed: false, only: {'sms'}).catchError((_) => const Delivery(''));
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
  Peer? peer(String id) => Net.instance.byId(id);

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

  /// The Android phone's alone (Sms.remote: a computer, an iPhone, a browser, paired or not).
  @override
  bool get numbers => !Sms.remote;

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
  _Out({required this.id, required this.address, this.to, required this.words, required this.row, required this.first, required this.next, this.tries = 1});
  final String id;
  final String address;

  /// The install it was sent to, by name: sent again only to that one. Null in what was kept by a build from before.
  String? to;
  final String words;
  final int row;
  final DateTime first;
  DateTime next;
  int tries;

  Map<String, Object> toJson() => {'i': id, 'a': address, 'd': ?to, 'w': words, 'r': row, 'f': first.millisecondsSinceEpoch, 'n': next.millisecondsSinceEpoch, 't': tries};

  static _Out? fromJson(Map j) {
    final id = j['i'], address = j['a'], words = j['w'], row = j['r'], first = j['f'], next = j['n'];
    if (id is! String || address is! String || words is! String || row is! num || first is! num || next is! num) return null;
    return _Out(id: id, address: address, to: j['d'] is String ? j['d'] as String : null, words: words, row: row.toInt(), first: DateTime.fromMillisecondsSinceEpoch(first.toInt()), next: DateTime.fromMillisecondsSinceEpoch(next.toInt()), tries: (j['t'] as num?)?.toInt() ?? 1);
  }
}
