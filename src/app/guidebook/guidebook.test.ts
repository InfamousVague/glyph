import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement } from 'react';
import type { Updates } from '../core/ota.ts';
import { press, show } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before the About page's imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

// The About page reads the releases from what was kept and from the site; neither is this file's business.
vi.mock('../core/changelog.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/changelog.ts')>()),
  keptReleases: () => [],
  fetchReleases: () => Promise.resolve([]),
}));

const { chaptersOf, isBookBody, numbered } = await import('../book/book.ts');
const { itemsIn } = await import('../core/boards/items.ts');
const { boardNoteBody } = await import('../core/boardNote.ts');
const { sampleNoteBody } = await import('../core/sampleNote.ts');
const { howCanvasBody } = await import('../canvas/howCanvas.ts');
const { sampleCanvasBody } = await import('../canvas/sampleCanvas.ts');
const { createNote, listNotes, newNoteId, noteTitle } = await import('../core/store.ts');
const { sameTitle, wikiLinksIn } = await import('../editor/wikiLinks.ts');
const { addGuideBook, GUIDE_TITLE, loadGuideBook } = await import('./guidebook.ts');
const { ToastProvider } = await import('@glacier/react');
const { AboutPane } = await import('../settings/AboutPane.tsx');

/**
 * Ghost.md: The Guide as it ships: the index is a book whose chapters are the files, every link in it lands on a
 * page that will be there, no page shares a name with the notes Settings already adds, nothing in it reads like a
 * secret, and adding it twice leaves one book. Its words are the book's own (guidebook/chapters); this holds the
 * shape they have to keep.
 */

/** The chapter files as they are on disk, in the order of their names. */
const FILES = Object.entries(import.meta.glob<string>('./chapters/*.md', { query: '?raw', import: 'default', eager: true })).sort(([a], [b]) =>
  a < b ? -1 : 1,
);

/** The notes Settings › About adds, by the titles the app gives them. */
const BUILT_IN = [noteTitle(sampleNoteBody(null)), noteTitle(boardNoteBody()), noteTitle(sampleCanvasBody(null)), noteTitle(howCanvasBody())];

const book = await loadGuideBook();
const titles = book.chapters.map((chapter) => chapter.title);
const pages = [...book.chapters.map((chapter) => ({ name: chapter.title, body: chapter.body })), { name: GUIDE_TITLE, body: book.index }];

/** A page's words with its code taken out, fenced and inline: where a [[link]] is a link rather than an example of one. */
function prose(markdown: string): string {
  const kept: string[] = [];
  let fence: string | null = null;
  for (const line of markdown.split('\n')) {
    const open = /^\s*(`{3,}|~{3,})/.exec(line);
    if (fence) {
      if (open && open[1]![0] === fence[0] && open[1]!.length >= fence.length && line.trim() === open[1]) fence = null;
      continue;
    }
    if (open) {
      fence = open[1]!;
      continue;
    }
    kept.push(line.replace(/(`+)[\s\S]*?\1/g, ''));
  }
  return kept.join('\n');
}

/** What a secret looks like, by name: never in a page anyone can add to their library and share. */
const SECRETS: [string, RegExp][] = [
  ['an IP address', /\b(?:\d{1,3}\.){3}\d{1,3}\b/],
  ['a password', /password\s*[:=]/i],
  ['a token', /token\s*=/i],
  ['SSHPASS', /sshpass/i],
  ['a hex key', /\b[0-9a-f]{32,}\b/i],
];

/** A base64 key: a run of sixteen or more characters with no path or word breaks in it, mixing letters and digits. */
function keyLike(text: string): string | null {
  for (const run of text.match(/[A-Za-z0-9+/=_-]{16,}/g) ?? []) {
    for (const piece of run.split(/[/_-]/)) {
      if (piece.length >= 16 && /\d/.test(piece) && /[A-Za-z]/.test(piece)) return piece;
    }
  }
  return null;
}

beforeEach(() => {
  localStorage.clear();
});

