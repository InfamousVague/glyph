import { useCallback, useEffect, useRef, type Dispatch, type SetStateAction } from 'react';
import type { ReviewHandoff } from '../ai/review.ts';
import { dropSummary, enqueueSummary } from '../ai/summaries.ts';
import type { SpokenAsk } from '../capture/CaptureScreen.tsx';
import type { CaptureLanding } from '../capture/landing.ts';
import { afterPendingDeletes } from '../capture/launch.ts';
import { meetingTitle } from '../capture/meeting.ts';
import { meetingStateNow, onMeetingEvent, useMeetingState, type MeetingEvent } from '../capture/meetingLive.ts';
import { freshTapeId, setTapeId } from '../core/clips.ts';
import { answerHost, forgetDiscardedOnHost, startMeetingOnHost } from '../core/host.ts';
import { isMobile } from '../core/platform.ts';
import { preferences, setPreferences } from '../core/preferences.ts';
import { createNote, deleteNote, getNote, newNoteId, type Note } from '../core/store.ts';
import { isTauri } from '../core/tauri.ts';
import { fileNewNote } from '../core/workspaces.ts';
import { captureScreen, meetingScreen, type Screen } from './screen.ts';

/**
 * How a capture begins and where the app goes when it ends: the Shell's half of the recorder (capture/CaptureScreen.tsx
 * is the recorder itself), and of a meeting (capture/MeetingScreen.tsx; docs/DESIGN.md §127 section 3).
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
 *
 * A meeting is the other kind of recording. On the Mac it is the page recorder in meeting mode. On Android it is the
 * phone's own service, and starting one is the page's to do in order: the note first (its date title, `source:
 * 'capture'`), its tape id, its place in `prefs.meetings`, its write-up queued as native, and only then the service
 * asked. The service can answer that the microphone has yet to be granted (the page waits for the activity's answer
 * and asks again), that a meeting is already being recorded (the page opens that one), or that it could not start,
 * and the service can fail after saying it started. Whatever the way, the UNDO HAS ONE OWNER: this hook deletes the
 * note, drops the preference and the job, and says why. The notification's Discard, with the app closed, is
 * remembered by the service until the page has done the same and said so (`forgetDiscarded`), which happens here as
 * well. And while a meeting is being recorded the microphone is taken, so every way into a capture - the side key,
 * a Speak button, the boot - opens the meeting screen instead.
 */

export interface CaptureRoute {
  /** A capture, from the side key (`fromAssistant`) or a Speak button, into `noteId` when it was one note's. */
  start: (fromAssistant: boolean, noteId?: string) => Promise<void>;
  /**
   * A capture over: filed, and the app on whatever comes next - the note with its run or review, the note the words
   * went into (`landing`), the note spoken into, or home.
   */
  finished: (note: Note | null, locked: boolean, review?: ReviewHandoff, ask?: SpokenAsk, landing?: CaptureLanding) => Promise<void>;
  /** A meeting: the Mac's recorder in meeting mode, or the phone's service with the meeting screen over it. */
  meeting: (fromAssistant?: boolean) => Promise<void>;
  /** The meeting screen for the meeting being recorded, when there is one: true when it opened. */
  showMeeting: (fromAssistant?: boolean) => boolean;
  /** The meeting screen left: home. */
  leftMeeting: () => void;
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
  /** A line to the person: why a meeting did not start. */
  say: (message: string) => void;
}

/** Said when the activity refused the microphone, and when the service could not say why it failed. */
export const MICROPHONE_REFUSED = 'Ghost.md needs the microphone to record a meeting.';
export const MEETING_FAILED = 'The meeting could not start.';

