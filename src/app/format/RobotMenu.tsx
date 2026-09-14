import { useEffect, useRef, useState } from 'react';
import { Robot } from '../art/Icons.tsx';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { MODES, type Mode } from './modes.ts';
import styles from './RobotMenu.module.css';

/**
 * The robot: the one button for everything the model does to a note.
 *
 * Matt: "make all of these buttons instead of the segmented toggle, make a
 * robot drop-down button for these options". A ring in the header, beside
 * the cog, that drops a short list - Format, Summarize, Enhance, each with a
 * line on what it does - and, while one of them is showing, "Back to note".
 * Choosing a mode opens that mode's view over the note; the note itself is
 * never changed by looking (Apply is what changes it).
 *
 * It leaves on a choice, a touch elsewhere, Escape, or the back gesture.
 */
export function RobotMenu({ mode, onChoose }: { mode: Mode | null; onChoose: (mode: Mode | null) => void }) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return undefined;
    const outside = (event: PointerEvent) => {
      if (root.current && event.target instanceof Node && root.current.contains(event.target)) return;
      setOpen(false);
    };
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    document.addEventListener('pointerdown', outside, true);
    document.addEventListener('keydown', key);
    return () => {
      document.removeEventListener('pointerdown', outside, true);
      document.removeEventListener('keydown', key);
    };
  }, [open]);

  useBack(open, () => setOpen(false));

  const choose = (next: Mode | null) => {
    fireNativeHaptic('selection');
    setOpen(false);
    onChoose(next);
  };

  return (
    <div ref={root} className={styles.root}>
      <button
        type="button"
        className={styles.button}
        data-active={mode !== null || undefined}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={mode ? `The robot: showing ${MODES.find((m) => m.id === mode)?.label ?? mode}` : 'The robot: format, summarize or enhance this note'}
        onClick={() => setOpen((was) => !was)}
      >
        <Robot />
        <svg viewBox="0 0 24 24" className={styles.caret} aria-hidden="true">
          <path d="M7 10l5 5 5-5" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {open ? (
        <div className={styles.menu} role="menu" aria-label="What the robot can do">
          {MODES.map((words) => (
            <button
              key={words.id}
              type="button"
              role="menuitemradio"
              aria-checked={mode === words.id}
              className={styles.item}
              onClick={() => choose(words.id)}
            >
              <span className={styles.label}>{words.label}</span>
              <span className={styles.hint}>{words.hint}</span>
            </button>
          ))}
          {mode !== null ? (
            <button type="button" role="menuitem" className={`${styles.item} ${styles.back}`} onClick={() => choose(null)}>
              <span className={styles.label}>Back to note</span>
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
