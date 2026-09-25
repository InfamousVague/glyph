import { setPreferences, usePreferences, type ThemePref } from '../../core/preferences.ts';
import styles from '../Guide.module.css';

const THEME_CHOICES: Array<{ value: ThemePref; label: string; hint: string }> = [
  { value: 'dark', label: 'Dark', hint: 'Light words on black. Easier on the eyes at night.' },
  { value: 'light', label: 'Light', hint: 'Dark words on white, like paper.' },
  { value: 'system', label: 'Match the phone', hint: 'Follows your phone’s dark mode.' },
];

/**
 * Light or dark, asked up front, because in an app that is almost all type the
 * ground behind the words is most of the look. Each choice applies the moment
 * it is tapped - the guide itself changes colour under the thumb - so the
 * person decides by seeing, not by imagining. Changeable any time in Settings.
 * Nothing puts the old theme back if the person skips on: the choice is the
 * preference, and there is no preview to undo.
 *
 * The page used to flick the theme on and off by itself a few times, to show there was a choice (GloveSwitch, since
 * removed: Matt, "remove the effect that flicks it on and off and whatnot automatically it's annoying"). It stays
 * still now until a choice is tapped.
 */
export function Theme() {
  const { theme } = usePreferences();
  return (
    <>
      <h1 className={styles.title}>Light or dark?</h1>
      <p className={styles.lead}>Pick one to see it. You can change it later in Settings.</p>
      <div className={styles.choices} role="radiogroup" aria-label="Theme">
        {THEME_CHOICES.map((choice) => (
          <button
            key={choice.value}
            type="button"
            role="radio"
            aria-checked={theme === choice.value}
            className={`${styles.choice} ${theme === choice.value ? 'app-inverse' : ''}`}
            data-selected={theme === choice.value ? '' : undefined}
            onClick={() => setPreferences({ theme: choice.value })}
          >
            <span className={styles.swatch} data-swatch={choice.value} aria-hidden="true">
              Aa
            </span>
            <span className={styles.choiceText}>
              <span className={styles.stepTitle}>{choice.label}</span>
              <span className={styles.note}>{choice.hint}</span>
            </span>
          </button>
        ))}
      </div>
    </>
  );
}
