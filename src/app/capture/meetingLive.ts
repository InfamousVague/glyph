import { useSyncExternalStore } from 'react';
import { externalStore } from '../core/externalStore.ts';
import { answerHost, canNotify as hostCanNotify, meetingStateJson } from '../core/host.ts';
import { writeUpRunningNow } from '../core/recordings.ts';
import { NOTES_CHANGED } from '../core/store.ts';

/**
 * The meeting being recorded, as the page knows it: one store every screen reads (docs/DESIGN.md §127 section 3).
 *
 * A meeting on Android is recorded by a foreground service (capture/MeetingService.kt), which outlives the page: the
 * screen can go off and the app can be left, and the microphone stays open with only the notification showing (a
 * swipe from Recents stops the meeting, and what was recorded is written up).
 * So the page does not hold the state, it asks for it. `GlyphHost.meetingState()` is read once a second while the
 * page is visible and something is listening (the shelf, the meeting screen, the capture route), at once when the
 * page comes back to the front, and whenever the service says something has changed (`window.__glyph.meeting`,
 * registered here once, and fanned out to whoever asked with `onMeetingEvent`). Nothing is asked of a binary without
 * the service: the poll starts only where the method exists, and everywhere else the state is null.
 *
 * The activity's own `refresh` call, which it makes as it resumes, has one owner (the notes store, core/store.ts,
 * since `answerHost` keeps one answer a name); its echo is the notes-changed event, and that is listened for here,
 * beside the page's own visibility.
 *
 * Whether Ghost.md may notify is read the same way (`canNotify`), again on the prompt's answer (`notified`) and on
 * every return to the front, since the person can turn notifications off in the phone's settings while the app is
 * closed. The two questions the rest of the page asks are here too: which note is being recorded (home/useMeetingLive.ts
 * for the shelf), and whether a write-up is running (`writeUpRunning`, for the refine queue, which wants the same
 * speech model).
 */

export interface MeetingState {
  /** A meeting is being recorded now. */
  recording: boolean;
  /** Its note, its title and when it began, while one is. */
  noteId: string | null;
  title: string | null;
  startedAt: number | null;
  elapsedMs: number;
  /** Another app took the microphone: the file keeps growing with silence. */
  silenced: boolean;
  /** The note the service is writing up now, or null. */
  writingUp: string | null;
  /** Notes the notification's Discard threw away that the page has not yet deleted (shell/useCaptureRoute.ts). */
  discarded: string[];
}

export type MeetingEventName = 'started' | 'silenced' | 'sounding' | 'stopped' | 'discarded' | 'failed' | 'permission' | 'asked' | 'open';

/** What the service says (capture/MeetingService.kt), as `window.__glyph.meeting` carries it. */
export interface MeetingEvent {
  event: MeetingEventName;
  /**
   * The meeting's note. Null only on the two the activity says without one in hand (MainActivity.kt): the
   * microphone's answer (`permission`, which is the waiting meeting's) and a tap on the recording notification (`open`).
   */
  noteId: string | null;
  elapsedMs: number;
  /** With `stopped`: Done or the notification's Stop, the cap, a read error, or a meeting a kill left that was finished at launch. */
  reason?: 'done' | 'notification' | 'cap' | 'error' | 'died' | null;
  /** With `permission`: whether the microphone was granted. */
  granted?: boolean;
  /** With `failed`: the app's-voice line to say. */
  message?: string;
}

const NONE: MeetingState = { recording: false, noteId: null, title: null, startedAt: null, elapsedMs: 0, silenced: false, writingUp: null, discarded: [] };

const state = externalStore<MeetingState | null>(null, { server: () => null });
const notify = externalStore<boolean>(false, { server: () => false });
const listeners = new Set<(event: MeetingEvent) => void>();

const str = (value: unknown): string | null => (typeof value === 'string' ? value : null);
const num = (value: unknown): number | null => (typeof value === 'number' && Number.isFinite(value) ? value : null);

/** The service's JSON as a state, or null for anything that is not one: an older host answers nothing this shape. */
export function parseMeetingState(raw: unknown): MeetingState | null {
  if (!raw || typeof raw !== 'object') return null;
  const got = raw as Record<string, unknown>;
  if (typeof got.recording !== 'boolean') return null;
  return {
    recording: got.recording,
    noteId: str(got.noteId),
    title: str(got.title),
    startedAt: num(got.startedAt),
    elapsedMs: num(got.elapsedMs) ?? 0,
    silenced: got.silenced === true,
    writingUp: str(got.writingUp),
    discarded: Array.isArray(got.discarded) ? got.discarded.filter((id): id is string => typeof id === 'string') : [],
  };
}

/** A `meeting` push as an event, or null for one this build cannot read. */
export function parseMeetingEvent(json: string): MeetingEvent | null {
  try {
    const got = JSON.parse(json) as Record<string, unknown>;
    const event = str(got.event) as MeetingEventName | null;
    const noteId = str(got.noteId);
    if (!event || (!noteId && event !== 'permission' && event !== 'open')) return null;
    return {
      event,
      noteId,
      elapsedMs: num(got.elapsedMs) ?? 0,
      ...(got.reason !== undefined ? { reason: str(got.reason) as MeetingEvent['reason'] } : {}),
      ...(typeof got.granted === 'boolean' ? { granted: got.granted } : {}),
      ...(typeof got.message === 'string' ? { message: got.message } : {}),
    };
  } catch {
    return null;
  }
}

