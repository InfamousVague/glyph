import { useEffect, useRef, useState } from 'react';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { useThinkingWhile } from '../core/thinking.ts';
import type { Scratch } from '../capture/scratch.ts';
import { leftover } from './plan.ts';
import { useSort } from './useSort.ts';
import styles from '../review/ReviewScreen.module.css';

/**
 * A memo, sorted before anything is filed (Matt chose "show, then commit"). The scratch's parts that belong in other
 * notes are listed, each with the note it would go to and the words it came from, Use this or Skip; under them, the
 * new note that the rest becomes. Commit files them; "Keep as one note" makes the whole memo a note. Back leaves the
 * scratch waiting, to sort next time.
 */
export function SortScreen({ scratch, onDone }: { scratch: Scratch; onDone: (noteId: string | null) => void }) {
  const { state, decide, commit, stopThinking } = useSort(scratch);
  const [showThought, setShowThought] = useState(true);
  const body = useRef<HTMLDivElement>(null);
  const pane = useRef<HTMLDivElement>(null);
  useWispEdge(body);

  const leave = async (all: boolean) => {
    const open = await commit(all);
    fireNativeHaptic('success');
    onDone(open);
  };
  // Back is not a decision: the scratch stays, and the list offers it again.
  useBack(true, () => onDone(null));

  useEffect(() => {
    const el = pane.current;
    if (el && state.step === 'running') el.scrollTop = el.scrollHeight;
  }, [state.thought, state.step]);

  const placements = state.placements;
  useEffect(() => {
    if (placements?.length) setShowThought(false);
  }, [placements?.length]);

  const kept = (placements ?? []).filter((p) => state.accepted.has(p.id));
  const rest = placements ? leftover(scratch.markdown, kept) : scratch.markdown;
  const running = state.step === 'running';
  // The gears turn over the screen while the model works out where the memo goes (art/ThinkingGears.tsx).
  useThinkingWhile(running);

  return (
    <div className={styles.screen}>
      <header className={styles.top}>
        <span className={styles.title}>Sorting your memo</span>
        <button type="button" className="app-word" onClick={() => void leave(true)} disabled={state.committing}>
          Keep as one note
        </button>
      </header>

      <div ref={body} className={styles.body}>
        <ol className={styles.steps}>
          <li className={styles.step}>
            <span className={styles.mark} data-state={state.step} aria-hidden="true" />
            <span className={styles.stepText}>
              <span className={styles.stepName}>Finding where it goes</span>
              {state.detail ? <span className={styles.stepDetail}>{state.detail}</span> : null}
            </span>
            {running ? (
              <button type="button" className={`app-word ${styles.stepAction}`} onClick={stopThinking}>
                Stop
              </button>
            ) : null}
          </li>
        </ol>

        {state.thought ? (
          <section className={styles.thought} aria-label="The model's thinking">
            <button type="button" className={styles.thoughtHead} onClick={() => setShowThought((on) => !on)} aria-expanded={showThought}>
              {running ? 'Thinking' : 'The thinking'}
              <span className={styles.chevron} data-open={showThought ? '' : undefined} aria-hidden="true" />
            </button>
            {showThought ? (
              <div ref={pane} className={styles.thoughtText} data-live={running ? '' : undefined}>
                {state.thought}
              </div>
            ) : null}
          </section>
        ) : null}

        {placements ? (
          <ul className={styles.findings}>
            {placements.map((placement) => {
              const use = state.accepted.has(placement.id);
              return (
                <li key={placement.id} className={styles.finding} data-accepted={use ? '' : undefined}>
                  <div className={styles.findingHead}>
                    <span className={styles.check}>{placement.how === 'item' ? (placement.task ? 'To-do' : 'List item') : 'Add'}</span>
                    <span className={styles.where}>{placement.noteTitle}</span>
                  </div>
                  <p className={styles.what}>{placement.text}</p>
                  <div className={styles.change}>
                    <p className={styles.before}>{placement.from}</p>
                  </div>
                  <div className={styles.findingActions}>
                    <span />
                    <div className={styles.answers} role="group" aria-label={`Use or skip: ${placement.text}`}>
                      <button type="button" className={styles.answer} aria-pressed={!use} onClick={() => decide(placement.id, false)}>
                        Skip
                      </button>
                      <button type="button" className={styles.answer} aria-pressed={use} onClick={() => decide(placement.id, true)}>
                        Use this
                      </button>
                    </div>
                  </div>
                </li>
              );
            })}
            <li className={styles.finding} data-accepted={rest ? '' : undefined}>
              <div className={styles.findingHead}>
                <span className={styles.check}>New note</span>
              </div>
              {rest ? (
                <div className={styles.change}>
                  <p className={styles.after}>{rest}</p>
                </div>
              ) : (
                <p className={styles.why}>Everything went into your notes, so no new note is made.</p>
              )}
            </li>
          </ul>
        ) : null}
      </div>

      <footer className={styles.footer}>
        {placements ? (
          <>
            <span className={styles.count}>
              {kept.length} of {placements.length} for your notes
            </span>
            <button type="button" className="app-pill" onClick={() => void leave(false)} disabled={state.committing}>
              {state.committing ? 'Filing…' : 'Commit'}
            </button>
          </>
        ) : (
          <span className={styles.count}>Nothing is filed until you commit.</span>
        )}
      </footer>
    </div>
  );
}
