import { useEffect, useRef, useState, type ComponentType, type HTMLAttributes } from 'react';
import styles from './ContextMenu.module.css';

/**
 * The pieces the press-and-hold menu is drawn from, its actions and its Style page alike (editor/ContextMenu.tsx,
 * editor/StyleMenu.tsx): a band that scrolls sideways, and a word under its drawn icon.
 *
 * Each word stands under its icon, in display weight, the same hand as a linked line's drawer (editor/MarkMenu.tsx).
 * Matt: "make the options typography and iconography heavy so they fit the theme on all context menus".
 */

/** A drawn icon a menu can size and weigh: the Glacier kit's, and the app's own (art/Icons.tsx). */
export type MenuIcon = ComponentType<{ size?: number; strokeWidth?: number }>;

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
 * One band of the menu. Five words do not always fit a phone held upright,
 * so the band scrolls sideways, and fades at whichever end has more: a word
 * cut off at the edge reads as broken, a word fading out reads as "and more".
 */
export function MenuBand({ children, ...rest }: HTMLAttributes<HTMLDivElement>) {
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
