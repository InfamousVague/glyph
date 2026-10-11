// Ported from @codemirror/language 6.12 (src/stringstream.ts), which is:
//
// MIT License
//
// Copyright (C) 2018-2021 by Marijn Haverbeke <marijn@haverbeke.berlin> and others
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

/// One line of code, as CodeMirror's older modes read it: `StringStream`. A mode's `token` function eats
/// characters off the front and answers what they were.
///
/// A character is a string of one code unit, as it is in the JavaScript the modes are ported from; `null` is
/// JavaScript's `undefined`, the end of the line.
library;

final RegExp _space = RegExp('[\\s ]');
final RegExp _notSpace = RegExp('[^\\s ]');

int _countCol(String string, int? end, int tabSize, [int startIndex = 0, int startValue = 0]) {
  if (end == null) {
    end = string.indexOf(_notSpace);
    if (end == -1) end = string.length;
  }
  var n = startValue;
  for (var i = startIndex; i < end; i++) {
    if (string.codeUnitAt(i) == 9) {
      n += tabSize - (n % tabSize);
    } else {
      n++;
    }
  }
  return n;
}

class StringStream {
  StringStream(this.string, this.tabSize, this.indentUnit);

  /// The line.
  final String string;
  final int tabSize;

  /// The current indent unit size.
  final int indentUnit;

  /// The current position on the line.
  int pos = 0;

  /// The start position of the current token.
  int start = 0;
  int _lastColumnPos = 0;
  int _lastColumnValue = 0;

  /// True if we are at the end of the line.
  bool eol() => pos >= string.length;

  /// True if we are at the start of the line.
  bool sol() => pos == 0;

  /// The next character, or null at the end of the line.
  String? peek() => pos < string.length ? string[pos] : null;

  /// Read the next character and advance.
  String? next() => pos < string.length ? string[pos++] : null;

  /// Eats the next character if it is `ch`.
  String? eat(String ch) {
    if (pos < string.length && string[pos] == ch) return string[pos++];
    return null;
  }

  /// Eats the next character if it matches.
  String? eatMatch(RegExp match) {
    if (pos < string.length && match.hasMatch(string[pos])) return string[pos++];
    return null;
  }

  /// Eats the next character if `test` says so.
  String? eatIf(bool Function(String ch) test) {
    if (pos < string.length && test(string[pos])) return string[pos++];
    return null;
  }

  /// Continue matching characters that match. Return true if any characters were consumed.
  bool eatWhile(RegExp match) {
    final start = pos;
    while (eatMatch(match) != null) {}
    return pos > start;
  }

  bool eatWhileChar(String ch) {
    final start = pos;
    while (eat(ch) != null) {}
    return pos > start;
  }

  bool eatWhileIf(bool Function(String ch) test) {
    final start = pos;
    while (eatIf(test) != null) {}
    return pos > start;
  }

  /// Consume whitespace ahead of [pos]. Return true if any was found.
  bool eatSpace() {
    final start = pos;
    while (pos < string.length && _space.hasMatch(string[pos])) {
      ++pos;
    }
    return pos > start;
  }

  /// Move to the end of the line.
  void skipToEnd() => pos = string.length;

  /// Move to directly before the given character, if found on the current line.
  bool skipTo(String ch) {
    final found = string.indexOf(ch, pos);
    if (found > -1) {
      pos = found;
      return true;
    }
    return false;
  }

  /// Move back `n` characters.
  void backUp(int n) => pos -= n;

  /// Get the column position at the token's start.
  int column() {
    if (_lastColumnPos < start) {
      _lastColumnValue = _countCol(string, start, tabSize, _lastColumnPos, _lastColumnValue);
      _lastColumnPos = start;
    }
    return _lastColumnValue;
  }

  /// Get the indentation column of the current line.
  int indentation() => _countCol(string, null, tabSize);

  /// Whether the line goes on with `pattern`; moves past it unless `consume` is false.
  bool matchString(String pattern, {bool consume = true, bool caseInsensitive = false}) {
    if (pos + pattern.length > string.length) return false;
    final there = string.substring(pos, pos + pattern.length);
    if (caseInsensitive ? there.toLowerCase() != pattern.toLowerCase() : there != pattern) return false;
    if (consume) pos += pattern.length;
    return true;
  }

  /// The match of `pattern` (which should start with a `^`) at the position, or null; moves past it unless
  /// `consume` is false. The pattern is tried on the rest of the line cut off, as JavaScript's `slice` cuts it,
  /// so a `\b` or a `^` sees the position as a start.
  RegExpMatch? match(RegExp pattern, {bool consume = true}) {
    final found = pattern.firstMatch(pos == 0 ? string : string.substring(pos));
    if (found == null || found.start > 0) return null;
    if (consume) pos += found.end;
    return found;
  }

  /// Get the current token.
  String current() => string.substring(start, pos);
}
