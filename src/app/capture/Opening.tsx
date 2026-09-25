import styles from './CaptureScreen.module.css';

/**
 * The recorder's picture of sound beginning, drawn in the app's own ink: a dot and three arcs opening to the right.
 *
 * Abstract, like the rest of the artwork. It plays as the microphone opens, each arc arriving in turn, and stays,
 * dashed, when the microphone never did (CaptureScreen.tsx's failed state). Single colour, so it inverts with the
 * theme.
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
