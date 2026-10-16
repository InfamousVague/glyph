import { BLANK } from '../../../tauri/src/app/core/blanks.ts';
import { MATHS } from '../../../tauri/src/app/core/maths.ts';

/**
 * Plain words from a page, escaped only where Ghost.md would read a mark in them (core/markdown.ts says why not
 * Turndown's own escaping): emphasis, code, a note link's `[[`, a link's `](`, strikethrough, a tag-like `<`, a
 * blank's `{?` (core/blanks.ts, the app's own pattern) and maths by the app's own rule (core/maths.ts), and the marks
 * a line may open with.
 */

/** Every ASCII punctuation character, which a backslash before escapes in CommonMark. */
const PUNCTUATION = /[!-/:-@[-`{-~]/;

export function escapeText(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i]!;
    // A backslash that would escape what follows it is written as two.
    out += c === '\\' && PUNCTUATION.test(text[i + 1] ?? '') ? '\\\\' : c;
  }
  out = out
    .replace(/\*/g, '\\*')
    .replace(/`/g, '\\`')
    // An underscore at a word's edge can open emphasis; one inside a word (snake_case) never does.
    .replace(/(^|[^\p{L}\p{N}])_|_(?=[^\p{L}\p{N}]|$)/gu, (m) => m.replace('_', '\\_'))
    .replace(/\[\[/g, '\\[\\[')
    .replace(/\](?=[([:])/g, '\\]')
    .replace(/~~/g, '\\~\\~')
    .replace(/<(?=[A-Za-z/!?])/g, '\\<')
    .replace(new RegExp(BLANK.source, 'g'), (m) => `\\${m}`)
    .replace(new RegExp(MATHS.source, 'g'), (m) => m.replace(/\$/g, '\\$'));
  // What a line may open with: a list's marker, a heading, a quote, a fence, a setext rule, a task's box.
  return out
    .replace(/^-(?=\s|$)/, '\\-')
    .replace(/^\+ /, '\\+ ')
    .replace(/^(=+)/, '\\$1')
    .replace(/^(#{1,6})(?=\s|$)/, '\\$1')
    .replace(/^>/, '\\>')
    .replace(/^(\d+)([.)]) /, '$1\\$2 ')
    .replace(/^~~~/, '\\~~~')
    .replace(/^\[( |x|X)\]/, '\\[$1]');
}

