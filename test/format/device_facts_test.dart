// A port of src/app/format/deviceFacts.test.tsx: the hook's logic, as the controller that stands for it. The web
// mounts a component to read the hook; here the controller's value is read directly.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/format/battery.dart';
import 'package:ghost_md/format/device_facts.dart';

import 'fake_battery.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  group('the phone as the AI card reads it', () {
    tearDown(() => useBatterySource(null));

    test('follows the battery as it drains and is plugged in', () async {
      final battery = FakeBattery(false, 0.8);
      useBatterySource(() => Future.value(battery));
      final seen = DeviceFactsController();
      var told = 0;
      seen.addListener(() => told += 1);
      expect(seen.value.battery, isNull);
      await tick();
      expect(seen.value.battery, const BatteryReading(level: 0.8, charging: false));
      battery.drain(0.3);
      battery.plug(true);
      expect(seen.value.battery, const BatteryReading(level: 0.3, charging: true));
      expect(told, 3);
      // Disposed of, it stops listening to the battery.
      seen.dispose();
      battery.plug(false);
    });

    test('leaves the battery out where the phone will not say, or will not be read', () async {
      final seen = DeviceFactsController();
      var told = 0;
      seen.addListener(() => told += 1);
      await tick();
      expect(seen.value.battery, isNull);
      useBatterySource(() => Future.error(Exception('not allowed')));
      final refused = DeviceFactsController()..addListener(() => told += 1);
      await tick();
      expect(refused.value.battery, isNull);
      final none = DeviceFactsController(source: () => Future.value(FakeBattery(true)), noBattery: true)..addListener(() => told += 1);
      await tick();
      expect(none.value.battery, isNull);
      // A battery that will not say is nothing to draw again for.
      expect(told, 0);
    });

    test('reads the cores the browser reports', () {
      // The page read `navigator.hardwareConcurrency || null`; here whoever knows hands the number in.
      expect(DeviceFactsController(cores: 8, memoryGb: 12).value, const DeviceFacts(cores: 8, memoryGb: 12, battery: null));
      expect(DeviceFactsController(cores: 0).value.cores, isNull);
      expect(DeviceFactsController().value.cores, isNull);
    });
  });
}
