/**
 * List items and their marks: which items are not linked to anything yet,
 * and what one becomes when it is.
 *
 * The one form, everywhere: a linked item keeps its words as they are and
 * ends with a mark - a link whose words are the lowercase name of what it is
 * linked to, `- [ ] Buy milk [notion](https://www.notion.so/…)`. Matt: "we
 * need a common format for linking Notion pages to list items, as the AI
 * will change how this looks when formatting or enhancing". The words used
 * to be the link, `[Buy milk](https://…)`, and a rewrite that moved or
 * dropped the link left the item looking unsent; a mark at the end is one
 * small thing the model is told to keep in place, the editor draws it as a
 * pill (editor/links.ts), and the formatter puts it back on the item it came
 * from when a model loses it (format/links.ts). The old form still counts as
 * linked, so a note from before is never sent twice.
 *
 * So "not linked yet" is a to-do or bullet with no mark and no link in its
 * words, and linking a whole list twice links nothing the second time.
 * Ticked to-dos are left alone: a done thing is not a task to make. Plugins
 * use these for what they link items to (the Notion plugin's tasks), and the
 * recorder for words of a take linked while it is being said. Pure, so every
 * shape of line is a test.
 */

const ITEM = /^(\s*(?:- \[[ xX]\] |[-*+] |\d{1,3}[.)] ))(.*)$/;
/** The mark: the last thing on a line, a link whose words are one lowercase name. */
const MARK = /\s*\[([a-z][a-z0-9-]*)\]\((https?:\/\/[^\s)]+)\)\s*$/;

export interface Item {
  /** 1-based line number in the note. */
  line: number;
  /** The words, without the marker and without a mark. */
  text: string;
}

export interface ItemMark {
  /** What it is linked to: "notion". */
  name: string;
  url: string;
}

/**
 * The names a mark can carry: the ids of the plugins that link items, told
 * here as they load (plugins/registry.ts). Without this, "read the [docs](…)"
 * at the end of an item would be a mark called docs.
 */
const MARK_NAMES = new Set(['notion']);

export function registerMarkName(name: string): void {
  MARK_NAMES.add(name.toLowerCase());
}

export function isMarkName(name: string): boolean {
  return MARK_NAMES.has(name);
}

/** The mark at the end of `text`, if it has one. */
export function markOf(text: string): ItemMark | null {
  const match = MARK.exec(text);
  return match && isMarkName(match[1] ?? '') ? { name: match[1] ?? '', url: match[2] ?? '' } : null;
}

/** `text` without its mark. */
export function unmarked(text: string): string {
  return markOf(text) ? text.replace(MARK, '').trimEnd() : text.trimEnd();
}

/** The words of a list item line, marker and mark aside; null for a line that is not an item. */
export function itemWords(lineText: string): string | null {
  const match = ITEM.exec(lineText);
  return match ? unmarked(match[2] ?? '').trim() : null;
}

/** Whether an item's words are already linked: a mark, or the old form with a link in the words. */
function linked(text: string): boolean {
  return markOf(text) !== null || /\[[^\]]+\]\(https?:\/\/[^)]+\)/.test(text);
}

/** Every list item not linked yet, in note order. */
export function unsentItems(body: string): Item[] {
  const items: Item[] = [];
  body.split('\n').forEach((raw, index) => {
    const match = ITEM.exec(raw);
    if (!match) return;
    const marker = match[1] ?? '';
    const text = (match[2] ?? '').trim();
    if (!text || /\[[xX]\]/.test(marker) || linked(text) || text.startsWith('![')) return;
    items.push({ line: index + 1, text });
  });
  return items;
}

/** The item on `line` if it is one that can be sent, else null. */
export function itemAt(lineText: string, line: number): Item | null {
  return unsentItems(lineText).map((item) => ({ ...item, line }))[0] ?? null;
}

/** `lineText` with a mark to `url` at its end; the marker, the indent and the words stay. */
export function linkedLine(lineText: string, url: string, name = 'notion'): string {
  const match = ITEM.exec(lineText);
  if (!match) return lineText;
  const words = unmarked(match[2] ?? '').trim();
  return `${match[1]}${words} [${name}](${url})`;
}

export interface SentLink {
  text: string;
  url: string;
  /** What the words were sent to: "notion" unless said otherwise. */
  name?: string;
}

const squash = (text: string) => text.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

/**
 * `markdown` with each sent thing marked, wherever its words landed: a to-do
 * or a bullet gets the mark at its end; words in a sentence get it right
 * after them. For a take whose phrases were sent while it is still being
 * said, so the words keep the shape the spoken cues gave them and only gain
 * the mark. The first line holding the words (ignoring case and punctuation)
 * is the one; words already linked are left alone.
 */
export function applyLinks(markdown: string, links: readonly SentLink[]): string {
  if (!links.length) return markdown;
  const lines = markdown.split('\n');
  for (const link of links) {
    const wanted = squash(link.text);
    if (!wanted) continue;
    const mark = `[${link.name ?? 'notion'}](${link.url})`;
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i] ?? '';
      if (line.includes(`](${link.url})`)) break;
      const match = ITEM.exec(line);
      const marker = match ? (match[1] ?? '') : '';
      const words = match ? (match[2] ?? '') : line;
      if (squash(words) === wanted) {
        lines[i] = `${marker}${words.trim().replace(/[.,;:!?]+$/, '')} ${mark}`;
        break;
      }
      const at = words.toLowerCase().indexOf(link.text.toLowerCase().replace(/[.,;:!?]+$/, ''));
      if (at >= 0 && !/\]\(/.test(words)) {
        const end = at + link.text.replace(/[.,;:!?]+$/, '').length;
        lines[i] = `${marker}${words.slice(0, end)} ${mark}${words.slice(end)}`;
        break;
      }
    }
  }
  return lines.join('\n');
}
