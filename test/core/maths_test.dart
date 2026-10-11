import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/maths.dart';

/// Maths by Pandoc's rule (lib/core/maths.dart), case for case with the web's `core/maths.test.ts`.

/// The maths found in a line, as the words it covers.
List<String> found(String line) => [for (final m in mathsIn(line)) line.substring(m.from, m.to)];

void main() {
  group('maths, by Pandoc’s rule', () {
    test('finds maths inline and on a line', () {
      expect(found(r'$x^2$'), [r'$x^2$']);
      expect(found(r'$$a+b$$'), [r'$$a+b$$']);
      expect(found(r'where $n$ is 3'), [r'$n$']);
      expect(found(r'when $x^2 + y$ holds'), [r'$x^2 + y$']);
    });

    test('reads two prices on a line as prices', () {
      expect(found(r'$200 and $45'), isEmpty);
      expect(found(r'It costs $5, or $6 with tax.'), isEmpty);
      expect(found(r'Cabin $200, ferry $45, food $80'), isEmpty);
      expect(found(r'it cost $20 and $30'), isEmpty);
    });

    test('leaves a budget line alone with a filled answer in it', () {
      expect(found(r'Budget $500 for ??$200??(Qwen3.5 4B from memory, 2026-09-28. Asked: the deposit) and the rest'), isEmpty);
      expect(found(r'Total so far: $325, and ??$40??(Qwen3.5 4B from memory, 2026-09-28) for the taxi'), isEmpty);
    });

    test('needs a word against each dollar sign, and none after a backslash', () {
      expect(found(r'$ 5 $'), isEmpty);
      expect(found(r'\$200 and \$45'), isEmpty);
    });

    test('counts from an offset', () {
      expect(mathsIn(r'so $n$', 10), [(from: 13, to: 16)]);
    });
  });
}
