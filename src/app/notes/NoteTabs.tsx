import { useEffect, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight, PanelLeft, X } from '@glacier/icons';
import { noteTitle, type Note } from '../core/store.ts';
import { useWorkspaces } from '../core/workspaces.ts';
import styles from './NoteTabs.module.css';

/**
 * The row across the top of a note: the notes that are open, and the way to
 * the rest of them (Matt: "add tabs at the top of the app for the different
 * notes that are open", and "add a sidebar that opens as a floating card, add
 * a sidebar icon on the top left of the page").
 *
 * Both asks are one bar. The sidebar's icon is the row's first thing, which
 * puts it at the top left of the page without a second back word fighting the
 * note's own; the tabs run beside it and scroll sideways when there are more
 * than fit. A tap changes note without leaving the screen; the cross closes a
 * tab, and the note behind it carries on existing, it is only no longer open.
 *
 * The row lives inside the note's header pane (editor/NoteScreen.tsx), so the
 * note scrolls under it and the header's own height already accounts for it.
 */

interface NoteTabsProps {
  /** The open notes, in the order they were opened. */
  tabs: Note[];
  activeId: string;
  onOpen: (id: string) => void;
  onClose: (id: string) => void;
  /** The floating list of every note; absent where the list is already beside the note (the desktop sidebar). */
  onSidebar?: () => void;
  sidebarOpen?: boolean;
  /** A tab dragged to sit somewhere else in the row (notes/openTabs.ts). */
  onMove?: (id: string, to: number) => void;
  /** Back and forward through where he has been (notes/visited.ts), beside the sidebar's button. */
  onGoBack?: () => void;
  onGoOn?: () => void;
  canGoBack?: boolean;
  canGoOn?: boolean;
}

/** How far a mouse must travel before a press on a tab is a drag rather than a click. */
const TRAVEL = 6;

