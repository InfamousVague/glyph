import { SignInFlow } from '../settings/AccountPane.tsx';
import styles from './AccountGate.module.css';

/**
 * The first screen on open, while signed out (shell/useAccountGate.ts): the way into an account - sign in, make one,
 * or recover one - over everything, before the walkthrough (Matt: "move the login / signup flow to the first thing that
 * happens when you open the app"), as one plain card that asks you to sign in or sign up (settings/AccountPane.tsx
 * `SignInFlow`; Matt: "remove the graphic on the sign in page"). Its form is the Account page's own, so the checks and
 * the recovery codes are the same in both places.
 *
 * An account is not needed: notes live on the device either way, so the last line goes on without one, and the way in
 * stays in Settings › Account.
 */
export function AccountGate({ onDone }: { onDone: () => void }) {
  return (
    <div className={styles.gate} role="dialog" aria-modal="true" aria-label="Sign in to Ghost.md">
      {/* The Mac's title bar is this screen's top: it still drags the window. */}
      <div className={styles.drag} data-tauri-drag-region aria-hidden="true" />
      <div className={styles.column}>
        <SignInFlow onIn={onDone} />
        <button type="button" className={`app-word ${styles.skip}`} onClick={onDone}>
          Use without an account
        </button>
      </div>
    </div>
  );
}
