import { useEffect, useRef, useState } from 'react';
import { Check, ChevronDown, ChevronUp, Ear, PenLine, Square, Undo2, X } from '@glacier/icons';
import { AiCard } from '../format/AiCard.tsx';
import { KIND_ICONS, PHASE_ICONS, spins } from './icons.ts';
import { kindWords } from './kinds.ts';
import { useRunLog, type RunRecord } from './log.ts';
import { cancelRun, dismissRun, ended, useRun } from './runs.ts';
import type { ReviewStage } from './useNoteReview.ts';
import { when } from '../notes/when.ts';
import { cardPhase, marksSentence, progressOf, recordSentence, runSentence } from './words.ts';
import styles from './AiStrip.module.css';

/**
 * The status strip: one line under the header while the model works on the
 * note, and for a while after.
 *
 * Matt chose this over the full card: "a one-line strip under the header, an
 * icon for the phase, the verb, tokens a second, a thin progress bar; tap it
 * for the full AI card with the hardware meters". So the line is the phase's
 * icon (ai/icons.ts), the sentence (ai/words.ts) and a hairline bar that
 * fills as the note is read and then as the answer is written; Stop sits at
 * its end while it runs. Once the run has ended the line says what happened
 * and how long it took, with Undo when the run changed the note and the note
 * still reads as it left it, and a cross to put the line away. Tapping the
 * line opens the card (format/AiCard.tsx) - the model, its size, the phone's
 * readings - and under it the note's log (ai/log.ts): every run, newest
 * first, each with its own Undo.
 *
 * It draws nothing at all for a note with no run to speak of, so a note
 * looks as it always did until the AI is asked.
 */
