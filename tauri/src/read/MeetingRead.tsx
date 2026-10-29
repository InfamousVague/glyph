import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { LoaderCircle, LocateFixed, Pause, Play } from '@glacier/icons';
import { SegmentedControl } from '@glacier/react';
import { TAPE_MS } from '../app/capture/tape.ts';
import { TapeArt } from '../app/tapes/TapeArt.tsx';
import { tapeDate } from '../app/tapes/tapeDate.ts';
import { clock, heardAt, seekFor, speakerOf, timelineOf, type At, type Meeting } from './meeting.ts';
import { useSharedTape, type SharedTape } from './useSharedTape.ts';
import styles from './MeetingRead.module.css';

/**
 * A shared meeting, read and heard (Matt, 2026-10-29: "Update the web version of the meeting transcripts to include
 * the casette tape and the per user transcript so we can listen along make a segmented toggle to switch between
 * summary and transcript"; docs/SHARING.md, "A meeting's recording").
 *
 * - **Summary | Transcript**, the kit's segmented toggle, under the title: the note's words without its transcript,
 *   or the transcript a turn at a time. Summary first.
 * - **The cassette** is the player where the share carries the recording: the app's tape (tapes/TapeArt.tsx) in the
 *   colour the app gives the meeting, its reels turning while it plays and the tape winding across, so the picture is
 *   the progress; Play, the time, a scrubber, and 1×, 1.5× and 2×. Space plays and pauses. Scrolled away from, it
 *   leaves a bar at the foot of the page with Play and the time, so the transcript can be read along to. A share
 *   without a recording has no cassette: the transcript is read as it is.
 * - **The transcript**: each turn its speaker's name and when it began, the phrase being heard lit (lib/tapes/
 *   transcript_words.dart's light: the last begun, through the quiet after it) and kept in the middle of the page while
 *   it plays. Scrolling the page oneself stops that, and "Back to now" takes it back. Tapping a phrase plays from it. A
 *   transcript with no times is read, not lit, and its phrases are not buttons. The app gives a speaker no colour of
 *   its own, so neither does this: names are in the first ink, in bold, as the app sets them.
 */

type View = 'summary' | 'transcript';

const CLIP = 22;
const SPEEDS = [1, 1.5, 2];

interface MeetingReadProps {
  title: string;
  meeting: Meeting;
  /** The share's id and key: where the recording is fetched from, and what opens it. */
  link: { id: string; key: string } | null;
  dark: boolean;
  /** The note's words without the transcript, drawn by the reader page (Read, or Markdown in its editor). */
  summary: ReactNode;
  /** Read | Markdown (ReadToggle.tsx), beside Summary | Transcript and shown while the summary is. */
  readToggle?: ReactNode;
  /** For the tests: what fetches the recording. */
  fetcher?: typeof fetch;
}

export function MeetingRead({ title, meeting, link, dark, summary, readToggle, fetcher }: MeetingReadProps) {
  const [view, setView] = useState<View>('summary');
  const audio = link && meeting.audio ? meeting.audio : null;
  const lengthMs = meeting.audio?.ms || meeting.ms;
  return (
    <article className={styles.meeting}>
      <h1 className={styles.title}>{title}</h1>
      <p className={styles.when}>
        Meeting · {tapeDate.format(meeting.at)}
        {lengthMs > 0 ? ` · ${clock(lengthMs)}` : ''}
        {meeting.speakers.length ? ` · ${meeting.speakers.join(', ')}` : ''}
      </p>
      <div className={styles.toggles}>
      <div className={styles.toggle}>
        <SegmentedControl
          aria-label="Summary or transcript"
          fullWidth
          size="sm"
          options={[
            { value: 'summary', label: 'Summary' },
            { value: 'transcript', label: 'Transcript' },
          ]}
          value={view}
          onValueChange={(value) => setView(value as View)}
        />
      </div>
      {readToggle && view === 'summary' ? <div className={styles.readToggle}>{readToggle}</div> : null}
      </div>
      {audio && link ? (
        <Heard id={link.id} secret={link.key} title={title} meeting={meeting} lengthMs={lengthMs} dark={dark} view={view} summary={summary} fetcher={fetcher} />
      ) : view === 'summary' ? (
        <div className={styles.summary}>{summary}</div>
      ) : (
        <Transcript meeting={meeting} tape={null} />
      )}
    </article>
  );
}

