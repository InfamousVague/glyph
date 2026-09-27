import type { EditorView } from '@codemirror/view';
import { frontMatterOffset } from '../core/frontMatter.ts';
import { aiEdit, setLanding } from '../editor/aiChanges.ts';
import { commonEnds } from '../editor/wispArrivals.ts';
import { noteContext, noteHash, prepareNote } from '../format/pipeline.ts';
import { RECORDING_SUMMARY_PROMPT, TEMPERATURE } from '../format/prompt.ts';
import type { Availability } from './available.ts';
import type { RunKind } from './kinds.ts';
import { askMessage, budgetForKind, promptForKind } from './prompts.ts';
import { startRun, type Placement, type RunHandle, type RunScope } from './runs.ts';
import type { SummaryAsk, SummaryStarted } from './summaries.ts';
import { summaryUnchanged } from './summaryKeep.ts';
import { carryTicked, retitled, shapeSummary, summaryPlace, summarySection } from './summaryText.ts';

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
 * carried in as it finishes; and a note still wearing a meeting's date title
 * takes the model's heading once the run is done. A section the person
 * edited is not written over unless they asked for that (`replace`): the
 * strip asks first (tapes/NoteTape.tsx).
 */

export interface StartOptions {
  /** The words the person gave, for a kind that takes some. */
  instruction?: string;
  /** The recording summarised into the note: the tape's words, from the queue (ai/summaries.ts). */
  recording?: SummaryAsk;
}

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

export function startNoteRun(view: EditorView, noteId: string, kind: RunKind, availability: Availability, options: StartOptions = {}): Started {
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
 * section that is no longer the app's when nobody asked to replace it, and 'nothing' for a tape with no words.
 */
function startRecordingSummary(view: EditorView, noteId: string, fallbackModel: string, ask: SummaryAsk): SummaryStarted {
  if (!ask.words.trim()) return { ok: false, reason: 'nothing' };
  const body = view.state.doc.toString();
  const section = summarySection(body);
  if (section && !ask.replace && !summaryUnchanged(noteId, section.text)) return { ok: false, reason: 'edited' };
  let scope: RunScope;
  /** A blank line lands first when the line above the section is words: the title, or a paragraph. */
  let blankFirst = false;
  if (section) scope = { from: section.start, to: section.end };
  else {
    const place = summaryPlace(body);
    // A section that ran straight into the paragraph under it would make that paragraph the last item's; a blank line
    // goes in first, so the section stands on its own. The run's lines land before it.
    if (place < body.length && body[place] !== '\n') view.dispatch({ changes: { from: place, insert: '\n' }, annotations: aiEdit.of('land') });
    scope = { from: place, to: place };
    blankFirst = place > 0 && body.slice(Math.max(0, place - 2), place) !== '\n\n';
  }
  const kept = section?.text ?? '';
  let title: string | null = null;
  const restore = (text: string, final: boolean) => {
    const shaped = shapeSummary(text);
    if (final) title = shaped.title;
    let out = shaped.section;
    if (final && kept && out) out = carryTicked(kept, out);
    return blankFirst && out ? `\n${out}` : out;
  };
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
    if (!state || state.phase !== 'done' || !title) return;
    const now = view.state.doc.toString();
    const next = retitled(now, title);
    if (next === now) return;
    const { prefix, suffix } = commonEnds(now, next);
    view.dispatch({ changes: { from: prefix, to: now.length - suffix, insert: next.slice(prefix, next.length - suffix) }, annotations: aiEdit.of('land') });
  });
  return { ok: true, handle };
}
