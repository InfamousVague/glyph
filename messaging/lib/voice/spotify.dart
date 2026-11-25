/// Spotify played to a circle's call (Matt, 2026-11-25: "Please add a spotify plugin for circles that allows a user to
/// add songs to a queue and play them from spotify in the server this may require my spotify account to be running on
/// the server or something", then "I want it to join a voice chat and stream the music over the voice chat i'm in", and
/// "also make sure this works on windows").
///
/// - **The DJ** is whoever in the call pressed Start on a Mac or a PC with the Spotify app open and signed in. Their own
///   Spotify plays; the app presses its buttons and sends its sound, and nothing else's, to each listener
///   (lib/voice/spotify_app.dart). No key, no account of ours, and nothing on the relay. One DJ a call: the first stays
///   until they stop or leave.
/// - **The queue** (spotify_queue.dart) is held by the DJ's device alone, which says all of it as it changes, every
///   [beatEvery] while it plays, and to whoever comes in ('mu' in the call's room, sealed as everything said there is; a
///   build from before it ignores it). Everyone else asks the DJ: add, take away, move, skip, pause, play. The DJ does
///   as it is asked by anyone whose role may speak in the space.
/// - **The music** goes from the DJ's device to each listener's over a connection of its own (spotify_link.dart), asked
///   for by the listener and made by the DJ: stereo Opus, beside the call's and no part of it, so the microphone, mute,
///   recordings, captions and Scribe know nothing of it. Deafened, it is silent; it has a loudness of its own here.
///
/// Only where the plugin is on in the circle, looked at on both sides for everything said and everything done.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../circles/circles.dart';
import '../net/crypto.dart';
import '../plugins/spotify.dart' show SpotifyPlugin;
import 'channels.dart';
import 'rtc.dart';
import 'spotify_app.dart';
import 'spotify_deck.dart';
import 'spotify_link.dart';
import 'spotify_lookup.dart';
import 'spotify_queue.dart';
import 'voice.dart';

class SpotifyMusic extends ChangeNotifier {
  SpotifyMusic._();
  static final SpotifyMusic instance = SpotifyMusic._();

  @visibleForTesting
  SpotifyMusic.forTest({required this.isOn, required this.maySpeak, required this.app, required this.source, required this.makeEar, required this.clock, this.lookUp = _noLookup, this.ways = _noWays, this.store});
  static Future<Song> _noLookup(String track) async => Song(track: track);
  static ({List<Map<String, Object>> servers, bool relay}) _noWays() => (servers: const [], relay: false);

  /// Whether the plugin is on in the call there is (in a circle's space, as the circle says).
  bool Function() isOn = SpotifyPlugin.onInCall;

  /// Whether [id] may speak in the call's space, as its roles and mutes say: only they choose songs.
  bool Function(String id) maySpeak = _roomSays;

  /// This computer's Spotify and its sound; null where it can't be the DJ.
  SpotifyApp? Function() app = SpotifyApp.here;
  MusicSource? Function() source = _sourceHere;
  MakeEar makeEar = RtcMusicEar.make;
  DateTime Function() clock = DateTime.now;
  Future<Song> Function(String track) lookUp = SpotifyLookup.of;

  /// Where a connection looks for a way through: the call's own servers, and whether the relay is among them.
  ({List<Map<String, Object>> servers, bool relay}) Function() ways = _callWays;

  /// Where the loudness is kept; the app's own choices where none is given.
  @visibleForTesting
  AppState? store;
  AppState? get _store => store ?? Voice.instance.app;

  static bool _roomSays(String id) {
    final s = Voice.instance.session;
    final room = s == null ? null : Voice.instance.heldHangout(s.channel);
    return room == null || room.heard(id == s!.route.me ? room.me : id);
  }

  static MusicSource? _sourceHere() => MusicSource.here(Voice.instance.settings);

  static ({List<Map<String, Object>> servers, bool relay}) _callWays() {
    final m = Voice.instance.media;
    return m == null ? (servers: RtcMedia.defaultIce, relay: false) : (servers: m.iceServers, relay: m.hasRelay);
  }

  // --- how often things are said and done --------------------------------------------------------------------------------

