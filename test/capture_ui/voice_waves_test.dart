/// The rings behind the recorder's mic (lib/capture/ui/voice_waves.dart): a layer that is decoration only, and empty
/// until the layer has a size. `src/app/capture/VoiceWaves.test.tsx`, its one case.
///
/// What differs: jsdom laid nothing out, so its layer was always 0 by 0. Here a layer is laid out the moment it is
/// drawn, so the case gives it a box of no size for the page's half, and then a real one, where the rings do rise and
/// never more than nine at once.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/ui/voice_waves.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  group('the voice’s rings', () {
    testWidgets('draws nothing a screen reader or a touch could reach, and no rings before the layer is laid out', (tester) async {
      await pumpApp(tester, home: Center(child: SizedBox(width: 0, height: 0, child: VoiceWaves(anchor: GlobalKey()))));
      final layer = find.byKey(const Key('voice-waves'));
      expect(tester.widget<IgnorePointer>(layer).ignoring, isTrue);
      expect(find.descendant(of: layer, matching: find.byType(ExcludeSemantics)), findsOneWidget);
      // The layer is 0 by 0, so nothing is drawn into it.
      expect(find.byKey(const Key('voice-waves-rings')), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('voice-waves-rings')), findsNothing);

      // Laid out, over a mic: rings leave it, and never more than nine are out at once.
      final mic = GlobalKey();
      await pumpApp(
        tester,
        home: Stack(
          key: UniqueKey(),
          children: [
            Positioned.fill(child: VoiceWaves(anchor: mic)),
            Positioned(left: 20, top: 40, child: SizedBox(key: mic, width: 14, height: 14)),
          ],
        ),
      );
      var most = 0;
      for (var i = 0; i < 80; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
        final rings = find.byKey(const Key('voice-waves-rings'));
        if (rings.evaluate().isEmpty) continue;
        final painter = tester.widget<CustomPaint>(rings).painter! as VoiceRingsPainter;
        if (painter.count > most) most = painter.count;
        expect(painter.at, const Offset(27, 47));
      }
      expect(most, greaterThan(0));
      expect(most, lessThanOrEqualTo(mostRings));

      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
