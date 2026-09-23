import { useEffect, useRef, useState } from 'react';
import { Check, CircleAlert, LoaderCircle } from '@glacier/icons';
import type { Updates } from '../core/ota.ts';
import type { SyncStatus } from '../core/sync/engine.ts';
import { isTauri } from '../core/tauri.ts';
import icon from './ghost-icon.webp';
import styles from './LaunchScreen.module.css';

/**
 * What the app shows while it opens (Matt: "I want a loading screen with the logo and checking for updates and stuff
 * and show statuses for checking for updates etc"): the icon, the name, and a line for each thing opening does, each
 * turning to a tick as it's done. The lines are the real steps, not a show: the notes read from the library, the
 * update check (asked now, on the app, rather than after the usual settling pause), and the account's sync when
 * there is one.
 *
 * It goes when the notes are read and the update check has answered, or three seconds on, whichever is first, so a slow
 * network never holds anyone at the door; and it stays at least long enough to be read rather than flash.
 */

/** Long enough to read the lines; short enough not to be a wait. */
const SHORTEST_MS = 900;
/** The update check stops holding the door after this: it carries on, and says what it found in the usual places. */
const LONGEST_MS = 3000;
const FADE_MS = 260;
/** A check that hasn't started by now isn't going to: this build or this device doesn't check. */
const SKIP_AFTER_MS = 500;

interface LaunchScreenProps {
  loading: boolean;
  notes: number;
  updates: Updates;
  sync: SyncStatus;
  onDone: () => void;
}

type Line = { key: string; state: 'working' | 'done' | 'note'; words: string };

export function LaunchScreen({ loading, notes, updates, sync, onDone }: LaunchScreenProps) {
  const native = isTauri();
  const started = useRef(Date.now());
  const [now, setNow] = useState(() => Date.now());
  const [leaving, setLeaving] = useState(false);
  const asked = useRef(false);

  // The update check, now: the app's own first check waits a few seconds for the list to settle, and this screen is
  // the moment the answer is worth having.
  useEffect(() => {
    if (!native || asked.current) return;
    asked.current = true;
    updates.check();
  }, [native, updates]);

  useEffect(() => {
    const beat = window.setInterval(() => setNow(Date.now()), 150);
    return () => window.clearInterval(beat);
  }, []);

  // Whether a check really ran: a staging build, local-only mode and the dev server never check (core/ota.ts), and
  // then there is no answer to wait for and no line to show.
  const begun = useRef(false);
  if (updates.checking) begun.current = true;
  const [skipped, setSkipped] = useState(!native);
  useEffect(() => {
    if (!native) return undefined;
    const timer = window.setTimeout(() => {
      if (!begun.current) setSkipped(true);
    }, SKIP_AFTER_MS);
    return () => window.clearTimeout(timer);
  }, [native]);

  const elapsed = now - started.current;
  const checked = skipped || (begun.current && !updates.checking);
  // Ready once, and ready from then on: a second check starting mid-fade can't hold the screen up again.
  const latched = useRef(false);
  if (!loading && elapsed >= SHORTEST_MS && (checked || elapsed >= LONGEST_MS)) latched.current = true;
  const ready = latched.current;

  // Once ready it stays ready: fade, then hand over. The callback is read from a ref so a new one each render can't
  // restart the fade and lose the hand-over.
  const done = useRef(onDone);
  done.current = onDone;
  useEffect(() => {
    if (!ready) return undefined;
    setLeaving(true);
    const timer = window.setTimeout(() => done.current(), FADE_MS);
    return () => window.clearTimeout(timer);
  }, [ready]);

  const lines: Line[] = [
    loading
      ? { key: 'notes', state: 'working', words: 'Opening your notes' }
      : { key: 'notes', state: 'done', words: notes === 1 ? '1 note' : `${notes} notes` },
  ];
  if (!skipped) {
    lines.push(
      !checked
        ? { key: 'updates', state: 'working', words: 'Checking for updates' }
        : updates.ready
          ? { key: 'updates', state: 'done', words: 'An update is ready for next time' }
          : updates.apk.kind === 'available'
            ? { key: 'updates', state: 'note', words: `Ghost.md ${updates.apk.info.version} is out` }
            : updates.lastError
              ? { key: 'updates', state: 'note', words: 'Couldn’t check for updates' }
              : { key: 'updates', state: 'done', words: 'Up to date' },
    );
  }
  if (sync.phase !== 'off') {
    lines.push(
      sync.phase === 'syncing'
        ? { key: 'sync', state: 'working', words: 'Syncing your devices' }
        : sync.phase === 'error'
          ? { key: 'sync', state: 'note', words: 'Sync will try again' }
          : { key: 'sync', state: 'done', words: 'In sync' },
    );
  }

  return (
    <div className={styles.launch} data-leaving={leaving || undefined} role="status" aria-live="polite" aria-label="Opening Ghost.md">
      <img className={styles.icon} src={icon} width={96} height={96} alt="" />
      <h1 className={styles.name}>Ghost.md</h1>
      <ul className={styles.lines}>
        {lines.map((line) => (
          <li key={line.key} className={styles.line} data-state={line.state}>
            <span className={styles.mark} aria-hidden="true">
              {line.state === 'working' ? <LoaderCircle size={14} strokeWidth={2.4} /> : line.state === 'done' ? <Check size={14} strokeWidth={2.6} /> : <CircleAlert size={14} strokeWidth={2.4} />}
            </span>
            {line.words}
          </li>
        ))}
      </ul>
    </div>
  );
}
