/// Whether live sync of the account's own notes runs on this device (docs/LIVE.md, "Switched off until it works").
/// A port of `src/app/core/live/enabled.ts`.
///
/// On by default since 2026-10-17 (docs/CLAUDE_LIVE.md, "Live typing for personal notes": a personal note open on
/// a device joins its room, so Claude can type into it), and off by hand under Settings > Account > Sync ("Live
/// typing"). It takes effect on the next note opened: a note already open keeps working the way it opened. A
/// team's notes do not ask: they are live by being the team's (lib/live/team.dart).
///
/// Kept on the device rather than in the synced settings, so turning it off on one device never turns it off on
/// another: the page's `deviceFlag('glyph-live')` is the same key in [Stored]. A key that was never written is on;
/// `'0'` is off, and a device that turned it on by hand when it was a trial (`'1'`) stays on.
library;

import 'package:flutter/foundation.dart';

import '../core/stored.dart';

/// The key the page keeps it under.
const String liveFlagKey = 'glyph-live';

/// The switch, as this device keeps it.
class LiveEnabled extends ChangeNotifier implements ValueListenable<bool> {
  LiveEnabled(this._kept);

  final Stored _kept;

  /// Whether it is on here: unless this device turned it off (`liveEnabled`).
  @override
  bool get value => _kept.readText(liveFlagKey) != '0';

  /// Turns it on or off here (`setLiveEnabled`).
  void set(bool on) {
    if (on == value) return;
    _kept.writeText(liveFlagKey, on ? '1' : '0');
    notifyListeners();
  }
}
