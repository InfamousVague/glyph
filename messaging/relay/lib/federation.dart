import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'fed_dial.dart';
import 'handles.dart';
import 'home_record.dart';
import 'hub.dart';
import 'p256.dart';
import 'sha256.dart';

/// Whether this relay links with other relays: its keeper's choice (`GHOST_FED`).
enum FedMode {
  /// With none: it is an island, as every relay was before. Nothing is dialled, no link is taken, no packet passed on.
  off,

  /// With any relay that proves its key, but those blocked.
  open,

  /// Only with the relays its keeper listed (`GHOST_FED_ALLOW`).
  list,
}

/// What federation reads from the server's environment (bin/relay.dart); every one has a default, and the default is
/// off.
class FedConfig {
  const FedConfig({this.mode = FedMode.off, this.allow = const {}, this.block = const {}, this.publicHub = '', this.via = '', this.packetsAMinute = 1200, this.bytesADay = 512 << 20, this.lookupsAnHour = 600, this.ports = const {}, this.plain = false, this.problems = const []});

  factory FedConfig.fromEnvironment(Map<String, String> env) {
    final problems = <String>[];
    String said(String name) => (env[name] ?? '').trim();
    final mode = switch (said('GHOST_FED').toLowerCase()) {
      'open' => FedMode.open,
      'list' => FedMode.list,
      '' || 'off' => FedMode.off,
      _ => () {
          problems.add('GHOST_FED is off, open or list: read as off');
          return FedMode.off;
        }(),
    };
    Set<String> names(String name) {
      final out = <String>{};
      for (final part in said(name).toLowerCase().split(',').map((p) => p.trim()).where((p) => p.isNotEmpty)) {
        if (_relayName.hasMatch(part) || _hostAndPort.hasMatch(part)) {
          out.add(part);
        } else {
          problems.add('$name: "$part" is neither a host nor a relay\'s name, and is passed over');
        }
      }
      return out;
    }

    String hub(String name) {
      final typed = said(name);
      if (typed.isEmpty) return '';
      final url = canonicalHub(typed);
      if (url == null || !url.endsWith('/hub')) {
        problems.add('$name is a hub\'s address, like wss://relay.example.com/hub: passed over');
        return '';
      }
      return url;
    }

    int number(String name, int fallback, int most) {
      final typed = said(name);
      if (typed.isEmpty) return fallback;
      final n = RegExp(r'^[0-9]{1,15}$').hasMatch(typed) ? int.parse(typed) : -1;
      if (n < 1) {
        problems.add('$name is a whole number above nothing: its default is used');
        return fallback;
      }
      return n > most ? most : n;
    }

    final ports = <int>{};
    for (final part in said('GHOST_FED_PORTS').split(',').map((p) => p.trim()).where((p) => p.isNotEmpty)) {
      final n = RegExp(r'^[0-9]{1,5}$').hasMatch(part) ? int.parse(part) : 0;
      if (n >= 1 && n <= 65535) {
        ports.add(n);
      } else {
        problems.add('GHOST_FED_PORTS: "$part" is not a port, and is passed over');
      }
    }
    return FedConfig(
      mode: mode,
      allow: names('GHOST_FED_ALLOW'),
      block: names('GHOST_FED_BLOCK'),
      publicHub: hub('GHOST_PUBLIC_HUB'),
      via: hub('GHOST_FED_VIA'),
      packetsAMinute: number('GHOST_FED_PACKETS_A_MINUTE', 1200, 1000000),
      // (2^40, written out: a shift keeps 32 bits where an integer is a browser's number.)
      bytesADay: number('GHOST_FED_BYTES_A_DAY', 512 << 20, 1099511627776),
      lookupsAnHour: number('GHOST_FED_LOOKUPS_AN_HOUR', 600, 1000000),
      ports: ports,
      plain: said('GHOST_FED_PLAIN') == '1',
      problems: problems,
    );
  }

  static final _relayName = RegExp(r'^[0-9a-f]{32}$');
  static final _hostAndPort = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*(:[0-9]{1,5})?$');

  final FedMode mode;

  /// With [FedMode.list], the only relays linked with: each a host (`relay.example.com`, or with its port) or a
  /// relay's name (32 hex digits). With [FedMode.open] it changes nothing.
  final Set<String> allow;

  /// Never linked with, whatever the mode: hosts or relays' names.
  final Set<String> block;

  /// This relay's own hub address as the world reaches it (`GHOST_PUBLIC_HUB`), as [canonicalHub] writes it. Empty,
  /// it claims none: it can dial out, and nobody is told an address of its own.
  final String publicHub;

  /// The public relay this one stays linked to (`GHOST_FED_VIA`): for a relay with no address of its own, as one
  /// hosted from an app is. Its people are reached through that link, and reach everyone else through it.
  final String via;

  /// What one linked relay may send here: packets a minute, bytes a day, and how many names it may ask after an hour.
  final int packetsAMinute;
  final int bytesADay;
  final int lookupsAnHour;

  /// Ports dialled besides 443, and whether `ws://` is (fed_dial.dart).
  final Set<int> ports;
  final bool plain;

  /// What in the environment could not be read, in words, for the keeper to see as the relay starts.
  final List<String> problems;
}

/// Dials the hub at [url], which has passed [DialGuard.shape]: the default looks the name up, checks every answer and
/// connects to an address that passed ([DialGuard.dial]); a test hands back a connection held in memory.
typedef FedDial = Future<HubSocket> Function(Uri url);

/// A link another relay opened, as the hub hands it what that relay says ([Federation.incoming]).
abstract class FedEnd {
  void heard(Object? data);
  void gone();
}

