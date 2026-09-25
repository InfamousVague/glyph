import { BookOpen, Bookmark, Code, EllipsisVertical, Mic } from '@glacier/icons';
import styles from './NoteScreen.module.css';

/**
 * The note's four tools: the view switch, the bookmark, the mic and More. The note screen draws them in its header, or
 * - wherever the app's top bar is there to take them - puts them into the bar with a portal (core/topBarTools.ts),
 * because they hold the editor's state and lifting them into App.tsx would lift the editor with them. So this is only
 * the drawing: what each one does is the screen's (editor/NoteScreen.tsx), and their rings are the screen's
 * stylesheet's, since the header's own rules (`.header:empty`) are written around them.
 */

/** What the note is drawn as when it is not its source: a canvas, a book's index, or words. */
export type NoteKind = 'canvas' | 'book' | 'words';

interface NoteToolsProps {
  kind: NoteKind;
  /**
   * The page rather than its source: a canvas or a book's index drawn, not its JSON or Markdown; for words, the
   * formatted note rather than the marks. The switch shows what is showing and says what a press shows instead.
   */
  page: boolean;
  /** The switch works: the note's own view is up, not the transcript while the tape plays. */
  switchable: boolean;
  onSwitch: () => void;
  /** The note has a bookmark (editor/useBookmark.ts). */
  marked: boolean;
  onBookmark: () => void;
  /** Talking into the note is here: a note with a recording has the tape's Add instead. */
  onSpeak: (() => void) | null;
  onMore: () => void;
}

/** The switch's words: what it says it is showing and what a press shows, and its short title. */
function viewSwitchWords(kind: NoteKind, page: boolean): { label: string; title: string } {
  if (kind === 'canvas') return page ? { label: 'Showing the canvas. Show its JSON.', title: 'Canvas' } : { label: 'Showing the canvas as JSON. Show the canvas.', title: 'JSON' };
  if (kind === 'book') return page ? { label: 'Showing the index. Show its Markdown.', title: 'Index' } : { label: 'Showing the index as Markdown. Show the index.', title: 'Markdown' };
  return page ? { label: 'Showing the formatted note. Show the marks.', title: 'Formatted' } : { label: 'Showing the marks. Show the formatted note.', title: 'Markdown' };
}

export function NoteTools({ kind, page, switchable, onSwitch, marked, onBookmark, onSpeak, onMore }: NoteToolsProps) {
  const { label, title } = viewSwitchWords(kind, page);
  return (
    <div className={styles.tools}>
      {/*
        Markdown, the marks with the formatting (the default), or just the formatted text (editor/viewMode.ts).
        One ring like the others rather than a pair in a capsule (Matt: "change the pencil and book icon to the
        normal round icon we use for the other items in the toolbar just make it toggle between a code icon and a
        book icon"): the glyph is the view you are in - the marks, or the page - and the label says what a press
        does, which is the part a pair of buttons used to say by being two.
      */}
      <button type="button" className={styles.cog} disabled={!switchable} onClick={onSwitch} aria-label={label} title={title}>
        {page ? <BookOpen size={20} strokeWidth={2.1} aria-hidden="true" /> : <Code size={20} strokeWidth={2.1} aria-hidden="true" />}
      </button>
      <button
        type="button"
        className={`${styles.cog} ${styles.bookmark} app-gold`}
        data-on={marked || undefined}
        onClick={onBookmark}
        aria-pressed={marked}
        aria-label={marked ? 'Move the bookmark to this line, or take it off here' : 'Bookmark this line'}
      >
        {/*
          The same outline and 33% wash as every other filled icon in the app, set or not (Matt: "the bookmark icon on the
          note should have the outline with semitransparent fill"). app.css gives it that; nothing here overrides it.

          It was solid once set, which read as a different kind of icon from everything beside it. Whether a bookmark is
          set is said by `aria-pressed` and the button's label, and on the page by the ribbon on the marked line - and,
          since the mark on the page went gold (Matt: "Make the bookmark icon on the note yellow / gold instead of white so
          it stands out"), by the button going gold with it (NoteScreen.module.css `.bookmark[data-on]`).
        */}
        <Bookmark size={20} strokeWidth={2.1} aria-hidden="true" />
      </button>
      {/* A note with no recording has no tape; talking into it is this mic. Once it has audio, the tape's Add is. */}
      {onSpeak ? (
        <button type="button" className={styles.cog} onClick={onSpeak} aria-label="Talk into this note">
          <Mic size={20} strokeWidth={2.1} aria-hidden="true" />
        </button>
      ) : null}
      {/* More for this note: the AI's runs, pin, archive, links, delete (NoteSettings). Three dots rather than a cog (Matt). */}
      <button type="button" className={`${styles.cog} ${styles.more}`} onClick={onMore} aria-label="More for this note">
        <EllipsisVertical size={20} strokeWidth={2.6} aria-hidden="true" />
      </button>
    </div>
  );
}
