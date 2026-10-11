/// The phone's own time zone, and its own time-zone database for the zones a blank's time is worked out in: what
/// Ghost.md's page has from `Intl` (`resolvedOptions().timeZone`, and `timeZoneName: 'shortOffset'` for a zone's
/// offset: core/fillFacts.ts `offsetMinutes`). The Dart half of `ghost_md/dates`' `zone` and `offsets`
/// (android/…/ghost_md/Dates.kt).
///
/// Asked once, as the app starts, and waited for by nothing: a blank is worked out long after. The answer is the
/// phone's zone by its name, and for each zone asked about (the solver's cities', lib/ai/support/time_zones.dart,
/// and the phone's own) its offset at the window's start and every change of it across the window, last year to
/// forty years on. lib/core/fill_facts.dart reads both through [deviceZone] and [deviceOffsets]: "Tokyo is 13
/// hours ahead of New York today." where it said "…ahead of here", and a zone's summer time by the phone's own
/// rules, whatever year it is, where a table stopped at 2040.
///
/// A phone with no such channel (an iPhone, a Mac) answers nothing, and the solver is as it was: the table, and
/// "here".
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../ai/support/time_zones.dart';
import 'fill_facts.dart';

const MethodChannel _dates = MethodChannel('ghost_md/dates');

int _minute(DateTime at) => (at.millisecondsSinceEpoch / 60000).floor();

/// The phone's answer as [deviceOffsets] reads it: each zone's offset at `from`, then pairs, the minute a change
/// takes hold and the offset from then on; null outside `from` to `to`, and for a zone not answered for.
int? Function(String zone, DateTime at) offsetsFrom(Map<String, List<int>> tables, {required int from, required int to}) => (zone, at) {
      final table = tables[zone];
      final minute = _minute(at);
      if (table == null || table.isEmpty || minute < from || minute >= to) return null;
      // The pairs after the first number: the last change at or before the minute.
      var low = 0;
      var high = (table.length - 1) ~/ 2;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (table[mid * 2 - 1] <= minute) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      return low == 0 ? table[0] : table[low * 2];
    };

/// Asks the phone for its zone and its clocks and keeps them ([deviceZone], [deviceOffsets]). Never fails: a phone
/// that does not answer leaves both as they were.
Future<void> usePhoneZones({MethodChannel channel = _dates, DateTime? now}) async {
  try {
    final zone = await channel.invokeMethod<String>('zone');
    final at = now ?? DateTime.now();
    final from = _minute(DateTime.utc(at.year - 1)), to = _minute(DateTime.utc(at.year + 40));
    final zones = <String>{...cityZones.values, if (zone != null && zone.isNotEmpty) zone}.toList();
    final answer = await channel.invokeMethod<Object?>('offsets', {'zones': zones, 'from': from, 'to': to});
    if (zone != null && zone.isNotEmpty) deviceZone = zone;
    if (answer is! Map) return;
    final tables = <String, List<int>>{};
    for (final MapEntry(:key, :value) in answer.entries) {
      if (key is! String || value is! List || value.isEmpty || value.length.isEven || value.any((n) => n is! int)) continue;
      tables[key] = value.cast<int>();
    }
    if (tables.isNotEmpty) deviceOffsets = offsetsFrom(tables, from: from, to: to);
  } on MissingPluginException {
    // No phone half: the table and "here".
  } on PlatformException {
    // The phone would not say.
  }
}
