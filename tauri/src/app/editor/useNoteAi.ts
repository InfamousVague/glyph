import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { EditorView } from '@codemirror/view';
import type { ToastOptions } from '@glacier/react';
import { useAvailability } from '../ai/available.ts';
import type { RunKind } from '../ai/kinds.ts';
import { recordUndone, type RunRecord } from '../ai/log.ts';
import { loadMarks, saveMarks } from '../ai/marks.ts';
import type { ReviewHandoff } from '../ai/review.ts';
import { ended, useRun } from '../ai/runs.ts';
import { startNoteRun } from '../ai/start.ts';
import { openForSummaries, type SummaryAsk, type SummaryStarted } from '../ai/summaries.ts';
import { useLanding } from '../ai/useLanding.ts';
import { useNoteReview } from '../ai/useNoteReview.ts';
import { lookupsHere, pressFill, type FillTarget } from '../ai/fills/queue.ts';
import { useFillLanding } from '../ai/fills/useFillLanding.ts';
import { accountState } from '../core/account/account.ts';
import { learntUntil } from '../core/ai.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { isIOS } from '../core/platform.ts';
import type { Note } from '../core/store.ts';
import { isTauri } from '../core/tauri.ts';
import { aiEdit, keepAllAiChanges, restoreAiChanges, type AiChange } from './aiChanges.ts';
import { fillAll, type BlankHooks } from './blanks.ts';

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
 *
 * The recording's summary lands here too (docs/DESIGN.md §127 section 2): while the note is open its summary is
 * handed to this screen by the queue (ai/summaries.ts `openForSummaries`) and run in the editor, the one writer of an
 * open note, rather than written plain behind it.
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
  /** Settings at the Model card, for a press that needs a model on the phone. */
  onGetModel?: () => void;
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
  /** Whether the AI can run here, or is still being looked for: the tape's Summarize word is there only then. */
  canSummarize: boolean;
  /** What the editor's blanks need: whose note, whether a Fill pill is drawn, and a press (editor/blanks.ts). */
  blankHooks: BlankHooks;
}

export function useNoteAi({ note, view, flush, body, wisp, ask, review, toast, onGetModel }: NoteAiOptions): NoteAi {
  const run = useRun(note.id);
  const runningKind: RunKind | null = run && !ended(run) ? run.kind : null;
  const availability = useAvailability();

  /** Why the AI cannot run, said with the way to a model where getting one is the fix. */
  const refuse = (reason: string, get: string | null) => toast(get && onGetModel ? { message: reason, action: { label: 'Get a model', onPress: onGetModel } } : { message: reason });

  /** A press of Fill, handed to the fills' queue with the model that runs, or said why not (docs/DESIGN.md §145). */
  const fill = (targets: FillTarget[]) => {
    const state = availability.availability;
    if (!state.ok) {
      refuse(state.reason, state.get);
      return;
    }
    flush();
    pressFill(note.id, targets, state.model);
    fireNativeHaptic('selection');
  };
  const fillRef = useRef(fill);
  fillRef.current = fill;

  const runAi = (kind: RunKind, instruction?: string) => {
    if (!view) return;
    if (kind === 'fill') {
      if (!fillAll(view)) toast({ message: 'No blanks for the model in this note.' });
      return;
    }
    flush();
    const started = startNoteRun(view, note.id, kind, availability.availability, { instruction });
    if (!started.ok) {
      const state = availability.availability;
      refuse(started.reason, state.ok ? null : state.get);
    } else fireNativeHaptic('selection');
  };

  const reviewStage = useNoteReview(review, view, { wisp, say: (message) => toast({ message, duration: 7000 }) });

  // The recording's summary, when the queue's turn for this note comes while it is open: a run in this editor.
  const summarize = (ask: SummaryAsk): SummaryStarted => {
    if (!view) return { ok: false, reason: 'The note is not open.' };
    flush();
    const started = startNoteRun(view, note.id, 'summarize', availability.availability, { recording: ask });
    if (started.ok) fireNativeHaptic('selection');
    return started;
  };
  const summarizeRef = useRef(summarize);
  summarizeRef.current = summarize;
  useEffect(() => {
    openForSummaries(note.id, (ask) => summarizeRef.current(ask));
    return () => openForSummaries(note.id, null);
  }, [note.id]);

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

  // A fill's answers land through this editor while the note is open (ai/fills/useFillLanding.ts).
  useFillLanding(note.id, view, { wisp, owner: accountState().session?.handle });

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

  // Where the model can ever run here: not a browser, not iOS, not a binary older than the engine (ai/available.ts).
  // A phone with no model still draws the pill, and a press says why and offers Get a model.
  const state = availability.availability;
  const canEverFill = isTauri() && !isIOS && (state.ok || !/newest Ghost\.md/.test(state.reason));
  const canFillRef = useRef(canEverFill);
  canFillRef.current = canEverFill;
  const modelRef = useRef(state.ok ? state.model : state.get);
  modelRef.current = state.ok ? state.model : state.get;
  const blankHooks = useMemo<BlankHooks>(
    () => ({
      noteId: () => note.id,
      canFill: () => canFillRef.current,
      learntUntil: () => learntUntil(modelRef.current ?? ''),
      lookups: lookupsHere,
      fill: (targets) => fillRef.current(targets),
      say: (message) => toast({ message }),
    }),
    [note.id, toast],
  );

  return { runAi, runningKind, reviewStage, marks, onAiMarks, undoRun, canSummarize: availability.availability.ok || availability.availability.waiting, blankHooks };
}
