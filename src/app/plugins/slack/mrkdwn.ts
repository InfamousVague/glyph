import { frontMatterEnd } from '../../core/frontMatter.ts';
import { noteTitle, withoutFrontMatter } from '../../core/noteTitle.ts';

/**
 * A note as a Slack message: its title as a bold first line, then its words in Slack's own markup, mrkdwn.
 *
 * Slack does not read Markdown. It has its own, smaller markup: `*bold*`, `_italic_`, `~strike~`, `` `code` ``,
 * ``` fences, `>` quotes and links as `<url|words>`, and it wants `&`, `<` and `>` written as entities everywhere
 * else. So the obvious Markdown is turned into that, line by line, and the rest goes as the words it is:
 *
 * - `**bold**` and `__bold__` are `*bold*`; `*italic*` is `_italic_`; `~~struck~~` is `~struck~`.
 * - A heading is a bold line. A to-do is ☐, a ticked one ☑, and a bullet •, at the indent it had.
 * - `[words](https://…)` is `<https://…|words>`; a link into the app (a note, a picture on the phone) is its words
 *   alone, since nobody in the channel can open it. A picture with a web address is a link to it; one on the phone
 *   is left out.
 * - Code, in backticks or a fence, goes as it was written, escaped and nothing more.
 * - The Marks plugin's looks go as plain words, except a redaction (`@@…@@`), which goes as a bar: words drawn hidden
 *   on the page are not handed to a whole channel in the clear.
 * - Front matter is dropped, and so is the title line, which the message already opens with.
 *
 * Slack takes 40,000 characters in a message; a longer note is cut a little before that, and says so.
 */

/** A little under Slack's 40,000, so the closing words fit. */
const MOST = 39_000;

/** A hidden marker for a span set aside while the line around it is converted. Never typed: a control character. */
const HELD = '\u0000';
/** Bold, while the single stars around it become italics. */
const BOLD = '\u0001';

/** Slack's three escapes, everywhere outside its own link and quote marks. */
function escaped(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** An address inside `<…|…>`: the two characters that would end it early, percent-encoded. */
function slackUrl(href: string): string {
  return href.replace(/\|/g, '%7C').replace(/>/g, '%3E').replace(/</g, '%3C');
}

const WEB = /^(?:https?:\/\/|mailto:)/i;

/** One line's inline marks, as mrkdwn. */
function inline(line: string): string {
  const held: string[] = [];
  const hold = (made: string) => `${HELD}${held.push(made) - 1}${HELD}`;
  let text = line
    // Code first, so nothing inside it is read as a mark.
    .replace(/`[^`\n]+`/g, (code) => hold(escaped(code)))
    // A picture: a link when it is on the web, and nothing when it is on the phone.
    .replace(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, (_m, alt: string, src: string) => (WEB.test(src) ? hold(`<${slackUrl(src)}|${escaped(alt.trim() || 'picture')}>`) : ''))
    // A link: Slack's own, or its words where the address is the app's.
    .replace(/\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, (_m, words: string, href: string) => {
      if (!WEB.test(href)) return words;
      const label = words.replace(/\*\*|__|~~|`/g, '').trim();
      return hold(label ? `<${slackUrl(href)}|${escaped(label)}>` : `<${slackUrl(href)}>`);
    })
    // An address written `<https://…>` is already Slack's shape.
    .replace(/<((?:https?:\/\/|mailto:)[^>\s]+)>/gi, (_m, href: string) => hold(`<${slackUrl(href)}>`));
  text = escaped(text)
    // A redaction is a bar; the other looks are their words.
    .replace(/@@(\S(?:[^@]*?\S)?)@@/g, (_m, words: string) => '▇'.repeat(Math.min(12, Math.max(3, words.length))))
    .replace(/(\|\||==|%%|\^\^)(\S(?:.*?\S)?)\1/g, '$2')
    .replace(/(\p{Extended_Pictographic}️?)\1(\S(?:.*?\S)?)\1\1/gu, '$2')
    .replace(/\*\*(\S(?:.*?\S)?)\*\*/g, `${BOLD}$1${BOLD}`)
    .replace(/__(\S(?:.*?\S)?)__/g, `${BOLD}$1${BOLD}`)
    .replace(/(^|[^*\w])\*(\S(?:[^*]*?\S)?)\*(?![*\w])/g, '$1_$2_')
    .replace(/~~(\S(?:.*?\S)?)~~/g, '~$1~')
    .replace(new RegExp(BOLD, 'g'), '*');
  return text.replace(new RegExp(`${HELD}(\\d+)${HELD}`, 'g'), (_m, n: string) => held[Number(n)] ?? '');
}

