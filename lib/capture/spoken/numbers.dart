/// Numbers and sums as they are said: "four hundred fifty", "twenty-one", "four four one seven" read a digit at a
/// time, and "four hundred fifty plus one hundred twenty times two", worked out on the page as `= 450 + 120 * 2`. A
/// port of `src/app/capture/spoken/numbers.ts`.
///
/// What the cues that take a number need (a counter, a numbered item, a sum, a formula, a raised or lowered word) and
/// what the voice suite compares recorded audio by (capture/voice_suite.dart `heardForm`), so a number said is a
/// number however Whisper spelled it. Pure.
///
/// What differs: the names of the constants, lower camel case (`ONE_TO_TEN` is [oneToTen], `NUMBER_WORD`
/// [numberWord], `SMALL_NUMBER` [smallNumber], `NUMBER_PHRASE` [numberPhrase]). [spokenNumber] answers a `num` that is
/// an `int` whenever the number is whole, so `'$value'` writes "450" as the web's does, never "450.0". The web reads
/// its number words from a plain object, so "constructor" counts as a number word there; here it is not one.
library;

const Map<String, int> _numberWords = {
  'zero': 0, 'none': 0, 'nil': 0, 'oh': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, //
  'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
  'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
  'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
};

/// The words a number is said in, as regex alternations, written once for every pattern that finds one: a count, a
/// table's column, a number inside a sentence, and the voice suite's runs of them (`ONE_TO_TEN`).
const String oneToTen = 'one|two|three|four|five|six|seven|eight|nine|ten';
const String _elevenToNinety =
    'eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety';

/// Every word a number from zero to the thousands is said in (`NUMBER_WORD`).
const String numberWord = 'zero|$oneToTen|$_elevenToNinety|hundred|thousand';

/// A small count said or written, as a cue that numbers something takes one: "number three", "item number 12"
/// (`SMALL_NUMBER`).
const String smallNumber = '(?:$oneToTen|\\d{1,2})';

final RegExp _thousandsComma = RegExp(r',(?=\d{3})');
final RegExp _digits = RegExp(r'^\d+(?:\.\d+)?$');
final RegExp _digit = RegExp(r'^\d$');
final RegExp _wordGap = RegExp(r'[\s-]+');

/// JS's `Number(text)` for a run of digits with at most one point: whole numbers as an `int`.
num _number(String text) => _whole(num.parse(text));

num _whole(num value) => value is double && value.isFinite && value == value.truncateToDouble() && value.abs() < 9e15 ? value.toInt() : value;

/// A number said in words or written in digits: "four hundred fifty", "1,200", "twenty-one", "two thousand and five".
/// Null when it isn't one.
num? spokenNumber(String text) {
  final said = text.trim().toLowerCase().replaceAll(_thousandsComma, '');
  if (_digits.hasMatch(said)) return _number(said);
  final words = said.split(_wordGap).where((word) => word.isNotEmpty && word != 'and').toList();
  if (words.isEmpty) return null;
  // "Four four one seven" is a code read out a digit at a time: 4417, not 16.
  if (words.length > 1 && words.every((word) => (_numberWords[word] ?? 99) < 10 || _digit.hasMatch(word))) {
    return _number(words.map((word) => _digit.hasMatch(word) ? word : '${_numberWords[word]}').join());
  }
  num total = 0;
  num group = 0;
  for (final word in words) {
    final known = _numberWords[word];
    if (known != null) {
      group += known;
    } else if (word == 'hundred') {
      group = (group == 0 ? 1 : group) * 100;
    } else if (word == 'thousand') {
      total += (group == 0 ? 1 : group) * 1000;
      group = 0;
    } else if (word == 'million') {
      total += (group == 0 ? 1 : group) * 1000000;
      group = 0;
    } else if (_digits.hasMatch(word)) {
      group += _number(word);
    } else {
      return null;
    }
  }
  return _whole(total + group);
}

/// A number as it may be said inside a sentence, in digits or in words, for a pattern to find before [spokenNumber]
/// reads it (`NUMBER_PHRASE`).
const String numberPhrase = '(?:\\d[\\d,]*(?:\\.\\d+)?|(?:(?:zero|none|$oneToTen|$_elevenToNinety|hundred|thousand|million|and)[\\s-]*)+)';

/// The operators as they are said, and the signs they are written as. "x" is times only with a space either side.
final List<(RegExp, String, bool)> _operators = [
  (RegExp(r'\bto\s+the\s+power\s+of\b', caseSensitive: false), ' ^ ', false),
  (RegExp(r'\b(?:multiplied\s+by|times)\b', caseSensitive: false), ' * ', false),
  (RegExp(r'\b(?:divided\s+by|over)\b', caseSensitive: false), ' / ', false),
  (RegExp(r'\bplus\b', caseSensitive: false), ' + ', false),
  (RegExp(r'\bminus\b', caseSensitive: false), ' - ', false),
  // The one spokenMaths leaves out: "x" is a letter there.
  (RegExp(r'\s[x×]\s'), ' * ', true),
  (RegExp('÷'), ' / ', false),
];

