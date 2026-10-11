import type { ReviewHandoff } from '../ai/review.ts';
import type { SpokenAsk } from '../capture/CaptureScreen.tsx';
import type { CaptureLanding } from '../capture/landing.ts';
import type { Placing } from '../capture/place.ts';
import type { Jump } from '../core/live/presence.ts';
import type { Note } from '../core/store.ts';
import { ALL_NOTES, notePlace, type Place } from '../notes/visited.ts';

/**
 * Which screen is up: the one piece of state the app would have bought a router to hold (App.tsx says why it did
 * not).
 *
 * Seven screens, each a member of one union: the home page, the All notes grid, a note, a capture, a meeting being
 * recorded by the phone's service, the Academy and an organization's dashboard (docs/TEAMS.md, D6). Everything else a
 * person sees - Settings and an organization's settings, the notifications drawer, the guide, the + sheet, the
 * sidebar's card, the aside, the palette - is a sheet or a card over whichever of these is up, and is held beside it in
 * the Shell rather than in here.
 *
 * Four of the seven are places (notes/visited.ts): the home page, the grid, a note and an organization's dashboard are
 * where a person goes, so they are where the tab row is drawn and where a wide window splits into panes; the first
 * three are on the trail the arrows walk. A capture, a meeting and the Academy are things a person is doing, each the
 * whole screen with its own way out. The questions below are asked of every render, so they live beside the union and
 * not in the Shell's body.
 */

export type Screen =
  /** The home page (home/HomeScreen.tsx), which the app opens on and every way out comes back to. */
  | { name: 'list' }
  /**
   * Every note as a grid of cards (notes/AllNotesScreen.tsx), from the home page's "All notes". Opened with `tapes`
   * from the Tapes heading's "See all", it shows only the notes with a recording (docs/DESIGN.md §127, §132).
   */
  | { name: 'notes'; tapes?: boolean }
  | {
      name: 'note';
      note: Note;
      /** The item to land on, `^anchor`, when the note was opened by a link that pointed inside it (core/boards.ts). */
      at?: string;
      /** A spoken instruction about this note ("hey Ghost, fix the spelling"), run on it as it opens; `key` tells one from the next. */
      ask?: SpokenAsk & { key: number };
      /** After Stop: the slower models check the take in the note itself (ai/useNoteReview.ts); `key` tells one review from the next. */
      review?: ReviewHandoff & { key: number };
      /** What a recording just wrote into this note, for its Undo (capture/landing.ts); `key` tells one from the next. */
      landing?: CaptureLanding & { key: number };
      /**
       * A note just made, opened to be written in: the caret here, the editor focused and the keyboard up where the phone
       * allows it. A blank note's line 1 (App.tsx `newNote`), or `end`, the end of its words, where a journal's entry's
       * first word goes (`newEntry`). A note opened to be read takes no focus.
       */
      caret?: number | 'end';
      /** A member's caret, or their spot on a canvas, to open at: the dashboard's Jump to cursor (docs/SHARED.md, S6, S9). */
      cursor?: Jump;
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
      /** Where in that note, when its opener says (capture/CaptureScreen.tsx `placing`): a journal's entry said aloud. */
      placing?: Placing;
      /** A meeting in the page recorder (the Mac; docs/DESIGN.md §127 section 3): recorded, not read, and written up after. */
      meeting?: true;
    }
  /**
   * A meeting being recorded by the phone's own service (capture/MeetingScreen.tsx; §127 section 3): the cassette
   * turning, Done and Discard, and no note words, since the side key can open it over the lock screen.
   */
  | {
      name: 'meeting';
      noteId: string;
      fromAssistant: boolean;
      /** Each opening is a fresh mount, keyed, as a capture's is. */
      key: number;
    }
  /** Glyph Academy: markdown taught a mark at a time, open from Settings whenever it is wanted (academy/). */
  | { name: 'academy' }
  /**
   * An organization's dashboard (notes/OrganizationScreen.tsx): its members, the notes filed in its workspace and its
   * news, with its settings behind a cog. From the top bar's picker, a notification about it, an invitation accepted,
   * one just made, its workspace's pill or a link; its arrow and the phone's back gesture go home. With `page` it is
   * the organization's audit log instead (notes/OrganizationLog.tsx): every change to every note filed in its
   * workspace with the team's news, a page under the dashboard, whose arrow goes back to it.
   */
  | { name: 'organization'; orgId: string; page?: 'log' };

/**
 * A capture, fresh: from the side key (`fromAssistant`) or a Speak button, into `noteId` when it was one note's, at
 * `placing` when its opener says where in it; a meeting on the Mac with `meeting`.
 */
export function captureScreen(fromAssistant: boolean, noteId?: string, { meeting = false, placing }: { meeting?: boolean; placing?: Placing } = {}): Screen {
  return { name: 'capture', key: Date.now(), fromAssistant, stop: 0, ...(noteId ? { noteId } : {}), ...(noteId && placing ? { placing } : {}), ...(meeting ? { meeting: true } : {}) };
}

/** The meeting screen for the note the service is recording into, from the side key (`fromAssistant`) or the page. */
export function meetingScreen(noteId: string, fromAssistant: boolean): Screen {
  return { name: 'meeting', noteId, fromAssistant, key: Date.now() };
}

/** Whether a screen is the whole window with a microphone behind it: a capture or a meeting, over which nothing else is drawn. */
export function isRecording(screen: Screen): boolean {
  return screen.name === 'capture' || screen.name === 'meeting';
}

/**
 * Where on the trail a screen is: the home page, the grid, or a note. A capture, the Academy and an organization's
 * dashboard are none: the arrows never walk into them, whose way out is their own arrow home.
 */
export function placeOf(screen: Screen): Place | null {
  if (screen.name === 'note') return notePlace(screen.note.id);
  if (screen.name === 'list') return 'list';
  if (screen.name === 'notes') return ALL_NOTES;
  return null;
}

/**
 * Whether a screen is one of the places, which carry the app's tab row (app.css .app-tabBar) and take a pane beside
 * the sidebar on a wide window: the three on the trail, and an organization's dashboard, drawn where All notes is. The
 * notifications are a drawer over any of them (notes/NotificationsDrawer.tsx), not a screen. A capture and the Academy
 * take the whole window, and the way out of them is their own.
 */
export function isPlace(screen: Screen): boolean {
  return placeOf(screen) !== null || screen.name === 'organization';
}

/** The id of the note on screen, or null when the screen is not a note. */
export function noteOnScreen(screen: Screen): string | null {
  return screen.name === 'note' ? screen.note.id : null;
}
