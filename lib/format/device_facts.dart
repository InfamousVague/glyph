/// What the app can read about the phone on its own, for the AI card: the cores, the memory class, and the battery.
/// An older binary reports nothing from the engine, and this still shows the phone. A port of
/// `src/app/format/deviceFacts.ts`.
///
/// What differs: the page's `useDeviceFacts` is a React hook over `navigator`; here it is [DeviceFactsController], a
/// `ValueNotifier` a widget listens to and disposes of. The cores and the memory class are handed in (the page read
/// `navigator.hardwareConcurrency` and `navigator.deviceMemory`; lib/ may not ask `dart:io`), and so may the
/// battery's source be, which is format/battery.dart's own when left out. A battery reading equal to the last one
/// tells nobody, where the page drew again.
library;

import 'package:flutter/foundation.dart';

import 'battery.dart';

/// A battery that says: how full, and whether it is on charge.
@immutable
class BatteryReading {
  const BatteryReading({required this.level, required this.charging});

  final double level;
  final bool charging;

  @override
  bool operator ==(Object other) => other is BatteryReading && other.level == level && other.charging == charging;

  @override
  int get hashCode => Object.hash(level, charging);

  @override
  String toString() => 'BatteryReading($level, $charging)';
}

/// The phone as the AI card reads it (`DeviceFacts`).
@immutable
class DeviceFacts {
  const DeviceFacts({required this.cores, required this.memoryGb, required this.battery});

  final int? cores;

  /// The device memory class in gigabytes.
  final double? memoryGb;

  final BatteryReading? battery;

  @override
  bool operator ==(Object other) => other is DeviceFacts && other.cores == cores && other.memoryGb == memoryGb && other.battery == battery;

  @override
  int get hashCode => Object.hash(cores, memoryGb, battery);

  @override
  String toString() => 'DeviceFacts($cores, $memoryGb, $battery)';
}

/// The facts, kept current with the battery until disposed of (`useDeviceFacts`). [cores] of zero is no reading, as
/// the page's was. [source] is the battery's source; left out it is the device's own (`batterySource()`), and
/// [noBattery] says the device has none.
class DeviceFactsController extends ValueNotifier<DeviceFacts> {
  DeviceFactsController({int? cores, double? memoryGb, GetBattery? source, bool noBattery = false})
      : super(DeviceFacts(cores: cores == null || cores == 0 ? null : cores, memoryGb: memoryGb, battery: null)) {
    void heard(BatteryState state) {
      // A battery that will not say is no reading at all, and nothing to draw again for.
      final charging = state.charging;
      final level = state.level;
      final battery = charging == null || level == null ? null : BatteryReading(level: level, charging: charging);
      if (_disposed || (battery == null && value.battery == null)) return;
      value = DeviceFacts(cores: value.cores, memoryGb: value.memoryGb, battery: battery);
    }

    _stop = noBattery ? watchBattery(heard, null) : (source == null ? watchBattery(heard) : watchBattery(heard, source));
  }

  late final VoidCallback _stop;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}