export function AiStrip({
  noteId,
  onUndo,
  onHeight,
  marks,
  stage = null,
}: {
  noteId: string;
  /** The review's own stages before its run - listening again, comparing - said while no run is on (ai/useNoteReview.ts). */
  stage?: ReviewStage | null;
  /** The AI's changes still marked in the note, and the way to keep them all at once; absent with none. */
  marks?: { count: number; keepAll: () => void };
  /**
   * Puts the note back as it was before a run, if the note still reads as the run left it; answers whether it did.
   * Absent where the note cannot be written (a shared page).
   */
  onUndo?: (record: RunRecord) => boolean;
  /** How tall the strip is, told as it changes, so the page can make room under it. */
  onHeight?: (height: number) => void;
}) {
  const run = useRun(noteId);
  const log = useRunLog(noteId);
  const [open, setOpen] = useState(false);
  const host = useRef<HTMLElement>(null);
  // A new run closes the card: the line is what matters while it works.
  const runId = run?.id;
  useEffect(() => setOpen(false), [runId]);

  // The page makes room under the strip: its height, as it changes, and 0 once it is gone.
  const shown = run !== null || stage !== null || (marks !== undefined && marks.count > 0);
  useEffect(() => {
    if (!onHeight) return undefined;
    const el = host.current;
    if (!el) {
      onHeight(0);
      return undefined;
    }
    const tell = () => onHeight(el.offsetHeight);
    tell();
    if (typeof ResizeObserver === 'undefined') return () => onHeight(0);
    const watched = new ResizeObserver(tell);
    watched.observe(el, { box: 'border-box' });
    return () => {
      watched.disconnect();
      onHeight(0);
    };
  }, [onHeight, shown]);

  if (!shown) return null;

  // The review listening again or comparing: the stage as a line of its own, with its percent along the foot.
  if (!run && stage) {
    return (
      <section ref={host} className={styles.strip} data-phase="stage" aria-label="The AI on this note">
        <div className={styles.row}>
          <span className={styles.line}>
            <Ear size={16} strokeWidth={2.2} className={styles.icon} aria-hidden="true" />
            <span className={styles.words} role="status" aria-live="polite">
              {stage.what}
              {stage.percent !== null && stage.percent > 0 ? `, ${stage.percent}%` : ''}. {stage.detail}
            </span>
          </span>
        </div>
        <div className={styles.bar} aria-hidden="true" data-going={stage.percent === null || undefined}>
          <span style={{ inlineSize: stage.percent === null ? undefined : `${Math.round(stage.percent)}%` }} />
        </div>
      </section>
    );
  }

  // No run to speak of, only marks left in the note: one line saying so, with Keep all.
  if (!run) {
    return (
      <section ref={host} className={styles.strip} data-phase="marks" aria-label="The AI on this note">
        <div className={styles.row}>
          <span className={styles.line}>
            <PenLine size={16} strokeWidth={2.2} className={styles.icon} aria-hidden="true" />
            <span className={styles.words} role="status">
              {marksSentence(marks?.count ?? 0)}
            </span>
          </span>
          <button type="button" className={styles.action} onClick={marks?.keepAll} aria-label="Keep every change">
            <Check size={15} strokeWidth={2.4} aria-hidden="true" />
            <span>Keep all</span>
          </button>
        </div>
      </section>
    );
  }

  const Icon = PHASE_ICONS[run.phase];
  const over = ended(run);
  const share = progressOf(run);
  const sentence = runSentence(run);
  const newest = log.find((r) => r.id === run.id);
  const undoable = over && newest?.before !== undefined && onUndo !== undefined;

  return (
    <section ref={host} className={styles.strip} data-phase={run.phase} aria-label="The AI on this note">
      <div className={styles.row}>
        <button type="button" className={styles.line} onClick={() => setOpen((was) => !was)} aria-expanded={open}>
          <Icon size={16} strokeWidth={2.2} className={styles.icon} data-spin={spins(run.phase) || undefined} aria-hidden="true" />
          <span className={styles.words} role="status" aria-live="polite">
            {sentence}
          </span>
          {open ? <ChevronUp size={16} strokeWidth={2.2} className={styles.chevron} aria-hidden="true" /> : <ChevronDown size={16} strokeWidth={2.2} className={styles.chevron} aria-hidden="true" />}
        </button>
        {over && marks && marks.count > 0 ? (
          <button type="button" className={styles.action} onClick={marks.keepAll} aria-label="Keep every change">
            <Check size={15} strokeWidth={2.4} aria-hidden="true" />
            <span>Keep all</span>
          </button>
        ) : null}
        {!over ? (
          <button type="button" className={styles.action} onClick={() => void cancelRun(noteId)} aria-label="Stop">
            <Square size={14} strokeWidth={2.4} aria-hidden="true" />
            <span>Stop</span>
          </button>
        ) : null}
        {undoable && newest ? (
          <button type="button" className={styles.action} onClick={() => onUndo?.(newest)} aria-label="Undo this run">
            <Undo2 size={15} strokeWidth={2.4} aria-hidden="true" />
            <span>Undo</span>
          </button>
        ) : null}
        {over ? (
          <button type="button" className={styles.dismiss} onClick={() => dismissRun(noteId)} aria-label="Put this away">
            <X size={15} strokeWidth={2.4} aria-hidden="true" />
          </button>
        ) : null}
      </div>
      <div className={styles.bar} aria-hidden="true" data-going={(!over && share === null) || undefined}>
        <span style={{ inlineSize: share === null ? undefined : `${Math.round(share * 100)}%` }} />
      </div>
      {open ? (
        <div className={styles.card}>
          {run.thought ? <Thought text={run.thought} live={!over} /> : null}
          {!over ? (
            <AiCard
              model={run.model}
              phase={cardPhase(run)}
              doing={kindWords(run.kind).doing}
              promptTokens={run.promptTokens}
              promptTokensDone={run.promptTokensDone}
              outputTokens={run.outputTokens}
              tokensPerSecond={run.tokensPerSecond}
              elapsedMs={run.elapsedMs}
              hardware={run.hardware}
            />
          ) : null}
          <RunLog records={log} onUndo={onUndo} />
        </div>
      ) : null}
    </section>
  );
}

/** The model's own thinking, raw, in a quiet pane that follows the newest line while it streams (Matt: "show the AI reasoning"). */
function Thought({ text, live }: { text: string; live: boolean }) {
  const pane = useRef<HTMLPreElement>(null);
  useEffect(() => {
    const el = pane.current;
    if (el && live) el.scrollTop = el.scrollHeight;
  }, [text, live]);
  return (
    <pre ref={pane} className={styles.thought} aria-label="The model's thinking" data-live={live || undefined}>
      {text}
    </pre>
  );
}

/** The note's runs, newest first: each its kind's icon, one sentence, when, and Undo where it still applies. */
function RunLog({ records, onUndo }: { records: readonly RunRecord[]; onUndo?: (record: RunRecord) => boolean }) {
  if (!records.length) return <p className={styles.none}>Nothing yet.</p>;
  return (
    <ol className={styles.log} aria-label="What the AI did to this note">
      {records.map((record) => {
        const Icon = KIND_ICONS[record.kind];
        return (
          <li key={record.id} className={styles.entry} data-outcome={record.outcome}>
            <Icon size={15} strokeWidth={2.2} className={styles.entryIcon} aria-hidden="true" />
            <span className={styles.entryWords}>
              {recordSentence(record)} <span className={styles.entryWhen}>{when(record.at)}</span>
            </span>
            {record.before !== undefined && onUndo ? (
              <button type="button" className={`app-word ${styles.entryUndo}`} onClick={() => onUndo(record)}>
                Undo
              </button>
            ) : null}
          </li>
        );
      })}
    </ol>
  );
}
