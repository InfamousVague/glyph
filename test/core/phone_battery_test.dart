// The phone's battery as the AI card reads it (lib/core/phone_battery.dart over lib/format/battery.dart), against a
// phone played on its channel: what `navigator.getBattery()` was to the page.
//
// Unwired 23 (docs/PARITY.md): `useBatterySource` had no caller, so the card never had a Battery reading.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/phone_battery.dart';
import 'package:ghost_md/format/battery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  /// The phone says the battery changed, as Battery.kt does.
  Future<void> phoneSays(Map<String, Object?> state) => messenger.handlePlatformMessage(batteryChannel.name, codec.encodeMethodCall(MethodCall('changed', state)), (_) {});

  tearDown(() => messenger.setMockMethodCallHandler(batteryChannel, null));

  test('says how the battery stands now, and again each time the phone says it is on charge, off it, or fuller', () async {
    var asked = 0;
    messenger.setMockMethodCallHandler(batteryChannel, (call) async {
      asked += 1;
      return call.method == 'watch' ? {'charging': true, 'level': 0.82} : null;
    });
    final heard = <BatteryState>[];
    final stop = watchBattery(heard.add, phoneBattery());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1);
    expect(heard, [const BatteryState(charging: true, level: 0.82)]);

    await phoneSays({'charging': false, 'level': 0.82});
    expect(heard.last, const BatteryState(charging: false, level: 0.82));
    await phoneSays({'charging': false, 'level': 0.81});
    expect(heard.last, const BatteryState(charging: false, level: 0.81));
    expect(heard, hasLength(3));
    // Said again as it stands (the phone's broadcast also comes for its voltage and its heat): nobody is told.
    await phoneSays({'charging': false, 'level': 0.81});
    expect(heard, hasLength(3));
    stop();
    await phoneSays({'charging': true, 'level': 0.9});
    expect(heard, hasLength(3));
  });

  test('is a phone that will not say where nothing answers, and the card leaves the reading out', () async {
    final heard = <BatteryState>[];
    watchBattery(heard.add, phoneBattery());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(heard, [unknown]);
    // A phone whose broadcast does not say how full: the same.
    messenger.setMockMethodCallHandler(batteryChannel, (call) async => null);
    heard.clear();
    watchBattery(heard.add, phoneBattery());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(heard, [unknown]);
  });
}
