import { useCallback, useEffect, useRef, useState } from 'react';
import type { EditorView } from '@codemirror/view';
import type { ToastOptions } from '@glacier/react';
import { useAvailability } from '../ai/available.ts';
import type { RunKind } from '../ai/kinds.ts';
import { recordUndone, type RunRecord } from '../ai/log.ts';
import { loadMarks, saveMarks } from '../ai/marks.ts';
import type { ReviewHandoff } from '../ai/review.ts';
import { ended, useRun } from '../ai/runs.ts';
import { startNoteRun } from '../ai/start.ts';
import { useLanding } from '../ai/useLanding.ts';
import { useNoteReview } from '../ai/useNoteReview.ts';
import { accountState } from '../core/account/account.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import type { Note } from '../core/store.ts';
import { aiEdit, keepAllAiChanges, restoreAiChanges, type AiChange } from './aiChanges.ts';

/**
 * The AI in the open note: a run started from the More sheet or a spoken instruction (ai/start.ts), whose
 * lines land in the note itself as they finish, as tracked changes (ai/useLanding.ts, editor/aiChanges.ts), with the
 * strip under the header saying what the model is doing (ai/AiStrip.tsx). The robot's own view over the note is gone:
 * Matt chose the note as the one surface, with auto-apply, marks, and Undo.
 *
 * What is typed is flushed before a run starts, so the run's Undo has the note as it was. The marks the AI leaves are
 * counted for the strip and kept with the note a moment after they change (ai/marks.ts), so leaving and coming back
 * finds them where they were, as long as the note still reads the same. The review after a recording runs here too:
 * listening again and comparing as a stage in the strip, the thinking as a run, the findings landing as tracked
 * changes (ai/useNoteReview.ts).
 */

/** A spoken instruction about this note, to run on it as it opens (App.tsx, ai/instruction.ts); `key` tells one from the next. */
export interface NoteAsk {
  kind: RunKind;
  instruction?: string;
  key: number;
}

interface NoteAiOptions {
  note: Note;
  view: EditorView | null;
  /** Saves what is typed now (editor/useNoteSaving.ts). */
  flush: () => void;
  /** The live document, for the marks kept with it. */
  body: { readonly current: string };
  /** Whether what the AI writes arrives from smoke (core/preferences.ts `wisp`). */
  wisp: boolean;
  ask?: NoteAsk;
  review?: ReviewHandoff & { key: number };
  toast: (options: ToastOptions) => void;
}

export interface NoteAi {
  /** Starts a run on the note; says why not when it cannot. */
  runAi: (kind: RunKind, instruction?: string) => void;
  /** The kind of run on the note now, for the More sheet to mark, or null. */
  runningKind: RunKind | null;
  /** The review's stage, for the strip. */
  reviewStage: ReturnType<typeof useNoteReview>;
  /** How many of the AI's marks are in the note. */
  marks: number;
  /** The editor's word that the marks changed. */
  onAiMarks: (changes: readonly AiChange[]) => void;
  /** Undo for a run in the strip's log; false when it cannot be undone. */
  undoRun: (record: RunRecord) => boolean;
}

export function useNoteAi({ note, view, flush, body, wisp, ask, review, toast }: NoteAiOptions): NoteAi {
  const run = useRun(note.id);
  const runningKind: RunKind | null = run && !ended(run) ? run.kind : null;
  const availability = useAvailability();

  const runAi = (kind: RunKind, instruction?: string) => {
    if (!view) return;
    flush();
    const started = startNoteRun(view, note.id, kind, availability.availability, { instruction });
    if (!started.ok) toast({ message: started.reason });
    else fireNativeHaptic('selection');
  };

  const reviewStage = useNoteReview(review, view, { wisp, say: (message) => toast({ message, duration: 7000 }) });

  // A spoken instruction the note opened with: run once the editor and the AI are ready.
  const askDone = useRef<number | null>(null);
  useEffect(() => {
    if (!ask || !view || askDone.current === ask.key) return;
    if (!availability.availability.ok) {
      if (availability.availability.waiting) return;
      askDone.current = ask.key;
      toast({ message: availability.availability.reason });
      return;
    }
    askDone.current = ask.key;
    runAi(ask.kind, ask.instruction);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- runAi is made afresh each render; the key and the readiness are what this keys on
  }, [ask, view, availability.availability]);

  // The AI signs beside the account's handle, where there is one (core/authors.ts).
  useLanding(note.id, view, {
    wisp,
    haptic: true,
    owner: accountState().session?.handle,
    onDropped: (count) => toast({ message: count === 1 ? 'One line the model wrote was dropped: you had written there.' : `${count} lines the model wrote were dropped: you had written there.` }),
  });

  const [marks, setMarks] = useState(0);
  const marksTimer = useRef<number | null>(null);
  const onAiMarks = useCallback(
    (changes: readonly AiChange[]) => {
      setMarks(changes.length);
      if (marksTimer.current !== null) window.clearTimeout(marksTimer.current);
      marksTimer.current = window.setTimeout(() => {
        marksTimer.current = null;
        saveMarks(note.id, body.current, changes);
      }, 400);
    },
    [note.id, body],
  );
  useEffect(() => {
    if (!view) return;
    const kept = loadMarks(note.id, view.state.doc.toString());
    if (kept?.length) view.dispatch({ effects: restoreAiChanges.of(kept) });
  }, [view, note.id]);

  /**
   * The note back as it was before the run, but only while it still reads as the run left it - a later edit is the
   * person's, and would be lost under the old words.
   */
  const undoRun = (record: RunRecord): boolean => {
    if (!view || record.before === undefined || record.after === undefined) return false;
    const now = view.state.doc.toString();
    if (now !== record.after) {
      toast({ message: 'The note has changed since, so that run can’t be undone.' });
      return false;
    }
    view.dispatch({
      changes: { from: 0, to: now.length, insert: record.before },
      selection: { anchor: 0 },
      scrollIntoView: true,
      effects: keepAllAiChanges.of(null),
      annotations: aiEdit.of('undo'),
    });
    recordUndone(note.id, record.id);
    fireNativeHaptic('success');
    toast({ message: 'Put back as it was.' });
    return true;
  };

  return { runAi, runningKind, reviewStage, marks, onAiMarks, undoRun };
}
