import { ArrowDownToLine, ArrowUpToLine, ClipboardPaste, Copy, CopyPlus, ImagePlus, LayoutGrid, Link, Scissors, SquareKanban, TextSearch, TextSelect, Trash2, Type } from '@glacier/icons';
import { useCallback, useEffect, useRef, useState } from 'react';
import type { EditorView } from '@codemirror/view';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { itemWords } from '../core/itemLinks.ts';
import { deleteSelection, duplicateSelection, moveLines } from './format.ts';
import { boardMadeWords, boardOffers, joinBoard, makeListBoard, selectBoard } from './boardActions.ts';
import { clipboardReadable, readClipboard, writeClipboard, type Clipboard } from './clipboard.ts';
import { MenuBand, MenuWord } from './MenuBand.tsx';
import { usePressAndHold, type Held } from './pressAndHold.ts';
import { StyleItems } from './StyleMenu.tsx';
import styles from './ContextMenu.module.css';

/**
 * The note's own press-and-hold menu, in place of the phone's.
 *
 * A long press in the editor, or a right click on a desktop, opens it over the caret (editor/pressAndHold.ts says how
 * the press is heard, and why the phone's own bar stays away). What appears is a band of Glyph's words above the
 * selection: Cut and Copy on a selection, Paste, Copy board on a board, Find, Select all, Duplicate, Delete, Move up
 * and down, the board rows where they apply (editor/boardActions.ts), a plugin's send for the line, Style, and Add
 * image. Under it, on a selection, a quieter band of the edits the screen offers for it - the AI's Ask - greyed with
 * the reason when they cannot run.
 *
 * Reading the clipboard is the one thing the page cannot do here (editor/clipboard.ts), so Paste appears only where
 * the activity answers `GlyphHost.readClipboard` or the browser can read; the keyboard's own paste works either way.
 *
 * Style turns the menu over to the formatting, in the same band (editor/StyleMenu.tsx).
 *
 * The menu's own pointerdown is prevented, so a press on it never takes the editor's focus or the selection the action
 * is about. Every action closes the menu before it runs and gives the editor its focus back after. It goes on a touch
 * anywhere else, a scroll of the note, or the back gesture.
 */

/** An edit the screen offers on a selection, under the menu's words. */
interface MenuEdit {
  id: string;
  label: string;
}

interface ContextMenuProps {
  view: EditorView | null;
  /** Opens the picture picker; absent where a picture makes no sense, and the word is not shown. */
  onAddImage?: () => void;
  /** Adopts a picture the activity copied out of the clipboard, by path; answers its name. */
  onPasteImage?: (path: string) => Promise<void>;
  /** A sentence for the person, when something they asked for could not be done. */
  say?: (message: string) => void;
  /** The edits offered on a selection, and what choosing one does with it. */
  edits?: MenuEdit[];
  onEdit?: (id: string, from: number, to: number) => void;
  /** Why the edits cannot run right now, shown under them greyed. */
  editsUnavailable?: string | null;
  /** Opens find and replace with the selected words (FindBar.tsx); absent, the word is not shown. */
  onFind?: (text: string) => void;
  /** Sends the line's words where a plugin takes them (a Notion board, a GitHub issue); absent, nothing is shown. */
  send?: { label: string; run: (text: string) => Promise<void> | void } | null;
}

