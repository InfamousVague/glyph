import type { CSSProperties } from 'react';
import { LoaderCircle } from '@glacier/icons';
import { retrySummary, useSummaries } from '../ai/summaries.ts';
import { summaryLine } from '../ai/summaryText.ts';
import { useRefining } from '../capture/refine.ts';
import { TAPE_MS, counter } from '../capture/tape.ts';
import { isMobile } from '../core/platform.ts';
import { scrollSideways } from '../core/scrollSideways.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { TapeArt } from '../tapes/TapeArt.tsx';
import { captionOf, type Caption, type CaptionSources } from './tapeCaption.ts';
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
 * the title with the counter and the date beside it; line two is the caption, the first true thing in the order
 * home/tapeCaption.ts keeps - a meeting being recorded, the better words or a summary on their way, a model that is
 * missing, a summary that did not come, the summary's first line, or the gist. A tap opens the note; the reels are
 * still, since the tape is the player and lives in the note (§26). The longest tape on the shelf, at least five
 * minutes, is the length every cassette is drawn against, so a three-minute note beside an hour's meeting is a thin
 * ring beside a full reel.
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
