import type { EditorView } from '@codemirror/view';
import { frontMatterOffset } from '../core/frontMatter.ts';
import { setLanding } from '../editor/aiChanges.ts';
import { noteContext, noteHash, prepareNote } from '../format/pipeline.ts';
import { TEMPERATURE } from '../format/prompt.ts';
import type { Availability } from './available.ts';
import type { RunKind } from './kinds.ts';
import { askMessage, budgetForKind, promptForKind } from './prompts.ts';
import { startRun, type RunHandle, type RunScope } from './runs.ts';

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
 */

export interface StartOptions {
  /** The words the person gave, for a kind that takes some. */
  instruction?: string;
}

export type Started = { ok: true; handle: RunHandle } | { ok: false; reason: string };

/** Where a kind's lines go: over the words it was given, above the note, or under it. */
export function placementOf(kind: RunKind): 'replace' | 'prepend' | 'append' {
  if (kind === 'summarize') return 'prepend';
  if (kind === 'continue') return 'append';
  return 'replace';
}

/**
 * Where a run's lines land in a note `length` long, given the part it works on: over that part for a rewrite, at its
 * start - after the front matter - for a summary, and at the very end for a continuation. Decided when the run is
 * asked for, and again, the same way, for a note opened while its run is on (ai/useLanding.ts).
 */
export function landingAt(kind: RunKind, scope: RunScope, length: number): { start: number; cursor: number; oldEnd: number } {
  const placement = placementOf(kind);
  const at = placement === 'append' ? length : Math.min(scope.from, length);
  return { start: at, cursor: at, oldEnd: placement === 'replace' ? Math.min(scope.to, length) : at };
}

export function startNoteRun(view: EditorView, noteId: string, kind: RunKind, availability: Availability, options: StartOptions = {}): Started {
  if (!availability.ok) return { ok: false, reason: availability.reason };
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
