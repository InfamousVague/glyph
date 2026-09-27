import { kindWords } from '../ai/kinds.ts';
import type { SummariesState } from '../ai/summaries.ts';
import { summaryLine } from '../ai/summaryText.ts';
import type { Note } from '../core/store.ts';

/**
 * The one line under a cassette's title on the home page's shelf (home/TapeShelf.tsx): the first true thing in an
 * order, from a meeting being recorded down to the note's gist (docs/DESIGN.md §127 section 1, "The caption"). Pure,
 * beside the shelf that draws it, so each state and its place in the order is a test rather than a queue to stand up.
 */

/** A tape this long or longer says "Keep Ghost.md open" on a phone while the page works on it: the page's queues only run while the app is up. */
export const LONG_TAPE_MS = 600_000;

/** What the caption reads from, apart from the note: the queues, and whether this is a phone. */
export interface CaptionSources {
  /** The note whose meeting is being recorded, or null (home/useMeetingLive.ts). */
  recording: string | null;
  /** Notes whose better words are queued or running (capture/refine.ts). */
  refining: ReadonlySet<string>;
  /** The summary queue's four sets (ai/summaries.ts). */
  summaries: SummariesState;
  /** On a phone the page's queues stop when the app is left, so a long job asks for the app to stay open. */
  phone: boolean;
}

export type Caption =
  /** A meeting being recorded: the reels turn. */
  | { kind: 'recording' }
  /** The better words or a summary on their way, with the working spinner; `keepOpen` adds "Keep Ghost.md open". */
  | { kind: 'working'; word: string; keepOpen: boolean }
  /** The job waits for a language model that is not on the phone: "Needs a model" with the word to get one. */
  | { kind: 'needsModel' }
  /** The queue gave up: "The summary didn't come" with Try again. */
  | { kind: 'failed' }
  /** The summary's first line, or the gist. */
  | { kind: 'line'; text: string };

/** The caption for a tape: the first of the states that is true, or null for none. */
export function captionOf(note: Note, sources: CaptionSources, gist: string | undefined): Caption | null {
  const { summaries } = sources;
  // A long tape the page itself is working on: the service's write-up carries on with the app closed, the page's queues do not.
  const keepOpen = sources.phone && (note.recordingMs ?? 0) > LONG_TAPE_MS && !summaries.native.has(note.id);
  if (sources.recording === note.id) return { kind: 'recording' };
  if (sources.refining.has(note.id)) return { kind: 'working', word: 'Listening again', keepOpen };
  if (summaries.native.has(note.id)) return { kind: 'working', word: 'Writing up', keepOpen: false };
  if (summaries.pending.has(note.id)) return { kind: 'working', word: kindWords('summarize').doing, keepOpen };
  if (summaries.needsModel.has(note.id)) return { kind: 'needsModel' };
  if (summaries.failed.has(note.id)) return { kind: 'failed' };
  const line = summaryLine(note.body);
  if (line) return { kind: 'line', text: line };
  if (gist) return { kind: 'line', text: gist };
  return null;
}
