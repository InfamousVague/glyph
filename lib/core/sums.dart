/// A sum's arithmetic: what a line that starts with `=` works out (Matt picked sums from the list of new formats),
/// and what a query's `total:` adds up. A port of `src/app/core/sums.ts`, one to one.
///
///     = 450 + 120 * 2          → 690
///     - = $1,200 / 3           → $400
///
/// Only arithmetic: numbers, `+ - * /`, `^` for powers, `%` after a number for a percent, and brackets, worked out
/// by a small precedence-climbing evaluator. A currency sign or thousands commas come back on the answer. Anything
/// else - a word, a sum that can't be done - answers nothing. The editor draws the answer after the line.
///
/// Here in core and not beside the drawing, because a reader away from the editor needs the same answer (Matt asked
/// for "notion and jira like features", and a query's `total: estimate` was one, docs/DESIGN.md §159): the estimates
/// a query lists are added as a sum of them would be, `$1,200` read the way a sum reads it and the total written the
/// way a sum writes its answer, so the two never disagree about the same numbers.
///
/// What differs: the answer's figures. The web writes them with `toLocaleString('en-US', …)`; there is no `Intl`
/// here without a package, so [_enUs] writes the same thing by hand from the number's shortest form: thousands
/// commas, and between the least and the most decimals asked for, rounded half up. `sumOnLine` answers a record
/// where the web answers an object literal. JavaScript's `Math.round` and `**` are [_jsRound] and [_jsPow], which
/// keep its answers at a half below nought and at one to the power of infinity.
library;

import 'dart:math' as math;

import 'item_syntax.dart' show jsTrim, markerPattern;

/// The start of a line, past an indent, a bullet and a quote mark, then `=` and a space.
final RegExp _lead = RegExp('^(\\s*(?:$markerPattern\\s+)?(?:>\\s*)?)=\\s+(.+)\$');
final RegExp _currency = RegExp(r'[$€£¥₹]');

/// A number as a sum reads one: a currency sign, digits with or without thousands commas, a fraction, a percent.
final RegExp _written = RegExp(r'^[$€£¥₹]?(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?%?');
final RegExp _operator = RegExp(r'^[-+*/^()×÷]');
final RegExp _space = RegExp(r'\s+');

/// A number, or an operator: [op] is null for a number.
class _Token {
  const _Token.number(this.value) : op = null;
  const _Token.operator(String this.op) : value = 0;

  final double value;
  final String? op;
}

List<_Token>? _tokens(String expr) {
  final out = <_Token>[];
  final text = expr.replaceAll(_space, '');
  var i = 0;
  while (i < text.length) {
    final rest = text.substring(i);
    final number = _written.firstMatch(rest);
    if (number != null) {
      final digits = number.group(1)!.replaceAll(',', '') + (number.group(2) ?? '');
      var value = double.parse(digits);
      if (number.group(0)!.endsWith('%')) value /= 100;
      out.add(_Token.number(value));
      i += number.group(0)!.length;
      continue;
    }
    final op = _operator.firstMatch(rest)?.group(0);
    if (op == null) return null;
    out.add(_Token.operator(op == '×' ? '*' : op == '÷' ? '/' : op));
    i += 1;
  }
  return out;
}

/// JavaScript's `**`: as `dart:math`'s `pow`, but for the two answers IEEE's `pow` gives 1 where JavaScript gives
/// NaN, a NaN exponent and one to the power of infinity.
double _jsPow(double base, double exponent) {
  if (exponent.isNaN) return double.nan;
  if (exponent.isInfinite && base.abs() == 1) return double.nan;
  return math.pow(base, exponent).toDouble();
}

/// A small precedence-climbing evaluator: nothing but numbers in and a number out.
class _Evaluator {
  _Evaluator(this.list);

  final List<_Token> list;
  int at = 0;

  _Token? get _peek => at < list.length ? list[at] : null;
  _Token? _take() => at < list.length ? list[at++] : null;
  bool _isOp(String value) => _peek?.op == value;

  double? _primary() {
    if (_isOp('-')) {
      _take();
      final value = _power();
      return value == null ? null : -value;
    }
    if (_isOp('+')) {
      _take();
      return _power();
    }
    if (_isOp('(')) {
      _take();
      final value = _sum();
      if (!_isOp(')')) return null;
      _take();
      return value;
    }
    final token = _take();
    return token != null && token.op == null ? token.value : null;
  }

  double? _power() {
    final base = _primary();
    if (base == null) return null;
    if (!_isOp('^')) return base;
    _take();
    final exponent = _power();
    return exponent == null ? null : _jsPow(base, exponent);
  }

  double? _product() {
    var value = _power();
    while (value != null && (_isOp('*') || _isOp('/'))) {
      final op = _take()!.op;
      final right = _power();
      if (right == null) return null;
      value = op == '*' ? value * right : value / right;
    }
    return value;
  }

  double? _sum() {
    var value = _product();
    while (value != null && (_isOp('+') || _isOp('-'))) {
      final op = _take()!.op;
      final right = _product();
      if (right == null) return null;
      value = op == '+' ? value + right : value - right;
    }
    return value;
  }

  double? run() {
    final value = _sum();
    return value != null && at == list.length && value.isFinite ? value : null;
  }
}

/// JavaScript's `Math.round`: to the nearest whole number, a half going up (so -2.5 is -2).
double _jsRound(double value) {
  final floor = value.floorToDouble();
  return value - floor >= 0.5 ? floor + 1 : floor;
}

