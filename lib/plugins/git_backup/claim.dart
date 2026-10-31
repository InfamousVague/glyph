/// One pusher (decision 13, docs/MARKDOWN_FIRST.md §11): of an account's devices, the one holding the pusher claim
/// commits and pushes; the others only read the repository's status and say "Backing up from your Mac". The claim is
/// the ticket sweep's (lib/book/rule_runs.dart `SweepClaim`, `holdsSweep`), kept under [pusherClaimKey] in the
/// synced preferences: `{by, name, at}`, live for [pusherClaimMs], renewed every [pusherRenewMs] while pushing, and
/// confirmed by reading the account's copy after a sync, which the server's revision check settles when two devices
/// claim at once (`chosenPusherClaim` in lib/sync/prefs.dart's merge keeps the other device's live claim). Desktops
/// are preferred: a phone waits [phoneDefers] after seeing no claim before it takes one, so a Mac that is awake takes
/// it first.
library;

import 'package:flutter/foundation.dart';

import '../../ai/summary_handoff.dart' show SummaryDevice;
import '../../core/preferences.dart';

/// The key in `Preferences.more`.
const String pusherClaimKey = 'gitPusher';

/// How long a claim stands without renewal: a day, as the design says (a device that sleeps a night is not the
/// pusher in the morning if another is awake).
const int pusherClaimMs = 24 * 60 * 60 * 1000;

/// How often the holder renews it.
const int pusherRenewMs = 10 * 60 * 1000;

/// How long a phone waits with no claim in sight before it takes one.
const Duration phoneDefers = Duration(minutes: 5);

@immutable
class PusherClaim {
  const PusherClaim({required this.by, this.name, required this.at});
  final String by;
  final String? name;
  final int at;

  static PusherClaim? fromJson(Object? raw) {
    if (raw is! Map || raw['by'] is! String || raw['at'] is! num) return null;
    return PusherClaim(by: raw['by'] as String, name: raw['name'] is String ? raw['name'] as String : null, at: (raw['at'] as num).toInt());
  }

  Map<String, Object?> toJson() => {'by': by, if (name != null) 'name': name, 'at': at};

  bool liveAt(int now) => now - at < pusherClaimMs;
}

PusherClaim? pusherClaimOf(Preferences prefs) => PusherClaim.fromJson(prefs.more[pusherClaimKey]);

/// Which of two devices' claims stands where both changed it (lib/sync/prefs.dart `merged`): a live claim of
/// another device's that the account already held, over this device's own; else this device's.
Object? chosenPusherClaim(Object? mine, Object? theirs, {int? now}) {
  final t = PusherClaim.fromJson(theirs);
  if (t == null) return mine;
  final m = PusherClaim.fromJson(mine);
  if (t.liveAt(now ?? DateTime.now().millisecondsSinceEpoch) && t.by != m?.by) return theirs;
  return mine;
}

/// Whether this device pushes (see the header).
class PusherClaims {
  PusherClaims({
    required this.device,
    required this.preferences,
    required this.setPreferences,
    required this.syncNow,
    this.accountHeld,
    this.isPhone = false,
    int Function()? clock,
    void Function(String)? warn,
  })  : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        warn = warn ?? debugPrint;

  final SummaryDevice Function() device;
  final Preferences Function() preferences;
  final void Function(Preferences Function(Preferences)) setPreferences;
  final Future<void> Function() syncNow;

  /// The account's copy of the preferences after a sync, or null signed out or local only (then the claim is this
  /// device's alone).
  final Map<String, Object?>? Function()? accountHeld;

  /// A phone defers to a desktop (see the header).
  final bool isPhone;
  final int Function() clock;
  final void Function(String) warn;

  bool _confirmed = false;
  int _renewed = 0;
  int? _firstSawNone;

  /// The device that holds the claim now, where it is another's and live.
  PusherClaim? elsewhere() {
    final claim = pusherClaimOf(preferences());
    if (claim == null || claim.by == device().id || !claim.liveAt(clock())) return null;
    return claim;
  }

  /// Whether this device holds the claim: another device's live claim says no; this device's own, once confirmed,
  /// says yes and is renewed as it ages; else it is claimed, a sync run, and the account asked.
  Future<bool> holds() async {
    final me = device();
    final now = clock();
    final claim = pusherClaimOf(preferences());
    if (claim != null && claim.by != me.id && claim.liveAt(now)) {
      _confirmed = false;
      _firstSawNone = null;
      return false;
    }
    if (claim != null && claim.by == me.id && claim.liveAt(now) && _confirmed) {
      if (now - _renewed >= pusherRenewMs) {
        _renewed = now;
        setPreferences((prefs) => prefs.copyWith(more: {...prefs.more, pusherClaimKey: PusherClaim(by: me.id, name: me.name, at: now).toJson()}));
      }
      return true;
    }
    if (isPhone && (claim == null || !claim.liveAt(now))) {
      // A desktop that is awake gets there first.
      final since = _firstSawNone ??= now;
      if (now - since < phoneDefers.inMilliseconds) return false;
    }
    setPreferences((prefs) {
      final was = pusherClaimOf(prefs);
      if (was != null && was.by != me.id && was.liveAt(now)) return prefs;
      return prefs.copyWith(more: {...prefs.more, pusherClaimKey: PusherClaim(by: me.id, name: me.name, at: now).toJson()});
    });
    _renewed = now;
    if (accountHeld == null || accountHeld!() == null) return _confirmed = pusherClaimOf(preferences())?.by == me.id;
    try {
      await syncNow();
    } catch (failure) {
      warn('[git-backup] the pusher claim could not be synced: $failure');
    }
    final held = accountHeld?.call();
    final said = held == null ? pusherClaimOf(preferences()) : PusherClaim.fromJson(held[pusherClaimKey]);
    return _confirmed = said != null && said.by == me.id;
  }

  /// Lets the claim go: this device stops pushing (Remove, or the plugin switched off).
  void release() {
    final me = device();
    _confirmed = false;
    setPreferences((prefs) {
      final was = pusherClaimOf(prefs);
      if (was == null || was.by != me.id) return prefs;
      final more = {...prefs.more}..remove(pusherClaimKey);
      return prefs.copyWith(more: more);
    });
  }
}
