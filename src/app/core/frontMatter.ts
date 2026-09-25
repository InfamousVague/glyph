/**
 * A note's front matter: what counts as it, one key read out of it, and one key written into it. This is the one
 * place the page decides where a note's front matter ends. The list's title (core/noteTitle.ts), the editor's quiet
 * keys (editor/extended.ts), a canvas's JSON (canvas/jsonCanvas.ts), a book's index (book/book.ts) and the MCP
 * server's titles all ask `frontMatterEnd`, so a note is never front matter to one of them and prose to another.
 *
 * The rule is the list's, as it has been since the list stopped calling such notes "---" (docs/MARKDOWN.md): a
 * fence on the first line, then lines that are each a `key:` or blank, then a fence that closes it within the first
 * 40 lines. A note that opens with a rule and some words is a note that opens with a rule. Until 2026-09-25 this
 * was answered three ways: the list and the editor held to this rule; a canvas and the MCP server's copy of the
 * list's title capped the search at 40 lines but took any line inside; and the key readers and writers here and the
 * book's index took any closing fence however far down. So `book: true` was read out of a block the list showed as
 * words, and the MCP server named a note by a line the app never showed. The files on disk have front matter of
 * their own, which Rust reads and takes off before the page sees a body (src-tauri/src/library/frontmatter.rs);
 * this is the block the page writes into that body.
 *
 * Writing keeps every other key as it was: the `title:` a canvas or a book is named by (docs/CANVAS.md,
 * docs/BOOKS.md), since neither has a first line to rename it in, and the `authors:` a note written with an AI
 * carries (core/authors.ts).
 */

/** A front matter fence, `---` or `+++`, on a line of its own. */
export const FENCE = /^(---|\+\+\+)\s*$/;

/**
 * The most lines front matter may take, both fences included: a `---` further down is a rule in a long note, not the
 * end of its keys. A reader that has the note as something other than lines (editor/extended.ts) reads this many.
 */
export const FRONT_MATTER_LINES = 40;

/** A line front matter may hold, besides a blank one: a `key:`. */
const KEY_LINE = /^\s*[\w.-]+\s*:/;

/**
 * Where a note's front matter ends: the index of the first line after its closing fence, or 0 where it has none -
 * no fence on the first line, a line of words before the close, or no close within the first 40 lines. So
 * `lines.slice(frontMatterEnd(lines))` is always the note's words, and the keys are `lines.slice(1, end - 1)`.
 */
export function frontMatterEnd(lines: readonly string[]): number {
  if (!FENCE.test(lines[0] ?? '')) return 0;
  for (let n = 1; n < Math.min(lines.length, FRONT_MATTER_LINES); n += 1) {
    const line = lines[n] ?? '';
    if (FENCE.test(line)) return n + 1;
    if (!KEY_LINE.test(line) && line.trim() !== '') return 0;
  }
  return 0;
}

/** The start of `key`'s line, as a pattern: any case, however it is spaced, up to its colon. */
function keyStart(key: string): string {
  return `^\\s*${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*:`;
}

/**
 * One key's value from the front matter, its quotes taken off, or null where there is no front matter or no such
 * key. A book note says `book: true` (book/book.ts); a canvas note is named by `title:`.
 */
export function frontMatterValue(body: string, key: string): string | null {
  const lines = body.split('\n');
  const end = frontMatterEnd(lines);
  if (!end) return null;
  const pattern = new RegExp(`${keyStart(key)}\\s*(.*?)\\s*$`, 'i');
  for (const line of lines.slice(1, end - 1)) {
    const m = pattern.exec(line);
    if (m) return (m[1] ?? '').replace(/^(["'])(.*)\1$/, '$2');
  }
  return null;
}

/**
 * A title as a front matter value: quoted, so a colon or a hash in it stays part of the name, with a quote or a line
 * break in it made a single quote, and `fallback` where nothing is left. A new canvas or book note is written with
 * one (canvas/jsonCanvas.ts, book/book.ts), and so is a rename.
 */
export function quotedTitle(title: string, fallback: string): string {
  return `"${title.replace(/["\n]/g, "'").trim() || fallback}"`;
}

/**
 * The body with its `title:` set to `title`: the key replaced where the front matter has one, added first where it
 * has not, and front matter made where there was none. Everything else - other keys, the words - is untouched. An
 * empty title takes the key off, and takes front matter that held nothing else off with it.
 */
export function withFrontMatterTitle(body: string, title: string): string {
  const clean = title.trim();
  const lines = body.split('\n');
  const end = frontMatterEnd(lines);
  if (!end) return clean ? `---\ntitle: ${quotedTitle(clean, clean)}\n---\n${body}` : body;
  const keys = lines.slice(1, end - 1).filter((key) => !/^\s*title\s*:/i.test(key));
  if (clean) keys.unshift(`title: ${quotedTitle(clean, clean)}`);
  const rest = lines.slice(end);
  if (!keys.length) return rest.join('\n');
  return [lines[0], ...keys, lines[end - 1], ...rest].join('\n');
}

/**
 * The body with front matter `key` set to `value` as it is written (no quoting added): replaced where the key is, added
 * last where it isn't, and front matter made where there was none. A null value takes the key off, and front matter
 * that held nothing else with it. The words are untouched.
 */
export function withFrontMatterValue(body: string, key: string, value: string | null): string {
  const lines = body.split('\n');
  const pattern = new RegExp(keyStart(key), 'i');
  const line = value === null ? null : `${key}: ${value.replace(/\n/g, ' ').trim()}`;
  const end = frontMatterEnd(lines);
  if (!end) return line ? `---\n${line}\n---\n${body}` : body;
  const keys = lines.slice(1, end - 1);
  const at = keys.findIndex((k) => pattern.test(k));
  if (at >= 0) {
    if (line) keys[at] = line;
    else keys.splice(at, 1);
  } else if (line) {
    keys.push(line);
  }
  const rest = lines.slice(end);
  if (!keys.length) return rest.join('\n');
  return [lines[0], ...keys, lines[end - 1], ...rest].join('\n');
}
