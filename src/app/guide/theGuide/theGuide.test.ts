import { EditorState } from '@codemirror/state';
import { ensureSyntaxTree } from '@codemirror/language';
import { beforeEach, describe, expect, it } from 'vitest';
import { readInstruction } from '../../ai/instruction.ts';
import { kindWords } from '../../ai/kinds.ts';
import { bookWords, chaptersOf, isBookBody, numbered } from '../../book/book.ts';
import { tips } from '../../capture/tips.ts';
import { endsMemo, startsMemo } from '../../capture/voiceMemo.ts';
import { itemsIn, boardsIn } from '../../core/boards.ts';
import { SAMPLE_TITLE, sampleNoteBody } from '../../core/sampleNote.ts';
import { createNote, listNotes, newNoteId, noteTitle } from '../../core/store.ts';
import { trashNote } from '../../core/trash.ts';
import { bookmarkLineIn } from '../../editor/bookmarkLine.ts';
import { glyphMarkdown } from '../../editor/language.ts';
import { wikiLinksIn } from '../../editor/wikiLinks.ts';
import { MODES } from '../../format/modes.ts';
import { BUILT_IN } from '../../plugins/registry.ts';
import { GUIDE_PAGES, THE_GUIDE_TITLE, addTheGuide, theGuideBody } from './book.ts';
import { ASKS, COMMANDS, CUES, FREE_ASK, MEMO, OWN_CHAPTERS } from './chapters.ts';

/**
 * Ghost.md: The Guide may only teach what the app does. Its index is read the way a book's is (book/book.ts); every
 * link in it leads to a chapter it has; and every spoken example goes through the recorder's own readers, so a rule
 * that changes under the guide fails here rather than teaching someone something that no longer works.
 */

const titles = GUIDE_PAGES.map((page) => page.title);
const everything = OWN_CHAPTERS.map((chapter) => chapter.body).join('\n');

/** The node names the editor's parser finds in `doc`. */
function parsed(doc: string): Set<string> {
  const state = EditorState.create({ doc, extensions: [glyphMarkdown(BUILT_IN.flatMap((plugin) => plugin.formats ?? []), [])] });
  const names = new Set<string>();
  ensureSyntaxTree(state, state.doc.length, 10_000)?.iterate({ enter: (node) => void names.add(node.name) });
  return names;
}

describe('the guide’s book', () => {
  it('is a book called Ghost.md: The Guide, its index every chapter in order, the examples under their chapters', () => {
    const body = theGuideBody();
    expect(isBookBody(body)).toBe(true);
    expect(noteTitle(body)).toBe(THE_GUIDE_TITLE);
    const chapters = chaptersOf(body);
    expect(chapters.map((chapter) => chapter.title)).toEqual(titles);
    expect(chapters.map((chapter) => chapter.depth)).toEqual(GUIDE_PAGES.map((page) => page.depth));
    expect(numbered(chapters)).toEqual(['1', '2', '3', '4', '5', '6', '7', '7.1', '8', '9', '9.1', '10', '11']);
  });

  it('says how to read it before the index, and where else the app teaches after it', () => {
    const { before, after } = bookWords(theGuideBody());
    expect(before).toContain('a chapter at a time');
    expect(after).toContain('Ghost.md Academy');
    expect(after).toContain('Formatting cheat sheet');
  });

  it('has a chapter of its own words for each title it lists that no other note is', () => {
    for (const chapter of OWN_CHAPTERS) {
      expect(titles, chapter.title).toContain(chapter.title);
      // A chapter is found by its title, which is its heading.
      expect(noteTitle(chapter.body), chapter.title).toBe(chapter.title);
    }
    expect(new Set(titles).size).toBe(titles.length);
  });
});

describe('the guide’s chapters', () => {
  it('link only to chapters the guide has, so no link draws dashed or makes an empty note', () => {
    for (const chapter of OWN_CHAPTERS) {
      for (const link of wikiLinksIn(chapter.body)) expect(titles, `${chapter.title} → ${link.title}`).toContain(link.title);
    }
  });

  it('never open anywhere but the top: no bookmark in any of them', () => {
    for (const chapter of OWN_CHAPTERS) expect(bookmarkLineIn(chapter.body), chapter.title).toBeNull();
  });

  it('teach nothing that has gone: the AI bar, its spark and chips, the robot, Memo mode', () => {
    expect(everything).not.toMatch(/AI bar|\bchips?\b|robot|memo mode|✨/i);
    // The app's name is Ghost.md, and the old word only as the one that still works.
    for (const found of everything.matchAll(/Glyph/g)) expect(everything.slice(found.index - 1, found.index - 1 + '“Glyph” still works'.length)).toBe('“Glyph” still works');
  });

  it('parse as notes, the boards chapter holding a working board of its own', () => {
    const boards = OWN_CHAPTERS.find((chapter) => chapter.title === 'How boards work')!.body;
    expect(boardsIn(boards)).toHaveLength(1);
    const cards = boardsIn(boards)[0]!.columns.flatMap((column) => column.cards);
    expect(cards.sort()).toEqual(itemsIn(boards).map((item) => item.id).sort());
    for (const chapter of OWN_CHAPTERS) expect(parsed(chapter.body), chapter.title).toContain('ATXHeading1');
  });

  it('describe the AI’s rows and runs in the app’s own words for them', () => {
    for (const mode of MODES) expect(everything).toContain(`**${mode.label}**`);
    for (const ask of ASKS) expect(everything).toContain(kindWords(ask.run).hint.slice(1));
  });
});

