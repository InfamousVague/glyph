import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { StrokeIcon } from '../art/Icons.tsx';
import styles from './ContextMenu.module.css';

/**
 * The pieces the press-and-hold menu is drawn from, its actions and its Style page alike (editor/ContextMenu.tsx,
 * editor/StyleItems.tsx): a band that scrolls sideways, a word under its drawn icon, and the row that presses it.
 *
 * Each word stands under its icon, in display weight, the same hand as a linked line's drawer (editor/MarkMenu.tsx).
 * Matt: "make the options typography and iconography heavy so they fit the theme on all context menus".
 */

/** A drawn icon a menu can size and weigh: the Glacier kit's, and the app's own (art/Icons.tsx `StrokeIcon`). */
export type MenuIcon = StrokeIcon;

/** An icon over its word. */
export function MenuWord({ icon: Icon, label }: { icon: MenuIcon; label: string }) {
  return (
    <>
      <Icon size={20} strokeWidth={2.1} />
      <span className={styles.word}>{label}</span>
    </>
  );
}

/**
 * One of the menu's rows: a word under its icon, pressed. `name` is its accessible name where the word alone would not
 * say what it does.
 */
export function MenuItem({ icon, label, onPress, name }: { icon: MenuIcon; label: string; onPress: () => void; name?: string }) {
  return (
    <button type="button" role="menuitem" className={styles.item} onClick={onPress} aria-label={name}>
      <MenuWord icon={icon} label={label} />
    </button>
  );
}

/**
 * One band of the menu. Five words do not always fit a phone held upright,
 * so the band scrolls sideways, and fades at whichever end has more: a word
 * cut off at the edge reads as broken, a word fading out reads as "and more".
 */
export function MenuBand({ children }: { children: ReactNode }) {
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
    <div ref={row} className={styles.row} data-more={more || undefined}>
      {children}
    </div>
  );
}