describe('the book', () => {
  it('is an index whose chapters are exactly the chapter files, in the order of their names', () => {
    expect(FILES).toHaveLength(44);
    expect(FILES.map(([path]) => path.slice('./chapters/'.length, './chapters/'.length + 2))).toEqual(FILES.map((_, i) => String(i + 1).padStart(2, '0')));
    expect(isBookBody(book.index)).toBe(true);
    expect(noteTitle(book.index)).toBe(GUIDE_TITLE);
    const fileTitles = FILES.map(([, body]) => /^# (.+)\n/.exec(body)?.[1]);
    expect(chaptersOf(book.index).map((chapter) => chapter.title)).toEqual(fileTitles);
    expect(titles).toEqual(fileTitles);
    // Numbered straight through the parts, one to forty-four, none of them a part of another.
    expect(numbered(chaptersOf(book.index))).toEqual(titles.map((_, i) => String(i + 1)));
  });

  it('opens every chapter with its own title as its heading, and names it so', () => {
    for (const [path, body] of FILES) {
      const title = /^# (.+)\n/.exec(body)?.[1];
      expect(title, path).toBeTruthy();
      expect(noteTitle(body), path).toBe(title);
    }
  });

  it('points every link at a page of the book or a note Settings adds, and every link to a line at an item it has', () => {
    const known = [...titles, GUIDE_TITLE, ...BUILT_IN];
    const lost: string[] = [];
    let checked = 0;
    for (const { name, body } of pages) {
      const words = prose(body);
      for (const link of wikiLinksIn(words)) {
        checked += 1;
        if (!known.some((title) => sameTitle(title, link.title))) lost.push(`${name}: [[${link.title}]]`);
      }
      // `[[#^an-anchor]]` is this page's own item; the item may sit in an example block, where a board still reads it.
      const anchors = new Set(itemsIn(body).map((item) => item.id));
      for (const [, id] of words.matchAll(/\[\[#\^([a-z0-9-]+)\]\]/g)) {
        checked += 1;
        if (!anchors.has(id!)) lost.push(`${name}: [[#^${id}]]`);
      }
    }
    expect(lost).toEqual([]);
    // Every chapter ends on three, and the index names all forty-four: a count this low means nothing was read.
    expect(checked).toBeGreaterThan(44 * 3 + 44);
    // The examples in code are not links, and are not read as any: the canvas frame, written in backticks.
    expect(wikiLinksIn(prose('Write `![[Cabin weekend, laid out]]` alone.'))).toEqual([]);
  });

  it('shares no title with another page or with the notes Settings adds', () => {
    const all = [GUIDE_TITLE, ...titles];
    for (const title of all) {
      expect(BUILT_IN.filter((builtIn) => sameTitle(builtIn, title)), title).toEqual([]);
      expect(all.filter((other) => sameTitle(other, title)), title).toHaveLength(1);
    }
  });

  it('holds nothing that looks like a secret', () => {
    const found: string[] = [];
    for (const { name, body } of pages) {
      for (const [what, pattern] of SECRETS) {
        const hit = pattern.exec(body);
        if (hit) found.push(`${name}: ${what} (${hit[0]})`);
      }
      const key = keyLike(body);
      if (key) found.push(`${name}: a key (${key})`);
    }
    expect(found).toEqual([]);
  });

  it('knows a secret when it sees one', () => {
    const hits = ['ssh root@203.0.113.9', 'password: hunter2', 'curl ?token=abc', 'SSHPASS=x sshpass', 'sha 9f86d081884c7d659a2feaa0c55ad015'].filter((text) =>
      SECRETS.some(([, pattern]) => pattern.test(text)),
    );
    expect(hits).toHaveLength(5);
    expect(keyLike('Authorization: Bearer sk-ant-api03-Zx9Qb7LmT2vWc4Yh')).toBe('Zx9Qb7LmT2vWc4Yh');
    expect(keyLike('src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/MainActivity.kt')).toBeNull();
  });
});

describe('adding the book', () => {
  it('makes every chapter and the index, and answers the index, which reads as the book', async () => {
    const index = await addGuideBook(await listNotes());
    expect(isBookBody(index.body)).toBe(true);
    expect(noteTitle(index.body)).toBe(GUIDE_TITLE);
    const notes = await listNotes();
    expect(notes).toHaveLength(45);
    // Newest first: the index, then the book from its first chapter, so Recent opens at the start.
    expect(notes.slice(0, 3).map((note) => noteTitle(note.body))).toEqual([GUIDE_TITLE, titles[0], titles[1]]);
    expect(notes.map((note) => noteTitle(note.body)).sort()).toEqual([GUIDE_TITLE, ...titles].sort());
  });

  it('twice gives one book, opened the second time rather than made again', async () => {
    const first = await addGuideBook(await listNotes());
    const second = await addGuideBook(await listNotes());
    expect(second.id).toBe(first.id);
    expect(await listNotes()).toHaveLength(45);
  });

  it('leaves a chapter a note already has by that title, and makes one again where that note is archived', async () => {
    const mine = await createNote(newNoteId(), '# Live typing\n\nMy own notes on it.', 'editor');
    await addGuideBook(await listNotes());
    const notes = await listNotes();
    expect(notes).toHaveLength(45);
    expect(notes.filter((note) => sameTitle(noteTitle(note.body), 'Live typing')).map((note) => note.id)).toEqual([mine.id]);

    localStorage.clear();
    const archived = { ...(await createNote(newNoteId(), '# Live typing\n\nPut away.', 'editor')), archivedAt: Date.now() };
    await addGuideBook([archived]);
    expect((await listNotes()).filter((note) => sameTitle(noteTitle(note.body), 'Live typing'))).toHaveLength(2);
  });
});

describe('Settings › About', () => {
  it('has a row that adds the guide, and pressing it calls the handler', () => {
    const noop = () => undefined;
    const onGuideBook = vi.fn();
    const updates: Updates = {
      ready: null,
      apk: { kind: 'none' },
      checking: false,
      lastError: null,
      lastChecked: null,
      status: null,
      build: '20260924221500',
      version: '1.8.0',
      check: noop,
      reload: noop,
      installApk: noop,
    };
    const host = show(
      createElement(
        ToastProvider,
        null,
        createElement(AboutPane, {
          updates,
          onGuide: noop,
          onSample: noop,
          onGuideBook,
          onBoard: noop,
          onCanvas: noop,
          onHowCanvas: noop,
          onAcademy: noop,
          onCheatSheet: noop,
          onDeveloper: noop,
        }),
      ),
    );
    const row = [...host.querySelectorAll('button')].find((b) => b.querySelector('.setk-row__label')?.textContent === 'Add Ghost.md: The Guide');
    expect(row).toBeTruthy();
    press(row);
    expect(onGuideBook).toHaveBeenCalledOnce();
  });
});
