import type { Note } from '../core/store.ts';

/**
 * The Tapes row's sums (settings/RecordingPane.tsx; docs/DESIGN.md §127 section 6): how much room the recordings take
 * on this device, said from their lengths rather than measured (16 kHz, 16-bit, mono: an hour is about 115 MB), and
 * which of them the row offers to remove the audio of. Pure, so the pane's words can be tested without a store.
 */

/** Bytes a recording of one millisecond takes: 16 kHz, 16-bit, mono. */
export const BYTES_PER_MS = 32;
/** A tape older than this is one the row offers to remove the audio of. */
export const OLD_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * The tapes among `notes` whose audio is on this device: a length, and not `away` (its audio removed by this row, or
 * answered 404 by the `rec` scheme, which is a synced note whose audio stayed on the device that made it). The words
 * "on this device" are only true of these.
 */
export function tapesHere(notes: readonly Note[], away: (id: string) => boolean): Note[] {
  return notes.filter((note) => (note.recordingMs ?? 0) > 0 && !away(note.id));
}

/** How much room the tapes among `notes` take, from their lengths. */
export function tapeBytes(notes: readonly Note[]): number {
  return notes.reduce((sum, note) => sum + Math.max(0, note.recordingMs ?? 0) * BYTES_PER_MS, 0);
}

/** "2.3 GB" or "410 MB": how much room the tapes take, never less than a megabyte once there is one. */
export function tapeSize(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  return `${Math.max(1, Math.round(bytes / 1e6))} MB`;
}

/** The notes whose audio the row would remove: a tape, not archived, made more than a month before `now`. */
export function oldTapes(notes: readonly Note[], now: number): Note[] {
  return notes.filter((note) => (note.recordingMs ?? 0) > 0 && !note.archivedAt && now - note.createdAt > OLD_MS);
}