describe('what the guide says to say', () => {
  const groceries = { id: 'g', title: 'Groceries', note: { body: '# Groceries\n\n- Eggs\n' } };
  const library = [groceries, { id: 'w', title: 'Work', note: { body: '# Work\n' } }];

  it('quotes no “Hey Ghost” but the ones held to the readers below', () => {
    const quoted = [...everything.matchAll(/“(Hey Ghost, [^”]+)”/g)].map((found) => found[1]);
    const known: string[] = [...COMMANDS.map((c) => c.say), ...ASKS.map((a) => a.say), FREE_ASK];
    for (const said of quoted) expect(known, said).toContain(said);
    for (const said of known) expect(quoted, said).toContain(said);
  });

  it('gives only commands the recorder acts on at Done, each doing what the chapter says', async () => {
    for (const command of COMMANDS) {
      const read = await readInstruction(command.say, library);
      expect(read.kind, command.say).toBe('command');
      if (read.kind !== 'command') continue;
      expect(read.plan.kind, command.say).toBe(command.kind);
      if (read.plan.kind === 'place') {
        expect(read.plan.note.title).toBe(command.note);
        expect(read.plan.text).toBe('bread');
        expect(read.plan.items).toBeUndefined();
      }
      if (read.plan.kind === 'create-list') {
        expect(read.plan.title).toBe(command.note);
        expect(read.plan.items).toEqual(['Spider-Man', 'Batman', 'Superman']);
      }
    }
  });

  it('gives asks the AI runs, each the run the chapter names, and a free ask it takes as words for the AI', async () => {
    for (const ask of ASKS) expect(await readInstruction(ask.say, library), ask.say).toEqual({ kind: 'run', run: ask.run });
    expect(await readInstruction(FREE_ASK, library)).toEqual({ kind: 'ask', instruction: FREE_ASK.replace('Hey Ghost, ', '') });
  });

  it('names cues the recorder suggests itself, and a voice memo it keeps as sound', () => {
    const said = tips({ continuing: false }).map((tip) => tip.say);
    for (const cue of CUES) expect(said, cue).toContain(cue);
    expect(startsMemo(MEMO.start)).toBe(true);
    expect(endsMemo(MEMO.end)).toBe(true);
  });
});

describe('adding the guide', () => {
  beforeEach(() => localStorage.clear());

  it('makes the book and every chapter, and answers the book', async () => {
    const book = await addTheGuide();
    expect(noteTitle(book.body)).toBe(THE_GUIDE_TITLE);
    const notes = await listNotes();
    expect(notes).toHaveLength(titles.length + 1);
    for (const title of titles) expect(notes.filter((note) => noteTitle(note.body) === title), title).toHaveLength(1);
  });

  it('makes nothing twice: a second time answers the same book', async () => {
    const first = await addTheGuide();
    const again = await addTheGuide();
    expect(again.id).toBe(first.id);
    expect(await listNotes()).toHaveLength(titles.length + 1);
  });

  it('uses a chapter the library has already, such as the sample note a fresh library is given', async () => {
    const sample = await createNote(newNoteId(), sampleNoteBody(null), 'editor');
    await addTheGuide();
    const samples = (await listNotes()).filter((note) => noteTitle(note.body) === SAMPLE_TITLE);
    expect(samples.map((note) => note.id)).toEqual([sample.id]);
  });

  it('makes a chapter again that is in the Trash, since the book could not open that one', async () => {
    await addTheGuide();
    const trashed = (await listNotes()).find((note) => noteTitle(note.body) === 'How books work')!;
    trashNote(trashed.id);
    await addTheGuide();
    const books = (await listNotes()).filter((note) => noteTitle(note.body) === 'How books work');
    expect(books).toHaveLength(2);
    expect(books.some((note) => note.id !== trashed.id)).toBe(true);
  });
});
