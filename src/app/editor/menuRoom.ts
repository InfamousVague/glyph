/**
 * The room a menu has on the screen (Matt: "Allow the header to be overlapped by the popup menus"): from under the
 * phone's status bar (`--app-inset-top`, app.css) down to what the keyboard leaves, the visual viewport's foot,
 * MENU_EDGE in from each side. The header and the tabs are inside it: a menu may cover them, and never the status bar
 * or the keyboard. On the Mac the inset is nothing since the three buttons moved into the bar's own row, so the room
 * starts at the window's top there.
 *
 * For the two menus that place themselves while the keyboard is up: the + list (editor/AddList.tsx) and press and
 * hold (editor/ContextMenu.tsx). The kit's menus put the keyboard away and place against the window
 * (editor/PopMenu.tsx).
 */

/** How near a menu comes to the room's edges. */
export const MENU_EDGE = 8;

/**
 * The status bar's height in px. `--app-inset-top` is `env(safe-area-inset-top, 0px)` or a px length, and both engines
 * hand a custom property back with its `env()` already put in: "32px", never the `env(...)` text (measured in Chromium
 * and WebKit). Not `--app-safe-top`, which comes back as `calc(32px + 48px)` and parses to nothing.
 */
export function statusBar(): number {
  if (typeof getComputedStyle === 'undefined') return 0;
  return parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--app-inset-top')) || 0;
}

/** The room, in the window's coordinates: under the status bar, over the keyboard, MENU_EDGE in from each side. */
export function menuRoom(): { top: number; bottom: number; left: number; right: number } {
  const viewport = window.visualViewport;
  const viewTop = viewport ? viewport.offsetTop : 0;
  const viewBottom = viewport ? viewport.offsetTop + viewport.height : window.innerHeight;
  return {
    top: Math.max(viewTop, statusBar()) + MENU_EDGE,
    bottom: viewBottom - MENU_EDGE,
    left: MENU_EDGE,
    right: window.innerWidth - MENU_EDGE,
  };
}
