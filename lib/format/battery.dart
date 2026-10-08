/// The phone's battery, live: whether it is on charge and how full it is, for the AI card's Battery reading
/// (format/device_facts.dart). A port of `src/app/format/battery.ts`.
///
/// The page reads the browser's Battery API; where that is missing the state is unknown and the card leaves the
/// reading out rather than guessing. The source is injectable, so a test can plug the phone in. A source that
/// refuses to be read is unknown the same way.
///
/// What differs: there is no `navigator` here, so [batterySource] answers whatever [useBatterySource] was last
/// given and null until then: the platform's battery (a plugin, a channel) is handed in by whoever holds it, in the
/// web's shape, [BatteryLike]. An event's name is a [BatteryEvent] where the page had two strings.
library;

import 'package:flutter/foundation.dart';

/// On charge or off, and how full (`BatteryState`).
@immutable
class BatteryState {
  const BatteryState({required this.charging, required this.level});

  /// On charge, off charge, or null when the phone won't say.
  final bool? charging;

  /// 0 to 1, or null.
  final double? level;

  @override
  bool operator ==(Object other) => other is BatteryState && other.charging == charging && other.level == level;

  @override
  int get hashCode => Object.hash(charging, level);

  @override
  String toString() => 'BatteryState($charging, $level)';
}

/// What a battery tells its listeners of: `chargingchange` and `levelchange`.
enum BatteryEvent { chargingchange, levelchange }

/// The slice of the Battery API this uses (`BatteryLike`).
abstract class BatteryLike {
  bool get charging;
  double get level;
  void addEventListener(BatteryEvent type, VoidCallback listener);
  void removeEventListener(BatteryEvent type, VoidCallback listener);
}

/// The way to a battery (`GetBattery`).
typedef GetBattery = Future<BatteryLike> Function();

GetBattery? _source;

/// The device's battery source, or null where there is none (`batterySource`).
GetBattery? batterySource() => _source;

/// Makes [source] the device's battery source; null for a device that will not say.
void useBatterySource(GetBattery? source) => _source = source;

/// A phone that won't say (`UNKNOWN`).
const BatteryState unknown = BatteryState(charging: null, level: null);

/// Stands for "the device's own source" where the page's default argument was `batterySource()`.
Future<BatteryLike> _devices() => Future.error(StateError('no battery'));

/// Tells [listener] the battery's state now and whenever it changes. Answers the way to stop listening. With no
/// source, or one that fails, the listener hears [unknown] once and nothing more. [source] left out is
/// [batterySource]; null is a device with none.
VoidCallback watchBattery(void Function(BatteryState state) listener, [GetBattery? source = _devices]) {
  final from = identical(source, _devices) ? batterySource() : source;
  if (from == null) {
    listener(unknown);
    return () {};
  }
  BatteryLike? battery;
  var stopped = false;
  void tell() {
    final found = battery;
    if (found != null && !stopped) listener(BatteryState(charging: found.charging, level: found.level));
  }

  () async {
    try {
      final found = await from();
      if (stopped) return;
      battery = found;
      found.addEventListener(BatteryEvent.chargingchange, tell);
      found.addEventListener(BatteryEvent.levelchange, tell);
      tell();
    } catch (_) {
      if (!stopped) listener(unknown);
    }
  }();
  return () {
    stopped = true;
    battery?.removeEventListener(BatteryEvent.chargingchange, tell);
    battery?.removeEventListener(BatteryEvent.levelchange, tell);
  };
}
