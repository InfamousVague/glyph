import { Check } from '@glacier/icons';
import type { HomeLayout } from '../core/preferences.ts';
import { HOME_LAYOUTS } from '../home/homeLayout.ts';
import styles from './LayoutCards.module.css';

/**
 * The home page's four layouts as cards (home/homeLayout.ts `HOME_LAYOUTS`; Matt: "show them in cards representing
 * the actual layout", docs/DESIGN.md §178): each a picture of the page laid out that way - the search at the top,
 * then Spotlight's pinned line, four cards and rows; Cards' grid; the Timeline's dated groups of rows; the List's
 * lines - in the page's own ink. The same radio cards as the themes (ThemeCards.tsx): the chosen one ringed and
 * ticked, the arrow keys moving between them.
 */

/** The page laid out one way, small. */
function Scene({ layout }: { layout: HomeLayout }) {
  const search = <span className={styles.search} />;
  const cards = (n: number) => (
    <span className={styles.cards}>
      {Array.from({ length: n }, (_, i) => (
        <span key={i} className={styles.card}>
          <span className={styles.cardTitle} />
          <span className={styles.cardLine} />
        </span>
      ))}
    </span>
  );
  const rows = (n: number, thin = false) => (
    <span className={styles.rows} data-thin={thin || undefined}>
      {Array.from({ length: n }, (_, i) => (
        <span key={i} className={styles.row} />
      ))}
    </span>
  );
  const head = <span className={styles.head} />;
  switch (layout) {
    case 'cards':
      return (
        <span className={styles.scene}>
          {search}
          {head}
          {cards(6)}
        </span>
      );
    case 'timeline':
      return (
        <span className={styles.scene}>
          {search}
          {head}
          {rows(2)}
          {head}
          {rows(3)}
        </span>
      );
    case 'list':
      return (
        <span className={styles.scene}>
          {search}
          {head}
          {rows(7, true)}
        </span>
      );
    default:
      return (
        <span className={styles.scene}>
          {search}
          <span className={styles.pinned} />
          {cards(2)}
          {head}
          {rows(2)}
        </span>
      );
  }
}

interface LayoutCardsProps {
  value: HomeLayout;
  onValueChange: (value: HomeLayout) => void;
}

export function LayoutCards({ value, onValueChange }: LayoutCardsProps) {
  return (
    <div className={styles.grid} role="radiogroup" aria-label="Home page layout">
      {HOME_LAYOUTS.map((option) => {
        const selected = option.id === value;
        return (
          <label key={option.id} className={styles.option} data-selected={selected || undefined}>
            <input className={styles.input} type="radio" name="home-layout" value={option.id} aria-label={option.label} checked={selected} onChange={() => onValueChange(option.id)} />
            <span className={styles.preview} aria-hidden="true">
              <Scene layout={option.id} />
            </span>
            <span className={styles.meta}>
              <span className={styles.copy}>
                <span className={styles.label}>{option.label}</span>
                <span className={styles.description}>{option.hint}</span>
              </span>
              <span className={styles.indicator} aria-hidden="true">
                <Check size={12} strokeWidth={2.5} />
              </span>
            </span>
          </label>
        );
      })}
    </div>
  );
}
