import TurndownService from 'turndown';
import { strikethrough } from '@joplin/turndown-plugin-gfm';
import { escapeText } from './escape.ts';
import { MOST_PICTURES, PICTURE_SCHEME } from './kinds.ts';

export { escapeText, MOST_PICTURES, PICTURE_SCHEME };

/**
 * A page's HTML as the Markdown a note is written in (Ghost.md's notes are plain Markdown, docs/MARKDOWN.md): Turndown,
 * with the GFM plugin's strikethrough, and rules of the clipper's own for the rest of GFM, because the app reads the
 * note's words as they are written and shows its marks as it meets them.
 *
 * - **Tables** are always a GFM table. The plugin keeps a table with code or a list in a cell as HTML, which Ghost.md
 *   shows as raw tags; here a cell's words are put on one line instead, and a table with no heading row takes its
 *   first row as the heading, since Markdown has no table without one. A table of tables is a page's layout, not data,
 *   and its cells are read as the words they hold.
 * - **Code** is a fenced block with its language, read from the class a highlighter leaves (`language-js`,
 *   `lang-js`, `highlight-source-js`, `brush: js`) or `data-lang`, whether the block is `pre > code` or a bare `pre`.
 * - **Task lists**: a list item's checkbox is `- [ ]` or `- [x]`. It is marked in the page's copy before anything
 *   else reads it (`markTasks`), because Readability takes every input out of an article, and the plugin's rule met
 *   only the inputs that were left.
 * - **Pictures** are not written with their addresses: each becomes `![alt](ghost-clip:picture/<n>)` and is listed in
 *   `pictures`, so the saving can store it as the app stores a picture (`image/<name>`) or link it where it could not.
 * - **Escaping** is only what would change the meaning in Ghost.md: Turndown escapes every `_` and `[`, which reads
 *   `snake\_case` in an editor that shows the Markdown as written. Here a `[[` (a note link), a `](` (a link), a
 *   blank's `{?` (core/blanks.ts) and a pair of dollars the app would draw as maths (core/maths.ts) are escaped,
 *   with the line-start marks Turndown escapes.
 */

export interface PictureRef {
  /** Where the picture is: an absolute http(s) address, or a `data:` one the page carried inline. */
  url: string;
  alt: string;
}

export interface Converted {
  markdown: string;
  pictures: PictureRef[];
}

/** What a list item's checkbox is turned into in the copy, until its item is written: `[x]` or `[ ]`. */
const TASK = (done: boolean) => `\u2063ghost-task:${done ? 'x' : ' '}\u2063`;
const TASK_MARK = /^\s*\u2063ghost-task:(x| )\u2063\s*/;

/**
 * Every checkbox of a list item in `root`, a copy of the page, as words that say whether it was ticked. A ticked box
 * is its `checked` (what the person or the page set) or its attribute (what a copy keeps of it).
 */
export function markTasks(root: ParentNode): void {
  for (const box of Array.from(root.querySelectorAll('input[type="checkbox"], [role="checkbox"]'))) {
    if (!box.closest('li')) continue;
    const done = box.nodeName === 'INPUT' ? (box as HTMLInputElement).checked || box.hasAttribute('checked') : box.getAttribute('aria-checked') === 'true';
    box.replaceWith((box.ownerDocument ?? document).createTextNode(TASK(done)));
  }
}

/** Elements that are never a note's words. */
const DROPPED = ['script', 'style', 'noscript', 'template', 'iframe', 'object', 'embed', 'canvas', 'svg', 'button', 'select', 'textarea', 'link', 'meta', 'dialog'];

