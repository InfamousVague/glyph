import type { EditorView } from '@codemirror/view';
import { listModels } from '../core/ai.ts';
import { hasNativeGeneration } from '../core/nativeGeneration.ts';
import { preferences } from '../core/preferences.ts';
import { isTauri } from '../core/tauri.ts';
import type { RefineJob } from '../capture/refine.ts';
import { addAiChanges, aiEdit, type AiChange } from '../editor/aiChanges.ts';
import { commonEnds, wisp } from '../editor/wispArrivals.ts';
import type { WordChange } from '../review/diff.ts';
import { addLine, locate, locateLast, type Finding, type NoteText } from '../review/findings.ts';

/**
 * The review after a recording, folded into the note (Matt): Stop opens the
 * note, the strip says what the slower models are doing, and each thing they
 * find lands in the note as a tracked change with Keep and Revert, instead of
 * a screen of cards to decide on first. The pure parts live here; the hook
 * that runs the stages is ai/useNoteReview.ts, and the prompt, the findings'
 * reading and the word diff stay in review/ where the Rust prompt test reads
 * them.
 */

/** The binary generation whose model can think out loud (`ai_generate` `think`). */
export const REVIEW_GENERATION = 13;

/** What the recorder hands over when Stop saves a take (capture/CaptureScreen.tsx). */
export interface ReviewHandoff {
  noteId: string;
  /** The better-words pass the queue would have run for this take, or null (no recording kept). */
  job: Omit<RefineJob, 'tries'> | null;
  /** Every phrase the fast model heard, commands and all, in order. */
  heard: string;
  /** What the take's commands did, in words. */
  commands: string[];
  /** Notes other than this one that a command changed. */
  touched: string[];
}

/**
 * `?review` in a browser: the review runs with its models played by a script
 * (listening again turns "seat" into "seek", the thinking streams a canned
 * thought), so the flow can be tried without a phone.
 */
export function simulatingReview(): boolean {
  return !isTauri() && typeof window !== 'undefined' && new URLSearchParams(window.location.search).has('review');
}

/** Whether this binary can run the review: an older one saves as it always did, and never shows it. */
export async function reviewAvailable(): Promise<boolean> {
  if (simulatingReview()) return true;
  if (!isTauri() || !preferences().review) return false;
  return hasNativeGeneration(REVIEW_GENERATION);
}

/** The model to think with: the one chosen for formatting if it reasons and is here, else the largest Qwen here. */
export async function thinkingModel(): Promise<string | null> {
  const present = (await listModels().catch(() => [])).filter((m) => m.present);
  const chosen = preferences().formatModel;
  if (present.some((m) => m.id === chosen) && chosen.startsWith('qwen')) return chosen;
  const qwen = present.filter((m) => m.id.startsWith('qwen')).sort((a, b) => b.bytes - a.bytes)[0];
  return qwen?.id ?? present.find((m) => m.id === chosen)?.id ?? null;
}

/**
 * A phrase as it is looked for in the note and put in its place: a speech model ends a phrase with the stop it heard,
 * and the note may have carried on after the word.
 */
export function unpunctuated(phrase: string): string {
  return phrase.replace(/[.,;:!?]+$/, '');
}

/** What a words finding says: the careful model's words, not the ones the note has. */
export function heardAs(careful: string, found: string): string {
  return `“${careful}”, not “${found}”`;
}

/** Without a model to think, the careful model's words alone: each change the note still has, offered as it heard it. */
export function wordsOnly(changes: readonly WordChange[], note: NoteText): Finding[] {
  return changes.flatMap((change, i) => {
    if (!change.heard || !change.careful) return [];
    const find = locate(note.body, unpunctuated(change.heard));
    if (!find) return [];
    const replace = unpunctuated(change.careful);
    return [
      {
        id: `w${i}`,
        check: 'words' as const,
        what: heardAs(replace, find),
        why: 'The slower speech model heard it this way.',
        noteId: note.id,
        noteTitle: note.title,
        change: { kind: 'replace' as const, find, replace },
      },
    ];
  });
}

/**
 * A finding as an edit on the note as it now reads: where the words are, what
 * goes in their place, and the change record that marks it. Null for a
 * finding whose words are no longer there.
 */
export function findingEdit(body: string, finding: Finding, runId: string, id: string): { from: number; to: number; insert: string; record: AiChange } | null {
  if (finding.change.kind === 'replace') {
    const at = locateLast(body, finding.change.find);
    if (!at) return null;
    const { replace } = finding.change;
    const block = /\n/.test(at.text) || /\n/.test(replace);
    return { from: at.index, to: at.index + at.text.length, insert: replace, record: { id, runId, from: at.index, to: at.index + replace.length, removed: at.text, block } };
  }
  const next = addLine(body, finding.change.line);
  if (next === body) return null;
  const { prefix, suffix } = commonEnds(body, next);
  const insert = next.slice(prefix, next.length - suffix);
  return { from: prefix, to: body.length - suffix, insert, record: { id, runId, from: prefix, to: prefix + insert.replace(/\n$/, '').length, removed: body.slice(prefix, body.length - suffix), block: true } };
}

/**
 * The findings for the note on screen, into its editor one by one as tracked
 * changes, each on the note as the one before left it. Answers how many
 * landed.
 */
export function landFindings(view: EditorView, findings: readonly Finding[], runId: string, options: { wisp: boolean }): number {
  let landed = 0;
  findings.forEach((finding, n) => {
    const edit = findingEdit(view.state.doc.toString(), finding, runId, `${runId}-f${n}`);
    if (!edit) return;
    view.dispatch({
      changes: { from: edit.from, to: edit.to, insert: edit.insert },
      effects: addAiChanges.of([edit.record]),
      annotations: [aiEdit.of('land'), ...(options.wisp ? [wisp.of({ kind: 'rewrite' as const })] : [])],
      userEvent: 'ai.land',
    });
    landed += 1;
  });
  return landed;
}
