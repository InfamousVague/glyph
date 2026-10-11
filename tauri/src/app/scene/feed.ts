import type { RunState } from '../ai/runs.ts';
import type { ReviewStage } from '../ai/useNoteReview.ts';
import { progressOf } from '../ai/words.ts';
import { PANE_LINES } from './steps.ts';

/**
 * What scrolls through the phone while the models work (scene/AtWork.tsx):
 * the transcript's phrases as the careful model listens again, the phrases
 * and then the note's lines as the thinking model reads its prompt, its
 * thought as it thinks, and each thing it finds as it writes. Matt: "scrolling
 * through the thoughts and transcriptions of the AI". Pure: one list, one
 * current line, and a window of it for the DOM.
 *
 * Every line has an ABSOLUTE index, `at`, which is its key in the DOM: a
 * phrase's index in the transcript, a thought line's index in the wrapped
 * thought, a note line's offset past the phrases. So a window sliding over
 * the list never remounts a line it keeps, and the line under the pen only
 * changes its text.
 *
 * Two of the modes are placements rather than positions, and say so here. The
 * careful speech model never streams its words (capture/refine.ts reports a
 * percent alone), so while it listens the head is put at that share of the
 * phrases. While the thinking model reads, the prompt starts with the fast
 * transcript and ends with the note (review/prompt.ts `reviewMessage`), with
 * the careful transcript, the disagreements and the titles between them,
 * which are not scrolled; so the head walks the phrases and then the note's
 * lines at the run's share of its prompt, a little ahead of the model.
 */

export interface FeedLine {
  /** The line's absolute index, and its key. */
  at: number;
  text: string;
  /** A thing the model found: bold. */
  strong?: boolean;
}

export type FeedMode = 'transcript' | 'reading' | 'thought' | 'findings' | 'prose';

export interface Feed {
  lines: FeedLine[];
  /** The line being read or written, by its index in `lines`; null with nothing to show. */
  current: number | null;
  mode: FeedMode;
}

/** The part of a run the feed reads: its words, its phase and its prompt's progress, so a screen can key a memo on those alone. */
export type FeedRun = Pick<RunState, 'kind' | 'phase' | 'thought' | 'lines' | 'partial' | 'promptTokens' | 'promptTokensDone' | 'outputTokens' | 'maxTokens'>;

export interface FeedInput {
  stage: ReviewStage | null;
  run: FeedRun | null;
  /** Every phrase the fast model heard, in order, as the recorder handed them over. */
  heard: string;
  /** The note as the prompt read it. */
  body: string;
}

/** About how many words a phrase gets when the speaker never stopped. */
const WORDS_A_PHRASE = 14;
/** A thought's sentence past this many words is cut at a clause end, so no one line is a paragraph. */
const WORDS_A_THOUGHT_LINE = 30;
/** A phrase this short is joined to the next: "1." or "Words." alone is not a line. */
const SHORT_PHRASE = 3;

const wordsIn = (piece: string): number => piece.split(/\s+/).length;

/**
 * Text as sentences: split at sentence ends (a stop, a question mark or an exclamation, then a space, but not after a
 * bare number, so "1. Words" holds together) and at line breaks.
 */
function sentencesOf(text: string): string[] {
  return text
    .split(/(?<=[^\d\s][.?!]["”’)]?)\s+|\n+/)
    .map((piece) => piece.trim())
    .filter(Boolean);
}

/** A phrase of a word or two joined to the one after it. */
function joinShort(pieces: string[]): string[] {
  const joined: string[] = [];
  for (const piece of pieces) {
    const last = joined.at(-1);
    if (last !== undefined && wordsIn(last) < SHORT_PHRASE) joined[joined.length - 1] = `${last} ${piece}`;
    else joined.push(piece);
  }
  return joined;
}

/**
 * Text as phrases: sentences, and, where a stretch has no end, about every fourteen words - a placement for the
 * transcript, whose head walks it at the listen's share. A phrase of a word or two is joined to the one after it.
 */
export function phrasesOf(text: string): string[] {
  return joinShort(
    sentencesOf(text).flatMap((piece) => {
      const words = piece.split(/\s+/);
      if (words.length <= WORDS_A_PHRASE) return [piece];
      const runs: string[] = [];
      for (let i = 0; i < words.length; i += WORDS_A_PHRASE) runs.push(words.slice(i, i + WORDS_A_PHRASE).join(' '));
      // A tail of a word or two rides with the run before it.
      const tail = runs.at(-1);
      if (runs.length > 1 && tail && wordsIn(tail) < SHORT_PHRASE) runs.splice(-2, 2, `${runs.at(-2)} ${tail}`);
      return runs;
    }),
  );
}

/** A line's Markdown marks: a heading's hashes, a list's dash and its checkbox, a number, a quote's chevron. */
const MARKS = /^(?:#{1,6}\s+|>\s*|(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?)+/;

/**
 * The note's lines as words, blanks dropped and the Markdown marks off the front: the pane is for what the model reads,
 * not how it is marked (the review saw "# Planning call" and "- [ ] Fix the seat bar" scrolling through the phone).
 */
export function noteLines(body: string): string[] {
  return body
    .split('\n')
    .map((line) => line.trim().replace(MARKS, ''))
    .filter(Boolean);
}

/**
 * A thought wrapped into lines: by sentence, since a reasoning model writes long paragraphs, and left to wrap from
 * there; only a sentence past thirty words is cut, at a clause end. Never every fourteen words, which the review saw
 * leave stubs like "and the" as lines of their own. The last line is the tail under the pen.
 */
export function thoughtLines(thought: string): string[] {
  return joinShort(sentencesOf(thought).flatMap((piece) => (wordsIn(piece) <= WORDS_A_THOUGHT_LINE ? [piece] : piece.split(/(?<=[;:])\s+/))));
}

const WHAT = /"what"\s*:\s*"((?:[^"\\]|\\.)*)"/g;
const OPEN_WHAT = /"what"\s*:\s*"((?:[^"\\]|\\.)*)$/;

