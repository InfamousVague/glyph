import type { CSSProperties } from 'react';
import { LoaderCircle } from '@glacier/icons';
import { kindWords } from '../ai/kinds.ts';
import { retrySummary, useSummaries } from '../ai/summaries.ts';
import { summaryLine } from '../ai/summaryText.ts';
import { useRefining } from '../capture/refine.ts';
import { TAPE_MS, counter } from '../capture/tape.ts';
import { isMobile } from '../core/platform.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { TapeArt } from '../tapes/TapeArt.tsx';
import { tapeDate } from '../tapes/tapeDate.ts';
import { canOfferSummary, captionOf, type Caption, type CaptionSources } from './tapeCaption.ts';
import { useMeetingLive } from './useMeetingLive.ts';
import styles from './TapeShelf.module.css';

/**
 * The shelf of tapes on the home page (Matt: "display them in a cassette shelf on the home page"; docs/DESIGN.md
 * §127 section 1, redrawn as cards in §132): a row of tape cards that scrolls sideways, one for each note the
 * recorder made, the last recorded first. Which notes are tapes is home/dashboard.ts's (`tapedNotes`); the home page
 * hands this the first eight, and says in its heading how many more there are and where.
 *
 * Each card is on the note card's ground (notes/NoteCard.tsx), so a row of tapes and a row of notes read as one kind
 * of thing: the cassette drawn bare (tapes/TapeArt.tsx) at the card's inner width, its title under it in two lines
 * of real type (at the old shelf's 11rem one line held about twenty-two characters), then the caption with three
 * lines' room for a summary's prose line - the first true thing in the order home/tapeCaption.ts keeps: a meeting
 * being recorded, the better words or a summary on their way, a model that is missing, a summary that did not come,
 * the summary's first line, or the gist - then, when the tape could be written up and nothing is doing it,
 * "Summarize" (Matt asked for summaries and quick actions; the strip's own verb, so the tape has one verb on the
 * shelf and in the note), and last the note card's foot, "12:40 · 26 Sep". A tap on the cassette or the title opens
 * the note; the reels are still, since the tape is the player and lives in the note (§26). The longest tape on the
 * shelf, at least five minutes, is the length every cassette is drawn against, so a three-minute note beside an
 * hour's meeting is a thin ring beside a full reel.
 */

interface TapeShelfProps {
  /** The tapes on the shelf, the last recorded first: at most the home page's eight. */
  notes: readonly Note[];
  /** What each note is about in a line (format/gist.ts), by id, when there is one. */
  gists: Readonly<Record<string, string>>;
  onOpen: (id: string) => void;
  /** "Get a model": Settings › Formatting, where a language model is fetched. */
  onGetModel: () => void;
  /** "Summarize": the queue asked for this tape's write-up (ai/summaries.ts), by the page that knows its kind. */
  onSummarize: (note: Note) => void;
  /** Whether a summariser can run here (on Tauri): off it the queue is a no-op and no Summarize is offered. */
  canSummarize: boolean;
}

export function TapeShelf({ notes, gists, onOpen, onGetModel, onSummarize, canSummarize }: TapeShelfProps) {
  const sources: CaptionSources = {
    recording: useMeetingLive(),
    refining: useRefining().pending,
    summaries: useSummaries(),
    phone: isMobile,
    canSummarize,
  };
  // The longest tape on the shelf, at least five minutes: what every cassette here is drawn against.
  const lengthMs = Math.max(TAPE_MS, ...notes.map((n) => n.recordingMs ?? 0));

  return (
    <ol className={styles.row} aria-label="Tapes">
      {notes.map((note, i) => {
        const title = noteTitle(note.body) || 'Untitled';
        const ms = note.recordingMs ?? 0;
        const date = tapeDate.format(note.createdAt);
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
              <span className={styles.title} data-untitled={noteTitle(note.body) ? undefined : ''}>
                {title}
              </span>
            </button>
            <CaptionLine caption={caption} id={note.id} onGetModel={onGetModel} />
            {canOfferSummary(note, sources) ? (
              <button type="button" className={`app-word ${styles.offer}`} onClick={() => onSummarize(note)}>
                {kindWords('summarize').label}
              </button>
            ) : null}
            {/* The button's label already says the counter and the date. */}
            <span className={styles.foot} aria-hidden="true">
              {counter(ms)} · {date}
            </span>
          </li>
        );
      })}
    </ol>
  );
}

/**
 * The caption as words: the spinner while something is on its way, a word to tap after the words where there is one,
 * and nothing at all otherwise. The words flow as prose, so a long caption wraps and the word goes under it when it
 * does not fit beside.
 */
function CaptionLine({ caption, id, onGetModel }: { caption: Caption | null; id: string; onGetModel: () => void }) {
  if (!caption) return <p className={styles.caption} />;
  switch (caption.kind) {
    case 'recording':
      return (
        <p className={styles.caption} role="status">
          Recording
        </p>
      );
    case 'working':
      return (
        <p className={styles.caption} role="status">
          <LoaderCircle size={14} strokeWidth={2.2} className={styles.working} aria-hidden="true" />
          {caption.keepOpen ? `${caption.word}. Keep Ghost.md open.` : caption.word}
        </p>
      );
    case 'needsModel':
      return (
        <p className={styles.caption} role="status">
          Needs a model{' '}
          <button type="button" className={`app-word ${styles.word}`} onClick={onGetModel}>
            Get a model
          </button>
        </p>
      );
    case 'failed':
      return (
        <p className={styles.caption} role="status">
          The summary didn’t come{' '}
          <button type="button" className={`app-word ${styles.word}`} onClick={() => retrySummary(id)}>
            Try again
          </button>
        </p>
      );
    case 'line':
      return <p className={`${styles.caption} ${styles.gist}`}>{caption.text}</p>;
  }
}
