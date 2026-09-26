import { isBookBody } from '../../book/book.ts';
import { BOARD_TITLE } from '../../core/boardNote.ts';
import { renewedSample, SAMPLE_TITLE } from '../../core/sampleNote.ts';
import { addBoardNote, addCanvasNote, addHowCanvas, addSampleNote } from '../../core/seed.ts';
import { createNote, listNotes, newNoteId, noteTitle, updateNote, type Note } from '../../core/store.ts';
import { outOfTrash, trash } from '../../core/trash.ts';
import { HOW_TITLE, renewedHowCanvas } from '../../canvas/howCanvas.ts';
import { CANVAS_TITLE } from '../../canvas/sampleCanvas.ts';
import { sameTitle } from '../../editor/wikiLinks.ts';
import {
  AI_TITLE,
  BOARDS_TITLE,
  BOOKS_TITLE,
  CANVASES_TITLE,
  COMMAND_TITLE,
  NOTES_TITLE,
  OWN_CHAPTERS,
  PLUGINS_TITLE,
  RECORD_TITLE,
  SHARING_TITLE,
} from './chapters.ts';

/**
 * Ghost.md: The Guide - the whole app, as a book in the library (Matt: "update the docs in app. I would like a
 * 'Ghost.md: The Guide'").
 *
 * A book (docs/BOOKS.md) because a guide is chapters in an order with an index, and the app already reads one that
 * way: the index, a chapter's bar with the pages either side, Previous and Next at its foot, reading straight
 * through, a place kept, a link to share. And because a book is notes, the guide is Markdown the person can write in,
 * search, link to and delete, the way everything else in Ghost.md is.
 *
 * Its chapters are of two kinds. Nine are its own, the words in guide/theGuide/chapters.ts. The rest are the notes
 * the app already makes to teach by example - the sample note, the example board, the example canvas and the canvas
 * that says how Ghost.md works (core/seed.ts) - each placed where it belongs, the examples under the chapter that
 * explains them. So the guide says nothing twice, and a chapter can be a canvas, which the books chapter points out.
 *
 * `addTheGuide` makes the book and whichever of its chapters the library lacks, found by title the way a book finds
 * them (book/book.ts), and answers the book. A chapter the library already has - the sample note a fresh library is
 * given, a chapter someone has written in - is used as it is rather than made twice; a note in the Trash does not
 * count, since the book could not open it. A second call with nothing missing makes nothing.
 *
 * The one exception is an example an earlier Ghost.md made, which nobody has written in since: the sample note and
 * the canvas that says how Ghost.md works both taught things that stopped being true, and the guide would teach them
 * again from a library's old copy. Such a copy is brought up to date first (`renew`); one with anyone's words in it is
 * theirs, and stays as it is.
 *
 * Its notes are ordinary notes, so the home page shows them as it shows any: the chapters among Recent, and the
 * examples' to-dos under To do until they are ticked or deleted. That is on purpose, and the About row says so.
 */

export const THE_GUIDE_TITLE = 'Ghost.md: The Guide';

/** A chapter of the guide: its title, where it sits in the index, and how it is made when the library lacks it. */
export interface GuidePage {
  title: string;
  /** 1 for a chapter set under the one before it: an example under the chapter that explains it. */
  depth: 0 | 1;
  make: () => Promise<Note>;
  /** The body the chapter has now, for a copy of it an earlier Ghost.md made that nobody has changed; null for any other. */
  renew?: (body: string) => string | null;
}

/** A chapter of the guide's own words, made as a note. */
function own(title: string): () => Promise<Note> {
  const chapter = OWN_CHAPTERS.find((each) => each.title === title);
  if (!chapter) throw new Error(`no chapter called ${title}`);
  return () => createNote(newNoteId(), chapter.body, 'editor');
}

/** Every chapter, in the order the index lists them. */
export const GUIDE_PAGES: readonly GuidePage[] = [
  { title: HOW_TITLE, depth: 0, make: addHowCanvas, renew: renewedHowCanvas },
  { title: NOTES_TITLE, depth: 0, make: own(NOTES_TITLE) },
  { title: RECORD_TITLE, depth: 0, make: own(RECORD_TITLE) },
  { title: COMMAND_TITLE, depth: 0, make: own(COMMAND_TITLE) },
  { title: SAMPLE_TITLE, depth: 0, make: addSampleNote, renew: renewedSample },
  { title: AI_TITLE, depth: 0, make: own(AI_TITLE) },
  { title: BOARDS_TITLE, depth: 0, make: own(BOARDS_TITLE) },
  { title: BOARD_TITLE, depth: 1, make: addBoardNote },
  { title: BOOKS_TITLE, depth: 0, make: own(BOOKS_TITLE) },
  { title: CANVASES_TITLE, depth: 0, make: own(CANVASES_TITLE) },
  { title: CANVAS_TITLE, depth: 1, make: addCanvasNote },
  { title: SHARING_TITLE, depth: 0, make: own(SHARING_TITLE) },
  { title: PLUGINS_TITLE, depth: 0, make: own(PLUGINS_TITLE) },
];

/**
 * The book note: its front matter, a line on how to read it, the index - numbered, the examples set under their
 * chapters - and, after it, where else the app teaches, which the index view shows under the chapters as the book's
 * own words (book/book.ts `bookWords`).
 */
export function theGuideBody(): string {
  let number = 0;
  const index = GUIDE_PAGES.map((page) => {
    if (page.depth === 1) return `   - [[${page.title}]]`;
    number += 1;
    return `${number}. [[${page.title}]]`;
  }).join('\n');
  return `---
title: "${THE_GUIDE_TITLE}"
book: true
---
# ${THE_GUIDE_TITLE}

Everything Ghost.md does, a chapter at a time. Each chapter is a note of its own: tap one to open it, or read straight through. They are ordinary notes, so write in them, or delete them once you know it all.

${index}

- The Academy teaches every mark by having you type it: Settings, About, Ghost.md Academy.
- The cheat sheet has every mark on one page: the three dots at the top of any note, then Formatting cheat sheet.
`;
}

/** The notes a book could open: out of the Trash. */
async function openable(): Promise<Note[]> {
  return outOfTrash(await listNotes(), trash());
}

/** Makes the guide, and whichever of its chapters the library lacks, brings an untouched old example up to date, and answers the book. */
export async function addTheGuide(): Promise<Note> {
  const library = await openable();
  // The first by that title, newest first as the store lists them, which is the one a link to the title opens.
  const named = (title: string) => library.find((note) => sameTitle(noteTitle(note.body), title));
  for (const page of GUIDE_PAGES) {
    const found = named(page.title);
    if (!found) {
      await page.make();
      continue;
    }
    const renewed = page.renew?.(found.body) ?? null;
    // Changed since it was read, it is someone's now, and stays as it is.
    if (renewed !== null) await updateNote(found.id, renewed, found.revision ?? 1).catch(() => null);
  }
  const book = library.find((note) => isBookBody(note.body) && sameTitle(noteTitle(note.body), THE_GUIDE_TITLE));
  return book ?? createNote(newNoteId(), theGuideBody(), 'editor');
}
