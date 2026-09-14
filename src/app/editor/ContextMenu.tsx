import { useCallback, useEffect, useRef, useState, type HTMLAttributes } from 'react';
import type { EditorView } from '@codemirror/view';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import styles from './ContextMenu.module.css';

/**
 * The note's own press-and-hold menu, in place of the phone's.
 *
 * A long press in the editor (a right click on a desktop) fires `contextmenu`;
 * preventing it keeps the word the press selected, handles and all, and
 * keeps Android's own Cut / Copy / Read aloud bar away - measured on the
 * emulator, and the reason this needs nothing native. What appears instead is
 * a row of Glyph's words above the selection: Cut, Copy, Paste, Select all,
 * Add image; and under it, when the formatter offers them, the edits that
 * rewrite the selection (Shorten, Expand and the rest, from format/edits.ts).
 *
 * Reading the clipboard is the one thing the page cannot do here (the WebView
 * refuses `clipboard.read`), so Paste appears only on a build whose activity
 * answers `GlyphHost.readClipboard`; the keyboard's own paste works either
 * way. Writing is allowed, so Cut and Copy are the page's own.
 */

export interface MenuEdit {
  id: string;
  label: string;
}

interface ContextMenuProps {
  view: EditorView | null;
  /** Opens the picture picker; absent where a picture makes no sense, and the word is not shown. */
  onAddImage?: () => void;
  /** Adopts a picture the activity copied out of the clipboard, by path; answers its name. */
  onPasteImage?: (path: string) => Promise<void>;
  edits?: MenuEdit[];
  onEdit?: (id: string, from: number, to: number) => void;
  /** Why the edits cannot run right now, shown under them greyed. */
  editsUnavailable?: string | null;
}

interface Open {
  x: number;
  y: number;
  from: number;
  to: number;
}

type Clipboard = { text?: string; path?: string };

function hostClipboard(): (() => string) | null {
  const host = (window as { GlyphHost?: { readClipboard?: () => string } }).GlyphHost;
  return typeof host?.readClipboard === 'function' ? () => host.readClipboard!() : null;
}

