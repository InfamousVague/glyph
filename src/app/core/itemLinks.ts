/**
 * List items and links: which items are not a link yet, and what one becomes
 * when it is linked to something.
 *
 * A linked item is one whose words are `[words](https://…)`, which the editor
 * shows short. So "not linked yet" is simply "a to-do or bullet whose words
 * are not already a link", and linking a whole list twice links nothing the
 * second time. Ticked to-dos are left alone: a done thing is not a task to
 * make. Plugins use these for what they link items to (the Notion plugin's
 * tasks), and the recorder for words of a take linked while it is being said.
 * Pure, so every shape of line is a test.
 */

const ITEM = /^(\s*(?:- \[[ xX]\] |[-*+] |\d{1,3}[.)] ))(.*)$/;

export interface Item {
  /** 1-based line number in the note. */
  line: number;
  /** The words, without the marker. */
  text: string;
}

/** Whether an item's words are already a link (to anywhere). */
function linked(text: string): boolean {
  return /\[[^\]]+\]\(https?:\/\/[^)]+\)/.test(text);
}

/** Every list item not sent yet, in note order. */
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

/** `lineText` with its words turned into a link to `url`; the marker and indent stay. */
export function linkedLine(lineText: string, url: string): string {
  const match = ITEM.exec(lineText);
  if (!match) return lineText;
  const words = (match[2] ?? '').trim().replace(/[[\]]/g, '');
  return `${match[1]}[${words}](${url})`;
}

export interface SentLink {
  text: string;
  url: string;
}

const squash = (text: string) => text.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

/**
 * `markdown` with each sent thing's words made a link, wherever the words
 * landed: in a to-do, a bullet or a sentence. For a take whose phrases were
 * sent while it is still being said, so the words keep the shape the spoken
 * cues gave them and only gain the link. The first line holding the words
 * (ignoring case and punctuation) is the one; words already inside a link are
 * left alone.
 */
export function applyLinks(markdown: string, links: readonly SentLink[]): string {
  if (!links.length) return markdown;
  const lines = markdown.split('\n');
  for (const link of links) {
    const wanted = squash(link.text);
    if (!wanted) continue;
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i] ?? '';
      if (line.includes(`](${link.url})`)) break;
      const match = ITEM.exec(line);
      const marker = match ? (match[1] ?? '') : '';
      const words = match ? (match[2] ?? '') : line;
      if (squash(words) === wanted) {
        lines[i] = `${marker}[${words.trim().replace(/[.,;:!?]+$/, '').replace(/[[\]]/g, '')}](${link.url})`;
        break;
      }
      const at = words.toLowerCase().indexOf(link.text.toLowerCase().replace(/[.,;:!?]+$/, ''));
      if (at >= 0 && !/\]\(/.test(words)) {
        const found = words.slice(at, at + link.text.replace(/[.,;:!?]+$/, '').length);
        lines[i] = `${marker}${words.slice(0, at)}[${found}](${link.url})${words.slice(at + found.length)}`;
        break;
      }
    }
  }
  return lines.join('\n');
}
