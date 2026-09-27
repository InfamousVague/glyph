/**
 * Which note's meeting is being recorded right now, for the shelf's "Recording" caption and its turning reels
 * (home/TapeShelf.tsx; docs/DESIGN.md §127 section 1).
 *
 * A meeting is recorded by a foreground service on Android (§127 section 3), and the page learns of it by asking
 * `GlyphHost.meetingState()` once a second while the shelf is visible, only on a binary that has it. Nothing can
 * record a meeting yet, so this answers null; section 3 fills it, and the caption that reads it is already built.
 */

/** The id of the note whose meeting is being recorded, or null while none is. */
export function useMeetingLive(): string | null {
  return null;
}
