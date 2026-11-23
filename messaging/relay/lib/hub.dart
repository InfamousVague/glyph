import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'accounts.dart';
import 'handles.dart';
import 'invites.dart';
import 'invite_words.dart';
import 'pushes.dart';
import 'turn.dart';
import 'p256.dart';
import 'sha256.dart';

/// The hub: where two people's apps find each other through this server (Matt, 2026-11-14: "implement a full relay
/// system for the app that's replacable and swappable so that for right now we can use our servers to negotiate
/// calls through the app, video chats"). It is one of the app's routes (lib/net/hub_carrier.dart in the app), made
/// to be taken out and a peer-to-peer one put in its place: it holds no account, no name and no number.
///
/// - **Who someone is.** A key pair made on their phone. Their name here is the first 16 bytes of the SHA-256 of
///   the public key, in hex. To connect they sign a number the hub has just made up, so only the holder of the
///   private key connects under that name. One connection per name: a newer one replaces the older.
/// - **A packet to someone** is passed to them if they are connected. If not it is **held** (at most
///   [mailboxFrames] and [mailboxBytes] for one person, [heldBytes] for everyone together, for [holdFor]) and
///   handed over when they next connect. The sender is told which happened. Held packets live in memory: a restart
///   of the hub loses them, and the app's own routes are what a sender falls back on (lib/net/switchboard.dart).
///   No more than [maxConnections] are connected at once.
/// - **Who is here.** A connection may ask to be told when some names come and go (`watch`), and whether each is using
///   the app or has put it away, and when they were last there (Matt, 2026-11-17: "Do the server change in order to get
///   presense sensing working ... for users who have signed up for a username and are part of our own system"). An app
///   says `{"away": true}` as it goes to the background and `{"away": false}` as it comes back; watchers are told
///   `{"away": id, "is": bool, "at": ms}`, a going is `{"went": id, "at": ms}` (when they were last using it), and
///   the answer to `watch` carries `away` (those here but away) and `seen` (when each not here was last there). Kept
///   in memory only, for at most [maxSeen] names: a restart forgets when anyone was last seen.
///   Since GMFB-34 a person may also choose how they are shown (`{"mode": "online" | "busy" | "invisible"}`, said by
///   any of their devices, held while one is here): busy is told as `{"busy": id, "is": bool}` and listed in the
///   answer to `watch` (`busy`); invisible is shown to watchers as gone (a `went`, no `came`, not in `here`, and when
///   they were last seen is not moved on while they are). An app from before passes over `busy` and never says a mode.
/// - **Looking at a room** without joining it (`look`, with its token): told who is in it, now and as that changes. A
///   voice channel's list, showing who is connected before you jump in.
/// - **Rooms** (a voice room, a group): named by 32 hex digits with a token of 64, both made by its members from a
///   key only they hold; the first to name a room sets its token. Whoever holds the token may join and leave at any
///   time, is told who is in it, and what one member sends to the room goes to the others. A room nobody is in is
///   forgotten.
/// - **Read-only rooms** (Matt, 2026-11-20: "read only channels for system messages and admin / moderation
///   announcements"): a circle's read-only space has a room whose name is made from the circle owner's public key
///   ([anchoredName]), joined with that key and what makes the name (`ro` in the join), so the hub can check the room
///   is that owner's and nobody else's. In it only the owner and the admins the owner signed may post: the admin list
///   is the circle's own (its generation signed by the owner, as the app checks it: lib/circles/circle.dart), handed
///   over by any member and kept at its highest generation. Anyone else's packet the hub would keep is refused, and
///   anything else they send goes to the writers alone, so a changed app can't put words in front of the other
///   members. Such rooms are apart from ordinary ones of the same name, so joining without `ro` never reaches one.
///   Reactions ([toRoomReaction]) are the exception: anyone in the room may react, as a packet too small to be a post.
/// - **What it can see:** which names talk to which, when, and how much. Never what: packets are sealed by the apps
///   with keys the hub never has. It logs no addresses.
/// - **What it does not carry:** a call's sound and picture. Those go between the phones directly (or through a
///   media relay); the hub carries only what sets a call up.
class Hub {
  Hub({DateTime Function()? now, this.verbose = false, Random? random, this.heldBytes = 96 << 20, this.maxConnections = 20000, this.handles, this.pushes, this.invites, this.accounts, this.words, this.turn = const TurnConfig(), List<String> helpers = const []})
      : _now = now ?? DateTime.now,
        started = (now ?? DateTime.now)(),
        _random = random ?? Random.secure(),
        helpers = linkHelpers(helpers);

  /// When this hub started, by its own clock. Said with each sign-in (`"since"`, beside its time now, `"now"`): what it
  /// kept for someone lives in memory and goes with a restart, so an app that knows when the relay started knows a
  /// packet it was told was kept before then is gone with it, and is no fault of the relay's (the app's
  /// docs/OPEN_NETWORK.md, section 3). An app from before passes over both.
  final DateTime started;

  /// The link helpers this relay's people use for direct links between their devices (the app's
  /// docs/OPEN_NETWORK.md, section 2): servers that help two devices find each other and carry their sealed traffic
  /// when no straight path can be made. Said to each app as it signs in (`"helpers"` beside `"ok"`), as the call
  /// relay is handed out with a room; from `GHOST_LINK_HELPERS`. With none nothing is said, and an app from before
  /// passes it over either way.
  final List<String> helpers;

