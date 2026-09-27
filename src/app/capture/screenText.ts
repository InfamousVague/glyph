import { noteTitle } from '../core/noteTitle.ts';
import { capitalise } from '../core/text.ts';
import type { Phase } from './useCaptureSession.ts';

/**
 * The recorder's own words, the ones that are not the note: the line at the top, which says where the words are going
 * or what is holding them up, and the line under the empty page, which says how this recording ends.
 *
 * Pure, so each state's line is a test; CaptureScreen.tsx draws them.
 */

/**
 * What the top line says while something stands between the person and the recording - it has not started, it could
 * not, the voice model is downloading, it is saving, or it failed before a word - or null when it is listening, and the
 * line says where the words are going instead (`whereLine`).
 */
export function statusLine({
  phase,
  error,
  download,
  heardWords,
}: {
  phase: Phase;
  error: string | null;
  download: { received: number; total: number } | null;
  /** Whether any phrase has been committed: an error after the first words is the diagnostics line's to show. */
  heardWords: boolean;
}): string | null {
  if (phase === 'failed') return error ?? 'Could not start';
  if (download) return `Downloading voice model ${Math.round(download.received / 1e6)} / ${Math.round(download.total / 1e6)} MB`;
  if (phase === 'starting') return 'Starting';
  if (phase === 'finishing') return 'Saving';
  if (error && !heardWords) return `Problem: ${error}`;
  return null;
}

/**
 * Where the words are going: a new note, one named on a card and made at Done (`named`), or the note being written
 * to - named, except over the lock screen, where a note a command switched to (`routed`) is only "the note you named".
 * A meeting (capture/meeting.ts) is recorded, not read, and its line says only that.
 */
export function whereLine(
  target: { body: string } | null,
  locked: boolean,
  { routed = false, named = null, meeting = false }: { routed?: boolean; named?: string | null; meeting?: boolean } = {},
): string {
  if (meeting) return 'Meeting';
  if (!target) return named !== null && !locked ? `New note “${named}”` : 'New note';
  if (locked) return routed ? 'Adding to the note you named' : 'Adding to your last note';
  return `Adding to “${noteTitle(target.body)}”`;
}

/**
 * What ends this recording, in a line under "Start talking.": the side key when this phone lets it stop one (a press,
 * or the hold that opened it), going quiet when that is switched on, and otherwise Done.
 */
export function stopHint(fromSideKey: boolean, pressStops: boolean, quietStops: boolean): string {
  const key = pressStops ? 'press the side key' : fromSideKey ? 'hold the side key again' : null;
  if (quietStops) return key ? `Stop talking to finish, or ${key}.` : 'Stop talking to finish, or tap Done.';
  if (key) return `${capitalise(key)} to stop.`;
  return 'Tap Done to stop.';
}
