import { Bookmark, EllipsisVertical } from '@glacier/icons';
import styles from './NoteScreen.module.css';

/**
 * The note's two tools: the bookmark and More. The view switch and the mic moved into More (editor/NoteSettings.tsx;
 * Matt: "redesign the top bar so that the mic, reading vs code mode move into the more button in the header";
 * docs/DESIGN.md §147). The note screen draws them in its header, or - wherever the app's top bar is there to take
 * them - puts them into the bar with a portal (core/topBarTools.ts), because they hold the editor's state and lifting
 * them into App.tsx would lift the editor with them. So this is only the drawing: what each one does is the screen's (editor/NoteScreen.tsx), and their rings are the screen's
 * stylesheet's, since the header's own rules (`.header:empty`) are written around them.
 */

interface NoteToolsProps {
  /** The note has a bookmark (editor/useBookmark.ts). */
  marked: boolean;
  onBookmark: () => void;
  onMore: () => void;
}

export function NoteTools({ marked, onBookmark, onMore }: NoteToolsProps) {
  return (
    <div className={styles.tools}>
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
      {/* More for this note: the AI's runs, pin, archive, links, delete (NoteSettings). Three dots rather than a cog (Matt). */}
      <button type="button" className={`${styles.cog} ${styles.more}`} onClick={onMore} aria-label="More for this note">
        <EllipsisVertical size={20} strokeWidth={2.6} aria-hidden="true" />
      </button>
    </div>
  );
}