/** The meeting with its recording: the deck, and whichever view is chosen, sharing one tape. */
function Heard({ id, secret, title, meeting, lengthMs, dark, view, summary, fetcher }: { id: string; secret: string; title: string; meeting: Meeting; lengthMs: number; dark: boolean; view: View; summary: ReactNode; fetcher?: typeof fetch }) {
  const tape = useSharedTape(id, secret, meeting.audio!, lengthMs, fetcher);
  const deck = useRef<HTMLElement>(null);
  const [deckSeen, setDeckSeen] = useState(true);

  // Space plays and pauses, anywhere but where it types or presses something of its own.
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.key !== ' ' || event.metaKey || event.ctrlKey || event.altKey) return;
      const target = event.target as HTMLElement | null;
      if (target?.closest('input, textarea, select, button, a, [contenteditable="true"], [role="slider"], [role="radio"]')) return;
      event.preventDefault();
      tape.toggle();
    };
    document.addEventListener('keydown', key);
    return () => document.removeEventListener('keydown', key);
  }, [tape]);

  // The bar at the foot is there while the deck is out of sight.
  useEffect(() => {
    const el = deck.current;
    if (!el || typeof IntersectionObserver === 'undefined') return undefined;
    const seen = new IntersectionObserver(([entry]) => setDeckSeen(entry?.isIntersecting ?? true));
    seen.observe(el);
    return () => seen.disconnect();
  }, []);

  const label = title.length > CLIP ? `${title.slice(0, CLIP - 1)}…` : title;
  return (
    <>
      <section ref={deck} className={styles.deck} aria-label="The recording">
        <button type="button" className={styles.cassette} onClick={tape.toggle} aria-label={tape.playing ? 'Pause the recording' : 'Play the recording'}>
          <TapeArt
            positionMs={tape.started ? tape.at : lengthMs}
            lengthMs={Math.max(TAPE_MS, lengthMs)}
            playing={tape.playing}
            title={label}
            side={tapeDate.format(meeting.at).toUpperCase()}
            counter={clock(lengthMs)}
            hue={meeting.hue}
            dark={dark}
          />
        </button>
        <div className={styles.controls}>
          <p className={styles.time} aria-live="off">
            {clock(tape.at)} <span className={styles.of}>/ {clock(lengthMs)}</span>
          </p>
          <div className={styles.transport}>
            <PlayButton tape={tape} />
            <SegmentedControl
              aria-label="Speed"
              size="sm"
              className={styles.speed}
              options={SPEEDS.map((speed) => ({ value: String(speed), label: `${speed}×` }))}
              value={String(tape.rate)}
              onValueChange={(value) => tape.setRate(Number(value))}
            />
          </div>
          <Scrubber tape={tape} lengthMs={lengthMs} />
          <p className={styles.status} role="status">
            {statusOf(tape)}
          </p>
        </div>
      </section>
      {view === 'summary' ? <div className={styles.summary}>{summary}</div> : <Transcript meeting={meeting} tape={tape} />}
      {!deckSeen ? (
        <div className={styles.bar} data-testid="tape-bar">
          <PlayButton tape={tape} compact />
          <span className={styles.time}>
            {clock(tape.at)} <span className={styles.of}>/ {clock(lengthMs)}</span>
          </span>
          <Scrubber tape={tape} lengthMs={lengthMs} />
        </div>
      ) : null}
    </>
  );
}

function statusOf(tape: SharedTape): string {
  if (tape.failed) return tape.failed;
  if (tape.loading && tape.progress < 1) return `${tape.waiting ? 'Loading the recording' : 'The recording is coming'}… ${Math.floor(tape.progress * 100)}%`;
  if (tape.waiting) return 'Loading…';
  return 'Space plays and pauses. Tap a line of the transcript to hear it.';
}

function PlayButton({ tape, compact = false }: { tape: SharedTape; compact?: boolean }) {
  const busy = tape.waiting && !tape.playing;
  const Mark = busy ? LoaderCircle : tape.playing ? Pause : Play;
  return (
    <button type="button" className={compact ? styles.playSmall : styles.play} onClick={tape.toggle} aria-label={tape.playing || busy ? 'Pause' : 'Play'} aria-pressed={tape.playing}>
      <Mark size={16} aria-hidden="true" className={busy ? styles.spin : undefined} />
      {compact ? null : tape.playing || busy ? 'Pause' : 'Play'}
    </button>
  );
}

