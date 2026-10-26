/// Which kinds of meeting Ghost joins, Google Meet and Zoom each a plugin of its own (Matt, 2026-10-26: "Make sure the
/// Google Meet and the Zoom plugins are two different plugins", and the same day: "I want settings / meetings to be
/// broken up into three plugins where each zoom, Google meets and discord handle their own meetings").
///
/// A kind is the service's word for where a meeting is (`meet`, `zoom`; server/src/meet.rs `KINDS`), and each has its
/// plugin (lib/plugins/meetings/): the plugin's switch is whether Ghost joins that kind at all. On the device that is
/// the registry's switch, read here; on the service it is the account's `meet/kinds`, since invites are booked there,
/// from mail, while no device is awake. So the device tells the service:
///
/// - **when a switch moves** ([MeetIn] hears the registry): what the switches say now is kept as unsent
///   ([unsentKindsKey]) and sent at once;
/// - **at sync** ([syncMeet]): anything still unsent (the phone was offline, or signed out, when the switch moved) is
///   sent again, until the service has it.
///
/// Only a switch that moved is sent, never the switches as they stand at a pass: a device that has not yet had the
/// account's switches through the sealed keys (lib/sync/connections.dart, where `google-meet` and `zoom` travel as
/// every other plugin's switch does) would otherwise tell the service its own defaults over a choice made elsewhere.
/// The service starts every kind on, as the plugins ship on.
///
/// Discord's calls are a kind of their own, `discord`, once they are booked (the Discord plugin's); [meetKindWords]
/// names it and the meetings' list takes it, but it has no switch here until the service books it.
library;

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../core/stored.dart';
import '../plugins/registry.dart' show Registry, plugins;
import 'meet_api.dart' show meetNoRoute;

/// The kinds a plugin's switch turns on and off, each to its plugin's id.
const Map<String, String> meetKindPlugins = {'meet': 'google-meet', 'zoom': 'zoom'};

/// A kind as a sentence names it: "Google Meet", "Zoom", "Discord".
String meetKindWords(String kind) => switch (kind) {
      'meet' => 'Google Meet',
      'zoom' => 'Zoom',
      'discord' => 'Discord',
      _ => kind,
    };

/// The kind of a link Ghost can join ([meetLink]'s): `zoom` for a Zoom's, else `meet`.
String meetKindOfLink(String url) => RegExp(r'^https://([a-z0-9-]+\.)?zoom\.us/', caseSensitive: false).hasMatch(url) ? 'zoom' : 'meet';

/// What "Join" with a link of a kind turned off says, as the service says it (server/src/meet.rs `turn_on_words`).
String meetTurnOnWords(String kind) {
  final words = meetKindWords(kind);
  return 'Turn on the $words plugin to send Ghost to $words calls.';
}

/// Whether Ghost joins [kind] here: its plugin on in [registry] (the app's), Local only included; a kind with no plugin
/// in the registry (a test's, or before the plugins are put in place) is on, as the service starts it.
bool meetKindOn(String kind, {Registry? registry}) {
  final reg = registry ?? plugins;
  final id = meetKindPlugins[kind];
  if (id == null || reg.byId(id) == null) return true;
  return reg.isEnabled(id);
}

/// The kinds as the switches say them, each kind whose plugin is in [registry]: the person's choice, whatever Local
/// only says ([Registry.switchedOn]), since it is what the account wants on every device.
Map<String, bool> meetKindsWanted({Registry? registry}) {
  final reg = registry ?? plugins;
  return {
    for (final MapEntry(key: kind, value: id) in meetKindPlugins.entries)
      if (reg.byId(id) != null) kind: reg.switchedOn(id),
  };
}

/// Where the kinds the service has not taken yet wait, in the device's storage: a map of kind to on, or nothing.
const String unsentKindsKey = 'glyph-meet-kinds-unsent';

Map<String, bool>? _unsent(Stored kept) => kept.read<Map<String, bool>?>(
      unsentKindsKey,
      null,
      (raw) => raw is Map ? {for (final MapEntry(:key, :value) in raw.entries) if (key is String && value is bool) key: value} : null,
    );

/// [wanted] kept as unsent: a switch moved.
void keepKindsUnsent(Stored kept, Map<String, bool> wanted) => kept.write(unsentKindsKey, wanted.isEmpty ? null : wanted);

/// Sends the kinds kept unsent, if any, and forgets them once the service has them. Answers whether anything was sent.
/// Quiet against a service from before kinds (no such route): the kinds are then forgotten too, as there is nothing
/// to tell. Any other failure keeps them for the next pass.
Future<bool> sendUnsentKinds({required Api api, required String token, required Stored kept}) async {
  final unsent = _unsent(kept);
  if (unsent == null || unsent.isEmpty) return false;
  try {
    await api.callMap('PUT', 'meet/kinds', token: token, body: unsent);
  } catch (failure) {
    if (meetNoRoute(failure)) {
      kept.write(unsentKindsKey, null);
      return false;
    }
    debugPrint('[meet] the plugins\' kinds were not sent: $failure');
    return false;
  }
  // Moved again while it was on its way: what is kept now is sent at the next chance.
  if (mapEquals(_unsent(kept), unsent)) kept.write(unsentKindsKey, null);
  return true;
}