final RegExp _stopsAtEnd = RegExp(r'[.?!]+$');
final RegExp _signSplit = RegExp(r'\s*([-+*/^()])\s*');
final RegExp _operator = RegExp(r'^[-+*/^]$');
final RegExp _sign = RegExp(r'^[-+*/^()]$');
final RegExp _currency = RegExp(r'^[$€£]');
final RegExp _percent = RegExp(r'%$|\s+percent$', caseSensitive: false);

/// JS's `split` with a pattern of one group: the pieces, with what the group matched between them.
List<String> _splitKeeping(String text, RegExp pattern) {
  final out = <String>[];
  var from = 0;
  for (final found in pattern.allMatches(text)) {
    // JS never splits on an empty match at the very start or end, and these patterns never match empty.
    out.add(text.substring(from, found.start));
    out.add(found.group(1) ?? '');
    from = found.end;
  }
  out.add(text.substring(from));
  return out;
}

/// "Four hundred fifty plus one hundred twenty times two" as `450 + 120 * 2`, or null when it isn't a sum.
String? spokenSum(String text) {
  var said = ' ${text.trim().replaceFirst(_stopsAtEnd, '')} ';
  for (final (word, symbol, _) in _operators) {
    said = said.replaceAll(word, symbol);
  }
  final parts = _splitKeeping(said, _signSplit).map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  if (!parts.any(_operator.hasMatch)) return null;
  final out = <String>[];
  for (final part in parts) {
    if (_sign.hasMatch(part)) {
      out.add(part);
      continue;
    }
    final sign = _currency.firstMatch(part)?.group(0) ?? '';
    final percent = _percent.hasMatch(part) ? '%' : '';
    final value = spokenNumber(part.replaceFirst(_currency, '').replaceFirst(_percent, ''));
    if (value == null) return null;
    out.add('$sign$value$percent');
  }
  return out.join(' ').replaceAll('( ', '(').replaceAll(' )', ')');
}

final RegExp _phrase = RegExp('\\b$numberPhrase\\b', caseSensitive: false);
final RegExp _andAtEnd = RegExp(r'\s+and\s*$');

/// "x squared plus two y" as `x^2 + 2 y`: the operators as signs and the numbers as digits, the letters as said.
String spokenMaths(String text) {
  var said = ' ${text.trim().toLowerCase()} '
      .replaceAll(RegExp(r'\bsquared\b'), '^2')
      .replaceAll(RegExp(r'\bcubed\b'), '^3')
      .replaceAll(RegExp(r'\b(?:is\s+)?equals?(?:\s+to)?\b'), ' = ')
      .replaceAll(RegExp(r'\bsquare\s+root\s+of\b'), r' \sqrt ')
      .replaceAll(RegExp(r'\bopen\s+brackets?\b'), ' ( ')
      .replaceAll(RegExp(r'\bclose\s+brackets?\b'), ' ) ');
  // "x" is a letter here, not "times".
  for (final (word, symbol, times) in _operators) {
    if (!times) said = said.replaceAll(word, symbol);
  }
  said = said.replaceAllMapped(_phrase, (found) {
    final phrase = found.group(0)!;
    final value = spokenNumber(phrase.replaceFirst(_andAtEnd, ''));
    return value == null ? phrase : ' $value ';
  });
  return said
      .replaceAll(RegExp(r'\s*\^\s*'), '^')
      .replaceAll(RegExp(r'\(\s+'), '(')
      .replaceAll(RegExp(r'\s+\)'), ')')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

const Map<String, String> _alone = {'to': '2', 'too': '2', 'for': '4', 'won': '1'};
final RegExp _leadingSpace = RegExp(r'^\s*');
final RegExp _trailingSpace = RegExp(r'\s*$');
final RegExp _beforeOrdinal = RegExp(r'(\d)\s+(?=(?:st|nd|rd|th)\b)', caseSensitive: false);

/// Raised or lowered words: numbers as digits, and no bare space, which ends the mark (`^2nd^`, `~2~`, `^to\ be^`).
String spokenScript(String text) {
  // Said alone, "to" and "for" are the numbers: "metres superscript two" is heard "superscript to".
  final alone = _alone[text.trim().toLowerCase()];
  if (alone != null) return alone;
  final said = text.trim().replaceAllMapped(_phrase, (found) {
    final phrase = found.group(0)!;
    final value = spokenNumber(phrase);
    return value == null ? phrase : '${_leadingSpace.firstMatch(phrase)?.group(0) ?? ''}$value${_trailingSpace.firstMatch(phrase)?.group(0) ?? ''}';
  });
  return said.trim().replaceAllMapped(_beforeOrdinal, (m) => m.group(1)!).replaceAll(RegExp(r'\s+'), r'\ ');
}