/** A highlighter's class for a block's language. */
const LANGUAGE = [/(?:^|\s)(?:language|lang)-([A-Za-z0-9_+#-]+)/, /(?:^|\s)highlight-(?:source|text)-([A-Za-z0-9_+#-]+)/, /brush:\s*([A-Za-z0-9_+#-]+)/];

/** A lazy-loading page's stand-in picture: a tiny GIF or SVG data address, or a file called blank/placeholder/spacer. */
function isPlaceholder(src: string): boolean {
  if (!src.trim()) return true;
  if (/^data:image\/(gif|svg)/i.test(src) && src.length < 600) return true;
  return /(?:^|\/)(?:blank|placeholder|spacer|pixel|transparent)\.(?:gif|png|svg)(?:$|\?)/i.test(src);
}

/** The largest candidate of a `srcset`, by its width, or its density. */
function largestOf(srcset: string): string | null {
  let best: { url: string; size: number } | null = null;
  for (const part of srcset.split(/,\s+(?=\S)/)) {
    const [url, size = '1x'] = part.trim().split(/\s+/);
    if (!url) continue;
    const n = Number.parseFloat(size) * (size.endsWith('w') ? 1 : 1000);
    if (!best || n > best.size) best = { url, size: Number.isFinite(n) ? n : 0 };
  }
  return best?.url ?? null;
}

/** Where a picture really is, as an absolute address: its source, unless that is a lazy page's stand-in. */
export function pictureSource(img: Element, base: string): string | null {
  const candidates = [
    img.getAttribute('src') ?? '',
    img.getAttribute('data-src') ?? '',
    img.getAttribute('data-original') ?? '',
    img.getAttribute('data-lazy-src') ?? '',
    largestOf(img.getAttribute('data-srcset') ?? '') ?? '',
    largestOf(img.getAttribute('srcset') ?? '') ?? '',
  ];
  // A <picture>'s sources, for an <img> whose own source is a stand-in.
  const picture = img.parentElement?.nodeName === 'PICTURE' ? img.parentElement : null;
  for (const source of picture ? Array.from(picture.querySelectorAll('source')) : []) candidates.push(largestOf(source.getAttribute('srcset') ?? '') ?? '');
  const found = candidates.find((c) => c && !isPlaceholder(c));
  if (!found) return null;
  if (found.startsWith('data:')) return /^data:image\//i.test(found) ? found : null;
  try {
    const url = new URL(found, base);
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.href : null;
  } catch {
    return null;
  }
}

/** A tracking pixel or a spacer: said to be at most a few pixels across. */
function isSpeck(img: Element): boolean {
  const w = Number(img.getAttribute('width'));
  const h = Number(img.getAttribute('height'));
  return (w > 0 && w <= 3) || (h > 0 && h <= 3);
}

/** An address as a Markdown destination: spaces, brackets and angle brackets escaped by their percent codes. */
function destination(href: string): string {
  return href.replace(/[ ()<>]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0')}`);
}

/** A cell's words on one line, with its own bars escaped. */
function cellText(content: string): string {
  const lines = content
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
  // A list in a cell is its items in a row.
  const items = lines.every((line) => /^(?:[-*+]|\d+[.)])\s/.test(line));
  return (items ? lines.map((line) => line.replace(/^(?:[-*+]|\d+[.)])\s+/, '')).join('; ') : lines.join(' '))
    .replace(/(?<!\\)\|/g, '\\|');
}

function closestTable(node: Node): HTMLTableElement | null {
  for (let at: Node | null = node.parentNode; at; at = at.parentNode) if (at.nodeName === 'TABLE') return at as HTMLTableElement;
  return null;
}

/** A table of tables is a page's layout: its cells are read as the words they hold. */
function isLayout(table: HTMLTableElement | null): boolean {
  if (!table) return true;
  if (table.querySelector('table')) return true;
  const rows = Array.from(table.rows ?? []);
  if (!rows.length) return true;
  return rows.length === 1 && rows[0]!.cells.length <= 1;
}

/** How many columns a row spans, counting its cells' colspans. */
function spanOf(row: HTMLTableRowElement): number {
  return Array.from(row.cells).reduce((sum, cell) => sum + Math.max(1, Number(cell.getAttribute('colspan')) || 1), 0);
}

/** The heading row's rule, each column aligned as its heading cell says (`align`, or `text-align`). */
function rule(row: HTMLTableRowElement, columns: number): string {
  const aligns: string[] = [];
  for (const cell of Array.from(row.cells)) {
    const said = (cell.getAttribute('align') ?? (cell as HTMLElement).style?.textAlign ?? '').toLowerCase();
    for (let n = 0; n < Math.max(1, Number(cell.getAttribute('colspan')) || 1); n += 1) aligns.push(said);
  }
  let out = '';
  for (let n = 0; n < columns; n += 1) {
    const align = aligns[n] ?? '';
    out += align === 'right' ? ' ---: |' : align === 'center' ? ' :---: |' : align === 'left' ? ' :--- |' : ' --- |';
  }
  return out;
}

function inCell(node: Node): boolean {
  for (let at: Node | null = node.parentNode; at; at = at.parentNode) if (at.nodeName === 'TD' || at.nodeName === 'TH') return !isLayout(closestTable(at));
  return false;
}

function languageOf(node: Element): string {
  const code = node.nodeName === 'PRE' ? node.querySelector('code') : node;
  for (const el of [node, code, node.parentElement]) {
    if (!el) continue;
    const said = el.getAttribute('data-lang') ?? el.getAttribute('data-language');
    if (said && /^[A-Za-z0-9_+#-]+$/.test(said)) return said.toLowerCase();
    const cls = el.getAttribute('class') ?? '';
    for (const pattern of LANGUAGE) {
      const found = pattern.exec(cls);
      if (found) return found[1]!.toLowerCase();
    }
  }
  return '';
}

/** Takes from a copy what is never a note's words, and makes its links and pictures absolute. */
function prepare(root: Element | DocumentFragment, base: string): void {
  markTasks(root);
  for (const el of Array.from(root.querySelectorAll(DROPPED.join(',')))) el.remove();
  for (const el of Array.from(root.querySelectorAll('[hidden], [aria-hidden="true"]'))) {
    // An icon hidden from a screen reader is decoration; a picture inside one is still the page's.
    if (!el.querySelector('img')) el.remove();
  }
  for (const input of Array.from(root.querySelectorAll('input'))) if (input.getAttribute('type') !== 'checkbox') input.remove();
  for (const a of Array.from(root.querySelectorAll('a[href]'))) {
    const href = a.getAttribute('href') ?? '';
    let url: URL | null = null;
    try {
      url = new URL(href, base);
    } catch {
      url = null;
    }
    if (!url || !/^(https?|mailto):$/.test(url.protocol) || href.startsWith('#')) a.removeAttribute('href');
    else a.setAttribute('href', url.href);
  }
}

function service(pictures: PictureRef[], base: string): TurndownService {
  const td = new TurndownService({
    headingStyle: 'atx',
    hr: '---',
    bulletListMarker: '-',
    codeBlockStyle: 'fenced',
    fence: '```',
    emDelimiter: '*',
    strongDelimiter: '**',
    linkStyle: 'inlined',
  });
  td.use([strikethrough]);
  td.escape = escapeText;

  // Rules added later are tried first (Turndown's `addRule` puts a rule at the front), so these win over the plugin's.
  td.addRule('ghostListItem', {
    filter: 'li',
    replacement(content, node, options) {
      const parent = node.parentNode as Element | null;
      let prefix = `${options.bulletListMarker} `;
      if (parent?.nodeName === 'OL') {
        const start = Number(parent.getAttribute('start') ?? 1) || 1;
        prefix = `${start + Array.prototype.indexOf.call(parent.children, node)}. `;
      }
      const paragraph = /\n$/.test(content);
      const body = content.replace(/^\n+/, '').replace(/\n+$/, '').replace(TASK_MARK, (_m, box: string) => `[${box}] `) + (paragraph ? '\n' : '');
      return prefix + body.replace(/\n/g, `\n${' '.repeat(prefix.length)}`) + (node.nextSibling ? '\n' : '');
    },
  });

  td.addRule('ghostTableCell', {
    filter: ['th', 'td'],
    replacement(content, node) {
      if (isLayout(closestTable(node))) return `\n\n${content}\n\n`;
      const span = Math.max(1, Number((node as Element).getAttribute('colspan')) || 1);
      const first = (node as Element).parentElement?.firstElementChild === node;
      return `${first ? '|' : ''} ${cellText(content)} |${' |'.repeat(span - 1)}`;
    },
  });
  td.addRule('ghostTableRow', {
    filter: 'tr',
    replacement(content, node) {
      const table = closestTable(node);
      if (isLayout(table)) return content;
      const row = node as HTMLTableRowElement;
      const columns = Math.max(...Array.from(table!.rows).map(spanOf));
      const missing = columns - spanOf(row);
      const line = `${content || '|'}${' |'.repeat(Math.max(0, missing))}`;
      // The first row is the heading, whatever its cells are: Markdown has no table without one.
      const heading = table!.rows[0] === row;
      return `\n${line}${heading ? `\n|${rule(row, columns)}` : ''}`;
    },
  });
  td.addRule('ghostTableSection', { filter: ['thead', 'tbody', 'tfoot'], replacement: (content) => content });
  td.addRule('ghostTableCaption', { filter: ['caption', 'colgroup', 'col'], replacement: () => '' });
  td.addRule('ghostTable', {
    filter: 'table',
    replacement(content, node) {
      const table = node as HTMLTableElement;
      if (isLayout(table)) return `\n\n${content}\n\n`;
      const caption = table.querySelector('caption')?.textContent?.trim();
      const rows = content.replace(/\n+/g, '\n').trim();
      return `\n\n${caption ? `**${escapeText(caption)}**\n\n` : ''}${rows}\n\n`;
    },
  });

  td.addRule('ghostCode', {
    filter: (node) => node.nodeName === 'PRE',
    replacement(_content, node) {
      const text = (node.textContent ?? '').replace(/\n$/, '');
      if (inCell(node)) return ` \`${text.replace(/\s+/g, ' ').replace(/`/g, "'")}\` `;
      const language = languageOf(node as Element);
      let fence = '```';
      while (text.includes(fence)) fence += '`';
      return `\n\n${fence}${language}\n${text}\n${fence}\n\n`;
    },
  });

  td.addRule('ghostPicture', {
    filter: 'img',
    replacement(_content, node) {
      const img = node as Element;
      if (isSpeck(img)) return '';
      const src = pictureSource(img, base);
      if (!src) return '';
      const alt = (img.getAttribute('alt') ?? img.getAttribute('title') ?? '').replace(/\s+/g, ' ').replace(/[[\]]/g, '').trim();
      const known = pictures.findIndex((p) => p.url === src);
      const n = known >= 0 ? known : pictures.push({ url: src, alt }) - 1;
      return `![${alt}](${PICTURE_SCHEME}${n})`;
    },
  });

  td.addRule('ghostLink', {
    filter: (node) => node.nodeName === 'A' && Boolean((node as Element).getAttribute('href')),
    replacement(content, node) {
      const href = (node as Element).getAttribute('href') ?? '';
      const words = content.trim();
      if (!words) return '';
      // A link round a block (a card whose whole body is the link) keeps the block and the link goes after it.
      if (/\n/.test(words) && !/^!\[[^\]]*\]\([^)]*\)$/.test(words)) return `${content}\n\n[${escapeText(new URL(href).hostname || href)}](${destination(href)})`;
      return `[${words}](${destination(href)})`;
    },
  });
  return td;
}

