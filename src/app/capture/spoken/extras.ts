import { emojiFor } from '../../core/emoji.ts';
import { BOOKMARK_SIGNS, listLead } from '../../core/itemSyntax.ts';
import { capitalise } from '../../core/text.ts';
import { titleKey } from '../../core/titleKey.ts';
import { matchNote } from '../route.ts';
import { NUMBER_PHRASE, spokenNumber } from './numbers.ts';
import { ANCHOR_MARK, BOOKMARK_MARK, BREAK_MARK } from './standIns.ts';

/**
 * The marks said inside a sentence that are not emphasis: tags, counters, links to a note, an item or a page, a
 * line's name, the bookmark, emoji, a line break, and footnotes.
 *
 * Each is a phrase with its own ending ("note link … end link", "anchor … end anchor") or a word that cannot be
 * anything else ("hashtag", "emoji"), so they are read out of the paragraph before it is cut into sentences. The ones
 * that belong at the end of a line - a line's name, the bookmark - and a break between lines leave a stand-in where
 * they were said (spoken/standIns.ts), and `finishLines` writes the real marks once the lines are known. Pure but for
 * the note titles a spoken link may name, which the recorder sets as it opens (`setLinkTitles`).
 */

/** "Counter three of eight": a counter (`[3/8]`), at the end of what it counts. */
const COUNTER_SAID = new RegExp(String.raw`[.,;]?\s*\bcounter\s+(${NUMBER_PHRASE})\s+(?:of|out\s+of)\s+(${NUMBER_PHRASE})(?=[\s.,;:!?]|$)`, 'gi');

/** "Hashtag travel": a tag. Whisper often writes "#travel" itself, which is left as it is. */
const TAG_SAID = /\bhash[\s-]?tag\s+([A-Za-z][\w-]*)/gi;

