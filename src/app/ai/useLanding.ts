import { useEffect, useRef } from 'react';
import type { EditorView } from '@codemirror/view';
import { AI_AUTHOR, withAuthor } from '../core/authors.ts';
import { aiEdit, landingField, setLanding } from '../editor/aiChanges.ts';
import { commonEnds } from '../editor/wispArrivals.ts';
import { Lander } from './land.ts';
import { placementOf } from './start.ts';
import { recordChange } from './log.ts';
import { allLines, ended, useRun } from './runs.ts';

/**
 * The note's run, landed: this hook watches the note's latest run and hands
 * its lines to the lander as they finish, then, when it is done, signs the
 * note with the AI as an author (Matt: the AI is an author; core/authors.ts)
 * and records the words before and after in the log, for Undo.
 *
 * A run that ended before this note was opened is left alone: its lines are
 * in the note already, or it never wrote any.
 */
export function useLanding(
  noteId: string,
  view: EditorView | null,
  options: { wisp: boolean; haptic: boolean; owner: string | undefined; onDropped?: (count: number) => void },
): void {
  const run = useRun(noteId);
  const current = useRef<{ runId: string; lander: Lander; before: string } | null>(null);
  const optionsRef = useRef(options);
  optionsRef.current = options;

  useEffect(() => {
    if (!view || !run) return;
    if (current.current && current.current.runId !== run.id) {
      // Another run took this one's place: what landed stays.
      current.current.lander.abandon();
      current.current = null;
    }
    if (!current.current) {
      if (ended(run) || run.phase === 'queued' || run.phase === 'loading' || run.phase === 'prefill') return;
      if (!view.state.field(landingField) && !run.scope) return;
      // A reopened note mid-run, before a line had landed: the landing is decided again as it was at the start
      // (ai/start.ts), against the note as it reads now, which is as it read then, since it was closed in between.
      if (!view.state.field(landingField) && run.scope) {
        const placement = placementOf(run.kind);
        const end = view.state.doc.length;
        const at = placement === 'append' ? end : Math.min(run.scope.from, end);
        view.dispatch({ effects: setLanding.of({ start: at, cursor: at, oldEnd: placement === 'replace' ? Math.min(run.scope.to, end) : at }) });
      }
      const lander = new Lander(view, run.id, { wisp: optionsRef.current.wisp, haptic: optionsRef.current.haptic }, view.state.doc.toString());
      current.current = { runId: run.id, lander, before: lander.before };
    }
    const { lander, before } = current.current;
    if (run.phase === 'generating') {
      lander.land(run.lines);
      return;
    }
    if (!ended(run)) return;
    if (run.phase === 'done') lander.finish(run.text !== null ? allLines(run.text) : run.lines);
    else lander.abandon();
    if (lander.dropped) optionsRef.current.onDropped?.(lander.dropped);
    // The AI signs what it co-wrote.
    if (run.phase === 'done') {
      const now = view.state.doc.toString();
      const signed = withAuthor(now, AI_AUTHOR, optionsRef.current.owner);
      if (signed !== now) {
        const { prefix, suffix } = commonEnds(now, signed);
        view.dispatch({ changes: { from: prefix, to: now.length - suffix, insert: signed.slice(prefix, signed.length - suffix) }, annotations: aiEdit.of('sign') });
      }
    }
    const after = view.state.doc.toString();
    if (after !== before) recordChange(noteId, run.id, before, after);
    current.current = null;
  }, [run, view, noteId]);

  // Leaving the note mid-run: the lander goes with the editor; the run keeps its place (ai/land.ts `progress`).
  useEffect(
    () => () => {
      current.current = null;
    },
    [view],
  );
}
