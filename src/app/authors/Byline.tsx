import { isKnownAi } from '../core/authors.ts';
import styles from './Byline.module.css';

/**
 * Who wrote a note, a book, or a shared page (core/authors.ts): each author's mark, then their names, "By matt and
 * Claude". A person is their initial in a ring. An AI the app knows draws its sign - a spark, the same for every AI,
 * so the byline reads "a person and an AI" at a glance - and one it doesn't know, its initial. Nothing is drawn for a
 * note with no authors, which is the person's own.
 */
export function Byline({ authors, className }: { authors: readonly string[]; className?: string }) {
  if (!authors.length) return null;
  return (
    <p className={`${styles.byline} ${className ?? ''}`} aria-label={`Written by ${spoken(authors)}`}>
      <span className={styles.marks} aria-hidden="true">
        {authors.slice(0, 4).map((name) => (
          <AuthorMark key={name} name={name} />
        ))}
      </span>
      <span className={styles.names}>By {spoken(authors)}</span>
    </p>
  );
}

/** One author's mark: an AI's spark, or a person's initial, in a ring. */
export function AuthorMark({ name }: { name: string }) {
  const ai = isKnownAi(name);
  return (
    <span className={styles.mark} data-ai={ai || undefined} title={name}>
      {ai ? <Spark /> : <span className={styles.initial}>{[...name.trim()][0]?.toUpperCase() ?? '?'}</span>}
    </span>
  );
}

/** A spark of eight tapering rays: the sign an AI author wears. */
function Spark() {
  const rays = Array.from({ length: 8 }, (_, i) => i * 45);
  return (
    <svg viewBox="0 0 24 24" width="12" height="12" aria-hidden="true">
      {rays.map((deg) => (
        <path key={deg} d="M12 12 L11.1 3.6 Q12 2.2 12.9 3.6 Z" transform={`rotate(${deg} 12 12)`} fill="currentColor" />
      ))}
      <circle cx="12" cy="12" r="1.6" fill="currentColor" />
    </svg>
  );
}

/** Names as a sentence says them: "a", "a and b", "a, b and c". */
function spoken(names: readonly string[]): string {
  if (names.length <= 1) return names[0] ?? '';
  return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}
