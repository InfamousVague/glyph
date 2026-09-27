import { LoaderCircle, Mic, Pause, Play, Sparkles, Trash2 } from '@glacier/icons';
import { useEffect, useRef, useState } from 'react';
import { kindWords } from '../ai/kinds.ts';
import { ended, useRun } from '../ai/runs.ts';
import { useSummaries } from '../ai/summaries.ts';
import { TAPE_MS, counter } from '../capture/tape.ts';
import { prefersStill } from '../core/motion.ts';
import type { Note } from '../core/store.ts';
import { TapeArt } from './TapeArt.tsx';
import { tapeDate } from './tapeDate.ts';
import type { Tape } from './useTape.ts';
import styles from './NoteTape.module.css';

/**
 * The tape at the top of a note that has a recording: the cassette, Play and
 * where the playhead is, and the two things to do with the audio, Add (talk
 * more into the note, the new take appended to the tape) and Remove.
 *
 * Remove asks a second time on a note with voice memos in it (core/clips.ts), since the marks stay in the words
 * while the audio they play goes: the line says so, and Undo brings the recording, its tape's id and the memos back
 * together.
 *
 * Summarize, the third word, is the recording's (docs/DESIGN.md §127 section 2): the tape's words written up under
 * the title by the model on the phone, queued (ai/summaries.ts) and landed in this open note as a run with Keep and
 * Revert. A summary is remade only on purpose, so a section the person edited is asked about first, "You edited
 * the summary. Replace it?" with Replace and Keep mine, and nothing is written until one is tapped. An Add to the
 * tape does not remake it: the strip says "Summary is from before the last take." and the word remakes it. The
 * word is only there where there is a model to run: a browser has none and shows what synced.
 *
 * Only a spoken note has one (Matt: "Don't show the tape on notes that don't
 * have any audio recorded; the notes with audio recordings added should show
 * the tape so we can add or remove audio there"). A note with no recording
 * has no cassette at all; its header has a mic to talk into it instead
 * (editor/NoteScreen.tsx), and once it has been spoken into, the tape
 * appears. The cassette plays and pauses when tapped; its reels turn while it
 * plays and the tape winds across, so the picture is the progress bar. Which
 * words are shown under it - the note, its formatted version, or the
 * recording's phrases following the sound (`TranscriptWords`) - is the note
 * screen's business.
 */

const CLIP = 22;

interface NoteTapeProps {
  note: Note;
  title: string;
  tape: Tape;
  /** Talk more into the note: the recorder, aimed at it, appending to the tape. */
  onSpeak: () => void;
  /** Take the recording off the note (the screen offers Undo). */
  onRemove: () => void;
  /** The note holds voice memos, which play from this recording: Remove asks first, and says so. */
  hasMemos: boolean;
  /** The recording's summary: how to ask for it, whether the section was edited, and whether the tape has grown since. Null where there is no model. */
  summary?: TapeSummary | null;
}

export interface TapeSummary {
  /** Asks the queue for the summary; with `replace`, over a section the person edited. */
  ask: (replace: boolean) => void;
  /** Whether the section in the note is no longer the one the app wrote. */
  edited: () => boolean;
  /** Whether a take was added since the summary was written. */
  behind: boolean;
}

