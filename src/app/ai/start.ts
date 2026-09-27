import type { EditorView } from '@codemirror/view';
import { accountState } from '../core/account/account.ts';
import { AI_AUTHOR, withAuthor } from '../core/authors.ts';
import { frontMatterOffset } from '../core/frontMatter.ts';
import { aiEdit, setLanding } from '../editor/aiChanges.ts';
import { commonEnds } from '../editor/wispArrivals.ts';
import { noteContext, noteHash, prepareNote } from '../format/pipeline.ts';
import { RECORDING_SUMMARY_PROMPT, TEMPERATURE } from '../format/prompt.ts';
import type { Availability } from './available.ts';
import type { RunKind } from './kinds.ts';
import { Lander } from './land.ts';
import { recordChange, recordRun } from './log.ts';
import { askMessage, budgetForKind, promptForKind } from './prompts.ts';
import { allLines, startRun, type Placement, type RunHandle, type RunScope } from './runs.ts';
import type { SummaryAsk, SummaryStarted } from './summaries.ts';
import { keptText, summaryUnchanged } from './summaryKeep.ts';
import { carryTicked, hasWords, retitled, shapeSummary, summaryPlace, summarySection } from './summaryText.ts';

/**
 * A run asked for on the note on screen: what the model is given, and where
 * its lines will land.
 *
 * The landing is decided here, before the model has read a word, and written
 * into the editor (editor/aiChanges.ts `setLanding`), so the person's typing
 * while it loads moves the bookmark with it. A rewrite - Format, Enhance,
 * Fix, Make a list, Ask - lands over the words it was given, the whole note;
 * a summary lands above the note (Matt, 29d: a summary belongs on top);
 * Continue lands under it. The front matter is never the model's: a rewrite
 * starts after it, and the model is given the words alone.
 *
 * A RECORDING'S SUMMARY is the one run whose landing is not its kind's
 * (docs/DESIGN.md §127 section 2). It is given the tape's words, not the
 * note's, and lands under the title as the section ai/summaryText.ts owns: at
 * the section's place when the note has none, or over the old section when
 * it does, as tracked changes with Keep and Revert. The model's answer is
 * shaped as it streams (`restore`), so the heading it opens with never lands
 * and the section only ever grows; the ticked to-dos of the old section are
 * carried in as it finishes; a note still wearing a meeting's date title
 * takes the model's heading once the run is done, and a note with no words
 * at all gets it as a `# title` line above the section. A section the person
 * edited is not written over unless they asked for that (`replace`): the
 * strip asks first (tapes/NoteTape.tsx). When the queue already has the
 * model's answer (the note was opened while a closed note's generation ran),
 * the section is landed at once, the same way, with no run.
 */

export interface StartOptions {
  /** The words the person gave, for a kind that takes some. */
  instruction?: string;
  /** The recording summarised into the note: the tape's words, from the queue (ai/summaries.ts). */
  recording?: SummaryAsk;
}

/** A run to follow, or why it could not start. A recording's summary may instead be landed at once (`SummaryStarted`). */
export type Started = { ok: true; handle: RunHandle } | { ok: false; reason: string };

/** Where a kind's lines go: over the words it was given, above the note, or under it. */
export function placementOf(kind: RunKind): Placement {
  if (kind === 'summarize') return 'prepend';
  if (kind === 'continue') return 'append';
  return 'replace';
}

/**
 * Where a run's lines land in a note `length` long, given the part it works on: over that part for a rewrite, at its
 * start - after the front matter - for a summary, and at the very end for a continuation. Decided when the run is
 * asked for, and again, the same way, for a note opened while its run is on (ai/useLanding.ts). A run that carries a
 * placement of its own (a recording's summary, over its scope) is landed by that rather than its kind's.
 */
export function landingAt(kind: RunKind, scope: RunScope, length: number, placement: Placement = placementOf(kind)): { start: number; cursor: number; oldEnd: number } {
  const at = placement === 'append' ? length : Math.min(scope.from, length);
  return { start: at, cursor: at, oldEnd: placement === 'replace' ? Math.min(scope.to, length) : at };
}

export function startNoteRun(view: EditorView, noteId: string, kind: RunKind, availability: Availability, options: StartOptions & { recording: SummaryAsk }): SummaryStarted;
export function startNoteRun(view: EditorView, noteId: string, kind: RunKind, availability: Availability, options?: StartOptions): Started;
export function startNoteRun(view: EditorView, noteId: string, kind: RunKind, availability: Availability, options: StartOptions = {}): Started | SummaryStarted {
  if (!availability.ok) return { ok: false, reason: availability.reason };
  if (options.recording) return startRecordingSummary(view, noteId, availability.model, options.recording);
  const body = view.state.doc.toString();
  const front = frontMatterOffset(body);
  const scope: RunScope = { from: front, to: body.length };
  const source = body.slice(front);
  if (!source.trim()) return { ok: false, reason: 'Nothing in the note yet.' };
  const instruction = options.instruction?.trim() || undefined;
  if (kind === 'ask' && !instruction) return { ok: false, reason: 'Say what to do with the note.' };
  const { prompt: text, restore } = prepareNote(source, kind === 'summarize' ? 'summarize' : 'format');
  const prompt = kind === 'ask' && instruction ? askMessage(instruction, text) : text;
  const handle = startRun({
    noteId,
    kind,
    instruction,
    model: availability.model,
    system: promptForKind(kind),
    context: noteContext(noteId) || undefined,
    prompt,
    maxTokens: budgetForKind(kind, text.length),
    temperature: TEMPERATURE,
    restore,
    hash: noteHash(noteId, body),
    scope,
  });
  // After the run is asked for: an earlier run on this note ended by it may still put its own bookmark away, and this
  // one is the newer, so it wears the run's id (editor/aiChanges.ts `Landing.runId`).
  view.dispatch({ effects: setLanding.of({ runId: handle.id, ...landingAt(kind, scope, body.length) }) });
  return { ok: true, handle };
}

