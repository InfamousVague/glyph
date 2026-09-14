import { useEffect, useRef } from 'react';
import { counter } from '../capture/tape.ts';
import type { Note } from '../core/store.ts';
import { TapeArt } from './TapeArt.tsx';
import type { Tape } from './useTape.ts';
import styles from './NoteTape.module.css';

/**
 * The tape at the top of every note: the cassette, Speak, and for a note that
 * has a recording, Play and where the playhead is.
 *
 * Every note has one, so talking into a note is always one tap away (Matt: "i
 * want to be able to start talking on a note"): Speak opens the recorder aimed
 * at this note, and the words land at its end. A note never spoken into shows
 * an empty cassette with its title on the label, and tapping it is Speak too.
 * A spoken note's cassette plays and pauses when tapped; its reels turn while
 * it plays and the tape winds across, so the picture is the progress bar.
 * Which words are shown under it - the note, its formatted version, or the
 * recording's phrases following the sound (`TranscriptWords`) - is the note
 * screen's business.
 */

const DATE = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' });
const CLIP = 22;

export function NoteTape({ note, title: typed, tape, onSpeak }: { note: Note; title: string; tape: Tape; onSpeak: () => void }) {
  const title = typed || 'Untitled';
  const label = title.length > CLIP ? `${title.slice(0, CLIP - 1).trimEnd()}…` : title;
  const recorded = tape.length > 0;
  const moved = tape.playing || tape.at > 0;
  return (
    <section className={styles.tape} aria-label={recorded ? 'Recording' : 'Talk into this note'}>
      <button
        type="button"
        className={styles.cassette}
        data-blank={recorded ? undefined : ''}
        onClick={recorded ? tape.toggle : onSpeak}
        aria-label={recorded ? (tape.playing ? 'Pause the recording' : 'Play the recording') : 'Talk into this note'}
      >
        <TapeArt
          positionMs={recorded ? (moved ? tape.at : tape.length) : 0}
          playing={tape.playing}
          title={label}
          side={DATE.format(note.createdAt).toUpperCase()}
          counter={recorded ? counter(tape.length) : 'BLANK'}
        />
      </button>

      <div className={styles.side}>
        {recorded ? (
          <span className={styles.time}>
            {counter(tape.at)} <span className={styles.of}>/ {counter(tape.length)}</span>
          </span>
        ) : (
          <span className={styles.blank}>Nothing recorded yet</span>
        )}
        <span className={styles.controls}>
          {recorded ? (
            <button type="button" className={`app-pill ${styles.play}`} onClick={tape.toggle} aria-label={tape.playing ? 'Pause' : 'Play'}>
              <span className={tape.playing ? styles.pauseMark : styles.playMark} aria-hidden="true" />
              {tape.playing ? 'Pause' : 'Play'}
            </button>
          ) : null}
          <button type="button" className={`${recorded ? 'app-word' : 'app-pill'} ${styles.speak}`} onClick={onSpeak} aria-label="Talk into this note">
            <span className={styles.speakDot} aria-hidden="true" />
            Speak
          </button>
        </span>
      </div>
      {tape.problem ? <p className={styles.problem}>{tape.problem}</p> : null}
    </section>
  );
}

/**
 * The words as they were spoken, lit as they are heard. The phrase under the
 * playhead is in ink, the ones already heard in grey, the ones still to come
 * lighter still, and the page keeps the lit one in view while the tape plays.
 * Tapping a phrase takes the tape there.
 */
export function TranscriptWords({ tape }: { tape: Tape }) {
  const list = useRef<HTMLOListElement>(null);
  const { current, playing } = tape;

  useEffect(() => {
    if (!playing || current < 0) return;
    const item = list.current?.children[current] as HTMLElement | undefined;
    item?.scrollIntoView({ block: 'center', behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
  }, [current, playing]);

  if (tape.segments === null) {
    return (
      <div className={styles.transcript} aria-busy="true" aria-label="Loading the transcript">
        <ol className={styles.words}>
          {[88, 62, 74].map((width, i) => (
            <li key={i}>
              <span className={styles.phraseSkeleton} style={{ inlineSize: `${width}%` }} />
            </li>
          ))}
        </ol>
      </div>
    );
  }
  if (!tape.segments.length) {
    return (
      <div className={styles.transcript}>
        <p className={styles.problem}>No words were kept with this recording.</p>
      </div>
    );
  }
  return (
    <div className={styles.transcript}>
      <ol ref={list} className={styles.words}>
        {tape.segments.map((segment, i) => (
          <li key={`${segment.startMs}-${i}`}>
            <button
              type="button"
              className={styles.phrase}
              data-current={i === tape.current ? '' : undefined}
              data-past={i < tape.current || (tape.current === -1 && tape.at >= segment.endMs && tape.at > 0) ? '' : undefined}
              onClick={() => tape.seek(segment.startMs)}
            >
              {segment.text}
            </button>
          </li>
        ))}
      </ol>
    </div>
  );
}
