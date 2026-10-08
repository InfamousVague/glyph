import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/sums.dart';

/// The arithmetic a sum and a query's totals share (lib/core/sums.dart), case for case with the web's
/// `core/sums.test.ts`. The sums themselves are tested on the web where they are drawn (`editor/sums.test.ts`); the
/// last group here holds [answer] and [sumOnLine] to the examples in the module's own comments, and the figures an
/// answer is written in to what `toLocaleString('en-US', …)` writes.
void main() {
  group('a number as a sum reads one', () {
    test('reads a value that is only a number', () {
      expect(writtenNumber('3'), 3);
      expect(writtenNumber(r' $1,200 '), 1200);
      expect(writtenNumber('-2.5'), -2.5);
      expect(writtenNumber('−4'), -4);
      expect(writtenNumber('50%'), 0.5);
      expect(writtenNumber('3 days'), isNull);
      expect(writtenNumber('GHO-12'), isNull);
      expect(writtenNumber(''), isNull);
    });

    test('reads the number a value starts with', () {
      expect(leadingNumber('3 days'), '3');
      expect(leadingNumber(r'$1,200 a month'), r'$1,200');
      expect(leadingNumber('- 2.5'), '-2.5');
      expect(leadingNumber('about 3'), isNull);
    });
  });

  group('a total', () {
    test('adds the numbers the values start with, as a sum would', () {
      expect(totalOf(['3', '2.5 days', '1']), '6.5');
      expect(totalOf([r'$1,200', r'$300']), r'$1,500');
      expect(totalOf([r'$12', r'$4.50']), r'$16.50');
      expect(totalOf(['5', '-2']), '3');
    });

    test('is the value itself where there is one, and nothing where none has a number', () {
      expect(totalOf(['7']), '7');
      expect(totalOf(['soon', 'later']), isNull);
      expect(totalOf([]), isNull);
    });

    test('agrees with the sum of the same numbers', () {
      expect(totalOf(['1,000', '2,500']), answer('1,000 + 2,500'));
    });
  });

  group('a sum, from the module’s own examples (not in the web’s core/sums.test.ts)', () {
    test('works out the two lines its comment shows', () {
      expect(sumOnLine('= 450 + 120 * 2'), (answer: '690'));
      expect(sumOnLine(r'- = $1,200 / 3'), (answer: r'$400'));
      expect(sumOnLine('> = 2 ^ 10'), (answer: '1024'));
      expect(sumOnLine('= 450'), isNull);
      expect(sumOnLine('=450 + 1'), isNull);
      expect(sumOnLine('= two + 2'), isNull);
    });

    test('answers only arithmetic: powers, percents, brackets, and the signs a keyboard writes', () {
      expect(answer('2 ^ 3 ^ 2'), '512');
      expect(answer('200 * 15%'), '30');
      expect(answer('(1 + 2) * 3'), '9');
      expect(answer('6 × 7'), '42');
      expect(answer('9 ÷ 3'), '3');
      expect(answer('-3 + 1'), '−2');
      expect(answer('1 / 0'), isNull);
      expect(answer('(1 + 2'), isNull);
      expect(answer('1 +'), isNull);
    });

    test('writes its figures as en-US does: commas when asked for, two places for money, at most six otherwise', () {
      expect(answer('1 / 3'), '0.33');
      expect(answer('1000 * 1000'), '1000000');
      expect(answer('1,000 * 1,000'), '1,000,000');
      expect(answer(r'$10 / 4'), r'$2.50');
      expect(answer(r'$10 / 5'), r'$2');
      expect(answer('£1234.5 + 0'), '£1,234.50');
      expect(answer('0 - 2.5'), '−2.5');
      // A number too long for a double is written from its shortest form, as JavaScript writes it.
      expect(answer('10 ^ 21'), '999999999999999900000');
      expect(answer('10 ^ 22'), '10000000000000000000000');
      expect(answer('1,000 * 2 ^ 70'), '1,180,591,620,717,411,300,000,000');
    });
  });
}
