/// Whether live sync of the account's own notes runs on this device (docs/LIVE.md, "Switched off until it works").
/// A port of `src/app/core/live/enabled.ts`.
///
/// Off by default, and on by hand under Settings > Account > Sync ("Live typing"), while it is still being tried on
/// real devices. It takes effect on the next note opened: a note already open keeps working the way it opened. A
/// team's notes do not ask: they are live by being the team's (lib/live/team.dart).
///
/// Kept on the device rather than in the synced settings, so trying it on one device never turns it on for
/// another: the page's `deviceFlag('glyph-live')` is the same key in [Stored].
library;

import 'package:flutter/foundation.dart';

import '../core/stored.dart';

/// The key the page keeps it under.
const String liveFlagKey = 'glyph-live';

/// The switch, as this device keeps it.
class LiveEnabled extends ChangeNotifier implements ValueListenable<bool> {
  LiveEnabled(this._kept);

  final Stored _kept;

  /// Whether this device asked for it (`liveEnabled`).
  @override
  bool get value => _kept.readText(liveFlagKey) == '1';

  /// Turns it on or off here (`setLiveEnabled`).
  void set(bool on) {
    if (on == value) return;
    _kept.writeText(liveFlagKey, on ? '1' : null);
    notifyListeners();
  }
}
