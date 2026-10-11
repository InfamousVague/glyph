// A port of src/app/format/battery.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/format/battery.dart';

import 'fake_battery.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  group('watching the battery', () {
    test('says now, and again when the phone is plugged in or unplugged', () async {
      final battery = FakeBattery(false, 0.4);
      final heard = <bool?>[];
      final stop = watchBattery((state) => heard.add(state.charging), () => Future.value(battery));
      await tick();
      battery.plug(true);
      battery.plug(false);
      stop();
      battery.plug(true);
      expect(heard, [false, true, false]);
    });

    test('answers unknown where the phone will not say', () {
      final heard = <Object?>[];
      watchBattery(heard.add, null);
      expect(heard, [unknown]);
      // Left out, the source is the device's own, and this device has none.
      heard.clear();
      watchBattery(heard.add);
      expect(heard, [unknown]);
    });

    test('answers unknown when the battery cannot be read', () async {
      final heard = <Object?>[];
      watchBattery(heard.add, () => Future.error(Exception('no')));
      await tick();
      expect(heard, [unknown]);
    });
  });
}
