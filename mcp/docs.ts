import { chaptersOf, isBookBody } from '../tauri/src/app/book/book.ts';
import { frontMatterEnd, frontMatterValue, quotedTitle, withFrontMatterValue } from '../tauri/src/app/core/frontMatter.ts';
import { noteTitle } from '../tauri/src/app/core/noteTitle.ts';
import { yamlValue } from '../tauri/src/app/core/properties.ts';
import { sameTitle, titleKey } from '../tauri/src/app/core/titleKey.ts';

/**
 * Docs on Ghost.md, for the connector (Matt, 2026-10-31: "There should be a specific type of notebook for docs that we
 * made, add it to the Claude and other AI connector so they can make docs on ghost expose it in the MCP and then add
 * instructions for AI to know how to use it"). The app's lib/core/docs_book.dart, written again in this one's
 * TypeScript, line for line, so a page added here lands in the index as the app adds one:
 *
 * A notebook (`book: true`) whose front matter also says `type: docs`. Its index is its title heading, a line about
 * it, and parts: each a `## ` heading with its pages numbered under it, straight through the book ("1. [[Welcome]]").
 * A page is a plain note named by its `# ` heading, which may carry an `icon:`. `type:` is the key that already says
 * what a note is (`ticket`, `teamspace`, `cycle`, `milestone`), each reader asking for its own word only; `docs:` is
 * a teamspace home's read-or-edit setting, so it is not this.
 *
 * And the words the AI is told: `DOCS_INSTRUCTIONS`, the paragraph in the server's instructions, and `DOCS_GUIDE`,
 * the fuller guide the `ghost-docs-guide` prompt and resource carry.
 */

/** The `type:` docs say. */
export const DOCS_TYPE = 'docs';

/** Whether a note is docs: `book: true` and `type: docs`, in any case. */
export function isDocsBody(body: string): boolean {
  return isBookBody(body) && frontMatterValue(body, 'type')?.trim().toLowerCase() === DOCS_TYPE;
}

/** A part of docs: its heading's words and its pages' titles. Read from an index, `line` is the heading's (-1 for none). */
export interface DocsPart {
  title: string;
  pages: string[];
  line?: number;
}

const PART = /^##\s+(.+?)(?:\s+#+)?\s*$/;

/**
 * The parts of a docs index, in order, each with its pages: every `## ` heading after the front matter is a part, one
 * with no pages yet too. Pages before the first heading are a part with no title, there only where there are some.
 */
export function docsParts(body: string): DocsPart[] {
  const lines = body.split('\n');
  const chapters = chaptersOf(body);
  const parts: DocsPart[] = [];
  const loose: string[] = [];
  let next = 0;
  const take = (before: number) => {
    while (next < chapters.length && chapters[next]!.line < before) {
      (parts.length ? parts[parts.length - 1]!.pages : loose).push(chapters[next]!.title);
      next += 1;
    }
  };
  for (let n = frontMatterEnd(lines); n < lines.length; n += 1) {
    take(n);
    const heading = PART.exec(lines[n]!);
    if (heading) parts.push({ title: heading[1]!.trim(), pages: [], line: n });
  }
  take(Infinity);
  return [...(loose.length ? [{ title: '', pages: loose, line: -1 }] : []), ...parts];
}

/** The body of new docs: their name, `about` under the heading, then each part with its pages numbered straight through. */
export function docsBookBody(title: string, options: { about?: string; parts?: readonly { title: string; pages: readonly string[] }[] } = {}): string {
  const named = quotedTitle(title, 'Docs');
  const out = ['---', `title: ${named}`, 'book: true', `type: ${DOCS_TYPE}`, '---', `# ${named.slice(1, -1)}`, ''];
  const said = options.about?.trim() ?? '';
  if (said) out.push(said, '');
  let number = 0;
  for (const part of options.parts ?? []) {
    const heading = part.title.trim();
    if (heading) out.push(`## ${heading}`, '');
    for (const page of part.pages) out.push(`${(number += 1)}. [[${page.trim()}]]`);
    if (part.pages.length) out.push('');
  }
  return out.join('\n');
}

const NUMBERED = /^(\s*)(\d+)([.)])/;

/**
 * The index with the page `page` added to the part `part` (matched as a title is): last in it, or `position`th (from 1).
 * A part the index has not got is made at the end. A page already in the index is left where it is. The numbered pages
 * are numbered again straight through; an index of bullets stays bullets.
 */
