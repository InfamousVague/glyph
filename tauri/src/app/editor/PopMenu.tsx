import { Menu, MenuLabel, MenuSub, type Placement } from '@glacier/react';
import { useCallback, useEffect, useImperativeHandle, useLayoutEffect, useRef, useState, type MutableRefObject, type ReactNode, type Ref, type RefObject } from 'react';
import { createPortal } from 'react-dom';
import { useBack } from '../core/back.ts';
import styles from './PopMenu.module.css';

/**
 * The kit's menu, hung from something already on the page: a board card's more button (editor/boards/CardMenu.tsx), a
 * tab or a group chip (notes/TabMenus.tsx), the top bar's people icon (notes/NoteTabs.tsx); or from the point a mouse
 * right-clicked, for a note's menu (notes/NoteMenu.tsx). Beside editor/Sheet.tsx, the same kind of shared shell.
 *
 * The kit's `Menu` draws its panel at the body, z 200, flipped and clamped on the screen, so it covers the header and
 * the tabs wherever it hangs (Matt: "Allow the header to be overlapped by the popup menus use the glacierUI context
 * menus"). What this adds is what the app's own menus already had:
 *
 * - **The back gesture closes it** (core/back.ts), as it closes the + list and press and hold.
 * - **A press anywhere closes it, heard on the window's way down.** The kit listens for a press outside on the
 *   document on the way up, and a card keeps its press to itself for its drag (boards/drag.ts), as the lanes' line
 *   does (boards/divider.ts): with the kit's ear alone, the menu floated on over a card being dragged. A press on the
 *   anchor or in any panel of the menu (every panel, flyouts too, carries the kit's `data-menu-stack`, the id it hands
 *   the anchor as `aria-controls`) is the menu's own.
 * - **It goes with what it hangs from**: an anchor gone from the page, or scrolled wholly off the screen.
 * - **Rows a thumb's height under a finger**, in the + list's type (PopMenu.module.css; Matt: "typography and
 *   iconography heavy so they fit the theme on all context menus"), and a height inside the room it has: under the top
 *   bar for one that hangs from it (`reach="down"`), half the screen for one that hangs from the page
 *   (`reach="either"`), so whichever side the kit turns it to holds it whole, under the status bar.
 * - **On the opened Fold it keeps to its anchor's side of the crease**, as the + list does: its alignment is chosen as
 *   it opens, once, and its width capped at half the window.
 * - **Nested rows in place** (`PopSub`) unless a mouse has room for a flyout either side of the menu.
 *
 * **The owner hears one `onDismiss`, a microtask after the kit's close**, however many ways it closes at once. The kit
 * reports a close and only then focuses its trigger (Escape, a row): the trigger is `AnchorAt`'s handle on the anchor,
 * which lives only while this is mounted, so an owner that took it down at once would drop the focus to the body.
 */

export type Reach = 'down' | 'either';

interface PopMenuProps {
  /** What it hangs from: an element on the page, which the kit measures, and focuses again on Escape. */
  anchor?: RefObject<HTMLElement | null>;
  /**
   * Or a point in the window, where a right-click was: a mark of no size is put there, at the body, for the kit to
   * measure. A fresh PopMenu (a new `key`) for each point, since the kit places once as it opens.
   */
  at?: { x: number; y: number };
  placement?: Placement;
  /** `down` for a menu hanging from the top bar, `either` for one that may open above or below its anchor. */
  reach?: Reach;
  /** Every way it closes, once, a microtask later; the owner takes it down. */
  onDismiss: () => void;
  'aria-label': string;
  children: ReactNode;
}

/** The opened Fold, as the + list knows it (editor/AddList.tsx): a finger on a window 600px and wider. */
const OPENED_FOLD = '(pointer: coarse) and (min-width: 600px)';
/** A mouse, the one pointer a flyout is for. */
const MOUSE = '(hover: hover) and (pointer: fine)';
/** How near a panel comes to the window's edges, and to the crease: the kit's padding, and the + list's gap. */
const EDGE = 8;
const CREASE_GAP = 16;

const asks = (query: string) => typeof matchMedia !== 'undefined' && matchMedia(query).matches;
const rootRem = () => parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
/** The widest panel the kit draws: its own `min(22rem, 100vw - 2rem)`. */
const widestPanel = () => Math.min(22 * rootRem(), window.innerWidth - 2 * rootRem());