/**
 * The recording's summary as a run in the note: the section's place or the old section as the scope, the answer
 * shaped as it streams, and the title taken at the end where the note still wears a date. Answers 'edited' for a
 * section that is no longer the app's when nobody asked to replace it, and 'nothing' for a tape with no words. With
 * the answer already in hand (`ask.text`), the section is landed at once and answered as landed.
 */
function startRecordingSummary(view: EditorView, noteId: string, fallbackModel: string, ask: SummaryAsk): SummaryStarted {
  if (!ask.words.trim()) return { ok: false, reason: 'nothing' };
  const body = view.state.doc.toString();
  const section = summarySection(body, keptText(noteId));
  if (section && !ask.replace && !summaryUnchanged(noteId, section.text)) return { ok: false, reason: 'edited' };
  let scope: RunScope;
  /** A blank line lands first when the line above the section is words: the title, or a paragraph. */
  let blankFirst = false;
  // Over the old section, its newline included: the lander would otherwise take its last line for the note's and
  // put a newline after it, one more blank line under the section at every remake.
  if (section) scope = { from: section.start, to: body[section.end] === '\n' ? section.end + 1 : section.end };
  else {
    const place = summaryPlace(body);
    // A section that ran straight into the paragraph under it would make that paragraph the last item's; a blank line
    // goes in first, so the section stands on its own. The run's lines land before it.
    if (place < body.length && body[place] !== '\n') view.dispatch({ changes: { from: place, insert: '\n' }, annotations: aiEdit.of('land') });
    scope = { from: place, to: place };
    blankFirst = place > 0 && body.slice(Math.max(0, place - 2), place) !== '\n\n';
  }
  const kept = section?.text ?? '';
  /** No words in the note: the section's own heading would be its title, so the model's heading goes above it. */
  const untitled = !hasWords(body);
  let title: string | null = null;
  const restore = (text: string, final: boolean) => {
    const shaped = shapeSummary(text);
    if (final) title = shaped.title;
    let out = shaped.section;
    if (final && kept && out) out = carryTicked(kept, out);
    // The heading only once its line is complete, so a landed title line never changes under the pen.
    if (untitled && out && shaped.title && text.includes('\n')) out = `# ${shaped.title}\n\n${out}`;
    return blankFirst && out ? `\n${out}` : out;
  };
  /** The title, once the lines are in, where the note still wears a meeting's date title. */
  const retitle = () => {
    if (!title) return;
    const now = view.state.doc.toString();
    const next = retitled(now, title);
    if (next === now) return;
    const { prefix, suffix } = commonEnds(now, next);
    view.dispatch({ changes: { from: prefix, to: now.length - suffix, insert: next.slice(prefix, next.length - suffix) }, annotations: aiEdit.of('land') });
  };
  if (ask.text !== undefined) return { ok: true, landed: landReady(view, noteId, ask.model || fallbackModel, scope, restore(ask.text, true), retitle) };
  const handle = startRun({
    noteId,
    kind: 'summarize',
    model: ask.model || fallbackModel,
    system: RECORDING_SUMMARY_PROMPT,
    prompt: ask.context ? `${ask.context}\n\n${ask.words}` : ask.words,
    maxTokens: ask.maxTokens,
    temperature: TEMPERATURE,
    restore,
    hash: noteHash(noteId, body),
    scope,
    placement: 'replace',
  });
  view.dispatch({ effects: setLanding.of({ runId: handle.id, ...landingAt('summarize', scope, view.state.doc.length, 'replace') }) });
  // The title, once the lines are in: the landing hook has finished with the run by the time its promise settles,
  // since the store's listeners run first and the editor's effects are flushed with them.
  void handle.done.then((state) => {
    if (state && state.phase === 'done') retitle();
  });
  return { ok: true, handle };
}

/**
 * A finished answer landed at once, with no run: the queue had it before the note was opened. The lander lands it
 * over the scope as tracked changes, as a run's lines would land (ai/useLanding.ts), the AI signs it and the log
 * keeps a record of it with the before and after for Undo. Answers the section as it landed, for the keep.
 */
function landReady(view: EditorView, noteId: string, model: string, scope: RunScope, text: string, retitle: () => void): string {
  const runId = `ready-${Date.now().toString(36)}`;
  recordRun({ id: runId, noteId, kind: 'summarize', instruction: null, model, at: Date.now(), ms: 0, outputTokens: 0, outcome: 'done', message: null, truncated: false });
  view.dispatch({ effects: setLanding.of({ runId, ...landingAt('summarize', scope, view.state.doc.length, 'replace') }) });
  const before = view.state.doc.toString();
  const lander = new Lander(view, runId, { wisp: false, haptic: false }, before);
  const lines = allLines(text);
  lander.land(lines);
  lander.finish(lines);
  retitle();
  const now = view.state.doc.toString();
  const signed = withAuthor(now, AI_AUTHOR, accountState().session?.handle);
  if (signed !== now) {
    const { prefix, suffix } = commonEnds(now, signed);
    view.dispatch({ changes: { from: prefix, to: now.length - suffix, insert: signed.slice(prefix, signed.length - suffix) }, annotations: aiEdit.of('sign') });
  }
  const after = view.state.doc.toString();
  if (after !== before) recordChange(noteId, runId, before, after);
  return summarySection(text)?.text ?? '';
}