  /// The most link helpers named, and the longest address one may have.
  static const maxHelpers = 4;
  static const maxHelper = 200;

  /// [said] as link helpers are named: https addresses of at most [maxHelper] characters, the first [maxHelpers].
  static List<String> linkHelpers(Iterable<String> said) =>
      List.unmodifiable(said.map((h) => h.trim()).where((h) => h.length > 'https://'.length && h.length <= maxHelper && h.startsWith('https://')).take(maxHelpers));

  final bool verbose;

  /// The media relay calls fall back on (turn.dart): a username and password for it go with every room joined.
  final TurnConfig turn;
  final DateTime Function() _now;
  final Random _random;

  /// The handles people linked (handles.dart): what a connection says that starts `{"dir": …}` is its to answer.
  /// None where null, and such a message is then answered that there is none.
  final Handles? handles;

  /// Waking a closed iPhone when something is held for it (pushes.dart); none where null.
  final Pushes? pushes;

  /// Invites waiting for someone not on the app yet, by a hash of their number (invites.dart): the `{"dir": …}`
  /// messages it names ([Invites.dirs]) are its to answer, not [handles]'s. None where null, and they are then
  /// answered that there are none.
  final Invites? invites;

  /// Circles' invite words (invite_words.dart): the `{"dir": …}` messages it names ([InviteWords.dirs]).
  final InviteWords? words;

  /// Ghost accounts (accounts.dart): the `{"dir": "acct-…"}` messages ([Accounts.dirs]) are its to answer. None where
  /// null, and they are then answered that there are none. An app from before accounts never says them.
  final Accounts? accounts;

  /// What is signed to connect: these words, then the hub's number.
  static const greeting = 'ghost-hub v1 ';

  /// How much is held for everyone together, in bytes, and how many may be connected: a server with a few hundred
  /// megabytes to itself, open to anyone who can make a key, is not to be filled by them.
  final int heldBytes;
  final int maxConnections;
  int _held = 0;

  static const maxPacket = 64 * 1024;
  static const mailboxFrames = 200;
  static const mailboxBytes = 1 << 20;
  static const holdFor = Duration(days: 7);
  static const maxRoom = 64;
  static const maxRooms = 50000;
  static const maxWatched = 500;
  static const authWait = Duration(seconds: 10);

  /// How many names' last-seen times are kept; the oldest go first.
  static const maxSeen = 200000;

  /// A packet to one person, and one to a room: the first byte of a binary message.
  static const toPeer = 1;
  static const toRoom = 2;

  /// A packet to a room that is kept as well, for whoever joins it later (Matt, 2026-11-18: "I can't see their messages
  /// in spaces within a circle"): the hub kept nothing of a room, so what was written while a phone was closed came to
  /// it only if a member who had it was in the room when it came back. The app marks a space's words, deletions,
  /// roster and description so ([toRoomKept]); each joining device is handed what is kept, sealed as it came, which
  /// the hub cannot read. Handed on as [toRoom], so nothing on the app's side reads another kind.
  static const toRoomKept = 3;

  /// A reaction to a message in a room (Matt, 2026-11-20: "add reactions after done to spaces and circles"): kept as
  /// [toRoomKept] is, handed to everyone in the room, and passed on with this first byte so the apps take nothing but a
  /// reaction from it. At most [maxReaction] bytes. The one thing someone who may not post in a read-only room may send
  /// to everyone there: a reaction is no post, and a packet that small carries no message the apps would show.
  static const toRoomReaction = 4;
  static const maxReaction = 512;

  /// What a room keeps: its newest [roomKeepFrames], none older than [roomKeepFor], [roomKeepBytes] in all at most.
  static const roomKeepFrames = 300;
  static const roomKeepFor = Duration(days: 7);
  static const roomKeepBytes = 256 * 1024 * 1024;

  /// Kept packets by room, with the hash of the room's token, so only one who knows it is handed them.
  final Map<String, ({String hash, List<_Held> frames})> _kept = {};
  int _keptBytes = 0;

  /// How many packets [room] keeps, for a test.
  int keptIn(String room) => _kept[room]?.frames.length ?? 0;

  void _keep(String name, String hash, Uint8List frame) {
    var box = _kept[name];
    if (box == null || box.hash != hash) {
      if (box != null) _keptBytes -= box.frames.fold<int>(0, (n, h) => n + h.frame.length);
      box = _kept[name] = (hash: hash, frames: <_Held>[]);
    }
    box.frames.add(_Held(frame, _now()));
    _keptBytes += frame.length;
    while (box.frames.length > roomKeepFrames) {
      _keptBytes -= box.frames.removeAt(0).frame.length;
    }
    // Over the whole store's cap: the oldest of the busiest room goes first.
    while (_keptBytes > roomKeepBytes && _kept.isNotEmpty) {
      final biggest = _kept.entries.reduce((a, b) => a.value.frames.length >= b.value.frames.length ? a : b);
      if (biggest.value.frames.isEmpty) {
        _kept.remove(biggest.key);
        continue;
      }
      _keptBytes -= biggest.value.frames.removeAt(0).frame.length;
    }
  }

