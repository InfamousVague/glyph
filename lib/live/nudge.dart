/// A word between an organization's devices that there is something to fetch. A port of
/// `src/app/core/live/nudge.ts`.
///
/// The sync itself is passes (docs/SYNC.md, SHARED.md S4): a device wrote, and the others heard at their next
/// pass, five minutes apart; so a member who had just joined waited a pass for someone to wrap the key for them, a
/// pass to read it, and a pass for the notes. Every member's device holds the organization's `sync` room on the
/// relay while the app is open, and says three things in it, none of them a secret and none of them sealed (a
/// device without the key yet must be able to say and hear them):
///
/// - **need**: this device is in the organization and has no key. Said on joining the room and whenever someone
///   else comes into it. A device that holds the key wraps for whoever lacks one at once, then says **keys**.
/// - **keys**: a wrap was just made. A device without the key reads its wrap and fetches the team's notes.
/// - **changed**: this device just wrote to the organization (a note, an update, a file). The others sync now.
///
/// What is fetched is still the sealed rows, by the pass; this only says when. No document here: the hub and a few
/// bytes.
///
/// What differs: the page's module is a [Nudges] made once with the account; `watchNudges` is [Nudges.watch], and
/// `tellChanged` is what the engine is handed as its own `tellChanged`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'hub.dart';
import 'transport.dart';

const String _room = 'sync';

/// The three words, as the base64url the relay insists on.
const String nudgeNeed = 'bmVlZA';
const String nudgeKeys = 'a2V5cw';
const String nudgeChanged = 'Y2hhbmdlZA';

/// Several words in a breath are one fetch.
const Duration _settle = Duration(milliseconds: 400);

/// What a nudge asks of the engine (`NudgeHooks`).
class NudgeHooks {
  const NudgeHooks({required this.keys, required this.notes});

  /// The keys step: the list read and whoever lacks a wrap wrapped for, or this device's wrap read (the engine's
  /// `syncNotificationsNow`).
  final Future<void> Function() keys;

  /// The team's notes fetched now (the engine's `syncTeamsNow`).
  final Future<void> Function() notes;
}

/// What the watch reads of the account.
class NudgeWatch {
  const NudgeWatch({required this.signedIn, required this.localOnly, required this.joined, required this.changes});
  final bool Function() signedIn;
  final bool Function() localOnly;
  final List<String> Function() joined;
  final List<Listenable> changes;
}

/// The `sync` rooms this device holds.
class Nudges {
  Nudges({required this.hub, required this.hasKey, Duration settle = _settle}) : _rest = settle;

  final LiveHub hub;

  /// Whether this device holds an organization's key.
  final bool Function(String orgId) hasKey;
  final Duration _rest;

  final Map<String, LiveTransport> _held = {};
  NudgeHooks? _hooks;
  Timer? _fetching;

  void _say(String orgId, String word) => _held[orgId]?.send(_room, word, org: orgId);

  /// This device just wrote to the organization: the others fetch now. Nothing when its room is not held
  /// (`tellChanged`).
  void tellChanged(String orgId) => _say(orgId, nudgeChanged);

  void _fetchSoon() {
    if (_fetching != null) return;
    _fetching = Timer(_rest, () {
      _fetching = null;
      unawaited(_hooks?.notes().catchError((Object _) {}));
    });
  }

  /// The key seen to, and what follows from it said: wrapped for someone, or read here and the notes fetched.
  Future<void> _seeToKeys(String orgId) async {
    final had = hasKey(orgId);
    try {
      await _hooks?.keys();
    } catch (_) {
      // The next pass sees to it.
    }
    final has = hasKey(orgId);
    if (has && had) _say(orgId, nudgeKeys);
    if (has && !had) _fetchSoon();
  }

  void _hold(String orgId) {
    // Without the key: this account's key pair is registered and any wrap already there read first (the keys
    // step), so that whoever answers finds a public key to wrap for; then, still without it, the room is asked.
    void needs() {
      if (hasKey(orgId)) return;
      unawaited(() async {
        try {
          await _hooks?.keys();
        } catch (_) {
          // Asked of the room all the same.
        }
        if (!hasKey(orgId)) {
          _say(orgId, nudgeNeed);
        } else {
          _fetchSoon();
        }
      }());
    }

    _held[orgId] = hub.holdRoom(
      _room,
      RoomFunctions(
        onJoined: (first, peers) {
          if (peers > 0) needs();
          // Back in the room, first time or after a drop: whatever was written meanwhile is fetched.
          _fetchSoon();
        },
        onPeers: (peers, left) {
          if (left == null && peers > 0) needs();
        },
        onMessage: (from, data) {
          if (data == nudgeNeed && hasKey(orgId)) {
            unawaited(_seeToKeys(orgId));
          } else if (data == nudgeKeys && !hasKey(orgId)) {
            unawaited(_seeToKeys(orgId));
          } else if (data == nudgeChanged) {
            _fetchSoon();
          }
        },
      ),
      orgId,
    );
  }

  /// The organizations whose `sync` room this device holds, for tests (`heldNudges`).
  List<String> heldNudges() => _held.keys.toList();

  /// Holds every joined organization's `sync` room while signed in and not local-only, key or no key, and lets
  /// each go when that stops being so. A key newly in hand here has its notes fetched now. Answers the way to stop
  /// (`watchNudges`).
  void Function() watch(NudgeHooks hooks, NudgeWatch of) {
    _hooks = hooks;
    final keyed = <String>{};
    void settle() {
      final wanted = of.signedIn() && !of.localOnly() ? of.joined() : const <String>[];
      for (final id in _held.keys.toList()) {
        if (wanted.contains(id)) continue;
        _held.remove(id);
        keyed.remove(id);
        hub.releaseRoom(_room, id);
      }
      for (final id in wanted) {
        if (!_held.containsKey(id)) _hold(id);
        final has = hasKey(id);
        // The key just came to this device: its notes are fetched now, not at the next pass.
        if (has && !keyed.contains(id)) _fetchSoon();
        if (has) {
          keyed.add(id);
        } else {
          keyed.remove(id);
        }
      }
    }

    settle();
    for (final each in of.changes) {
      each.addListener(settle);
    }
    return () {
      for (final each in of.changes) {
        each.removeListener(settle);
      }
      for (final id in _held.keys.toList()) {
        hub.releaseRoom(_room, id);
      }
      _held.clear();
      _hooks = null;
      _fetching?.cancel();
      _fetching = null;
    };
  }
}