export function NoteTabs({
  tabs,
  activeId,
  onOpen,
  onClose,
  onSidebar,
  sidebarOpen,
  onMove,
  onGoBack,
  onGoOn,
  canGoBack = false,
  canGoOn = false,
}: NoteTabsProps) {
  const spaces = useWorkspaces();
  /*
   * Dragging a tab along the row (Matt: "Add dragging around tabs into different positions"). The row reorders under
   * the finger rather than a ghost following it: the tab being dragged is the tab in the row, and it swaps with a
   * neighbour the moment the pointer passes that neighbour's middle.
   *
   * The drag is followed on the window rather than on the tab, and deliberately: reordering moves the tab's own
   * element in the DOM, which drops a pointer capture held on it. Held that way, a drag lost its end - no pointerup
   * ever arrived at the tab - and every later tap was swallowed as "the click that ends a drag". The window sees the
   * whole gesture whatever React does to the row underneath.
   *
   * A mouse drags once it has actually travelled, since a plain click emits a move of no distance. A finger waits a
   * moment first, because the row scrolls sideways and a flick along it must stay a flick - the same reason a phone's
   * home screen waits before it lets you move an icon.
   */
  const row = useRef<HTMLDivElement>(null);
  const [moving, setMoving] = useState<string | null>(null);
  /** A drag ends in a click somewhere in the row, which must not also open a note. */
  const dragged = useRef(false);

  /** Which place in the row the pointer is over: the first tab whose middle it has not passed. */
  const placeAt = (x: number): number => {
    const items = row.current ? [...row.current.querySelectorAll<HTMLElement>('[data-tab]')] : [];
    for (let i = 0; i < items.length; i += 1) {
      const box = items[i]!.getBoundingClientRect();
      if (x < box.left + box.width / 2) return i;
    }
    return items.length - 1;
  };

  const takeHold = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!onMove || (event.pointerType === 'mouse' && event.button !== 0)) return;
    const tab = (event.target as HTMLElement).closest<HTMLElement>('[data-tab]');
    const id = tab?.dataset.tabId;
    if (!id) return;
    // The cross is not a handle: pressing it means close, whatever the finger does next.
    if ((event.target as HTMLElement).closest('[data-close]')) return;

    const from = event.clientX;
    const mouse = event.pointerType === 'mouse';
    let on = false;
    const hold = mouse
      ? 0
      : window.setTimeout(() => {
          on = true;
          setMoving(id);
        }, 220);

    const along = (moved: PointerEvent) => {
      if (!on) {
        if (!mouse || Math.abs(moved.clientX - from) < TRAVEL) return;
        on = true;
        setMoving(id);
      }
      dragged.current = true;
      onMove(id, placeAt(moved.clientX));
    };
    const done = () => {
      window.clearTimeout(hold);
      window.removeEventListener('pointermove', along);
      window.removeEventListener('pointerup', done);
      window.removeEventListener('pointercancel', done);
      setMoving(null);
      // The click that ends the drag is swallowed below; this clears the flag even when the gesture ends
      // somewhere that sends no click at all.
      if (dragged.current) window.setTimeout(() => {
        dragged.current = false;
      }, 0);
    };
    window.addEventListener('pointermove', along);
    window.addEventListener('pointerup', done);
    window.addEventListener('pointercancel', done);
  };

  /*
   * Whether the row has more tabs than fit, which is the only time its end should go to smoke (Matt: "only show the
   * wisp blur effect on the end of the scrolling tab list when it overflows the screen"). Watched rather than worked
   * out once: tabs are added, closed, dragged and renamed, workspaces put a pill in front of a name, and the window
   * changes width, and each of those can turn a row that fits into one that does not.
   */
  const [over, setOver] = useState(false);
  useEffect(() => {
    const el = row.current;
    if (!el) return undefined;
    const look = () => setOver(el.scrollWidth - el.clientWidth > 1);
    look();
    const watch = new ResizeObserver(look);
    watch.observe(el);
    for (const tab of el.children) watch.observe(tab);
    return () => watch.disconnect();
  }, [tabs]);

  /** Moving a tab without a pointer: the arrow keys with the platform's own modifier, as a browser's tab strip does. */
  const nudge = (id: string, at: number) => (event: React.KeyboardEvent) => {
    if (!onMove || !(event.metaKey || event.ctrlKey)) return;
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    onMove(id, at + (event.key === 'ArrowLeft' ? -1 : 1));
  };

  if (!onSidebar && !onGoBack && tabs.length === 0) return null;
  return (
    <div className={styles.bar}>
      {onSidebar ? (
        <button
          type="button"
          className={styles.sidebar}
          onClick={onSidebar}
          aria-label="All your notes"
          aria-expanded={sidebarOpen ?? false}
          data-on={sidebarOpen || undefined}
        >
          <PanelLeft size={18} strokeWidth={2.1} aria-hidden="true" />
        </button>
      ) : null}
      {/* Where he has been: the same two arrows a browser has, in the same place, beside the sidebar's button. */}
      {onGoBack && onGoOn ? (
        <>
          <button type="button" className={styles.step} onClick={onGoBack} disabled={!canGoBack} aria-label="Back to where you were">
            <ChevronLeft size={18} strokeWidth={2.2} aria-hidden="true" />
          </button>
          <button type="button" className={styles.step} onClick={onGoOn} disabled={!canGoOn} aria-label="Forward again">
            <ChevronRight size={18} strokeWidth={2.2} aria-hidden="true" />
          </button>
        </>
      ) : null}
      {tabs.length > 0 ? (
        <div
          ref={row}
          className={styles.tabs}
          data-over={over || undefined}
          role="tablist"
          aria-label="Notes you have open"
          onPointerDown={takeHold}
          onClickCapture={(event) => {
            if (!dragged.current) return;
            dragged.current = false;
            event.preventDefault();
            event.stopPropagation();
          }}
        >
          {tabs.map((note, at) => {
            const title = noteTitle(note.body) || 'Untitled';
            const active = note.id === activeId;
            // The workspace the note is filed in, worn as its own coloured pill in front of the name (Matt: "show the
            // workspace pill first on the tab"). Two notes called Monday are told apart by colour before either is read.
            const space = spaces.list.find((w) => w.id === spaces.of[note.id]) ?? null;
            return (
              <span
                key={note.id}
                data-tab
                data-tab-id={note.id}
                className={styles.tab}
                data-active={active || undefined}
                data-moving={moving === note.id || undefined}
              >
                <button
                  type="button"
                  role="tab"
                  aria-selected={active}
                  className={styles.name}
                  onKeyDown={nudge(note.id, at)}
                  onClick={() => onOpen(note.id)}
                  // Said rather than shown twice: the pill is a colour to the eye and the workspace's name to a reader.
                  aria-label={space ? `${title}, in ${space.name}` : title}
                >
                  {space ? (
                    <span className={styles.space} data-hue={space.hue ?? 'ink'} aria-hidden="true">
                      {space.name}
                    </span>
                  ) : null}
                  <span className={styles.title}>{title}</span>
                </button>
                <button type="button" data-close className={styles.close} onClick={() => onClose(note.id)} aria-label={`Close ${title}`}>
                  <X size={14} strokeWidth={2.4} aria-hidden="true" />
                </button>
              </span>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
