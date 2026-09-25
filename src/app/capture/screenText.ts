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

/** Where the words are going: a new note, or the note being continued - named, except over the lock screen. */
export function whereLine(target: { body: string } | null, locked: boolean): string {
  if (!target) return 'New note';
  return locked ? 'Adding to your last note' : `Adding to “${noteTitle(target.body)}”`;
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
