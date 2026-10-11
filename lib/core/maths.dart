/// Maths in a note's words: `$x^2$` inline and `$$a + b$$` on a line, found the way Pandoc finds them. A port of
/// `src/app/core/maths.ts`, one to one.
///
/// Maths is drawn by a pattern, not the parser, which makes no node for it (the web's editor/extended.ts sets it as
/// code). The first pattern paired any two dollars on a line, so every line with two prices in it drew as maths: "It
/// costs $5, or $6 with tax." set `$5, or $` in code, and a note of costs was half code. Pandoc's rule tells the two
/// apart by what touches the dollar sign: an opening `$` has a character that is not a space straight after it, a
/// closing `$` has one straight before it and no digit after it, and a `$` after a backslash is a dollar and never
/// maths. So `$x^2$` and `where $n$ is 3` are maths, and `$200 and $45` is two prices.
///
/// Here, pure and importing nothing, because two readers need the same answer: the editor, which draws it, and the
/// blanks' reader away from the editor (blanks_syntax.dart), which must not find a blank inside maths the editor
/// would not draw as one (docs/DESIGN.md §145).
///
/// What differs: the name. The web's `MATHS` is [mathsPattern] here, and a Dart `RegExp` carries no `lastIndex`, so
/// there is nothing to reset after a loop over it.
library;

/// Display maths, `$$…$$`, or inline maths by Pandoc's rule (`MATHS`).
final RegExp mathsPattern = RegExp(r'(?<!\\)\$\$[^$]+?(?<!\\)\$\$|(?<![\\$])\$(?=[^\s$])[^$\n]*?[^\s\\$]\$(?![\d$])');

/// Every stretch of maths in [text], as offsets from [offset].
List<({int from, int to})> mathsIn(String text, [int offset = 0]) =>
    [for (final match in mathsPattern.allMatches(text)) (from: offset + match.start, to: offset + match.end)];
