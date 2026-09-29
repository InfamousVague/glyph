import {
  Asterisk,
  Calculator,
  ChartNoAxesCombined,
  ChevronLeft,
  ChevronRight,
  CircleDot,
  Clock,
  Ellipsis,
  FileText,
  Film,
  Gauge,
  Grid2x2Plus,
  Hash,
  Heading,
  ImagePlus,
  Info,
  List,
  ListOrdered,
  ListTodo,
  Minus,
  Sparkles,
  SquareCode,
  SquareDashed,
  SquareKanban,
  Table,
  TextQuote,
  Workflow,
} from '@glacier/icons';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type KeyboardEvent, type MutableRefObject, type ReactNode } from 'react';
import type { EditorView } from '@codemirror/view';
import { Locate, type StrokeIcon } from '../art/Icons.tsx';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { plugins } from '../plugins/registry.ts';
import { emptyCellsAbove, linkableTitles, moreRows, readGates, topRows, writeCanvasFrame, writeNoteLink, writeRow, type AddRow, type AddRowId } from './addRows.ts';
import { closePlus, plusMenu, type PlusKey, type PlusOpening } from './insertPlus.ts';
import styles from './AddList.module.css';

/**
 * The + beside the line's list (editor/insertPlus.ts is the +, editor/addRows.ts what the rows are and write).
 *
 * A short card against the +'s own row, never over it: below the row, or above it when the keyboard leaves no room
 * below, or on the larger side, scrolling, when neither holds it all. Its left edge is the text's. On the opened Fold
 * it keeps to one side of the crease, the window's middle, where the home page puts its gap: at the text when it fits
 * before the crease, past the crease when it does not, and across it only when neither side has room.
 *
 * It is not a sheet, which would take the page and the keyboard with it, and not the sideways band of press and hold,
 * whose bold words under icons read as a toolbox. It is the list the + promised: seven things and More, which turns
 * the list over to the rest in the same card, with Back at its top (Matt: "Fuller but hide extras behind nested
 * menu"). More and Back are the doors between the two pages, so neither ever scrolls: a phone's keyboard leaves room
 * for six or seven rows at most, and the rows between the doors scroll under a fade while the doors stay put.
 *
 * **Focus.** Pressed with a finger or a mouse, the list never takes the focus: the editor keeps it, with its caret and
 * the keyboard, and the list is driven from the editor's keys (Up and Down move the lit row, Enter chooses it, Escape
 * closes, Left goes back, Right goes into More), the lit row named to a screen reader through the editor. Opened from
 * the keyboard on the + itself, the focus comes into the list's first row. A step that asks which note to link to is
 * the one place the list takes the focus on purpose, for its field.
 *
 * The lit row wears the kit's ring only once a key has moved it, so the keyboard's place is seen; lit by the pointer,
 * or first as the list opens, it has the pressed paper and no ring, which would otherwise follow the mouse about.
 *
 * **Closing.** A row chosen closes the list first and then does what it says. So do a press anywhere else, a wheel or
 * a drag outside it, Escape, the back gesture, the × pressed again, any other key, and any change or caret move in the
 * note. A scroll does not: the keyboard rising shortens the page and the editor scrolls the caret into view, so the
 * list follows the + instead, and closes only once the + has left the screen. On More or a step, the back gesture
 * goes back a page, as Back and Left do.
 */

export interface AddListProps {
  view: EditorView;
  opening: PlusOpening;
  /** The note's pane, for the crease and the room above the row: the box of the page that scrolls the note. */
  pane: () => DOMRect | null;
  onClose: () => void;
  /** Where the editor's keys reach the list while the editor keeps the focus (editor/insertPlus.ts `onKey`). */
  keys: MutableRefObject<((key: PlusKey) => boolean) | null>;
  /** What the screen itself can put in, beyond what the device allows: absent, the row is not there. */
  onPicture?: () => void;
  onPlace?: () => void;
  onVideo?: () => void;
  /** Every note's title, for A note; absent where notes cannot be opened. */
  titles?: () => string[];
  /** Every canvas's title, for A canvas; absent where a canvas cannot be framed. */
  canvases?: () => string[];
  /** This note's own title, which it does not link to. */
  own: string;
}

const LIST_ID = 'add-list';
/** How far the list sits from the +'s row, above or below it. */
const GAP = 6;
/** How near the list comes to the screen's edges and to the crease. */
const EDGE = 8;
const CREASE_GAP = 16;

type Page = 'top' | 'more' | 'note' | 'canvas';

