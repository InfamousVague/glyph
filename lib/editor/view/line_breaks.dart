/// Where a line may break between two ASCII characters, made the page's.
///
/// Blink does not ask the Unicode line breaking algorithm about a pair of ASCII characters: it has a table of its
/// own (`blink_breaks.g.dart`, read off Chromium by tool/editor_reference.mjs), "for compatibility with other
/// browsers". Flutter's paragraph asks ICU. The two disagree where it shows most in a note: ICU breaks an address
/// after every `/` and Blink never does; Blink breaks before a `(` after a `]` or a full stop and after a `?`, and
/// ICU does not always. A line that breaks in another place is another height, and every line after it moves.
///
/// So the paragraph is told. [breakFix] says, for a pair, whether the paragraph must be given a place to break it
/// does not see (a zero-width space) or kept from breaking where it would (a word joiner); `PaintText` writes
/// them in. Both are default-ignorable: shaping passes over them, so a ligature or a kerned pair across one is
/// drawn as it was.
///
/// What ICU does with a pair is asked of the paragraph itself, once for each pair, with a letter either side as
/// the table was read. What differs from the page after this: a pair whose break depends on more than its two
/// characters and the one before (ICU's rules for numbers and quotations, mostly) is taken at its plain answer.
library;

import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'blink_breaks.g.dart';

const int _first = 0x21, _last = 0x7e, _span = _last - _first + 1;

/// U+200B, where a line may break; U+2060, where it may not.
const String zeroWidthSpace = '​', wordJoiner = '⁠';

/// What the paragraph has to be told about a pair.
enum BreakFix { none, allow, forbid }

bool _alnum(int unit) => (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);

// What the paragraph does by itself between each pair: 0 not asked yet, 1 no break, 2 break.
final Int8List _own = Int8List(_span * _span);

bool _paragraphBreaks(int before, int after) {
  final at = (before - _first) * _span + (after - _first);
  if (_own[at] != 0) return _own[at] == 2;
  // A lead with one place to break early in it, then the pair: given just the room for everything up to the first
  // of the pair, the first line ends between the two only if a line may break there. Anywhere else it may end
  // (the early place, or before the pair) is a different length.
  const lead = 'x​xxx';
  const style = TextStyle(fontSize: 10, letterSpacing: 0);
  final head = '$lead${String.fromCharCode(before)}';
  final measure = TextPainter(text: TextSpan(text: head, style: style), textDirection: TextDirection.ltr)..layout();
  final probe = TextPainter(text: TextSpan(text: '$head${String.fromCharCode(after)}xxxx', style: style), textDirection: TextDirection.ltr)
    ..layout(maxWidth: measure.width + 0.01);
  final breaks = probe.getLineBoundary(const TextPosition(offset: 0)).end == head.length;
  measure.dispose();
  probe.dispose();
  _own[at] = breaks ? 2 : 1;
  return breaks;
}

/// Whether the page may break a line between `before` and `after`, where it has a rule of its own for the pair:
/// null for a pair it leaves to the Unicode algorithm. `earlier` is the character before `before`, or -1.
bool? blinkBreaks(int earlier, int before, int after) {
  if (before < _first || before > _last || after < _first || after > _last) return null;
  // "Don't allow line breaking between '-' and a digit if the '-' may mean a minus sign in the context, while
  // allow breaking in 'ABCD-1234' and '1234-5678' which may be in long URLs."
  if (before == 0x2d && after >= 0x30 && after <= 0x39) return earlier >= 0 && _alnum(earlier);
  return blinkAsciiBreaks[before - _first].codeUnitAt(after - _first) == 0x31;
}

/// What the paragraph must be told about the pair `before`, `after` so it breaks there as the page does.
BreakFix breakFix(int earlier, int before, int after) {
  // Two letters or digits are a word in both.
  if (_alnum(before) && _alnum(after)) return BreakFix.none;
  final want = blinkBreaks(earlier, before, after);
  if (want == null) return BreakFix.none;
  final has = _paragraphBreaks(before, after);
  if (want == has) return BreakFix.none;
  return want ? BreakFix.allow : BreakFix.forbid;
}
