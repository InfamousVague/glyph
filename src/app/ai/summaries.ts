import { externalStore } from '../core/externalStore.ts';

/**
 * The summary queue, as the home page's shelf reads it (home/TapeShelf.tsx): which notes have a summary queued or
 * running, which are being written up natively, which failed, and which wait for a language model that is not on
 * the phone. The shelf's captions come from these four sets (docs/DESIGN.md §127 section 1).
 *
 * The queue itself is section 2 of §127, which fills this module: the jobs in localStorage, the holds, the runs and
 * the toast. Until then every set is empty and Try again has nothing to re-queue, so the captions that read them are
 * built and tested now and only start to show once the queue exists.
 */

export interface SummariesState {
  /** Notes whose page summary is queued or running. */
  pending: ReadonlySet<string>;
  /** Notes a native write-up is running for (§127 section 4). */
  native: ReadonlySet<string>;
  /** Notes whose summary the queue gave up on, for the caption's Try again. */
  failed: ReadonlySet<string>;
  /** Notes whose job waits for a language model that is not on the phone. */
  needsModel: ReadonlySet<string>;
}

const NONE: SummariesState = { pending: new Set(), native: new Set(), failed: new Set(), needsModel: new Set() };

const summaries = externalStore<SummariesState>(NONE, { server: () => NONE });

export const useSummaries = summaries.use;

/** Try again, from the shelf's caption: the note's job back in the queue with its tries reset. Section 2 fills it. */
export function retrySummary(_id: string): void {
  // No queue yet: nothing to put back. Section 2 of §127 resets the job's tries and kicks the runner here.
}
