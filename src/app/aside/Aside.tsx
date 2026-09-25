import { BookOpen, X } from '@glacier/icons';
import { numbered } from '../book/book.ts';
import { FloatingCard } from '../notes/FloatingCard.tsx';
import type { AsideContent } from './aside.ts';
import styles from './Aside.module.css';

/**
 * The right-hand aside (aside.ts says what it holds): a book's index while a book or one of its pages is on screen,
 * the open chapter marked and a tap opening another; or, with no book, a numbered chapter's run in order. With
 * neither it isn't drawn at all (App.tsx). Its shell follows the
 * sidebar's: a column on the split layout when the sidebar is docked, else the notes drawer's floating card, at the
 * right (`AsideCard`; Matt: "the new right hand sidebar doesn't match the floating left sidebar"). The tab row's
 * mirrored sidebar icon shows and hides it (notes/NoteTabs.tsx).
 */
export interface AsideProps {
  content: AsideContent;
  onOpen: (id: string) => void;
  onOpenTitle: (title: string) => void;
  /** In the floating card: the close in its head. */
  onClose?: () => void;
  /** In the floating card, which has no bar over it. */
  popup?: boolean;
}

export function Aside({ content, onOpen, onOpenTitle, onClose, popup }: AsideProps) {
  return (
    <div className={styles.aside} data-kind={content.kind} data-popup={popup || undefined}>
      {content.kind === 'book' ? (
        <>
          <div className={styles.head}>
            <button type="button" className={styles.headButton} onClick={() => onOpen(content.place.book.id)} aria-label={`Open the book ${content.place.title}`}>
              <BookOpen size={15} aria-hidden="true" />
              <span className={styles.headTitle}>{content.place.title}</span>
            </button>
            {onClose ? (
              <button type="button" className={styles.close} onClick={onClose} aria-label="Close">
                <X size={16} aria-hidden="true" />
              </button>
            ) : null}
          </div>
          {content.place.chapters.length === 0 ? (
            <p className={styles.empty}>No chapters yet.</p>
          ) : (
            <ol className={styles.list} aria-label="Chapters">
              {content.place.chapters.map((chapter, i) => {
                const current = content.place.at === i;
                return (
                  <li key={`${chapter.line}-${chapter.title}`} data-depth={chapter.depth}>
                    <button type="button" className={styles.row} aria-current={current ? 'page' : undefined} data-current={current || undefined} onClick={() => onOpenTitle(chapter.title)}>
                      <span className={styles.number} aria-hidden="true">
                        {numbered(content.place.chapters)[i]}
                      </span>
                      <span className={styles.title}>{chapter.title}</span>
                    </button>
                  </li>
                );
              })}
            </ol>
          )}
        </>
      ) : (
        <>
          <div className={styles.head}>
            {content.titleId ? (
              <button type="button" className={styles.headButton} onClick={() => onOpen(content.titleId!)} aria-label={`Open ${content.title}`}>
                <BookOpen size={15} aria-hidden="true" />
                <span className={styles.headTitle}>{content.title}</span>
              </button>
            ) : (
              <span className={styles.headButton}>
                <BookOpen size={15} aria-hidden="true" />
                <span className={styles.headTitle}>{content.title}</span>
              </span>
            )}
            {onClose ? (
              <button type="button" className={styles.close} onClick={onClose} aria-label="Close">
                <X size={16} aria-hidden="true" />
              </button>
            ) : null}
          </div>
          <ol className={styles.list} aria-label="Chapters">
            {content.chapters.map((chapter) => {
              const current = chapter.id === content.open;
              return (
                <li key={chapter.id}>
                  <button type="button" className={styles.row} aria-current={current ? 'page' : undefined} data-current={current || undefined} onClick={() => onOpen(chapter.id)}>
                    <span className={styles.number} aria-hidden="true">
                      {chapter.number}
                    </span>
                    <span className={styles.title}>{chapter.name}</span>
                  </button>
                </li>
              );
            })}
          </ol>
        </>
      )}
    </div>
  );
}

/**
 * The aside as the notes drawer's card (notes/FloatingCard.tsx), at the right: the same rounded, blurred card hung
 * from the icon that opened it, the page live beside it, closed by a tap outside, Escape, the phone's back gesture,
 * the X, or opening a page. The icon itself is left to close it, as the drawer leaves its own.
 */
export function AsideCard({ onClose, onOpen, onOpenTitle, ...rest }: AsideProps & { onClose: () => void }) {
  return (
    <FloatingCard side="end" label="Book index" toggle="[data-aside-toggle]" onClose={onClose}>
      <Aside
        {...rest}
        popup
        onClose={onClose}
        onOpen={(id) => {
          onClose();
          onOpen(id);
        }}
        onOpenTitle={(title) => {
          onClose();
          onOpenTitle(title);
        }}
      />
    </FloatingCard>
  );
}