  /// Who is here, by name: every device signed in under it (Matt, 2026-11-18: "I want desktop to be able to run
  /// standalone for internal friends and circles ... even if the desktop is linked": a phone and its computer, one
  /// identity, both here). Each says which device it is (`device` in its hello); a connection from the same device
  /// takes its place, as one name's connection always did. An app from before says none, and takes the place of any
  /// other that said none.
  final Map<String, List<_End>> _here = {};

  /// The most devices here under one name at once; one more takes the place of the longest here.
  static const maxDevices = 8;

  bool _isHere(String id) => _here[id]?.isNotEmpty ?? false;

  /// Away, under a name with several devices here, is every one of them away.
  /// [id] chose how they are shown (GMFB-34): told to whoever watches them, once a change.
  void _setMode(String id, String said) {
    final mode = said == 'busy' || said == 'invisible' ? said : '';
    final was = _mode[id] ?? '';
    if (mode == was || !_isHere(id)) return;
    if (mode.isEmpty) {
      _mode.remove(id);
    } else {
      _mode[id] = mode;
    }
    final watchers = _watching[id] ?? const <_End>{};
    final at = _now().millisecondsSinceEpoch;
    if (mode == 'invisible') {
      // Gone, to watchers, as of now; last seen not moved on while hidden.
      _keepSeen(id, at);
      for (final w in watchers) {
        _tell(w.ws, {'went': id, 'at': at});
      }
      return;
    }
    for (final w in watchers) {
      if (was == 'invisible') {
        _tell(w.ws, {'came': id});
        if (_awaySince.containsKey(id)) _tell(w.ws, {'away': id, 'is': true, 'at': _awaySince[id]});
      }
      if ((was == 'busy') != (mode == 'busy')) _tell(w.ws, {'busy': id, 'is': mode == 'busy'});
    }
  }

  bool _allAway(String id) => (_here[id] ?? const <_End>[]).every((e) => e.away);
  final Map<String, List<_Held>> _mail = {};
  final Map<String, _Room> _rooms = {};
  final Map<String, Set<_End>> _watching = {};

  /// When each name that has gone was last using the app (ms since 1970), oldest first.
  final Map<String, int> _seen = {};

  /// Those here with the app put away, and since when.
  final Map<String, int> _awaySince = {};

  /// How each person here chose to be shown, where not plainly: 'busy' or 'invisible' (GMFB-34).
  final Map<String, String> _mode = {};

  /// Here and not hiding: what watchers are told.
  bool _shown(String id) => _isHere(id) && _mode[id] != 'invisible';

  void _keepSeen(String id, int at) {
    _seen.remove(id);
    _seen[id] = at;
    while (_seen.length > maxSeen) {
      _seen.remove(_seen.keys.first);
    }
  }

  /// When [id] was last seen, for a test.
  int? seenOf(String id) => _seen[id];

  /// Who is looking at a room without being in it (a voice channel's list: who is connected), by room, with the hash
  /// of the token each looked with. Told who is in it now and whenever that changes; a wrong token is told nothing.
  final Map<String, Map<_End, String>> _lookers = {};
  static const maxLooks = 200;
  Timer? _sweeper;

  int _open = 0;
  int get connected => _here.values.fold(0, (n, l) => n + l.length);

  /// How much is held for people who are away, in bytes.
  int get holding => _held;
  int get rooms => _rooms.length;
  int heldFor(String id) => _mail[id]?.length ?? 0;

  void start() {
    handles?.load();
    invites?.load();
    words?.load();
    accounts?.load();
    _sweeper ??= Timer.periodic(const Duration(minutes: 10), (_) {
      sweep();
      handles?.sweep();
      accounts?.sweep();
      accounts?.save();
      words?.sweep();
      final i = invites;
      if (i != null) unawaited(i.sweep());
    });
  }

  void stop() {
    _sweeper?.cancel();
    _sweeper = null;
    handles?.save();
    invites?.save();
    words?.save();
    accounts?.save();
    for (final end in _here.values.expand((l) => l).toList()) {
      end.ws.close(WebSocketStatus.goingAway);
    }
  }

  static final _hexOnly = RegExp(r'^[0-9a-f]+$');
  static bool _hex(Object? text, int length) => text is String && text.length == length && _hexOnly.hasMatch(text);
  static List<int> _unhex(String text) => [for (var i = 0; i + 1 < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)];

  /// The name a public key is known by here.
  static String nameOf(List<int> publicKey) => hexOf(sha256(publicKey).sublist(0, 16));

  /// What a read-only room's name is made from: these words, then 16 bytes only its members know (from the space's
  /// seed), then the circle owner's public key (33 bytes).
  static const anchorWords = 'ghost-ro|';

  /// The name of the read-only room made from [base] for the circle owner [owner].
  static String anchoredName(List<int> base, List<int> owner) => hexOf(sha256([...utf8.encode(anchorWords), ...base, ...owner]).sublist(0, 16));

  /// What the circle's owner signs for generation [gv] of its admin list (CircleManifest.grantsMessage in the app).
  static List<int> grantsMessage(String owner, int gv, Map<String, String> grants) =>
      utf8.encode('ghost-circle grants|$owner|$gv|${jsonEncode(Map.fromEntries(grants.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))}');

