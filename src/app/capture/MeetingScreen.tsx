import { Square } from '@glacier/icons';
import { useEffect, useState } from 'react';
import { dropSummary } from '../ai/summaries.ts';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { discardMeetingOnHost, endCapture, isLocked, requestNotifications, stopMeetingOnHost } from '../core/host.ts';
import { preferences, setPreferences } from '../core/preferences.ts';
import { storedFlag } from '../core/stored.ts';
import { deleteNote } from '../core/store.ts';
import { TapeArt } from '../tapes/TapeArt.tsx';
import { canNotifyNow, onNotified, useCanNotify, useMeetingState } from './meetingLive.ts';
import { counter, TAPE_MS } from './tape.ts';
import styles from './MeetingScreen.module.css';

/**
 * A meeting being recorded by the phone's own service (docs/DESIGN.md §127 section 3): the cassette turning, the
 * counter, the line that says the screen can go off, and Discard and Done. Its own small screen rather than the
 * recorder, because a meeting is recorded and not read: no live words, no reader, no cues, nothing of the note, since
 * the side key can open it over the lock screen.
 *
 * It holds nothing the recorder holds. No `setCapturing`, which keeps the screen on and stops the take when the
 * screen goes off - "the screen can go off" is this screen's whole point - and no hold on the queues. The service
 * has the microphone and the wake lock (capture/MeetingService.kt); this screen reads its state once a second
 * (capture/meetingLive.ts) and asks it two things. Done stops the recording, and the service carries on as the
 * write-up. Discard stops it and deletes the WAV, and the page deletes the note itself. Back only leaves: the
 * recording goes on, stoppable here or from the notification, and a locked phone goes back behind its lock screen.
 *
 * Other apps' sound (native generation 25; capture/OtherApps.kt), when the meeting was started with "Include sound
 * from other apps": a line that says it is in the recording, and that calls are not (Android never lets an app hear
 * one), or, when sharing was declined or stopped from the status bar, that the microphone is recording on its own.
 *
 * Under the cassette, until it has been asked once on this device, the way to be told when the meeting is written
 * up (the meeting's own notification prompt, never the update alerts'), and, refused - the phone blocking the prompt,
 * or the prompt answered no, now or on an earlier meeting - the line that says the notification's Stop is not coming.
 */

interface MeetingScreenProps {
  noteId: string;
  /** Opened by the side key: leaving hands a locked phone back to its lock screen, as a capture does. */
  fromAssistant: boolean;
  /** The screen left, however it was left: home. */
  onLeave: () => void;
}

/** Asked once on this device: the line offering it goes once it has been answered, or Allow tapped. */
const alertsAsked = storedFlag('glyph-meeting-alerts-asked');

export function MeetingScreen({ noteId, fromAssistant, onLeave }: MeetingScreenProps) {
  const live = useMeetingState();
  const mine = live?.recording === true && live.noteId === noteId;
  const canNotify = useCanNotify();
  /** Asked on an earlier meeting: an answer that is still no is a refusal, and the offer is not made again. */
  const [askedBefore] = useState(() => alertsAsked.is());
  /** Asked from this screen: the offer goes, and nothing more is said until the phone answers. */
  const [askedNow, setAskedNow] = useState(false);
  const [answered, setAnswered] = useState(false);
  const [blocked, setBlocked] = useState(false);
  useEffect(() => onNotified(() => setAnswered(true)), []);
  // The counter runs between the service's answers, from when the meeting began where the service said.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);
  useEffect(() => void canNotifyNow(), []);
  const elapsedMs = mine ? (live.startedAt !== null ? Math.max(live.elapsedMs, now - live.startedAt) : live.elapsedMs) : 0;

  const leave = () => {
    if (fromAssistant) endCapture(isLocked());
    onLeave();
  };
  useBack(true, leave);

  const done = () => {
    fireNativeHaptic('success');
    stopMeetingOnHost();
    leave();
  };
  const discard = () => {
    fireNativeHaptic('warning');
    discardMeetingOnHost();
    const meetings = { ...preferences().meetings };
    delete meetings[noteId];
    setPreferences({ meetings });
    dropSummary(noteId);
    void deleteNote(noteId).catch(() => undefined);
    leave();
  };
  const allow = () => {
    const answer = requestNotifications();
    if (answer === 'blocked') setBlocked(true);
    else {
      alertsAsked.mark();
      setAskedNow(true);
    }
    canNotifyNow();
  };
  const offer = !canNotify && !askedBefore && !askedNow && !blocked;
  const refused = !canNotify && (blocked || askedBefore || answered);

  return (
    <div className={styles.screen} data-recording={mine ? '' : undefined}>
      <div className={`app-headerPane ${styles.top}`} role="status" aria-live="polite">
        <span className={styles.where}>Meeting</span>
        <span className={styles.counter} aria-label={`Recorded ${counter(elapsedMs)}`}>
          {counter(elapsedMs)}
        </span>
      </div>
      <div className={styles.body}>
        <TapeArt bare playing={mine} positionMs={elapsedMs} lengthMs={Math.max(TAPE_MS, elapsedMs)} className={styles.tape} />
        <p className={styles.line}>Recording. The screen can go off and you can leave. Stop here or from the notification.</p>
        {mine && live.otherApps ? (
          <p className={styles.line} role="status">
            {live.otherAppsHeard ? 'Recording sound from other apps too.' : 'Listening for sound from other apps too.'} Media and games, never calls.
          </p>
        ) : mine && live.otherAppsNote ? (
          <p className={styles.line} role="status">
            {live.otherAppsNote}
          </p>
        ) : null}
        {mine && live.silenced ? (
          <p className={styles.line} role="status">
            Muted by another app.
          </p>
        ) : null}
        {offer ? (
          <p className={styles.line}>
            Let Ghost.md tell you when it is written up.{' '}
            <button type="button" className={`app-word ${styles.word}`} onClick={allow}>
              Allow
            </button>
          </p>
        ) : null}
        {refused ? <p className={styles.line}>Notifications are off for Ghost.md, so stop it here.</p> : null}
      </div>
      <footer className={styles.footer}>
        <button type="button" className="app-word" onClick={discard}>
          Discard
        </button>
        <button type="button" className={`app-pill ${styles.done}`} onClick={done} aria-label="Stop and write up">
          <Square size={16} aria-hidden="true" />
          Done
        </button>
      </footer>
    </div>
  );
}
