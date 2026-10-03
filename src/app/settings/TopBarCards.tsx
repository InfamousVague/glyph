import { Check } from '@glacier/icons';
import type { TopBar } from '../core/preferences.ts';
import { TOP_BAR_STYLES } from '../shell/topBar.ts';
import styles from './TopBarCards.module.css';

/**
 * The top bar's six ways as cards (shell/topBar.ts `TOP_BAR_STYLES`; docs/DESIGN.md §178), each a picture of the
 * bar laid out that way over a few lines of a note, drawn in the page's own ink: rings as rings, tabs as tabs or
 * capsules, the Masthead's words as short bars, the Islands' capsules floating, Thumb's strip at the foot. The same
 * radio cards as the themes (ThemeCards.tsx) and the interface size (ScaleCards.tsx): the chosen one ringed and
 * ticked, the arrow keys moving between them.
 */

/** The bar laid out one way, small. */
function Scene({ style }: { style: TopBar }) {
  const rings = (n: number) => Array.from({ length: n }, (_, i) => <span key={i} className={styles.ring} />);
  const lines = (
    <span className={styles.lines}>
      <span className={styles.heading} />
      <span className={styles.line} />
      <span className={styles.line} data-short="true" />
    </span>
  );
  const tabs = (shape: 'tab' | 'capsule' | 'index') => (
    <span className={styles.tabs} data-shape={shape}>
      <span className={styles.tab} data-active="true" />
      <span className={styles.tab} />
      <span className={styles.tab} />
    </span>
  );
  switch (style) {
    case 'ledger':
      return (
        <span className={styles.scene}>
          <span className={styles.row} data-row="tabs">
            <span className={styles.tab} data-house="true" />
            {tabs('tab')}
          </span>
          <span className={styles.row} data-row="paper">
            {rings(3)}
            <span className={styles.gap} />
            {rings(3)}
          </span>
          {lines}
        </span>
      );
    case 'strip':
      return (
        <span className={styles.scene}>
          <span className={styles.row}>
            {rings(2)}
            {tabs('capsule')}
            {rings(2)}
          </span>
          {lines}
        </span>
      );
    case 'masthead':
      return (
        <span className={styles.scene}>
          <span className={styles.row}>
            <span className={styles.word} />
            <span className={styles.word} data-short="true" />
            <span className={styles.gap} />
            {rings(2)}
          </span>
          <span className={styles.row} data-row="rule">
            {tabs('index')}
          </span>
          {lines}
        </span>
      );
    case 'islands':
      return (
        <span className={styles.scene} data-islands="true">
          <span className={styles.row}>
            <span className={styles.capsule}>{rings(3)}</span>
            <span className={styles.gap} />
            <span className={styles.capsule}>{rings(2)}</span>
          </span>
          <span className={styles.row}>
            <span className={styles.capsule} data-wide="true">
              {tabs('capsule')}
            </span>
          </span>
          {lines}
        </span>
      );
    case 'thumb':
      return (
        <span className={styles.scene}>
          <span className={styles.row}>
            {rings(2)}
            <span className={styles.title} />
            {rings(2)}
          </span>
          {lines}
          <span className={styles.foot}>{tabs('capsule')}</span>
        </span>
      );
    default:
      return (
        <span className={styles.scene}>
          <span className={styles.row}>
            {rings(4)}
            <span className={styles.gap} />
            {rings(3)}
          </span>
          <span className={styles.row} data-row="tabs">
            {tabs('tab')}
          </span>
          {lines}
        </span>
      );
  }
}

interface TopBarCardsProps {
  value: TopBar;
  onValueChange: (value: TopBar) => void;
}

export function TopBarCards({ value, onValueChange }: TopBarCardsProps) {
  return (
    <div className={styles.grid} role="radiogroup" aria-label="Top bar">
      {TOP_BAR_STYLES.map((option) => {
        const selected = option.id === value;
        return (
          <label key={option.id} className={styles.option} data-selected={selected || undefined}>
            <input className={styles.input} type="radio" name="top-bar" value={option.id} aria-label={option.label} checked={selected} onChange={() => onValueChange(option.id)} />
            <span className={styles.preview} aria-hidden="true">
              <Scene style={option.id} />
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
