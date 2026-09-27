import type { CSSProperties } from 'react';
import { LoaderCircle } from '@glacier/icons';
import { kindWords } from '../ai/kinds.ts';
import { retrySummary, useSummaries, type SummariesState } from '../ai/summaries.ts';
import { summaryLine } from '../ai/summaryText.ts';
import { useRefining } from '../capture/refine.ts';
import { TAPE_MS, counter } from '../capture/tape.ts';
import { isMobile } from '../core/platform.ts';
import { scrollSideways } from '../core/scrollSideways.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { TapeArt } from '../tapes/TapeArt.tsx';
import { useMeetingLive } from './useMeetingLive.ts';
import styles from './TapeShelf.module.css';

/**
 * The shelf of tapes on the home page (Matt: "display them in a cassette shelf on the home page"; docs/DESIGN.md
 * §127 section 1): a row of cassettes that scrolls sideways, one for each note the recorder made, the last recorded
 * first. Which notes are tapes is home/dashboard.ts's (`tapedNotes`); the home page hands this the first eight and
 * how many more there are.
 *
 * Each cassette is drawn bare (tapes/TapeArt.tsx) and its words are set under it in real type: at the shelf's 11rem
 * the label's own print would be unreadable, and on the Fold's cover screen the whole row is 412px wide. Line one is
 * the title with the counter and the date beside it; line two is the caption, the first true thing in `captionOf`'s
 * order - a meeting being recorded, the better words or a summary on their way, a model that is missing, a summary
 * that did not come, the summary's first line, or the gist. A tap opens the note; the reels are still, since the
 * tape is the player and lives in the note (§26). The longest tape on the shelf, at least five minutes, is the
 * length every cassette is drawn against, so a three-minute note beside an hour's meeting is a thin ring beside a
 * full reel.
 */

interface TapeShelfProps {
  /** The tapes on the shelf, the last recorded first: at most the home page's eight. */
  notes: readonly Note[];
  /** How many tapes there are past the shelf, said at the row's end. */
  more: number;
  /** What each note is about in a line (format/gist.ts), by id, when there is one. */
  gists: Readonly<Record<string, string>>;
  onOpen: (id: string) => void;
  /** "and N more in All notes": the grid with its Tapes toggle on. */
  onMore: () => void;
  /** "Get a model": Settings › Formatting, where a language model is fetched. */
  onGetModel: () => void;
}

/** A tape this long or longer says "Keep Ghost.md open" on a phone while the page works on it: the page's queues only run while the app is up. */
const LONG_TAPE_MS = 600_000;

/** What the caption reads from, apart from the note: the queues, and whether this is a phone. */
export interface CaptionSources {
  /** The note whose meeting is being recorded, or null. */
  recording: string | null;
  /** Notes whose better words are queued or running (capture/refine.ts). */
  refining: ReadonlySet<string>;
  summaries: SummariesState;
  /** On a phone the page's queues stop when the app is left, so a long job asks for the app to stay open. */
  phone: boolean;
}

export type Caption =
  /** A meeting being recorded: the reels turn. */
  | { kind: 'recording' }
  /** The better words or a summary on their way, with the working spinner; `keepOpen` adds "Keep Ghost.md open". */
  | { kind: 'working'; word: string; keepOpen: boolean }
  /** The job waits for a language model that is not on the phone: "Needs a model" with the word to get one. */
  | { kind: 'needsModel' }
  /** The queue gave up: "The summary didn't come" with Try again. */
  | { kind: 'failed' }
  /** The summary's first line, or the gist. */
  | { kind: 'line'; text: string };