/**
 * The alignment that keeps the panel on its anchor's side of the opened Fold's crease, the window's middle, and whether
 * it is creased at all. An anchor in the left half keeps its alignment only if the widest panel would still end
 * CREASE_GAP before the crease, and otherwise hangs by its end, growing toward the outer edge; one in the right half
 * mirrors that. The kit places against the window alone, and its clamp then keeps the capped panel in its half.
 */
function offTheCrease(box: DOMRect | null, asked: Placement): { placement: Placement; creased: boolean } {
  if (!box || !asks(OPENED_FOLD)) return { placement: asked, creased: false };
  const [side = 'bottom', align = 'center'] = asked.split('-');
  if (side !== 'top' && side !== 'bottom') return { placement: asked, creased: true };
  const crease = window.innerWidth / 2;
  const widest = Math.min(widestPanel(), crease - EDGE - CREASE_GAP);
  const left = align === 'start' ? box.left : align === 'end' ? box.right - widest : box.left + box.width / 2 - widest / 2;
  if (box.left + box.width / 2 < crease) {
    return { placement: left + widest > crease - CREASE_GAP ? (`${side}-end` as Placement) : asked, creased: true };
  }
  return { placement: left < crease + CREASE_GAP ? (`${side}-start` as Placement) : asked, creased: true };
}

/** The kit's trigger, standing in for an element already on the page. Renders nothing. */
function AnchorAt({
  ref,
  at,
  stack,
  'aria-expanded': expanded,
  'aria-controls': controls,
}: {
  ref?: Ref<HTMLElement | null>;
  at: RefObject<HTMLElement | null>;
  /** Where the id the kit gives every panel of this menu (`data-menu-stack`) is kept for the press heard outside. */
  stack: MutableRefObject<string | undefined>;
  'aria-expanded'?: boolean;
  'aria-controls'?: string;
}) {
  // The kit measures this element, asks whether a press was inside it, reads its direction and focuses it on Escape:
  // a real element answers all four, where a rect alone throws on the first. Set before the kit's own layout effects,
  // which run after a child's.
  useImperativeHandle(ref, () => at.current as HTMLElement, [at]);
  // What the kit would have written on its trigger, written on the anchor while this is up, and undone after.
  useLayoutEffect(() => {
    stack.current = controls;
    const element = at.current;
    if (!element) return undefined;
    const had = { expanded: element.getAttribute('aria-expanded'), controls: element.getAttribute('aria-controls') };
    const put = (name: string, value: string | null | undefined) => (value == null ? element.removeAttribute(name) : element.setAttribute(name, value));
    if (expanded !== undefined) put('aria-expanded', String(expanded));
    put('aria-controls', controls);
    return () => {
      put('aria-expanded', had.expanded);
      put('aria-controls', had.controls);
    };
  }, [at, stack, expanded, controls]);
  return null;
}

