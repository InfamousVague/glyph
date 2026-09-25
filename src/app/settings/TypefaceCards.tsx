import { isCodingFace, type Typeface } from '../core/preferences.ts';
import styles from './TypefaceCards.module.css';
import { FACE_WORDS } from './words.ts';

/**
 * Typefaces as small cards (Matt: "show the fonts as small cards on the app with markdown symbols like a # Quick &
 * Foxy or something to preview what each font looks like"), for either of the two faces the app is set in (Matt:
 * "font pairs ... make both kinds of fonts pickable"). A note face's card sets the same scrap of a note in it - a
 * heading with its hash, an ampersand, bold between its stars, and the pairs a coding face joins into one sign - with
 * the marks dimmed as the editor dims them. An interface face's card sets a scrap of the app's own words instead: a
 * title and a row of tabs. A card's face is loaded the moment it is drawn (typefaces.css registers every one), so the
 * preview is the face itself.
 */

/** The family each face is set in (typefaces.css registers them); what it is called is words.ts. */
const FAMILIES: Record<Typeface, string> = {
  maple: "'Maple Mono'",
  fira: "'Fira Code Variable'",
  inter: "'Inter Variable'",
  noto: "'Noto Sans Variable'",
  plex: "'IBM Plex Sans'",
};

interface TypefaceCardsProps<F extends Typeface> {
  faces: readonly F[];
  value: F;
  onValueChange: (value: F) => void;
  /** What the choice is, for a screen reader, and the radios' shared name. */
  label: string;
  /** A note's face previews Markdown; the interface's previews the app's own words. */
  kind: 'note' | 'interface';
}

export function TypefaceCards<F extends Typeface>({ faces, value, onValueChange, label, kind }: TypefaceCardsProps<F>) {
  return (
    <div className={styles.grid} role="radiogroup" aria-label={label}>
      {faces.map((face) => {
        const name = FACE_WORDS[face];
        const family = FAMILIES[face];
        const selected = face === value;
        return (
          <label key={face} className={styles.card} data-selected={selected || undefined} data-coding={isCodingFace(face) || undefined}>
            <input className={styles.input} type="radio" name={label} value={face} aria-label={name} checked={selected} onChange={() => onValueChange(face)} />
            <div className={styles.sample} style={{ fontFamily: `${family}, ui-sans-serif, system-ui, sans-serif` }} aria-hidden="true">
              {kind === 'note' ? (
                <>
                  <div className={styles.heading}>
                    <b className={styles.mark}>#</b> Quick &amp; Foxy
                  </div>
                  <div className={styles.line}>
                    <b className={styles.mark}>**</b>
                    <b>bold</b>
                    <b className={styles.mark}>**</b> -&gt; != &lt;=
                  </div>
                </>
              ) : (
                <>
                  <div className={styles.title}>Notes &amp; Books</div>
                  <div className={styles.tabs}>
                    <span className={styles.tab} data-on="">
                      Today
                    </span>
                    <span className={styles.tab}>Recent</span>
                    <span className={styles.tab}>Settings</span>
                  </div>
                </>
              )}
            </div>
            <strong className={styles.name}>{name}</strong>
          </label>
        );
      })}
    </div>
  );
}
