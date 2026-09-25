import { useEffect, useRef, useState } from 'react';
import type { EditorView } from '@codemirror/view';
import { modelName } from '../core/ai.ts';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { getNote, listNotes, noteTitle, updateNote, type Note } from '../core/store.ts';
import { enqueueRefine, holdRefining, keepBetterPhrases, listenAgain } from '../capture/refine.ts';
import { renderNote, type Segment } from '../capture/markdown.ts';
import { pluginContextFor } from '../plugins/registry.ts';
import { wordChanges } from '../review/diff.ts';
import { applyFindings, readFindings, type NoteText } from '../review/findings.ts';
import { REVIEW_PROMPT, reviewBudget, reviewMessage } from '../review/prompt.ts';
import { recordChange } from './log.ts';
import { landFindings, simulatingReview, thinkingModel, wordsOnly, type ReviewHandoff } from './review.ts';
import { simulateRuns, startRun, type RunState } from './runs.ts';
import { simulatedReview } from './reviewSimulation.ts';

/**
 * The review after a recording, run in the note it reviews: listen again,
 * compare, think, land.
 *
 * Matt: "show the AI reasoning dissecting and parsing the note after we hit
 * stop, use slower more detailed models to check if the fast model got stuff
 * right and work with the user to resolve and commit" - and then, folding it
 * into the note: Stop opens the note, listening again and the thinking run
 * in the strip, and each finding lands as a tracked change with Keep and
 * Revert. The recording is already saved when this starts, so leaving at any
 * point loses nothing.
 *
 * 1. Listening again: the larger speech model over this take (capture/refine.ts),
 *    said in the strip as a stage of its own with its percent.
 * 2. Comparing: where it and the fast model heard different words (review/diff.ts).
 * 3. Thinking: the formatting model, reasoning on, as a run of the engine
 *    (ai/runs.ts) the strip follows like any other, its thought readable in
 *    the strip's card as it streams.
 * 4. Landing: its findings, each checked against the notes (review/findings.ts),
 *    into this note as tracked changes, and into another note a command
 *    changed through the guarded write; the words before and after in the
 *    log, for Undo.
 */

export interface ReviewStage {
  /** "Listening again", "Comparing". */
  what: string;
  detail: string;
  /** 0 to 100 while it can be told, else null. */
  percent: number | null;
}

