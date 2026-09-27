import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { RotateCcw, X } from '@glacier/icons';
import { cancelRun, dismissRun, simulateRuns, startRun } from '../ai/runs.ts';
import type { ReviewStage } from '../ai/useNoteReview.ts';
import { useBack } from '../core/back.ts';
import { AtWork } from '../scene/AtWork.tsx';
import { SCRIPT_BODY, SCRIPT_HEARD, SCRIPT_PROMPT, scriptedReview, scriptedStages, type SceneScript } from '../scene/scripted.ts';
import styles from './SceneBench.module.css';

/**
 * Settings › Developer › The phone at work: the scene after Done (scene/AtWork.tsx) played from a script
 * (scene/scripted.ts), so its layout, its pictures and its steps can be looked at without a recording - on the
 * Fold, which is where Matt asked to review them, and in a browser at `?scene=`. The models are pretend, the screen
 * is this one, and the words are the note's.
 *
 * The scene is mounted inline in the bench's body, under its bar, so the bar is never under the scene. The pretend
 * model is installed round `startRun` alone and taken out the moment it returns, as the browser's own `?review`
 * does (ai/useNoteReview.ts), and again on close, so no later real run is ever played by the script. The run's note
 * is the bench's own, `scene-bench`, and the run is cancelled and put away when the bench closes.
 */

/** The bench's note: no note has this id, so the run touches nothing. */
export const BENCH_NOTE = 'scene-bench';

interface SceneBenchProps {
  /** Which script to play, or null for a closed bench. */
  script: SceneScript | null;
  onClose: () => void;
}

export function SceneBench({ script, onClose }: SceneBenchProps) {
  const open = script !== null;
  /** Each play is a new opening of the scene. */
  const [key, setKey] = useState(0);
  const [stage, setStage] = useState<ReviewStage | null>(null);
  const card = useRef<HTMLDivElement>(null);
  useBack(open, onClose);

  useEffect(() => {
    if (!script) return undefined;
    card.current?.focus();
    let alive = true;
    // The stages first; when they clear, the run, with the pretend model installed only round its start.
    const stop = scriptedStages((next) => {
      if (!alive) return;
      setStage(next);
      if (next !== null) return;
      simulateRuns(scriptedReview(script));
      startRun({ noteId: BENCH_NOTE, kind: 'review', model: 'qwen3.5-4b', system: '', prompt: SCRIPT_PROMPT, maxTokens: 1900, think: true, thinkBudget: 700 });
      simulateRuns(null);
    });
    return () => {
      alive = false;
      stop();
      simulateRuns(null);
      setStage(null);
      void cancelRun(BENCH_NOTE).then(() => dismissRun(BENCH_NOTE));
    };
  }, [script, key]);

  if (!open) return null;

  return createPortal(
    <div className={styles.over} role="dialog" aria-modal="true" aria-label="The phone at work" ref={card} tabIndex={-1}>
      <div className={styles.bar}>
        <h2 className={styles.title}>The phone at work</h2>
        <button type="button" className={styles.again} onClick={() => setKey((was) => was + 1)}>
          <RotateCcw size={15} strokeWidth={2.2} aria-hidden="true" />
          <span>Play again</span>
        </button>
        <button type="button" className={styles.close} aria-label="Close" onClick={onClose}>
          <X size={18} />
        </button>
      </div>
      <div className={styles.body}>
        <AtWork inline noteId={BENCH_NOTE} opening={key} heard={SCRIPT_HEARD} body={SCRIPT_BODY} hasJob stage={stage} />
      </div>
    </div>,
    document.body,
  );
}