  /// What the owner signs to make [id] an admin (CircleManifest.grantMessage in the app).
  static List<int> grantMessage(String owner, String id) => utf8.encode('ghost-circle admin|$owner|$id');

  /// The most admins a read-only room's list is read for.
  static const maxGrants = 200;

  /// The key a room is kept under: a read-only room's apart from an ordinary one of the same name.
  static String _keyOf(String name, bool anchored) => anchored ? 'ro:$name' : name;
  static String _nameOf(String key) => key.startsWith('ro:') ? key.substring(3) : key;

  /// The room [e] is in by [name]: its read-only one where it joined that.
  String _keyIn(_End e, String name) => e.rooms.contains('ro:$name') ? 'ro:$name' : name;

  /// Who may post in a read-only room, for a test.
  Set<String>? writersIn(String name) => _rooms['ro:$name']?.writers;

  /// Takes the admin list [ro] carries for [room]: a newer generation signed by the owner replaces what is kept; a
  /// circle from before generations (0) adds each grant that checks out. Anything that doesn't check out is passed over.
  void _takeGrants(_Room room, Map ro) {
    final owner = room.owner;
    if (owner == null) return;
    final gv = ro['gv'] is int ? ro['gv'] as int : 0;
    final raw = ro['g'] is Map ? ro['g'] as Map : const {};
    final grants = <String, String>{
      for (final e in raw.entries.take(maxGrants))
        if (_hex(e.key, 32) && _hex(e.value, 128)) e.key as String: e.value as String,
    };
    bool granted(String id) {
      try {
        return P256.verify(_unhex(owner), grantMessage(owner, id), _unhex(grants[id]!));
      } catch (_) {
        return false;
      }
    }

    if (gv > 0) {
      if (gv <= room.gv || !_hex(ro['gs'], 128)) return;
      if (raw.length > maxGrants || !P256.verify(_unhex(owner), grantsMessage(owner, gv, grants), _unhex(ro['gs'] as String))) return;
      room.gv = gv;
      room.writers
        ..clear()
        ..add(room.ownerId)
        ..addAll(grants.keys.where(granted));
    } else if (room.gv <= 0) {
      room.gv = 0;
      room.writers.addAll(grants.keys.where(granted));
    }
  }

  void _say(String what) {
    // Never an address, never a whole name.
    if (verbose) stdout.writeln('${_now().toIso8601String()} hub $what');
  }

  void _tell(HubSocket? ws, Map<String, Object?> what) {
    if (ws == null || !ws.isOpen) return;
    try {
      ws.add(jsonEncode(what));
    } catch (_) {}
  }

  /// Takes a connection that asked for the hub (the relay hands over any address ending in `/hub`).
  Future<void> accept(HttpRequest request) async {
    if (_open >= maxConnections) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    final WebSocket ws;
    try {
      // No compression: a message is held whole before its length is looked at, and a deflated one of a few hundred
      // kilobytes opens out to hundreds of megabytes (found in review, 2026-11-22). Sealed packets don't shrink anyway.
      ws = await WebSocketTransformer.upgrade(request, compression: CompressionOptions.compressionOff);
    } catch (_) {
      return;
    }
    ws.pingInterval = const Duration(seconds: 30);
    attach(_WebSocketHubSocket(ws));
  }