  static const beatEvery = Duration(seconds: 5), pollEvery = Duration(seconds: 1);

  /// Two who pressed Start at once settle it by their ids, within this long of starting.
  static const settlesWithin = Duration(seconds: 10);

  /// The DJ's: how often one person may ask for a connection, how many things of the queue's they may ask in
  /// [askWindow], and the most listeners there may be.
  static const linkEvery = Duration(seconds: 2), askWindow = Duration(seconds: 10);
  static const asksMost = 12, listenersMost = 60;

  /// Silence from Spotify for this many looks while it says it plays: nothing is being heard of it.
  static const silentAfter = 10;

  /// The longest description and way to connect taken from the room.
  static const sdpMost = 24000, candidateMost = 800;

  // --- the call ----------------------------------------------------------------------------------------------------------

  VoiceSession? _session;

  /// Who is playing the music: their id, this device's own where it is; null for nobody.
  String? get dj => _dj;
  String? _dj;
  DateTime? _djAt;

  /// This device is the DJ.
  bool get mine => _deck != null;

  /// What they last said, or what this device says; null while nobody plays.
  MusicState? state;

  bool get inCall => _session != null;
  String? get me => _session?.route.me;

  /// Whether this device's person may choose songs: in the call, and their role may speak.
  bool get mayChoose => _session != null && maySpeak(me!);

  /// Whether this computer could be the DJ, Spotify there or not.
  bool get canDj => app() != null;

  /// What to say is wrong, at the DJ's own device or at someone else's; null for nothing.
  String? get troubleWords {
    final w = state?.trouble ?? '';
    if (w.isEmpty) return null;
    return mine ? MusicTrouble.mine(w, mac: app()?.mac ?? true) : MusicTrouble.words[w];
  }

  /// Follows the call [Voice] is in.
  void follow() => followSession(Voice.instance.session);

  void followSession(VoiceSession? s) {
    if (identical(s, _session)) return;
    final was = _session;
    was?.onMusic = null;
    was?.removeListener(_callChanged);
    if (mine) unawaited(_stopDj());
    _forgetDj();
    _session = s;
    _asked.clear();
    _linkAt.clear();
    _known = const {};
    if (s != null) {
      s.onMusic = _heard;
      s.addListener(_callChanged);
      if (_circles == null) {
        _circles = _callChanged;
        Circles.instance.addListener(_circles!);
      }
      // Whoever is playing says so to this device.
      if (isOn()) s.sayMusic({'k': 'hi'});
    } else if (_circles != null) {
      Circles.instance.removeListener(_circles!);
      _circles = null;
    }
    notifyListeners();
  }

  VoidCallback? _circles;

  /// Who was in the call as last looked: whoever is new is told what plays.
  Set<String> _known = const {};

  /// Anything in the call changed: who is in it, what they may do, this device deafened.
  void _callChanged() {
    final s = _session;
    if (s == null) return;
    if (!isOn()) {
      if (mine) unawaited(stop());
      if (_dj != null) {
        _forgetDj();
        notifyListeners();
      }
      return;
    }
    final here = s.members.keys.toSet();
    if (mine) {
      // Muted for everyone, or a role that may not speak: not heard, so neither is their music.
      if (!maySpeak(s.route.me)) {
        unawaited(stop());
        return;
      }
      for (final id in here.difference(_known)) {
        _sayState(to: id);
      }
      for (final id in _links.keys.toList()) {
        if (!here.contains(id)) unawaited(_dropLink(id));
      }
    } else if (_dj != null && (!here.contains(_dj) || !maySpeak(_dj!))) {
      _forgetDj();
      notifyListeners();
    }
    _known = here;
    _tuneEar();
  }

