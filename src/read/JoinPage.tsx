import { appJoinLink } from '../app/core/orgs/joinLinks.ts';
import { APP_URL, INSTALL_URL } from './places.ts';
import styles from './Reader.module.css';

/**
 * The page an invite link opens (docs/TEAMS.md, "Invite by link"): `read.html#join=<code>`. It knows nothing of the
 * organization - the code is only shown to the service by someone signed in - so it says what the link is and offers
 * the two ways in, the app (`ghostmd://join/<code>`, src-tauri/src/links.rs) and the web app (`#join=<code>`), each of
 * which asks "Join it?" with the organization's name before anything is joined (notes/JoinSheet.tsx).
 */
export function JoinPage({ code }: { code: string }) {
  return (
    <>
      <header className={styles.banner}>
        <div className={styles.bannerInner}>
          <span className={styles.brand}>Ghost.md</span>
          <span className={styles.pitch}>
            <span className={styles.pitchMore}>Notes you write by typing or by voice. </span>
            <a className={styles.getApp} href={INSTALL_URL}>
              Get the app
            </a>
          </span>
        </div>
      </header>
      <main className={styles.page}>
        <section className={styles.save} aria-labelledby="join-title">
          <h1 id="join-title" className={styles.joinTitle}>
            You’re invited to a team
          </h1>
          <p>Open the link in Ghost.md to see which organization it is and join it. You’ll need an account; signing up takes a handle and a password.</p>
          <span className={styles.saveWays}>
            <a className={styles.primary} href={appJoinLink(code)}>
              Open in the Ghost.md app
            </a>
            <a className={styles.action} href={`${APP_URL}#join=${code}`}>
              Join on the web
            </a>
          </span>
          <p className={styles.quiet}>
            If the app doesn’t open, it may be an older one: update it, or join on the web. No app yet?{' '}
            <a className={styles.getApp} href={INSTALL_URL}>
              Get Ghost.md
            </a>
            .
          </p>
        </section>
      </main>
    </>
  );
}
