import styles from './CanvasView.module.css';

/**
 * The cross that takes something off the canvas: an open card, a group, a picture, a picked line (canvas/Card.tsx,
 * canvas/LineWords.tsx). One button in one look, told apart by what its label says it takes off.
 */
export function Remove({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <button type="button" className={styles.remove} onClick={() => onPress()} aria-label={label}>
      ×
    </button>
  );
}
