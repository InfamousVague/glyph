/// Blanks the app works out itself, before any model is asked (docs/DESIGN.md §145, 2.2 and 2.3). A port of
/// `src/app/core/fillFacts.ts`.
///
/// Measured on the 4B: asked the days to Christmas it said 12 and 13 (the answer was 88), and it added a note's costs
/// right one time and answered the bare word KNOWN the next. Sums and calendars are code's. So a total or an average
/// of the note's own amounts, a count of its to-dos, days until or since a date, a weekday, a date some days on, a
/// unit conversion, and the time in a city or between two are worked out here, drawn after the blank like a sum with
/// the working a tap away, and never written into the note unless asked.
///
/// Each solver reads the words a blank asks with (core/blanks.dart `askingWords`): its question, its sentence, and
/// the question just before an empty blank. They are drawn narrow: a word anywhere in a sentence is not enough, since
/// "What is the average lifespan of a cat?" is not a sum. A solver that recognises its material and cannot finish
/// says Can't work out in its own words (two currencies, a line with two amounts, Easter, no date to count to), and
/// the person can ask the model anyway. It never hands the blank to the model on its own.
///
/// Pure, and the clock is passed in, so every date here is a test.
///
/// What differs:
/// - The page asks `Intl` for a zone's offset, which is the device's own time-zone database. Dart has none without
///   a package, so the phone is asked for its own once, off to one side as the app starts
///   (lib/core/phone_zones.dart sets [deviceOffsets]): every change of every zone the solver's cities are in, and
///   of the phone's own, from last year for forty years on. Where the phone has not answered (an iPhone, a Mac, a
///   test, a moment outside those years) [offsetMinutes] reads a table of the same zones
///   (ai/support/time_zone_table.dart, written by tool/ai_fixtures.mjs from the page's own `offsetMinutes`),
///   which answers exactly as the page does from the start of 2000 to the start of 2041. A zone neither has is 0,
///   where the page throws. The clock carries the function ([FactClock.offsetOf]), so a test passes its own.
/// - The device's own zone: the page asks `Intl` for its name (`clock.zone ?? Intl…timeZone`). Here it is what
///   the phone said ([deviceZone]); a clock with no [FactClock.zone] on a device that has not said, or one in a
///   zone nothing knows, takes the device's offset from the `DateTime` itself and is called "here".
/// - Dates and weekdays are written in English, in the phone's own order once it has said which ("Monday, September
///   28, 2026" and "October 25" on an American phone, "Monday 28 September 2026" and "25 October" on a British one),
///   and the day first until then, where the page writes the device's language (ai/support/stamp.dart says why).
/// - `Worked` is a sealed class with the page's two shapes under it, and [Worked.toJson] is the page's own object.
library;

import '../ai/support/stamp.dart';
import '../ai/support/time_zone_table.dart';
import '../ai/support/time_zones.dart';
import 'blanks.dart';
import 'front_matter.dart';
import 'item_syntax.dart';
import 'sums.dart' as sums;
import 'text.dart';

/// The icon an answer is drawn with (`FactIcon`).
enum FactIcon { calculator, calendar, globe }

/// Which solver answered (`Solver`).
enum Solver { total, average, count, days, weekday, dateOn, units, time }

/// How often an answer changes, so the panel says so and the editor redraws it: the web's `'day' | 'minute'`.
enum Changes { day, minute }

/// What the app made of a blank: an answer, or why it cannot give one (`Worked`).
sealed class Worked {
  const Worked({required this.solver, required this.icon});

  final Solver solver;
  final FactIcon icon;

  /// The web's `kind`: `answer` or `cannot`.
  String get kind;

  /// The object the page holds, key for key.
  Map<String, Object?> toJson();
}

/// An answer the app worked out (`WorkedAnswer`).
class WorkedAnswer extends Worked {
  const WorkedAnswer({required super.solver, required super.icon, required this.answer, required this.working, required this.changes});

  /// What is drawn after the blank: `$325`, `88 days`, `Saturday`.
  final String answer;

  /// How it was reached, for the panel: `$200 + $45 + $80 = $325.`
  final String working;

  /// Whether it changes with the day or the minute; null for one that stays.
  final Changes? changes;

  @override
  String get kind => 'answer';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'solver': solver.name, 'icon': icon.name, 'answer': answer, 'working': working, 'changes': changes?.name};

  @override
  bool operator ==(Object other) => other is WorkedAnswer && other.solver == solver && other.icon == icon && other.answer == answer && other.working == working && other.changes == changes;

  @override
  int get hashCode => Object.hash(solver, icon, answer, working, changes);

  @override
  String toString() => 'WorkedAnswer(${solver.name}, $answer, $working, ${changes?.name})';
}

/// What the app recognised and could not finish (`CannotWork`).
class CannotWork extends Worked {
  const CannotWork({required super.solver, required super.icon, required this.words});

  /// The panel's sentence, in the app's words.
  final String words;

  @override
  String get kind => 'cannot';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'solver': solver.name, 'icon': icon.name, 'words': words};

  @override
  bool operator ==(Object other) => other is CannotWork && other.solver == solver && other.icon == icon && other.words == words;

  @override
  int get hashCode => Object.hash(solver, icon, words);

  @override
  String toString() => 'CannotWork(${solver.name}, $words)';
}

/// A zone's offset from UTC at a moment, in minutes: the shape of [offsetMinutes], for a clock that brings its own.
typedef ZoneOffset = int Function(String zone, DateTime at);

/// The moment the answers are for, and the device's own zone (for "Tokyo is 8 hours ahead of London") (`FactClock`).
class FactClock {
  const FactClock({required this.now, this.zone, this.offsetOf = offsetMinutes});

  /// The moment. Its day is read on the device's own calendar, whichever way the `DateTime` was made.
  final DateTime now;

  /// The device's IANA zone, `Europe/London`; null to take the device's offset from [now] itself.
  final String? zone;

  /// What a zone's offset is asked of: [offsetMinutes] and its table unless the caller has better.
  final ZoneOffset offsetOf;
}

const Map<Solver, FactIcon> _icons = {
  Solver.total: FactIcon.calculator,
  Solver.average: FactIcon.calculator,
  Solver.count: FactIcon.calculator,
  Solver.units: FactIcon.calculator,
  Solver.days: FactIcon.calendar,
  Solver.weekday: FactIcon.calendar,
  Solver.dateOn: FactIcon.calendar,
  Solver.time: FactIcon.globe,
};

WorkedAnswer _answered(Solver solver, String answer, String working, [Changes? changes]) => WorkedAnswer(solver: solver, icon: _icons[solver]!, answer: answer, working: working, changes: changes);
CannotWork _cannot(Solver solver, String words) => CannotWork(solver: solver, icon: _icons[solver]!, words: words);

