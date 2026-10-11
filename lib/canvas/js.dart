/// The arithmetic the canvas's pure files lean on where JavaScript's and Dart's differ, so a line's path and a
/// canvas's JSON come out character for character as the web app writes them (`src/app/canvas/lines.ts`,
/// `jsonCanvas.ts`; held by tool/canvas_fixtures.mjs).
///
/// - `Math.round` rounds a half up, towards plus infinity (-2.5 is -2); Dart's `round()` goes away from zero.
/// - A number in a template string is the shortest digits that read back as it, with no `.0` on a whole one and no
///   sign on a zero; Dart writes `250.0` and `-0.0`.
/// - `Math.hypot` is not the square root of the squares' sum: V8 divides by the largest first and sums with Kahan's
///   compensation, and the last digit of a curve's reach depends on it.
/// - `Array.prototype.sort` is stable; Dart's `List.sort` is not promised to be.
library;

import 'dart:math' as math;

/// `Math.round`.
double jsRound(double value) {
  if (!value.isFinite) return value;
  final floor = value.floorToDouble();
  return value - floor >= 0.5 ? floor + 1 : floor;
}

/// `String(number)` for a finite number: `250`, `-3.5`, `0` for either zero, `1e+21`.
String jsNumber(double value) {
  if (value == 0) return '0';
  // Dart prints the same shortest digits, with `.0` after a whole number.
  final text = value.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// `Math.hypot(x, y)`, as V8 works it out.
double jsHypot(double x, double y) {
  if (x.isNaN || y.isNaN) return x.isInfinite || y.isInfinite ? double.infinity : double.nan;
  final a = x.abs();
  final b = y.abs();
  final max = math.max(a, b);
  if (max == double.infinity) return double.infinity;
  if (max == 0) return 0;
  var sum = 0.0;
  var compensation = 0.0;
  for (final each in [a, b]) {
    final n = each / max;
    final summand = n * n - compensation;
    final preliminary = sum + summand;
    compensation = (preliminary - sum) - summand;
    sum = preliminary;
  }
  return math.sqrt(sum) * max;
}

/// `Math.sign`: -1, 0 or 1.
double jsSign(double value) => value > 0 ? 1 : (value < 0 ? -1 : 0);

/// `list.sort(compare)`, keeping the order of what compares equal.
void stableSort<T>(List<T> list, double Function(T a, T b) compare) {
  for (var i = 1; i < list.length; i += 1) {
    final each = list[i];
    var j = i - 1;
    while (j >= 0 && compare(list[j], each) > 0) {
      list[j + 1] = list[j];
      j -= 1;
    }
    list[j + 1] = each;
  }
}
