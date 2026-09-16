import { useCallback, useEffect, useRef, useState } from 'react';
import { generate, modelName, splitThought, type Run } from '../core/ai.ts';
import { deleteNote, getNote, listNotes, noteTitle, saveNote, setNoteRecording } from '../core/store.ts';
import { holdRefining } from '../capture/refine.ts';
import { placeWords } from '../capture/listAppend.ts';
import { clearScratch, type Scratch } from '../capture/scratch.ts';
import { enqueueFormat, setFormattingPaused } from '../format/queue.ts';
import { thinkingModel } from '../review/useReview.ts';
import { leftover, memosNote, onlyMemos, readPlacements, rulePlacements, UNSORTED_MEMOS, type Placement } from './plan.ts';
import { addWorkspace, fileNote } from '../core/workspaces.ts';
import { SORT_PROMPT, sortBudget, sortMessage } from './prompt.ts';

/**
 * A finished memo, sorted: the model reads the scratch beside the person's notes and proposes where its parts go
 * (sort/plan.ts), with its thinking streamed as the review's is; without a model, or when it fails, the rules file the
 * commands they understand. The person keeps or skips each placement; Commit writes them and makes a new note of
 * what is left. Nothing is written before Commit, and the scratch stays until then, so leaving loses nothing.
 */

export type SortStep = 'running' | 'done' | 'skipped' | 'failed';

export interface SortState {
  step: SortStep;
  detail: string;
  thought: string;
  thinking: boolean;
  placements: Placement[] | null;
  accepted: Set<string>;
  committing: boolean;
}

const INITIAL: SortState = { step: 'running', detail: 'Reading your notes', thought: '', thinking: false, placements: null, accepted: new Set(), committing: false };

/** The model's placements, and the rules' for any command it missed: the rules never lose an explicit "add X to Y". */
function merged(model: Placement[], rules: Placement[]): Placement[] {
  const taken = new Set(model.map((p) => p.from));
  return [...model, ...rules.filter((p) => !taken.has(p.from))];
}

export function useSort(scratch: Scratch) {
  const [state, setState] = useState<SortState>(INITIAL);
  const patch = useCallback((next: (s: SortState) => Partial<SortState>) => setState((s) => ({ ...s, ...next(s) })), []);
  const run = useRef<Run | null>(null);

  useEffect(() => {
    let alive = true;
    holdRefining(true);
    setFormattingPaused(true);
    void (async () => {
      const all = (await listNotes().catch(() => []))
        .filter((note) => !note.archivedAt && note.id !== scratch.id)
        .map((note) => ({ id: note.id, title: noteTitle(note.body), body: note.body }))
        .filter((note) => note.title);
      const rules = rulePlacements(scratch.markdown, all);
      const settle = (placements: Placement[], step: SortStep, detail: string) =>
        alive && patch(() => ({ step, detail, placements, accepted: new Set(placements.map((p) => p.id)), thinking: false }));

      const model = await thinkingModel();
      if (!alive) return;
      if (!model) {
        settle(rules, 'skipped', rules.length ? 'No language model on this phone, so only the plain commands were sorted.' : 'No language model on this phone to sort it.');
        return;
      }
      const prompt = sortMessage({ memo: scratch.markdown, notes: all });
      const budget = sortBudget(model, prompt.length);
      patch(() => ({ detail: `${modelName(model)} is reading the memo` }));
      const started = generate({
        model,
        system: SORT_PROMPT,
        prompt,
        maxTokens: budget.total,
        temperature: 0.1,
        think: true,
        thinkBudget: budget.think,
        onProgress: (progress) => {
          if (!alive) return;
          const split = splitThought(progress.partial, progress.thinking ?? false);
          patch(() => ({ thought: split.thought, thinking: !split.answering, detail: progress.phase === 'loading' ? `Loading ${modelName(model)}` : `${modelName(model)} is sorting` }));
        },
      });
      run.current = started;
      try {
        const output = await started.done;
        if (!alive) return;
        const split = splitThought(output.text, output.thinking ?? false);
        const placements = merged(readPlacements(split.answer, scratch.markdown, all), rules);
        patch(() => ({ thought: split.thought }));
        settle(placements, 'done', placements.length ? `${modelName(model)} found ${placements.length} ${placements.length === 1 ? 'thing' : 'things'} for your notes` : 'Nothing here for your other notes');
      } catch (failure) {
        const message = failure instanceof Error ? failure.message : String(failure);
        settle(rules, /cancel/i.test(message) ? 'skipped' : 'failed', /cancel/i.test(message) ? 'Stopped' : message);
      } finally {
        run.current = null;
      }
    })();
    return () => {
      alive = false;
      run.current?.cancel();
      holdRefining(false);
      setFormattingPaused(false);
    };
    // Sorted once for its scratch.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const decide = useCallback((id: string, use: boolean) => patch((s) => {
    const accepted = new Set(s.accepted);
    if (use) accepted.add(id);
    else accepted.delete(id);
    return { accepted };
  }), [patch]);

  const stopThinking = useCallback(() => run.current?.cancel(), []);

  /**
   * Commits the kept placements into their notes and makes a new note of what is left (with the take's recording on
   * it), or, when everything was placed, lets the recording go. Answers the note to open: the new one, or the first
   * note that was added to. With `all`, every placement is skipped: the whole memo becomes one note.
   */
  const commit = useCallback(
    async (all = false): Promise<string | null> => {
      patch(() => ({ committing: true }));
      run.current?.cancel();
      const kept = all ? [] : (state.placements ?? []).filter((p) => state.accepted.has(p.id));
      for (const placement of kept) {
        const note = await getNote(placement.noteId).catch(() => null);
        if (!note) continue;
        const placed = placeWords(note.body, placement.text, { how: placement.how, task: placement.task, many: false });
        await saveNote(note.id, placed.body, note.source);
      }
      const rest = leftover(scratch.markdown, kept);
      let open: string | null = kept[0]?.noteId ?? null;
      if (rest) {
        // Nothing but voice memos left: they are not an untitled note of players, they are the Unsorted memos note,
        // filed in a workspace of that name so they are all in one place until they are put somewhere.
        const loose = onlyMemos(rest);
        const saved = await saveNote(scratch.id, loose ? memosNote(rest) : rest, 'capture');
        if (loose) {
          const space = addWorkspace(UNSORTED_MEMOS);
          if (space) fileNote(saved.id, space.id);
        }
        if (scratch.recordedMs !== null) await setNoteRecording(saved.id, scratch.recordedMs, scratch.segments).catch(() => null);
        enqueueFormat(saved.id);
        open = saved.id;
      } else {
        // Everything went into other notes: the take's recording has no note to stay with.
        await deleteNote(scratch.id).catch(() => undefined);
      }
      clearScratch();
      return open;
    },
    [patch, scratch, state.accepted, state.placements],
  );

  return { state, decide, commit, stopThinking };
}
