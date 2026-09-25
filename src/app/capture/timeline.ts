import type { Segment } from './markdown.ts';
import type { Span } from './takeTypes.ts';

/**
 * A take's place on the tape of the note it is kept with.
 *
 * A take's phrases, commands and voice memos are timed from the start of the take. Its sound is kept under the note's
 * id (capture_stop `recordAs`), on the end of the note's own tape when the note still has one (`appendsTo`), so
 * everything stored against the tape - its phrases, the clips' marks, the better words' job - is on that longer
 * timeline, later by the length the tape already had (`onTape`). One that forgot the shift would play the wrong
 * sound, and the better words would listen to the wrong stretch. Pure, so each rule is a test.
 */

/** `spans` moved `by` ms later, keeping whatever else each one carries (a clip's mark, a phrase's words). */
export function shifted<T extends Span>(spans: readonly T[], by: number): T[] {
  return spans.map((span) => ({ ...span, startMs: span.startMs + by, endMs: span.endMs + by }));
}

/** The part of a note its tape is read from: how long the tape is, and the phrases timed against it. */
export interface TapedNote {
  recordingMs?: number | null;
  segments?: readonly Segment[] | null;
}

/**
 * Whether a take's sound goes on the end of `continued`'s tape: only onto a tape the note still has. A recording
 * removed from the note leaves its file behind, and a take added after it starts the file afresh rather than playing
 * after the removed sound. A new note (null) starts a tape of its own.
 */
export function appendsTo(continued: TapedNote | null): boolean {
  return continued !== null && (continued.recordingMs ?? 0) > 0;
}

/** Where a take's pieces sit on the tape it was kept on. */
export interface OnTape {
  /** Where the take starts on the tape: the length the continued note's tape already had, or 0. */
  fromMs: number;
  /** The continued note's phrases from before this take, as they were. */
  prior: Segment[];
  /** Every phrase on the tape: the prior ones, then this take's, moved after them. */
  segments: Segment[];
  /** The stretches that were commands, for the better words to leave out. */
  skip: Span[];
  /** The voice memos this take left, as their marks. */
  clips: Segment[];
  /** Phrases that were words and then "Glyph", for the better words to keep only what came before it. */
  keywordAt: Span[];
}

/** The take's phrases (`spoken`, with any the stopped decode added), commands and clips, moved onto the tape of `continued`. */
export function onTape(
  continued: TapedNote | null,
  take: { readonly commandSpans: readonly Span[]; readonly clips: readonly Segment[]; readonly keywordSpans: readonly Span[] },
  spoken: readonly Segment[],
): OnTape {
  const fromMs = continued?.recordingMs ?? 0;
  const prior = [...(continued?.segments ?? [])];
  return {
    fromMs,
    prior,
    segments: [...prior, ...shifted(spoken, fromMs)],
    skip: shifted(take.commandSpans, fromMs),
    clips: shifted(take.clips, fromMs),
    keywordAt: shifted(take.keywordSpans, fromMs),
  };
}
