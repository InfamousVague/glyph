import { useEffect, useRef } from 'react';
import type { EditorView } from '@codemirror/view';
import { fireNativeHaptic } from '../core/haptics.ts';
import { isDrawnBlock } from './drawnBlock.ts';

/**
 * How the note's own menu is asked for (editor/ContextMenu.tsx): a press and hold on a phone, a right click on a
 * desktop.
 *
 * Both fire `contextmenu`, and preventing it keeps the word the press selected, handles and all, and keeps Android's
 * own Cut / Copy / Read aloud bar away - measured on the emulator, and the reason this needs nothing native. The menu
 * opens a frame later, when the word the press selected has landed, over the caret.
 *
 * A long press where there is no word to hold - an empty line, or the space after a line's last word - selects
 * nothing, so the phone may fire no `contextmenu` and the caret may be somewhere else (Matt: "quite hard to open on
 * new text lines where there's nothing yet"). That press is timed here instead: held LONG_PRESS_MS within SLOP_PX of
 * where it began, the caret goes to the finger and the menu opens there. A press on a word is left to the phone,
 * which selects it and fires `contextmenu` as before; timing it too would race the phone's own selection.
 *
 * Neither opens over something the note draws in place of its words: a board or a diagram is not a line to format
 * (Matt: "Formatting menu shows up on board unexpectedly"), and a board's cards have a menu of their own.
 */

/** How long a finger holds on empty paper before the menu opens there: about the phone's own long press. */
const LONG_PRESS_MS = 480;
/** How far the finger may wander during that hold and still be holding. */
const SLOP_PX = 8;

/** Where the menu is asked for: the caret's place when the view has one for it, else the finger's; and the selection. */
export interface Held {
  x: number;
  y: number;
  from: number;
  to: number;
}

/** Calls `onHold` whenever the menu is asked for in `view`. */
export function usePressAndHold(view: EditorView | null, onHold: (held: Held) => void): void {
  const hold = useRef(onHold);
  hold.current = onHold;

  useEffect(() => {
    if (!view) return undefined;
    const dom = view.dom;
    const show = (x: number, y: number) => {
      const { from, to, head } = view.state.selection.main;
      const at = view.coordsAtPos(head);
      hold.current({ x: at ? (at.left + at.right) / 2 : x, y: at ? at.top : y, from, to });
    };
    const onContextMenu = (event: MouseEvent) => {
      event.preventDefault();
      if (isDrawnBlock(event.target)) return;
      // The word the press selected has landed by the next frame.
      window.requestAnimationFrame(() => show(event.clientX, event.clientY));
    };
    dom.addEventListener('contextmenu', onContextMenu);

    let press: { timer: number; x: number; y: number } | null = null;
    const cancel = () => {
      if (press) window.clearTimeout(press.timer);
      press = null;
    };
    const onPointerDown = (event: PointerEvent) => {
      if (event.pointerType === 'mouse' || !event.isPrimary) return;
      cancel();
      // A press on a drawn board or diagram belongs to it: it is picked up, or it opens the card's own menu.
      if (isDrawnBlock(event.target)) return;
      const { clientX: x, clientY: y } = event;
      press = {
        x,
        y,
        timer: window.setTimeout(() => {
          press = null;
          // An empty note has no text under the finger, and the precise reading is null there; the nearest place in
          // the note is what a press means anyway (Matt: "i cant seem to paste a note" - into an empty one).
          const pos = view.posAtCoords({ x, y }) ?? view.posAtCoords({ x, y }, false);
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
      if (press && Math.hypot(event.clientX - press.x, event.clientY - press.y) > SLOP_PX) cancel();
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
}