/** Whether this host can be asked at all. */
function hostHasMeetings(): boolean {
  return typeof window !== 'undefined' && typeof window.GlyphHost?.meetingState === 'function';
}

/** Ask the service now, keep the answer, and answer it: null where there is no service to ask. */
export function readMeetingState(): MeetingState | null {
  if (!hostHasMeetings()) return state.get();
  const json = meetingStateJson();
  let parsed: MeetingState | null = null;
  if (json !== null) {
    try {
      parsed = parseMeetingState(JSON.parse(json));
    } catch {
      parsed = null;
    }
  }
  // A new object each read would tell every listener every second; only a change does.
  const was = state.get();
  const next = parsed ?? NONE;
  if (!was || JSON.stringify(was) !== JSON.stringify(next)) state.set(next);
  return state.get();
}

/** The state as it is now, fresh from the service where there is one: for callers outside React. */
export function meetingStateNow(): MeetingState | null {
  return readMeetingState();
}

/** Whether Ghost.md may notify, fresh from the host, and kept for the screens that follow it. */
export function canNotifyNow(): boolean {
  const can = hostCanNotify();
  notify.set(can);
  return can;
}

export const useCanNotify = notify.use;

const notifiedListeners = new Set<() => void>();

/** Hear the meeting's own notification prompt being answered, whichever way; answers the way to stop. */
export function onNotified(listener: () => void): () => void {
  notifiedListeners.add(listener);
  return () => {
    notifiedListeners.delete(listener);
  };
}

/** Whether a write-up is running, by the last look at the jobs and the service: the refine queue holds while one is. */
export function writeUpRunning(): boolean {
  return writeUpRunningNow() || state.get()?.writingUp != null;
}

/** Hear every `meeting` push; answers the way to stop. */
export function onMeetingEvent(listener: (event: MeetingEvent) => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** What a push says about the state, before the service is asked again: enough for a page with no service to ask. */
function applyEvent(event: MeetingEvent): void {
  const was = state.get() ?? NONE;
  switch (event.event) {
    case 'started':
      state.set({ ...was, recording: true, noteId: event.noteId, startedAt: was.startedAt ?? Date.now() - event.elapsedMs, elapsedMs: event.elapsedMs, silenced: false });
      break;
    case 'silenced':
    case 'sounding':
      state.set({ ...was, silenced: event.event === 'silenced', elapsedMs: event.elapsedMs });
      break;
    case 'stopped':
      state.set({ ...was, recording: false, noteId: null, title: null, startedAt: null, elapsedMs: 0, silenced: false, writingUp: event.noteId });
      break;
    case 'failed':
      state.set({ ...was, recording: false, noteId: null, title: null, startedAt: null, elapsedMs: 0, silenced: false });
      break;
    case 'discarded':
      state.set({ ...was, recording: false, noteId: null, title: null, startedAt: null, elapsedMs: 0, silenced: false, discarded: event.noteId ? [...new Set([...was.discarded, event.noteId])] : was.discarded });
      break;
    default:
      break;
  }
}

/** The service said something: the state follows it, the service is asked again, and every listener hears it. */
function heard(json: string): void {
  const event = parseMeetingEvent(json);
  if (!event) return;
  applyEvent(event);
  readMeetingState();
  for (const listener of listeners) listener(event);
}

// ---- polling ------------------------------------------------------------------------------------

const POLL_MS = 1000;
let subscribers = 0;
let timer = 0;

function poll(): void {
  if (typeof document === 'undefined' || document.visibilityState !== 'visible' || !hostHasMeetings()) return;
  readMeetingState();
}

function startPolling(): void {
  if (timer || typeof window === 'undefined') return;
  poll();
  timer = window.setInterval(poll, POLL_MS);
}

function stopPolling(): void {
  if (!timer) return;
  window.clearInterval(timer);
  timer = 0;
}

/** The store's subscribe, with the poll running while anyone listens. */
function subscribe(listener: () => void): () => void {
  const off = state.subscribe(listener);
  subscribers += 1;
  if (subscribers === 1) startPolling();
  return () => {
    off();
    subscribers -= 1;
    if (subscribers === 0) stopPolling();
  };
}

const none = () => null;

/** The meeting's state, live: null where nothing can record one. */
export function useMeetingState(): MeetingState | null {
  return useSyncExternalStore(subscribe, state.get, none);
}

// ---- wiring -------------------------------------------------------------------------------------

if (typeof window !== 'undefined') {
  answerHost('meeting', heard);
  answerHost('notified', () => {
    canNotifyNow();
    for (const listener of notifiedListeners) listener();
  });
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    if (hostHasMeetings()) {
      readMeetingState();
      canNotifyNow();
    }
  });
  // The activity's refresh, as the notes store echoes it: the service may have moved while the app was away.
  window.addEventListener(NOTES_CHANGED, () => {
    if (hostHasMeetings()) readMeetingState();
  });
}

/** For tests: the store as a test wants it. */
export function setMeetingStateForTests(next: MeetingState | null): void {
  state.set(next);
}
