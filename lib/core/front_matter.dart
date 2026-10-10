/// A note's front matter: what counts as it, and one key read out of it. A port of the reading half of
/// `src/app/core/frontMatter.ts`, under the web's own names, so the list's title, a notebook's `book: true` and a
/// ticket's `type: ticket` are all read where the web app reads them.
///
/// The rule is the list's: a fence on the first line, then lines that are each a `key:` or blank, then a fence that
/// closes it within the first 40 lines. A note that opens with a rule and some words is a note that opens with a rule.
///
/// What differs: only the readers and `quotedTitle` are here. The writers (`withFrontMatterTitle`,
/// `withFrontMatterValue`) come with the editor.
///
/// **Read where it lies.** These are asked of every note in every list, so none of them splits the body or builds
/// a pattern: [frontMatterOffset], [frontMatterValue] and [frontMatterSpan] walk the front matter's own lines in
/// the body, from one line break to the next, and stop at the fence that closes it (a note with no front matter is
/// answered from its first three characters). Each line is read character by character, to the letter as the
/// patterns the web has for them read it ([frontMatterFence], and its `key:` line); test/core/front_matter_test.dart
/// holds the two readings to one answer. They were a `split('\n')` of the whole body and a `RegExp` made per call:
/// measured walking a library of 354 notes, half of all the time the home page took to come back from a note.
library;

/// A front matter fence, `---` or `+++`, on a line of its own (`FENCE`). The readers below read a fence by hand
/// ([_fenceAt]); this is the same rule as a pattern, for whoever has a line in hand.
final RegExp frontMatterFence = RegExp(r'^(---|\+\+\+)\s*$');

/// The most lines front matter may take, both fences included (`FRONT_MATTER_LINES`).
const int frontMatterLines = 40;

/// A pattern's `\s`, JavaScript's and Dart's alike: a tab, the line breaks, a space, and Unicode's spaces.
bool _space(int c) {
  if (c < 0x80) return c == 0x20 || (c >= 0x09 && c <= 0x0D);
  return c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF;
}

/// What Dart's `trim` takes off: a pattern's `\s`, and U+0085 with it.
bool _trimmed(int c) => c == 0x85 || _space(c);

/// Whether `text[from..to)` is blank as `trim` has it: `text.substring(from, to).trim().isEmpty`, with no string made.
bool blankIn(String text, int from, int to) {
  for (var i = from; i < to; i += 1) {
    if (!_trimmed(text.codeUnitAt(i))) return false;
  }
  return true;
}

/// What a pattern's `.` does not match: where a line ends.
bool _lineEnd(int c) => c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029;