const ICONS: Partial<Record<AddRowId, StrokeIcon>> = {
  picture: ImagePlus,
  video: Film,
  time: Clock,
  table: Table,
  note: FileText,
  todo: ListTodo,
  more: Ellipsis,
  heading: Heading,
  bullets: List,
  numbers: ListOrdered,
  quote: TextQuote,
  callout: Info,
  choice: CircleDot,
  code: SquareCode,
  divider: Minus,
  board: SquareKanban,
  chart: ChartNoAxesCombined,
  canvas: Workflow,
  footnote: Asterisk,
  tag: Hash,
  counter: Gauge,
  sum: Calculator,
  blank: SquareDashed,
  blankCells: Grid2x2Plus,
};

function iconFor(id: AddRowId | 'back'): ReactNode {
  if (id === 'back') return <ChevronLeft size={18} strokeWidth={2} />;
  // The place is the app's own mark, the one on the More sheet's Add my location (editor/NoteSettings.tsx).
  if (id === 'place') return <Locate />;
  if (id.startsWith('effect:')) {
    const Mark = plugins.formats().find((format) => `effect:${format.name}` === id)?.icon ?? Sparkles;
    return <Mark size={18} strokeWidth={2} />;
  }
  const Icon = ICONS[id as AddRowId] ?? Sparkles;
  return <Icon size={18} strokeWidth={2} />;
}

const rowId = (id: string) => `add-${id.replace(/[^a-z0-9-]/gi, '-')}`;