  /// Something said of the music by [from].
  void _heard(String from, Map<String, dynamic> m) {
    final s = _session;
    if (s == null || !isOn() || !s.members.containsKey(from)) return;
    switch (m['k']) {
      case 'state':
        _heardState(from, m);
      case 'stop':
        if (from == _dj && !mine) {
          _forgetDj();
          notifyListeners();
        }
      case 'hi':
        if (mine && _may(from)) _sayState(to: from);
      case 'do':
        if (mine && m['to'] == s.route.me && maySpeak(from) && _may(from)) _doAsked(from, m);
      case 'ask':
        if (mine && m['to'] == s.route.me) unawaited(_offerTo(from, m['n']));
      case 'ans':
        if (mine && m['to'] == s.route.me) unawaited(_answered(from, m));
      case 'offer':
        if (!mine && from == _dj && m['to'] == s.route.me) unawaited(_offered(m));
      case 'ice':
        if (m['to'] == s.route.me) unawaited(_heardIce(from, m));
    }
  }

  /// Whether [from] may ask one more thing of this device now.
  bool _may(String from) {
    final now = clock();
    final list = _asked.putIfAbsent(from, () => []);
    list.removeWhere((t) => now.difference(t) >= askWindow);
    if (list.length >= asksMost) return false;
    list.add(now);
    return true;
  }

  final Map<String, List<DateTime>> _asked = {};

  void _heardState(String from, Map<String, dynamic> m) {
    final s = _session!;
    if (!maySpeak(from)) return;
    final now = clock();
    if (mine) {
      // Someone else started too: within a moment of each other the lower id stays; later, the one who was first.
      if (now.difference(_djAt!) < settlesWithin && from.compareTo(s.route.me) < 0) unawaited(stop());
      return;
    }
    final had = _dj;
    if (had != null && had != from) {
      if (now.difference(_djAt!) >= settlesWithin || from.compareTo(had) > 0) return;
      _forgetDj();
    }
    final fresh = MusicState.fromWire(m, at: now);
    if (fresh == null) return;
    if (_dj == null) {
      _dj = from;
      _djAt = now;
    }
    state = fresh;
    _tuneEar();
    notifyListeners();
  }

  /// Nobody plays, as far as this device knows.
  void _forgetDj() {
    _dj = null;
    _djAt = null;
    state = null;
    _tries = 0;
    _askTimer?.cancel();
    _askTimer = null;
    unawaited(_dropEar());
  }

  // --- what this device's person asks ------------------------------------------------------------------------------------

  /// Adds the song [pasted] names. Why not, where it can't be.
  Future<String?> add(String pasted) async {
    final s = _session;
    if (s == null || !isOn() || _dj == null) return 'Nobody is playing music here yet.';
    if (!maySpeak(s.route.me)) return 'Your role in this space can\'t speak, so it can\'t choose songs.';
    final p = songIn(pasted);
    if (p.id == null) return p.why;
    final q = state?.next ?? const <QueuedSong>[];
    if (q.length >= songsMost) return 'The queue is full: $songsMost songs.';
    if (q.where((x) => x.by == s.route.me).length >= songsEachMost) return 'That is $songsEachMost songs from you in the queue. One more when one of them has played.';
    final song = await lookUp(p.id!);
    // The call was left, or the music stopped, while Spotify was asked what the song is.
    if (!identical(s, _session) || _dj == null) return 'The music stopped.';
    if (mine) return _add(song, s.route.me);
    s.sayMusic({'k': 'do', 'to': _dj, 'w': 'add', 'x': song.toWire()});
    return null;
  }

  void remove(int id) => mine ? _remove(id, me!) : _ask({'w': 'rm', 'e': id});
  void move(int id, int place) => mine ? _move(id, place) : _ask({'w': 'mv', 'e': id, 'i': place});
  void skip() => mine ? unawaited(_press((d) => d.skip(clock()))) : _ask({'w': 'skip'});
  void pause() => mine ? unawaited(_press((d) => d.pause())) : _ask({'w': 'pause'});
  void play() => mine ? unawaited(_press((d) => d.resume(clock()))) : _ask({'w': 'play'});
  void toggle() => (state?.playing ?? false) ? pause() : play();

  void _ask(Map<String, Object?> what) {
    final s = _session;
    if (s == null || _dj == null || !isOn() || !maySpeak(s.route.me)) return;
    s.sayMusic({'k': 'do', 'to': _dj, ...what});
  }

  /// Whether this device's person may take [song] away: their own, or any as the DJ.
  bool mayRemove(QueuedSong song) => mine || (mayChoose && song.by == me);

