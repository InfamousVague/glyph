import { findKeyword } from './command.ts';
import { renderNote, type Segment } from './markdown.ts';
import { END, placeTake } from './place.ts';
import type { RefineJob } from './refine.ts';

/**
 * The better words, as the note will read with them: the pure half of the pass after a recording (capture/refine.ts
 * runs it).
 *
 * The larger model hears the take's whole recording again, commands, voice memos and all, so what it answers is not
 * yet the note's words: the stretches that were commands are taken out, a phrase the live words cut at "hey Ghost" is
 * cut there again, and the voice memos - which it never heard as words - are put back where they were said. Then the
 * take is rendered again from the result, into the note's text from before it where the recorder put the live words
 * (place.ts: its end, or its lists). By overlap rather than by match throughout, because the larger model hears the
 * phrases at slightly different times. Pure, so every rule is a test (refine.test.ts).
 */

/**
 * The note as it should read with the take's better phrases in place of the
 * live ones: the text before the take, then the take rendered again from the
 * new phrases - the first take titled, a later one not, as the recorder did.
 */
export function refinedBody(job: RefineJob, refined: readonly Segment[]): string {
  const take = renderNote(withClips(job, withoutCommands(job, refined)), '', { titled: job.titled }).markdown;
  return placeTake(job.baseBody, take, job.placing ?? END).body;
}

/** The better phrases with this take's voice memos back among them, in the order they were spoken. */
export function withClips(job: Pick<RefineJob, 'clips'>, refined: readonly Segment[]): Segment[] {
  const clips = job.clips ?? [];
  if (!clips.length) return [...refined];
  return [...refined, ...clips].sort((a, b) => a.startMs - b.startMs || a.endMs - b.endMs);
}

/** The recording's phrases with the take's replaced by the better ones. */
export function refinedSegments(job: RefineJob, refined: readonly Segment[]): Segment[] {
  return [...job.priorSegments.filter((s) => s.endMs <= job.fromMs), ...withClips(job, withoutCommands(job, refined))];
}

/** How much of `segment` the spans cover, 0 to 1. */
function covered(segment: Segment, spans: readonly { startMs: number; endMs: number }[]): number {
  const length = Math.max(1, segment.endMs - segment.startMs);
  const overlap = spans.reduce((sum, span) => sum + Math.max(0, Math.min(span.endMs, segment.endMs) - Math.max(span.startMs, segment.startMs)), 0);
  return overlap / length;
}

/**
 * The better phrases with the take's commands taken out: a phrase mostly
 * inside a command's stretch goes, and one that overlaps a phrase the live
 * words cut at "Glyph" is cut there too. The larger model hears the phrases
 * at slightly different times, so it is by overlap, not by match.
 */
export function withoutCommands(job: Pick<RefineJob, 'skip' | 'keywordAt' | 'live'>, refined: readonly Segment[]): Segment[] {
  const skip = job.skip ?? [];
  const keywordAt = job.keywordAt ?? [];
  const live = job.live;
  if (live) {
    // The live reader kept the take's phrases itself, a command's payload among them: a better phrase that touches a
    // command is replaced by the live phrases inside it, so it neither erases what the command sent nor brings the
    // command back.
    const spans = [...skip, ...keywordAt];
    return refined.flatMap((segment) => {
      if (!spans.some((span) => Math.min(span.endMs, segment.endMs) > Math.max(span.startMs, segment.startMs))) return [segment];
      return live.filter((phrase) => {
        const middle = (phrase.startMs + phrase.endMs) / 2;
        return middle >= segment.startMs && middle <= segment.endMs;
      });
    });
  }
  return refined.flatMap((segment) => {
    if (skip.length && covered(segment, skip) >= 0.5) return [];
    if (keywordAt.length && covered(segment, keywordAt) > 0) {
      const found = findKeyword(segment.text);
      if (found) return found.before ? [{ ...segment, text: found.before }] : [];
    }
    return [segment];
  });
}
