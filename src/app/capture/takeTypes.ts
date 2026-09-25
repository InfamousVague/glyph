import type { Candidate } from './route.ts';

/**
 * The shapes a take (capture/take.ts) is written in terms of, which its host, its offers and the tape's timeline all
 * share: the note it can be written to, a note a command can name, and a stretch of its recording.
 *
 * The take is generic in its note: the recorder runs one over the real notes (core/store.ts `Note`), and the voice
 * suite over an in-memory store (capture/voiceSuite.ts), so all a take asks of a note is its id and its body.
 */

/** A note as a take sees it: all it reads is the id and the body. */
export interface TakeNote {
  id: string;
  body: string;
}

/** A note a command can name, by the title the command list knows it by, with the note itself. */
export type TakeCandidate<N extends TakeNote> = Candidate & { note: N };

/** A stretch of the take's recording, in ms on its own timeline. */
export interface Span {
  startMs: number;
  endMs: number;
}