const FENCE = /^\s*(```|~~~)/;
const HEADING = /^\s{0,3}#{1,6}\s+(.*?)(?:\s+#+)?\s*$/;
const TODO = /^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$/;
const BULLET = /^(\s*)[-*+]\s+(.*)$/;
const QUOTE = /^\s*>\s?(.*)$/;
const RULE = /^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/;

/** Markdown lines as mrkdwn, with runs of blank lines made one. */
export function toMrkdwn(markdown: string): string {
  const out: string[] = [];
  let inCode = false;
  for (const line of markdown.split('\n')) {
    if (FENCE.test(line)) {
      inCode = !inCode;
      out.push('```');
      continue;
    }
    if (inCode) {
      out.push(escaped(line));
      continue;
    }
    const heading = HEADING.exec(line);
    const todo = TODO.exec(line);
    const bullet = BULLET.exec(line);
    const quote = QUOTE.exec(line);
    if (heading) {
      const words = inline(heading[1]!.replace(/\*\*|__/g, '')).replace(/\*/g, '');
      out.push(words ? `*${words}*` : '');
    } else if (todo) out.push(`${todo[1]}${todo[2] === ' ' ? '☐' : '☑'} ${inline(todo[3]!)}`);
    else if (RULE.test(line)) out.push('———');
    else if (bullet) out.push(`${bullet[1]}• ${inline(bullet[2]!)}`);
    // Slack's quote mark is a `>` of its own at the line's start, so it stays one, not an entity.
    else if (quote) out.push(`> ${inline(quote[1]!)}`);
    else out.push(inline(line));
  }
  if (inCode) out.push('```');
  return out
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

/**
 * The note's words after its front matter and its title line: what follows the bold title in the message. The title
 * is the first line of words that is not a picture (core/noteTitle.ts), or the front matter's `title:`, which
 * `withoutFrontMatter` puts first; that line goes and the rest stays. A list item that opens the note stays too: it is
 * the list's first item as well as the title.
 */
function bodyAfterTitle(body: string): string {
  const words = withoutFrontMatter(body.split('\n'));
  const first = words.findIndex((l) => l.trim() && !/^!\[[^\]]*\]\([^)]*\)\s*$/.test(l));
  if (first >= 0 && !TODO.test(words[first]!) && !BULLET.test(words[first]!)) words.splice(first, 1);
  return words.join('\n');
}

/** Cut to what Slack takes, at a line where it can be, and saying so. */
function fitted(message: string): string {
  if (message.length <= MOST) return message;
  const cut = message.slice(0, MOST);
  const at = cut.lastIndexOf('\n');
  return `${at > MOST / 2 ? cut.slice(0, at) : cut}\n…\n_The rest is in Ghost.md: it is longer than one Slack message._`;
}

/** A title as the bold line a message opens with; an untitled note is "Untitled". */
function titleLine(title: string): string {
  // A note that opens with a list is titled by its first item, box and all; the message's title is its words.
  const bare = title.replace(/^[-*+]\s+(?:\[[ xX]\]\s+)?/, '');
  const words = inline(bare.replace(/\*\*|__/g, '')).replace(/\*/g, '');
  return `*${words || 'Untitled'}*`;
}

/**
 * The whole note as a message: the title bold, then the rest. A note whose title is its only line is the title alone;
 * a list that opens a note is its own first line, so it stays in the message under the title it gives.
 */
export function noteMessage(body: string): string {
  const rest = toMrkdwn(bodyAfterTitle(body));
  return fitted(rest ? `${titleLine(noteTitle(body))}\n${rest}` : titleLine(noteTitle(body)));
}

/** A meeting's summary as a message: the note's title bold, then the section (`## Summary` and what is under it). */
export function summaryMessage(body: string, section: string): string {
  return fitted(`${titleLine(noteTitle(body))}\n${toMrkdwn(section)}`);
}

/** Whether a note has anything to post: words past its front matter. */
export function hasWords(body: string): boolean {
  const lines = body.split('\n');
  return lines.slice(frontMatterEnd(lines)).some((l) => l.trim() !== '');
}