/** The one line under a cassette's title: the first of these that is true, or null for none (§127 section 1, "The caption"). */
export function captionOf(note: Note, sources: CaptionSources, gist: string | undefined): Caption | null {
  const { summaries } = sources;
  // A long tape the page itself is working on: the service's write-up carries on with the app closed, the page's queues do not.
  const keepOpen = sources.phone && (note.recordingMs ?? 0) > LONG_TAPE_MS && !summaries.native.has(note.id);
  if (sources.recording === note.id) return { kind: 'recording' };
  if (sources.refining.has(note.id)) return { kind: 'working', word: 'Listening again', keepOpen };
  if (summaries.native.has(note.id)) return { kind: 'working', word: 'Writing up', keepOpen: false };
  if (summaries.pending.has(note.id)) return { kind: 'working', word: kindWords('summarize').doing, keepOpen };
  if (summaries.needsModel.has(note.id)) return { kind: 'needsModel' };
  if (summaries.failed.has(note.id)) return { kind: 'failed' };
  const line = summaryLine(note.body);
  if (line) return { kind: 'line', text: line };
  if (gist) return { kind: 'line', text: gist };
  return null;
}

const DATE = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' });

export function TapeShelf({ notes, more, gists, onOpen, onMore, onGetModel }: TapeShelfProps) {
  const sources: CaptionSources = {
    recording: useMeetingLive(),
    refining: useRefining().pending,
    summaries: useSummaries(),
    phone: isMobile,
  };
  // The longest tape on the shelf, at least five minutes: what every cassette here is drawn against.
  const lengthMs = Math.max(TAPE_MS, ...notes.map((n) => n.recordingMs ?? 0));

  return (
    <ol className={styles.row} aria-label="Tapes" onWheel={scrollSideways}>
      {notes.map((note, i) => {
        const title = noteTitle(note.body) || 'Untitled';
        const ms = note.recordingMs ?? 0;
        const date = DATE.format(note.createdAt);
        const caption = captionOf(note, sources, gists[note.id]);
        const summarized = summaryLine(note.body) !== null;
        return (
          <li key={note.id} className={styles.tape} style={{ '--i': Math.min(i, 8) } as CSSProperties}>
            <button
              type="button"
              className={styles.cassette}
              onClick={() => onOpen(note.id)}
              aria-label={`${title}, ${counter(ms)}, ${date}${summarized ? ', summarized' : ''}`}
            >
              <TapeArt bare positionMs={ms} lengthMs={lengthMs} playing={caption?.kind === 'recording'} />
              <span className={styles.line}>
                <span className={styles.title} data-untitled={noteTitle(note.body) ? undefined : ''}>
                  {title}
                </span>
                <span className={styles.meta}>
                  {counter(ms)} · {date}
                </span>
              </span>
            </button>
            <CaptionLine caption={caption} id={note.id} onGetModel={onGetModel} />
          </li>
        );
      })}
      {more > 0 ? (
        <li className={styles.moreItem}>
          <button type="button" className={`app-word ${styles.more}`} onClick={onMore}>
            and {more} more in All notes
          </button>
        </li>
      ) : null}
    </ol>
  );
}

/** The caption as words: the spinner while something is on its way, a word to tap where there is one, and nothing at all otherwise. */
function CaptionLine({ caption, id, onGetModel }: { caption: Caption | null; id: string; onGetModel: () => void }) {
  if (!caption) return <p className={styles.caption} />;
  switch (caption.kind) {
    case 'recording':
      return (
        <p className={styles.caption} role="status">
          <span className={styles.captionText}>Recording</span>
        </p>
      );
    case 'working':
      return (
        <p className={styles.caption} role="status">
          <LoaderCircle size={14} strokeWidth={2.2} className={styles.working} aria-hidden="true" />
          <span className={styles.captionText}>{caption.keepOpen ? `${caption.word}. Keep Ghost.md open.` : caption.word}</span>
        </p>
      );
    case 'needsModel':
      return (
        <p className={styles.caption} role="status">
          <span className={styles.captionText}>Needs a model</span>
          <button type="button" className={`app-word ${styles.word}`} onClick={onGetModel}>
            Get a model
          </button>
        </p>
      );
    case 'failed':
      return (
        <p className={styles.caption} role="status">
          <span className={styles.captionText}>The summary didn’t come</span>
          <button type="button" className={`app-word ${styles.word}`} onClick={() => retrySummary(id)}>
            Try again
          </button>
        </p>
      );
    case 'line':
      return (
        <p className={`${styles.caption} ${styles.gist}`}>
          <span className={styles.captionText}>{caption.text}</span>
        </p>
      );
  }
}