/// The digits of a number that is nought or more, written out in full: Dart's shortest form with any exponent
/// (`1e+21`, `5e-7`) unrolled, as the whole part and the fraction.
({String whole, String fraction}) _digits(double value) {
  final text = value.toString();
  final e = text.indexOf('e');
  final mantissa = e < 0 ? text : text.substring(0, e);
  final exponent = e < 0 ? 0 : int.parse(text.substring(e + 1));
  final dot = mantissa.indexOf('.');
  var whole = dot < 0 ? mantissa : mantissa.substring(0, dot);
  var fraction = dot < 0 ? '' : mantissa.substring(dot + 1);
  if (exponent > 0) {
    fraction = fraction.padRight(exponent, '0');
    whole = '$whole${fraction.substring(0, exponent)}';
    fraction = fraction.substring(exponent);
  } else if (exponent < 0) {
    whole = whole.padLeft(-exponent + 1, '0');
    fraction = '${whole.substring(whole.length + exponent)}$fraction';
    whole = whole.substring(0, whole.length + exponent);
  }
  whole = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return (whole: whole, fraction: fraction.replaceFirst(RegExp(r'0+$'), ''));
}

/// [digits] with one added to its last figure, carried as far as it goes.
String _bumped(String digits) {
  final figures = digits.codeUnits.toList();
  for (var n = figures.length - 1; n >= 0; n -= 1) {
    if (figures[n] == 0x39) {
      figures[n] = 0x30;
    } else {
      figures[n] += 1;
      return String.fromCharCodes(figures);
    }
  }
  return '1${String.fromCharCodes(figures)}';
}

/// A number that is nought or more as `toLocaleString('en-US', …)` writes it: [grouped] for thousands commas, and
/// between [least] and [most] decimals.
String _enUs(double value, {required bool grouped, required int least, required int most}) {
  var (:whole, :fraction) = _digits(value);
  if (fraction.length > most) {
    final up = fraction.codeUnitAt(most) >= 0x35;
    fraction = fraction.substring(0, most);
    if (up) {
      final all = _bumped('$whole$fraction');
      whole = all.substring(0, all.length - most);
      fraction = all.substring(all.length - most);
    }
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  }
  fraction = fraction.padRight(least, '0');
  if (grouped) whole = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

final RegExp _thousands = RegExp(r'\d,\d{3}');

/// The answer to a sum as it should read, or null when the text isn't one.
String? answer(String expr) {
  final list = _tokens(expr);
  // A sum has at least one operator between numbers: `= 450` alone is a number, not a question.
  if (list == null || !list.any((t) => t.op != null && t.op != '(' && t.op != ')')) return null;
  final value = _Evaluator(list).run();
  if (value == null) return null;
  final sign = _currency.firstMatch(expr)?.group(0) ?? '';
  final grouped = _thousands.hasMatch(expr) || sign.isNotEmpty;
  final rounded = _jsRound(value * 100) / 100;
  final decimals = sign.isNotEmpty && rounded != rounded.truncateToDouble() ? 2 : 0;
  final text = _enUs(rounded.abs(), grouped: grouped, least: decimals, most: sign.isNotEmpty ? 2 : 6);
  return '${rounded < 0 ? '−' : ''}$sign$text';
}

/// The sum on a line, if the line is one: its answer.
({String answer})? sumOnLine(String text) {
  final found = _lead.firstMatch(text);
  if (found == null) return null;
  final result = answer(found.group(2) ?? '');
  return result == null ? null : (answer: result);
}

final RegExp _minus = RegExp(r'^[-−]\s*');

/// The number a value starts with, written as a sum reads one, with a minus before it where there is one: `3` of
/// "3 days", `$1,200` of "$1,200 a month", `-2.5`. Null where the value does not start with a number.
String? leadingNumber(String value) {
  final text = jsTrim(value);
  final minus = _minus.firstMatch(text)?.group(0) ?? '';
  final found = _written.firstMatch(text.substring(minus.length));
  return found != null ? '${minus.isNotEmpty ? '-' : ''}${found.group(0)}' : null;
}

/// A value that is a number and nothing else, as a sum reads one: `3`, `$1,200`, `-2.5`, `50%`; null for anything
/// else.
double? writtenNumber(String value) {
  final text = jsTrim(value);
  final minus = _minus.firstMatch(text)?.group(0) ?? '';
  final rest = text.substring(minus.length);
  final found = _written.firstMatch(rest);
  if (found == null || found.group(0)!.length != rest.length) return null;
  final magnitude = double.parse('${found.group(1)!.replaceAll(',', '')}${found.group(2) ?? ''}') / (found.group(0)!.endsWith('%') ? 100 : 1);
  return minus.isNotEmpty ? -magnitude : magnitude;
}

/// The total of some values, answered as a sum of them would be: each value's leading number ([leadingNumber])
/// added, the currency sign and the thousands commas they were written with coming back on the answer. `3`, `2.5
/// days` and `1` total `6.5`; `$1,200` and `$300` total `$1,500`. A value with no number in it is left out; null
/// where none had one.
String? totalOf(List<String> values) {
  final numbers = [for (final value in values) ?leadingNumber(value)];
  if (numbers.isEmpty) return null;
  // Nought first: a sum answers only where there is something to work out, and the total of one value is that value.
  return answer(['0', ...numbers].join(' + '));
}
