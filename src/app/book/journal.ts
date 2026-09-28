import { frontMatterEnd, frontMatterValue, quotedTitle, withFrontMatterValue } from '../core/frontMatter.ts';
import { noteTitle } from '../core/noteTitle.ts';
import type { Note } from '../core/store.ts';
import { titleKey } from '../core/titleKey.ts';
import { chaptersOf, isBookBody, isJournalBody, withChapter } from './book.ts';

/**
 * A journal: a notebook whose pages are dated entries, each started from a template the journal keeps (Matt: "a
 * journal function where we can just do entries into a book marked as a journal where we pick the template for pages
 * (time and date prefixed, with geo location, etc etc)"; docs/DESIGN.md §142).
 *
 * It is a notebook note (book/book.ts) with two more flat keys beside `book: true`, and a third when it keeps places:
 *
 *   ---
 *   title: "Diary"
 *   book: true
 *   journal: true
 *   template: "# {{date}}\n\n**{{time}}** "
 *   entry-place: true
 *   ---
 *
 * `template:` is one double-quoted string with JSON's escapes, which is also a YAML double-quoted scalar, so any
 * Markdown app reads the text back, and it stays one line, so the front matter stays flat. An older app draws a
 * journal as the notebook it is and keeps every key it does not know (core/frontMatter.ts writes keep them).
 *
 * An entry is an ordinary note named `2026-09-28 14.05`, by the minute it was made, in ASCII digits whatever the
 * language: its key (core/titleKey.ts keeps only a-z and 0-9) never loses its month, and nothing in it is a character a
 * file name drops (src-tauri/src/library/names.rs), so its file is `2026-09-28 14.05.md` and the index's link resolves
 * in any Markdown app. Its `date:` is the wall clock it was written at, with no offset, so a shared entry does not say
 * which time zone its writer was in. The friendly date is its heading and its row in the journal.
 *
 * Pure: imports nothing that draws or stores, so the MCP server writes an entry and its line as the app does.
 */

/** A template to start from, and the one sentence every hint says it with (docs/DESIGN.md §21: never a name in a frame). */
export interface Preset {
  id: 'stamped' | 'time' | 'morning' | 'todos';
  name: string;
  text: string;
  sentence: string;
}

/** The templates offered, in the order the sheet lists them: the first is every journal's default. */
export const PRESETS: readonly Preset[] = [
  { id: 'stamped', name: 'The date and the time', text: '# {{date}}\n\n**{{time}}** ', sentence: 'Starts with the date and the time.' },
  { id: 'time', name: 'Just the time', text: '**{{time}}** ', sentence: 'Starts with the time.' },
  { id: 'morning', name: 'A morning page', text: '# {{date}}\n\n> What is on your mind this morning?\n\n', sentence: 'Starts with a question for the morning.' },
  { id: 'todos', name: 'A day’s to-dos', text: '# {{date}}\n\n## To do\n\n- [ ] ', sentence: 'Starts with a to-do list.' },
];

/** A template of the person's own writing: any text that is not one of the presets. */
export const OWN = { id: 'own', name: 'My own', sentence: 'Starts with your own template.' } as const;

export type PresetId = Preset['id'] | typeof OWN.id;

/** The template a journal with none says starts its entries. */
export const DEFAULT_TEMPLATE = PRESETS[0]!.text;

/** Said after a template's sentence when the journal keeps where each entry was written. */
export const PLACE_SENTENCE = 'Keeps where each was written.';

/** Which preset `text` is, or `own`. */
export function presetOf(text: string): PresetId {
  return PRESETS.find((preset) => preset.text === text)?.id ?? OWN.id;
}

/** The sentence that says what an entry starts with: the preset's, or your own template's. */
export function templateSentence(text: string): string {
  return PRESETS.find((preset) => preset.text === text)?.sentence ?? OWN.sentence;
}

// ---- the journal's keys ---------------------------------------------------------------------------

/** A front matter key's value as it is written, quotes and escapes and all, or null where there is none. */
function rawValue(body: string, key: string): string | null {
  const lines = body.split('\n');
  const end = frontMatterEnd(lines);
  const pattern = new RegExp(`^\\s*${key}\\s*:`, 'i');
  const line = lines.slice(1, Math.max(1, end - 1)).find((each) => pattern.test(each));
  return line === undefined ? null : line.replace(pattern, '').trim();
}

/**
 * The template as `template:` holds it: one JSON string, as the app writes it. A value someone wrote by hand without
 * quotes, or with quotes JSON will not read, is taken as written, `\n` as a line break. Absent, the default.
 */