export function withDocsPage(body: string, part: string, page: string, position?: number): string {
  const title = page.trim();
  const heading = part.trim();
  const chapters = chaptersOf(body);
  if (!title || chapters.some((c) => sameTitle(c.title, title))) return body;
  const lines = body.split('\n');
  const numbers = !chapters.length || chapters.some((c) => NUMBERED.test(lines[c.line]!));
  const item = `${numbers ? '1.' : '-'} [[${title}]]`;
  const found = docsParts(body).find((p) => (heading ? p.title !== '' && sameTitle(p.title, heading) : p.title === '' && p.pages.length > 0));
  if (!found) {
    while (lines.length && !lines[lines.length - 1]!.trim()) lines.pop();
    lines.push('', ...(heading ? [`## ${heading}`, ''] : []), item, '');
    return renumbered(lines.join('\n'));
  }
  const own = chapters.filter((c) => c.depth === 0 && found.pages.some((p) => sameTitle(p, c.title)));
  const at = position === undefined ? own.length : Math.min(Math.max(position - 1, 0), own.length);
  if (!own.length) {
    let where = found.line! + 1;
    lines.splice(where, 0, '');
    where += 1;
    lines.splice(where, 0, item);
    if (where + 1 < lines.length && lines[where + 1]!.trim()) lines.splice(where + 1, 0, '');
  } else if (at < own.length) {
    lines.splice(own[at]!.line, 0, item);
  } else {
    // After the last of the part's pages and any indented under it.
    const last = own[own.length - 1]!;
    const under = chapters.filter((c) => c.line > last.line && c.depth === 1 && !chapters.some((d) => d.depth === 0 && d.line > last.line && d.line < c.line));
    lines.splice((under.length ? under[under.length - 1]!.line : last.line) + 1, 0, item);
  }
  return renumbered(lines.join('\n'));
}

/** The top-level numbered pages numbered 1, 2, 3 in the order they stand. */
function renumbered(body: string): string {
  const lines = body.split('\n');
  let number = 0;
  for (const c of chaptersOf(body)) {
    if (c.depth !== 0) continue;
    const marker = NUMBERED.exec(lines[c.line]!);
    if (!marker) continue;
    number += 1;
    lines[c.line] = `${marker[1]}${number}${marker[3]}${lines[c.line]!.slice(marker[0].length)}`;
  }
  return lines.join('\n');
}

