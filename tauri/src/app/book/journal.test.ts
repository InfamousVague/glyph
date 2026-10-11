import { afterEach, describe, expect, it } from 'vitest';
import { valueImports } from '../../test/imports.ts';
import { inLocale } from '../../test/locale.ts';
import { makeNote } from '../../test/notes.ts';
import { frontMatterEnd, frontMatterValue, withFrontMatterValue } from '../core/frontMatter.ts';
import { noteTitle } from '../core/noteTitle.ts';
import { titleKey } from '../core/titleKey.ts';
import { chaptersOf, isBookBody, isJournalBody, withChapter } from './book.ts';
import { chapterOf } from './chapterNumber.ts';
import {
  DEFAULT_TEMPLATE,
  entryBody,
  entryPages,
  entryPlaceOf,
  entryTitle,
  isEntryTitle,
  journalNoteBody,
  localStamp,
  PRESETS,
  presetOf,
  stampOf,
  templateOf,
  templateSentence,
  uniqueTitle,
  withEntry,
  withEntryPlace,
  withJournal,
  withoutJournal,
  withTemplate,
} from './journal.ts';

/**
 * A journal is a notebook with a template, and its entries are notes named by the minute they were made. The keys it
 * adds, the names, the wall clock an entry keeps, and which notes are some journal's entries.
 */

const DIARY = journalNoteBody('Diary', DEFAULT_TEMPLATE, true);
/** The process's own zone, put back after a test that reads a clock somewhere else. */
const zone = process.env.TZ;
afterEach(() => {
  if (zone === undefined) delete process.env.TZ;
  else process.env.TZ = zone;
});