/** Where the tape is, to drag: what has come of the recording drawn behind it. */
function Scrubber({ tape, lengthMs }: { tape: SharedTape; lengthMs: number }) {
  const played = lengthMs > 0 ? Math.min(100, (tape.at / lengthMs) * 100) : 0;
  const loaded = lengthMs > 0 ? Math.min(100, (tape.loadedMs / lengthMs) * 100) : 0;
  return (
    <input
      type="range"
      className={styles.scrub}
      min={0}
      max={Math.max(1, Math.round(lengthMs))}
      step={1000}
      value={Math.round(tape.at)}
      aria-label="Where in the recording"
      aria-valuetext={`${clock(tape.at)} of ${clock(lengthMs)}`}
      style={{ ['--played' as string]: `${played}%`, ['--loaded' as string]: `${Math.max(played, loaded)}%` }}
      onChange={(event) => tape.seek(Number(event.currentTarget.value))}
    />
  );
}

/** The turns, the one being heard lit and followed while the tape plays (see the header). */
function Transcript({ meeting, tape }: { meeting: Meeting; tape: SharedTape | null }) {
  const timeline = useMemo(() => timelineOf(meeting), [meeting]);
  const heard: At | null = tape && tape.started ? heardAt(timeline, tape.at) : null;
  const [following, setFollowing] = useState(true);
  const list = useRef<HTMLOListElement>(null);
  const playing = tape?.playing ?? false;

  // The reader's own scroll while it plays stops the following; the page's own does not, as it sends no wheel or touch.
  useEffect(() => {
    if (!playing) return undefined;
    const away = () => setFollowing(false);
    const keys = (event: KeyboardEvent) => {
      if (['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End'].includes(event.key)) away();
    };
    window.addEventListener('wheel', away, { passive: true });
    window.addEventListener('touchmove', away, { passive: true });
    window.addEventListener('keydown', keys);
    return () => {
      window.removeEventListener('wheel', away);
      window.removeEventListener('touchmove', away);
      window.removeEventListener('keydown', keys);
    };
  }, [playing]);

  const key = heard ? `${heard.turn}:${heard.phrase}` : '';
  useEffect(() => {
    if (!following || !playing || !key) return;
    const lit = list.current?.querySelector<HTMLElement>('[data-current]');
    lit?.scrollIntoView?.({ block: 'center', behavior: 'smooth' });
  }, [key, following, playing]);

  if (!meeting.turns.length) return <p className={styles.empty}>This meeting has no transcript yet.</p>;
  const back = () => {
    setFollowing(true);
    list.current?.querySelector<HTMLElement>('[data-current]')?.scrollIntoView?.({ block: 'center', behavior: 'smooth' });
  };
  return (
    <>
      <ol ref={list} className={styles.turns} aria-label="Transcript">
        {meeting.turns.map((turn, t) => {
          const name = speakerOf(meeting, turn);
          const start = turn.p[0]![0];
          return (
            <li key={t} className={styles.turn} data-current={heard?.turn === t ? '' : undefined}>
              <p className={styles.who}>
                {name ? <strong className={styles.name}>{name}</strong> : null}
                {start >= 0 ? <span className={styles.at}>{clock(start)}</span> : null}
              </p>
              <p className={styles.words}>
                {turn.p.map((phrase, p) => {
                  const to = seekFor(phrase);
                  const current = heard?.turn === t && heard.phrase === p;
                  const past = heard ? t < heard.turn || (t === heard.turn && p < heard.phrase) : false;
                  const text = `${phrase[2]} `;
                  return to === null || !tape ? (
                    <span key={p} className={styles.phrase} data-plain="">
                      {text}
                    </span>
                  ) : (
                    <button
                      key={p}
                      type="button"
                      className={styles.phrase}
                      data-current={current ? '' : undefined}
                      data-past={past ? '' : undefined}
                      aria-current={current ? 'true' : undefined}
                      title={`Play from ${clock(to)}`}
                      onClick={() => {
                        setFollowing(true);
                        tape.seek(to, true);
                      }}
                    >
                      {text}
                    </button>
                  );
                })}
              </p>
            </li>
          );
        })}
      </ol>
      {playing && !following ? (
        <button type="button" className={styles.backToNow} onClick={back}>
          <LocateFixed size={14} aria-hidden="true" />
          Back to now
        </button>
      ) : null}
    </>
  );
}
