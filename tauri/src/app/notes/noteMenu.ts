import type { MouseEvent as ReactMouseEvent } from 'react';
import { externalStore } from '../core/externalStore.ts';

/**
 * A note's menu, opened by a right-click on its card, row or line (notes/NoteMenu.tsx draws it; docs/DESIGN.md §172;
 * Matt: "add context menus so i can right click on desktop to delete a note"). One menu for the whole app, mounted once
 * by App.tsx, and a note's place in any list only says which note and where the pointer was.
 *
 * A mouse's right-click only. On a phone the same event is a press and hold, which every list already uses - a card's
 * swipe, a tab's drag - so a touch's is left to them; where a WebView does not say what made the event, the menu opens
 * only on a screen with a fine pointer that can hover.
 */

export interface NoteMenuAt {
  id: string;
  /** Where the pointer was, the menu's corner. */
  x: number;
  y: number;
}

const open = externalStore<NoteMenuAt | null>(null);

export const useNoteMenu = open.use;
export const noteMenuNow = open.get;

export function openNoteMenu(id: string, x: number, y: number): void {
  open.set({ id, x, y });
}

export function closeNoteMenu(): void {
  open.set(null);
}

/** Whether a contextmenu event came from a mouse: said by the event where it says, else by the screen. */
export function byMouse(event: Pick<MouseEvent, 'type'> & { pointerType?: string }): boolean {
  if (event.pointerType) return event.pointerType === 'mouse';
  return typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia('(hover: hover) and (pointer: fine)').matches;
}

/** The right-click a note's card, row or line answers: the note's menu at the pointer, a mouse's only. */
export function onNoteContextMenu(id: string) {
  return (event: ReactMouseEvent) => {
    if (!byMouse(event.nativeEvent as MouseEvent & { pointerType?: string })) return;
    event.preventDefault();
    event.stopPropagation();
    openNoteMenu(id, event.clientX, event.clientY);
  };
}
