import { FileText, Mic, RefreshCw } from '@glacier/icons';
import { WispText } from '../../art/WispText.tsx';
import styles from '../Guide.module.css';

const POINTS = [
  { icon: Mic, label: 'Say it or type it' },
  { icon: FileText, label: 'Plain Markdown files' },
  { icon: RefreshCw, label: 'The same on every device' },
] as const;

/**
 * The first page: what Ghost.md is, in one line and three points (Matt: "revamp the welcome flow remove the AI warning
 * page"). It used to be a heads-up that the app uses AI, with gags played over it, before anything about notes. The
 * name comes out of smoke like the app's other headlines, and the points pop in after it. There is no picture: the
 * launch screen showed the icon a moment ago, and Matt asked for the ghost off this page before.
 */
export function Welcome() {
  return (
    <>
      <h1 className={styles.title}>
        <WispText text="Welcome to Ghost.md" pace={16} />
      </h1>
      <p className={styles.lead}>Notes you type or say. Plain Markdown, kept on your own devices, the same on every one.</p>
      <ul className={styles.promises} aria-label="What Ghost.md does">
        {POINTS.map(({ icon: Icon, label }, index) => (
          <li key={label} className={styles.promise} style={{ animationDelay: `${420 + index * 120}ms` }}>
            <span className={styles.promiseIcon} aria-hidden="true">
              <Icon size={18} strokeWidth={2.4} />
            </span>
            {label}
          </li>
        ))}
      </ul>
    </>
  );
}