  /// Takes a connection whatever carries it: the WebSocket [accept] upgraded, or any other [HubSocket] (one made in
  /// this very program, another relay's, a peer-to-peer stream). It is said hello to and heard from then on, as a
  /// WebSocket always was. [maxConnections] counts these too: one more than that is closed at once (4503, "full").
  void attach(HubSocket socket) {
    if (_open >= maxConnections) {
      socket.close(4503, 'full');
      return;
    }
    _open++;
    var counted = true;
    final nonce = [for (var i = 0; i < 32; i++) _random.nextInt(256)];
    _End? end;
    final waiting = Timer(authWait, () {
      if (end == null) socket.close(4401, 'no hello');
    });
    // `peek`: this hub knows a look (below), so a closed app's check can sign in without being handed anything; a
    // hub from before would hand it all over, and the check does not sign in to one that does not say so.
    // `react`: this hub takes reactions ([toRoomReaction]); an app sends them as kept packets to one that doesn't say so.
    _tell(socket, {'hello': hexOf(nonce), 'peek': true, 'react': true});

    void leave() {
      waiting.cancel();
      if (counted) {
        counted = false;
        _open--;
      }
      final e = end;
      if (e == null) return;
      end = null;
      for (final room in e.rooms.toList()) {
        _leave(e, room);
      }
      for (final room in e.looks.toList()) {
        _unlook(e, room);
      }
      for (final id in e.watches) {
        final set = _watching[id];
        set?.remove(e);
        if (set != null && set.isEmpty) _watching.remove(id);
      }
      handles?.went(e.id, e.tell);
      final list = _here[e.id];
      if (list == null || !list.remove(e)) return; // replaced by a newer connection from the same device
      if (list.isNotEmpty) {
        // Another device of theirs is still here: not gone, though maybe now away (every one left is).
        final away = _allAway(e.id);
        if (away != _awaySince.containsKey(e.id)) {
          final at = _now().millisecondsSinceEpoch;
          if (away) {
            _awaySince[e.id] = at;
          } else {
            _awaySince.remove(e.id);
          }
          for (final w in _watching[e.id] ?? const <_End>{}) {
            _tell(w.ws, {'away': e.id, 'is': away, 'at': at});
          }
        }
        return;
      }
      _here.remove(e.id);
      // Invisible, they were gone to watchers already, and their last seen was not moved on.
      final hidden = _mode.remove(e.id) == 'invisible';
      // Last seen: when they put the app away, where they had, else now.
      final at = _awaySince.remove(e.id) ?? _now().millisecondsSinceEpoch;
      if (hidden) return;
      _keepSeen(e.id, at);
      for (final w in _watching[e.id] ?? const <_End>{}) {
        _tell(w.ws, {'went': e.id, 'at': at});
      }
      _say('${e.id.substring(0, 6)} left');
    }

    socket.incoming.listen((data) {
      final e = end;
      if (e == null) {
        // The first thing said: who this is, and the hub's number signed with their key.
        Map? hello;
        try {
          hello = data is String ? jsonDecode(data) as Map : null;
        } catch (_) {}
        List<int>? key, sig;
        try {
          key = base64Decode(hello?['key'] as String);
          sig = base64Decode(hello?['sig'] as String);
        } catch (_) {}
        final id = hello?['id'];
        if (key == null || sig == null || !_hex(id, 32) || nameOf(key) != id || !P256.verify(key, [...utf8.encode(greeting), ...nonce], sig)) {
          _tell(socket, {'ok': false, 'err': 'bad hello'});
          socket.close(4400, 'bad hello');
          return;
        }
        waiting.cancel();
        // A look, not a coming (Matt, 2026-11-16: "Yes, wake-ups"): a closed app's check, every so often, of whether
        // anything is held for it. Told how many, and nothing is handed over or taken, nor the app's own connection
        // replaced: the app gets them when it opens.
        if (hello?['peek'] == true) {
          final cutoff = _now().subtract(holdFor);
          final count = (_mail[id] ?? const <_Held>[]).where((h) => h.at.isAfter(cutoff)).length;
          _tell(socket, {'ok': true, 'held': count, 'peek': true, 'here': _isHere(id as String)});
          socket.close(1000, 'looked');
          return;
        }
        final device = hello?['device'] is String && (hello!['device'] as String).length <= 64 ? hello['device'] as String : '';
        final made = _End(id as String, socket, (what) => _tell(socket, what), device: device);
        final list = _here[made.id] ??= [];
        final first = list.isEmpty;
        // The same device again (a reconnect) takes its own place; the longest here goes where there are too many.
        for (final old in [...list.where((o) => o.device == device), if (list.length >= maxDevices) list.first]) {
          list.remove(old);
          old.ws.close(4409, 'replaced');
        }
        list.add(made);
        // Another device coming while the others were put away: back, to whoever watches.
        if (_awaySince.remove(made.id) != null && !first) {
          for (final w in _watching[made.id] ?? const <_End>{}) {
            _tell(w.ws, {'away': made.id, 'is': false, 'at': _now().millisecondsSinceEpoch});
          }
        }
        end = made;
        handles?.came(made.id, made.tell, key: key);
        final all = _mail.remove(made.id) ?? const <_Held>[];
        // What this very device sent to its own name stays kept for the others (a device from before devices, with no
        // name, is handed everything, as before).
        final back = [for (final h in all) if (h.byDevice != null && h.byDevice == made.device) h];
        final held = [for (final h in all) if (!back.contains(h)) h];
        if (back.isNotEmpty) _mail[made.id] = back;
        _held -= held.fold<int>(0, (n, h) => n + h.frame.length);
        final cutoff = _now().subtract(holdFor);
        final fresh = held.where((h) => h.at.isAfter(cutoff)).toList();
        _tell(socket, {'ok': true, 'held': fresh.length, 'now': _now().millisecondsSinceEpoch, 'since': started.millisecondsSinceEpoch, if (helpers.isNotEmpty) 'helpers': helpers});
        for (final h in fresh) {
          socket.add(h.frame);
        }
        // A mode said with the hello holds from the first moment: someone invisible never shows as come.
        final asked = hello?['mode'];
        if (first && asked is String && (asked == 'busy' || asked == 'invisible')) _mode[made.id] = asked;
        if (first && _shown(made.id)) {
          for (final w in _watching[made.id] ?? const <_End>{}) {
            _tell(w.ws, {'came': made.id});
            if (_mode[made.id] == 'busy') _tell(w.ws, {'busy': made.id, 'is': true});
          }
        }
        _say('${made.id.substring(0, 6)} came${fresh.isEmpty ? '' : ', ${fresh.length} held'}');
        return;
      }
      if (data is List<int>) {
        _packet(e, data);
        return;
      }
      Map? said;
      try {
        said = jsonDecode(data as String) as Map;
      } catch (_) {}
      if (said == null) return;
      if (said.containsKey('ping')) {
        _tell(socket, {'pong': said['ping']});
      } else if (said.containsKey('push')) {
        // This install's token for push notifications (an iPhone), or null to forget it.
        pushes?.said(e.id, said['push']);
        _tell(socket, {'push': pushes != null});
      } else if (said['dir'] is String && Accounts.dirs.contains(said['dir'])) {
        final a = accounts;
        if (a == null) {
          _tell(socket, {'dir': 'err', 'about': said['dir'], 'err': 'This server keeps no accounts.'});
        } else {
          a.said(e.id, said, (m) => _tell(socket, m));
        }
      } else if (said['dir'] is String && InviteWords.dirs.contains(said['dir'])) {
        final w = words;
        if (w == null) {
          _tell(socket, {'dir': 'err', 'about': said['dir'], 'err': 'This server keeps no invite words.'});
        } else {
          w.said(e.id, said, (m) => _tell(socket, m));
        }
      } else if (said['dir'] is String && Invites.dirs.contains(said['dir'])) {
        final i = invites;
        if (i == null) {
          _tell(socket, {'dir': 'err', 'about': said['dir'], 'err': 'This server keeps no invites.'});
        } else {
          i.said(e.id, said, (m) => _tell(socket, m));
        }
      } else if (said['dir'] is String) {
        final h = handles;
        if (h == null) {
          _tell(socket, {'dir': 'err', 'about': said['dir'], 'err': 'This server keeps no handles.'});
        } else {
          // The asking connection's own tell, as came and went are given: the answer goes to the device that asked.
          h.said(e.id, said, e.tell);
        }
      } else if (said['watch'] is List) {
        final ids = (said['watch'] as List).where((i) => _hex(i, 32)).cast<String>().take(maxWatched).toList();
        for (final id in ids) {
          if (e.watches.length >= maxWatched && !e.watches.contains(id)) break;
          e.watches.add(id);
          (_watching[id] ??= {}).add(e);
        }
        _tell(socket, {
          'here': [for (final id in ids) if (_shown(id)) id],
          'away': [for (final id in ids) if (_shown(id) && _awaySince.containsKey(id)) id],
          'busy': [for (final id in ids) if (_shown(id) && _mode[id] == 'busy') id],
          'seen': {for (final id in ids) if (!_shown(id) && _seen.containsKey(id)) id: _seen[id]},
        });
      } else if (said['mode'] is String) {
        _setMode(e.id, said['mode'] as String);
      } else if (said['away'] is bool) {
        // The app put away, or back in use: told to whoever watches them, once a change.
        e.away = said['away'] as bool;
        final away = _allAway(e.id);
        if (away == _awaySince.containsKey(e.id)) return;
        final at = _now().millisecondsSinceEpoch;
        if (away) {
          _awaySince[e.id] = at;
        } else {
          _awaySince.remove(e.id);
        }
        if (!_shown(e.id)) return;
        for (final w in _watching[e.id] ?? const <_End>{}) {
          _tell(w.ws, {'away': e.id, 'is': away, 'at': at});
        }
      } else if (said.containsKey('join')) {
        _join(e, said['join'], said['token'], said['ro'] is Map ? said['ro'] as Map : null);
      } else if (said.containsKey('anchor')) {
        // A read-only room's admin list, newer than the one it was joined with (an admin made or taken away).
        final name = said['anchor'];
        final room = name is String && e.rooms.contains('ro:$name') ? _rooms['ro:$name'] : null;
        if (room != null) _takeGrants(room, said);
      } else if (said.containsKey('leave')) {
        final room = said['leave'];
        if (room is String) {
          final key = _keyIn(e, room);
          if (e.rooms.contains(key)) _leave(e, key);
        }
      } else if (said.containsKey('look')) {
        _look(e, said['look'], said['token']);
      } else if (said.containsKey('unlook')) {
        final room = said['unlook'];
        if (room is String) _unlook(e, room);
      }
    }, onDone: leave, onError: (_) => leave(), cancelOnError: true);
  }

