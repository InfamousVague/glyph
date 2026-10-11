/**
 * Maths in a note's words: `$x^2$` inline and `$$a + b$$` on a line, found the way Pandoc finds them.
 *
 * Maths is drawn by a pattern, not the parser, which makes no node for it (editor/extended.ts sets it as code). The
 * first pattern paired any two dollars on a line, so every line with two prices in it drew as maths: "It costs $5, or
 * $6 with tax." set `$5, or $` in code, and a note of costs was half code. Pandoc's rule tells the two apart by what
 * touches the dollar sign: an opening `$` has a character that is not a space straight after it, a closing `$` has one
 * straight before it and no digit after it, and a `$` after a backslash is a dollar and never maths. So `$x^2$` and
 * `where $n$ is 3` are maths, and `$200 and $45` is two prices.
 *
 * Here, pure and importing nothing, because two readers need the same answer: the editor, which draws it, and the
 * blanks' reader away from the editor (core/blanks.ts), which must not find a blank inside maths the editor would not
 * draw as one (docs/DESIGN.md §145).
 */

/** Display maths, `$$…$$`, or inline maths by Pandoc's rule. Global: reset `lastIndex` after a loop, or use `mathsIn`. */
export const MATHS = /(?<!\\)\$\$[^$]+?(?<!\\)\$\$|(?<![\\$])\$(?=[^\s$])[^$\n]*?[^\s\\$]\$(?![\d$])/g;

/** Every stretch of maths in `text`, as offsets from `offset`. */
export function mathsIn(text: string, offset = 0): { from: number; to: number }[] {
  const found: { from: number; to: number }[] = [];
  const pattern = new RegExp(MATHS.source, 'g');
  for (let match = pattern.exec(text); match; match = pattern.exec(text)) {
    found.push({ from: offset + match.index, to: offset + match.index + match[0].length });
  }
  return found;
}