/** "Note link weekend trip end link": a link to another note (`[[Weekend trip]]`). */
const NOTE_LINK_SAID = /\b(?:no(?:te|de)\s?link|link\s+to\s+note)[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+link\b/gi;

/**
 * Titles of the notes a spoken link can name, set by the recorder: a link takes the note's own spelling. A module's
 * own state, as the spoken formats are (spoken/inline.ts), set as the recorder opens and by the voice suite per test.
 */
let linkTitles: readonly string[] = [];

export function setLinkTitles(titles: readonly string[]): void {
  linkTitles = titles;
}

/** "Item link ask Sam end link": a link to a line of this note by its name (`[[#^ask-sam]]`, editor/boards.ts). */
const ITEM_LINK_SAID = /\bitem\s?link[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+link\b/gi;

/** "Link Glyph to attack dot fm end link", "link attack dot fm end link": a link to a page. */
const LINK_SAID = /\blink[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+link\b/gi;

/** "Anchor ship page end anchor": the line's own name (` ^ship-page`), moved to the end of its line when the note is laid out. */
const ANCHOR_SAID = /[.,]?\s*\b(?:anchor|item\s+name)[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+(?:anchor|name)\b([.,!?]?)/gi;

/** "Bookmark this", "bookmark here", at the end of what it marks: the note's bookmark (`§§`, editor/bookmarkLine.ts). */
const BOOKMARK_SAID = /[.,]?\s*\bbookmark\s+(?:this(?:\s+line)?|here)\b(?=[.,!?]|\s*$)([.,!?]?)/gi;

/** "Emoji party popper": the emoji by its name, as a shortcode (`:tada:`, core/emoji.ts). */
const EMOJI_SAID = /\bemoji[,:]?\s+([A-Za-z]+(?:[\s-]+[A-Za-z]+){0,3})/gi;

/** "… end unsure, note Sam said four hundred, end note": what a mark means, shown on a tap (`??four hundred??(Sam said…)`). */
const MARK_NOTE_SAID = /(\?\?|==|%%|\*\*|\^\^|\+\+|~~|\|\||\b_)[.,]?\s+(?:with\s+(?:a\s+)?)?note[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+note\b/gi;

/** "…, new line, …" with a pause either side: a line break inside the paragraph. "A new line of shoes" is words. */
const LINE_BREAK_SAID = /(^|[.,;!?])\s*\b(?:new|next)\s+line\b[.,;!]?(?=\s|$)/gi;

/** "Footnote Sam said so end footnote": a footnote marker where it was said, its words under the note. */
const FOOTNOTE_SAID = /([.!?]?)[,]?\s*\bfoot\s?note[,:.]?\s+(.+?)[.,]?\s+(?:end|and)\s+foot\s?note\b([.,!?]?)/gi;

/** The spoken names people give emoji, where they differ from the shortcode. */
const EMOJI_SAID_AS: Record<string, string> = {
  thumbs_up: '+1',
  thumbs_down: '-1',
  party: 'tada',
  party_popper: 'tada',
  celebration: 'tada',
  check: 'white_check_mark',
  check_mark: 'white_check_mark',
  tick: 'white_check_mark',
  cross: 'x',
  cross_mark: 'x',
  light_bulb: 'bulb',
  laughing: 'joy',
  crying: 'sob',
  smiley: 'smile',
  money_bag: 'moneybag',
  magnifying_glass: 'mag',
  lightning: 'zap',
  plane: 'airplane',
  sun: 'sunny',
  pin: 'pushpin',
};

/** A spoken name as a line's name: "Ship Page" is `ship-page`, as said (core/boards.ts reads `[a-z0-9][a-z0-9_-]*`). */
export function spokenSlug(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/** "attack dot fm slash glyph" as `https://attack.fm/glyph`, or null when it isn't an address. */
export function spokenAddress(text: string): string | null {
  const said = text
    .trim()
    .toLowerCase()
    .replace(/\s*\b(?:dot)\b\s*/g, '.')
    .replace(/\s*\b(?:forward\s+)?slash\b\s*/g, '/')
    .replace(/\s*\bcolon\b\s*/g, ':')
    .replace(/\s*\b(?:dash|hyphen)\b\s*/g, '-')
    .replace(/\s*\bunderscore\b\s*/g, '_')
    .replace(/\s*([./:])\s*/g, '$1')
    .replace(/[.,]+$/, '');
  // Words still apart are words: "Glyph to attack.fm" is a name and an address, not one address.
  if (!/^(?:https?:\/\/)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?:[/?#]\S*)?$/.test(said)) return null;
  return /^https?:\/\//.test(said) ? said : `https://${said}`;
}

function spokenEmoji(all: string, words: string): string {
  const said = words.toLowerCase().split(/[\s-]+/);
  for (let take = said.length; take >= 1; take -= 1) {
    const name = said.slice(0, take).join('_');
    const code = EMOJI_SAID_AS[name] ?? (emojiFor(name) ? name : null);
    if (code) {
      const rest = words.split(/[\s-]+/).slice(take).join(' ');
      return `:${code}:${rest ? ` ${rest}` : ''}`;
    }
  }
  return all;
}

/** Tags, counters, links, emoji and the other marks said inside a sentence, written as what they are. */
export function spokenExtras(paragraph: string): string {
  return paragraph
    .replace(ITEM_LINK_SAID, (all, name: string) => {
      const slug = spokenSlug(name);
      return slug ? `[[#^${slug}]]` : all;
    })
    .replace(NOTE_LINK_SAID, (_all, name: string) => {
      const said = name.trim().replace(/^(?:the|my|our)\s+/i, '').replace(/\s+note$/i, '');
      // The note's own spelling, and the closest title when the name was misheard ("week and trip").
      const known = linkTitles.find((title) => titleKey(title) === titleKey(said)) ?? matchNote(said, linkTitles.map((title) => ({ id: title, title })))?.note.title;
      return `[[${known ?? capitalise(said)}]]`;
    })
    .replace(LINK_SAID, (all, inner: string) => {
      const bare = spokenAddress(inner);
      if (bare) return `<${bare}>`;
      // "Glyph to attack dot fm": the words, then where they go, split at the last "to" that leaves an address.
      const parts = inner.split(/\s+to\s+/i);
      for (let at = parts.length - 1; at >= 1; at -= 1) {
        const address = spokenAddress(parts.slice(at).join(' to '));
        const words = parts.slice(0, at).join(' to ').trim();
        if (address && words) return `[${words}](${address})`;
      }
      return all;
    })
    .replace(MARK_NOTE_SAID, (_all, mark: string, note: string) => `${mark}(${note.trim()})`)
    .replace(ANCHOR_SAID, (all, name: string, after: string) => {
      const slug = spokenSlug(name);
      return slug ? `${ANCHOR_MARK}${slug}${ANCHOR_MARK}${after}` : all;
    })
    .replace(BOOKMARK_SAID, (_all, after: string) => `${BOOKMARK_MARK}${after}`)
    .replace(EMOJI_SAID, spokenEmoji)
    .replace(LINE_BREAK_SAID, (_all, before: string) => `${before && /[.!?]/.test(before) ? before : before ? '.' : ''}${BREAK_MARK}`)
    .replace(TAG_SAID, (_all, word: string) => `#${word.toLowerCase()}`)
    .replace(COUNTER_SAID, (all, count: string, goal: string) => {
      const n = spokenNumber(count);
      const m = spokenNumber(goal);
      return n === null || m === null || m < 1 ? all : ` [${n}/${m}]`;
    });
}

/**
 * The footnotes said in `text` lifted out: each one's words pushed onto `footnotes`, in order, and a marker
 * (`[^1]`) left where it was said. The notes are written under the whole note (capture/markdown.ts `renderNote`).
 */
export function liftFootnotes(text: string, footnotes: string[]): string {
  return text.replace(FOOTNOTE_SAID, (_all, before: string, note: string, after: string) => {
    const words = capitalise(note.trim().replace(/[,;]+$/, ''));
    footnotes.push(/[.!?]$/.test(words) ? words : `${words}.`);
    return `[^${footnotes.length}]${after || before}`;
  });
}

/**
 * The stand-ins put back as marks, once the note is laid out: a line break where one was said, a line's name at the
 * end of its line (after the bookmark, as core/boards.ts reads it), and the bookmark on the last line it was said on,
 * since a note holds one.
 */
export function finishLines(body: string): string {
  const lines = body
    .replace(new RegExp(`${BREAK_MARK} *(\\S)`, 'g'), (_all, next: string) => `  \n${next.toUpperCase()}`)
    .replaceAll(BREAK_MARK, '')
    .split('\n');
  let marked = -1;
  lines.forEach((line, index) => {
    if (line.includes(BOOKMARK_MARK)) marked = index;
  });
  const used = new Set<string>();
  const nameOn = new RegExp(`${ANCHOR_MARK}([^${ANCHOR_MARK}]*)${ANCHOR_MARK}`, 'g');
  return lines
    .map((line, index) => {
      const names = [...line.matchAll(nameOn)].map((found) => found[1] ?? '');
      if (!names.length && !line.includes(BOOKMARK_MARK)) return line;
      const broken = line.endsWith('  ');
      let text = line
        .replace(nameOn, '')
        .replaceAll(BOOKMARK_MARK, '')
        .replace(/\s+([.,;!?])/g, '$1')
        .replace(/ {2,}/g, ' ')
        .trimEnd();
      // A list item's words end without a stop, before its bookmark and name.
      if (listLead(text)) text = text.replace(/[.,;]+$/, '');
      if (index === marked) text += ` ${BOOKMARK_SIGNS}`;
      const name = names[names.length - 1];
      if (name) {
        let unique = name;
        for (let count = 2; used.has(unique); count += 1) unique = `${name}-${count}`;
        used.add(unique);
        text += ` ^${unique}`;
      }
      return broken ? `${text}  ` : text;
    })
    .join('\n');
}
