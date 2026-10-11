/// The recorder's cards (lib/capture/ui/capture_cards.dart): items landing in a list.
/// `src/app/capture/CaptureCards.test.tsx`, its one case.
///
/// What differs: the note's name is drawn in the capitals its style gives it, where the page's `textContent` read the
/// word before the stylesheet had its say.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/ui/capture_cards.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  group('items landing in another note', () {
    testWidgets('shows the list’s last lines as they were, then the new ones, all without their marks', (tester) async {
      const body = '# Shopping\n\n- Eggs\n- Bread\n- [ ] Milk\n\n- Oat milk\n- Bin bags';
      await pumpApp(tester, home: const Align(child: ListLanding(title: 'Shopping', body: body, added: ['- Oat milk', '- Bin bags'])));
      final lines = tester.widgetList<Text>(find.descendant(of: find.byType(ListLanding), matching: find.byType(Text))).map((line) => line.data ?? line.textSpan!.toPlainText()).toList();
      expect(lines, ['SHOPPING', 'Milk', 'Oat milk', 'Bin bags']);

      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