export function templateOf(body: string): string {
  const raw = rawValue(body, 'template');
  if (raw === null) return DEFAULT_TEMPLATE;
  if (raw.startsWith('"')) {
    try {
      const text: unknown = JSON.parse(raw);
      if (typeof text === 'string') return text;
    } catch {
      // Not JSON after all: read as written, below.
    }
  }
  return raw.replace(/^(["'])(.*)\1$/, '$2').replace(/\\n/g, '\n');
}

/** A template as `template:`'s value: JSON's escapes, and the two line separators JSON leaves raw escaped too. */
function templateValue(text: string): string {
  return JSON.stringify(text).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

/** The body with its template set; every other key and the index as they were. */
export function withTemplate(body: string, text: string): string {
  return withFrontMatterValue(body, 'template', templateValue(text));
}

/** Whether the journal's entries keep where each was written (`entry-place:`, never `place:`, which is a geotag's). */
export function entryPlaceOf(body: string): boolean {
  const said = frontMatterValue(body, 'entry-place');
  return said !== null && /^(true|yes)$/i.test(said);
}

/** The body with its entries keeping their places, or not. */
export function withEntryPlace(body: string, on: boolean): string {
  return withFrontMatterValue(body, 'entry-place', on ? 'true' : null);
}

/** A notebook kept as a journal: `journal: true`, its template and its place switch, the rest as it was. */
export function withJournal(body: string, template: string, place: boolean): string {
  return withEntryPlace(withTemplate(withFrontMatterValue(body, 'journal', 'true'), template), place);
}

/** A journal made a notebook again: its three keys out, `book: true` and every page kept. */
export function withoutJournal(body: string): string {
  return ['journal', 'template', 'entry-place'].reduce((next, key) => withFrontMatterValue(next, key, null), body);
}

/** The body of a new journal: named, its template and its place switch, and an empty index under its heading. */
export function journalNoteBody(name: string, template: string, place: boolean): string {
  const named = quotedTitle(name, 'Journal');
  const keys = [`title: ${named}`, 'book: true', 'journal: true', `template: ${templateValue(template)}`, ...(place ? ['entry-place: true'] : [])];
  return `---\n${keys.join('\n')}\n---\n# ${named.slice(1, -1)}\n\n`;
}

/**
 * The journal's body with an entry's line added last, where the index's last line is, or after its words when it has
 * none yet. Last, whatever the entries' times, so the index reads in the order they were made in any app, and two
 * devices that each added one merge as the two lines (core/sync/notes.ts); the journal's own view orders by time.
 */
export function withEntry(body: string, title: string): string {
  return withChapter(body, title);
}

/**
 * The journal on screen, writing its own index (editor/NoteScreen.tsx): App puts an entry's line in, or takes it out,
 * through the journal's editor rather than under it, since the open journal's next save would otherwise write the old
 * index back or be refused.
 */
export interface JournalWriter {
  id: string;
  /** `change` made to the journal's body as the screen holds it, saved at once. */
  write: (change: (body: string) => string) => void;
}

// ---- an entry -------------------------------------------------------------------------------------

/** Two figures. */
const two = (n: number) => String(n).padStart(2, '0');

/** An entry's name, by the minute it was made in the device's time: "2026-09-28 14.05", ASCII in every language. */
export function entryTitle(ms: number): string {
  const at = new Date(ms);
  return `${at.getFullYear()}-${two(at.getMonth() + 1)}-${two(at.getDate())} ${two(at.getHours())}.${two(at.getMinutes())}`;
}

/** A title an entry is named by: the minute, and ` (2)` or more for a second in the same minute. */
const ENTRY_TITLE = /^\d{4}-\d{2}-\d{2} \d{2}\.\d{2}(?: \(\d+\))?$/;

export function isEntryTitle(title: string): boolean {
  return ENTRY_TITLE.test(title.trim());
}

/** `title`, or with ` (2)`, ` (3)` after it until no key in `keys` is its (core/titleKey.ts). */
export function uniqueTitle(title: string, keys: ReadonlySet<string>): string {
  if (!keys.has(titleKey(title))) return title;
  for (let n = 2; ; n += 1) {
    const next = `${title} (${n})`;
    if (!keys.has(titleKey(next))) return next;
  }
}

/** The wall clock at `ms` as `date:` writes it: "2026-09-28T14:05", with no offset. */
export function localStamp(ms: number): string {
  const at = new Date(ms);
  return `${at.getFullYear()}-${two(at.getMonth() + 1)}-${two(at.getDate())}T${two(at.getHours())}:${two(at.getMinutes())}`;
}

/** An entry's note: its name and when it was written, then the words it starts with. */
export function entryBody(title: string, stamp: string, words: string): string {
  return `---\ntitle: ${quotedTitle(title, title)}\ndate: ${stamp}\n---\n${words}`;
}

/** `date:`'s wall clock: a day, and a time where it gives one. */
const WALL = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?/;

/**
 * When an entry was written, as the wall clock read then, in milliseconds whose UTC fields are that wall clock: from
 * its `date:`, else from when the note was made, read in this device's time. So an entry written at 23:30 in New York
 * sorts and is grouped on the 28th wherever it is read, and entries compare by the clocks they were written at.
 */
export function stampOf(body: string, createdAt: number): number {
  const said = WALL.exec(frontMatterValue(body, 'date') ?? '');
  if (said) {
    const [, year, month, day, hour, minute] = said;
    const wall = Date.UTC(Number(year), Number(month) - 1, Number(day), Number(hour ?? 0), Number(minute ?? 0));
    if (Number.isFinite(wall)) return wall;
  }
  const made = new Date(createdAt);
  return Date.UTC(made.getFullYear(), made.getMonth(), made.getDate(), made.getHours(), made.getMinutes());
}

/**
 * The notes some journal's index names, by id: its entries, and any page it planned before it was kept as a journal.
 * Recent and the palette's first list leave them out (home/dashboard.ts, commands/palette.ts), as they leave out the
 * Guide's pages: a year of entries would otherwise fill Recent every day, and the journal's card is the way to them.
 */
export function entryPages(notes: readonly Note[]): Set<string> {
  const named = new Set<string>();
  for (const note of notes) {
    if (!isJournalBody(note.body)) continue;
    for (const chapter of chaptersOf(note.body)) {
      const key = titleKey(chapter.title);
      if (key) named.add(key);
    }
  }
  const ids = new Set<string>();
  if (!named.size) return ids;
  for (const note of notes) {
    if (!isBookBody(note.body) && named.has(titleKey(noteTitle(note.body)))) ids.add(note.id);
  }
  return ids;
}
