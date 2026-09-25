import { useCallback, useEffect, useRef, type Dispatch, type SetStateAction } from 'react';
import type { ReviewHandoff } from '../ai/review.ts';
import type { SpokenAsk } from '../capture/CaptureScreen.tsx';
import { afterPendingDeletes } from '../capture/launch.ts';
import { answerHost } from '../core/host.ts';
import { fileNewNote } from '../core/workspaces.ts';
import { getNote, type Note } from '../core/store.ts';
import { captureScreen, type Screen } from './screen.ts';

/**
 * How a capture begins and where the app goes when it ends: the Shell's half of the recorder (capture/CaptureScreen.tsx
 * is the recorder itself).
 *
 * A capture can begin several ways, and all of them arrive at the same screen: the side key while Glyph is closed
 * (read once at boot, core/host.ts `takeCaptureLaunch`), the side key while Glyph is open (pushed by the activity into
 * `window.__glyph.capture`), and a Speak button - the home dock's, the sidebar's foot, the drawer's, the palette's, the
 * guide's Try, and a note's own. Each capture is a fresh mount (shell/screen.ts `captureScreen`), so a second press
 * mid-capture cannot inherit the first one's microphone.
 *
 * Every one of them waits for the deferred deletes first (notes/useNoteActions.ts): the recorder reads its targets as
 * it mounts - a note to continue, the titles a command could mean - and a note deleted a moment ago must not be one of
 * them (capture/launch.ts).
 */

export interface CaptureRoute {
  /** A capture, from the side key (`fromAssistant`) or a Speak button, into `noteId` when it was one note's. */
  start: (fromAssistant: boolean, noteId?: string) => Promise<void>;
  /** A capture over: filed, and the app on whatever comes next - the note with its run or review, the note spoken into, or home. */
  finished: (note: Note | null, locked: boolean, review?: ReviewHandoff, ask?: SpokenAsk) => Promise<void>;
}

export interface CaptureRouteOptions {
  screen: Screen;
  setScreen: Dispatch<SetStateAction<Screen>>;
  refresh: () => Promise<void>;
  /** Makes every deferred delete final (notes/useNoteActions.ts `flushDeletes`). */
  flushDeletes: () => Promise<void>;
  /** The side key launched the app, and a recording is what it asked for: the capture starts as the app does. */
  atBoot: boolean;
  /** The side key pressed while the guide is on a page still to be read: "Not yet", not a recording (guide/tooSoon.ts). */
  tooSoon: () => boolean;
  sayTooSoon: () => void;
  /** Everything over the screen put away - the sheet, the walkthrough - so the bare recorder is all that is left. */
  clearStage: () => void;
}

export function useCaptureRoute({ screen, setScreen, refresh, flushDeletes, atBoot, tooSoon, sayTooSoon, clearStage }: CaptureRouteOptions): CaptureRoute {
  const start = useCallback(
    async (fromAssistant: boolean, noteId?: string) => {
      await afterPendingDeletes(flushDeletes, () => setScreen(captureScreen(fromAssistant, noteId)));
    },
    [flushDeletes, setScreen],
  );

  const boot = useRef(atBoot);
  useEffect(() => {
    if (!boot.current) return;
    boot.current = false;
    void start(true);
  }, [start]);

  // Read by the side-key handler, which is registered once.
  const now = useRef({ screen, tooSoon, sayTooSoon, clearStage });
  now.current = { screen, tooSoon, sayTooSoon, clearStage };

  // The side key, while Glyph is already open.
  //
  // During a capture it is the stop button: holding the key again saves, the
  // way pressing a tape recorder's key a second time does. (Letting go cannot
  // stop it - Android tells the assistant app when the key is held, and never
  // when it is released.)
  //
  // Otherwise it clears the stage: the sheet, the walkthrough, an open note
  // (whose editor flushes as it unmounts) and the keyboard all go, so the bare
  // recorder is the only thing on screen - and when it ends, the app lands on
  // the note or the list, not back in a menu.
  useEffect(
    () =>
      answerHost('capture', () => {
        const current = now.current.screen;
        if (current.name === 'capture') {
          setScreen({ ...current, stop: current.stop + 1 });
          return;
        }
        // On a reading page of the guide the key is too soon: the line, not a recording.
        if (now.current.tooSoon()) {
          now.current.sayTooSoon();
          return;
        }
        if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
        now.current.clearStage();
        void start(true);
      }),
    [start, setScreen],
  );

  const finished = useCallback(
    async (note: Note | null, locked: boolean, review?: ReviewHandoff, ask?: SpokenAsk) => {
      // A spoken note lands in the workspace the list is showing, unless it is filed already.
      if (note) fileNewNote(note.id);
      await refresh();
      // An instruction spoken into a note: the note opens with the run on it (ai/instruction.ts, editor/NoteScreen.tsx).
      if (note && ask) {
        const fresh = await getNote(note.id).catch(() => null);
        setScreen({ name: 'note', note: fresh ?? note, ask: { ...ask, key: Date.now() } });
        return;
      }
      // The review after a recording runs in the note (ai/useNoteReview.ts), read fresh, since its words just changed.
      if (note && review) {
        const fresh = await getNote(note.id).catch(() => null);
        setScreen({ name: 'note', note: fresh ?? note, review: { ...review, key: Date.now() } });
        return;
      }
      // Talking into a note from the note: back to that note, read fresh, since
      // its words just changed (and a Formatted view compares against them).
      // Otherwise the list, the new note at its top: reading it back is a tap
      // away, and a locked phone has already stepped back behind its lock
      // screen, so nothing of the note is shown to whoever is holding it.
      const current = now.current.screen;
      const from = current.name === 'capture' ? current.noteId : undefined;
      if (from && !locked) {
        const fresh = await getNote(note?.id ?? from).catch(() => null);
        if (fresh) {
          setScreen({ name: 'note', note: fresh });
          return;
        }
      }
      setScreen({ name: 'list' });
    },
    [refresh, setScreen],
  );

  return { start, finished };
}