export function useCaptureRoute({ screen, setScreen, refresh, flushDeletes, atBoot, tooSoon, sayTooSoon, clearStage, say }: CaptureRouteOptions): CaptureRoute {
  // Read by the handlers registered once.
  const now = useRef({ screen, tooSoon, sayTooSoon, clearStage, say, refresh });
  now.current = { screen, tooSoon, sayTooSoon, clearStage, say, refresh };

  const showMeeting = useCallback(
    (fromAssistant = false) => {
      const live = meetingStateNow();
      if (!live?.recording || !live.noteId) return false;
      const current = now.current.screen;
      if (current.name === 'meeting' && current.noteId === live.noteId) return true;
      setScreen(meetingScreen(live.noteId, fromAssistant));
      return true;
    },
    [setScreen],
  );

  const start = useCallback(
    async (fromAssistant: boolean, noteId?: string) => {
      // A meeting being recorded holds the microphone: the way to it, not a second recording.
      if (showMeeting(fromAssistant)) return;
      await afterPendingDeletes(flushDeletes, () => setScreen(captureScreen(fromAssistant, noteId)));
    },
    [flushDeletes, setScreen, showMeeting],
  );

  const boot = useRef(atBoot);
  useEffect(() => {
    if (!boot.current) return;
    boot.current = false;
    void start(true);
  }, [start]);

  // The app opened with a meeting already being recorded (the notification's tap, or a launch while one runs): its
  // screen, once, as the boot would have shown a capture; a boot by the side key has asked already.
  const wasAtBoot = useRef(atBoot);
  const shownAtBoot = useRef(false);
  useEffect(() => {
    if (shownAtBoot.current) return;
    shownAtBoot.current = true;
    if (!wasAtBoot.current) showMeeting(false);
  }, [showMeeting]);

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
        // The meeting screen is up: Done and the notification stop a meeting, not the key.
        if (current.name === 'meeting') return;
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

  // ---- a meeting on the phone -----------------------------------------------------------------

  /** The meeting waiting for the microphone to be granted, to be asked for again once it is. */
  const pendingMeeting = useRef<{ id: string; title: string; fromAssistant: boolean } | null>(null);
  /** The meetings this page started, whose failure is this page's to undo. */
  const started = useRef(new Set<string>());

  /** Everything the start made, taken back, and the person told why. */
  const undo = useCallback(
    async (id: string, why: string | null) => {
      started.current.delete(id);
      if (pendingMeeting.current?.id === id) pendingMeeting.current = null;
      const rest = { ...preferences().meetings };
      delete rest[id];
      setPreferences({ meetings: rest });
      dropSummary(id);
      await deleteNote(id).catch(() => undefined);
      const current = now.current.screen;
      if (current.name === 'meeting' && current.noteId === id) setScreen({ name: 'list' });
      await now.current.refresh().catch(() => undefined);
      if (why) now.current.say(why);
    },
    [setScreen],
  );

  /** The service asked; what it answers decides what happens next. */
  const ask = useCallback(
    async (id: string, title: string, fromAssistant: boolean) => {
      const answer = startMeetingOnHost(id, title);
      if (answer === 'started') {
        pendingMeeting.current = null;
        started.current.add(id);
        setScreen(meetingScreen(id, fromAssistant));
        // The list read again, so the note is on the shelf, recording, when Back leaves the meeting screen.
        void now.current.refresh().catch(() => undefined);
        return;
      }
      if (answer === 'permission') {
        pendingMeeting.current = { id, title, fromAssistant };
        return;
      }
      if (answer === 'recording') {
        // One is being recorded already: that one, and not a second note for it.
        await undo(id, null);
        showMeeting(fromAssistant);
        return;
      }
      await undo(id, answer);
    },
    [setScreen, showMeeting, undo],
  );

  const meeting = useCallback(
    async (fromAssistant = false) => {
      // The Mac: the page recorder, with the dictation features off (capture/CaptureScreen.tsx `meeting`).
      if (isTauri() && !isMobile) {
        await afterPendingDeletes(flushDeletes, () => setScreen(captureScreen(fromAssistant, undefined, { meeting: true })));
        return;
      }
      if (showMeeting(fromAssistant)) return;
      const id = newNoteId();
      const startedAt = Date.now();
      const title = meetingTitle(startedAt);
      await createNote(id, `# ${title}\n`, 'capture');
      fileNewNote(id);
      setTapeId(id, freshTapeId());
      setPreferences({ meetings: { ...preferences().meetings, [id]: startedAt } });
      if (preferences().summaries !== 'off') enqueueSummary(id, 'meeting', { native: true });
      await ask(id, title, fromAssistant);
    },
    [ask, flushDeletes, setScreen, showMeeting],
  );

  // What the service says, for the meetings this page started: the microphone's answer, and a start that failed
  // after it was asked for; and, while its screen is up, a meeting that ended from the notification or the cap.
  useEffect(
    () =>
      onMeetingEvent((event: MeetingEvent) => {
        const pending = pendingMeeting.current;
        // The microphone's answer is the waiting meeting's: only one waits, so a push that names no note is its too.
        if (event.event === 'permission' && pending && (event.noteId === null || pending.id === event.noteId)) {
          if (event.granted) void ask(pending.id, pending.title, pending.fromAssistant);
          else void undo(pending.id, MICROPHONE_REFUSED);
          return;
        }
        const id = event.noteId;
        if (id === null) {
          if (event.event === 'open') showMeeting(false);
          return;
        }
        if (event.event === 'failed' && (started.current.has(id) || pending?.id === id)) {
          void undo(id, event.message ?? MEETING_FAILED);
          return;
        }
        if (event.event === 'started') started.current.delete(id);
        const current = now.current.screen;
        if ((event.event === 'stopped' || event.event === 'discarded') && current.name === 'meeting' && current.noteId === id) {
          setScreen({ name: 'list' });
          void now.current.refresh().catch(() => undefined);
        }
        if (event.event === 'open') showMeeting(false);
      }),
    [ask, setScreen, showMeeting, undo],
  );

  // A meeting the notification's Discard threw away with the app closed: its note goes, as Discard here would have
  // taken it, and the service is told so it can stop listing it.
  const live = useMeetingState();
  const discarded = live?.discarded;
  const handled = useRef(new Set<string>());
  useEffect(() => {
    if (!discarded?.length) return;
    for (const id of discarded) {
      if (handled.current.has(id)) continue;
      handled.current.add(id);
      void undo(id, null).then(() => forgetDiscardedOnHost(id));
    }
  }, [discarded, undo]);

  const leftMeeting = useCallback(() => setScreen({ name: 'list' }), [setScreen]);

  const finished = useCallback(
    async (note: Note | null, locked: boolean, review?: ReviewHandoff, ask?: SpokenAsk, landing?: CaptureLanding) => {
      // A spoken note lands in the workspace the list is showing, unless it is filed already; so do the notes it made.
      // A note that was there already and only had words put into it (`landing.blocks`) stays where it was filed, or
      // unfiled.
      const existed = note !== null && landing !== undefined && landing.blocks.length > 0 && !landing.made.includes(note.id);
      if (note && !existed) fileNewNote(note.id);
      for (const made of landing?.made ?? []) fileNewNote(made);
      await refresh();
      // Words a recording put into a note that was already there (capture/liveRoute.ts), or a card after Done confirmed:
      // that note opens, read fresh, with an Undo for what went in (editor/NoteScreen.tsx). Not over a locked phone.
      if (note && landing && !locked) {
        const fresh = await getNote(note.id).catch(() => null);
        const key = Date.now();
        setScreen({
          name: 'note',
          note: fresh ?? note,
          landing: { ...landing, key },
          ...(ask ? { ask: { ...ask, key } } : {}),
          ...(review ? { review: { ...review, key } } : {}),
        });
        return;
      }
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

  return { start, finished, meeting, showMeeting, leftMeeting };
}
