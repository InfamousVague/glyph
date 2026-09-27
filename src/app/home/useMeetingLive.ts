import { useMeetingState } from '../capture/meetingLive.ts';

/**
 * Which note's meeting is being recorded right now, for the shelf's "Recording" caption and its turning reels
 * (home/TapeShelf.tsx; docs/DESIGN.md §127 section 1), and for the home page to put that tape first (home/dashboard.ts).
 *
 * A meeting is recorded by a foreground service on Android (§127 section 3), and the page learns of it from the one
 * store that asks the service (capture/meetingLive.ts): null wherever nothing can record one.
 */

/** The id of the note whose meeting is being recorded, or null while none is. */
export function useMeetingLive(): string | null {
  const state = useMeetingState();
  return state?.recording ? state.noteId : null;
}