/// What the app works out for a blank, why it cannot, or null where it is not the app's to answer.
Worked? workOut(Blank blank, String text, FactClock clock) {
  final asking = askingWords(blank, text);
  return _sum(blank, text, asking) ?? _count(blank, text, asking) ?? _dateOn(asking, clock) ?? _days(asking, clock) ?? _weekday(asking, clock) ?? _units(asking) ?? _time(asking, clock);
}

// ---- JavaScript's ways with numbers and text ------------------------------------------------------------------------

/// Where the line holding [at] starts: JavaScript's `text.lastIndexOf('\n', at - 1) + 1`, which Dart refuses at 0.
int _lineStart(String text, int at) => at <= 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;

/// A number as JavaScript writes one in a template: `200`, `1.5`, never `200.0`.
String _js(double value) => value.isFinite && value == value.truncateToDouble() && value.abs() < 1e21 ? value.toStringAsFixed(0) : value.toString();

/// JavaScript's `Math.round`: a half goes up, and a small negative is minus nought.
double _jsRound(double value) {
  final rounded = (value + 0.5).floorToDouble();
  return rounded == 0 && value < 0 ? -0.0 : rounded;
}

/// The digits of a number that is nought or more, written out in full, as the whole part and the fraction.
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

final RegExp _grouping = RegExp(r'\B(?=(\d{3})+$)');

