import styles from './CaptureScreen.module.css';

/**
 * The recorder's two pictures, drawn in the app's own ink: sound beginning,
 * and a sentence coming to a stop.
 *
 * Abstract, like the rest of the artwork - a dot and three arcs opening to the
 * right; a bar ending in a dot. `Opening` plays as the microphone opens (each
 * arc arrives in turn) and is the whole screen until the first words land;
 * `Saved` takes its place while the note is being written. Both are single
 * colour so they invert with the theme.
 */

export function Opening({ failed = false }: { failed?: boolean }) {
  return (
    <svg viewBox="0 0 160 120" className={styles.picture} data-failed={failed ? '' : undefined} aria-hidden="true">
      <circle cx="40" cy="60" r="7" className={styles.pictureInk} />
      {[24, 44, 64].map((r, i) => (
        <path
          key={r}
          d={`M${40 + r * Math.cos(-0.9)} ${60 + r * Math.sin(-0.9)} A${r} ${r} 0 0 1 ${40 + r * Math.cos(0.9)} ${60 + r * Math.sin(0.9)}`}
          className={styles.pictureArc}
          style={{ animationDelay: `${180 + i * 220}ms` }}
          strokeDasharray={failed ? '6 7' : undefined}
        />
      ))}
    </svg>
  );
}

export function Saved() {
  return (
    <svg viewBox="0 0 160 120" className={styles.picture} aria-hidden="true">
      <rect x="28" y="54" width="82" height="12" rx="6" className={styles.pictureInk} />
      <circle cx="126" cy="60" r="7" className={`${styles.pictureInk} ${styles.pictureDot}`} />
    </svg>
  );
}
