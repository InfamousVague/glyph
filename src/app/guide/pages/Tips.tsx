import { Tips as TipsArt } from '../../art/Shapes.tsx';
import styles from '../Guide.module.css';

/**
 * The last page: how to talk so the cues are heard. Every habit here is one the speech rules keep
 * (capture/markdown.ts) - a cue at the start of a sentence, a cue said on its own, a pause for a paragraph - and
 * guide/guide.test.ts holds the rules to them through the spoken examples in guide/phrases.ts. The cues' own words
 * are on the marks page, beside each mark (guide/marks.ts `say`).
 */
export function Tips() {
  return (
    <>
      <TipsArt className={styles.art} />
      <h1 className={styles.title}>A few habits.</h1>
      <ol className={styles.steps}>
        <li>
          <h2 className={styles.stepTitle}>Pause before a cue word.</h2>
          <p className={styles.note}>A short pause before “heading” or “bullet point” starts a new sentence. That’s where Ghost.md listens for cues.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Or say the cue on its own.</h2>
          <p className={styles.note}>“Bullet point.” Pause. “Oat milk.” The cue waits for the next thing you say.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Stop for two seconds to start a paragraph.</h2>
          <p className={styles.note}>You don’t have to say it. The pause does it.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Talk normally.</h2>
          <p className={styles.note}>Ghost.md picks lists and to-dos out of normal speech. It never changes your words, only how they’re laid out.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Fix it after.</h2>
          <p className={styles.note}>A voice note lands at the top of your notes. Open it to fix anything. The markdown is all there.</p>
        </li>
      </ol>
    </>
  );
}
