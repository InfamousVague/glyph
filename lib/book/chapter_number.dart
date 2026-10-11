/// A chapter's number, read from its title (Matt: "make chapters numbered with some standard identifiers for books
/// maybe at the end of the title and that should let us lay out the chapters in order when there is no book"). A
/// port of `src/app/book/chapterNumber.ts`. The number lets chapters be put in order when no book's index says the
/// order. ../glyph docs/BOOKS.md has the standard.
///
/// The standard, at the end of the title:
///
///     The risks, and a glossary · Ch. 8
///     The risks, and a glossary (Chapter 8)
///     The risks, and a glossary · Chapter VIII
///
/// "Ch." or "Chapter", then an Arabic or Roman number, after a middle dot, a dash, a comma or a colon, or in
/// brackets. The way many chapters are already titled, a number in front, is read too:
///
///     08 · The risks, and a glossary
///     Chapter 8: The risks, and a glossary
///
/// A bare number at the end ("Top 10") is not a chapter number: too many titles end with one.
library;

import '../core/item_syntax.dart' show jsTrim;

class ChapterNumber {
  const ChapterNumber({required this.number, required this.name});
  final int number;

  /// The title without its number.
  final String name;

  @override
  bool operator ==(Object other) => other is ChapterNumber && other.number == number && other.name == name;

  @override
  int get hashCode => Object.hash(number, name);

  @override
  String toString() => 'ChapterNumber($number, $name)';
}

/// Before "Ch." at the end: a mark, a bracket or at least a space, so "Batch 5" isn't chapter 5.
const String _sep = r'(?:\s*[·•|:,—–-]\s*|\s*[(\[]\s*|\s+)';
const String _word = r'(?:ch(?:apter)?\.?|§)';

/// Roman numbers up to C's: no book has a thousand chapters, and "mix" is 1009.
const String _num = r'(\d{1,3}|[ivxlc]{1,8})';
final RegExp _atEnd = RegExp('^(.*?\\S)$_sep$_word\\s*$_num\\s*[)\\]]?\\s*\$', caseSensitive: false);
final RegExp _wordFirst = RegExp('^\\s*$_word\\s*$_num\\s*[·•|:.—–-]\\s*(\\S.*)\$', caseSensitive: false);
final RegExp _numberFirst = RegExp(r'^\s*(\d{1,3})\s*[·•|—–]\s*(\S.*)$');
final RegExp _digits = RegExp(r'^\d+$');

const Map<String, int> _roman = {'i': 1, 'v': 5, 'x': 10, 'l': 50, 'c': 100};

/// An Arabic or Roman number, or null for letters that aren't one written the usual way.
int? _valueOf(String written) {
  if (_digits.hasMatch(written)) return int.parse(written);
  final lower = written.toLowerCase();
  var total = 0;
  for (var n = 0; n < lower.length; n += 1) {
    final here = _roman[lower[n]];
    if (here == null) return null;
    final next = n + 1 < lower.length ? (_roman[lower[n + 1]] ?? 0) : 0;
    total += here < next ? -here : here;
  }
  // "civil" or "ill" are words, not numbers: only a numeral that writes back the same way counts.
  return total > 0 && _toRoman(total) == lower ? total : null;
}

String _toRoman(int value) {
  const steps = [(100, 'c'), (90, 'xc'), (50, 'l'), (40, 'xl'), (10, 'x'), (9, 'ix'), (5, 'v'), (4, 'iv'), (1, 'i')];
  final out = StringBuffer();
  var left = value;
  for (final (size, mark) in steps) {
    while (left >= size) {
      out.write(mark);
      left -= size;
    }
  }
  return out.toString();
}

/// The chapter number a title carries, and the title without it; null for a title with none.
ChapterNumber? chapterOf(String title) {
  final clean = jsTrim(title);
  final end = _atEnd.firstMatch(clean);
  if (end != null) {
    final number = _valueOf(end.group(2)!);
    if (number != null) return ChapterNumber(number: number, name: jsTrim(end.group(1)!));
  }
  final word = _wordFirst.firstMatch(clean);
  if (word != null) {
    final number = _valueOf(word.group(1)!);
    if (number != null) return ChapterNumber(number: number, name: jsTrim(word.group(2)!));
  }
  final first = _numberFirst.firstMatch(clean);
  if (first != null) return ChapterNumber(number: int.parse(first.group(1)!), name: jsTrim(first.group(2)!));
  return null;
}
