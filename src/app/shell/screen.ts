import type { ReviewHandoff } from '../ai/review.ts';
import type { SpokenAsk } from '../capture/CaptureScreen.tsx';
import type { Note } from '../core/store.ts';
import { ALL_NOTES, notePlace, type Place } from '../notes/visited.ts';

/**
 * Which screen is up: the one piece of state the app would have bought a router to hold (App.tsx says why it did
 * not).
 *
 * Five screens, each a member of one union: the home page, the All notes grid, a note, a capture and the Academy.
 * Everything else a person sees - Settings, the guide, the + sheet, the sidebar's card, the aside, the palette - is a
 * sheet or a card over whichever of these is up, and is held beside it in the Shell rather than in here.
 *
 * Three of the five are places (notes/visited.ts): the home page, the grid and a note are where a person goes, so they
 * are where the tab row is drawn, where the arrows walk, and where a wide window splits into panes. A capture and the
 * Academy are things a person is doing, each the whole screen with its own way out. The two questions below are
 * asked of every render, so they live beside the union and not in the Shell's body.
 */

export type Screen =
  /** The home page (home/HomeScreen.tsx), which the app opens on and every way out comes back to. */
  | { name: 'list' }
  /** Every note as a grid of cards (notes/AllNotesScreen.tsx), from the home page's "All notes". */
  | { name: 'notes' }
  | {
      name: 'note';
      note: Note;
      /** The item to land on, `^anchor`, when the note was opened by a link that pointed inside it (core/boards.ts). */
      at?: string;
      /** A spoken instruction about this note ("hey Ghost, fix the spelling"), run on it as it opens; `key` tells one from the next. */
      ask?: SpokenAsk & { key: number };
      /** After Stop: the slower models check the take in the note itself (ai/useNoteReview.ts); `key` tells one review from the next. */
      review?: ReviewHandoff & { key: number };
    }
  | {
      name: 'capture';
      /** Each capture is a fresh mount, keyed, so a second press mid-capture cannot inherit the first one's microphone. */
      key: number;
      fromAssistant: boolean;
      /** How many times the side key has asked this capture to stop: a count, so each press is a change. */
      stop: number;
      /** Talking into this note, from its Speak: the words go here, and the capture comes back here. */
      noteId?: string;
    }
  /** Glyph Academy: markdown taught a mark at a time, open from Settings whenever it is wanted (academy/). */
  | { name: 'academy' };

/** A capture, fresh: from the side key (`fromAssistant`) or a Speak button, into `noteId` when it was one note's. */
export function captureScreen(fromAssistant: boolean, noteId?: string): Screen {
  return { name: 'capture', key: Date.now(), fromAssistant, stop: 0, ...(noteId ? { noteId } : {}) };
}

/** Where on the trail a screen is: the home page, the grid, or a note. A capture or the Academy is none. */
export function placeOf(screen: Screen): Place | null {
  if (screen.name === 'note') return notePlace(screen.note.id);
  if (screen.name === 'list') return 'list';
  if (screen.name === 'notes') return ALL_NOTES;
  return null;
}

/**
 * Whether a screen is one of the places, which carry the app's tab row (app.css .app-tabBar) and take a pane beside
 * the sidebar on a wide window. A capture and the Academy take the whole window, and the way out of them is their own.
 */
export function isPlace(screen: Screen): boolean {
  return placeOf(screen) !== null;
}

/** The id of the note on screen, or null when the screen is not a note. */
export function noteOnScreen(screen: Screen): string | null {
  return screen.name === 'note' ? screen.note.id : null;
}