function unescaped(raw: string): string {
  try {
    return JSON.parse(`"${raw}"`) as string;
  } catch {
    return raw;
  }
}

/**
 * The model's findings as it writes them: every complete "what" string in the JSON so far, unescaped, and the one still
 * open under the pen, so a finding's words type in as the model writes them and the JSON itself never shows.
 */
export function findingsSoFar(json: string): { done: string[]; open: string | null } {
  const done: string[] = [];
  let last = 0;
  for (const match of json.matchAll(WHAT)) {
    done.push(unescaped(match[1] ?? ''));
    last = match.index + match[0].length;
  }
  const open = OPEN_WHAT.exec(json.slice(last));
  return { done, open: open ? unescaped(open[1] ?? '') : null };
}

/** The lines of `texts` numbered from `from`. */
function numbered(texts: readonly string[], from = 0, strong = false): FeedLine[] {
  return texts.map((text, i) => (strong ? { at: from + i, text, strong } : { at: from + i, text }));
}

const lastOf = (lines: readonly FeedLine[]): number | null => (lines.length ? lines.length - 1 : null);

export function feedOf({ stage, run, heard, body }: FeedInput): Feed {
  const phrases = phrasesOf(heard);
  const transcript = numbered(phrases);

  // The stages, and a run not yet reading: the transcript, the head placed at the listen's share of it.
  if (stage || !run || run.phase === 'queued' || run.phase === 'loading') {
    if (!transcript.length) return { lines: [], current: null, mode: 'transcript' };
    if (stage?.what === 'Listening again' && stage.percent !== null) {
      // A placement, not the model's position: the careful model reports a percent and never its words.
      return { lines: transcript, current: Math.min(transcript.length - 1, Math.floor((stage.percent / 100) * transcript.length)), mode: 'transcript' };
    }
    return { lines: transcript, current: lastOf(transcript), mode: 'transcript' };
  }

  // Reading the prompt: the phrases again from the top, then the note's lines, at the run's share of its prompt.
  if (run.phase === 'prefill') {
    const lines = [...transcript, ...numbered(noteLines(body), transcript.length)];
    if (!lines.length) return { lines, current: null, mode: 'reading' };
    // A placement: the prompt holds more between the transcript and the note than is scrolled here.
    const share = progressOf(run) ?? 0;
    return { lines, current: Math.min(lines.length - 1, Math.floor(share * lines.length)), mode: 'reading' };
  }

  // Writing, other kinds: prose as it lands, the partial line under the pen.
  if (run.kind !== 'review') {
    const texts = run.partial ? [...run.lines, run.partial] : [...run.lines];
    const lines = numbered(texts);
    return { lines, current: lastOf(lines), mode: 'prose' };
  }

  const thought = numbered(thoughtLines(run.thought));
  // Thinking: the thought wrapped by sentence, the tail the line under the pen.
  if (!run.lines.length && !run.partial) return { lines: thought, current: lastOf(thought), mode: 'thought' };

  // Writing: the thought stays, dimmed, and under it each thing found so far, the open one typing in.
  const { done, open } = findingsSoFar(run.lines.join('\n') + run.partial);
  const found = numbered(done, thought.length, true);
  const lines = open !== null ? [...thought, ...found, { at: thought.length + found.length, text: open, strong: true }] : [...thought, ...found];
  return { lines, current: lastOf(lines), mode: 'findings' };
}

/** How many lines before the current one the reading modes keep in the DOM; the rest of the window comes after it. */
const BEFORE = 16;

/**
 * The lines the DOM holds: in the reading modes a window round the current line, sixteen before it and the rest
 * after (seven, of twenty-four); in the streaming modes the last PANE_LINES, newest at the bottom.
 */
export function paneWindow(feed: Feed, size = PANE_LINES): FeedLine[] {
  const { lines, current, mode } = feed;
  if (lines.length <= size) return lines;
  if ((mode === 'transcript' || mode === 'reading') && current !== null) {
    const from = Math.max(0, Math.min(current - BEFORE, lines.length - size));
    return lines.slice(from, from + size);
  }
  return lines.slice(-size);
}
