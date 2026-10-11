import { useRef, type ComponentType } from 'react';
import { BookOpen, Code, EllipsisVertical } from '@glacier/icons';
import { useToolRoom } from './toolRoom.ts';
import styles from './NoteScreen.module.css';

/**
 * The note's tools: the view switch and More; the bookmark and the mic are in More (editor/NoteSettings.tsx), but the
 * view switch came back to the header (Matt: "move the toggle between markdown and reading view back into the header"),
 * where it was before docs/DESIGN.md §147 moved it in. The note screen draws them in its header, or - wherever the
 * app's top bar is there to take them - puts them into the bar with a portal (core/topBarTools.ts), because they hold
 * the editor's state and lifting them into App.tsx would lift the editor with them. So this is only the drawing: what
 * each one does is the screen's (editor/NoteScreen.tsx), and their rings are the screen's stylesheet's, since the
 * header's own rules (`.header:empty`) are written around them.
 */

/**
 * One of the note's actions that comes out of More into the bar when there is room for it (Matt: "add the version
 * history as an item in the header when the space is available, I'd like the top toolbar to automatically adapt to
 * show more or less icons ... the following should be able to expand out in order of priority": Share, History,
 * Bookmark, Pin/Unpin, Archive, Speak). Each stays in More as well, so nothing moves out from under a hand that knows
 * where it was.
 */
export interface ToolAction {
  id: string;
  label: string;
  icon: ComponentType<{ size?: number; strokeWidth?: number; 'aria-hidden'?: boolean | 'true' }>;
  onPress: () => void;
  /** A toggle that is on now: the bookmark set, the note pinned. */
  on?: boolean;
}

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
  onMore: () => void;
  /** False when More is drawn on its own, at the bar's end after the bell (core/topBarTools.ts `useTopBarTail`). */
  more?: boolean;
  /** The actions to bring out of More while there is room, first first (`ToolAction`). */
  actions?: readonly ToolAction[];
}

/** More for this note: the view's look, the bookmark, the mic, the AI's runs, pin, archive, links, delete (NoteSettings). */
export function NoteMore({ onMore }: { onMore: () => void }) {
  return (
    <button type="button" className={`${styles.cog} ${styles.more}`} onClick={onMore} aria-label="More for this note">
      <EllipsisVertical size={20} strokeWidth={2.6} aria-hidden="true" />
    </button>
  );
}

/** The switch's words: what it says it is showing and what a press shows, and its short title. */
function viewSwitchWords(kind: NoteKind, page: boolean): { label: string; title: string } {
  if (kind === 'canvas') return page ? { label: 'Showing the canvas. Show its JSON.', title: 'Canvas' } : { label: 'Showing the canvas as JSON. Show the canvas.', title: 'JSON' };
  if (kind === 'book') return page ? { label: 'Showing the index. Show its Markdown.', title: 'Index' } : { label: 'Showing the index as Markdown. Show the index.', title: 'Markdown' };
  return page ? { label: 'Showing the formatted note. Show the marks.', title: 'Formatted' } : { label: 'Showing the marks. Show the formatted note.', title: 'Markdown' };
}

export function NoteTools({ kind, page, switchable, onSwitch, onMore, more = true, actions = [] }: NoteToolsProps) {
  const { label, title } = viewSwitchWords(kind, page);
  const here = useRef<HTMLDivElement>(null);
  // As many as the row has room for, in their order; the rest are in More (editor/toolRoom.ts).
  const out = actions.slice(0, useToolRoom(here, actions.length));
  return (
    <div ref={here} className={styles.tools}>
      {out.map((action) => {
        const Icon = action.icon;
        return (
          <button
            key={action.id}
            type="button"
            className={styles.cog}
            onClick={action.onPress}
            aria-label={action.label}
            title={action.label}
            aria-pressed={action.on === undefined ? undefined : action.on}
            data-on={action.on || undefined}
            data-tool={action.id}
          >
            <Icon size={20} strokeWidth={2.1} aria-hidden="true" />
          </button>
        );
      })}
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
      {/* The bookmark went into More (Matt: "put bookmark in the more menu"); More itself ends the bar. */}
      {more ? <NoteMore onMore={onMore} /> : null}
    </div>
  );
}