export function ContextMenu({ view, onAddImage, onPasteImage, edits = [], onEdit, editsUnavailable = null }: ContextMenuProps) {
  const [open, setOpen] = useState<Open | null>(null);
  const menu = useRef<HTMLDivElement>(null);
  const canPaste = hostClipboard() !== null;

  const close = useCallback(() => setOpen(null), []);

  // The press: where the selection is, or where the finger was.
  useEffect(() => {
    if (!view) return undefined;
    const dom = view.dom;
    const onContextMenu = (event: MouseEvent) => {
      event.preventDefault();
      // The word the press selected has landed by the next frame.
      window.requestAnimationFrame(() => {
        const { from, to, head } = view.state.selection.main;
        const at = view.coordsAtPos(head);
        setOpen({ x: at ? (at.left + at.right) / 2 : event.clientX, y: at ? at.top : event.clientY, from, to });
      });
    };
    dom.addEventListener('contextmenu', onContextMenu);
    return () => dom.removeEventListener('contextmenu', onContextMenu);
  }, [view]);

  // It leaves on a touch anywhere else, a scroll, or the back gesture.
  useEffect(() => {
    if (!open) return undefined;
    const outside = (event: PointerEvent) => {
      if (menu.current && event.target instanceof Node && menu.current.contains(event.target)) return;
      close();
    };
    const onScroll = () => close();
    document.addEventListener('pointerdown', outside, true);
    view?.scrollDOM.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      document.removeEventListener('pointerdown', outside, true);
      view?.scrollDOM.removeEventListener('scroll', onScroll);
    };
  }, [open, view, close]);

  useBack(open !== null, close);

  // Sits above the selection, inside the screen, and never over the keyboard.
  useEffect(() => {
    const element = menu.current;
    if (!open || !element) return;
    // Layout sizes, not the drawn box: the entrance animation starts a touch
    // smaller, and a rect taken on that frame would put the menu off-centre.
    const width = element.offsetWidth;
    const height = element.offsetHeight;
    const margin = 8;
    let left = open.x - width / 2;
    left = Math.max(margin, Math.min(left, window.innerWidth - width - margin));
    let top = open.y - height - 12;
    if (top < margin) top = open.y + 40;
    element.style.left = `${left}px`;
    element.style.top = `${top}px`;
  }, [open]);

  if (!open || !view) return null;

  const { from, to } = open;
  const selected = from !== to;
  const text = () => view.state.sliceDoc(from, to);

  const act = (what: () => void | Promise<void>) => async () => {
    fireNativeHaptic('selection');
    close();
    await what();
    view.focus();
  };

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text());
    } catch {
      // A browser with no clipboard access: the old way still copies a selection.
      document.execCommand('copy');
    }
  };

  const cut = async () => {
    await copy();
    view.dispatch({ changes: { from, to, insert: '' }, selection: { anchor: from } });
  };

  const paste = async () => {
    const read = hostClipboard();
    if (!read) return;
    let clip: Clipboard;
    try {
      clip = JSON.parse(read()) as Clipboard;
    } catch {
      return;
    }
    if (clip.path && onPasteImage) {
      await onPasteImage(clip.path);
    } else if (clip.text) {
      view.dispatch({ changes: { from, to, insert: clip.text }, selection: { anchor: from + clip.text.length } });
    }
  };

  const selectAll = () => {
    view.dispatch({ selection: { anchor: 0, head: view.state.doc.length } });
  };

  return (
    <div
      ref={menu}
      className={styles.menu}
      role="menu"
      aria-label="Note actions"
      // A press on the menu must not take the editor's focus or its selection.
      onPointerDown={(event) => event.preventDefault()}
    >
      <Row>
        {selected ? (
          <>
            <button type="button" role="menuitem" className={styles.item} onClick={() => void act(cut)()}>
              Cut
            </button>
            <button type="button" role="menuitem" className={styles.item} onClick={() => void act(copy)()}>
              Copy
            </button>
          </>
        ) : null}
        {canPaste ? (
          <button type="button" role="menuitem" className={styles.item} onClick={() => void act(paste)()}>
            Paste
          </button>
        ) : null}
        <button type="button" role="menuitem" className={styles.item} onClick={() => void act(selectAll)()}>
          Select all
        </button>
        {onAddImage ? (
          <button type="button" role="menuitem" className={styles.item} onClick={() => void act(onAddImage)()}>
            Add image
          </button>
        ) : null}
      </Row>
      {selected && edits.length ? (
        <Row data-edits="" aria-disabled={editsUnavailable ? true : undefined}>
          {edits.map((edit) => (
            <button
              key={edit.id}
              type="button"
              role="menuitem"
              className={styles.item}
              disabled={Boolean(editsUnavailable)}
              onClick={() => void act(() => onEdit?.(edit.id, from, to))()}
            >
              {edit.label}
            </button>
          ))}
          {editsUnavailable ? <span className={styles.why}>{editsUnavailable}</span> : null}
        </Row>
      ) : null}
    </div>
  );
}

/**
 * One band of the menu. Five words do not always fit a phone held upright,
 * so the band scrolls sideways, and fades at whichever end has more: a word
 * cut off at the edge reads as broken, a word fading out reads as "and more".
 */
function Row({ children, ...rest }: HTMLAttributes<HTMLDivElement>) {
  const row = useRef<HTMLDivElement>(null);
  const [more, setMore] = useState('');

  useEffect(() => {
    const element = row.current;
    if (!element) return undefined;
    const measure = () => {
      const start = element.scrollLeft > 1;
      const end = element.scrollLeft + element.clientWidth < element.scrollWidth - 1;
      setMore([start ? 'start' : '', end ? 'end' : ''].filter(Boolean).join(' '));
    };
    measure();
    element.addEventListener('scroll', measure, { passive: true });
    return () => element.removeEventListener('scroll', measure);
  }, []);

  return (
    <div ref={row} className={styles.row} data-more={more || undefined} {...rest}>
      {children}
    </div>
  );
}
