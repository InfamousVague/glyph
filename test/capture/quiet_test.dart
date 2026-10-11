import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/quiet.dart';

/// "Stop when I go quiet" (lib/capture/quiet.dart), case for case with the web's `capture/quiet.test.ts`.

/// Feeds [rms] five times a second from [from] to [to] ms.
void hum(QuietWatch watch, double rms, int from, int to) {
  for (var t = from; t < to; t += 200) {
    watch.level(rms, t);
  }
}

void main() {
  group('stop when I go quiet', () {
    test('never stops before the first words, however quiet or loud it is', () {
      final watch = QuietWatch(4000);
      hum(watch, 0.005, 0, 3000);
      hum(watch, 0.2, 3000, 3400); // a door
      hum(watch, 0.005, 3400, 20000);
      expect(watch.due(20000), false);
      expect(watch.remaining(20000), isNull);
    });

    test('stops four seconds after talking ends', () {
      final watch = QuietWatch(4000);
      hum(watch, 0.005, 0, 1000);
      hum(watch, 0.15, 1000, 5000); // talking
      watch.words(4200);
      hum(watch, 0.006, 5000, 12000);
      expect(watch.due(8600), false);
      expect(watch.due(9000), true);
    });

    test('a steady fan is the floor, not talking', () {
      final watch = QuietWatch(4000);
      hum(watch, 0.15, 0, 3000);
      watch.words(3000);
      hum(watch, 0.03, 3000, 30000); // the fan, after the voice stops
      expect(watch.due(30000), true);
    });

    test('late words keep it going', () {
      final watch = QuietWatch(4000);
      hum(watch, 0.15, 0, 2000);
      hum(watch, 0.005, 2000, 7000);
      watch.words(5500); // the recogniser catching up on what was said
      expect(watch.due(7000), false);
      expect(watch.due(9600), true);
    });
  });
}