/// Relays that talk to each other (docs/OPEN_NETWORK.md, section 4; Matt, 2026-11-22: "I'd like the relays to be able
/// to talk to each other"): two people whose apps use different relays can be friends and talk, each through their
/// own relay, and the relays pass their sealed packets to each other.
///
/// - **A key of its own.** `relay-key.json` in the data folder, made on first start (in memory where there is no
///   folder). The relay's name is made from it as an install's is ([Hub.nameOf]), and the hub's hello to anything that
///   connects says so (`"relay": {"id", "key"}`, [card]).
/// - **Home records** ([HomeRecord], [HomeBook]). The one thing believed about where someone lives: their own
///   signature. An app gives its own as it signs in and its friends' so this relay can route to them
///   (`{"dir":"home","rec":…}`), and asks what is held (`{"dir":"home?","a":…}`).
/// - **Links.** One relay dials another's hub and, in place of an app's hello, says who it is ([dialBytes],
///   [answerBytes]): both prove their keys, each over a number the other made up and over **both** names, so what one
///   signs for this link is no use on another. A relay that claims an address is believed once this relay has dialled
///   that address itself and seen the same key there ([_keyAt], remembered for a day). Whether it links at all is
///   [FedConfig.mode], off unless its keeper says otherwise. A link is opened when first needed, kept while used,
///   closed after [idleFor], tried again with [backoff]; [maxLinks] at most.
/// - **Passing packets on** ([pass]). A packet for someone not connected here, whose record names another relay, goes
///   over a link (`[5]`), and its sender is told what that relay said. With that relay unreachable it waits here
///   ([queuePackets], [queueBytes], [queueFor]) and the sender is told it is kept.
/// - **A relay speaks only for its own people** ([_speaksFor]): what a relay passes on as from someone is taken only
///   where that someone's record names that relay. Refused for want of a record (`nak` `home`), the sender gives the
///   record and tries once more.
/// - **One hop.** What another relay passed here is handed to someone here or kept for them, never passed to a third
///   relay. The one exception is `via`: a relay with no address of its own (hosted from an app) dials a public relay
///   and stays linked; its people's records say `ghost-relay://<its name>?…&via=<that relay>`, they are reached over
///   the standing link, and another relay reaches them by sending that relay a `[6]` naming the hosted one.
/// - **Names** ([_whoisFromApp]). `@maya@relay.example` is asked of that relay over a link.
/// - **Limits.** Per linked relay: [FedConfig.packetsAMinute], [FedConfig.bytesADay], [FedConfig.lookupsAnHour].
///   Everything someone else can grow is counted and capped: records ([HomeBook]), record checks ([checksAnHour],
///   [checksASecond]), links, relays waited on ([maxPeers]), what waits ([queuedBytes] for all of them together),
///   names asked after, dials (fed_dial.dart).
///
/// What it adds to what a relay can see: which of its people talk to people on which other relay. Still never what.
class Federation {
  Federation({
    this.dataDir,
    this.config = const FedConfig(),
    FedDial? dial,
    DialGuard? guard,
    DateTime Function()? now,
    Random? random,
    this.verbose = false,
    this.maxLinks = 64,
    this.maxPeers = 256,
    this.queuePackets = 2000,
    this.queueBytes = 16 << 20,
    this.queuedBytes = 32 << 20,
    this.checksAnHour = 600,
    this.checksASecond = 20,
    this.hellosAMinute = 30,
    this.recordsAMinute = 240,
    HomeBook? homes,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random.secure(),
        guard = guard ?? DialGuard(plain: config.plain, ports: config.ports, now: now),
        homes = homes ?? HomeBook(file: dataDir == null ? null : File('${dataDir.path}/homes.json')) {
    _dial = dial ?? this.guard.dial;
    _loadKey();
    this.homes.load();
  }

  /// Where `relay-key.json` and `homes.json` are kept; null keeps the key in memory and nothing across restarts.
  final Directory? dataDir;
  final FedConfig config;
  final bool verbose;
  final DateTime Function() _now;
  final Random _random;

  /// What every address is held to before it is dialled (fed_dial.dart).
  final DialGuard guard;
  late final FedDial _dial;

  /// The home records held.
  final HomeBook homes;

  /// The most links open at once, to and from other relays together.
  final int maxLinks;

  /// The most other relays anything waits for at once.
  final int maxPeers;

  /// What waits here for one relay that can't be reached: so many packets, so many bytes, for so long.
  final int queuePackets;
  final int queueBytes;
  static const queueFor = Duration(days: 7);

  /// What waits here for all of them together, in bytes: packets for relays not linked right now. A quarter of it at
  /// most is what other relays had this one keep (for a relay that stays linked to it and is away), so no other relay
  /// can use up the room this relay's own people's packets wait in. What is on its way over an open link is counted
  /// apart, held to twice this for everything together, so nothing that waits can stop what can go now.
  final int queuedBytes;

  /// How many records one signed-in install, or one linked relay, may have checked in an hour (a check is several
  /// milliseconds of arithmetic), and how many this relay checks in any one second for everyone together.
  final int checksAnHour;
  final int checksASecond;

  /// How many relays may say hello in a minute: each costs a signature's check, and maybe a dial back.
  final int hellosAMinute;

  /// How many records one linked relay may give in a minute.
  final int recordsAMinute;

  /// A link nothing has crossed for this long is closed; it is opened again when next needed.
  static const idleFor = Duration(minutes: 10);

  /// How long a sender waits to hear what the other relay said before it is told its packet is kept.
  static const answerWithin = Duration(seconds: 4);

  /// How long a hello, a look at an address, or a name asked after may take.
  static const helloWithin = Duration(seconds: 10);
  static const whoisWithin = Duration(seconds: 8);

  /// A link whose relay has not answered a packet for this long is closed and made again.
  static const stuckAfter = Duration(seconds: 30);

  /// How long the key seen at an address is believed without looking again.
  static const believedFor = Duration(days: 1);

  /// How many packets are on a link at once waiting to be answered.
  static const window = 64;

  /// How many names may be waiting on one relay's answer.
  static const asksWaiting = 64;

  /// What a dialling relay signs: these words, the hub's number (32 bytes), its own name, the name of the relay it
  /// dialled (16 bytes each), the number it made up (32 bytes), and the address it claims (empty for none).
  static const dialWords = 'ghost-fed-dial v1 ';

  /// What the relay dialled signs back: these words, the dialler's number, the dialler's name, its own.
  static const answerWords = 'ghost-fed v1 ';

  /// A packet one relay passes to another for someone there, and one for someone on a relay linked to it.
  static const toRelay = 5;
  static const toRelayVia = 6;

  static List<int> dialBytes({required List<int> nonce, required String dialler, required String answerer, required List<int> c, required String url}) =>
      [...utf8.encode(dialWords), ...nonce, ..._unhex(dialler), ..._unhex(answerer), ...c, ...utf8.encode(url)];

  static List<int> answerBytes({required List<int> c, required String dialler, required String answerer}) => [...utf8.encode(answerWords), ...c, ..._unhex(dialler), ..._unhex(answerer)];

  /// How long before a relay that could not be reached is tried again, after so many failures in a row: five seconds,
  /// then twice as long each time, ten minutes at most.
  static Duration backoff(int failures) => Duration(seconds: (5 * (1 << (failures - 1).clamp(0, 10))).clamp(5, 600));

  /// A relay that answered no is not asked again for this long.
  static const refusedFor = Duration(minutes: 10);

  static final _hexOnly = RegExp(r'^[0-9a-f]+$');
  static bool _hex(Object? text, int length) => text is String && text.length == length && _hexOnly.hasMatch(text);
  static List<int> _unhex(String text) => [for (var i = 0; i + 1 < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)];

  // --- who this relay is ---------------------------------------------------------------------------------------------

  late List<int> _scalar;

  /// This relay's public key (33 bytes) and its name.
  late final List<int> key;
  late final String id;

  File? get _keyFile => dataDir == null ? null : File('${dataDir!.path}/relay-key.json');

  /// Thirty-two bytes that are a private key: above nothing, below the curve's order.
  List<int> _freshScalar() {
    while (true) {
      final bytes = [for (var i = 0; i < 32; i++) _random.nextInt(256)];
      final v = bytes.fold(BigInt.zero, (BigInt v, b) => (v << 8) | BigInt.from(b));
      if (v > BigInt.zero && v < P256.n) return bytes;
    }
  }

  void _loadKey() {
    final file = _keyFile;
    List<int>? scalar;
    if (file != null && file.existsSync()) {
      try {
        final kept = (jsonDecode(file.readAsStringSync()) as Map)['scalar'];
        if (_hex(kept, 64)) {
          final v = BigInt.parse(kept as String, radix: 16);
          if (v > BigInt.zero && v < P256.n) scalar = _unhex(kept);
        }
      } catch (_) {}
      if (scalar == null) {
        // A key file that can't be read is put aside, not written over: the relay gets a new name, and says so.
        final aside = '${file.path}.broken-${_now().millisecondsSinceEpoch}';
        try {
          file.renameSync(aside);
        } catch (_) {}
        stderr.writeln('relay: relay-key.json could not be read; kept as ${aside.split('/').last}, and a new key made (this relay has a new name)');
      }
    }
    final made = scalar == null;
    _scalar = scalar ?? _freshScalar();
    key = P256.publicOf(_scalar);
    id = Hub.nameOf(key);
    if (made && file != null) {
      try {
        file.parent.createSync(recursive: true);
        writePrivately(file, jsonEncode({'v': 1, 'id': id, 'key': base64Encode(key), 'scalar': hexOf(_scalar)}));
      } catch (e) {
        stderr.writeln('relay: relay-key.json could not be written (${'$e'.split('\n').first}); this relay\'s key lasts until it stops');
      }
    }
  }

  /// Writes [text] to [file] so that only the relay's own user can read it (mode 600), from the moment it exists: the
  /// process's file mask is narrowed while it is made, since Dart has no way to ask for a mode. Where that can't be
  /// done (Windows) it is written as any file is.
  static void writePrivately(File file, String text) {
    int Function(int)? umask;
    if (!Platform.isWindows) {
      try {
        umask = ffi.DynamicLibrary.process().lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>('umask');
      } catch (_) {}
    }
    final before = umask?.call(0x3f); // 077: nothing for the group or for others
    try {
      final tmp = File('${file.path}.tmp');
      if (tmp.existsSync()) tmp.deleteSync();
      tmp.writeAsStringSync(text, flush: true);
      tmp.renameSync(file.path);
    } finally {
      if (before != null) umask!(before);
    }
  }

  /// A signature of this relay's over [message], with a number of its own made for it and never used again.
  List<int> _sign(List<int> message) => P256.sign(_scalar, message, _freshScalar());

  /// Whether this relay links with others at all.
  bool get on => config.mode != FedMode.off;

  /// This relay has no address of its own and stays linked to a public one: everything not for its own people goes
  /// through that link.
  bool get _hosted => on && config.via.isNotEmpty && config.publicHub.isEmpty;

  /// What the hub's hello says of this relay: its name and key, its own address where it claims one, the relay it
  /// stays linked to where it does, and whether it talks to other relays.
  Map<String, Object?> get card => {'id': id, 'key': base64Encode(key), if (config.publicHub.isNotEmpty) 'url': config.publicHub, if (config.via.isNotEmpty) 'via': config.via, if (on) 'fed': true};

  void _say(String what) {
    // Never an address of a person's, never a whole name.
    if (verbose) stdout.writeln('${_now().toIso8601String()} fed $what');
  }

  // --- what the hub gives it ------------------------------------------------------------------------------------------

  bool? Function(String to, String from, List<int> packet) _deliver = (_, _, _) => null;
  bool Function(String id) _isHere = (_) => false;
  Handles? _handles;

  /// Told by the hub it serves ([Hub]) how a packet is handed to someone here ([Hub.deliver]), who is here, and who
  /// keeps the usernames.
  void bind({required bool? Function(String to, String from, List<int> packet) deliver, required bool Function(String id) isHere, Handles? handles}) {
    _deliver = deliver;
    _isHere = isHere;
    _handles = handles;
  }

  Timer? _ticker;
  Timer? _saver;

  /// Starts its clock: once a second it does what is due ([tick]), and a relay with a `via` dials it.
  void start() {
    for (final p in config.problems) {
      stderr.writeln('relay: $p');
    }
    if (on && config.publicHub.isEmpty && config.via.isEmpty) {
      stderr.writeln('relay: GHOST_FED is on, but GHOST_PUBLIC_HUB is not set: this relay can ask other relays who someone is, but can\'t pass its people\'s packets to them');
    }
    if (!on) return;
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
    tick();
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _saver?.cancel();
    _saver = null;
    homes.save();
    for (final l in _links.toList()) {
      l.socket.close(WebSocketStatus.goingAway);
    }
  }

  void _changed() {
    if (homes.file == null || !homes.dirty) return;
    _saver ??= Timer(const Duration(seconds: 2), () {
      _saver = null;
      homes.save();
    });
  }

  // --- who may link ---------------------------------------------------------------------------------------------------

  bool _listed(Set<String> list, {String? relay, Uri? url}) {
    if (relay != null && list.contains(relay)) return true;
    if (url == null) return false;
    final port = url.hasPort ? url.port : (url.scheme == 'wss' ? 443 : 80);
    return list.contains(url.host) || list.contains('${url.host}:$port');
  }

  /// Whether this relay links with the one named [relay] (where its name is known) at [url] (where it has one).
  bool _mayLink({String? relay, Uri? url}) {
    if (!on || _listed(config.block, relay: relay, url: url)) return false;
    if (url != null && config.via.isNotEmpty && '$url' == config.via) return true;
    return config.mode == FedMode.open || _listed(config.allow, relay: relay, url: url);
  }

  // --- limits ---------------------------------------------------------------------------------------------------------

  final Map<String, _Meter> _meters = {};
  final Map<String, _Count> _checks = {};
  final _Count _checksNow = _Count();
  final _Count _hellos = _Count();

  _Meter _meter(String relay) {
    final m = _meters.remove(relay) ?? _Meter();
    _meters[relay] = m;
    while (_meters.length > 1024) {
      _meters.remove(_meters.keys.first);
    }
    return m;
  }

  /// Whether one more record may be checked for [who] (an install's name, or `relay:` and a relay's) now.
  bool _mayCheck(String who) {
    final now = _now();
    if (!_checksNow.take(now, const Duration(seconds: 1), checksASecond)) return false;
    final c = _checks.remove(who) ?? _Count();
    _checks[who] = c;
    while (_checks.length > 50000) {
      _checks.remove(_checks.keys.first);
    }
    return c.take(now, const Duration(hours: 1), checksAnHour);
  }

  /// Takes a record someone gave, where it checks out and is newer: `kept`, `held` (nothing newer in it), `busy` (too
  /// many checks just now: give it again later), or why it is not a record at all.
  String _takeRecord(Object? json, {required String from, bool byOwner = false}) {
    if (json is! Map) return 'shape';
    final a = json['a'], n = json['n'], s = json['s'];
    // The very record held already needs no checking again: what an app says at every sign-in.
    if (a is String && n is int && s is String && s.length <= 128) {
      try {
        if (homes.holds(a, n, base64Decode(s))) {
          final held = homes.of(a)!;
          if (byOwner && a == from) {
            homes.keep(held, byOwner: true);
            _changed();
          }
          return 'held';
        }
      } catch (_) {}
    }
    if (!_mayCheck(from)) return 'busy';
    final read = HomeRecord.read(json, now: _now());
    final rec = read.rec;
    if (rec == null) return read.err!;
    final kept = homes.keep(rec, byOwner: byOwner && rec.a == from);
    _changed();
    if (_wanting > 0) _retryWanting(rec.a);
    return kept ? 'kept' : 'held';
  }

  // --- what an app says -------------------------------------------------------------------------------------------------

  /// Whether what an app said is federation's to answer: a home record given or asked for, or a name on another relay.
  static bool takes(Map said) => said['dir'] == 'home' || said['dir'] == 'home?' || (said['dir'] == 'whois' && said['at'] is String);

  /// Something the signed-in install [id] said that [takes] is true of; the answer goes to [tell].
  void said(String id, Map said, void Function(Map<String, Object?>) tell) {
    switch (said['dir']) {
      case 'home':
        // Its own record, or a friend's so this relay can route to them: kept where it checks out and is newer.
        final rec = said['rec'];
        final a = rec is Map && rec['a'] is String ? rec['a'] as String : null;
        final took = _takeRecord(rec, from: id, byOwner: true);
        if (took == 'kept' || took == 'held') {
          tell({'dir': 'home', 'a': a, 'ok': true, 'n': homes.of(a!)?.n});
        } else {
          tell({'dir': 'home', 'a': ?a, 'ok': false, 'err': took == 'busy' ? 'busy' : 'bad'});
        }
      case 'home?':
        final a = said['a'];
        if (!_hex(a, 32)) return tell({'dir': 'home?', 'a': a, 'none': true});
        // Asking after someone else's is a lookup, held to the same limit as asking who a username is.
        if (a != id && !_mayLookUp(id)) return tell({'dir': 'err', 'about': 'home?', 'err': 'Too many lookups. Try again in a while.'});
        final rec = homes.of(a as String);
        tell({'dir': 'home?', 'a': a, if (rec == null) 'none': true else 'rec': rec.toJson()});
      case 'whois':
        _whoisFromApp(id, said, tell);
    }
  }

  final Map<String, _Count> _lookups = {};

  /// The existing limit on lookups ([Handles.lookupsAnHour]), kept by the handles where there are any.
  bool _mayLookUp(String id) {
    final h = _handles;
    if (h != null) return h.mayLookUp(id);
    final c = _lookups.remove(id) ?? _Count();
    _lookups[id] = c;
    while (_lookups.length > 50000) {
      _lookups.remove(_lookups.keys.first);
    }
    return c.take(_now(), const Duration(hours: 1), Handles.lookupsAnHour);
  }

  /// The hub's address `at` names (`relay.example`, or with a port): `wss://relay.example/hub`. Null where it is not
  /// a host.
  static String? hubAt(String at) {
    final host = at.trim().toLowerCase();
    if (host.isEmpty || host.length > 120 || !FedConfig._hostAndPort.hasMatch(host)) return null;
    return canonicalHub('wss://$host/hub');
  }

  /// `{"dir":"whois","name":"maya","at":"relay.example"}`: who has that username on that relay. Asked of it over a
  /// link, and answered with what was asked (`name`, `at`) and `id`, `key`, and `home` where that relay holds their
  /// record; or `none`, with `why` where it is not that nobody has the name: `off` (this relay doesn't talk to that
  /// one), `refused` (that one won't talk to this), `down` (it couldn't be reached), `busy`.
  void _whoisFromApp(String asker, Map said, void Function(Map<String, Object?>) tell) {
    final name = said['name'], at = said['at'];
    Map<String, Object?> none([String? why]) => {'dir': 'whois', 'name': name is String ? Handles.tidyName(name) : name, 'at': at, 'none': true, 'why': ?why};
    final url = at is String ? hubAt(at) : null;
    if (name is! String || !Handles.goodName(name) || url == null) return tell(none());
    // This relay itself: an ordinary lookup, under its own limit, answered with what was asked.
    if (_isSelfUrl(url)) {
      final h = _handles;
      if (h == null) return tell(none());
      unawaited(h.said(asker, {'dir': 'whois', 'name': name}, (m) => tell(m['dir'] == 'whois' ? {...m, 'at': at, 'here': true} : m)));
      return;
    }
    if (!_mayLookUp(asker)) return tell({'dir': 'err', 'about': 'whois', 'err': 'Too many lookups. Try again in a while.'});
    final uri = Uri.parse(url);
    if (!on || !_mayLink(url: uri) || guard.shape(uri) != null) return tell(none('off'));
    final peer = _peerAt(url);
    if (peer == null) return tell(none('busy'));
    if (_refusedNow(peer)) return tell(none('refused'));
    // Not reachable a moment ago, and not due to be tried again yet: said now, not after a wait.
    if (_linkFor(peer) == null && !peer.dialling && peer.nextTry != null && _now().isBefore(peer.nextTry!)) return tell(none('down'));
    if (peer.asks.length >= asksWaiting) return tell(none('busy'));
    peer.asks.add(_Ask(Handles.tidyName(name), _now(), (m) {
      final id = m['id'], key = m['key'];
      if (m['none'] == true || id is! String || key is! String) return tell(none(m['why'] is String ? m['why'] as String : null));
      // Nothing is taken on that relay's say-so but which key holds the name: the name it gives must be that key's.
      try {
        if (Hub.nameOf(base64Decode(key)) != id) return tell(none());
      } catch (_) {
        return tell(none());
      }
      // Their record, where that relay gave one that is theirs: kept here too, so a packet to them can be routed.
      Map<String, Object>? home;
      final rec = m['home'];
      if (rec is Map && rec['a'] == id && rec['k'] == key) {
        final took = _takeRecord(rec, from: 'relay:${peer.key}');
        if (took == 'kept' || took == 'held') home = homes.of(id)?.toJson();
      }
      tell({'dir': 'whois', 'name': Handles.tidyName(name), 'at': at, 'id': id, 'key': key, 'home': ?home});
    }));
    peer.lastUsed = _now();
    _pump(peer);
  }

  // --- passing a packet on ----------------------------------------------------------------------------------------------

  final Map<String, _Peer> _peers = {};
  int _queued = 0;
  int _queuedForOthers = 0;
  int _wanting = 0;

  /// How much waits here for other relays, in bytes, and for how many.
  int get waiting => _queued;
  int waitingFor(String url) => _peers['u:$url']?.queue.length ?? 0;
  int waitingForRelay(String relay) => _peers['r:$relay']?.queue.length ?? 0;

  /// How many links are open, and whether one is with the relay named [relay].
  int get links => _links.length;
  bool linkedWith(String relay) => _links.any((l) => l.id == relay && l.socket.isOpen);

  final Map<String, DateTime> _selfUrls = {};

  bool _isSelfUrl(String url) => url == config.publicHub || _selfUrls.containsKey(url);
  bool _isSelf(HomeAddress a) => a.url != null ? _isSelfUrl(a.url!) : a.relay == id;

  /// The relay waited on at [url], made where there is room for one more.
  _Peer? _peerAt(String url) => _peer('u:$url', url: Uri.parse(url));

  /// A relay with no address, known by its name alone: one that dials this relay and stays linked.
  _Peer? _peerNamed(String relay) => _peer('r:$relay', relay: relay);

  _Peer? _peer(String key, {Uri? url, String? relay}) {
    final had = _peers[key];
    if (had != null) return had;
    if (_peers.length >= maxPeers) {
      // Room is made by letting go of one nothing waits for and nothing is linked to.
      final idle = _peers.values.where((p) => p.idle && _linkFor(p) == null && p.key != 'u:${config.via}').toList()..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
      if (idle.isEmpty) return null;
      _peers.remove(idle.first.key);
    }
    return _peers[key] = _Peer(key, url: url, relay: relay, lastUsed: _now());
  }

  bool _refusedNow(_Peer peer) => peer.refusedUntil != null && _now().isBefore(peer.refusedUntil!);

  /// Where a packet for the account [rec] is for goes: null for "here, as before" (the record names this relay), else
  /// the relay to pass it to and how; `far` where it names nowhere this relay will pass it.
  ({_Peer? peer, int kind, String? relay, bool far, bool full})? _targetOf(HomeRecord rec, {bool forStanding = false}) {
    const far = (peer: null, kind: 0, relay: null, far: true, full: false);
    const full = (peer: null, kind: 0, relay: null, far: false, full: true);
    final addresses = rec.addresses;
    if (addresses.any(_isSelf)) return null;
    // A relay with no address of its own: everything else goes through the relay it stays linked to.
    if (_hosted) {
      final via = _peerAt(config.via);
      return via == null ? full : (peer: via, kind: toRelay, relay: null, far: false, full: false);
    }
    for (final a in addresses) {
      final url = a.url ?? a.via;
      if (url == null) continue;
      if (a.url == null && _isSelfUrl(url)) {
        // Someone on a relay that stays linked to this one: over that link, or kept for it.
        final p = _peerNamed(a.relay!);
        return p == null ? full : (peer: p, kind: toRelay, relay: null, far: false, full: false);
      }
      // What a relay linked to this one sent is passed to the relay its person lives on, never to a relay linked to
      // that one: two links at most.
      if (a.url == null && forStanding) continue;
      final uri = Uri.parse(url);
      if (!_mayLink(url: uri) || guard.shape(uri) != null) continue;
      final p = _peerAt(url);
      if (p == null) return full;
      return (peer: p, kind: a.url == null ? toRelayVia : toRelay, relay: a.url == null ? a.relay : null, far: false, full: false);
    }
    return far;
  }

  /// Takes a packet from [from] (someone signed in here) for [to], whom nobody is connected as here, where [to]'s home
  /// record names another relay: it is passed to that relay, or waits here for it. False where it is not this one's
  /// to pass on (no record, or the record names this relay): the hub keeps it, as it always did.
  ///
  /// [answer] is told once what became of it: `here` true (the other relay handed it to them) or false (kept, there or
  /// here), or with `err` why it was not taken (`full`, `far`: their relay is one this relay doesn't pass to,
  /// `refused`).
  bool pass(String to, String from, List<int> packet, void Function(bool? here, [String? err]) answer) {
    if (!on) return false;
    final rec = homes.of(to);
    if (rec == null) return false;
    return _send(rec, to, from, packet, answer);
  }

  bool _send(HomeRecord rec, String to, String from, List<int> packet, void Function(bool? here, [String? err]) answer, {bool forStanding = false}) {
    final target = _targetOf(rec, forStanding: forStanding);
    if (target == null) return false;
    if (target.far) {
      answer(null, 'far');
      return true;
    }
    final peer = target.peer;
    if (target.full || peer == null) {
      answer(null, 'full');
      return true;
    }
    if (_refusedNow(peer)) {
      answer(null, 'far');
      return true;
    }
    final out = _Out(peer, target.kind, to, from, target.relay, Uint8List.fromList(packet), _now(), answer, forOthers: forStanding);
    if (!_enqueue(peer, out)) {
      answer(null, 'full');
      return true;
    }
    _pump(peer);
    return true;
  }

  bool _enqueue(_Peer peer, _Out out) {
    if (peer.queue.length >= queuePackets || peer.bytes + out.size > queueBytes || _queued + out.size > 2 * queuedBytes) return false;
    // With no link to its relay it will wait: held to what may wait, and what another relay asked to be kept to its
    // share of that.
    if (_linkFor(peer) == null && (_queued + out.size > queuedBytes || (out.forOthers && _queuedForOthers + out.size > queuedBytes ~/ 4))) return false;
    peer.queue.add(out);
    peer.bytes += out.size;
    _queued += out.size;
    if (out.forOthers) _queuedForOthers += out.size;
    peer.lastUsed = _now();
    return true;
  }

  void _dequeue(_Out out) {
    final peer = out.peer;
    if (!peer.queue.remove(out)) return;
    peer.bytes -= out.size;
    _queued -= out.size;
    if (out.forOthers) _queuedForOthers -= out.size;
    out.flying?.flying.removeWhere((_, o) => identical(o, out));
    out.flying = null;
    if (out.wantsHome) {
      out.wantsHome = false;
      _wanting--;
    }
  }

  /// The open link to [peer]: the newest whose proven relay is at its address, or has its name.
  _Link? _linkFor(_Peer peer) {
    for (final l in _links.reversed) {
      if (!l.socket.isOpen) continue;
      if (peer.url != null ? l.url == '${peer.url}' : l.id == peer.relay) return l;
    }
    return null;
  }

  /// Sends what waits for [peer] over its link, as far as the window allows; with no link, one is asked for.
  void _pump(_Peer peer) {
    final now = _now();
    final link = _linkFor(peer);
    if (link == null) {
      _wantLink(peer);
      // A relay that can only dial this one, or one that could not be reached a moment ago and is not being tried
      // just now: what is for it is kept, and its sender told so at once, not after a wait that can tell it nothing.
      if (peer.url == null || (peer.failures > 0 && !peer.dialling)) {
        for (final out in peer.queue) {
          out.tell(false);
        }
      }
      return;
    }
    for (final ask in peer.asks) {
      if (ask.sent) continue;
      ask.sent = true;
      ask.q = ++link.seq;
      link.asked[ask.q] = ask;
      _tell(link, {'fed': 'whois', 'q': ask.q, 'name': ask.name});
      link.used = now;
    }
    if (peer.pausedUntil != null && now.isBefore(peer.pausedUntil!)) return;
    for (final out in peer.queue) {
      if (link.flying.length >= window) break;
      if (out.flying != null || out.wantsHome) continue;
      _fly(link, out);
    }
  }

  /// Says [a]'s record on [link] where it is held and has not been said there: so the other relay can see whom this
  /// one speaks for, or where someone lives, without having to refuse first.
  void _give(_Link link, String a, {bool again = false}) {
    final rec = homes.of(a);
    if (rec == null) return;
    final tag = '$a:${rec.n}';
    if (!again && link.gave.contains(tag)) return;
    link.gave.add(tag);
    while (link.gave.length > 4000) {
      link.gave.remove(link.gave.first);
    }
    _tell(link, {'fed': 'home', 'rec': rec.toJson()});
  }

  void _fly(_Link link, _Out out) {
    _give(link, out.from);
    // To a relay that must itself find where they live (the relay this one stays linked to, or the one theirs does).
    if (out.kind == toRelayVia || link.isVia) _give(link, out.to);
    final n = link.seq = (link.seq + 1) & 0x7fffffff;
    final head = ByteData(5)
      ..setUint8(0, out.kind)
      ..setUint32(1, n);
    link.flying[n] = out;
    out.flying = link;
    out.sentAt = _now();
    link.used = out.sentAt!;
    try {
      link.socket.add(Uint8List.fromList([...head.buffer.asUint8List(), ..._unhex(out.to), ..._unhex(out.from), if (out.kind == toRelayVia) ..._unhex(out.relay!), ...out.packet]));
    } catch (_) {}
  }

  void _tell(_Link link, Map<String, Object?> what) {
    if (!link.socket.isOpen) return;
    try {
      link.socket.add(jsonEncode(what));
    } catch (_) {}
  }

  /// What the other relay said of a packet sent it.
  void _answered(_Link link, Map m) {
    final acked = m.containsKey('ack');
    final n = acked ? m['ack'] : m['nak'];
    final out = link.flying.remove(n);
    if (out == null) return;
    out.flying = null;
    final peer = out.peer;
    if (acked) {
      _dequeue(out);
      out.tell(m['here'] == true);
      _pump(peer);
      return;
    }
    switch (m['err']) {
      case 'home' || 'to' || 'moved':
        // Refused for want of a record: of the sender's, naming this relay (`home`); of where the other lives
        // (`to`); or the other relay holds one that says they live elsewhere (`moved`, and it has just said which).
        final about = m['err'] == 'home' ? out.from : out.to;
        if (m['err'] == 'moved' && !out.rerouted) {
          // Routed again by what is held now (the other relay has just said where they live).
          out.rerouted = true;
          final rec = homes.of(out.to);
          final target = rec == null ? null : _targetOf(rec);
          if (rec != null && target == null) {
            // Here, by the newer record: handed over or kept as any packet for someone here.
            _dequeue(out);
            final did = _deliver(out.to, out.from, out.packet);
            out.tell(did, did == null ? 'full' : null);
            _pump(peer);
            return;
          }
          if (target != null && target.peer != null && !identical(target.peer, peer)) {
            _dequeue(out);
            final moved = _Out(target.peer!, target.kind, out.to, out.from, target.relay, out.packet, out.at, out.answer, forOthers: out.forOthers)
              ..rerouted = true
              ..answered = out.answered;
            if (_enqueue(target.peer!, moved)) {
              _pump(target.peer!);
            } else {
              moved.tell(null, 'full');
            }
            _pump(peer);
            return;
          }
        }
        if (!out.again) {
          out.again = true;
          if (homes.of(about) != null) {
            _give(link, about, again: true);
            _fly(link, out);
            return;
          }
          if (m['err'] == 'home') {
            // None is held to give: it waits for its sender's own, which their app gives as it signs in.
            out.wantsHome = true;
            _wanting++;
            return;
          }
        }
        _dequeue(out);
        out.tell(null, 'refused');
      case 'limit':
        // Over what that relay takes from this one: it waits here a while, in its place.
        peer.pausedUntil = _now().add(const Duration(seconds: 15));
        return;
      case 'full':
        _dequeue(out);
        out.tell(null, 'full');
      default:
        _dequeue(out);
        out.tell(null, 'refused');
    }
    _pump(peer);
  }

  /// [a]'s record has just come: what waited for it goes again.
  void _retryWanting(String a) {
    for (final peer in _peers.values.toList()) {
      var any = false;
      for (final out in peer.queue) {
        if (out.wantsHome && out.from == a) {
          out.wantsHome = false;
          out.again = false;
          _wanting--;
          any = true;
        }
      }
      if (any) _pump(peer);
    }
  }

  // --- links ------------------------------------------------------------------------------------------------------------

  final List<_Link> _links = [];
  final List<_Hello> _hellosOut = [];
  final LinkedHashMap<String, ({String key, DateTime at})> _seenAt = LinkedHashMap();

  void _believe(String url, String key) {
    _seenAt.remove(url);
    _seenAt[url] = (key: key, at: _now());
    while (_seenAt.length > 1024) {
      _seenAt.remove(_seenAt.keys.first);
    }
  }

  /// Makes room for one more link: at the most, the one used longest ago that nothing is waiting on goes.
  bool _room() {
    if (_links.length < maxLinks) return true;
    final idle = _links.where((l) => l.flying.isEmpty && !l.isVia).toList()..sort((a, b) => a.used.compareTo(b.used));
    if (idle.isEmpty) return false;
    idle.first.socket.close(1000, 'room');
    _lost(idle.first);
    return _links.length < maxLinks;
  }

  /// Asks for a link to [peer]: dialled now where it has an address, is not being dialled, and is due.
  void _wantLink(_Peer peer) {
    final url = peer.url;
    if (url == null || peer.dialling) return;
    final now = _now();
    if (peer.nextTry != null && now.isBefore(peer.nextTry!)) return;
    if (!_mayLink(url: url) || guard.shape(url) != null) return _failed(peer, 'off', refused: true);
    if (!_room()) return _failed(peer, 'busy');
    peer.dialling = true;
    unawaited(_open(peer, url));
  }

  Future<void> _open(_Peer peer, Uri url) async {
    final HubSocket socket;
    try {
      socket = await _dial(url);
    } catch (e) {
      _say('could not dial ${url.host}: ${'$e'.split('\n').first}');
      return _failed(peer, 'down');
    }
    final hello = _Hello(peer, socket, _now().add(helloWithin));
    _hellosOut.add(hello);
    socket.incoming.listen((data) => _helloHeard(hello, data), onDone: () => _helloGone(hello), onError: (_) => _helloGone(hello), cancelOnError: true);
  }

  void _helloGone(_Hello hello) {
    _hellosOut.remove(hello);
    final link = hello.link;
    if (link != null) return _lost(link);
    if (!hello.done) {
      hello.done = true;
      _failed(hello.peer, 'down');
    }
  }

  /// A dial that came to nothing: tried again later, later each time; what was asked of that relay is answered.
  void _failed(_Peer peer, String why, {bool refused = false}) {
    final now = _now();
    peer.dialling = false;
    peer.failures++;
    peer.nextTry = now.add(backoff(peer.failures));
    if (refused) peer.refusedUntil = now.add(refusedFor);
    for (final ask in peer.asks.toList()) {
      ask.answer({'none': true, 'why': refused ? (why == 'off' ? 'off' : 'refused') : why});
    }
    peer.asks.clear();
    for (final out in peer.queue.toList()) {
      if (out.answered) continue;
      if (refused) {
        // What waits for a relay that said no is not kept as though it were only away.
        _dequeue(out);
        out.tell(null, 'far');
      } else {
        // Unreachable: it waits here, and its sender is told it is kept.
        out.tell(false);
      }
    }
  }

  /// What the relay dialled says before the link is made: its hub's hello, then its answer to this relay's.
  void _helloHeard(_Hello hello, Object? data) {
    final link = hello.link;
    if (link != null) return _heard(link, data);
    if (hello.done) return;
    void no(String why, {bool refused = true}) {
      hello.done = true;
      _hellosOut.remove(hello);
      hello.socket.close(1000, 'no');
      _failed(hello.peer, why, refused: refused);
    }

    Map? m;
    try {
      if (data is String && data.length <= 4096) m = jsonDecode(data) as Map;
    } catch (_) {}
    if (m == null) return no('not a relay');
    final peer = hello.peer;
    final url = '${peer.url}';
    if (hello.nonce == null) {
      // The hub's hello, as any app is given it: its number, and who the relay is.
      final card = m['relay'];
      final theirs = card is Map ? card['id'] : null, theirKey = card is Map ? card['key'] : null;
      if (!_hex(m['hello'], 64) || !_hex(theirs, 32) || theirKey is! String) return no('not a relay that talks to others');
      final List<int> k;
      try {
        k = base64Decode(theirKey);
      } catch (_) {
        return no('not a relay that talks to others');
      }
      if (k.length != 33 || Hub.nameOf(k) != theirs) return no('not a relay that talks to others');
      if (theirs == id) {
        // This relay itself, by another address: what waits is for people here after all.
        hello.done = true;
        _hellosOut.remove(hello);
        hello.socket.close(1000, 'self');
        return _isMe(peer);
      }
      if (!_mayLink(relay: theirs as String, url: peer.url)) return no('off');
      hello
        ..nonce = _unhex(m['hello'] as String)
        ..id = theirs
        ..key = k
        ..c = [for (var i = 0; i < 32; i++) _random.nextInt(256)];
      final stay = url == config.via;
      final sig = _sign(dialBytes(nonce: hello.nonce!, dialler: id, answerer: theirs, c: hello.c!, url: config.publicHub));
      try {
        hello.socket.add(jsonEncode({'fed': 1, 'id': id, 'key': base64Encode(key), 'sig': base64Encode(sig), if (config.publicHub.isNotEmpty) 'url': config.publicHub, 'c': hexOf(hello.c!), if (stay) 'stay': true}));
      } catch (_) {}
      return;
    }
    // Its answer: yes, signed over this relay's number and both names by the key its hello named; or no.
    if (m['ok'] != true) return no('${m['err'] ?? 'refused'}', refused: m['err'] != 'busy');
    List<int>? sig;
    try {
      sig = base64Decode(m['sig'] as String);
    } catch (_) {}
    if (m['fed'] != 1 || m['id'] != hello.id || sig == null || !P256.verify(hello.key!, answerBytes(c: hello.c!, dialler: id, answerer: hello.id!), sig)) return no('bad answer');
    hello.done = true;
    _hellosOut.remove(hello);
    _believe(url, base64Encode(hello.key!));
    final made = hello.link = _Link(hello.socket, hello.id!, hello.key!, url, _now(), outbound: true, isVia: url == config.via);
    _links.add(made);
    peer
      ..dialling = false
      ..failures = 0
      ..nextTry = null
      ..refusedUntil = null
      ..relay ??= made.id;
    _say('linked with ${made.id.substring(0, 6)} (dialled)');
    _linked(made);
  }

  /// [peer]'s address turned out to be this relay's own: remembered, and what waited for it is handed over here.
  void _isMe(_Peer peer) {
    final url = '${peer.url}';
    _selfUrls.remove(url);
    _selfUrls[url] = _now();
    while (_selfUrls.length > 256) {
      _selfUrls.remove(_selfUrls.keys.first);
    }
    peer.dialling = false;
    for (final out in peer.queue.toList()) {
      _dequeue(out);
      final did = _deliver(out.to, out.from, out.packet);
      out.tell(did, did == null ? 'full' : null);
    }
    for (final ask in peer.asks.toList()) {
      final found = _handles?.holder(ask.name);
      ask.answer(found == null ? {'none': true} : {'id': found.id, 'key': found.key, 'home': ?homes.of(found.id)?.toJson()});
    }
    peer.asks.clear();
    _peers.remove(peer.key);
  }

  /// A link is made: whatever waits for its relay goes.
  void _linked(_Link link) {
    for (final peer in _peers.values.toList()) {
      if (identical(_linkFor(peer), link)) _pump(peer);
    }
  }

  void _lost(_Link link) {
    if (!_links.remove(link)) return;
    _say('link with ${link.id.substring(0, 6)} closed');
    // What was on it unanswered waits again, and goes by the next link.
    for (final out in link.flying.values) {
      out.flying = null;
    }
    link.flying.clear();
    for (final ask in link.asked.values.toList()) {
      ask.answer({'none': true, 'why': 'down'});
    }
    link.asked.clear();
    for (final peer in _peers.values) {
      peer.asks.removeWhere((a) => a.done);
    }
  }

  /// The key the hub at [url] says is its relay's, as this relay sees it by dialling there itself; null where it
  /// can't be dialled, is not a relay, or says none. Believed for a day.
  Future<String?> _keyAt(String url, {bool again = false}) async {
    final seen = _seenAt[url];
    if (!again && seen != null && _now().difference(seen.at) < believedFor) return seen.key;
    final uri = Uri.parse(url);
    if (guard.shape(uri) != null) return null;
    final HubSocket socket;
    try {
      socket = await _dial(uri);
    } catch (_) {
      return null;
    }
    final found = Completer<String?>();
    final look = _Look(socket, _now().add(helloWithin));
    _looks.add(look);
    socket.incoming.listen((data) {
      if (found.isCompleted) return;
      String? key;
      try {
        final m = data is String && data.length <= 4096 ? jsonDecode(data) as Map : null;
        final card = m?['relay'];
        if (_hex(m?['hello'], 64) && card is Map && card['key'] is String && base64Decode(card['key'] as String).length == 33) key = card['key'] as String;
      } catch (_) {}
      found.complete(key);
    }, onDone: () => found.isCompleted ? null : found.complete(null), onError: (_) => found.isCompleted ? null : found.complete(null), cancelOnError: true);
    final key = await found.future;
    _looks.remove(look);
    unawaited(socket.close(1000, 'looked').catchError((_) {}));
    if (key != null) _believe(url, key);
    return key;
  }

  final List<_Look> _looks = [];

  /// Another relay's hello, said in place of an app's ([Hub.attach] hands it over): the link is made where it proves
  /// its key, may link with this relay, and the address it claims is its own.
  FedEnd incoming(HubSocket socket, Map hello, List<int> nonce) {
    final end = _In(this, socket);
    unawaited(_admit(end, hello, nonce));
    return end;
  }

  Future<void> _admit(_In end, Map hello, List<int> nonce) async {
    final socket = end.socket;
    void no(String why) {
      try {
        if (socket.isOpen) socket.add(jsonEncode({'ok': false, 'err': why}));
      } catch (_) {}
      socket.close(4403, why);
    }

    if (!on) return no('fed off');
    if (!_hellos.take(_now(), const Duration(minutes: 1), hellosAMinute)) return no('busy');
    final theirs = hello['id'], said = hello['url'];
    List<int>? k, sig;
    try {
      k = base64Decode(hello['key'] as String);
      sig = base64Decode(hello['sig'] as String);
    } catch (_) {}
    if (k == null || sig == null || k.length != 33 || sig.length != 64 || !_hex(theirs, 32) || !_hex(hello['c'], 64) || Hub.nameOf(k) != theirs || (said != null && (said is! String || said.length > HomeRecord.maxAddress))) return no('bad hello');
    if (theirs == id) return no('self');
    final c = _unhex(hello['c'] as String);
    if (!P256.verify(k, dialBytes(nonce: nonce, dialler: theirs as String, answerer: id, c: c, url: said is String ? said : ''), sig)) return no('bad hello');
    // The address it claims, where it claims one: a hub's, written as hubs' addresses are compared.
    final url = said is String ? canonicalHub(said) : null;
    if (said is String && (url == null || url != said)) return no('bad address');
    final uri = url == null ? null : Uri.parse(url);
    if (!_mayLink(relay: theirs, url: uri)) return no(_listed(config.block, relay: theirs, url: uri) ? 'blocked' : 'not listed');
    if (url != null) {
      // Believed only once this relay has dialled that address itself and seen the same key there.
      if (guard.shape(uri!) != null) return no('bad address');
      var seen = await _keyAt(url);
      // Another key was seen there a while ago: looked at once more, since a relay may have been given a new key.
      final at = _seenAt[url]?.at;
      if (seen != null && seen != base64Encode(k) && at != null && _now().difference(at) >= const Duration(minutes: 5)) seen = await _keyAt(url, again: true);
      if (end.left || !socket.isOpen) return;
      if (seen != base64Encode(k)) return no('address');
    }
    if (!_room()) return no('busy');
    final sign = _sign(answerBytes(c: c, dialler: theirs, answerer: id));
    try {
      socket.add(jsonEncode({'ok': true, 'fed': 1, 'id': id, 'key': base64Encode(key), 'sig': base64Encode(sign)}));
    } catch (_) {}
    final link = _Link(socket, theirs, k, url, _now(), outbound: false, standing: url == null && hello['stay'] == true);
    _links.add(link);
    end.link = link;
    _say('linked with ${link.id.substring(0, 6)} (it dialled${link.standing ? ', and stays' : ''})');
    _linked(link);
  }

  // --- what a linked relay says ---------------------------------------------------------------------------------------

  /// Whether [link]'s relay speaks for [from]: their home record names it. A relay's own address ([_Link.url], which
  /// this relay has seen its key at), its name where it is one hosted from an app, or the relay such a one stays
  /// linked to. The relay this one itself stays linked to is believed as an app believes its relay.
  bool _speaksFor(_Link link, String from) {
    if (link.isVia && _hosted) return true;
    final rec = homes.of(from);
    if (rec == null) return false;
    for (final a in rec.addresses) {
      if (a.url != null) {
        if (link.url != null && a.url == link.url) return true;
      } else if (a.relay == link.id || (a.via != null && link.url != null && a.via == link.url)) {
        return true;
      }
    }
    return false;
  }

  void _heard(_Link link, Object? data) {
    // Far past anything a link carries: not a relay that keeps the rules, and nothing more is read from it.
    if ((data is List<int> && data.length > Hub.maxPacket + 256) || (data is String && data.length > 65536)) {
      link.socket.close(WebSocketStatus.messageTooBig, 'too big');
      return _lost(link);
    }
    if (data is List<int>) {
      if (data.isEmpty) return;
      if (data[0] == toRelay) return _took(link, data, 37, null);
      if (data[0] == toRelayVia && data.length > 53) return _took(link, data, 53, hexOf(data.sublist(37, 53)));
      return;
    }
    Map? m;
    try {
      if (data is String && data.length <= 8192) m = jsonDecode(data) as Map;
    } catch (_) {}
    if (m == null) return;
    if (m.containsKey('ack') || m.containsKey('nak')) return _answered(link, m);
    if (m.containsKey('ping')) return _tell(link, {'pong': m['ping']});
    switch (m['fed']) {
      case 'home':
        // A record it gives: to show whom it speaks for, or where someone lives. Checked like any other.
        final meter = _meter(link.id);
        if (!meter.records.take(_now(), const Duration(minutes: 1), recordsAMinute)) return;
        _takeRecord(m['rec'], from: 'relay:${link.id}');
      case 'whois':
        final q = m['q'];
        if (m['name'] is String) {
          // It asks who has a username here.
          if (q is! int) return;
          if (!_meter(link.id).lookups.take(_now(), const Duration(hours: 1), config.lookupsAnHour)) return _tell(link, {'fed': 'whois', 'q': q, 'none': true, 'why': 'busy'});
          final found = _handles?.holder(m['name'] as String);
          link.used = _now();
          _tell(link, found == null ? {'fed': 'whois', 'q': q, 'none': true} : {'fed': 'whois', 'q': q, 'id': found.id, 'key': found.key, 'home': ?homes.of(found.id)?.toJson()});
        } else {
          // It answers one this relay asked.
          link.asked.remove(q)?.answer(m);
          for (final peer in _peers.values) {
            peer.asks.removeWhere((a) => a.done);
          }
        }
    }
  }

  /// A packet another relay passed here: `[5][number][to][from][packet]`, or `[6]` with the name of a relay linked
  /// to this one before the packet ([relay]).
  void _took(_Link link, List<int> data, int head, String? relay) {
    if (data.length <= head) return;
    final n = ByteData.sublistView(Uint8List.fromList(data.sublist(1, 5))).getUint32(0);
    void nak(String why) => _tell(link, {'nak': n, 'err': why});
    final now = _now();
    final meter = _meter(link.id);
    if (!meter.packets.take(now, const Duration(minutes: 1), config.packetsAMinute) || !meter.bytes.take(now, const Duration(days: 1), config.bytesADay, by: data.length)) return nak('limit');
    if (data.length - head > Hub.maxPacket + 32) return nak('big');
    final to = hexOf(data.sublist(5, 21)), from = hexOf(data.sublist(21, 37));
    // A relay speaks only for its own people.
    if (!_speaksFor(link, from)) return nak('home');
    link.used = now;
    final packet = data.sublist(head);
    void answer(bool? here, [String? err]) => err != null ? nak(err) : _tell(link, {'ack': n, 'here': here == true});
    if (relay != null) {
      // For someone on a relay linked to this one, as their record must say: over that link, or kept for it. Never
      // to a relay this one would have to dial.
      final rec = homes.of(to);
      if (rec == null || !rec.addresses.any((a) => a.relay == relay && a.via != null && _isSelfUrl(a.via!))) return nak('to');
      // No more than a quarter of the relays this one waits on are ones another relay named.
      if (!_peers.containsKey('r:$relay') && _peers.keys.where((k) => k.startsWith('r:')).length >= maxPeers ~/ 4) return nak('full');
      final peer = _peerNamed(relay);
      if (peer == null) return nak('full');
      final out = _Out(peer, toRelay, to, from, null, Uint8List.fromList(packet), now, answer, forOthers: true);
      if (!_enqueue(peer, out)) return nak('full');
      return _pump(peer);
    }
    if (!_isHere(to)) {
      final rec = homes.of(to);
      if (rec != null && !rec.addresses.any(_isSelf)) {
        // They live elsewhere, by the record held here. From a relay that stays linked to this one, for its own
        // people who name this relay as their way out: passed on, as for someone signed in here.
        final theirs = homes.of(from);
        if (link.standing && theirs != null && theirs.addresses.any((a) => a.relay == link.id && a.via != null && _isSelfUrl(a.via!))) {
          if (_send(rec, to, from, packet, answer, forStanding: true)) return;
        } else if (!(link.isVia && _hosted)) {
          // From any other relay it goes no further: that relay is told where they live now, and routes it itself.
          _give(link, to, again: true);
          return nak('moved');
        }
      }
    }
    // Handed to their devices here or kept for them, exactly as one from a connection here.
    final did = _deliver(to, from, packet);
    answer(did, did == null ? 'full' : null);
  }

  // --- what is due --------------------------------------------------------------------------------------------------

  /// Does what the clock says is due: tells senders whose packets have waited [answerWithin] that they are kept, lets
  /// go of what waited [queueFor], closes links nothing has crossed for [idleFor] and hellos that never finished,
  /// and dials again the relays that are due. The relay calls it once a second ([start]); a test calls it itself.
  void tick() {
    final now = _now();
    for (final hello in _hellosOut.toList()) {
      if (!hello.done && !now.isBefore(hello.deadline)) hello.socket.close(1000, 'slow');
    }
    for (final look in _looks.toList()) {
      if (!now.isBefore(look.deadline)) look.socket.close(1000, 'slow');
    }
    for (final link in _links.toList()) {
      if (!link.socket.isOpen) {
        _lost(link);
        continue;
      }
      final stuck = link.flying.values.any((o) => o.sentAt != null && now.difference(o.sentAt!) >= stuckAfter);
      final idle = !link.standing && !link.isVia && link.flying.isEmpty && link.asked.isEmpty && now.difference(link.used) >= idleFor;
      if (stuck || idle) {
        link.socket.close(1000, stuck ? 'stuck' : 'idle');
        _lost(link);
      }
      for (final ask in link.asked.values.toList()) {
        if (now.difference(ask.at) >= whoisWithin) {
          link.asked.remove(ask.q);
          ask.answer({'none': true, 'why': 'down'});
        }
      }
    }
    for (final peer in _peers.values.toList()) {
      for (final out in peer.queue.toList()) {
        if (now.difference(out.at) >= queueFor) {
          _dequeue(out);
          out.tell(false);
        } else if (!out.answered && now.difference(out.at) >= answerWithin) {
          out.tell(false);
        }
      }
      for (final ask in peer.asks.toList()) {
        if (!ask.done && now.difference(ask.at) >= whoisWithin) ask.answer({'none': true, 'why': 'down'});
      }
      peer.asks.removeWhere((a) => a.done);
      if (peer.queue.isNotEmpty || peer.asks.isNotEmpty) {
        _pump(peer);
      } else if (peer.key != 'u:${config.via}' && !peer.dialling && _linkFor(peer) == null && now.difference(peer.lastUsed) >= const Duration(hours: 1)) {
        _peers.remove(peer.key);
      }
    }
    // The relay this one stays linked to: dialled whenever the link is not up.
    if (on && config.via.isNotEmpty) {
      final via = _peerAt(config.via);
      if (via != null && _linkFor(via) == null) _wantLink(via);
    }
    _selfUrls.removeWhere((_, at) => now.difference(at) >= believedFor);
    _seenAt.removeWhere((_, seen) => now.difference(seen.at) >= believedFor);
    _checks.removeWhere((_, c) => c.over(now, const Duration(hours: 1)));
    _lookups.removeWhere((_, c) => c.over(now, const Duration(hours: 1)));
    _meters.removeWhere((_, m) => m.over(now));
  }
}

/// So many in a stretch of time, counted from the first: [take] says whether there is room for one more.
class _Count {
  DateTime? _since;
  int _n = 0;

  bool take(DateTime now, Duration every, int most, {int by = 1}) {
    if (over(now, every)) {
      _since = now;
      _n = 0;
    }
    if (_n + by > most) return false;
    _n += by;
    return true;
  }

  /// Whether the stretch it was counting in has ended.
  bool over(DateTime now, Duration every) => _since == null || now.difference(_since!) >= every;
}

/// What one linked relay has sent lately.
class _Meter {
  final packets = _Count();
  final bytes = _Count();
  final lookups = _Count();
  final records = _Count();

  /// Whether nothing is being counted for it any more.
  bool over(DateTime now) => packets.over(now, const Duration(minutes: 1)) && bytes.over(now, const Duration(days: 1)) && lookups.over(now, const Duration(hours: 1)) && records.over(now, const Duration(minutes: 1));
}

/// A link with another relay, proven: whichever of the two dialled.
class _Link {
  _Link(this.socket, this.id, this.key, this.url, this.used, {required this.outbound, this.standing = false, this.isVia = false});
  final HubSocket socket;

  /// The other relay's name and key, as it proved them.
  final String id;
  final List<int> key;

  /// Its hub's address, where this relay has seen that key there itself; null for a relay with none.
  final String? url;
  final bool outbound;

  /// It dialled this relay with no address of its own, to stay: its people are reached over this link.
  final bool standing;

  /// The relay this one stays linked to (`GHOST_FED_VIA`).
  final bool isVia;
  DateTime used;
  int seq = 0;

  /// What was sent on it and is not answered yet, by its number.
  final Map<int, _Out> flying = {};
  final Map<int, _Ask> asked = {};

  /// The records said on it, as `name:count`.
  final LinkedHashSet<String> gave = LinkedHashSet();
}

/// A relay something waits for: by its hub's address, or for one with no address by its name.
class _Peer {
  _Peer(this.key, {this.url, this.relay, required this.lastUsed});
  final String key;
  final Uri? url;
  String? relay;
  final Queue<_Out> queue = Queue();
  final List<_Ask> asks = [];
  int bytes = 0;
  bool dialling = false;
  int failures = 0;
  DateTime? nextTry;
  DateTime? refusedUntil;
  DateTime? pausedUntil;
  DateTime lastUsed;

  bool get idle => queue.isEmpty && asks.isEmpty && !dialling;
}

/// A packet on its way to another relay.
class _Out {
  _Out(this.peer, this.kind, this.to, this.from, this.relay, this.packet, this.at, this.answer, {this.forOthers = false});
  final _Peer peer;

  /// Another relay passed it here to be passed on (a `[6]`, or from a relay that stays linked to this one): not from
  /// someone signed in here.
  final bool forOthers;
  final int kind;
  final String to;
  final String from;
  final String? relay;
  final Uint8List packet;
  final DateTime at;
  final void Function(bool? here, [String? err]) answer;
  bool answered = false;

  /// The link it was sent on, while it waits for that relay's answer, and when.
  _Link? flying;
  DateTime? sentAt;

  /// Refused once for want of a record and sent again with it; sent to another relay once because the one it went
  /// to said they live elsewhere; and waiting for its sender's own record to come.
  bool again = false;
  bool rerouted = false;
  bool wantsHome = false;

  int get size => packet.length + 64;

  /// Tells whoever sent it, once.
  void tell(bool? here, [String? err]) {
    if (answered) return;
    answered = true;
    answer(here, err);
  }
}

/// A username asked of another relay.
class _Ask {
  _Ask(this.name, this.at, this._answer);
  final String name;
  final DateTime at;
  final void Function(Map) _answer;
  int q = 0;
  bool sent = false;
  bool done = false;

  void answer(Map m) {
    if (done) return;
    done = true;
    _answer(m);
  }
}

/// A hello under way with a relay this one dialled.
class _Hello {
  _Hello(this.peer, this.socket, this.deadline);
  final _Peer peer;
  final HubSocket socket;
  final DateTime deadline;
  List<int>? nonce;
  String? id;
  List<int>? key;
  List<int>? c;
  bool done = false;
  _Link? link;
}

/// A look at what key an address shows ([Federation._keyAt]).
class _Look {
  _Look(this.socket, this.deadline);
  final HubSocket socket;
  final DateTime deadline;
}

class _In implements FedEnd {
  _In(this._fed, this.socket);
  final Federation _fed;
  final HubSocket socket;
  _Link? link;
  bool left = false;

  @override
  void heard(Object? data) {
    final l = link;
    if (l != null) _fed._heard(l, data);
  }

  @override
  void gone() {
    left = true;
    final l = link;
    if (l != null) _fed._lost(l);
  }
}
