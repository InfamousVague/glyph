import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';

/// A to-do ticked from a query in another note (lib/core/query/tick.dart), case for case with the web's
/// `core/query/tick.test.ts`.
void main() {
  group('a to-do ticked from a query', () {
    test('turns the box on the line the query read', () {
      expect(tickedBody('# Shop\n\n- [ ] Milk\n- [ ] Eggs', 2, '- [ ] Milk', true), '# Shop\n\n- [x] Milk\n- [ ] Eggs');
      expect(tickedBody('- [x] Milk 📅 2026-10-04', 0, '- [x] Milk 📅 2026-10-04', false), '- [ ] Milk 📅 2026-10-04');
    });

    test('finds the line by its words where the note has moved under it', () {
      expect(tickedBody('# Shop\n\nA new line.\n\n- [ ] Milk', 2, '- [ ] Milk', true), '# Shop\n\nA new line.\n\n- [x] Milk');
    });

    test('leaves alone a line that is gone, or no longer a to-do', () {
      expect(tickedBody('# Shop\n\n- [ ] Bread', 2, '- [ ] Milk', true), isNull);
      expect(tickedBody('- Milk', 0, '- Milk', true), isNull);
    });

    test('changes nothing where the box is already as asked', () {
      const body = '- [x] Milk';
      expect(tickedBody(body, 0, body, true), body);
    });

    test('moves the card on a board in that note into Done, in the same write', () {
      const body = '- [ ] Ship it ^ship\n- [ ] Test it ^test\n\n```board\nTo do: ship, test\nDone:\n```';
      expect(tickedBody(body, 0, '- [ ] Ship it ^ship', true), '- [x] Ship it ^ship\n- [ ] Test it ^test\n\n```board\nTo do: test\nDone: ship\n```');
    });
  });
}
