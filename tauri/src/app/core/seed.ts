import { saveImageFile } from './images.ts';
import { boardNoteBody } from './boardNote.ts';
import { howCanvasBody } from '../canvas/howCanvas.ts';
import { sampleCanvasBody } from '../canvas/sampleCanvas.ts';
import { sampleImageBlob, sampleNoteBody } from './sampleNote.ts';
import { exampleJournal, exampleNotebookBody, exampleTicketBodies, todayFor } from './starterNotes.ts';
import { storedFlag } from './stored.ts';
import { createNote, newNoteId, type Note } from './store.ts';

/**
 * The starter notes' arrival. A fresh library, with no notes in it, gets them once: the sample note with every mark
 * the app draws (core/sampleNote.ts), the example board (core/boardNote.ts), a notebook of three example tickets and a
 * journal with its first entry (core/starterNotes.ts; docs/DESIGN.md §172; Matt: "pre populate new accounts with an
 * example board, example tickets (3) example journal and an example with all the formatting"). A library that already
 * has notes is left alone and marked done, so an update never drops a note on someone. Settings > About > Examples adds
 * the sample note and the board on request at any time, which is how Matt sees them on a phone full of notes.
 *
 * The mark is a key in localStorage, the way the guide's is, and a reset
 * clears it with the rest (core/reset.ts).
 */

/** Nowhere to remember it: better never to seed than to seed on every open. */
const seeded = storedFlag('glyph-sample-note', { unreadable: true });

export const sampleNoteSeeded = seeded.is;

const markSeeded = seeded.mark;

/**
 * The bundled smoke photograph kept as a picture of this device's, answering its name; null where a picture cannot be
 * kept or drawn, and the sample is then made without one rather than not at all.
 */
async function samplePicture(): Promise<string | null> {
  try {
    const blob = await sampleImageBlob();
    return blob ? await saveImageFile(blob) : null;
  } catch {
    return null;
  }
}

/** Makes the sample note now, picture and all where a picture can be drawn, and answers it. */
export async function addSampleNote(): Promise<Note> {
  // Without a picture the note says nothing of one.
  const note = await createNote(newNoteId(), sampleNoteBody(await samplePicture()), 'editor');
  markSeeded();
  return note;
}

/** Makes the example board (core/boardNote.ts) now, and answers it. */
export async function addBoardNote(): Promise<Note> {
  return createNote(newNoteId(), boardNoteBody(), 'editor');
}

/** Makes the example canvas (canvas/sampleCanvas.ts) now, its picture kept where one can be drawn, and answers it. */
export async function addCanvasNote(): Promise<Note> {
  // Without a picture the canvas is made with no picture card.
  return createNote(newNoteId(), sampleCanvasBody(await samplePicture()), 'editor');
}

/** Makes the canvas that says how Glyph works (canvas/howCanvas.ts) now, and answers it. */
export async function addHowCanvas(): Promise<Note> {
  return createNote(newNoteId(), howCanvasBody(), 'editor');
}

/**
 * The examples a fresh library starts with, beside the sample note: the three tickets and their notebook, the board,
 * and the journal's entry and then the journal, so the journal's index names a note that is there. Made oldest first,
 * so the sample note, made after them, is the newest and leads Recent.
 */
async function addStarterExamples(now: Date = new Date()): Promise<void> {
  for (const ticket of exampleTicketBodies(todayFor(now))) await createNote(newNoteId(), ticket.body, 'editor');
  await createNote(newNoteId(), exampleNotebookBody(), 'editor');
  await addBoardNote();
  const journal = exampleJournal(now);
  await createNote(newNoteId(), journal.entry, 'editor');
  await createNote(newNoteId(), journal.journal, 'editor');
}

/**
 * The starter notes for a fresh library only: made when the library holds `noteCount` of nothing and they have never
 * been made; a library with notes is marked done and left as it is. Marked done before anything is made, so a second
 * pass while the first is writing makes nothing twice. Answers the sample note, made last, or null.
 */
export async function seedSampleNote(noteCount: number): Promise<Note | null> {
  if (sampleNoteSeeded()) return null;
  markSeeded();
  if (noteCount > 0) return null;
  await addStarterExamples();
  return addSampleNote();
}
