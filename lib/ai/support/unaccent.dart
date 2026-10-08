/// Words with their accents off, as the page takes them off: JavaScript's
/// `text.normalize('NFD').replace(/\p{Diacritic}/gu, '')`, which the check on a fill reads a note's words through
/// (`src/app/ai/fills/shape.ts` `lowerWords`) and the time solver a city's name (`src/app/core/timeZones.ts` `fold`).
/// It belongs in lib/core beside `text.dart` once a second stage needs it.
///
/// Dart has no normaliser without a package, so the decompositions are a table written by `tool/ai_fixtures.mjs` from
/// JavaScript's own (`unaccent_table.dart`), a Hangul syllable is taken apart by the standard's arithmetic, and the
/// diacritics themselves go by the same `\p{Diacritic}`.
///
/// What differs: NFD also puts a run of combining marks into one order, which this does not. It shows only where a
/// letter carries two marks that are not diacritics and were typed in the other order, and then only as a different
/// order of the marks left. The table is the Unicode the tool's Node knew; Dart's `\p{Diacritic}` is its own
/// engine's.
library;

import 'unaccent_table.dart';

/// The table, read once: a character's code point to its decomposition with the diacritics off.
final Map<int, String> _folded = () {
  final map = <int, String>{};
  for (final line in unaccentTable.split('\n')) {
    final at = line.indexOf('=');
    if (at < 0) continue;
    final to = line.substring(at + 1);
    map[int.parse(line.substring(0, at), radix: 16)] = to.isEmpty ? '' : String.fromCharCodes([for (final code in to.split(' ')) int.parse(code, radix: 16)]);
  }
  return map;
}();

final RegExp _diacritic = RegExp(r'\p{Diacritic}', unicode: true);

/// [text] taken apart as NFD takes it and its diacritics dropped: "São Paulo" is "Sao Paulo", "が" is "か".
String unaccented(String text) {
  var plain = true;
  for (var i = 0; i < text.length; i += 1) {
    if (text.codeUnitAt(i) >= 0xC0) {
      plain = false;
      break;
    }
  }
  // Below U+00C0 nothing decomposes, but `^`, a backtick, `¨`, `¯`, `´`, `·` and `¸` are diacritics all the same.
  if (plain) return text.replaceAll(_diacritic, '');
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0xAC00 && rune <= 0xD7A3) {
      final s = rune - 0xAC00;
      out.writeCharCode(0x1100 + s ~/ 588);
      out.writeCharCode(0x1161 + (s % 588) ~/ 28);
      if (s % 28 != 0) out.writeCharCode(0x11A7 + s % 28);
      continue;
    }
    final folded = _folded[rune];
    if (folded != null) {
      out.write(folded);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString().replaceAll(_diacritic, '');
}