/** A page of docs: `title` as its `# ` heading (never twice), `words` under it, and its `icon:` where given. */
export function docsPageBody(title: string, words: string, icon?: string): string {
  const clean = title.trim();
  let said = words.trim();
  const first = said.split('\n')[0] ?? '';
  if (/^#\s+/.test(first) && sameTitle(noteTitle(first), clean)) said = said.slice(first.length).trim();
  const body = `# ${clean}\n${said ? `\n${said}\n` : ''}`;
  const mark = icon?.trim();
  return mark ? withFrontMatterValue(body, 'icon', yamlValue(mark)) : body;
}

/** What is wrong with a title a `[[link]]` must name, or null: a bracket, `|`, `#` or a line break cuts a link short. */
export function docsTitleProblem(title: string): string | null {
  const clean = title.trim();
  if (!clean) return 'A page needs a title.';
  if (clean.length > 120) return `“${clean.slice(0, 40)}…” is longer than a link can name: keep a title under 120 letters.`;
  if (/[[\]|#\n]/.test(clean)) return `“${clean}” has a [, ], |, # or a line break in it, which a [[link]] to it would cut short.`;
  return null;
}

/** Whether two titles are one, for the tools' checks. */
export function titlesClash(titles: readonly string[]): string | null {
  const seen = new Map<string, string>();
  for (const title of titles) {
    const key = titleKey(title);
    if (seen.has(key)) return title;
    seen.set(key, title);
  }
  return null;
}

/**
 * The paragraph of the server's instructions on docs: when to make them and how, in this connector's tools' names.
 * The app's own AI is told the same (lib/claude/claude_books.dart `claudeDocsSystem`).
 */
export const DOCS_INSTRUCTIONS =
  'Writing docs on Ghost.md: when the person asks for docs, a guide, a handbook, a manual or a wiki, make them with create_docs — a notebook marked as docs whose index is parts (`## ` headings) of numbered pages, each page a note of its own. One topic a page; parts group the pages a reader takes together; page titles short and unique in the account, since they are what [[links]] name. Open each page with a line saying what it is for, use `## ` headings inside it for its outline, and link the other pages as [[Their title]]. Grow docs with add_doc_page. Never hand-write `book:` or `type: docs` front matter with create_note, nor add a page by editing the index. Docs for a team go in the organization’s workspace or a folder in it (`workspace`). The fuller guide, with the markdown that works well in docs, is the ghost-docs-guide prompt and the ghost://guide/docs resource.';

/**
 * The paragraph of the server's instructions on Figma (Matt, 2026-11-02: "add a instruction to the Claude connector to
 * try to link figma frames with previews where possible"). A figma.com link alone on its line, or a list line that is
 * only the link, is drawn in the app as a card with its picture (lib/editor/media/link_cards.dart, the Rich embeds
 * and Figma plugins); with `node-id` it is the frame's own picture once the Figma plugin is connected.
 */
export const FIGMA_INSTRUCTIONS =
  'Figma frames: whenever a note is about a screen, a component, a flow or any design that lives in Figma, link the frame itself so Ghost.md shows its preview. Use the frame’s own address, https://www.figma.com/design/<file key>/<file name>?node-id=<node id> (the node-id names the frame; write it with a hyphen, 12-34, as Figma’s links do), rather than the whole file’s, and put each link on a line of its own — a bare link, or a list line that is only `- [Frame name](link)` — never in the middle of a sentence, since only a line that is just the link is drawn as a card with the picture. Say in a word above it what the frame is. Where Figma tools are connected, find the real node id of the frame you mean (from the file’s metadata or the link the person gave) instead of guessing; never make up a node-id or a file key, and when you know only the file, link the file. Several frames are several such lines, one frame each.';

/** The fuller guide: the `ghost-docs-guide` prompt and the `ghost://guide/docs` resource. */
export const DOCS_GUIDE = `# Writing docs on Ghost.md

Docs on Ghost.md are a notebook kept as documentation: an index of parts, each part a list of pages, every page a markdown note of its own. The public Ghost.md Docs (ghostmarkdown.com/docs) are made this way.

## The shape

The index is a note whose front matter says \`book: true\` and \`type: docs\`. Under its title heading comes a line or two on what the docs cover, then the parts:

\`\`\`
---
title: "Onboarding handbook"
book: true
type: docs
---
# Onboarding handbook

Everything a new person needs in their first month.

## Getting started

1. [[Welcome]]
2. [[Accounts and tools]]

## How we work

3. [[Shipping a change]]
\`\`\`

Pages are numbered straight through the book, not per part. Never write this by hand: create_docs makes the index and every page, and add_doc_page adds a page under its part and numbers it in.

## Tools

- **create_docs**: \`title\`, \`about\`, \`parts\` (each a \`title\` and its \`pages\`, each page a \`title\`, a \`body\` and an optional \`icon\` emoji), and \`workspace\` to make them in. Every title is checked first; nothing is made if one will not do.
- **add_doc_page**: \`docs\` (id or title), \`part\` (a part's heading; a new one is added at the end), \`title\`, \`body\`, \`icon\`, \`position\` (from 1 in its part; left out, last).
- **read_note** reads the index or a page; **update_note** changes a page's words. To rename a page, change its heading and its line in the index together.
- **list_notes** with \`query\` finds docs by name; a docs index's \`preview\` shows its first lines.

## Planning docs

- **One topic a page.** A page answers one question or covers one task. Split a page that needs two \`# \` titles.
- **Parts group pages a reader takes together**: Getting started, Guides, Reference, Troubleshooting. Three to seven pages a part reads well.
- **Titles are links.** A page is found by its title, so make it short, plain and unique in the whole account: "Install the app", not "Installation (Mac, Windows, phones) — read first". No \`[\`, \`]\`, \`|\` or \`#\` in a title.
- **Open each page with one sentence saying what it is for.** It is the page's summary in lists and search.
- **\`## \` headings inside a page are its outline**, drawn beside the words on a wide screen. Keep them short; \`###\` for a step inside a section.
- **Link instead of repeating**: \`[[Accounts and tools]]\`, \`[[Shipping a change#Review]]\` for a heading, \`[[Accounts and tools|your accounts]]\` for other words. A link to a page not written yet is drawn dashed: a place to write next.
- **Team docs** go in the organization's workspace, or a folder in it (list_workspaces), so every member has them. Personal docs need no workspace.

## Markdown that works well in docs

Plain CommonMark with GitHub's tables, task lists and strikethrough, plus:

- **Callouts**: a quote whose first line names its kind — NOTE, TIP, IMPORTANT, WARNING or CAUTION — with an optional heading after it:

  \`\`\`
  > [!WARNING] Before you deploy
  > Merge main first.
  \`\`\`

- **Code**: three backticks above and below, the language named after the first three (bash, ts, json): coloured in over a hundred languages.
- **Tables**: pipes between cells and a row of dashes under the first. Good for settings, keys and comparisons.
- **Diagrams**: a code fence named \`mermaid\` is drawn as its diagram — flowcharts, sequences, timelines, gantt charts.
- **Maths**: \`$\\pi r^2$\` in a line, \`$$\` on lines of their own around a formula set apart.
- **Definitions**: a term on one line and \`: its meaning\` on the next.
- **Footnotes**: \`[^1]\` where the small print belongs and \`[^1]: the note.\` below.
- **Live lists**: a code fence named \`query\` lists what matches across the notes and keeps up — \`from: tickets\`, \`where: status != Done\`, \`show: table\` — for a page of open work or a changelog.
- **Boards**: a code fence named \`board\`, a line per column (\`To do: Draft, Review\`).
- **A canvas inside a page**: \`![[Its title]]\` on a line of its own.
- **Pictures**: add_picture puts one from the web into a page, kept with it; never write a picture's address into the words.
- **Ghost.md's own marks**, sparingly: \`==highlight==\`, \`%%aside%%\`, \`??to check??\`.

Raw HTML is shown as text, never run, so use markdown for everything.
`;
