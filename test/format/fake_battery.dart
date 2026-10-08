// A phone battery a test can drain and plug in: the slice format/battery.dart watches, with its events fired by
// hand. A port of the web's test/battery.ts.
import 'dart:ui' show VoidCallback;

import 'package:ghost_md/format/battery.dart';

class FakeBattery implements BatteryLike {
  FakeBattery(this.charging, [this.level = 0.5]);

  @override
  bool charging;

  @override
  double level;

  final Set<VoidCallback> _listeners = {};

  @override
  void addEventListener(BatteryEvent type, VoidCallback listener) => _listeners.add(listener);

  @override
  void removeEventListener(BatteryEvent type, VoidCallback listener) => _listeners.remove(listener);

  void plug(bool on) {
    charging = on;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  void drain(double to) {
    level = to;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }
}
