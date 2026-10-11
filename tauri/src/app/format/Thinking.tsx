import type { Phase } from '../core/ai.ts';
import styles from './Thinking.module.css';

/**
 * The little reader, for the wait before the first word.
 *
 * Loading a model and reading the note are the two stretches where nothing
 * arrives for the person to watch - ten seconds to a minute on a phone - so
 * something on the page has to be alive. Matt asked for "a robot doing things
 * or a fun abstract animation": this is a robot made of the app's own shapes,
 * on currentColor like everything in art/Shapes.tsx. A rounded square for a
 * head with two dots for eyes and an antenna; under it, three bars, the note.
 *
 * Two acts, by phase. Loading: the antenna's dot blinks and the eyes are shut
 * (two short bars), the machine warming up. Reading: the eyes open and sweep
 * left to right along each bar in turn, and the bar being read is ink while
 * the others wait in grey. It leaves the moment the first word is written.
 * Under reduced motion the eyes and the antenna hold still.
 */
export function Thinking({ phase }: { phase: Phase }) {
  const reading = phase === 'prefill' || phase === 'generating';
  return (
    <div className={styles.stage} data-phase={reading ? 'reading' : 'loading'} aria-hidden="true">
      <svg viewBox="0 0 120 120" className={styles.robot}>
        {/* the antenna */}
        <line x1="60" y1="16" x2="60" y2="30" stroke="currentColor" strokeWidth="4" strokeLinecap="round" />
        <circle className={styles.beacon} cx="60" cy="12" r="5" fill="currentColor" />
        {/* the head */}
        <rect x="32" y="30" width="56" height="44" rx="12" fill="none" stroke="currentColor" strokeWidth="4" />
        {/* eyes: closed while loading, open and sweeping while reading */}
        <g className={styles.eyes}>
          <circle className={styles.eye} cx="48" cy="50" r="4.5" fill="currentColor" />
          <circle className={styles.eye} cx="72" cy="50" r="4.5" fill="currentColor" />
          <line className={styles.lid} x1="42" y1="50" x2="54" y2="50" stroke="currentColor" strokeWidth="4" strokeLinecap="round" />
          <line className={styles.lid} x1="66" y1="50" x2="78" y2="50" stroke="currentColor" strokeWidth="4" strokeLinecap="round" />
        </g>
        {/* the note: three lines it reads */}
        <g className={styles.lines}>
          <rect className={styles.line1} x="22" y="86" width="76" height="6" rx="3" fill="currentColor" />
          <rect className={styles.line2} x="22" y="98" width="56" height="6" rx="3" fill="currentColor" />
          <rect className={styles.line3} x="22" y="110" width="66" height="6" rx="3" fill="currentColor" />
        </g>
      </svg>
    </div>
  );
}