  void _packet(_End from, List<int> data) {
    if (data.length > maxPacket + 32 || data.isEmpty) {
      from.ws.close(WebSocketStatus.messageTooBig, 'too big');
      return;
    }
    if (data[0] == toPeer && data.length > 21) {
      // [1][a number the sender made, 4 bytes][to, 16 bytes][the packet]
      final seq = ByteData.sublistView(Uint8List.fromList(data.sublist(1, 5))).getUint32(0);
      final to = hexOf(data.sublist(5, 21));
      final frame = Uint8List.fromList([toPeer, ..._unhex(from.id), ...data.sublist(21)]);
      // To every device of theirs that is here (but the one sending it, where they write to themselves).
      final there = [for (final t in _here[to] ?? const <_End>[]) if (!identical(t, from) && t.ws.isOpen) t];
      if (there.isNotEmpty) {
        for (final t in there) {
          t.ws.add(frame);
        }
        _tell(from.ws, {'ack': seq, 'here': true});
        return;
      }
      final box = _mail[to] ??= [];
      final size = box.fold<int>(0, (n, h) => n + h.frame.length);
      if (box.length >= mailboxFrames || size + frame.length > mailboxBytes || _held + frame.length > heldBytes) {
        if (box.isEmpty) _mail.remove(to);
        _tell(from.ws, {'nak': seq, 'err': 'full'});
        return;
      }
      box.add(_Held(frame, _now(), byDevice: to == from.id && from.device.isNotEmpty ? from.device : null));
      _held += frame.length;
      _tell(from.ws, {'ack': seq, 'here': false});
      // Their app is closed: woken where it can be (an iPhone's push; an Android phone looks for itself).
      pushes?.held(to);
    } else if (data[0] == toRoomReaction && data.length > 17) {
      // [4][the room, 16 bytes][a sealed reaction]: kept, and to everyone else in it, whoever may post there.
      if (data.length - 17 > maxReaction) return;
      final name = hexOf(data.sublist(1, 17));
      final key = _keyIn(from, name);
      final room = _rooms[key];
      if (room == null || !(room.members[from.id]?.contains(from) ?? false)) return;
      final frame = Uint8List.fromList([toRoomReaction, ...data.sublist(1, 17), ..._unhex(from.id), ...data.sublist(17)]);
      _keep(key, room.hash, frame);
      for (final m in room.members.values.expand((d) => d)) {
        if (!identical(m, from) && m.ws.isOpen) m.ws.add(frame);
      }
    } else if ((data[0] == toRoom || data[0] == toRoomKept) && data.length > 17) {
      // [2][the room, 16 bytes][the packet]: to everyone else in it.
      final name = hexOf(data.sublist(1, 17));
      final key = _keyIn(from, name);
      final room = _rooms[key];
      if (room == null || !(room.members[from.id]?.contains(from) ?? false)) return;
      final frame = Uint8List.fromList([toRoom, ...data.sublist(1, 17), ..._unhex(from.id), ...data.sublist(17)]);
      // A read-only room: someone who may not post keeps nothing in it, and what else they say (who they are, asking
      // for what was missed) reaches only those who may.
      final reader = room.owner != null && !room.writers.contains(from.id);
      if (reader && data[0] == toRoomKept) {
        _tell(from.ws, {'room': name, 'ro': 'refused'});
        return;
      }
      if (data[0] == toRoomKept) _keep(key, room.hash, frame);
      // To every device of everyone in it, the sender's other devices too, but not the connection it came from.
      for (final e in room.members.entries) {
        if (reader && !room.writers.contains(e.key)) continue;
        for (final m in e.value) {
          if (!identical(m, from) && m.ws.isOpen) m.ws.add(frame);
        }
      }
    }
  }

