/// Characters in a UTF-16 string: CodeMirror's `findClusterBreak`, `codePointAt`, `fromCodePoint`, `codePointSize`
/// (@codemirror/state, char.ts, over @marijn/find-cluster-break) and `countColumn` / `findColumn` (column.ts).
///
/// These are CodeMirror's own rules for where a caret may stand, not the whole of Unicode's: surrogate pairs,
/// extending marks, zero-width joiners and flags. They are ported as they are so a caret stops where the web app's
/// does.
library;

import 'char_data.dart';

final List<int> _rangeFrom = <int>[];
final List<int> _rangeTo = <int>[];
bool _unpacked = false;

void _unpack() {
  if (_unpacked) return;
  _unpacked = true;
  final numbers = extendRanges.split(',');
  var n = 0;
  for (var i = 0; i < numbers.length; i++) {
    n += numbers[i].isEmpty ? 1 : int.parse(numbers[i], radix: 36);
    (i.isOdd ? _rangeTo : _rangeFrom).add(n);
  }
}

/// Whether a code point extends the character before it (find-cluster-break's `isExtendingChar`).
bool isExtendingChar(int code) {
  if (code < 768) return false;
  _unpack();
  for (var from = 0, to = _rangeFrom.length;;) {
    final mid = (from + to) >> 1;
    if (code < _rangeFrom[mid]) {
      to = mid;
    } else if (code >= _rangeTo[mid]) {
      from = mid + 1;
    } else {
      return true;
    }
    if (from == to) return false;
  }
}

bool _isRegionalIndicator(int code) => code >= 0x1F1E6 && code <= 0x1F1FF;

const int _zwj = 0x200d;

/// The next cluster break after `pos` (not at it) when `forward`, or the one before it otherwise; `pos` itself when
/// there is none further (CodeMirror's `findClusterBreak`).
int findClusterBreak(String str, int pos, [bool forward = true, bool includeExtending = true]) =>
    forward ? _nextClusterBreak(str, pos, includeExtending) : _prevClusterBreak(str, pos, includeExtending);

int _nextClusterBreak(String str, int pos, bool includeExtending) {
  if (pos == str.length) return pos;
  // If pos is in the middle of a surrogate pair, move to its start
  if (pos > 0 && _surrogateLow(str.codeUnitAt(pos)) && _surrogateHigh(str.codeUnitAt(pos - 1))) pos--;
  var prev = codePointAt(str, pos);
  pos += codePointSize(prev);
  while (pos < str.length) {
    final next = codePointAt(str, pos);
    if (prev == _zwj || next == _zwj || includeExtending && isExtendingChar(next)) {
      pos += codePointSize(next);
      prev = next;
    } else if (_isRegionalIndicator(next)) {
      var countBefore = 0, i = pos - 2;
      while (i >= 0 && _isRegionalIndicator(codePointAt(str, i))) {
        countBefore++;
        i -= 2;
      }
      if (countBefore.isEven) {
        break;
      } else {
        pos += 2;
      }
    } else {
      break;
    }
  }
  return pos;
}

int _prevClusterBreak(String str, int pos, bool includeExtending) {
  while (pos > 1) {
    final found = _nextClusterBreak(str, pos - 2, includeExtending);
    if (found < pos) return found;
    pos--;
  }
  return 0;
}

bool _surrogateLow(int ch) => ch >= 0xDC00 && ch < 0xE000;
bool _surrogateHigh(int ch) => ch >= 0xD800 && ch < 0xDC00;

/// The code point at `pos` in a string (CodeMirror's `codePointAt`): a pair read as one, a lone half as itself.
int codePointAt(String str, int pos) {
  final code0 = str.codeUnitAt(pos);
  if (!_surrogateHigh(code0) || pos + 1 == str.length) return code0;
  final code1 = str.codeUnitAt(pos + 1);
  if (!_surrogateLow(code1)) return code0;
  return ((code0 - 0xd800) << 10) + (code1 - 0xdc00) + 0x10000;
}

/// The string for a code point (CodeMirror's `fromCodePoint`).
String fromCodePoint(int code) {
  if (code <= 0xffff) return String.fromCharCode(code);
  code -= 0x10000;
  return String.fromCharCodes(<int>[(code >> 10) + 0xd800, (code & 1023) + 0xdc00]);
}

/// How many UTF-16 units a code point takes: 1 or 2 (CodeMirror's `codePointSize`).
int codePointSize(int code) => code < 0x10000 ? 1 : 2;

/// The column at `to` in a string, tabs counted to the next multiple of `tabSize` and a cluster as one column
/// (CodeMirror's `countColumn`).
int countColumn(String string, int tabSize, [int? to]) {
  to ??= string.length;
  var n = 0;
  for (var i = 0; i < to && i < string.length;) {
    if (string.codeUnitAt(i) == 9) {
      n += tabSize - (n % tabSize);
      i++;
    } else {
      n++;
      i = findClusterBreak(string, i);
    }
  }
  return n;
}

/// The offset in a string of column `col` (CodeMirror's `findColumn`). Past the end: the string's length, or -1 when
/// `strict`.
int findColumn(String string, int col, int tabSize, [bool strict = false]) {
  for (var i = 0, n = 0;;) {
    if (n >= col) return i;
    if (i == string.length) break;
    n += string.codeUnitAt(i) == 9 ? tabSize - (n % tabSize) : 1;
    i = findClusterBreak(string, i);
  }
  return strict ? -1 : string.length;
}