export function ContextMenu({ view, onAddImage, onPasteImage, say, edits = [], onEdit, editsUnavailable = null, onFind, send = null }: ContextMenuProps) {
  const [open, setOpen] = useState<Held | null>(null);
  /** The menu's words, or its styles. */
  const [styling, setStyling] = useState(false);
  const menu = useRef<HTMLDivElement>(null);
  const pasteable = clipboardReadable();

  const close = useCallback(() => setOpen(null), []);

  // The press: where the selection is, or where the finger was.
  usePressAndHold(
    view,
    useCallback((held: Held) => {
      setStyling(false);
      setOpen(held);
    }, []),
  );

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

  const copy = () => writeClipboard(text());

  const cut = async () => {
    await copy();
    view.dispatch({ changes: { from, to, insert: '' }, selection: { anchor: from } });
  };

  const paste = async () => {
    let got: { clip: Clipboard; read: boolean };
    try {
      got = await readClipboard();
    } catch {
      // Refused outright: nothing is pasted, and the person is told why rather than left guessing at a dead row.
      say?.('Ghost.md couldn’t reach the clipboard here. Tap into the note and paste from your keyboard instead.');
      return;
    }
    const { clip, read } = got;
    if (clip.error) {
      say?.(clip.error);
      return;
    }
    if (clip.path && onPasteImage) {
      await onPasteImage(clip.path);
      return;
    }
    if (!clip.text) {
      // Nothing came back. Only a reader that answered can say the clipboard is empty; otherwise it went unread.
      // An activity that answered with nothing cannot tell an empty clipboard from a read it was refused, so the
      // words say only what is certain: nothing arrived, and here is the way round it.
      say?.(
        read
          ? 'Nothing on the clipboard to paste. Copy the words again, then hold here.'
          : 'Nothing came back from the clipboard. Copy it again, or tap into the note and paste from your keyboard.',
      );
      return;
    }
    view.dispatch({ changes: { from, to, insert: clip.text }, selection: { anchor: from + clip.text.length } });
  };

  const selectAll = () => {
    view.dispatch({ selection: { anchor: 0, head: view.state.doc.length } });
  };

  /** The line the caret is on, for the actions that are about a line rather than a selection. */
  const caretLine = view.state.doc.lineAt(view.state.selection.main.head);
  // What the item says, as a plugin sends it: no marker, no mark, and not the board's anchor (core/itemLinks.ts).
  const lineWords = itemWords(caretLine.text) ?? caretLine.text.trim();
  const boards = boardOffers(view);
  const board = boards.copy;

  /** A row that works on lines, run on a board: the whole fence is taken first (editor/boardActions.ts `selectBoard`). */
  const whole = (run: (target: EditorView) => void) => () => {
    if (boards.fence) selectBoard(view, boards.fence);
    run(view);
  };

  const listToBoard = () => {
    if (!boards.list) return;
    const made = makeListBoard(view, boards.list);
    if (!made) return;
    fireNativeHaptic('success');
    say?.(boardMadeWords(made, 'a board'));
  };

  const putOnBoard = () => {
    const column = joinBoard(view);
    if (column === null) return;
    fireNativeHaptic('success');
    say?.(`Added to ${column}.`);
  };

  return (
    <div
      ref={menu}
      className={styles.menu}
      role="menu"
      aria-label={styling ? 'Styles' : 'Note actions'}
      // A press on the menu must not take the editor's focus or its selection.
      onPointerDown={(event) => event.preventDefault()}
    >
      <MenuBand>
        {styling ? (
          <StyleItems view={view} onBack={() => setStyling(false)} onClose={close} />
        ) : (
          <>
            {selected ? (
              <>
                <button type="button" role="menuitem" className={styles.item} onClick={() => void act(cut)()}>
                  <MenuWord icon={Scissors} label="Cut" />
                </button>
                <button type="button" role="menuitem" className={styles.item} onClick={() => void act(copy)()}>
                  <MenuWord icon={Copy} label="Copy" />
                </button>
              </>
            ) : null}
            {pasteable ? (
              <button type="button" role="menuitem" className={styles.item} onClick={() => void act(paste)()}>
                <MenuWord icon={ClipboardPaste} label="Paste" />
              </button>
            ) : null}
            {/* A board is drawn as columns, so it cannot be dragged over: this takes the whole of it at once. */}
            {board ? (
              <button type="button" role="menuitem" className={styles.item} onClick={() => void act(() => writeClipboard(board))()}>
                <MenuWord icon={Copy} label="Copy board" />
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
                <MenuWord icon={TextSearch} label="Find" />
              </button>
            ) : null}
            <button type="button" role="menuitem" className={styles.item} onClick={() => void act(selectAll)()}>
              <MenuWord icon={TextSelect} label="Select all" />
            </button>
            <button type="button" role="menuitem" className={styles.item} onClick={() => void act(whole(duplicateSelection))()}>
              <MenuWord icon={CopyPlus} label="Duplicate" />
            </button>
            <button type="button" role="menuitem" className={styles.item} onClick={() => void act(whole(deleteSelection))()}>
              <MenuWord icon={Trash2} label="Delete" />
            </button>
            <button type="button" role="menuitem" className={styles.item} onClick={() => void act(whole((target) => moveLines(target, -1)))()}>
              <MenuWord icon={ArrowUpToLine} label="Move up" />
            </button>
            <button type="button" role="menuitem" className={styles.item} onClick={() => void act(whole((target) => moveLines(target, 1)))()}>
              <MenuWord icon={ArrowDownToLine} label="Move down" />
            </button>
            {boards.joinable ? (
              <button type="button" role="menuitem" className={styles.item} onClick={() => void act(putOnBoard)()}>
                <MenuWord icon={LayoutGrid} label="Add to board" />
              </button>
            ) : null}
            {boards.list ? (
              <button type="button" role="menuitem" className={styles.item} onClick={() => void act(listToBoard)()}>
                <MenuWord icon={SquareKanban} label="Board from list" />
              </button>
            ) : null}
            {send && lineWords ? (
              <button type="button" role="menuitem" className={styles.item} onClick={() => void act(() => send.run(lineWords))()}>
                <MenuWord icon={Link} label={send.label} />
              </button>
            ) : null}
            <button
              type="button"
              role="menuitem"
              className={styles.item}
              onClick={() => {
                fireNativeHaptic('selection');
                setStyling(true);
              }}
            >
              <MenuWord icon={Type} label="Style" />
            </button>
            {onAddImage ? (
              <button type="button" role="menuitem" className={styles.item} onClick={() => void act(onAddImage)()}>
                <MenuWord icon={ImagePlus} label="Add image" />
              </button>
            ) : null}
          </>
        )}
      </MenuBand>
      {!styling && selected && edits.length ? (
        <MenuBand data-edits="" aria-disabled={editsUnavailable ? true : undefined}>
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
        </MenuBand>
      ) : null}
    </div>
  );
}
