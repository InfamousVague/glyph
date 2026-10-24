/// The tapes of the cassettes in view on the home page's shelf, loaded ahead (Matt, 2026-10-24: "preload meeting
/// audio on desktop for the visible cassets so hovering is instant to play"): a few players of their own, each
/// holding one cassette's recording stopped at its start, so the 300 ms rest (lib/home/meeting_shelf.dart
/// `meetingHoverDwell`) ends in a Play and nothing else.
///
/// What a hover cost before, measured on this Mac (an M-series MacBook, 2026-10-24) with the `AVAudioPlayer` the
/// Mac's TapeChannel.swift makes, over 12, 48 and 62 minute meeting WAVs: opening the file and `prepareToPlay` took
/// 6 to 8 ms once the Mac's audio had been woken, and 50 ms more for the first tape after a launch, while the audio
/// was woken; Play itself took 3 to 14 ms; and the sound was under way some 23 ms after Play, the Mac's own output,
/// whatever was loaded. Loaded ahead, the hover is Play's few milliseconds and that 23 ms. A meeting's recording is
/// never fetched for this: sync brings every recording that travels as its note arrives (lib/sync/notes.dart
/// `_fetchFilesOf`), and one that stayed on the device that made it (Sync meeting recordings off there, or over
/// the service's limit) is on no server to fetch; its load fails, it is not tried again until the shelf is let go,
/// and its hover loads on the memos' player as before and says nothing.
///
/// - [want] names the cassettes in view, the shelf's to say, in the order to load them: as many as there are
///   players ([tapePreviewsMost]), one at a time so the Mac's main thread is never held for long, and the rest let
///   go. About a quarter of a megabyte a player, measured the same way.
/// - [take] lends a player holding a cassette ready, waiting for one still loading; null and the hover loads as it
///   always did. [done] has it back, at its start again, or let go where its cassette has gone from view meanwhile.
/// - The memos' player, and the tape's, are never touched: a note open beside the shelf keeps its playhead and its
///   memo.
///
/// Only the Mac has players for this (macos/Runner/GhostChannels.swift, `ghost_md/preview/<n>`); the shelf asks
/// for none on a phone or a tablet, where there is no mouse to rest, nor while the app is hidden.
library;

import 'dart:async';

import 'player.dart';
import 'phone_player.dart';

/// How many cassettes are kept loaded at once: those a wide window shows, and one either side.
const int tapePreviewsMost = 6;

class TapePreviews {
  /// Over [players], which this owns from now on.
  TapePreviews(List<TapePlayer> players) : _slots = [for (final player in players) _Slot(player)];

  /// The Mac's: [tapePreviewsMost] players, each on a channel of its own.
  factory TapePreviews.mac() => TapePreviews([for (var i = 0; i < tapePreviewsMost; i += 1) PhoneTapePlayer.preview(i)]);

  final List<_Slot> _slots;
  List<String> _wanted = const [];

  /// The cassettes whose load failed: not asked for again until the shelf lets go of everything.
  final Set<String> _failed = {};
  bool _filling = false;
  bool _gone = false;

  /// The cassettes held or loading, for the tests.
  Set<String> get held => {for (final slot in _slots) ?slot.id};

  /// The cassettes ready to play at once.
  Set<String> get ready => {for (final slot in _slots) if (slot.ready) slot.id!};

  /// Have [ids] loaded, the first first, as many as there are players; any other cassette held is let go, unless a
  /// mouse is resting on it.
  void want(List<String> ids) {
    if (_gone) return;
    _wanted = ids.take(_slots.length).toList(growable: false);
    final keep = _wanted.toSet();
    for (final slot in _slots) {
      if (slot.id != null && !slot.busy && !keep.contains(slot.id)) _free(slot);
    }
    unawaited(_fill());
  }

  /// Let go of everything, and forget which failed: the shelf gone, the app hidden.
  void releaseAll() {
    if (_gone) return;
    _wanted = const [];
    _failed.clear();
    for (final slot in _slots) {
      if (slot.id != null) _free(slot);
    }
  }

  /// A player holding [id] stopped at its start, lent until [done]; null where none is, or its load failed.
  Future<TapePlayer?> take(String id) async {
    var slot = _of(id);
    if (slot == null) return null;
    if (!slot.ready) await slot.loading;
    slot = _of(id);
    if (slot == null || !slot.ready || slot.busy) return null;
    slot.busy = true;
    return slot.player;
  }

  /// [player] back from a hover: put at its start for the next, or let go where its cassette is not wanted now.
  void done(TapePlayer player) {
    for (final slot in _slots) {
      if (slot.player != player || !slot.busy) continue;
      slot.busy = false;
      if (slot.id != null && _wanted.contains(slot.id)) {
        unawaited(player.seek(0).then<void>((_) {}, onError: (Object _) {}));
      } else if (slot.id != null) {
        _free(slot);
      }
      unawaited(_fill());
    }
  }

  /// Stops and lets go of every player: the app's to call, at its end.
  void dispose() {
    _gone = true;
    for (final slot in _slots) {
      slot.player.dispose();
    }
  }

  _Slot? _of(String id) {
    for (final slot in _slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }

  void _free(_Slot slot) {
    slot
      ..gen += 1
      ..id = null
      ..ready = false
      ..busy = false
      ..loading = null;
    unawaited(slot.player.release().then<void>((_) {}, onError: (Object _) {}));
  }

  /// Load the wanted that are not held, one at a time, into players holding nothing.
  Future<void> _fill() async {
    if (_filling) return;
    _filling = true;
    try {
      while (!_gone) {
        final held = this.held;
        final next = _wanted.where((id) => !held.contains(id) && !_failed.contains(id)).firstOrNull;
        final slot = _slots.where((slot) => slot.id == null).firstOrNull;
        if (next == null || slot == null) break;
        await _load(slot, next);
      }
    } finally {
      _filling = false;
    }
  }

  Future<void> _load(_Slot slot, String id) async {
    final gen = slot.gen += 1;
    final loaded = Completer<void>();
    slot
      ..id = id
      ..ready = false
      ..loading = loaded.future;
    try {
      await slot.player.load(id);
      if (slot.gen == gen) slot.ready = true;
    } catch (_) {
      // Not here, or not readable: the hover loads it as it always did, and says why there if it must.
      if (slot.gen == gen) {
        _failed.add(id);
        slot.id = null;
      }
    } finally {
      if (slot.gen == gen) slot.loading = null;
      loaded.complete();
    }
  }
}

class _Slot {
  _Slot(this.player);

  final TapePlayer player;

  /// The cassette it holds or is loading.
  String? id;

  /// Loaded, stopped at its start.
  bool ready = false;

  /// Lent to a hover.
  bool busy = false;

  /// The load under way.
  Future<void>? loading;

  /// Which load is the slot's latest: one let go of meanwhile changes nothing when it ends.
  int gen = 0;
}
