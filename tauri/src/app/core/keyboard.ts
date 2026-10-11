/**
 * Whether the phone's keyboard is up, as far as the page can tell (docs/DESIGN.md §144): what lets a new note's names
 * and templates wait under its first line until the page is being written in, so the tap that raises the keyboard
 * never lands on one of them (editor/nameChips.ts).
 *
 * There is no event for it. On Android from native generation 15 the activity shortens the WebView by the keyboard's
 * height (MainActivity.kt `fitAboveKeyboard`), and some WebViews shrink only the visual viewport, so either way the
 * page sees its viewport grow shorter. So the keyboard is up when the visual viewport is at least 150px shorter than
 * the tallest it has been at this width in this run. Kept by width, because the Fold's two screens differ and opening
 * it is not a keyboard.
 *
 * It fails safe, never early. A launch with the keyboard already up reads as down until it has gone once, a floating
 * keyboard shortens nothing, and a hardware keyboard raises none: in each the names wait for the person's own tap or
 * key instead. Page only; nothing native is asked.
 */

/** How much shorter than its tallest the viewport must be for the keyboard to be up: more than a toolbar, less than any keyboard. */
export const KEYBOARD_PX = 150;

/** The tallest the viewport has been at each width this run. */
const tallest = new Map<number, number>();
const listeners = new Set<(up: boolean) => void>();
let up = false;
let listening = false;

/** The viewport's width and height, as the page is laid out at: the visual viewport where there is one, unzoomed. */
function viewport(): { width: number; height: number } {
  const visual = window.visualViewport;
  const scale = visual?.scale ?? 1;
  return { width: Math.round(window.innerWidth), height: visual ? visual.height * scale : window.innerHeight };
}

function measure(): void {
  const { width, height } = viewport();
  const most = Math.max(tallest.get(width) ?? 0, height);
  tallest.set(width, most);
  const now = most - height >= KEYBOARD_PX;
  if (now === up) return;
  up = now;
  for (const listener of listeners) listener(up);
}

function listen(): void {
  if (listening || typeof window === 'undefined') return;
  listening = true;
  measure();
  window.addEventListener('resize', measure);
  window.visualViewport?.addEventListener('resize', measure);
}

/** Whether the keyboard is up now. */
export function keyboardUp(): boolean {
  listen();
  measure();
  return up;
}

/** Told each time the keyboard comes up or goes down; answers the way to stop. */
export function watchKeyboard(listener: (up: boolean) => void): () => void {
  listen();
  listeners.add(listener);
  return () => void listeners.delete(listener);
}

// From the page's first moment, so the tallest is taken while the keyboard is still down.
listen();