describe('a journal note', () => {
  it('is a notebook that says so, and only beside book: true', () => {
    expect(DIARY).toBe('---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: "# {{date}}\\n\\n**{{time}}** "\nentry-place: true\n---\n# Diary\n\n');
    expect(isBookBody(DIARY)).toBe(true);
    expect(isJournalBody(DIARY)).toBe(true);
    expect(isJournalBody('---\njournal: true\n---\n# Not a notebook\n')).toBe(false);
    expect(isJournalBody('---\nbook: true\njournal: YES\n---\n')).toBe(true);
    expect(isJournalBody('---\nbook: true\njournal: false\n---\n')).toBe(false);
    expect(isJournalBody('---\nbook: true\njournal: no\n---\n')).toBe(false);
    expect(frontMatterEnd(DIARY.split('\n'))).toBe(7);
    expect(noteTitle(DIARY)).toBe('Diary');
    expect(entryPlaceOf(DIARY)).toBe(true);
    expect(entryPlaceOf(journalNoteBody('Log', DEFAULT_TEMPLATE, false))).toBe(false);
    expect(entryPlaceOf('---\nbook: true\njournal: true\nentry-place: false\n---\n')).toBe(false);
    expect(entryPlaceOf('---\nbook: true\njournal: true\nentry-place: Yes\n---\n')).toBe(true);
    // Its name as the heading says it, out of its quotes; no name at all is a Journal.
    expect(journalNoteBody('Say "hi"', DEFAULT_TEMPLATE, false)).toMatch(/^---\ntitle: "Say 'hi'"\n[\s\S]*\n---\n# Say 'hi'\n\n$/);
    expect(journalNoteBody('  ', DEFAULT_TEMPLATE, false)).toMatch(/^---\ntitle: "Journal"\n[\s\S]*\n---\n# Journal\n\n$/);
  });

  it('keeps any template through its one line: quotes, backslashes, curly quotes, emoji and line breaks', () => {
    const text = '# {{date}}\n\n"Quoted" and \\back\\slashes, ‘curly’ “quotes” 🌙\n\t- [ ] ';
    const body = journalNoteBody('Moon log', text, false);
    // One line of front matter, whatever the text.
    expect(frontMatterEnd(body.split('\n'))).toBe(6);
    expect(templateOf(body)).toBe(text);
    expect(templateOf(withTemplate(DIARY, text))).toBe(text);
    // The line separators JSON leaves raw are escaped too.
    expect(withTemplate(DIARY, 'a\u2028b')).toContain('template: "a\\u2028b"');
    expect(templateOf(withTemplate(DIARY, 'a\u2028b'))).toBe('a\u2028b');
  });

  it('reads a template written by hand without quotes, with \\n as a line break, and the default where there is none', () => {
    expect(templateOf('---\nbook: true\njournal: true\ntemplate: # {{date}}\\n\\n{{time}} \n---\n')).toBe('# {{date}}\n\n{{time}}');
    expect(templateOf("---\nbook: true\njournal: true\ntemplate: 'Just {{time}}'\n---\n")).toBe('Just {{time}}');
    expect(templateOf('---\nbook: true\njournal: true\n---\n')).toBe(DEFAULT_TEMPLATE);
    // Only the front matter's: a line in the words that looks like the key is words.
    expect(templateOf('---\nbook: true\njournal: true\n---\ntemplate: "Not this"\n')).toBe(DEFAULT_TEMPLATE);
  });

  it('changes its template and its place switch without touching the other keys or the index', () => {
    const indexed = withEntry(withEntry(DIARY, '2026-09-27 21.40'), '2026-09-28 08.10');
    const changed = withEntryPlace(withTemplate(indexed, PRESETS[1]!.text), false);
    expect(frontMatterValue(changed, 'title')).toBe('Diary');
    expect(frontMatterValue(changed, 'book')).toBe('true');
    expect(templateOf(changed)).toBe('**{{time}}** ');
    expect(entryPlaceOf(changed)).toBe(false);
    // Off is the key taken out, not a `false` an older app would have to read.
    expect(changed).not.toContain('entry-place');
    expect(chaptersOf(changed).map((c) => c.title)).toEqual(['2026-09-27 21.40', '2026-09-28 08.10']);
  });

  it('is made from a notebook, and made a notebook again with book: true and every page kept', () => {
    const notebook = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Trees]]\n';
    const kept = withJournal(notebook, PRESETS[3]!.text, false);
    expect(isJournalBody(kept)).toBe(true);
    expect(templateOf(kept)).toBe(PRESETS[3]!.text);
    expect(entryPlaceOf(kept)).toBe(false);
    expect(withoutJournal(withEntryPlace(kept, true))).toBe(notebook);
  });

  it('puts an entry’s line last: after the last line of the index, or after its words when it has none', () => {
    expect(withEntry(DIARY, '2026-09-28 14.05')).toBe(`${DIARY}- [[2026-09-28 14.05]]\n`);
    const worded = `${DIARY}Written on the train.\n`;
    expect(withEntry(worded, '2026-09-28 14.05')).toBe(`${DIARY}Written on the train.\n\n- [[2026-09-28 14.05]]\n`);
    // The next goes after it, whatever time it names: the index is in the order they were made.
    const two = withEntry(withEntry(DIARY, '2026-09-28 14.05'), '2026-09-27 09.00');
    expect(chaptersOf(two).map((c) => c.title)).toEqual(['2026-09-28 14.05', '2026-09-27 09.00']);
    // It is withChapter's append, so a numbered index goes on numbering.
    expect(withEntry('---\nbook: true\njournal: true\n---\n1. [[A]]\n', 'B')).toBe(withChapter('---\nbook: true\njournal: true\n---\n1. [[A]]\n', 'B'));
    // At the top level, never a part of the page above it, and numbered on from the last top-level line.
    const kept = '---\nbook: true\njournal: true\n---\n- [[Trip]]\n  - [[Day one]]\n';
    expect(withEntry(kept, '2026-09-28 14.05')).toBe(`${kept}- [[2026-09-28 14.05]]\n`);
    const numbered = '---\nbook: true\njournal: true\n---\n1. [[Trip]]\n   1. [[Day one]]\n';
    expect(withEntry(numbered, '2026-09-28 14.05')).toBe(`${numbered}2. [[2026-09-28 14.05]]\n`);
    expect(chaptersOf(withEntry(numbered, '2026-09-28 14.05')).at(-1)).toMatchObject({ title: '2026-09-28 14.05', depth: 0 });
    expect(withEntry(kept, 'Day one')).toBe(kept);
  });

  it('says what an entry starts with in one fixed sentence, and knows its presets', () => {
    expect(PRESETS.map((p) => p.name)).toEqual(['The date and the time', 'Just the time', 'A morning page', 'A day’s to-dos']);
    expect(presetOf(DEFAULT_TEMPLATE)).toBe('stamped');
    expect(presetOf(PRESETS[3]!.text)).toBe('todos');
    expect(presetOf('# {{date}}')).toBe('own');
    expect(templateSentence(PRESETS[2]!.text)).toBe('Starts with a question for the morning.');
    expect(templateSentence('Anything')).toBe('Starts with your own template.');
    for (const preset of PRESETS) expect(preset.sentence).toMatch(/^[A-Z][^;—–…]*\.$/);
  });
});

