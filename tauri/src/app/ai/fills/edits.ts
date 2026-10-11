import { AI_AUTHOR, withAuthor } from '../../core/authors.ts';
import { filledMark, type FillSource } from '../../core/blanks.ts';
import { commonEnds } from '../../editor/wispMotion.ts';
import { nextLead } from './message.ts';
import type { ShapeInfo } from './shape.ts';

/**
 * Where an answer goes in the note, as changes to its text (docs/DESIGN.md §145, 6.2), the same for a note open in
 * its editor (ai/fills/useFillLanding.ts, one transaction) and one closed (ai/fills/queue.ts, one write). Pure.
 *
 * - A model's answer replaces its blank as an Unsure mark whose hidden bracket says where it came from.
 * - Items: one item a line with the list's own lead, the first where the blank was, each marked with its place.
 * - A title never holds a mark: a title blank lands as plain words, a question that is the whole first line stays the
 *   title with its answer under it, and a blank among the title's words lands as plain words. So the note's name and
 *   its file's name never carry a bracket.
 * - An answer asked again replaces the mark it was asked for.
 */

/** One answer ready to land: where, what, and whose. */
export interface Landing {
  /** The target's span in the text as it reads now: a blank's braces, or an asked-again fill's whole span. */
  from: number;
  to: number;
  question: string;
  info: ShapeInfo;
  /** The checked answer: one text, or an items blank's items. */
  words: string[];
  source: FillSource;
  model: string;
  /** ISO, `2026-09-28`. */
  date: string;
}

export interface TextChange {
  from: number;
  to: number;
  insert: string;
}

/** The changes one answer makes, in the text's own offsets. */
export function landingChanges(text: string, answer: Landing): TextChange[] {
  const meta = { model: answer.model, source: answer.source, date: answer.date };
  const before = text.slice(Math.max(0, answer.from - 1), answer.from);
  const lineStart = text.lastIndexOf('\n', answer.from - 1) + 1;
  const lineEndAt = text.indexOf('\n', answer.to);
  const lineEnd = lineEndAt === -1 ? text.length : lineEndAt;
  const line = text.slice(lineStart, lineEnd);
  const words = answer.words[0] ?? '';
  const { info } = answer;
  if (info.shape === 'title') return [{ from: answer.from, to: answer.to, insert: words }];
  if (info.titleLine && info.shape === 'line') {
    // The question stays as the title, plain, and the answer goes under it: on the next line after a heading, after an
    // empty line otherwise. The title does not change, so neither does the file's name.
    const heading = /^\s*#{1,6}\s/.test(line);
    const mark = filledMark(words, meta, answer.question);
    return [{ from: answer.from, to: answer.to, insert: answer.question }, { from: lineEnd, to: lineEnd, insert: `${heading ? '\n' : '\n\n'}${mark}` }];
  }
  if (info.titleLine) return [{ from: answer.from, to: answer.to, insert: words }];
  if (info.shape === 'items') {
    const count = answer.words.length;
    const marks = answer.words.map((item, i) => filledMark(item, meta, answer.question, i === 0 ? before : '', count > 1 ? { n: i + 1, of: count } : null));
    const rest = marks.slice(1).map((mark, i) => `\n${nextLead(line, i + 1)}${mark}`);
    return [{ from: answer.from, to: answer.to, insert: `${marks[0]}${rest.join('')}` }];
  }
  return [{ from: answer.from, to: answer.to, insert: filledMark(words, meta, answer.question, before) }];
}

/** Every answer's changes, sorted and never overlapping, for one transaction or one write. */
export function allChanges(text: string, answers: readonly Landing[]): TextChange[] {
  return answers.flatMap((answer) => landingChanges(text, answer)).sort((a, b) => a.from - b.from || a.to - b.to);
}

/** The text with changes applied. */
export function applyChanges(text: string, changes: readonly TextChange[]): string {
  let out = text;
  for (const change of [...changes].sort((a, b) => b.from - a.from)) out = `${out.slice(0, change.from)}${change.insert}${out.slice(change.to)}`;
  return out;
}

/**
 * The AI's signature as a change of its own at the top, in the text's own offsets: it touches only the front matter,
 * so it lands in the same transaction as the answers without crossing them. Null when the note is signed already.
 */
export function signatureChange(text: string, owner?: string): TextChange | null {
  const signed = withAuthor(text, AI_AUTHOR, owner);
  if (signed === text) return null;
  const { prefix, suffix } = commonEnds(text, signed);
  return { from: prefix, to: text.length - suffix, insert: signed.slice(prefix, signed.length - suffix) };
}
