import { useEffect, useMemo, useState } from 'react';
import { ArrowRight } from '../../art/Icons.tsx';
import { SideKey as SideKeyArt } from '../../art/Shapes.tsx';
import { isAndroid } from '../../core/platform.ts';
import { assistantPath, canOpenAssistantSettings, isAssistantNow, openAssistantSettings, sideKeyPath, thisPhone } from '../assistant.ts';
import styles from '../Guide.module.css';

/**
 * The side-key page: the one that matters most, and the one Ghost.md can do the least about (guide/assistant.ts says
 * why). It opens the right settings screen, says exactly which rows to tap on THIS phone, checks the result when the
 * person comes back, and is honest that this replaces Gemini or Bixby. From this page on, holding the side key
 * records as it always does; before it, a press is someone who has not finished reading (guide/tooSoon.ts).
 *
 * Off Android there is no side key to give away, so the page says how to start a voice note instead.
 */
export function SideKey() {
  const [held, setHeld] = useState<boolean | null>(() => isAssistantNow());
  const kind = useMemo(thisPhone, []);
  const canOpen = canOpenAssistantSettings();

  // The person leaves for Settings and comes back; look again when they do.
  useEffect(() => {
    const recheck = () => {
      if (document.visibilityState === 'visible') setHeld(isAssistantNow());
    };
    document.addEventListener('visibilitychange', recheck);
    return () => document.removeEventListener('visibilitychange', recheck);
  }, []);

  if (!isAndroid) {
    return (
      <>
        <SideKeyArt className={styles.art} />
        {/* Not "an Android thing": the App Store doesn't allow naming another platform in the app (guideline 2.3.10). */}
        <h1 className={styles.title}>Start a voice note with Speak.</h1>
        <p className={styles.lead}>Tap Speak at the bottom of your notes, say what you want to keep, and it becomes a note.</p>
      </>
    );
  }

  return (
    <>
      <SideKeyArt className={styles.art} />
      <h1 className={styles.title}>Make the side key record.</h1>
      {held ? (
        <p className={styles.done} role="status">
          <span aria-hidden="true">✓</span> Ghost.md is your assistant.
        </p>
      ) : null}

      <ol className={styles.steps}>
        <li>
          <h2 className={styles.stepTitle}>Make Ghost.md your digital assistant.</h2>
          <Path parts={assistantPath(kind)} />
          {canOpen && !held ? (
            <button type="button" className={`app-word ${styles.action}`} onClick={openAssistantSettings}>
              Open assistant settings <ArrowRight />
            </button>
          ) : null}
        </li>
        <li>
          <h2 className={styles.stepTitle}>Point the side key at it.</h2>
          <Path parts={sideKeyPath(kind)} />
          {kind === 'samsung' ? (
            <p className={styles.note}>
              Choose Digital assistant, not Bixby. On a Fold this is the key under your thumb when the phone is open.
            </p>
          ) : null}
        </li>
        <li>
          <h2 className={styles.stepTitle}>Hold the key and talk.</h2>
          <p className={styles.note}>
            Ghost.md opens already listening, even on the lock screen. Let go and talk. If the phone is locked, the note is
            there once you unlock it.
          </p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Hold the side key again to stop.</h2>
          <p className={styles.note}>That saves the note. Tapping Done does the same.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Say where things go, and Ghost.md sorts it after.</h2>
          <p className={styles.note}>
            “Add oat milk to groceries” goes to your Groceries note, and the rest becomes a new note. You see where
            everything is going before anything is filed. Turn off Memo mode in Settings to get a plain new note every
            time.
          </p>
        </li>
      </ol>

      <p className={styles.fine}>
        This replaces {kind === 'samsung' ? 'Bixby or Gemini' : 'Gemini'} as your assistant. Switch back in the same place any
        time.
      </p>
    </>
  );
}

/** A path through Settings, one row after another, the row to pick set apart. */
function Path({ parts }: { parts: string[] }) {
  return (
    <p className={styles.path}>
      {parts.map((part, i) => (
        <span key={part}>
          {i > 0 ? <span className={styles.sep} aria-hidden="true"> › </span> : null}
          <span className={i === parts.length - 1 ? styles.target : undefined}>{part}</span>
        </span>
      ))}
    </p>
  );
}
