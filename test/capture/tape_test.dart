import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/tape.dart';

/// The tape's geometry (lib/capture/tape.dart, which is lib/tapes/tape.dart), case for case with the web's
/// `capture/tape.test.ts`.
void main() {
  group('the tape', () {
    test('starts full on the left and ends full on the right, conserving tape', () {
      expect(packRadii(0), (supply: packMaxR, takeup: packMinR));
      final end = packRadii(tapeMs * 2);
      expect(end.supply, closeTo(packMinR, 0.005));
      expect(end.takeup, closeTo(packMaxR, 0.005));
      final mid = packRadii(tapeMs / 3);
      expect(mid.supply * mid.supply + mid.takeup * mid.takeup, closeTo(packMaxR * packMaxR + packMinR * packMinR, 0.005));
    });

    test('fills the cassette over a longer tape when told how long it is', () {
      // Three minutes on a five-minute tape is over half wound; on an hour's tape it is a thin ring.
      const hour = 3600000;
      expect(packRadii(180000).takeup, greaterThan((packMinR + packMaxR) / 2));
      expect(packRadii(180000, hour).takeup, lessThan(packMinR + 3));
      // The whole of the tape fills the right reel, whatever its length.
      expect(packRadii(hour, hour).takeup, closeTo(packMaxR, 0.005));
      expect(packRadii(hour, hour).supply, closeTo(packMinR, 0.005));
      // Left unsaid, the length is the five-minute tape it always was.
      expect(packRadii(tapeMs, tapeMs), packRadii(tapeMs));
      // The reels turn over the radii the length gives: a nearly empty take-up reel turns fast.
      expect(reelTurn(180000, 1000, hour).takeup, greaterThan(reelTurn(180000, 1000).takeup));
    });

    test('turns the smaller pack faster for the same tape', () {
      final early = reelTurn(0, 1000);
      expect(early.takeup, greaterThan(early.supply));
      final late = reelTurn(tapeMs, 1000);
      expect(late.supply, greaterThan(late.takeup));
    });

    test('reads like a tape counter', () {
      expect(counter(0), '0:00');
      expect(counter(7900), '0:07');
      expect(counter(760000), '12:40');
      expect(counter(3723000), '1:02:03');
    });
  });
}
