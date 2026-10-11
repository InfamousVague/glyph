import type { ReactNode } from 'react';
import styles from '../Guide.module.css';

/**
 * The piece more than one guide page is built of: a row of a choice asked up front (the theme page's, the model
 * page's), so a chosen row is marked the same way on every page that asks. The numbered step that was here went with
 * the side-key page and the habits page (docs/DESIGN.md §173).
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