export function NoteTape({ note, title: typed, tape, onSpeak, onRemove, hasMemos, summary = null }: NoteTapeProps) {
  // Remove, on a note with voice memos in it: the word asks once, since the memos go quiet with the recording.
  const [asking, setAsking] = useState(false);
  useEffect(() => {
    if (!asking) return undefined;
    const timer = window.setTimeout(() => setAsking(false), 5000);
    return () => window.clearTimeout(timer);
  }, [asking]);
  // Summarize, over a section the person edited: the word asks once.
  const [replacing, setReplacing] = useState(false);
  useEffect(() => {
    if (!replacing) return undefined;
    const timer = window.setTimeout(() => setReplacing(false), 8000);
    return () => window.clearTimeout(timer);
  }, [replacing]);
  const summaries = useSummaries();
  const run = useRun(note.id);
  if (tape.length <= 0) return null;
  const summarizing = summaries.pending.has(note.id) || (run !== null && run.kind === 'summarize' && !ended(run));
  const summaryLine = summaries.needsModel.has(note.id)
    ? 'Needs a model.'
    : summaries.failed.has(note.id)
      ? 'The summary didn’t come.'
      : summarizing
        ? null
        : summary?.behind
          ? 'Summary is from before the last take.'
          : null;
  const title = typed || 'Untitled';
  const label = title.length > CLIP ? `${title.slice(0, CLIP - 1).trimEnd()}…` : title;
  const moved = tape.playing || tape.at > 0;
  return (
    <section className={styles.tape} aria-label="Recording">
      <button type="button" className={styles.cassette} onClick={tape.toggle} aria-label={tape.playing ? 'Pause the recording' : 'Play the recording'}>
        <TapeArt
          positionMs={moved ? tape.at : tape.length}
          // A tape longer than five minutes winds across its whole length in playback, rather than sitting full from the fifth minute on.
          lengthMs={Math.max(TAPE_MS, tape.length)}
          playing={tape.playing}
          title={label}
          side={tapeDate.format(note.createdAt).toUpperCase()}
          counter={counter(tape.length)}
        />
      </button>

      <div className={styles.side}>
        <span className={styles.time}>
          {counter(tape.at)} <span className={styles.of}>/ {counter(tape.length)}</span>
        </span>
        <button type="button" className={`app-pill ${styles.play}`} onClick={tape.toggle} aria-label={tape.playing ? 'Pause' : 'Play'}>
          {tape.playing ? <Pause size={16} aria-hidden="true" /> : <Play size={16} aria-hidden="true" />}
          {tape.playing ? 'Pause' : 'Play'}
        </button>
        <span className={styles.edits}>
          <button type="button" className={`app-word ${styles.edit}`} onClick={onSpeak} aria-label="Record more into this note">
            <Mic size={15} strokeWidth={2.2} aria-hidden="true" />
            Add
          </button>
          {asking ? (
            <button type="button" className={`app-word ${styles.edit}`} onClick={() => setAsking(false)} aria-label="Keep this note's recording">
              Keep
            </button>
          ) : null}
          <button
            type="button"
            className={`app-word ${styles.edit}`}
            data-asking={asking || undefined}
            onClick={() => {
              if (hasMemos && !asking) setAsking(true);
              else {
                setAsking(false);
                onRemove();
              }
            }}
            aria-label={asking ? 'Remove the recording and stop its voice memos' : "Remove this note's recording"}
          >
            <Trash2 size={15} strokeWidth={2.2} aria-hidden="true" />
            Remove
          </button>
          {summary && !replacing ? (
            <button
              type="button"
              className={`app-word ${styles.edit}`}
              onClick={() => {
                if (summary.edited()) setReplacing(true);
                else summary.ask(false);
              }}
              disabled={summarizing}
              aria-label="Summarize the recording"
              title="The recording, summarized under the title."
            >
              {summarizing ? <LoaderCircle size={15} strokeWidth={2.2} className={styles.working} aria-hidden="true" /> : <Sparkles size={15} strokeWidth={2.2} aria-hidden="true" />}
              {summarizing ? kindWords('summarize').doing : kindWords('summarize').label}
            </button>
          ) : null}
          {summary && replacing ? (
            <>
              <button
                type="button"
                className={`app-word ${styles.edit}`}
                data-asking=""
                onClick={() => {
                  setReplacing(false);
                  summary.ask(true);
                }}
                aria-label="Replace the summary you edited"
              >
                Replace
              </button>
              <button type="button" className={`app-word ${styles.edit}`} onClick={() => setReplacing(false)} aria-label="Keep the summary as you edited it">
                Keep mine
              </button>
            </>
          ) : null}
        </span>
      </div>
      {asking ? <p className={styles.warning}>The voice memos in this note play from this recording. They’ll stop until you undo.</p> : null}
      {replacing ? <p className={styles.warning}>You edited the summary. Replace it?</p> : null}
      {summaryLine && !replacing ? <p className={styles.warning}>{summaryLine}</p> : null}
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
    item?.scrollIntoView({ block: 'center', behavior: prefersStill() ? 'auto' : 'smooth' });
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