/** Lines tidied after Turndown: no run of blank lines, no trailing spaces but a hard break's, one newline at the end. */
function tidy(markdown: string): string {
  return `${markdown
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t]+$/gm, (spaces) => (spaces === '  ' ? spaces : ''))
    .replace(/\n{3,}/g, '\n\n')
    .trim()}\n`;
}

/** The first line said again as a heading of the same title: the article's own title, which the note already has. */
function withoutTitle(markdown: string, title: string | undefined): string {
  if (!title) return markdown;
  const key = (s: string) => s.replace(/[*_`\\]/g, '').replace(/\s+/g, ' ').trim().toLowerCase();
  const lines = markdown.split('\n');
  const first = lines.findIndex((l) => l.trim());
  if (first >= 0 && /^#{1,2}\s/.test(lines[first]!) && key(lines[first]!.replace(/^#+\s*/, '')) === key(title)) lines.splice(first, 1);
  return lines.join('\n');
}

/**
 * HTML as Markdown: `root` is an element or fragment (it is changed, so pass a copy) or HTML text, `base` the page's
 * address that its relative links and pictures are read against, and `title` the note's own, which a first heading
 * that only says it again is dropped for.
 */
export function toMarkdown(root: Element | DocumentFragment | string, { base, title, doc }: { base: string; title?: string; doc?: Document }): Converted {
  let node: Element | DocumentFragment;
  if (typeof root === 'string') {
    const parsed = (doc?.implementation ?? document.implementation).createHTMLDocument('');
    parsed.body.innerHTML = root;
    node = parsed.body;
  } else node = root;
  prepare(node, base);
  const pictures: PictureRef[] = [];
  const markdown = service(pictures, base).turndown(node as unknown as HTMLElement);
  return { markdown: tidy(withoutTitle(tidy(markdown), title)), pictures };
}