/// A number as `toLocaleString('en-US', {maximumFractionDigits: most})` writes it: thousands commas, at most [most]
/// decimals with a half going up, and a minus for anything below nought, minus nought included.
String _enUs(double value, [int most = 3]) {
  if (value.isNegative) return '-${_enUs(-value, most)}';
  var (:whole, :fraction) = _digits(value);
  if (fraction.length > most) {
    final up = fraction.codeUnitAt(most) >= 0x35;
    fraction = fraction.substring(0, most);
    if (up) {
      final all = _bumped('$whole$fraction');
      whole = all.substring(0, all.length - most);
      fraction = all.substring(all.length - most);
      if (whole.isEmpty) whole = '0';
    }
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  }
  whole = whole.replaceAllMapped(_grouping, (_) => ',');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

// ---- totals and averages --------------------------------------------------------------------------------------------

final RegExp _closingStops = RegExp(r'[?.!]+$');
final RegExp _totalQuestion = RegExp(r'^(?:the |a )?(?:total|sum|altogether|in all|grand total)$', caseSensitive: false);
final RegExp _totalWords = RegExp(r'\b(?:total|sum|altogether|in all|adds up to|comes to)\b', caseSensitive: false);
final RegExp _averageWords = RegExp(r'\b(?:average|mean)\b', caseSensitive: false);

/// Whether the blank asks for a total or an average, read only where the rule says (2.2): never a word elsewhere.
Solver? _sumAsked(Asking asking) {
  final question = jsTrim(asking.question.replaceFirst(_closingStops, ''));
  if (_averageWords.hasMatch(question) || _averageWords.hasMatch(asking.label)) return Solver.average;
  if (_totalQuestion.hasMatch(question) || _totalWords.hasMatch(asking.label)) return Solver.total;
  if (asking.prior.isNotEmpty && _averageWords.hasMatch(asking.prior)) return Solver.average;
  if (asking.prior.isNotEmpty && _totalWords.hasMatch(asking.prior)) return Solver.total;
  return null;
}

/// An amount on a line: its value, what kind it is (`$` or `EUR` for money, a unit's symbol, or '' for a plain
/// number), and how it was written.
typedef _Amount = ({double value, String kind, bool money, String written});

const String _month = r'(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

/// What is not an amount, taken out of a line before its amounts are read.
final List<RegExp> _notAmounts = [
  RegExp(r'\[[^\]\n]*\]\([^)\n]*\)'), // a link, words and all
  RegExp(r'`[^`\n]*`'), // a code span
  RegExp(r'\{\?[^{}\n]*\}'), // a blank
  RegExp(r'\b\d{4}-\d{2}-\d{2}\b'), // an ISO date
  RegExp('\\b\\d{1,2}(?:st|nd|rd|th)?\\s+$_month\\b\\.?', caseSensitive: false), // 3 Oct
  RegExp('\\b$_month\\.?\\s+\\d{1,2}(?:st|nd|rd|th)?\\b', caseSensitive: false), // Oct 3
  RegExp(r'\b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b'), // 3/10
  RegExp(r'\b\d{1,2}[:.]\d{2}\s*(?:am|pm)?\b', caseSensitive: false), // 14:05, 9.30pm
  RegExp(r'\b\d{1,2}\s*(?:am|pm)\b', caseSensitive: false), // 9am
  RegExp(r'\b\d+(?:st|nd|rd|th)\b', caseSensitive: false), // 3rd
  RegExp(r'\d+(?:\.\d+)?\s*%'), // 20%
  RegExp(r'\b\d+\.\d+\.\d+(?:\.\d+)*\b'), // a version
  RegExp(r'\+\d[\d\s-]{5,}'), // a phone number
];

const String _currencyCodes = 'USD|EUR|GBP|JPY|CHF|CAD|AUD|NZD|CNY|INR|SEK|NOK|DKK|PLN|CZK|HKD|SGD|KRW|MXN|BRL|ZAR';
const List<String> _unitSymbols = ['kg', 'g', 'lb', 'oz', 'km', 'm', 'cm', 'mm', 'mi', 'ml', 'l'];

final RegExp _amount = RegExp('([\$€£¥₹])\\s?(\\d{1,3}(?:,\\d{3})+|\\d+)(\\.\\d+)?|(\\d{1,3}(?:,\\d{3})+|\\d+)(\\.\\d+)?\\s?($_currencyCodes|${_unitSymbols.join('|')})?\\b');
final RegExp _isCurrencyCode = RegExp('^(?:$_currencyCodes)\$');
final RegExp _quoteMarks = RegExp(r'^\s*(?:>\s*)+');
final RegExp _aYear = RegExp(r'^[12]\d{3}$');
final RegExp _letter = RegExp(r'[\p{L}]', unicode: true);
final RegExp _space = RegExp(r'\s');
final RegExp _spaces = RegExp(r'\s+');

/// The amounts a line holds, as the solver reads them.
List<_Amount> _amountsOf(String line) {
  // The list's lead goes first: a numbered item's own number is not an amount.
  final lead = listLead(line);
  var rest = plainFills(lead != null ? line.substring(lead.wordsAt) : line).replaceFirst(_quoteMarks, '');
  for (final pattern in _notAmounts) {
    rest = rest.replaceAll(pattern, ' ');
  }
  final found = <_Amount>[];
  for (final match in _amount.allMatches(rest)) {
    final sign = match.group(1);
    if (sign != null) {
      found.add((value: double.parse('${match.group(2)!.replaceAll(',', '')}${match.group(3) ?? ''}'), kind: sign, money: true, written: match.group(0)!.replaceAll(_space, '')));
      continue;
    }
    final digits = match.group(4)!;
    final decimal = match.group(5) ?? '';
    final suffix = match.group(6);
    // A year: four figures from 1000 to 2999, with no sign, unit or comma.
    if (suffix == null && decimal.isEmpty && _aYear.hasMatch(digits)) continue;
    // The number a numbered list starts its line with has gone with the lead; a number glued to a letter is a name.
    if (match.start > 0 && _letter.hasMatch(rest[match.start - 1])) continue;
    final value = double.parse('${digits.replaceAll(',', '')}$decimal');
    if (suffix != null && _isCurrencyCode.hasMatch(suffix)) {
      found.add((value: value, kind: suffix, money: true, written: '$digits$decimal $suffix'));
    } else if (suffix != null) {
      found.add((value: value, kind: suffix, money: false, written: '$digits$decimal $suffix'));
    } else {
      found.add((value: value, kind: '', money: false, written: '$digits$decimal'));
    }
  }
  return found;
}

final RegExp _oneQuoteMark = RegExp(r'^\s*>\s*');

/// A line's words, as the working names one: the list's lead off, and filled answers as words.
String _lineSaid(String line) {
  final lead = listLead(line);
  return jsTrim(plainFills(lead != null ? line.substring(lead.wordsAt) : line).replaceFirst(_oneQuoteMark, '').replaceAll(_spaces, ' '));
}

final RegExp _headingLine = RegExp(r'^\s*#{1,6}\s');

/// The block directly above the blank's line: blank lines just above passed over, then up to a heading, a blank line
/// or the start.
List<String> _blockAbove(String text, Blank blank) {
  final lines = text.substring(0, _lineStart(text, blank.from)).split('\n')..removeLast();
  final front = frontMatterEnd(text.split('\n'));
  var at = lines.length - 1;
  while (at >= front && at >= 0 && jsTrim(lines[at]).isEmpty) {
    at -= 1;
  }
  final block = <String>[];
  for (; at >= front && at >= 0; at -= 1) {
    final line = lines[at];
    if (jsTrim(line).isEmpty || _headingLine.hasMatch(line)) break;
    block.insert(0, line);
  }
  return block;
}

final RegExp _outerPipes = RegExp(r'^\||\|$');
final RegExp _pipe = RegExp(r'(?<!\\)\|');
final RegExp _tableLine = RegExp(r'^\s*\|');
final RegExp _totalRow = RegExp(r'^(?:\*\*)?(?:total|sum|average|mean)(?:\*\*)?:?$', caseSensitive: false);

/// The cells of a table line, outer pipes off.
List<String> _cells(String line) => [for (final cell in jsTrim(line).replaceAll(_outerPipes, '').split(_pipe)) jsTrim(cell)];

/// For a cell whose row starts `Total` or `Sum`: the column above it, as lines of one cell each.
List<String>? _columnAbove(String text, Blank blank) {
  final lineStart = _lineStart(text, blank.from);
  final lineEnd = text.indexOf('\n', blank.to);
  final line = text.substring(lineStart, lineEnd == -1 ? text.length : lineEnd);
  if (!_tableLine.hasMatch(line)) return null;
  final row = _cells(line);
  if (!_totalRow.hasMatch(row.isEmpty ? '' : row[0])) return null;
  // The blank's column: the unescaped pipes before it, less the one that opens the row.
  final pipes = _pipe.allMatches(line.substring(0, blank.from - lineStart)).length;
  final column = (pipes == 0 ? 1 : pipes) - 1;
  final above = text.substring(0, lineStart).split('\n')..removeLast();
  final rows = <String>[];
  for (var at = above.length - 1; at >= 0 && _tableLine.hasMatch(above[at]); at -= 1) {
    rows.insert(0, above[at]);
  }
  // The header and the delimiter row are not amounts.
  return [
    for (final r in rows.skip(2))
      if (jsTrim(_cellAt(_cells(r), column)).isNotEmpty) _cellAt(_cells(r), column),
  ];
}

String _cellAt(List<String> cells, int column) => column >= 0 && column < cells.length ? cells[column] : '';

final RegExp _moneySign = RegExp(r'^[$€£¥₹]$');

/// A total's figure as it should read: the sum's own evaluator for signs and plain numbers, a code or a unit after.
String _figure(List<double> values, String kind, bool average) {
  final total = values.fold<double>(0, (a, b) => a + b);
  final value = average ? total / values.length : total;
  if (kind == '' || _moneySign.hasMatch(kind)) {
    final expression = values.map((v) => '$kind${_js(v)}').join(' + ');
    final worked = sums.answer(average ? '($expression) / ${values.length}' : expression);
    if (worked != null && worked.isNotEmpty) return worked;
  }
  final rounded = _jsRound(value * 100) / 100;
  return jsTrim('${_enUs(rounded, 2)} $kind');
}

final RegExp _stopOrColon = RegExp(r'[.:]$');

Worked? _sum(Blank blank, String text, Asking asking) {
  final asked = _sumAsked(asking);
  if (asked == null) return null;
  final column = _columnAbove(text, blank);
  final lines = column ?? _blockAbove(text, blank);
  final amounts = <_Amount>[];
  final passed = <String>[];
  for (final line in lines) {
    final here = _amountsOf(line);
    if (here.length > 1) return _cannot(asked, 'The app adds these up itself, and one line has two amounts: ${_lineSaid(line)}. Keep one to a line.');
    if (here.length == 1) {
      amounts.add(here[0]);
    } else if (_lineSaid(line).isNotEmpty) {
      passed.add(_lineSaid(line));
    }
  }
  if (amounts.length < 2) return null;
  final first = amounts[0];
  final others = amounts.where((a) => a.kind != first.kind);
  if (others.isNotEmpty) {
    final other = others.first;
    final money = first.money && other.money;
    return _cannot(
      asked,
      money
          ? 'The app adds these up itself, and ${first.written} and ${other.written} are different money.'
          : 'The app adds these up itself, and ${first.written} and ${other.written} are not the same kind of number.',
    );
  }
  final result = _figure([for (final a in amounts) a.value], first.kind, asked == Solver.average);
  final joined = amounts.map((a) => a.written).join(' + ');
  final working = asked == Solver.average ? '($joined) ÷ ${amounts.length} = $result.' : '$joined = $result.';
  final skipped = passed.map((line) => ' ${capitalise(line.replaceFirst(_stopOrColon, ''))} has no amount.').join();
  return _answered(asked, result, '$working$skipped');
}

// ---- counts ---------------------------------------------------------------------------------------------------------

final RegExp _countNoun = RegExp(r'\b(to-?dos?|tasks?|items?|things?)\b', caseSensitive: false);
final RegExp _countWhich = RegExp(r'\b(left|done|ticked|open|to go|still|above|on this list|in this note)\b', caseSensitive: false);
final RegExp _todoNoun = RegExp(r'^(?:to-?dos?|tasks?)$');
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

Worked? _count(Blank blank, String text, Asking asking) {
  final noun = _countNoun.firstMatch(asking.text)?.group(1)?.toLowerCase();
  final which = _countWhich.firstMatch(asking.text)?.group(1)?.toLowerCase();
  if (noun == null || noun.isEmpty || which == null || which.isEmpty) return null;
  final left = const ['left', 'open', 'to go', 'still'].contains(which);
  final done = which == 'done' || which == 'ticked';
  if (_todoNoun.hasMatch(noun)) {
    final lines = text.split('\n');
    final front = frontMatterEnd(lines);
    var fenced = false;
    var open = 0;
    var ticked = 0;
    for (var index = front; index < lines.length; index += 1) {
      final line = lines[index];
      if (_fence.hasMatch(line)) fenced = !fenced;
      if (fenced) continue;
      final box = taskBox(line);
      if (box != null && box.done) {
        ticked += 1;
      } else if (box != null) {
        open += 1;
      }
    }
    final all = open + ticked;
    final todos = all == 1 ? 'to-do' : 'to-dos';
    if (left) return _answered(Solver.count, '$open left', '$open of $all $todos in this note ${open == 1 ? 'is' : 'are'} not ticked.');
    if (done) return _answered(Solver.count, '$ticked done', '$ticked of $all $todos in this note ${ticked == 1 ? 'is' : 'are'} ticked.');
    return _answered(Solver.count, '$all $todos', 'This note has $all $todos.');
  }
  final items = _blockAbove(text, blank).where((line) {
    final lead = listLead(line);
    return lead != null && jsTrim(line.substring(lead.wordsAt)).isNotEmpty;
  }).toList();
  if (items.isEmpty) return null;
  final word = noun.startsWith('thing') ? 'thing' : 'item';
  return _answered(Solver.count, '${items.length} ${items.length == 1 ? word : '${word}s'}', 'The list above has ${items.length} ${items.length == 1 ? 'item' : 'items'}.');
}

// ---- dates ----------------------------------------------------------------------------------------------------------

/// A day on the calendar: its year, its month from 0 as JavaScript counts them, and its day. Compared by identity
/// where the page compares objects, so it has no equality of its own.
class _Day {
  const _Day(this.y, this.m, this.d);
  final int y;
  final int m;
  final int d;
}

const Map<String, int> _months = {'jan': 0, 'feb': 1, 'mar': 2, 'apr': 3, 'may': 4, 'jun': 5, 'jul': 6, 'aug': 7, 'sep': 8, 'oct': 9, 'nov': 10, 'dec': 11};
int _monthOf(String word) => _months[(word.length > 3 ? word.substring(0, 3) : word).toLowerCase()]!;
const List<String> _weekdays = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

/// Fixed days, by what people call them.
final List<({RegExp pattern, int m, int d})> _fixed = [
  (pattern: RegExp(r'\bchristmas eve\b', caseSensitive: false), m: 11, d: 24),
  (pattern: RegExp(r'\bchristmas(?: day)?\b|\bxmas\b', caseSensitive: false), m: 11, d: 25),
  (pattern: RegExp(r'\bboxing day\b', caseSensitive: false), m: 11, d: 26),
  (pattern: RegExp(r"\bnew year'?s eve\b", caseSensitive: false), m: 11, d: 31),
  (pattern: RegExp(r"\bnew year'?s(?: day)?\b", caseSensitive: false), m: 0, d: 1),
  (pattern: RegExp(r"\bvalentine'?s(?: day)?\b", caseSensitive: false), m: 1, d: 14),
  (pattern: RegExp(r'\bhalloween\b', caseSensitive: false), m: 9, d: 31),
  (pattern: RegExp(r'\bbonfire night\b|\bguy fawkes\b', caseSensitive: false), m: 10, d: 5),
];

/// Days that move from year to year, which the app does not reckon.
final RegExp _moving = RegExp(r"\b(easter|thanksgiving|mother'?s day|father'?s day|diwali|eid|hanukkah|chanukah|lunar new year|chinese new year|ramadan|passover|good friday)\b", caseSensitive: false);

/// What a blank's words name: a day, with whether its year was written, or a refusal.
class _Found {
  const _Found.day(_Day this.day, {required this.year}) : refuse = null;
  const _Found.refuse(String this.refuse) : day = null, year = false;
  final _Day? day;
  final bool year;
  final String? refuse;
}

const int _dayMs = 86400000;

/// A year as a JavaScript `Date` takes one: 0 to 99 are 1900 to 1999.
int _jsYear(int y) => y >= 0 && y <= 99 ? 1900 + y : y;

int _dayNumber(_Day day) => DateTime.utc(_jsYear(day.y), day.m + 1, day.d).millisecondsSinceEpoch ~/ _dayMs;
_Day _fromNumber(int n) {
  final date = DateTime.fromMillisecondsSinceEpoch(n * _dayMs, isUtc: true);
  return _Day(date.year, date.month - 1, date.day);
}

DateTime _localDate(_Day day) => DateTime(_jsYear(day.y), day.m + 1, day.d, 12);
_Day _todayOf(DateTime now) {
  final local = now.toLocal();
  return _Day(local.year, local.month - 1, local.day);
}

final RegExp _wordStart = RegExp(r'\b\w');
final RegExp _possessiveS = RegExp(r"'S\b");
final RegExp _slashed = RegExp(r'\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b');
final RegExp _iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
final RegExp _dayMonth = RegExp('\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?($_month)\\b\\.?(?:,?\\s+(\\d{4}))?', caseSensitive: false);
final RegExp _monthDay = RegExp('\\b($_month)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:,?\\s+(\\d{4}))?', caseSensitive: false);
final RegExp _today = RegExp(r'\btoday\b', caseSensitive: false);
final RegExp _tomorrow = RegExp(r'\btomorrow\b', caseSensitive: false);
final RegExp _yesterday = RegExp(r'\byesterday\b', caseSensitive: false);
final RegExp _weekdayNamed = RegExp('\\b(this|next|last)?\\s*(${_weekdays.join('|')})\\b', caseSensitive: false);

/// The date a blank's words name, the year left open where none is written; a refusal for a date the app cannot
/// place.
_Found? _findDate(String words, _Day today) {
  final moving = _moving.firstMatch(words);
  if (moving != null) {
    final name = moving.group(1)!.replaceAllMapped(_wordStart, (c) => c.group(0)!.toUpperCase()).replaceFirst(_possessiveS, "'s");
    return _Found.refuse('$name moves each year, and the app does not know when it falls.');
  }
  final slashed = _slashed.firstMatch(words);
  if (slashed != null) {
    final a = int.parse(slashed.group(1)!);
    final b = int.parse(slashed.group(2)!);
    final year = slashed.group(3);
    if (a <= 12 && b <= 12 && a != b) return _Found.refuse('${slashed.group(0)} is a different day in London and in New York. Write it as $b ${monthName(a)} or $a ${monthName(b)}.');
    if (b <= 12) return _Found.day(_Day(year != null ? _fullYear(year) : today.y, b - 1, a), year: year != null);
    return _Found.refuse('${slashed.group(0)} could be read two ways. Write the month as a word.');
  }
  final iso = _iso.firstMatch(words);
  if (iso != null) return _Found.day(_Day(int.parse(iso.group(1)!), int.parse(iso.group(2)!) - 1, int.parse(iso.group(3)!)), year: true);
  final dm = _dayMonth.firstMatch(words);
  if (dm != null) {
    final year = dm.group(3);
    return _Found.day(_Day(year != null ? int.parse(year) : today.y, _monthOf(dm.group(2)!), int.parse(dm.group(1)!)), year: year != null);
  }
  final md = _monthDay.firstMatch(words);
  if (md != null) {
    final year = md.group(3);
    return _Found.day(_Day(year != null ? int.parse(year) : today.y, _monthOf(md.group(1)!), int.parse(md.group(2)!)), year: year != null);
  }
  if (_today.hasMatch(words)) return _Found.day(today, year: true);
  if (_tomorrow.hasMatch(words)) return _Found.day(_fromNumber(_dayNumber(today) + 1), year: true);
  if (_yesterday.hasMatch(words)) return _Found.day(_fromNumber(_dayNumber(today) - 1), year: true);
  for (final fixed in _fixed) {
    if (fixed.pattern.hasMatch(words)) return _Found.day(_Day(today.y, fixed.m, fixed.d), year: false);
  }
  final weekday = _weekdayNamed.firstMatch(words);
  if (weekday != null) {
    final want = _weekdays.indexOf(weekday.group(2)!.toLowerCase());
    final now = DateTime.utc(_jsYear(today.y), today.m + 1, today.d).weekday % 7;
    final which = (weekday.group(1) ?? '').toLowerCase();
    var ahead = (want - now + 7) % 7;
    if (which == 'last') {
      ahead = ahead == 0 ? -7 : ahead - 7;
    } else if (which == 'next' && ahead == 0) {
      ahead = 7;
    }
    return _Found.day(_fromNumber(_dayNumber(today) + ahead), year: true);
  }
  return null;
}

int _fullYear(String text) => text.length == 2 ? 2000 + int.parse(text) : int.parse(text);

/// A date with no year: the next time it comes round, or the last, today counting either way.
_Day _placed(_Found found, _Day today, bool back) {
  final named = found.day!;
  if (found.year) return named;
  final t = _dayNumber(today);
  var day = _Day(today.y, named.m, named.d);
  if (!back && _dayNumber(day) < t) day = _Day(today.y + 1, day.m, day.d);
  if (back && _dayNumber(day) > t) day = _Day(today.y - 1, day.m, day.d);
  return day;
}

String _plural(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';

/// Days, weeks and days, or months and days between two dates, as the question asked for them.
String _span(_Day from, _Day to, String unit) {
  final days = (_dayNumber(to) - _dayNumber(from)).abs();
  if (unit == 'week') {
    final weeks = days ~/ 7;
    final rest = days % 7;
    return rest != 0 ? '${_plural(weeks, 'week')} and ${_plural(rest, 'day')}' : _plural(weeks, 'week');
  }
  if (unit == 'month') {
    final forward = _dayNumber(from) <= _dayNumber(to);
    final start = forward ? from : to;
    final end = forward ? to : from;
    var months = (end.y - start.y) * 12 + (end.m - start.m);
    if (end.d < start.d) months -= 1;
    final landed = _dayNumber(_addMonths(start, months));
    final rest = _dayNumber(end) - landed;
    return rest != 0 ? '${_plural(months, 'month')} and ${_plural(rest, 'day')}' : _plural(months, 'month');
  }
  return _plural(days, 'day');
}

_Day _addMonths(_Day day, int months) {
  final target = DateTime.utc(_jsYear(day.y), day.m + months + 1, 1);
  final last = DateTime.utc(target.year, target.month + 1, 0).day;
  return _Day(target.year, target.month - 1, day.d < last ? day.d : last);
}

/// A count of days, weeks or months asked for: the plural, as "Days until" and "how many weeks" ask. "What day" asks
/// which.
final RegExp _unitWord = RegExp(r'\b(days|weeks|months)\b', caseSensitive: false);
final RegExp _forward = RegExp(r'\b(until|till|til|to go|to|before|left)\b', caseSensitive: false);
final RegExp _backward = RegExp(r'\b(since|ago)\b', caseSensitive: false);

/// A count of days stated rather than asked: "3 days until my exam" says how many, so it is not a question for the
/// app.
final RegExp _stated = RegExp(r'\b(?:\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|few|several)\s+(?:days?|weeks?|months?)\b', caseSensitive: false);
final RegExp _howLong = RegExp(r'\bhow long (?:until|till|since|ago)\b|\bhow long ago\b', caseSensitive: false);

Worked? _days(Asking asking, FactClock clock) {
  final words = asking.text;
  if (_stated.hasMatch(words)) return null;
  final unitWord = _unitWord.firstMatch(words)?.group(1)?.toLowerCase();
  final howLong = _howLong.hasMatch(words);
  final back = _backward.hasMatch(words);
  final forward = _forward.hasMatch(words);
  if (!((unitWord != null && (back || forward)) || howLong)) return null;
  final today = _todayOf(clock.now);
  final found = _findDate(words, today);
  if (found == null) return unitWord != null ? _cannot(Solver.days, 'The app counts days itself, and there is no date here to count to.') : null;
  if (found.refuse != null) return _cannot(Solver.days, found.refuse!);
  final target = _placed(found, today, back);
  final unit = unitWord != null && unitWord.startsWith('week') ? 'week' : (unitWord != null && unitWord.startsWith('month') ? 'month' : 'day');
  final past = _dayNumber(target) < _dayNumber(today);
  final working = past
      ? 'From ${longDate(_localDate(target))} to today, ${longDate(_localDate(today))}. It changes each day.'
      : 'From today, ${longDate(_localDate(today))}, to ${longDate(_localDate(target))}. It changes each day.';
  return _answered(Solver.days, _span(today, target, unit), working, Changes.day);
}

final RegExp _weekdayAsked = RegExp(r'\b(?:weekday|day of the week|what day)\b', caseSensitive: false);
final RegExp _isALabel = RegExp(r'\b(?:is|was|falls on) an?\s*$', caseSensitive: false);
final RegExp _isAWhole = RegExp(r'^(?:is|was) an?$', caseSensitive: false);
final RegExp _was = RegExp(r'\bwas\b', caseSensitive: false);

Worked? _weekday(Asking asking, FactClock clock) {
  final words = asking.text;
  final asked = _weekdayAsked.hasMatch(words) || _isALabel.hasMatch(asking.label) || _isAWhole.hasMatch(asking.label);
  if (!asked) return null;
  final today = _todayOf(clock.now);
  final found = _findDate(words, today);
  if (found == null) return null;
  if (found.refuse != null) return _cannot(Solver.weekday, found.refuse!);
  final back = _was.hasMatch(asking.label) && !found.year;
  final day = _placed(found, today, back);
  return _answered(Solver.weekday, weekdayName(_localDate(day)), '${longDate(_localDate(day))}.');
}

const Map<String, int> _numberWords = {'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12};

final RegExp _dateFrom = RegExp(r'\b(\d{1,4}|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(days?|weeks?|months?|years?)\s+(from|after|before)\s+(.+)$', caseSensitive: false);
final RegExp _dateIn = RegExp(
  r"\bin\s+(\d{1,4}|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(days?|weeks?|months?|years?)(?:'?\s*time)?(?:\s+(?:is|will be|it will be|it is))?\s*:?\s*$",
  caseSensitive: false,
);
final RegExp _allDigits = RegExp(r'^\d+$');
final RegExp _before = RegExp('before', caseSensitive: false);
final RegExp _todayOrNow = RegExp(r'^(?:today|now)\b', caseSensitive: false);
final RegExp _closingS = RegExp(r's$');

Worked? _dateOn(Asking asking, FactClock clock) {
  // Only what is asked: the question, the words before the blank, or the question before an empty one. "I fly out in
  // two days, so pack {?what}" asks what to pack.
  final words = [asking.question, asking.before, asking.prior].where((each) => each.isNotEmpty).join(' ');
  final on = _dateFrom.firstMatch(words);
  // "In 3 weeks:" asks for a date only straight before the blank: "I fly out in two days, so pack {?what}" does not.
  final inside = _dateIn.firstMatch(jsTrim('${asking.question} ${asking.before}'));
  final match = on ?? inside;
  if (match == null) return null;
  final n = _allDigits.hasMatch(match.group(1)!) ? int.parse(match.group(1)!) : _numberWords[match.group(1)!.toLowerCase()]!;
  final unit = match.group(2)!.toLowerCase().replaceFirst(_closingS, '');
  final today = _todayOf(clock.now);
  var base = today;
  var baseWords = 'today, ${longDate(_localDate(today))}';
  final sign = on != null && _before.hasMatch(on.group(3)!) ? -1 : 1;
  if (on != null && !_todayOrNow.hasMatch(jsTrim(on.group(4)!))) {
    final found = _findDate(on.group(4)!, today);
    if (found == null) return null;
    if (found.refuse != null) return _cannot(Solver.dateOn, found.refuse!);
    base = _placed(found, today, false);
    baseWords = longDate(_localDate(base));
  }
  final day = switch (unit) {
    'day' => _fromNumber(_dayNumber(base) + sign * n),
    'week' => _fromNumber(_dayNumber(base) + sign * n * 7),
    'month' => _addMonths(base, sign * n),
    _ => _addMonths(base, sign * n * 12),
  };
  final dayWords = '$n ${n == 1 ? unit : '${unit}s'}';
  final fromToday = identical(base, today);
  return _answered(Solver.dateOn, longDate(_localDate(day)), '${capitalise(dayWords)} ${sign < 0 ? 'before' : 'from'} $baseWords.${fromToday ? ' It changes each day.' : ''}', fromToday ? Changes.day : null);
}

// ---- units ----------------------------------------------------------------------------------------------------------

/// A unit: its symbol, its kind, how many of the kind's base (a metre, a gram, a millilitre, a km/h) one of it is,
/// and the names it goes by.
typedef _Unit = ({String symbol, String kind, double factor, List<String> names});

const List<_Unit> _unitTable = [
  (symbol: '°C', kind: 'temperature', factor: 1, names: ['°c', 'celsius', 'centigrade', 'degrees celsius']),
  (symbol: '°F', kind: 'temperature', factor: 1, names: ['°f', 'fahrenheit', 'degrees fahrenheit']),
  (symbol: 'mm', kind: 'length', factor: 0.001, names: ['mm', 'millimetre', 'millimetres', 'millimeter', 'millimeters']),
  (symbol: 'cm', kind: 'length', factor: 0.01, names: ['cm', 'centimetre', 'centimetres', 'centimeter', 'centimeters']),
  (symbol: 'm', kind: 'length', factor: 1, names: ['m', 'metre', 'metres', 'meter', 'meters']),
  (symbol: 'km', kind: 'length', factor: 1000, names: ['km', 'kms', 'kilometre', 'kilometres', 'kilometer', 'kilometers']),
  (symbol: 'in', kind: 'length', factor: 0.0254, names: ['in', 'inch', 'inches']),
  (symbol: 'ft', kind: 'length', factor: 0.3048, names: ['ft', 'foot', 'feet']),
  (symbol: 'yd', kind: 'length', factor: 0.9144, names: ['yd', 'yard', 'yards']),
  (symbol: 'mi', kind: 'length', factor: 1609.344, names: ['mi', 'mile', 'miles']),
  (symbol: 'g', kind: 'mass', factor: 1, names: ['g', 'gram', 'grams', 'gramme', 'grammes']),
  (symbol: 'kg', kind: 'mass', factor: 1000, names: ['kg', 'kilo', 'kilos', 'kilogram', 'kilograms']),
  (symbol: 'oz', kind: 'mass', factor: 28.349523125, names: ['oz', 'ounce', 'ounces']),
  (symbol: 'lb', kind: 'mass', factor: 453.59237, names: ['lb', 'lbs', 'pound', 'pounds']),
  (symbol: 'st', kind: 'mass', factor: 6350.29318, names: ['st', 'stone', 'stones']),
  (symbol: 'ml', kind: 'volume', factor: 1, names: ['ml', 'millilitre', 'millilitres', 'milliliter', 'milliliters']),
  (symbol: 'l', kind: 'volume', factor: 1000, names: ['l', 'litre', 'litres', 'liter', 'liters']),
  (symbol: 'tsp', kind: 'volume', factor: 5, names: ['tsp', 'teaspoon', 'teaspoons']),
  (symbol: 'tbsp', kind: 'volume', factor: 15, names: ['tbsp', 'tablespoon', 'tablespoons']),
  (symbol: 'km/h', kind: 'speed', factor: 1, names: ['km/h', 'kph', 'kmh', 'kilometres per hour', 'kilometers per hour']),
  (symbol: 'mph', kind: 'speed', factor: 1.609344, names: ['mph', 'miles per hour']),
];

/// Names that are everyday words too ("in", "st", "mi"), a unit only straight after a number.
const Set<String> _ambiguous = {'in', 'm', 'g', 'l', 'st', 'mi'};

/// A unit by any of its names; [short] also for the names that need a number before them.
_Unit? _unitNamed(String word, bool short) {
  final w = jsTrim(word.toLowerCase());
  for (final unit in _unitTable) {
    if (unit.names.contains(w) && (short || !_ambiguous.contains(w))) return unit;
  }
  return null;
}

/// Every unit name as one alternation, longest first, names of one length in the table's order.
final String _unitNames = () {
  final names = [for (final unit in _unitTable) ...unit.names];
  final order = [for (var i = 0; i < names.length; i += 1) i]..sort((a, b) => names[b].length != names[a].length ? names[b].length - names[a].length : a - b);
  return order.map((i) => escapeRegExp(names[i])).join('|');
}();

/// A number and a unit straight after it: `180 °C`, `10km`, `2.5 kilos`.
final RegExp _measure = RegExp('(\\d+(?:[.,]\\d+)?)\\s*($_unitNames)(?![\\p{L}])', caseSensitive: false, unicode: true);
final RegExp _inUnit = RegExp('\\bin\\s+($_unitNames)(?![\\p{L}])', caseSensitive: false, unicode: true);
final RegExp _inOrHowMany = RegExp(r'^(?:in|how many)\s+', caseSensitive: false);
final RegExp _firstWordAfter = RegExp(r'^([^\s.,;:!?]+(?:\s+per\s+hour)?)');

Worked? _units(Asking asking) {
  final question = jsTrim(asking.question.replaceFirst(_closingStops, ''));
  var target = _unitNamed(question, true) ?? _unitNamed(question.replaceFirst(_inOrHowMany, ''), false);
  if (target == null) {
    final afterWord = _firstWordAfter.firstMatch(asking.after)?.group(1) ?? '';
    target = _unitNamed(afterWord, false);
  }
  if (target == null) {
    final inWords = _inUnit.firstMatch('${asking.sentence} ${asking.prior}');
    if (inWords != null) target = _unitNamed(inWords.group(1)!, false);
  }
  if (target == null) return null;
  ({double value, _Unit unit})? source;
  for (final m in _measure.allMatches('${asking.sentence} ${asking.prior}')) {
    final unit = _unitNamed(m.group(2)!, true);
    if (unit != null && unit.symbol != target.symbol) {
      source = (value: double.parse(m.group(1)!.replaceFirst(',', '.')), unit: unit);
      break;
    }
  }
  if (source == null || source.unit.kind != target.kind) return null;
  final from = source.unit;
  final double value;
  final String working;
  if (from.kind == 'temperature') {
    value = from.symbol == '°C' ? (source.value * 9) / 5 + 32 : ((source.value - 32) * 5) / 9;
    working = from.symbol == '°C' ? '${_js(source.value)} × 9 ÷ 5 + 32 = ${_round(value)}.' : '(${_js(source.value)} − 32) × 5 ÷ 9 = ${_round(value)}.';
  } else {
    value = (source.value * from.factor) / target.factor;
    final rate = from.factor / target.factor;
    working = '${_js(source.value)} ${from.symbol} × ${_round(rate, 4)} = ${_round(value)} ${target.symbol}.';
  }
  return _answered(Solver.units, '${_round(value)} ${target.symbol}', working);
}

/// A figure worth reading: whole where it is near whole, else to a tenth, or to [places] for a rate.
String _round(double value, [int places = 1]) {
  final whole = _jsRound(value);
  if ((value - whole).abs() < 0.05 && places == 1) return _enUs(whole);
  final scale = places == 1 ? 10.0 : 10000.0;
  return _enUs(_jsRound(value * scale) / scale, places);
}

// ---- the time -------------------------------------------------------------------------------------------------------

/// The device's own zone, as the phone said it ("Europe/London"), or null where it has not
/// (lib/core/phone_zones.dart): what the page has from `Intl.DateTimeFormat().resolvedOptions().timeZone`.
String? deviceZone;

/// A zone's offset by the device's own time-zone database, where the phone gave it: null for a zone or a moment
/// it did not answer for, and the table is read.
int? Function(String zone, DateTime at)? deviceOffsets;

/// A zone's offset from UTC at a moment, in minutes: the device's own database's where the phone gave it
/// ([deviceOffsets]), else read from the table of the solver's own zones (ai/support/time_zone_table.dart). The
/// table is what the page's `Intl` answers from 2000 to the end of 2040, to the minute; before and after, the
/// nearest offset it has. 0 for a zone neither has ([knowsZone]).
int offsetMinutes(String zone, DateTime at) {
  final own = deviceOffsets?.call(zone, at);
  if (own != null) return own;
  final table = zoneTable[zone];
  if (table == null) return 0;
  final minute = (at.millisecondsSinceEpoch / 60000).floor();
  // The pairs after the first number: the last change at or before the minute.
  var low = 0;
  var high = (table.length - 1) ~/ 2;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (table[mid * 2 - 1] <= minute) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low == 0 ? table[0] : table[low * 2];
}

/// Whether [offsetMinutes] has this zone: the zones of the solver's cities, and the device's own where the phone
/// answered for it.
bool knowsZone(String zone, [DateTime? at]) => zoneTable.containsKey(zone) || deviceOffsets?.call(zone, at ?? DateTime.now()) != null;

final List<({String city, RegExp pattern})> _cityPatterns = [
  for (final city in cities) (city: city, pattern: RegExp('\\b${city.replaceAll(' ', r'\s+')}\\b', caseSensitive: false)),
];

/// The known cities a text names, in the order it names them.
List<String> _citiesIn(String text) {
  final found = <({int at, String city})>[];
  var rest = text;
  for (final each in _cityPatterns) {
    final match = each.pattern.firstMatch(rest);
    if (match != null) {
      found.add((at: match.start, city: each.city));
      rest = '${rest.substring(0, match.start)}${' ' * (match.end - match.start)}${rest.substring(match.end)}';
    }
  }
  found.sort((a, b) => a.at - b.at);
  return [for (final f in found) f.city];
}

/// Hours and minutes as a person says them: `8 hours`, `5 hours 30 minutes`.
String _hoursWords(int minutes) {
  final whole = minutes.abs() ~/ 60;
  final rest = minutes.abs() % 60;
  return rest != 0 ? '${_plural(whole, 'hour')} ${_plural(rest, 'minute')}' : _plural(whole, 'hour');
}

/// The moment as a clock in [zone] shows it, by the clock's own offsets.
DateTime _wallIn(FactClock clock, String zone, DateTime at) => DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch + clock.offsetOf(zone, at) * 60000, isUtc: true);
String _clockIn(FactClock clock, String zone, DateTime at) => clockTime(_wallIn(clock, zone, at));
String _weekdayIn(FactClock clock, String zone, DateTime at) => weekdayName(_wallIn(clock, zone, at));
DateTime _utc(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

final RegExp _fourFigures = RegExp(r'\b\d{4}\b');
final RegExp _clockTime = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b', caseSensitive: false);
final RegExp _timeWords = RegExp(r'\b(time|hours?|ahead|behind)\b', caseSensitive: false);
final RegExp _difference = RegExp(r'\b(ahead of|behind|difference|hours between|time difference)\b', caseSensitive: false);
final RegExp _timeInNamed = RegExp(r"\btime\s+(?:is\s+it\s+)?in\s+([A-Z][\p{L}'.-]+(?:\s+[A-Z][\p{L}'.-]+)?)", unicode: true);
final RegExp _inMonth = RegExp('\\bin\\s+($_month)\\b', caseSensitive: false);
final RegExp _aheadOf = RegExp(r'\bahead of\b', caseSensitive: false);
final RegExp _behind = RegExp(r'\bbehind\b', caseSensitive: false);
final RegExp _whatTime = RegExp(r'\b(what time|the time|time in|time is it)\b', caseSensitive: false);

Worked? _time(Asking asking, FactClock clock) {
  final words = asking.text;
  final clockTimeFound = _clockTime.firstMatch(words.replaceAll(_fourFigures, ' '));
  final stated = clockTimeFound != null && (clockTimeFound.group(2) != null || clockTimeFound.group(3) != null);
  if (!stated && !_timeWords.hasMatch(words)) return null;
  final found = _citiesIn(words);
  final difference = _difference.hasMatch(words);
  final named = _timeInNamed.firstMatch(words);
  if (named != null && found.isEmpty) return _cannot(Solver.time, 'The app knows the time in about sixty cities, and ${named.group(1)} is not one.');
  if (difference && found.length >= 2) {
    final a = zoneOf(found[0])!;
    final b = zoneOf(found[1])!;
    final month = _inMonth.firstMatch(words);
    final today = _todayOf(clock.now);
    var start = DateTime.utc(_jsYear(today.y), today.m + 1, today.d, 12).millisecondsSinceEpoch;
    var days = 1;
    if (month != null) {
      final m = _monthOf(month.group(1)!);
      final y = m < today.m ? today.y + 1 : today.y;
      start = DateTime.utc(_jsYear(y), m + 1, 1, 12).millisecondsSinceEpoch;
      days = DateTime.utc(_jsYear(y), m + 2, 0).day;
    }
    int diffOn(int ms) => clock.offsetOf(a, _utc(ms)) - clock.offsetOf(b, _utc(ms));
    final first = diffOn(start);
    ({int at, int diff})? change;
    for (var d = 1; d < days; d += 1) {
      final at = start + d * _dayMs;
      if (diffOn(at) != first) {
        change = (at: at, diff: diffOn(at));
        break;
      }
    }
    final ahead = _aheadOf.hasMatch(words);
    final behind = _behind.hasMatch(words);
    String say(int diff) {
      if (!ahead && !behind) return _hoursWords(diff);
      final wrongWay = (ahead && diff < 0) || (behind && diff > 0);
      return wrongWay ? '${_hoursWords(diff)} ${diff < 0 ? 'behind' : 'ahead'}' : _hoursWords(diff);
    }

    String direction(int diff) => diff >= 0 ? 'ahead of' : 'behind';
    if (change != null) {
      final later = change.diff.abs() % 60 == 0 ? '${change.diff.abs() ~/ 60}' : _hoursWords(change.diff);
      final on = dayMonth(_utc(change.at));
      return _answered(Solver.time, '${say(first)}, $later from $on', '${found[0]} is ${_hoursWords(first)} ${direction(first)} ${found[1]} until $on, then ${_hoursWords(change.diff)}. The clocks change then.');
    }
    return _answered(Solver.time, say(first), '${found[0]} is ${_hoursWords(first)} ${direction(first)} ${found[1]}${month != null ? ' all through ${capitalise(month.group(1)!.toLowerCase())}' : ' today'}.');
  }
  if (clockTimeFound != null && stated && found.length >= 2) {
    var hour = int.parse(clockTimeFound.group(1)!) % 24;
    final half = clockTimeFound.group(3)?.toLowerCase();
    if (half == 'pm' && hour < 12) hour += 12;
    if (half == 'am' && hour == 12) hour = 0;
    final minute = int.parse(clockTimeFound.group(2) ?? '0');
    final from = zoneOf(found[0])!;
    final to = zoneOf(found[1])!;
    final today = _todayOf(clock.now);
    final guess = DateTime.utc(_jsYear(today.y), today.m + 1, today.d, hour, minute).millisecondsSinceEpoch;
    final at = _utc(guess - clock.offsetOf(from, _utc(guess)) * 60000);
    final there = _clockIn(clock, to, at);
    final sameDay = _weekdayIn(clock, from, at) == _weekdayIn(clock, to, at);
    return _answered(
      Solver.time,
      sameDay ? there : '$there ${_weekdayIn(clock, to, at)}',
      '${_clockIn(clock, from, at)} in ${found[0]} is $there${sameDay ? '' : ' on ${_weekdayIn(clock, to, at)}'} in ${found[1]}, today.',
    );
  }
  if (found.length == 1 && _whatTime.hasMatch(words)) {
    final zone = zoneOf(found[0])!;
    // The device's own zone: by its name where the clock gives one the offsets are known for, else by the offset the
    // device itself keeps at that moment, which has no city's name.
    // `clock.zone ?? Intl.DateTimeFormat().resolvedOptions().timeZone`.
    final here = clock.zone ?? deviceZone;
    final known = here != null && (clock.offsetOf != offsetMinutes || knowsZone(here, clock.now));
    final hereMinutes = known ? clock.offsetOf(here, clock.now) : clock.now.toLocal().timeZoneOffset.inMinutes;
    final diff = clock.offsetOf(zone, clock.now) - hereMinutes;
    final hereName = (known ? cityOf(here) : null) ?? 'here';
    final relation = diff == 0 ? '${found[0]} keeps the same time as $hereName today.' : '${found[0]} is ${_hoursWords(diff)} ${diff > 0 ? 'ahead of' : 'behind'} $hereName today.';
    return _answered(Solver.time, '${_clockIn(clock, zone, clock.now)} ${_weekdayIn(clock, zone, clock.now)}', '$relation It changes each minute.', Changes.minute);
  }
  return null;
}