  // --- the DJ --------------------------------------------------------------------------------------------------------------

  SpotifyDeck? _deck;
  MusicSource? _source;
  SpotifyApp? _spotify;
  Timer? _poll, _beat;

  /// Between Start being pressed and the music being the call's.
  bool starting = false;

  /// Why the last Start here did not start, in a word of [MusicTrouble]'s; null where it did.
  String? startTrouble;
  String? get startWords => startTrouble == null ? null : MusicTrouble.mine(startTrouble!, mac: app()?.mac ?? true);

  /// What is wrong with it now, as the DJ's device knows it.
  String _trouble = '';
  int _silent = 0;

  /// Each button pressed counts one: what Spotify had said before it is not believed after.
  int _presses = 0;
  bool _polling = false;

  /// Becomes the DJ: only ever by this device's person pressing Start here. True where it did; else [startTrouble].
  Future<bool> start() async {
    final s = _session;
    if (s == null || !isOn() || mine || starting || _dj != null || !maySpeak(s.route.me)) return false;
    final spotify = app(), source = this.source();
    if (spotify == null || source == null) return false;
    starting = true;
    startTrouble = null;
    notifyListeners();
    String? why;
    try {
      final able = await spotify.able();
      if (!able.system) throw const SpotifyRefused(MusicTrouble.system);
      if (!able.installed && !able.running) throw const SpotifyRefused(MusicTrouble.absent);
      if (!able.running) throw const SpotifyRefused(MusicTrouble.closed);
      // Asked what it is doing first: this is where the system asks the person whether the app may.
      final now = await spotify.now();
      await source.begin();
      // Left, or someone else started, or the plugin was turned off, while the system asked.
      if (!identical(s, _session) || !isOn() || _dj != null) {
        await source.end();
        why = '';
      } else {
        _begin(s, spotify, source, now);
      }
    } on SpotifyRefused catch (e) {
      why = e.word;
      await source.end();
    } catch (e) {
      debugPrint('spotify: not started: $e');
      why = MusicTrouble.failed;
      await source.end();
    }
    starting = false;
    startTrouble = why == null || why.isEmpty ? null : why;
    notifyListeners();
    return why == null;
  }

  void _begin(VoiceSession s, SpotifyApp spotify, MusicSource source, SpotifyNow now) {
    final deck = _deck = SpotifyDeck(me: s.route.me, opens: spotify.opens);
    _spotify = spotify;
    _source = source;
    _dj = s.route.me;
    _djAt = clock();
    _trouble = '';
    _silent = 0;
    _known = s.members.keys.toSet();
    source.onCandidate = (id, c) {
      final l = _links[id];
      if (l != null) _session?.sayMusic({'k': 'ice', 'to': id, 'l': l, 'c': c});
    };
    source.onState = (id, state) {
      if (state == 'failed' || state == 'closed') unawaited(_dropLink(id));
    };
    spotify.onQuit = () {
      if (!identical(_deck, deck)) return;
      deck.playing = false;
      _setTrouble(MusicTrouble.closed);
    };
    // What Spotify was playing already is what the call hears first.
    final d = deck.heard(now, clock());
    _poll = Timer.periodic(pollEvery, (_) => unawaited(look()));
    _beat = Timer.periodic(beatEvery, (_) {
      if (deck.playing) _sayState();
    });
    _said(force: true);
    if (d != null) unawaited(_do(d));
  }

  /// Stops the music for everyone, and lets go of Spotify's sound. A song of the queue's is paused in Spotify; one the DJ
  /// chose there is left playing, as theirs.
  Future<void> stop() async {
    if (!mine) return;
    await _stopDj();
    notifyListeners();
  }

  Future<void> _stopDj() async {
    final deck = _deck, source = _source, spotify = _spotify;
    _deck = null;
    _source = null;
    _spotify = null;
    _poll?.cancel();
    _beat?.cancel();
    _poll = _beat = null;
    _links.clear();
    _trouble = '';
    spotify?.onQuit = null;
    source?.onCandidate = null;
    source?.onState = null;
    _dj = null;
    _djAt = null;
    state = null;
    _session?.sayMusic({'k': 'stop'});
    notifyListeners();
    if (deck != null && deck.oursPlaying) {
      try {
        await spotify?.pause();
      } catch (_) {}
    }
    await source?.end();
  }