describe('an entry', () => {
  it('is named by the minute in ASCII digits, whatever the language', () => {
    const at = new Date(2026, 8, 28, 14, 5).getTime();
    for (const locale of ['en-GB', 'ar-EG', 'ru-RU', 'el-GR']) expect(inLocale(locale, () => entryTitle(at))).toBe('2026-09-28 14.05');
    // Its key keeps the month, so September and October are two keys.
    expect(titleKey(entryTitle(at))).toBe('2026 09 28 14 05');
    expect(titleKey(entryTitle(new Date(2026, 9, 28, 14, 5).getTime()))).not.toBe(titleKey(entryTitle(at)));
    expect(entryTitle(new Date(2026, 0, 2, 7, 9).getTime())).toBe('2026-01-02 07.09');
  });

  it('is told by its name, a second in the same minute included, and is not a numbered chapter', () => {
    expect(isEntryTitle('2026-09-28 14.05')).toBe(true);
    expect(isEntryTitle('2026-09-28 14.05 (2)')).toBe(true);
    expect(isEntryTitle('2026-09-28')).toBe(false);
    expect(isEntryTitle('Notes 2026-09-28 14.05')).toBe(false);
    expect(isEntryTitle('2026-09-28 14.05 later')).toBe(false);
    expect(isEntryTitle('Trees')).toBe(false);
    expect(chapterOf('2026-09-28 14.05')).toBeNull();
    expect(chapterOf('2026-09-28 14.05 (2)')).toBeNull();
  });

  it('takes (2) and then (3) for a minute already taken, matched as titles are', () => {
    const keys = new Set([titleKey('2026-09-28 14.05')]);
    expect(uniqueTitle('2026-09-28 14.05', keys)).toBe('2026-09-28 14.05 (2)');
    keys.add(titleKey('2026-09-28 14.05 (2)'));
    expect(uniqueTitle('2026-09-28 14.05', keys)).toBe('2026-09-28 14.05 (3)');
    expect(uniqueTitle('2026-09-28 14.06', keys)).toBe('2026-09-28 14.06');
  });

  it('keeps the wall clock it was written at, with no offset, in any zone', () => {
    const instant = Date.UTC(2026, 8, 28, 8, 35);
    process.env.TZ = 'Asia/Kolkata';
    expect(localStamp(instant)).toBe('2026-09-28T14:05');
    expect(entryTitle(instant)).toBe('2026-09-28 14.05');
    process.env.TZ = 'America/New_York';
    expect(localStamp(instant)).toBe('2026-09-28T04:35');
    expect(localStamp(instant)).not.toMatch(/[+Z]|-\d\d:\d\d$/);
  });

  it('is a note named by its front matter, with its date, then the words it starts with', () => {
    const body = entryBody('2026-09-28 14.05', '2026-09-28T14:05', '# Monday 28 September\n\n**14:05** ');
    expect(body).toBe('---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n# Monday 28 September\n\n**14:05** ');
    expect(noteTitle(body)).toBe('2026-09-28 14.05');
    // A heading rewritten, or the words, and the entry keeps its name.
    expect(noteTitle(body.replace('# Monday 28 September', '# A long walk'))).toBe('2026-09-28 14.05');
  });

  it('is ordered by the clock it says it was written at, else when its note was made', () => {
    const said = stampOf('---\ndate: 2026-09-28T23:30\n---\nLate.', 0);
    expect(new Date(said).toISOString()).toBe('2026-09-28T23:30:00.000Z');
    // Read in London, written in New York: still the 28th.
    process.env.TZ = 'Europe/London';
    expect(new Date(stampOf('---\ndate: 2026-09-28T23:30\n---\n', 0)).getUTCDate()).toBe(28);
    const made = new Date(2026, 6, 4, 9, 15).getTime();
    expect(new Date(stampOf('# No date', made)).toISOString()).toBe('2026-07-04T09:15:00.000Z');
    expect(new Date(stampOf('---\ndate: not a date\n---\n', made)).toISOString()).toBe('2026-07-04T09:15:00.000Z');
  });
});

describe('which notes are entries', () => {
  it('names a journal’s entries and planned pages, never a notebook’s pages, and never the journal', () => {
    const journal = makeNote('diary', withEntry(withEntry(DIARY, '2026-09-28 14.05'), 'A plan'));
    const notebook = makeNote('guide', '---\ntitle: "Field guide"\nbook: true\n---\n- [[Trees]]\n');
    const entry = makeNote('e1', entryBody('2026-09-28 14.05', '2026-09-28T14:05', 'Words.'));
    const plan = makeNote('plan', '# A plan');
    const trees = makeNote('trees', '# Trees');
    expect([...entryPages([journal, notebook, entry, plan, trees])].sort()).toEqual(['e1', 'plan']);
    expect(entryPages([notebook, trees]).size).toBe(0);
  });
});

describe('the pure half', () => {
  it('reaches nothing that draws or stores, so the MCP server can bundle a journal', () => {
    for (const entry of ['app/book/journal.ts', 'app/core/template.ts']) {
      const { files, packages } = valueImports(entry);
      expect(packages).toEqual([]);
      expect(files.filter((file) => /store\.ts$|tauri|editor\/|\.tsx$/.test(file))).toEqual([]);
    }
  });

  it('keeps every other key when the journal is written', () => {
    const body = withFrontMatterValue(DIARY, 'authors', '"Matt, Claude"');
    expect(frontMatterValue(withoutJournal(withTemplate(body, 'x')), 'authors')).toBe('Matt, Claude');
  });
});