export function AddList({ view, opening, pane, onClose, keys, onPicture, onPlace, onVideo, titles, canvases, own }: AddListProps) {
  const card = useRef<HTMLDivElement>(null);
  const rowsBox = useRef<HTMLDivElement>(null);
  const [page, setPage] = useState<Page>('top');
  const [turn, setTurn] = useState<'forward' | 'back' | null>(null);
  const [now, setNow] = useState(() => new Date());
  const [looking, setLooking] = useState('');
  const [more, setMore] = useState('');
  // The editor keeps the focus unless the + was opened from the keyboard; a fine pointer lights the first row, so the
  // keys have a place to start from.
  const driven = opening.by !== 'keyboard';
  const [active, setActive] = useState(opening.by === 'touch' ? -1 : 0);
  // Whether a key moved the lit row last, rather than the pointer or the list opening: only then is it ringed.
  const [keyed, setKeyed] = useState(false);

  // The gates, read once as the list opens (editor/addRows.ts).
  const gates = useMemo(
    () =>
      readGates({
        picture: Boolean(onPicture),
        video: Boolean(onVideo),
        place: Boolean(onPlace),
        note: Boolean(titles),
        canvas: Boolean(canvases),
        // Read from the +'s line as the list opens, beside the others: a table straight above with an empty cell.
        tableAbove: emptyCellsAbove(view.state, view.state.selection.main.head) !== null,
      }),
    [onPicture, onVideo, onPlace, titles, canvases, view],
  );

  // The time row says what it will write: read as the list opens, and again at the turn of each minute while it is open.
  useEffect(() => {
    let timer = 0;
    const tick = () => {
      setNow(new Date());
      timer = window.setTimeout(tick, 60_000 - (Date.now() % 60_000));
    };
    timer = window.setTimeout(tick, 60_000 - (Date.now() % 60_000));
    return () => window.clearTimeout(timer);
  }, []);

  const rows: (AddRow | { id: 'back'; words: string })[] =
    page === 'top' ? topRows(gates, now) : page === 'more' ? [{ id: 'back', words: 'Back' }, ...moreRows(gates)] : [];

  /** The list closed: told to the editor first, so the × turns back and what a row writes is not read as a change under it. */
  const close = useCallback(
    (refocus: boolean) => {
      closePlus(view);
      onClose();
      if (refocus && !view.hasFocus && view.dom.isConnected) view.focus();
    },
    [view, onClose],
  );

  const go = (next: Page, way: 'forward' | 'back') => {
    fireNativeHaptic('selection');
    setTurn(way);
    setPage(next);
    setLooking('');
    setActive(driven && opening.by === 'touch' ? -1 : 0);
  };

  /** A row's press: dimmed, a step, or the list closed and then what the row does. */
  const choose = (row: AddRow | { id: 'back'; words: string }) => {
    if (row.id === 'back') {
      go('top', 'back');
      return;
    }
    const chosen = row as AddRow;
    if (chosen.dimmed) {
      fireNativeHaptic('warning');
      return;
    }
    if (chosen.step) {
      go(chosen.step, 'forward');
      return;
    }
    fireNativeHaptic('selection');
    close(false);
    if (chosen.id === 'picture') onPicture?.();
    else if (chosen.id === 'video') onVideo?.();
    else if (chosen.id === 'place') onPlace?.();
    // The time the row says, not the clock's: pressed just past the minute, before the row has turned, it wrote 14:06
    // under a row that said 14:05.
    else if (writeRow(view, chosen.id, now) && !view.hasFocus) view.focus();
  };

  /** A note or a canvas chosen in a step: written where the caret was, and the note has the focus back. */
  const pick = (title: string) => {
    fireNativeHaptic('selection');
    close(false);
    if (page === 'canvas') writeCanvasFrame(view, title);
    else writeNoteLink(view, title);
    view.focus();
  };

  // The editor names the lit row to a screen reader while it keeps the focus (editor/insertPlus.ts).
  const activeId = driven && active >= 0 && rows[active] ? rowId(rows[active].id) : null;
  useEffect(() => {
    if (view.dom.isConnected) view.dispatch({ effects: plusMenu.of({ list: LIST_ID, active: activeId }) });
  }, [view, activeId]);
  // Gone from the page: the editor hears the list closed, however it closed.
  useEffect(() => () => closePlus(view), [view]);

  // Opened from the keyboard, the focus is in the list: on its first row, and again on each page.
  useEffect(() => {
    if (driven || page === 'note' || page === 'canvas') return;
    card.current?.querySelector<HTMLButtonElement>(`[data-index="${Math.max(0, active)}"]`)?.focus();
  }, [driven, page, active]);

  const move = (by: number) => {
    if (!rows.length) return;
    setKeyed(true);
    setActive((was) => (was < 0 ? (by > 0 ? 0 : rows.length - 1) : (was + by + rows.length) % rows.length));
  };

  // The editor's keys, while it keeps the focus.
  keys.current = (key: PlusKey): boolean => {
    if (key === 'escape') {
      close(false);
      return true;
    }
    if (page === 'note' || page === 'canvas') return false;
    if (key === 'up' || key === 'down') {
      move(key === 'up' ? -1 : 1);
      return true;
    }
    if (key === 'left') {
      if (page === 'top') return false;
      go('top', 'back');
      return true;
    }
    const row = rows[active];
    if (!row) return false;
    if (key === 'right') {
      if (!('step' in row) || row.step !== 'more') return false;
      choose(row);
      return true;
    }
    choose(row);
    return true;
  };
  useEffect(
    () => () => {
      keys.current = null;
    },
    [keys],
  );

  // The same keys when the focus is in the list itself.
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      close(true);
      return;
    }
    const inField = event.target instanceof HTMLInputElement;
    if (event.key === 'ArrowLeft' && page !== 'top' && !inField) {
      event.preventDefault();
      go('top', 'back');
      return;
    }
    if ((event.key === 'ArrowDown' || event.key === 'ArrowUp') && !inField && rows.length) {
      event.preventDefault();
      move(event.key === 'ArrowUp' ? -1 : 1);
    }
  };

  // The phone's back gesture goes back a page, as Back does, and closes the list from its first.
  useBack(true, () => (page === 'top' ? close(true) : go('top', 'back')));

  // It closes on a press anywhere but itself and the +, and on a wheel or a drag outside it.
  useEffect(() => {
    const outside = (event: Event) => {
      const target = event.target;
      if (!(target instanceof Node)) return;
      if (card.current?.contains(target) || opening.button.contains(target)) return;
      close(false);
    };
    document.addEventListener('pointerdown', outside, true);
    document.addEventListener('wheel', outside, { capture: true, passive: true });
    document.addEventListener('touchmove', outside, { capture: true, passive: true });
    return () => {
      document.removeEventListener('pointerdown', outside, true);
      document.removeEventListener('wheel', outside, { capture: true });
      document.removeEventListener('touchmove', outside, { capture: true });
    };
  }, [opening.button, close]);

  /** Against the +'s row: below it, above it, or on the larger side; beside the text, and clear of the crease. */
  const place = useCallback(() => {
    const element = card.current;
    const scroller = rowsBox.current;
    if (!element || !scroller) return;
    const row = opening.button.getBoundingClientRect();
    const viewport = window.visualViewport;
    const viewTop = viewport ? viewport.offsetTop : 0;
    const viewBottom = viewport ? viewport.offsetTop + viewport.height : window.innerHeight;
    // The + scrolled out of sight: the list has nothing to be beside. (A + with no box has not been laid out yet.)
    if (row.height > 0 && (row.bottom <= viewTop || row.top >= viewBottom)) {
      close(false);
      return;
    }
    const box = pane();
    const top = Math.max(viewTop, box?.top ?? 0) + EDGE;
    const bottom = viewBottom - EDGE;
    // Its whole height, read without unsetting the cap, which would lose where its rows are scrolled to.
    const chrome = element.offsetHeight - scroller.offsetHeight;
    const natural = chrome + scroller.scrollHeight;
    const rowHeight = (scroller.querySelector<HTMLElement>('[data-index]')?.offsetHeight ?? 44) * 3 + 8;
    const below = bottom - (row.bottom + GAP);
    const above = row.top - GAP - top;
    let y: number;
    let height = natural;
    if (natural <= below) y = row.bottom + GAP;
    else if (natural <= above) y = row.top - GAP - natural;
    else if (below >= above) {
      height = Math.max(below, rowHeight);
      y = row.bottom + GAP;
    } else {
      height = Math.max(above, rowHeight);
      y = row.top - GAP - height;
    }
    scroller.style.maxBlockSize = height < natural ? `${Math.max(0, height - chrome)}px` : '';

    // Across: the text's left edge, and on a folding phone opened out, one side of the crease.
    const text = row.right;
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
    const full = element.offsetWidth || 16 * rem;
    let x = text;
    let width = full;
    const opened = typeof matchMedia !== 'undefined' && matchMedia('(pointer: coarse) and (min-width: 600px)').matches;
    if (opened) {
      const crease = window.innerWidth / 2;
      const before = crease - CREASE_GAP - text;
      const right = (box?.right ?? window.innerWidth) - row.width;
      const past = right - (crease + CREASE_GAP);
      if (text < crease && before < full) {
        if (before >= 12 * rem) width = before;
        else if (past >= 12 * rem) {
          x = crease + CREASE_GAP;
          width = Math.min(full, past);
        }
      }
    }
    x = Math.max(EDGE, Math.min(x, window.innerWidth - width - EDGE));
    element.style.left = `${x}px`;
    element.style.top = `${y}px`;
    element.style.inlineSize = width === full ? '' : `${width}px`;
  }, [opening.button, pane, close]);

  // A page turned opens at its top, with Back first, wherever the page before was scrolled to.
  useLayoutEffect(() => {
    if (rowsBox.current) rowsBox.current.scrollTop = 0;
  }, [page]);

  useLayoutEffect(() => {
    place();
  }, [place, page, rows.length, looking]);

  // Re-anchored to the + on every scroll and resize, one frame at a time: the keyboard rising scrolls the note. A
  // scroll of the list's own rows is the list's.
  useEffect(() => {
    let frame = 0;
    const soon = (event?: Event) => {
      if (event?.target instanceof Node && card.current?.contains(event.target)) return;
      window.cancelAnimationFrame(frame);
      frame = window.requestAnimationFrame(place);
    };
    document.addEventListener('scroll', soon, { capture: true, passive: true });
    window.addEventListener('resize', soon);
    window.visualViewport?.addEventListener('resize', soon);
    window.visualViewport?.addEventListener('scroll', soon);
    return () => {
      window.cancelAnimationFrame(frame);
      document.removeEventListener('scroll', soon, { capture: true });
      window.removeEventListener('resize', soon);
      window.visualViewport?.removeEventListener('resize', soon);
      window.visualViewport?.removeEventListener('scroll', soon);
    };
  }, [place]);

  // Rows past an edge fade there.
  useEffect(() => {
    const element = rowsBox.current;
    if (!element) return undefined;
    const measure = () => {
      const start = element.scrollTop > 1;
      const end = element.scrollTop + element.clientHeight < element.scrollHeight - 1;
      setMore([start ? 'start' : '', end ? 'end' : ''].filter(Boolean).join(' '));
    };
    measure();
    element.addEventListener('scroll', measure, { passive: true });
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(measure);
    observer?.observe(element);
    return () => {
      element.removeEventListener('scroll', measure);
      observer?.disconnect();
    };
  }, [page]);

  // The lit row kept in sight as the keys move it.
  useEffect(() => {
    if (active < 0) return;
    rowsBox.current?.querySelector<HTMLElement>(`[data-index="${active}"]`)?.scrollIntoView?.({ block: 'nearest' });
  }, [active, page]);

  const step = page === 'note' || page === 'canvas';
  const found = step ? linkableTitles((page === 'note' ? titles : canvases)?.() ?? [], own, looking) : [];

  /** A row of the menu, where it is drawn: among the rows that scroll, or held at the card's top or foot. */
  const menuRow = (row: (typeof rows)[number], index: number) => {
    const dimmed = 'dimmed' in row ? row.dimmed : undefined;
    return (
      <button
        key={row.id}
        type="button"
        role="menuitem"
        id={rowId(row.id)}
        className={styles.row}
        data-index={index}
        data-active={(driven && index === active) || undefined}
        tabIndex={driven ? -1 : index === Math.max(0, active) ? 0 : -1}
        aria-disabled={dimmed ? true : undefined}
        aria-label={'label' in row ? row.label : undefined}
        onClick={() => choose(row)}
        onPointerEnter={(event) => {
          if (!driven || event.pointerType !== 'mouse') return;
          setKeyed(false);
          setActive(index);
        }}
      >
        <span className={styles.icon} aria-hidden="true">
          {iconFor(row.id)}
        </span>
        <span className={styles.words}>
          {row.words}
          {dimmed ? <span className={styles.why}>{dimmed}</span> : null}
        </span>
        {'step' in row && row.step === 'more' ? (
          <span className={styles.onward} aria-hidden="true">
            <ChevronRight size={16} strokeWidth={2} />
          </span>
        ) : null}
      </button>
    );
  };
  // The doors between the pages never scroll away: Back held at the top of More, More at the foot of the first page.
  const head = page === 'more' && rows[0]?.id === 'back' ? 0 : -1;
  const foot = page === 'top' && rows.at(-1)?.id === 'more' ? rows.length - 1 : -1;
  const turned = { 'data-turn': turn ?? undefined };

  return (
    <div
      ref={card}
      className={styles.list}
      id={LIST_ID}
      role={step ? 'group' : 'menu'}
      aria-label={step ? (page === 'note' ? 'Which note?' : 'Which canvas?') : 'Add to this note'}
      data-keys={(driven && keyed) || undefined}
      // A press on the list must not take the editor's focus or its caret, for a mouse as for a finger.
      onPointerDown={(event) => {
        if (!(event.target instanceof HTMLInputElement)) event.preventDefault();
      }}
      onKeyDown={onKeyDown}
    >
      {step ? (
        <div key={`${page}-head`} className={`${styles.page} ${styles.head}`} {...turned}>
          <button type="button" className={styles.row} data-index={0} onClick={() => go('top', 'back')}>
            <span className={styles.icon} aria-hidden="true">
              {iconFor('back')}
            </span>
            <span className={styles.words}>Back</span>
          </button>
        </div>
      ) : head >= 0 ? (
        <div key={`${page}-head`} className={`${styles.page} ${styles.head}`} {...turned}>
          {menuRow(rows[head]!, head)}
        </div>
      ) : null}
      <div ref={rowsBox} className={styles.rows} data-rows="" data-more={more || undefined}>
        <div key={page} className={styles.page} {...turned}>
          {step ? (
            <>
              <p className={styles.title}>{page === 'note' ? 'Which note?' : 'Which canvas?'}</p>
              <input
                className={styles.field}
                autoFocus
                value={looking}
                placeholder={page === 'note' ? 'Type part of its title' : 'Type part of its name'}
                aria-label={page === 'note' ? 'Part of the note’s title' : 'Part of the canvas’s name'}
                onChange={(event) => setLooking(event.currentTarget.value)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter' && found[0]) {
                    event.preventDefault();
                    pick(found[0]);
                  }
                }}
              />
              <ul className={styles.found} aria-label={page === 'note' ? 'Notes' : 'Canvases'}>
                {found.map((title) => (
                  <li key={title}>
                    <button type="button" className={styles.row} onClick={() => pick(title)}>
                      <span className={styles.icon} aria-hidden="true">
                        {iconFor(page === 'note' ? 'note' : 'canvas')}
                      </span>
                      <span className={styles.words}>{title}</span>
                    </button>
                  </li>
                ))}
                {!found.length ? (
                  <li className={styles.none}>
                    {looking.trim() ? (page === 'note' ? 'No note by that name.' : 'No canvas by that name.') : page === 'note' ? 'No notes yet.' : 'No canvases yet.'}
                  </li>
                ) : null}
              </ul>
            </>
          ) : (
            rows.map((row, index) => (index === head || index === foot ? null : menuRow(row, index)))
          )}
        </div>
      </div>
      {foot >= 0 ? (
        <div key={`${page}-foot`} className={`${styles.page} ${styles.foot}`} {...turned}>
          {menuRow(rows[foot]!, foot)}
        </div>
      ) : null}
    </div>
  );
}