  /// Looks at what Spotify is doing, and does what follows from it. Once a second while this device is the DJ.
  @visibleForTesting
  Future<void> look() async {
    final deck = _deck, spotify = _spotify, source = _source;
    if (deck == null || spotify == null || source == null || _polling) return;
    _polling = true;
    try {
      final presses = _presses;
      final SpotifyNow now;
      try {
        now = await spotify.now();
      } on SpotifyRefused catch (e) {
        if (identical(deck, _deck)) _setTrouble(e.word, stopped: true);
        return;
      }
      if (!identical(deck, _deck)) return;
      // A button was pressed while it was asked: what it said was from before it.
      if (presses != _presses) return;
      if (_trouble == MusicTrouble.closed || _trouble == MusicTrouble.denied || _trouble == MusicTrouble.failed) _trouble = '';
      final d = deck.heard(now, clock());
      final level = await source.level().catchError((_) => 1.0);
      if (!identical(deck, _deck)) return;
      // Nothing at all from it for a while, though it says it plays.
      _silent = deck.playing && now.playing && level < 0.0005 ? _silent + 1 : 0;
      if (_silent >= silentAfter) {
        _trouble = MusicTrouble.silent;
      } else if (_trouble == MusicTrouble.silent && _silent == 0) {
        _trouble = '';
      }
      if (d != null) await _do(d);
      _said();
    } finally {
      _polling = false;
    }
  }

  void _setTrouble(String word, {bool stopped = false}) {
    final deck = _deck;
    if (deck == null) return;
    if (stopped) deck.playing = false;
    _trouble = word;
    _said();
  }

  /// Presses what [of] says, for the DJ's own person or someone who asked.
  Future<void> _press(DeckDo? Function(SpotifyDeck d) of) async {
    final deck = _deck;
    if (deck == null) return;
    final d = of(deck);
    _said();
    if (d != null) await _do(d);
  }

  Future<void> _do(DeckDo d) async {
    final spotify = _spotify, deck = _deck;
    if (spotify == null) return;
    _presses++;
    try {
      switch (d) {
        case DeckPlay(:final track):
          await spotify.play(track);
        case DeckPause():
          await spotify.pause();
        case DeckResume():
          await spotify.resume();
      }
      if (identical(deck, _deck) && (_trouble == MusicTrouble.closed || _trouble == MusicTrouble.denied || _trouble == MusicTrouble.failed)) _trouble = '';
    } on SpotifyRefused catch (e) {
      if (identical(deck, _deck)) _setTrouble(e.word, stopped: true);
    } finally {
      _presses++;
    }
    if (identical(deck, _deck)) _said();
  }

  /// Does what [from] asked, where it is something that can be asked.
  void _doAsked(String from, Map<String, dynamic> m) {
    final id = m['e'], place = m['i'];
    switch (m['w']) {
      case 'add':
        final song = Song.fromWire(m['x']);
        if (song != null) _add(song, from);
      case 'rm':
        if (id is int) _remove(id, from);
      case 'mv':
        if (id is int && place is int) _move(id, place);
      case 'skip':
        unawaited(_press((d) => d.skip(clock())));
      case 'pause':
        unawaited(_press((d) => d.pause()));
      case 'play':
        unawaited(_press((d) => d.resume(clock())));
    }
  }

  String? _add(Song song, String by) {
    final deck = _deck;
    if (deck == null) return 'Nobody is playing music here yet.';
    final why = deck.queue.add(song, by);
    if (why != null) return why;
    final id = deck.queue.songs.last.id;
    unawaited(_press((d) => d.added(clock())));
    // Added from a browser, or where its name could not be read: read here, for everyone.
    if (song.title.isEmpty) {
      unawaited(lookUp(song.track).then((found) {
        if (!identical(deck, _deck) || found.title.isEmpty) return;
        final n = deck.now;
        if (n != null && n.id == id && n.song.title.isEmpty) deck.now = n.withSong(found.copyWith(length: n.song.length));
        deck.queue.say(id, found);
        _said();
      }).catchError((_) {}));
    }
    return null;
  }

