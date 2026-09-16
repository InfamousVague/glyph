import {
  Bold,
  ChevronLeft,
  ClipboardPaste,
  Code,
  Copy,
  Heading,
  ImagePlus,
  Italic,
  Link,
  List,
  ListOrdered,
  ListTodo,
  Minus,
  Scissors,
  Strikethrough,
  Table,
  TextQuote,
  TextSearch,
  TextSelect,
  Type,
} from '@glacier/icons';
import { useCallback, useEffect, useReducer, useRef, useState, type ComponentType, type CSSProperties, type HTMLAttributes } from 'react';
import type { EditorView } from '@codemirror/view';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { plugins } from '../plugins/registry.ts';
import { activeBlock, activeMarks, activeWraps, insertLink, insertRule, insertTable, toggleBlock, toggleMark, toggleWrap, type Block, type Mark } from './format.ts';
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
 *
 * Each word stands under its drawn icon, in display weight, the same hand as
 * a linked line's menu (MarkMenu.tsx). Matt: "make the options typography and
 * iconography heavy so they fit the theme on all context menus".
 *
 * Style is here too, not in a bar of its own (Matt, of the bar of symbols
 * under the top bar: "redo the UI/UX for selecting text styles, it doesn't
 * look good as is, maybe it needs to be something we do by pressing and
 * holding on text"). Style turns the menu over to the formatting, in the same
 * hand: the marks that wrap the selection (bold, italic, struck, code, and
 * any a switched-on plugin adds, like Spoiler), the forms a line takes
 * (heading, quote, list, numbered, to-do), and the things put in (link,
 * table, rule), all in one band that scrolls sideways, a little space between
 * the three kinds (three bands stacked "looks a bit strange", Matt; a heavier
 * rule between the kinds read as "two pixels thick"). A
 * pressed style stays on the menu, lit while it applies, so a word can be
 * made bold and struck in one go; the arrow goes back.
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
  /** Opens find and replace with the selected words (FindBar.tsx); absent, the word is not shown. */
  onFind?: (text: string) => void;
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

export function ContextMenu({ view, onAddImage, onPasteImage, edits = [], onEdit, editsUnavailable = null, onFind }: ContextMenuProps) {
  const [open, setOpen] = useState<Open | null>(null);
  /** The menu's words, or its styles. */
  const [styling, setStyling] = useState(false);
  // A style pressed changes what is lit: the menu reads the editor again.
  const [, restyled] = useReducer((n: number) => n + 1, 0);
  const menu = useRef<HTMLDivElement>(null);
  const canPaste = hostClipboard() !== null;

  const close = useCallback(() => setOpen(null), []);

  // The press: where the selection is, or where the finger was.
  useEffect(() => {
    if (!view) return undefined;
    const dom = view.dom;
    const show = (x: number, y: number) => {
      const { from, to, head } = view.state.selection.main;
      const at = view.coordsAtPos(head);
      setStyling(false);
      setOpen({ x: at ? (at.left + at.right) / 2 : x, y: at ? at.top : y, from, to });
    };
    const onContextMenu = (event: MouseEvent) => {
      event.preventDefault();
      // The word the press selected has landed by the next frame.
      window.requestAnimationFrame(() => show(event.clientX, event.clientY));
    };
    dom.addEventListener('contextmenu', onContextMenu);

    // A long press where there is no word to hold, an empty line or the space after a line's last word, selects
    // nothing, so the phone may fire no contextmenu and the caret may be somewhere else (Matt: "quite hard to open
    // on new text lines where there's nothing yet"). Timed here instead: the caret goes to the finger and the menu
    // opens there. A press on a word is left to the phone, which selects it and fires contextmenu as before.
    let press: { timer: number; x: number; y: number } | null = null;
    const cancel = () => {
      if (press) window.clearTimeout(press.timer);
      press = null;
    };
    const onPointerDown = (event: PointerEvent) => {
      if (event.pointerType === 'mouse' || !event.isPrimary) return;
      cancel();
      const { clientX: x, clientY: y } = event;
      press = {
        x,
        y,
        timer: window.setTimeout(() => {
          press = null;
          const pos = view.posAtCoords({ x, y });
          if (pos === null) return;
          const line = view.state.doc.lineAt(pos);
          const wordAt = (offset: number) => offset > line.from - 1 && offset < line.to && /\S/.test(view.state.sliceDoc(offset, offset + 1));
          if (wordAt(pos) || wordAt(pos - 1)) return;
          view.dispatch({ selection: { anchor: pos } });
          fireNativeHaptic('selection');
          show(x, y);
        }, LONG_PRESS_MS),
      };
    };
    const onPointerMove = (event: PointerEvent) => {
      if (press && Math.hypot(event.clientX - press.x, event.clientY - press.y) > 8) cancel();
    };
    dom.addEventListener('pointerdown', onPointerDown);
    dom.addEventListener('pointermove', onPointerMove);
    dom.addEventListener('pointerup', cancel);
    dom.addEventListener('pointercancel', cancel);
    return () => {
      cancel();
      dom.removeEventListener('contextmenu', onContextMenu);
      dom.removeEventListener('pointerdown', onPointerDown);
      dom.removeEventListener('pointermove', onPointerMove);
      dom.removeEventListener('pointerup', cancel);
      dom.removeEventListener('pointercancel', cancel);
    };
  }, [view]);

  // It leaves on a touch anywhere else, a scroll, or the back gesture.
  useEffect(() => {
    if (!open) return undefined;
    const outside = (event: PointerEvent) => {
      if (menu.current && event.target instanceof Node && menu.current.contains(event.target)) return;
      close();
    };
    // A scroll along the menu's own band (the styles run past the screen's edge) is not a scroll of the note.
    const onScroll = (event: Event) => {
      if (menu.current && event.target instanceof Node && menu.current.contains(event.target)) return;
      close();
    };
    document.addEventListener('pointerdown', outside, true);
    // Scroll events don't bubble; captured on the document, a scroll of the editor or of the page around it is heard.
    document.addEventListener('scroll', onScroll, { capture: true, passive: true });
    return () => {
      document.removeEventListener('pointerdown', outside, true);
      document.removeEventListener('scroll', onScroll, { capture: true });
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
  }, [open, styling]);

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

  if (styling) {
    const style = (run: (target: EditorView) => void) => () => {
      fireNativeHaptic('selection');
      run(view);
      restyled();
    };
    const put = (run: (target: EditorView) => void) => () => {
      fireNativeHaptic('selection');
      close();
      run(view);
      view.focus();
    };
    const state = view.state;
    // Each switched-on plugin's formattings, under that plugin's own icon.
    // A mark's own icon where it has one (plugins/types.ts `InlineFormat`), else the plugin's, else the letter.
    const formats = plugins.enabled().flatMap((plugin) => (plugin.formats ?? []).map((format) => ({ format, icon: ((format.icon ?? plugin.icon) as Icon | undefined) ?? Type })));
    return (
      <div ref={menu} className={styles.menu} role="menu" aria-label="Styles" onPointerDown={(event) => event.preventDefault()}>
        <Row>
          <button type="button" role="menuitem" className={styles.item} onClick={() => setStyling(false)} aria-label="Back to the note's actions">
            <Word icon={ChevronLeft} label="Back" />
          </button>
          {MARKS.map(({ mark, icon, label }, i) => (
            <StyleItem key={mark} icon={icon} label={label} i={i} lit={activeMarks(state).includes(mark)} onClick={style((target) => toggleMark(target, mark))} />
          ))}
          {formats.map(({ format, icon }, i) => (
            <StyleItem
              key={format.name}
              icon={icon}
              label={format.name}
              i={MARKS.length + i}
              lit={activeWraps(state, [format.delimiter]).length > 0}
              onClick={style((target) => toggleWrap(target, format.delimiter))}
            />
          ))}
          {BLOCKS.map(({ block, icon, label }, i) => (
            <StyleItem
              key={block}
              icon={icon}
              label={label}
              i={MARKS.length + formats.length + i}
              group={i === 0}
              lit={activeBlock(state) === block}
              onClick={style((target) => toggleBlock(target, block))}
            />
          ))}
          {INSERTS.map(({ key, icon, label, run }, i) => (
            <StyleItem key={key} icon={icon} label={label} i={MARKS.length + formats.length + BLOCKS.length + i} group={i === 0} onClick={put(run)} />
          ))}
        </Row>
      </div>
    );
  }

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
              <Word icon={Scissors} label="Cut" />
            </button>
            <button type="button" role="menuitem" className={styles.item} onClick={() => void act(copy)()}>
              <Word icon={Copy} label="Copy" />
            </button>
          </>
        ) : null}
        {canPaste ? (
          <button type="button" role="menuitem" className={styles.item} onClick={() => void act(paste)()}>
            <Word icon={ClipboardPaste} label="Paste" />
          </button>
        ) : null}
        {selected && onFind && to - from <= 120 ? (
          <button
            type="button"
            role="menuitem"
            className={styles.item}
            onClick={() => {
              fireNativeHaptic('selection');
              close();
              onFind(text());
            }}
          >
            <Word icon={TextSearch} label="Find" />
          </button>
        ) : null}
        <button type="button" role="menuitem" className={styles.item} onClick={() => void act(selectAll)()}>
          <Word icon={TextSelect} label="Select all" />
        </button>
        <button
          type="button"
          role="menuitem"
          className={styles.item}
          onClick={() => {
            fireNativeHaptic('selection');
            setStyling(true);
          }}
        >
          <Word icon={Type} label="Style" />
        </button>
        {onAddImage ? (
          <button type="button" role="menuitem" className={styles.item} onClick={() => void act(onAddImage)()}>
            <Word icon={ImagePlus} label="Add image" />
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

/** How long a finger holds on empty paper before the menu opens there: about the phone's own long press. */
const LONG_PRESS_MS = 480;

type Icon = ComponentType<{ size?: number; strokeWidth?: number }>;

const MARKS: { mark: Mark; icon: Icon; label: string }[] = [
  { mark: 'bold', icon: Bold, label: 'Bold' },
  { mark: 'italic', icon: Italic, label: 'Italic' },
  { mark: 'strike', icon: Strikethrough, label: 'Struck' },
  { mark: 'code', icon: Code, label: 'Code' },
];

const INSERTS: { key: string; icon: Icon; label: string; run: (view: EditorView) => void }[] = [
  { key: 'link', icon: Link, label: 'Link', run: insertLink },
  { key: 'table', icon: Table, label: 'Table', run: insertTable },
  { key: 'rule', icon: Minus, label: 'Rule', run: insertRule },
];

const BLOCKS: { block: Block; icon: Icon; label: string }[] = [
  { block: 'heading', icon: Heading, label: 'Heading' },
  { block: 'quote', icon: TextQuote, label: 'Quote' },
  { block: 'bullet', icon: List, label: 'List' },
  { block: 'number', icon: ListOrdered, label: 'Numbered' },
  { block: 'task', icon: ListTodo, label: 'To-do' },
];

/** A style: its icon over its word, lit (printed in reverse) while it applies, coming in out of smoke after the ones before it. */
function StyleItem({ icon, label, i, lit = false, group = false, onClick }: { icon: Icon; label: string; i: number; lit?: boolean; group?: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      role="menuitemcheckbox"
      aria-checked={lit}
      className={`${styles.item} ${styles.style}`}
      data-lit={lit || undefined}
      data-group={group || undefined}
      style={{ '--i': i } as CSSProperties}
      onClick={onClick}
    >
      <Word icon={icon} label={label} />
    </button>
  );
}

/** An icon over its word. */
function Word({ icon: Icon, label }: { icon: ComponentType<{ size?: number; strokeWidth?: number }>; label: string }) {
  return (
    <>
      <Icon size={20} strokeWidth={2.1} />
      <span className={styles.word}>{label}</span>
    </>
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
