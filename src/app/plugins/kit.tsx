import type { ComponentType, InputHTMLAttributes, ReactNode } from 'react';
import styles from '../editor/NoteSettings.module.css';

/**
 * The pieces a plugin's page on a note's cog sheet is built from, in the
 * sheet's own look: a title, a sentence, a heading, a card of rows, a text
 * field. A plugin page uses these rather than the sheet's class names, so
 * the sheet can change its look without every plugin changing with it.
 */

export function SheetTitle({ children }: { children: ReactNode }) {
  return <p className={styles.title}>{children}</p>;
}

export function SheetNote({ children }: { children: ReactNode }) {
  return <p className={styles.note}>{children}</p>;
}

export function SheetHeading({ children }: { children: ReactNode }) {
  return <p className={styles.heading}>{children}</p>;
}

export function SheetGroup({ children }: { children: ReactNode }) {
  return <div className={styles.group}>{children}</div>;
}

/** The sheet's icon slot, for a plugin's mark. */
export function SheetIcon({ icon: Icon }: { icon: ComponentType }) {
  return (
    <span className={styles.icon} aria-hidden="true">
      <Icon />
    </span>
  );
}

interface SheetRowProps {
  icon?: ComponentType;
  label: ReactNode;
  hint?: ReactNode;
  /** Without it the row is a line of text, not a button. */
  onPress?: () => void;
  disabled?: boolean;
  /** A choice among several: pressed, with a tick. */
  chosen?: boolean;
  danger?: boolean;
}

export function SheetRow({ icon, label, hint, onPress, disabled, chosen, danger }: SheetRowProps) {
  const inner = (
    <>
      {icon ? <SheetIcon icon={icon} /> : null}
      <span className={styles.label}>
        {label}
        {hint ? <span className={styles.hint}>{hint}</span> : null}
      </span>
      {chosen ? <span className={styles.tick} aria-hidden="true" /> : null}
    </>
  );
  if (!onPress) {
    return (
      <div className={styles.row} aria-disabled="true">
        {inner}
      </div>
    );
  }
  return (
    <button
      type="button"
      className={`${styles.row}${danger ? ` ${styles.danger}` : ''}`}
      onClick={onPress}
      disabled={disabled}
      aria-pressed={chosen === undefined ? undefined : chosen}
    >
      {inner}
    </button>
  );
}

export function SheetField({ label, ...input }: { label: string } & InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className={styles.field}>
      <span className={styles.fieldLabel}>{label}</span>
      <input className={styles.input} {...input} />
    </label>
  );
}

/** A stroke mark in the sheet's icon style: one path on a 24 grid, `size` pixels or the text's size. */
export function StrokeMark({ d, size }: { d: string; size?: number }) {
  const box = size ? `${size}px` : '1em';
  return (
    <svg viewBox="0 0 24 24" style={{ inlineSize: box, blockSize: box }} aria-hidden="true">
      <path d={d} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
