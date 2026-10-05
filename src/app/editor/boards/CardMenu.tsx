import { MenuItem } from '@glacier/react';
import { useMemo } from 'react';
import { PopMenu } from '../PopMenu.tsx';
import type { CardRow } from './cardMenu.ts';
import { ICONS, type IconName } from './icons.ts';

/**
 * A board card's menu as the kit draws it (Matt: "Allow the header to be overlapped by the popup menus use the
 * glacierUI context menus"): the kit's menu through editor/PopMenu.tsx, hung from the card's more button, in a React
 * root of its own over the page (editor/reactMount.ts). What it offers and when it closes are
 * editor/boards/cardMenu.ts's, which loads this module when a card's menu first opens and draws it.
 *
 * **The focus goes back to the more button, and what that rests on.** The kit's close reports the close and only then
 * focuses its trigger (on Escape, and after a row). The trigger is PopMenu's handle on the more button, which lives
 * only while this root is mounted. PopMenu hands the close to cardMenu.ts a microtask later, so the kit has focused
 * the button by the time `closeCardMenu()` runs, and mountReact takes the root down a microtask after that. Never take
 * this root down synchronously ahead of that (a `flushSync`, a bare `root.unmount()`): the focus would drop to the
 * body without a sound. Held by boards.test.ts's 'Escape gives the focus back to the more button' and PopMenu's own
 * Escape test, which takes its owner down with flushSync.
 */

export interface CardMenuProps {
  /** The card's more button, which the menu hangs from and gives the focus back to. */
  more: HTMLElement;
  rows: readonly CardRow[];
  onDismiss: () => void;
}

/** A row's icon: the board's own paths (editor/boards/icons.ts), so the menu's icons are the lane's. */
function RowIcon({ name }: { name: IconName }) {
  return (
    <svg
      className="app-drawnIcon"
      data-icon={name}
      viewBox="0 0 24 24"
      width="1em"
      height="1em"
      aria-hidden="true"
      fill="none"
      stroke="currentColor"
      strokeWidth={2.4}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {ICONS[name].map((d) => (
        <path key={d} d={d} />
      ))}
    </svg>
  );
}

export function CardMenu({ more, rows, onDismiss }: CardMenuProps) {
  const at = useMemo(() => ({ current: more }), [more]);
  return (
    <PopMenu anchor={at} placement="bottom-end" reach="either" aria-label="Card" onDismiss={onDismiss}>
      {rows.map((row, index) => (
        // Closed first, then done, as the lane's menu was: the kit hands the focus back to the more button as
        // it closes, and Go to the line must take it into the note after that, not before.
        <MenuItem key={`${index}:${row.label}`} icon={<RowIcon name={row.icon} />} onSelect={() => queueMicrotask(row.run)}>
          {row.label}
        </MenuItem>
      ))}
    </PopMenu>
  );
}