  void _remove(int id, String by) {
    final deck = _deck;
    if (deck != null && deck.queue.remove(id, by: by, dj: by == me)) _said();
  }

  void _move(int id, int place) {
    final deck = _deck;
    if (deck != null && deck.queue.move(id, place)) _said();
  }

  /// What was last said of it, to say it again only when it is something else.
  String _last = '';
  DateTime? _lastAt;
  Duration _lastPos = Duration.zero;

  /// The state is as the deck has it now: kept, shown here, and said to the call where it is not what was last said
  /// (its place alone is said with the beat, or where it was moved).
  void _said({bool force = false}) {
    final deck = _deck;
    if (deck == null) return;
    final now = clock();
    final fresh = deck.state(now, trouble: _trouble);
    state = fresh;
    final mark = '${fresh.now?.id}|${fresh.now?.song.hashCode}|${fresh.playing}|${fresh.trouble}|${[for (final q in fresh.next) '${q.id}:${q.song.hashCode}'].join(',')}';
    final due = _lastAt == null ? Duration.zero : _lastPos + (fresh.playing ? now.difference(_lastAt!) : Duration.zero);
    if (force || mark != _last || (fresh.position - due).abs() > const Duration(seconds: 3)) _sayState();
    _last = mark;
    notifyListeners();
  }

  /// Says the whole state, to everyone or to [to].
  void _sayState({String? to}) {
    final deck = _deck, s = _session;
    if (deck == null || s == null) return;
    final now = clock();
    final fresh = deck.state(now, trouble: _trouble);
    if (to == null) {
      _lastAt = now;
      _lastPos = fresh.position;
    }
    s.sayMusic({'k': 'state', 'to': ?to, ...fresh.toWire()});
  }

  // --- the connections, the DJ's side ----------------------------------------------------------------------------------------

  /// Each listener's connection, by its mark: what is said of another is not for it.
  final Map<String, String> _links = {};
  final Map<String, DateTime> _linkAt = {};

  Future<void> _offerTo(String id, Object? tries) async {
    final s = _session, source = _source;
    if (s == null || source == null) return;
    final now = clock();
    final last = _linkAt[id];
    if (last != null && now.difference(last) < linkEvery) return;
    if (!_links.containsKey(id) && _links.length >= listenersMost) return;
    _linkAt[id] = now;
    final mark = _links[id] = NetCrypto.hex(NetCrypto.randomBytes(8));
    final w = ways();
    // Through the relay alone first where there is one, as the call's own connections are; every path the next time.
    final relay = w.relay && (tries is! int || tries.isEven);
    final sdp = await source.offer(id, servers: w.servers, relayOnly: relay).catchError((_) => null);
    if (_links[id] != mark || !identical(source, _source)) return;
    if (sdp == null) {
      _links.remove(id);
      return;
    }
    s.sayMusic({'k': 'offer', 'to': id, 'l': mark, 'sdp': sdp, if (relay) 'r': 1});
  }

  Future<void> _answered(String from, Map<String, dynamic> m) async {
    final mark = _links[from], sdp = m['sdp'];
    if (mark == null || m['l'] != mark || sdp is! String || sdp.length > sdpMost) return;
    final ok = await _source?.answer(from, sdp).catchError((_) => false) ?? false;
    if (!ok && _links[from] == mark) await _dropLink(from);
  }

  Future<void> _dropLink(String id) async {
    if (_links.remove(id) == null) return;
    await _source?.close(id).catchError((_) {});
  }

  Future<void> _heardIce(String from, Map<String, dynamic> m) async {
    final c = m['c'];
    if (c is! Map || m['l'] is! String) return;
    final line = c['candidate'], mid = c['sdpMid'], at = c['sdpMLineIndex'];
    if (line is! String || line.length > candidateMost) return;
    final way = <String, dynamic>{'candidate': line, 'sdpMid': mid is String && mid.length < 40 ? mid : '', 'sdpMLineIndex': at is int && at >= 0 && at < 8 ? at : 0};
    if (mine) {
      if (_links[from] == m['l']) await _source?.candidate(from, way).catchError((_) {});
    } else if (from == _dj && m['l'] == _earMark) {
      try {
        await _ear?.candidate(way);
      } catch (_) {}
    }
  }

