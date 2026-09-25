import type { ReactNode } from 'react';
import styles from '../Guide.module.css';

/**
 * The two pieces more than one guide page is built of: a row of a choice asked up front (the theme page's, the model
 * page's), and a numbered step with its line of explanation (the side-key page's, the habits page's). One of each, so
 * a chosen row is marked the same way on every page that asks.
 */

interface ChoiceProps {
  label: string;
  /** The line under the label. */
  hint: string;
  /** Whether this is the choice made. */
  on: boolean;
  onPick: () => void;
  /** What the swatch shows: the choice itself, drawn ("Aa" in its colours), or the one number that decides it. */
  swatch: ReactNode;
  /** A class the swatch takes beside its own. */
  swatchClass?: string;
  /** The swatch's `data-swatch`, for a stylesheet that colours it by name. */
  swatchName?: string;
}

/**
 * One radio of a page's radiogroup. The chosen row is printed in reverse (`app-inverse`) and carries `data-selected`
 * for its swatch; a tap is the choice, with nothing to confirm.
 */
export function Choice({ label, hint, on, onPick, swatch, swatchClass, swatchName }: ChoiceProps) {
  return (
    <button type="button" role="radio" aria-checked={on} className={`${styles.choice} ${on ? 'app-inverse' : ''}`} data-selected={on ? '' : undefined} onClick={onPick}>
      <span className={swatchClass ? `${styles.swatch} ${swatchClass}` : styles.swatch} data-swatch={swatchName} aria-hidden="true">
        {swatch}
      </span>
      <span className={styles.choiceText}>
        <span className={styles.stepTitle}>{label}</span>
        <span className={styles.note}>{hint}</span>
      </span>
    </button>
  );
}

/** One step of a page's numbered list: what to do, anything that shows how, and then the line that says why. */
export function Step({ title, note, children }: { title: string; note?: string; children?: ReactNode }) {
  return (
    <li>
      <h2 className={styles.stepTitle}>{title}</h2>
      {children}
      {note ? <p className={styles.note}>{note}</p> : null}
    </li>
  );
}