  /// Tells whoever looks at [name] with its token who is in it now.
  void _showLookers(String name) {
    final lookers = _lookers[name];
    if (lookers == null) return;
    final room = _rooms[name];
    for (final l in lookers.entries) {
      if (room != null && room.hash != l.value) continue;
      _tell(l.key.ws, {'room': name, 'look': [...?room?.members.keys]});
    }
  }

  void _look(_End e, Object? name, Object? token) {
    if (!_hex(name, 32) || !_hex(token, 64)) return;
    if (e.looks.length >= maxLooks && !e.looks.contains(name)) return;
    final hash = hexOf(sha256(utf8.encode(token as String)));
    (_lookers[name as String] ??= {})[e] = hash;
    e.looks.add(name);
    final room = _rooms[name];
    if (room == null || room.hash == hash) _tell(e.ws, {'room': name, 'look': [...?room?.members.keys]});
  }

  void _unlook(_End e, String name) {
    e.looks.remove(name);
    final lookers = _lookers[name];
    lookers?.remove(e);
    if (lookers != null && lookers.isEmpty) _lookers.remove(name);
  }

  void _join(_End e, Object? name, Object? token, [Map? ro]) {
    if (!_hex(name, 32) || !_hex(token, 64)) {
      _tell(e.ws, {'room': name, 'ok': false, 'err': 'bad room'});
      return;
    }
    // A read-only room: its name must be the one made from the owner's key it is joined with.
    String? owner;
    if (ro != null) {
      final base = ro['base'], key = ro['owner'];
      if (!_hex(base, 32) || !_hex(key, 66) || !(key as String).startsWith(RegExp('0[23]')) || anchoredName(_unhex(base as String), _unhex(key)) != name) {
        _tell(e.ws, {'room': name, 'ok': false, 'err': 'bad anchor'});
        return;
      }
      owner = key;
    }
    final at = _keyOf(name as String, owner != null);
    // In one of a name's two rooms at a time.
    if (e.rooms.contains(_keyOf(name, owner == null))) {
      _tell(e.ws, {'room': name, 'ok': false, 'err': 'refused'});
      return;
    }
    final hash = hexOf(sha256(utf8.encode(token as String)));
    var room = _rooms[at];
    if (room == null) {
      if (_rooms.length >= maxRooms) {
        _tell(e.ws, {'room': name, 'ok': false, 'err': 'full'});
        return;
      }
      room = _rooms[at] = _Room(hash, owner: owner);
    }
    if (room.hash != hash || (room.members.length >= maxRoom && !room.members.containsKey(e.id))) {
      _tell(e.ws, {'room': name, 'ok': false, 'err': room.hash != hash ? 'refused' : 'full'});
      return;
    }
    final others = room.members.keys.where((id) => id != e.id).toList();
    // Every device of a member is in the room, each handed what is sent there (Matt, 2026-11-18: his phone stopped
    // seeing a circle's messages and members once his computer, the same identity, joined its rooms and took the one
    // place a member had). The others hear that someone came only with their first device.
    final devices = room.members.putIfAbsent(e.id, () => <_End>[]);
    final first = devices.isEmpty;
    if (!devices.any((d) => identical(d, e))) devices.add(e);
    e.rooms.add(at);
    if (ro != null) _takeGrants(room, ro);
    _tell(e.ws, {'room': name, 'ok': true, 'members': others, if (room.owner != null) 'ro': room.writers.contains(e.id) ? 'writer' : 'reader', 'ice': ?turn.serverFor(e.id, _now())});
    // What the room kept, for one who knows its token: written while this device was away.
    final kept = _kept[at];
    if (kept != null && kept.hash == hash) {
      final cutoff = _now().subtract(roomKeepFor);
      for (final h in kept.frames) {
        if (h.at.isAfter(cutoff) && e.ws.isOpen) e.ws.add(h.frame);
      }
    }
    if (first) {
      for (final id in others) {
        for (final d in room.members[id] ?? const <_End>[]) {
          _tell(d.ws, {'room': name, 'came': e.id});
        }
      }
    }
    if (owner == null) _showLookers(name);
    _say('${e.id.substring(0, 6)} joined ${owner == null ? '' : 'read-only '}room ${name.substring(0, 6)} (${room.members.length} in it)');
  }