export function PopMenu({ anchor: element, at: point, placement = 'bottom-start', reach = 'either', onDismiss, 'aria-label': label, children }: PopMenuProps) {
  // The mark at a point, drawn before the kit's trigger so its ref is set by the time the trigger hands it on.
  const mark = useRef<HTMLSpanElement>(null);
  const anchor = element ?? mark;
  const owner = useRef(onDismiss);
  owner.current = onDismiss;
  const stack = useRef<string | undefined>(undefined);
  // One onDismiss however many ways it closes at once, and a microtask later: the kit reports a close and only then
  // focuses its trigger, which must still be here when it does.
  const gone = useRef(false);
  const dismiss = useCallback(() => {
    if (gone.current) return;
    gone.current = true;
    queueMicrotask(() => owner.current());
  }, []);

  useBack(true, dismiss);

  // A press anywhere but the menu and its anchor, heard before anything under it can keep the press to itself.
  useEffect(() => {
    const away = (event: PointerEvent) => {
      const target = event.target instanceof Element ? event.target : null;
      if (target && anchor.current?.contains(target)) return;
      const id = stack.current;
      if (target && id && target.closest(`[data-menu-stack="${CSS.escape(id)}"]`)) return;
      dismiss();
    };
    window.addEventListener('pointerdown', away, true);
    return () => window.removeEventListener('pointerdown', away, true);
  }, [anchor, dismiss]);

  // Gone with what it hangs from: an anchor taken off the page, or scrolled wholly off the screen. Looked at a frame
  // after each scroll or resize, once the page has moved.
  useEffect(() => {
    let frame = 0;
    const look = () => {
      const at = anchor.current;
      if (!at?.isConnected) {
        dismiss();
        return;
      }
      const box = at.getBoundingClientRect();
      const viewport = window.visualViewport;
      const top = viewport ? viewport.offsetTop : 0;
      const bottom = viewport ? viewport.offsetTop + viewport.height : window.innerHeight;
      if (box.bottom < top || box.top > bottom || box.right < 0 || box.left > window.innerWidth) dismiss();
    };
    const soon = () => {
      window.cancelAnimationFrame(frame);
      frame = window.requestAnimationFrame(look);
    };
    window.addEventListener('scroll', soon, { capture: true, passive: true });
    window.addEventListener('resize', soon);
    window.visualViewport?.addEventListener('resize', soon);
    window.visualViewport?.addEventListener('scroll', soon);
    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener('scroll', soon, { capture: true });
      window.removeEventListener('resize', soon);
      window.visualViewport?.removeEventListener('resize', soon);
      window.visualViewport?.removeEventListener('scroll', soon);
    };
  }, [anchor, dismiss]);

  // On the opened Fold, the alignment that keeps it on its anchor's side of the crease, chosen once as it opens: in a
  // layout effect, since an anchor drawn beside this (TabMenus' span) has no box until the commit, and before the kit
  // mounts its panel, which it does an effect later. Never again: the kit places anew whenever `placement` changes.
  const [side, setSide] = useState<{ placement: Placement; creased: boolean }>({ placement, creased: false });
  useLayoutEffect(() => {
    setSide(offTheCrease(anchor.current?.getBoundingClientRect() ?? null, placement));
    // eslint-disable-next-line react-hooks/exhaustive-deps -- chosen as it opens, and never again (above)
  }, []);

  return (
    <>
      {point && typeof document !== 'undefined'
        ? createPortal(<span ref={mark} data-pop-point="" style={{ position: 'fixed', left: point.x, top: point.y, inlineSize: 0, blockSize: 0 }} />, document.body)
        : null}
      <Menu
        open
        onOpenChange={(open) => {
          if (!open) dismiss();
        }}
        trigger={<AnchorAt at={anchor} stack={stack} />}
        placement={side.placement}
        aria-label={label}
        className={[styles.pop, styles[reach], side.creased ? styles.creased : ''].filter(Boolean).join(' ')}
      >
        {children}
      </Menu>
    </>
  );
}

/**
 * Whether a flyout fits: a mouse, on a window that holds the menu and a widest flyout on either side of it, with the
 * kit's 2px offsets and 8px edges. The kit may clamp the menu anywhere along the window, and turns a flyout only to a
 * side where it fits whole, never clamping it, so a flyout is on the screen wherever the menu sits only then: 1076px at
 * the app's 100% interface size, 1340px at 125%. Worked out here because the interface size moves the root's font size
 * (core/preferences.ts), which a media query's `rem` does not follow.
 */
function flyoutFits(): boolean {
  return asks(MOUSE) && window.innerWidth >= 3 * widestPanel() + 2 * (2 + EDGE);
}

function useFlyoutFits(): boolean {
  const [fits, setFits] = useState(flyoutFits);
  useEffect(() => {
    const again = () => setFits(flyoutFits());
    const mouse = typeof matchMedia === 'undefined' ? null : matchMedia(MOUSE);
    window.addEventListener('resize', again);
    // A Fold opening, or a mouse joining a tablet, while a menu is open.
    mouse?.addEventListener?.('change', again);
    return () => {
      window.removeEventListener('resize', again);
      mouse?.removeEventListener?.('change', again);
    };
  }, []);
  return fits;
}

/**
 * Rows under a name, inside a PopMenu: the kit's flyout where one fits (above), and otherwise listed in place under a
 * label, in the same panel. A finger never gets a flyout, which keeps one off the Fold's crease and a phone's edge,
 * where the kit's ran off (map 2 measured one at left 397 on a 412 phone). A label is not tied to its rows, so each
 * row carries its whole name itself (`aria-label`).
 */
export function PopSub({ label, reach = 'either', children }: { label: string; reach?: Reach; children: ReactNode }) {
  const fits = useFlyoutFits();
  if (fits) {
    return (
      <MenuSub label={label} menuClassName={`${styles.pop} ${styles[reach]}`}>
        {children}
      </MenuSub>
    );
  }
  return (
    <>
      <MenuLabel>{label}</MenuLabel>
      {children}
    </>
  );
}
