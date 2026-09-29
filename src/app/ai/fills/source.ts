import { askingWords, BLANK, type Blank, fillsIn } from '../../core/blanks.ts';
import type { Shape } from './shape.ts';

/**
 * Where a model's answer came from, decided by code when it lands (docs/DESIGN.md §145, 2.5): from this note, or from
 * memory. Never by the model: asked to label its own answers NOTE, KNOWN or UNKNOWN, the 4B kept the format 9 times in
 * 17 and called an invented 2026 World Cup winner KNOWN.
 *
 * "From this note" needs the answer's words beside what was asked. A note that says `We watched France play in Qatar.`
 * above `The 2022 World Cup was won by {?}` got the measured wrong answer France: every word of it is in the note, but
 * the one sentence holding "France" holds none of 2022, World, Cup or won, so it is from memory and dotted as it can be
 * wrong. Pure.
 */

const STOP = new Set('a an the of to in on at and or is are was be it for with by from as that this i we you he she they'.split(' '));

/** A text's content words: lower case, accents folded, punctuation off, a trailing s aside, stop words and short words out, numbers kept. */
export function contentWords(text: string): string[] {
  const words = text
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/(\d),(\d)/g, '$1$2')
    .match(/[\p{L}\p{N}]+/gu);
  return (words ?? [])
    .filter((w) => /\d/.test(w) || (w.length >= 3 && !STOP.has(w)))
    .map((w) => (/\d/.test(w) ? w : w.replace(/s$/, '')));
}

/** The note as a source reads it: no blanks, and no earlier fill's words or bracket, so a memory answer never vouches for another. */
export function noteForSource(text: string): string {
  let out = text;
  for (const fill of fillsIn(text).reverse()) out = `${out.slice(0, fill.from)}${out.slice(fill.to)}`;
  return out.replace(new RegExp(BLANK.source, 'g'), ' ');
}

/** The note's sentences: each line split at its sentence ends, a table row one sentence. */
function sentencesOf(text: string): string[] {
  return text.split('\n').flatMap((line) => (/^\s*\|/.test(line) ? [line] : line.split(/(?<=[.?!])\s+/)));
}

/**
 * Whether an answer is from this note: for a title or a summary, every content word of it is in its scope; for any
 * other shape, one sentence of the note holds every content word of it and at least one of the asking words'. An
 * answer with no content words at all ("no", "A") is from memory.
 */
export function fromThisNote(answer: string, blank: Blank, shape: Shape, text: string, scope: string): boolean {
  const words = contentWords(answer);
  if (!words.length) return false;
  if (shape === 'title' || shape === 'summary') {
    const have = new Set(contentWords(noteForSource(scope)));
    return words.every((w) => have.has(w));
  }
  const asking = new Set(contentWords(askingWords(blank, text).text));
  return sentencesOf(noteForSource(text)).some((sentence) => {
    const have = new Set(contentWords(sentence));
    return words.every((w) => have.has(w)) && [...asking].some((w) => have.has(w));
  });
}
