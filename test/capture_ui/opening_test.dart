/// The recorder's picture while nothing has been heard (lib/capture/ui/opening.dart), and when the microphone never
/// opened. `src/app/capture/Opening.test.tsx`, its one case.
///
/// What differs: the page's arcs were three paths to count and a `data-failed` to read; here they are what the
/// picture's painter holds.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/ui/opening.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  group('the recorder’s picture of sound beginning', () {
    testWidgets('draws its three arcs, dashed when the microphone never opened', (tester) async {
      OpeningPainter painter() => tester.widget<CustomPaint>(find.descendant(of: find.byType(Opening), matching: find.byType(CustomPaint))).painter! as OpeningPainter;

      await pumpApp(tester, home: Align(key: UniqueKey(), child: const Opening()));
      expect(OpeningPainter.radii, hasLength(3));
      expect(painter().failed, isFalse);
      expect(painter().dash, isNull);
      await tester.pump(const Duration(seconds: 2));

      await pumpApp(tester, home: Align(key: UniqueKey(), child: const Opening(failed: true)));
      expect(painter().failed, isTrue);
      expect(painter().dash, [6, 7]);

      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
