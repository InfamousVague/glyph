import type { EditorView } from '@codemirror/view';
import { setLanding } from '../editor/aiChanges.ts';
import { noteHash, prepareNote } from '../format/pipeline.ts';
import { budgetFor, promptFor, TEMPERATURE } from '../format/prompt.ts';
import type { Mode } from '../format/modes.ts';
import { pluginContextFor } from '../plugins/registry.ts';
import type { Availability } from './available.ts';
import type { RunKind } from './kinds.ts';
import { frontMatterEnd } from './landing.ts';
import { startRun, type RunHandle, type RunScope } from './runs.ts';

/**
 * A run asked for on the note on screen: what the model is given, and where
 * its lines will land.
 *
 * The landing is decided here, before the model has read a word, and written
 * into the editor (editor/aiChanges.ts `setLanding`), so the person's typing
 * while it loads moves the bookmark with it. A rewrite - Format, Enhance,
 * and the newer kinds - lands over the note's words (or the part asked
 * about); a summary lands above them (Matt, 29d: a summary belongs on top);
 * Continue lands under them. The front matter is never the model's: a
 * rewrite of the whole note starts after it, and the model is given the
 * words alone.
 */

export interface StartOptions {
  /** The words the person gave, for a kind that takes some. */
  instruction?: string;
  /** The part of the note to work on, as offsets in the body now; the whole note when absent. */
  scope?: RunScope | null;
}

export type Started = { ok: true; handle: RunHandle } | { ok: false; reason: string };

/** Where a kind's lines go: over the words it was given, above the note, or under it. */
export function placementOf(kind: RunKind): 'replace' | 'prepend' | 'append' {
  if (kind === 'summarize') return 'prepend';
  if (kind === 'continue') return 'append';
  return 'replace';
}

export function startNoteRun(view: EditorView, noteId: string, kind: RunKind, availability: Availability, options: StartOptions = {}): Started {
  if (!availability.ok) return { ok: false, reason: availability.reason };
  const body = view.state.doc.toString();
  const front = frontMatterEnd(body);
  const placement = placementOf(kind);
  const scope: RunScope = options.scope ?? { from: front, to: body.length };
  const source = placement === 'replace' ? body.slice(scope.from, scope.to) : body.slice(front);
  if (!source.trim()) return { ok: false, reason: 'Nothing in the note yet.' };
  // Only the three older kinds have prompts so far; the rest come with the bar (ai/prompts.ts).
  const mode = (kind === 'format' || kind === 'summarize' || kind === 'enhance' ? kind : 'format') as Mode;
  const { prompt, restore } = prepareNote(source, mode);
  const landing =
    placement === 'replace'
      ? { start: scope.from, cursor: scope.from, oldEnd: scope.to }
      : placement === 'prepend'
        ? { start: front, cursor: front, oldEnd: front }
        : { start: body.length, cursor: body.length, oldEnd: body.length };
  view.dispatch({ effects: setLanding.of(landing) });
  const handle = startRun({
    noteId,
    kind,
    instruction: options.instruction,
    model: availability.model,
    system: promptFor(mode),
    context: pluginContextFor(noteId) ?? undefined,
    prompt,
    maxTokens: budgetFor(mode, prompt.length),
    temperature: TEMPERATURE,
    restore,
    hash: noteHash(noteId, body),
    scope,
  });
  return { ok: true, handle };
}