  // --- the listener ------------------------------------------------------------------------------------------------------------

  MusicEar? _ear;
  String? _earMark;
  bool _through = false;
  int _tries = 0;
  Timer? _askTimer;

  /// The music is coming to this device.
  bool get hearing => _ear != null && _through;

  static const volumeKey = 'spotify_volume';

  /// How loud the music is here, 0 to 100. At 0 it is not asked for at all.
  int get volume => (int.tryParse(_store?.choice(volumeKey, '60') ?? '60') ?? 60).clamp(0, 100);

  void setVolume(int to) {
    _store?.keep(volumeKey, '${to.clamp(0, 100)}');
    _tuneEar();
    notifyListeners();
  }

  /// Whether this device wants the music's sound: someone else plays it, and it is not turned all the way down.
  bool get _wants => _session != null && !mine && _dj != null && state?.now != null && volume > 0 && isOn();

  /// The connection as it should be: asked for, let go of, or as loud as it is to be.
  void _tuneEar() {
    if (!_wants) {
      _askTimer?.cancel();
      _askTimer = null;
      if (_ear != null && (mine || _dj == null || volume == 0 || !isOn())) unawaited(_dropEar());
    } else if (_ear == null && _askTimer == null) {
      _askNow();
    }
    _loud();
  }

  void _loud() {
    final s = _session;
    final out = Voice.instance.media?.settings.outputVolume ?? 100;
    _ear?.set(volume: volume / 100 * out / 100, silent: s == null || s.deafened);
  }

  /// Asks the DJ for a connection, and again, further apart each time, until it is through.
  void _askNow() {
    final s = _session;
    if (s == null || !_wants) return;
    s.sayMusic({'k': 'ask', 'to': _dj, 'n': _tries});
    final wait = Duration(seconds: [4, 8, 16, 30][_tries.clamp(0, 3)]);
    _tries++;
    _askTimer = Timer(wait, () {
      _askTimer = null;
      if (_ear == null && _wants) _askNow();
    });
  }

  /// The DJ's offer, for a connection this device asked for.
  Future<void> _offered(Map<String, dynamic> m) async {
    final s = _session, mark = m['l'], sdp = m['sdp'];
    if (s == null || !_wants || mark is! String || mark.length > 40 || sdp is! String || sdp.length > sdpMost) return;
    await _dropEar();
    if (!identical(s, _session) || !_wants) return;
    _earMark = mark;
    final from = _dj!;
    late final MusicEar ear;
    ear = _ear = makeEar(
      servers: ways().servers,
      relayOnly: m['r'] == 1,
      onCandidate: (c) {
        if (identical(_ear, ear)) _session?.sayMusic({'k': 'ice', 'to': from, 'l': mark, 'c': c});
      },
      onState: (up) {
        if (!identical(_ear, ear)) return;
        _through = up;
        if (up) {
          _tries = 0;
          _askTimer?.cancel();
          _askTimer = null;
        } else {
          // Lost, or never through: let go of, and asked for again.
          unawaited(_dropEar().then((_) {
            if (_wants && _ear == null && _askTimer == null) _askNow();
          }));
        }
        notifyListeners();
      },
    );
    _loud();
    final out = Voice.instance.media?.settings.output ?? '';
    unawaited(ear.output(out).catchError((_) {}));
    try {
      final answer = await ear.takeOffer(sdp);
      if (identical(_ear, ear)) _session?.sayMusic({'k': 'ans', 'to': from, 'l': mark, 'sdp': answer});
    } catch (e) {
      debugPrint('spotify: the music\'s offer not taken: $e');
      if (identical(_ear, ear)) await _dropEar();
    }
  }

  Future<void> _dropEar() async {
    final ear = _ear;
    _ear = null;
    _earMark = null;
    _through = false;
    await ear?.close();
  }
}
