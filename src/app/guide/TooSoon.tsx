import { WispText } from '../art/WispText.tsx';
import styles from './TooSoon.module.css';

/**
 * The one line for a reader who held the side key before the guide got to
 * it (tooSoon.ts): sassy, not cheesy, and out of smoke like the rest of the
 * page. Matt: "maybe just 'not yet, finish reading.'"
 */
export function TooSoon() {
  return (
    <p className={styles.tooSoon} role="status">
      <WispText text="Not yet, finish reading." pace={18} />
    </p>
  );
}
