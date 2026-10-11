import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import type { LanguageDescription } from '@codemirror/language';
import { languages } from '@codemirror/language-data';
import type { Extension } from '@codemirror/state';
import { tags } from '@lezer/highlight';
import type { MarkdownConfig } from '@lezer/markdown';
import type { InlineFormat } from '../plugins/types.ts';

/**
 * The markdown the editor speaks: GFM, with one CommonMark rule taken out,
 * and whatever inline formattings the switched-on plugins add.
 *
 * In CommonMark a line of dashes or equals signs under a paragraph turns the
 * paragraph into a heading (a "setext" heading). On a phone that rule bites:
 * typing `-` to start a list under a line promoted the line above it, and the
 * person was "stuck in headings". Here `#` is the only way to make a heading;
 * a lone `-` is an empty list item and `---` is a rule. Kept in its own module
 * so the parser can be tested without a view.
 *
 * A fenced block with a language after its backticks (```js) is parsed by
 * that language, loaded when first met from the CodeMirror language pack, so
 * its keywords, strings and comments are highlighted (glyphHighlight.ts);
 * a fence with no language, or one the pack doesn't know, is plain
 * monospace. `codeLanguages` is a parameter so a test can hand in a
 * language already loaded.
 *
 * A plugin's formatting (plugins/types.ts `InlineFormat`) is a delimiter run
 * that opens and closes a node, parsed the way GFM's `~~` is: the Spoiler
 * plugin's `||secret||` becomes a `Spoiler` node holding two `SpoilerMark`s
 * and the words. The marks take the dimmed marker style every delimiter has
 * (glyphHighlight.ts); the words are drawn by the look plugins
 * (formatLooks.ts, wispFormat.ts), not by the highlighter, so a plugin's
 * look needs no CSS of its own.
 */
export function glyphMarkdown(formats: readonly InlineFormat[] = [], codeLanguages: readonly LanguageDescription[] = languages): Extension {
  return markdown({
    // GFM: the default `commonmarkLanguage` has no strikethrough and no task
    // lists, both of which a notes app wants.
    base: markdownLanguage,
    extensions: [{ remove: ['SetextHeading'] }, ...formats.map(inlineFormat)],
    codeLanguages,
    // Enter continues a list, Backspace removes a marker whole. The most
    // useful phone behaviour in the package.
    addKeymap: true,
    // No autocomplete popup over a phone keyboard when a `<` is typed.
    completeHTMLTags: false,
    pasteURLAsLink: true,
  });
}

/** The characters CommonMark counts as punctuation when deciding whether a delimiter opens or closes. */
const PUNCTUATION = /[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~\xA1\u2010-\u2027]/;

/**
 * What a delimiter is a run of: the shortest piece it repeats. `||` is a run of `|`, and `🔥🔥` a run of `🔥`, which is
 * two UTF-16 code units (and `❄️❄️` a run of `❄️`, a character and its variation selector). The parser counts in code
 * units, as CodeMirror's positions do, so the piece is kept as a string and compared whole rather than as one code.
 */
export function delimiterUnit(delimiter: string): string {
  for (let size = 1; size <= delimiter.length / 2; size += 1) {
    if (delimiter.length % size !== 0) continue;
    const unit = delimiter.slice(0, size);
    if (unit.repeat(delimiter.length / size) === delimiter) return unit;
  }
  return delimiter;
}

/**
 * The parser's piece for one plugin formatting: `delimiter` opens and closes
 * a `name` node, with the flanking rules GFM's strikethrough uses, so a run
 * next to a space can only open on its far side and only close on its near
 * one. A longer run of the same character is not this formatting.
 *
 * The delimiter is a run of one piece (`delimiterUnit`): a character, as `||` is, or an emoji, as the effects' `🔥🔥`
 * is (plugins/marks, editor/textEffects.ts). A longer run of the piece is not this formatting either way, so three
 * flames are three flames.
 */
function inlineFormat({ name, delimiter }: Pick<InlineFormat, 'name' | 'delimiter'>): MarkdownConfig {
  const mark = `${name}Mark`;
  const type = { resolve: name, mark };
  const unit = delimiterUnit(delimiter);
  const code = delimiter.charCodeAt(0);
  const length = delimiter.length;
  return {
    defineNodes: [{ name }, { name: mark, style: tags.processingInstruction }],
    parseInline: [
      {
        name,
        parse(cx, next, pos) {
          if (next !== code) return -1;
          if (cx.slice(pos, pos + length) !== delimiter) return -1;
          // A longer run of the piece, either side, is not this formatting.
          if (cx.slice(pos + length, pos + length + unit.length) === unit || (pos - unit.length >= cx.offset && cx.slice(pos - unit.length, pos) === unit)) return -1;
          const before = cx.slice(pos - 1, pos);
          const after = cx.slice(pos + length, pos + length + 1);
          const spaceBefore = /\s|^$/.test(before);
          const spaceAfter = /\s|^$/.test(after);
          const punctBefore = PUNCTUATION.test(before);
          const punctAfter = PUNCTUATION.test(after);
          return cx.addDelimiter(
            type,
            pos,
            pos + length,
            !spaceAfter && (!punctAfter || spaceBefore || punctBefore),
            !spaceBefore && (!punctBefore || spaceAfter || punctAfter),
          );
        },
        after: 'Emphasis',
      },
    ],
  };
}