export function useNoteReview(
  review: (ReviewHandoff & { key: number }) | undefined,
  view: EditorView | null,
  options: { wisp: boolean; say: (message: string) => void },
): ReviewStage | null {
  const [stage, setStage] = useState<ReviewStage | null>(null);
  const done = useRef<number | null>(null);
  const optionsRef = useRef(options);
  optionsRef.current = options;

  useEffect(() => {
    if (!review || !view || done.current === review.key) return undefined;
    done.current = review.key;
    let alive = true;
    const handoff = review;
    // While the review runs, nothing queued competes for the cores.
    holdRefining(true);
    let refined: Segment[] | null = null;
    let listened = false;
    // What the queue would have done with this take still happens, once: when the review ends, or when the note is
    // left before it does. Leaving after it ended hands nothing back again - a second pass over the take, or the
    // queue let go while the recorder holds it.
    let handedBack = false;
    const handBack = () => {
      if (handedBack) return;
      handedBack = true;
      if (handoff.job && refined && listened) void keepBetterPhrases(handoff.job, refined);
      else if (handoff.job) enqueueRefine(handoff.job);
      holdRefining(false);
    };

    void (async () => {
      const note = await getNote(handoff.noteId);
      if (!alive || !note) return;
      const self: NoteText = { id: note.id, title: noteTitle(note.body) || 'This note', body: note.body };
      const others = (await Promise.all(handoff.touched.filter((id) => id !== note.id).map((id) => getNote(id).catch(() => null))))
        .filter((n): n is Note => Boolean(n))
        .map((n) => ({ id: n.id, title: noteTitle(n.body) || 'Untitled', body: n.body }));

      // 1. Listening again.
      let careful: string | null = null;
      if (simulatingReview()) {
        setStage({ what: 'Listening again', detail: 'The slower speech model is listening to the recording again (simulated).', percent: 0 });
        for (let percent = 10; percent <= 100 && alive; percent += 15) {
          await new Promise((resolve) => window.setTimeout(resolve, 250));
          setStage({ what: 'Listening again', detail: 'The slower speech model is listening to the recording again (simulated).', percent });
        }
        careful = handoff.heard.replace(/\bseat\b/gi, 'seek').replace(/\bhello trade\b/gi, 'HelloTrade');
      } else if (handoff.job) {
        setStage({ what: 'Listening again', detail: 'The slower speech model is listening to the recording again.', percent: 0 });
        try {
          const better = await listenAgain(handoff.job, (percent) => alive && setStage({ what: 'Listening again', detail: 'The slower speech model is listening to the recording again.', percent }));
          if (!alive) return;
          if (better) {
            refined = better;
            listened = true;
            careful = renderNote(better).plain;
          }
        } catch (failure) {
          if (!alive) return;
          optionsRef.current.say(failureText(failure));
        }
      }

      // 2. Comparing.
      const changes = careful !== null ? wordChanges(handoff.heard, careful) : [];
      setStage({ what: 'Comparing', detail: careful === null ? 'Nothing to compare against.' : changes.length ? `${changes.length} ${changes.length === 1 ? 'place' : 'places'} where the two models heard different words.` : 'Both models heard the same words.', percent: null });

      // 3. Thinking, as a run the strip follows.
      const model = simulatingReview() ? 'qwen3.5-4b' : await thinkingModel();
      if (!alive) return;
      let findings = wordsOnly(changes, self);
      let runId = `review-${handoff.key.toString(36)}`;
      let last: RunState | null = null;
      if (model) {
        const titles = (await listNotes().catch(() => [])).map((n) => noteTitle(n.body)).filter(Boolean);
        const prompt = reviewMessage({ title: self.title, body: self.body, heard: handoff.heard, careful, changes, commands: handoff.commands, titles, touched: others });
        const budget = reviewBudget(model, prompt.length);
        setStage(null);
        if (simulatingReview()) simulateRuns(simulatedReview);
        const handle = startRun({
          noteId: self.id,
          kind: 'review',
          model,
          system: REVIEW_PROMPT,
          context: pluginContextFor(self.id) ?? undefined,
          prompt,
          maxTokens: budget.total,
          temperature: 0.2,
          think: true,
          thinkBudget: budget.think,
        });
        runId = handle.id;
        last = await handle.done;
        if (simulatingReview()) simulateRuns(null);
        if (!alive) return;
        if (last.phase === 'done' && last.text !== null) findings = readFindings(last.text, self, others);
      } else {
        optionsRef.current.say('No language model on this phone to think it through, so only the words the slower model heard differently are marked.');
      }

      // 4. Landing: this note's findings into its editor, another note's through the guarded write.
      const mine = findings.filter((f) => f.noteId === self.id);
      const theirs = findings.filter((f) => f.noteId !== self.id);
      const before = view.state.doc.toString();
      const landed = landFindings(view, mine, runId, { wisp: optionsRef.current.wisp });
      const after = view.state.doc.toString();
      if (after !== before) recordChange(self.id, runId, before, after);
      let elsewhere = 0;
      if (theirs.length) {
        const fresh = await Promise.all(
          others.map(async (n) => {
            const now = await getNote(n.id).catch(() => null);
            return now ? { ...n, body: now.body, revision: now.revision ?? 1 } : { ...n, revision: 1 };
          }),
        );
        for (const [id, body] of applyFindings(fresh, theirs)) {
          const was = fresh.find((n) => n.id === id);
          if (!was) continue;
          try {
            await updateNote(id, body, was.revision);
            elsewhere += 1;
          } catch {
            // The note changed meanwhile: the finding stands down rather than writing over newer words.
          }
        }
      }
      const found = landed + elsewhere;
      if (model && last && last.phase !== 'done') {
        // Stopped or failed: the word findings alone landed, and the strip already says what happened to the run.
      } else if (found) {
        fireNativeHaptic('success');
        optionsRef.current.say(`${model ? modelName(model) : 'The slower model'} found ${found} ${found === 1 ? 'thing' : 'things'} to look at${elsewhere ? `, ${elsewhere} in ${elsewhere === 1 ? 'another note' : 'other notes'}` : ''}. ${landed ? 'Each is marked in the note.' : ''}`.trim());
      } else if (model) {
        optionsRef.current.say(`${modelName(model)} found nothing to change.`);
      }
    })().finally(() => {
      if (!alive) return;
      setStage(null);
      handBack();
    });

    return () => {
      alive = false;
      setStage(null);
      // Left mid-review: what would have run anyway still runs.
      handBack();
      if (simulatingReview()) simulateRuns(null);
    };
  }, [review, view]);

  return stage;
}
