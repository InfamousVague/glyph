import { isTypeface, TYPEFACES, type Typeface } from '../core/preferences.ts';
import styles from './TypefaceCards.module.css';

/**
 * The typefaces as small cards (Matt: "show the fonts as small cards on the app with markdown symbols like a # Quick &
 * Foxy or something to preview what each font looks like"). Each card sets the same scrap of a note in its own face -
 * a heading with its hash, an ampersand, bold between its stars, and the pairs a coding face joins into one sign - so
 * the ampersand's shape and the ligatures are seen before the face is chosen. The marks are dimmed as the editor dims
 * them. A card's face is loaded the moment the card is drawn (typefaces.css registers every one), so the preview is
 * the face itself.
 */

interface Face {
  label: string;
  /** The family as its @font-face names it. */
  family: string;
  /** A monospace coding face: its ligatures on and its letters unspaced, as the app sets it (typefaces.css). */
  coding?: boolean;
}

const FACES: Record<Typeface, Face> = {
  inter: { label: 'Inter', family: "'Inter Variable'" },
  noto: { label: 'Noto', family: "'Noto Sans Variable'" },
  plex: { label: 'Plex', family: "'IBM Plex Sans'" },
  maple: { label: 'Maple Mono', family: "'Maple Mono'", coding: true },
  fira: { label: 'Fira Code', family: "'Fira Code Variable'", coding: true },
};

interface TypefaceCardsProps {
  value: Typeface;
  onValueChange: (value: Typeface) => void;
}

export function TypefaceCards({ value, onValueChange }: TypefaceCardsProps) {
  return (
    <div className={styles.grid} role="radiogroup" aria-label="Typeface">
      {TYPEFACES.map((face) => {
        const { label, family, coding } = FACES[face];
        const selected = face === value;
        return (
          <label key={face} className={styles.card} data-selected={selected || undefined} data-coding={coding || undefined}>
            <input
              className={styles.input}
              type="radio"
              name="typeface"
              value={face}
              aria-label={label}
              checked={selected}
              onChange={() => {
                if (isTypeface(face)) onValueChange(face);
              }}
            />
            <div className={styles.sample} style={{ fontFamily: `${family}, ui-sans-serif, system-ui, sans-serif` }} aria-hidden="true">
              <div className={styles.heading}>
                <b className={styles.mark}>#</b> Quick &amp; Foxy
              </div>
              <div className={styles.line}>
                <b className={styles.mark}>**</b>
                <b>bold</b>
                <b className={styles.mark}>**</b> -&gt; != &lt;=
              </div>
            </div>
            <strong className={styles.name}>{label}</strong>
          </label>
        );
      })}
    </div>
  );
}