/// A key's letter: `[\w.-]`.
bool _keyLetter(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x5F || c == 0x2E || c == 0x2D;

/// Whether `text[from..to)` is a fence ([frontMatterFence]): three dashes or three pluses, then spaces alone.
bool _fenceAt(String text, int from, int to) {
  if (to - from < 3) return false;
  final c = text.codeUnitAt(from);
  if ((c != 0x2D && c != 0x2B) || text.codeUnitAt(from + 1) != c || text.codeUnitAt(from + 2) != c) return false;
  for (var i = from + 3; i < to; i += 1) {
    if (!_space(text.codeUnitAt(i))) return false;
  }
  return true;
}

/// Whether `text[from..to)` is a line front matter may hold: a `key:` (`^\s*[\w.-]+\s*:`), or blank as `trim` has it.
bool _heldAt(String text, int from, int to) {
  var i = from;
  while (i < to && _space(text.codeUnitAt(i))) {
    i += 1;
  }
  final key = i;
  while (i < to && _keyLetter(text.codeUnitAt(i))) {
    i += 1;
  }
  if (i > key) {
    while (i < to && _space(text.codeUnitAt(i))) {
      i += 1;
    }
    if (i < to && text.codeUnitAt(i) == 0x3A) return true;
  }
  return blankIn(text, from, to);
}

/// Where a note's front matter ends: the index of the first line after its closing fence, or 0 where it has none.
/// So `lines.sublist(frontMatterEnd(lines))` is always the note's words.
int frontMatterEnd(List<String> lines) {
  if (lines.isEmpty || !_fenceAt(lines[0], 0, lines[0].length)) return 0;
  final most = lines.length < frontMatterLines ? lines.length : frontMatterLines;
  for (var n = 1; n < most; n += 1) {
    final line = lines[n];
    if (_fenceAt(line, 0, line.length)) return n + 1;
    if (!_heldAt(line, 0, line.length)) return 0;
  }
  return 0;
}

/// Where a body's front matter is, found without splitting the body: how many lines it takes, both fences
/// included ([frontMatterEnd] of the body's lines), where its closing fence's line begins, and where the note's
/// words begin ([frontMatterOffset]). [none] for a body with no front matter.
class FrontMatterSpan {
  const FrontMatterSpan._(this.lines, this.closing, this.offset);

  /// A body with no front matter: no lines of it, and its words from the first character.
  static const FrontMatterSpan none = FrontMatterSpan._(0, 0, 0);

  /// The index of the first line after the closing fence; 0 where there is no front matter.
  final int lines;

  /// Where the closing fence's line begins in the body: the keys' lines are from the first line break to here.
  final int closing;

  /// The first character after the closing fence's line break, or the body's length where nothing follows it.
  final int offset;

  bool get isEmpty => lines == 0;
}

/// [frontMatterEnd] and [frontMatterOffset] of [body] at once, reading no further than the closing fence.
FrontMatterSpan frontMatterSpan(String body) {
  final length = body.length;
  // Nothing shorter than a fence, and nothing that does not open with one, has front matter: most notes stop here.
  if (length < 3) return FrontMatterSpan.none;
  final first = body.codeUnitAt(0);
  if (first != 0x2D && first != 0x2B) return FrontMatterSpan.none;
  var end = body.indexOf('\n');
  // One line alone has no fence to close it.
  if (end < 0 || !_fenceAt(body, 0, end)) return FrontMatterSpan.none;
  for (var n = 1; n < frontMatterLines; n += 1) {
    final from = end + 1;
    final next = body.indexOf('\n', from);
    final to = next < 0 ? length : next;
    if (_fenceAt(body, from, to)) return FrontMatterSpan._(n + 1, from, next < 0 ? length : next + 1);
    if (next < 0 || !_heldAt(body, from, to)) return FrontMatterSpan.none;
    end = next;
  }
  return FrontMatterSpan.none;
}

/// [frontMatterEnd] as an offset into the body: the first character after the closing fence's line break, or 0.
int frontMatterOffset(String body) => frontMatterSpan(body).offset;

/// A key no line is read for by hand: one with a letter outside ASCII (a pattern folds its case its own way), one
/// that opens with a space (the pattern's `\s*` gives it back), or none at all. Read by the pattern, kept by key.
final Map<String, RegExp> _patterns = <String, RegExp>{};

bool _plainKey(String key) {
  if (key.isEmpty || _space(key.codeUnitAt(0))) return false;
  for (var i = 0; i < key.length; i += 1) {
    if (key.codeUnitAt(i) >= 0x80) return false;
  }
  return true;
}

/// Whether two ASCII characters are one letter, in either case.
bool _sameLetter(int a, int b) {
  if (a == b) return true;
  final low = a | 0x20;
  return low == (b | 0x20) && low >= 0x61 && low <= 0x7A;
}

/// The value of [key] on the line `body[from..to)`, as `^\s*key\s*:\s*(.*?)\s*$` reads it in any case: what follows
/// the colon with the spaces off both its ends. Null where the line is not the key's.
String? _valueAt(String body, int from, int to, String key) {
  var i = from;
  while (i < to && _space(body.codeUnitAt(i))) {
    i += 1;
  }
  final length = key.length;
  if (to - i < length + 1) return null;
  for (var k = 0; k < length; k += 1) {
    if (!_sameLetter(body.codeUnitAt(i + k), key.codeUnitAt(k))) return null;
  }
  i += length;
  while (i < to && _space(body.codeUnitAt(i))) {
    i += 1;
  }
  if (i >= to || body.codeUnitAt(i) != 0x3A) return null;
  i += 1;
  while (i < to && _space(body.codeUnitAt(i))) {
    i += 1;
  }
  var end = to;
  while (end > i && _space(body.codeUnitAt(end - 1))) {
    end -= 1;
  }
  // The pattern's `.` stops where a line ends: a value with a carriage return inside it is not read.
  for (var at = i; at < end; at += 1) {
    if (_lineEnd(body.codeUnitAt(at))) return null;
  }
  return body.substring(i, end);
}

/// One key's value from the front matter, its quotes taken off, or null where there is no front matter or no such
/// key. A book note says `book: true`; a canvas note is named by `title:`.
String? frontMatterValue(String body, String key) {
  final span = frontMatterSpan(body);
  if (span.isEmpty) return null;
  return frontMatterValueIn(body, span, key);
}

/// [frontMatterValue] for a body whose front matter has been found already ([frontMatterSpan]).
String? frontMatterValueIn(String body, FrontMatterSpan span, String key) {
  if (span.isEmpty) return null;
  final plain = _plainKey(key);
  final pattern = plain ? null : _patterns[key] ??= RegExp('^\\s*${RegExp.escape(key)}\\s*:\\s*(.*?)\\s*\$', caseSensitive: false);
  // The keys' lines: after the opening fence's line break, up to the closing fence's line.
  var from = body.indexOf('\n') + 1;
  while (from < span.closing) {
    final to = body.indexOf('\n', from);
    if (pattern == null) {
      final value = _valueAt(body, from, to, key);
      if (value != null) return unquoted(value);
    } else {
      final m = pattern.firstMatch(body.substring(from, to));
      if (m != null) return unquoted(m.group(1) ?? '');
    }
    from = to + 1;
  }
  return null;
}

final RegExp _double = RegExp(r'^"(.*)"$');
final RegExp _single = RegExp(r"^'(.*)'$");
final RegExp _escaped = RegExp(r'\\(["\\])');

/// A value as written with its quotes taken off, the way YAML reads them: in double quotes `\"` is a quote and `\\` a
/// backslash, in single quotes `''` is one quote, and a value in neither is as it is.
String unquoted(String value) {
  // Neither pattern reads a value that does not open with its quote.
  if (value.isEmpty) return value;
  final first = value.codeUnitAt(0);
  if (first != 0x22 && first != 0x27) return value;
  final double = _double.firstMatch(value);
  if (double != null) return (double.group(1) ?? '').replaceAllMapped(_escaped, (m) => m.group(1)!);
  final single = _single.firstMatch(value);
  if (single != null) return (single.group(1) ?? '').replaceAll("''", "'");
  return value;
}

final RegExp _quoteOrBreak = RegExp(r'["\n]');

/// A title as a front matter value: quoted, with a quote or a line break in it made a single quote, and [fallback]
/// where nothing is left.
String quotedTitle(String title, String fallback) {
  final clean = title.replaceAll(_quoteOrBreak, "'").trim();
  return '"${clean.isEmpty ? fallback : clean}"';
}