  /// [e] out of the room kept under [key] (a read-only room's is `ro:` and its name).
  void _leave(_End e, String key) {
    final name = _nameOf(key);
    e.rooms.remove(key);
    final room = _rooms[key];
    final devices = room?.members[e.id];
    if (room == null || devices == null || !devices.any((d) => identical(d, e))) return;
    devices.removeWhere((d) => identical(d, e));
    // Another device of theirs is still in it: they have not gone.
    if (devices.isNotEmpty) return;
    room.members.remove(e.id);
    if (room.members.isEmpty) {
      _rooms.remove(key);
    } else {
      for (final m in room.members.values.expand((d) => d)) {
        _tell(m.ws, {'room': name, 'went': e.id});
      }
    }
    if (key == name) _showLookers(name);
    _say('${e.id.substring(0, 6)} left room ${name.substring(0, 6)}');
  }

  /// Forgets packets held longer than [holdFor].
  void sweep() {
    final keptCutoff = _now().subtract(roomKeepFor);
    for (final name in _kept.keys.toList()) {
      final box = _kept[name]!;
      while (box.frames.isNotEmpty && !box.frames.first.at.isAfter(keptCutoff)) {
        _keptBytes -= box.frames.removeAt(0).frame.length;
      }
      if (box.frames.isEmpty) _kept.remove(name);
    }
    final cutoff = _now().subtract(holdFor);
    for (final id in _mail.keys.toList()) {
      final box = _mail[id]!;
      for (final h in box.where((h) => !h.at.isAfter(cutoff)).toList()) {
        box.remove(h);
        _held -= h.frame.length;
      }
      if (box.isEmpty) _mail.remove(id);
    }
  }
}

/// A connection as the hub holds it, whatever carries it: a WebSocket, or anything else that passes strings and bytes.
abstract class HubSocket {
  /// What the other end says: a String or a `List<int>`. Done when it has gone.
  Stream<Object?> get incoming;

  /// Says a String or a `List<int>` to the other end.
  void add(Object data);

  /// Whether the other end can still be said to.
  bool get isOpen;

  /// Closes it, with a WebSocket's number and reason for closing where there is a use for them. [incoming] is done
  /// once it has closed, whichever end closed it.
  Future<void> close([int? code, String? reason]);
}

/// A WebSocket as the hub holds it ([Hub.accept]).
class _WebSocketHubSocket implements HubSocket {
  _WebSocketHubSocket(this._ws);
  final WebSocket _ws;

  @override
  Stream<Object?> get incoming => _ws;
  @override
  void add(Object data) => _ws.add(data);
  @override
  bool get isOpen => _ws.readyState == WebSocket.open;
  @override
  Future<void> close([int? code, String? reason]) => _ws.close(code, reason);
}

class _End {
  _End(this.id, this.ws, this.tell, {this.device = ''});
  final String id;
  final HubSocket ws;

  /// Which of its name's devices this is, as it said; empty from an app from before devices.
  final String device;

  /// Whether this device has the app put away.
  bool away = false;

  /// Says something to this connection, as JSON.
  final void Function(Map<String, Object?>) tell;
  final Set<String> rooms = {};
  final Set<String> watches = {};
  final Set<String> looks = {};
}

class _Held {
  _Held(this.frame, this.at, {this.byDevice});
  final Uint8List frame;
  final DateTime at;

  /// For a packet an identity sent to its own name: which of its devices sent it (its hello's `device`). That device
  /// isn't handed it back: it is kept for the identity's other devices (GMFB-26, an app passing on a packet it couldn't
  /// open, for a sibling that can). Null for anything else.
  final String? byDevice;
}

class _Room {
  _Room(this.hash, {this.owner}) : ownerId = owner == null ? '' : Hub.nameOf(Hub._unhex(owner)) {
    if (owner != null) writers.add(ownerId);
  }

  /// SHA-256 of the room's token, in hex.
  final String hash;

  /// A read-only room's circle owner (their public key, 33 bytes in hex) and name; null for an ordinary room.
  final String? owner;
  final String ownerId;

  /// Who may post in a read-only room: the owner and the admins they signed.
  final Set<String> writers = {};

  /// The generation of the admin list [writers] came from; -1 before any.
  int gv = -1;
  /// Each member by name, with every device of theirs in the room.
  final Map<String, List<_End>> members = {};
}
