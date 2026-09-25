import { useEffect, useRef, useState } from 'react';
import { ArrowUp, Download, Sparkles } from '@glacier/icons';
import { gb, modelName, MODELS } from '../core/ai.ts';
import type { Availability } from './available.ts';
import { KIND_ICONS } from './icons.ts';
import { CHIP_KINDS, kindWords, type RunKind } from './kinds.ts';
import type { RunScope } from './runs.ts';
import { useReportedHeight } from './useReportedHeight.ts';
import styles from './PromptBar.module.css';

/**
 * The prompt bar: how a person asks the AI for something on the note.
 *
 * Matt: a bar at the bottom of the note for free text, with quick chips, and
 * a floating Ask over a selection for scoped edits - and, on a selection, a
 * choice each time between this part and the whole note. So: a row of chips
 * for the six things asked for daily (Format, Summarize, Enhance, Fix
 * spelling, Make a list, Continue), and under it a field for anything else,
 * sent with Enter or the arrow. A chip or a sent instruction with words
 * selected in the note first asks which: this part, or the whole note; the
 * press-and-hold menu's Ask opens the bar with the part already chosen
 * (NoteScreen.tsx). Where the AI cannot run, the bar shows, greyed, with the
 * reason in the field and a way to get a model when that is the fix
 * (ai/available.ts).
 *
 * It floats at the foot of the note and the page makes room under it, the
 * way the strip does at the head; on a phone the activity shortens the page
 * for the keyboard, so the bar rises with it.
 */
export function PromptBar({
  availability,
  onRun,
  onGet,
  scope,
  onScopeUsed,
  focusAsk = 0,
  onHeight,
  disabled = false,
  onHide,
}: {
  availability: Availability;
  /** Runs a kind on the note, or on `scope` when given, with the instruction for a kind that takes one. */
  onRun: (kind: RunKind, instruction: string | undefined, scope: RunScope | null) => void;
  /** Gets a model, when getting one is what the AI needs. */
  onGet?: (model: string) => void;
  /**
   * Words selected in the note, as offsets in it: the Ask over a selection hands them here, and a chip or an
   * instruction then asks which - this part or the whole note - before it runs. Null with nothing selected.
   */
  scope: RunScope | null;
  /** The choice was made and the run started, or the person chose the whole note: the scope is spent. */
  onScopeUsed?: () => void;
  /** Rises to put the caret in the field: the Ask over a selection. */
  focusAsk?: number;
  /** How tall the bar is, told as it changes, so the page can make room under it. */
  onHeight?: (height: number) => void;
  /** Nothing to ask on: a canvas, a book's index, the transcript playing. The bar steps out. */
  disabled?: boolean;
  /**
   * Puts the bar away (editor/NoteScreen.tsx, core/preferences.ts `aiBar`): given, the spark at the start of the
   * field is the button that hides it, the same ✨ that showed it from the foot of the note.
   */
  onHide?: () => void;
}) {
  const [words, setWords] = useState('');
  /** A kind chosen with words selected, waiting to hear which part it is for. */
  const [pending, setPending] = useState<{ kind: RunKind; instruction: string | undefined } | null>(null);
  const field = useRef<HTMLInputElement>(null);
  const host = useRef<HTMLElement>(null);

  useEffect(() => {
    if (focusAsk) field.current?.focus();
  }, [focusAsk]);

  // The page makes room under the bar: its height, as it changes, and 0 once it is gone.
  useReportedHeight(host, onHeight, !disabled);

  // A selection gone (the person tapped elsewhere): a choice waiting on it goes too.
  useEffect(() => {
    if (!scope) setPending(null);
  }, [scope]);

  if (disabled) return null;

  const ready = availability.ok;
  const reason = availability.ok ? null : availability.reason;
  const get = availability.ok ? null : availability.get;
  const spec = get ? MODELS.find((m) => m.id === get) : null;

  const ask = (kind: RunKind, instruction?: string) => {
    if (!ready) return;
    if (scope && scope.to > scope.from) {
      setPending({ kind, instruction });
      return;
    }
    onRun(kind, instruction, null);
    if (kind === 'ask') setWords('');
  };
  const choose = (which: 'part' | 'note') => {
    if (!pending) return;
    onRun(pending.kind, pending.instruction, which === 'part' ? scope : null);
    if (pending.kind === 'ask') setWords('');
    setPending(null);
    onScopeUsed?.();
  };
  const send = () => {
    const instruction = words.trim();
    if (!instruction) return;
    ask('ask', instruction);
  };

  return (
    <section ref={host} className={styles.bar} aria-label="Ask the AI" data-ready={ready || undefined}>
      {pending ? (
        <div className={styles.chips} role="group" aria-label="Which part">
          <span className={styles.which}>{pending.kind === 'ask' ? `“${pending.instruction ?? ''}”` : kindWords(pending.kind).label}, on</span>
          <button type="button" className={styles.chip} data-scope="" onClick={() => choose('part')}>
            This part
          </button>
          <button type="button" className={styles.chip} data-scope="" onClick={() => choose('note')}>
            The whole note
          </button>
          <button type="button" className={`app-word ${styles.never}`} onClick={() => setPending(null)}>
            Never mind
          </button>
        </div>
      ) : (
        <div className={styles.chips} role="group" aria-label="Quick asks">
          {CHIP_KINDS.map((kind) => {
            const Icon = KIND_ICONS[kind];
            const w = kindWords(kind);
            return (
              <button key={kind} type="button" className={styles.chip} onClick={() => ask(kind)} disabled={!ready} title={w.hint}>
                <Icon size={14} strokeWidth={2.2} aria-hidden="true" />
                <span>{w.label}</span>
              </button>
            );
          })}
        </div>
      )}
      <form
        className={styles.row}
        onSubmit={(event) => {
          event.preventDefault();
          send();
        }}
      >
        {onHide ? (
          <button type="button" className={`${styles.spark} ${styles.sparkButton}`} onClick={onHide} aria-label="Hide the AI bar" aria-expanded="true">
            <Sparkles size={18} strokeWidth={2.1} aria-hidden="true" />
          </button>
        ) : (
          <Sparkles size={18} strokeWidth={2.1} className={styles.spark} aria-hidden="true" />
        )}
        <input
          ref={field}
          className={styles.field}
          type="text"
          value={words}
          onChange={(event) => setWords(event.target.value)}
          placeholder={reason ?? (scope && scope.to > scope.from ? 'Ask about the selected words' : 'Ask the AI to change the note')}
          aria-label="What to ask the AI"
          disabled={!ready}
          enterKeyHint="send"
          autoComplete="off"
          autoCorrect="on"
          spellCheck
        />
        {get && spec ? (
          <button type="button" className={`app-word ${styles.get}`} onClick={() => onGet?.(get)}>
            <Download size={15} strokeWidth={2.4} aria-hidden="true" />
            <span>
              Get {modelName(get)} ({gb(spec.bytes)})
            </span>
          </button>
        ) : (
          <button type="submit" className={styles.send} disabled={!ready || !words.trim()} aria-label="Send">
            <ArrowUp size={18} strokeWidth={2.4} aria-hidden="true" />
          </button>
        )}
      </form>
    </section>
  );
}
