/// The phone's battery as the AI card reads it (lib/format/battery.dart): what the page's WebView answered
/// `navigator.getBattery()` with, asked of the phone itself (`ghost_md/battery`, android/…/ghost_md/Battery.kt).
///
/// One battery for the app, in the web's shape ([BatteryLike]): on charge or off, how full from 0 to 1, and its two
/// events. [phoneBattery] is what [useBatterySource] is given at launch on Android. The phone is asked once how
/// things stand (`watch`) and tells of each change after (`changed`); where nothing answers the channel (a Mac, an
/// iPhone, a test) the asking fails, which the card reads as a phone that will not say, and leaves the reading out.
library;

import 'package:flutter/services.dart';

import '../format/battery.dart';

const MethodChannel batteryChannel = MethodChannel('ghost_md/battery');

/// The phone's battery, kept as the phone tells of it.
class PhoneBattery implements BatteryLike {
  PhoneBattery._(this._channel);

  final MethodChannel _channel;
  final Map<BatteryEvent, Set<VoidCallback>> _listeners = <BatteryEvent, Set<VoidCallback>>{};
  bool _charging = false;
  double _level = 1;
  bool _hearing = false;

  @override
  bool get charging => _charging;

  @override
  double get level => _level;

  @override
  void addEventListener(BatteryEvent type, VoidCallback listener) => _listeners.putIfAbsent(type, () => <VoidCallback>{}).add(listener);

  @override
  void removeEventListener(BatteryEvent type, VoidCallback listener) => _listeners[type]?.remove(listener);

  /// What the phone said, kept; with [tell], whoever listens for what moved is told.
  void _take(Map<Object?, Object?> said, {required bool tell}) {
    final charging = said['charging'], level = said['level'];
    final charged = charging is bool && charging != _charging;
    final moved = level is num && level.toDouble() != _level;
    if (charging is bool) _charging = charging;
    if (level is num) _level = level.toDouble().clamp(0, 1);
    if (!tell) return;
    if (charged) _say(BatteryEvent.chargingchange);
    if (moved) _say(BatteryEvent.levelchange);
  }

  void _say(BatteryEvent event) {
    for (final listener in [...?_listeners[event]]) {
      listener();
    }
  }

  Future<void> _watch() async {
    if (!_hearing) {
      _hearing = true;
      _channel.setMethodCallHandler((call) async {
        final said = call.arguments;
        if (call.method == 'changed' && said is Map) _take(said, tell: true);
        return null;
      });
    }
    final said = await _channel.invokeMapMethod<Object?, Object?>('watch');
    if (said == null) throw StateError('The phone did not say how its battery is.');
    _take(said, tell: false);
  }
}

/// The way to the phone's battery (`navigator.getBattery`): the same battery each time, read afresh as it is asked
/// for. Fails where the phone has no half to answer, or will not say.
GetBattery phoneBattery({MethodChannel channel = batteryChannel}) {
  final battery = PhoneBattery._(channel);
  return () async {
    await battery._watch();
    return battery;
  };
}
