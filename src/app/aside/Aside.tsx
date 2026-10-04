import { useState } from 'react';
import { BookOpen, X } from '@glacier/icons';
import { readStoredText, writeStoredText } from '../core/stored.ts';
import { numbered } from '../book/book.ts';
import { FloatingCard } from '../notes/FloatingCard.tsx';
import type { AsideContent } from './aside.ts';
import { AsideHistory } from './AsideHistory.tsx';
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
      <AsideIndex content={content} onOpen={onOpen} onOpenTitle={onOpenTitle} onClose={onClose} />
    </div>
  );
}

/** What a book's index or a run of chapters puts in the aside, without the column it sits in. */
function AsideIndex({ content, onOpen, onOpenTitle, onClose }: Omit<AsideProps, 'popup'>) {
  return (
    <>
      {content.kind === 'book' && content.place.journal ? (
        <>
          <div className={styles.head}>
            <button type="button" className={styles.headButton} onClick={() => onOpen(content.place.book.id)} aria-label={`Open the journal ${content.place.title}`}>
              <BookOpen size={15} aria-hidden="true" />
              <span className={styles.headTitle}>{content.place.title}</span>
            </button>
            {onClose ? (
              <button type="button" className={styles.close} onClick={onClose} aria-label="Close">
                <X size={16} aria-hidden="true" />
              </button>
            ) : null}
          </div>
          {/* One month of a journal's entries, newest first: the open entry's, or the newest (aside.ts). */}
          {!content.month ? (
            <p className={styles.empty}>No entries yet.</p>
          ) : (
            <>
              <p className={styles.month}>{content.month.label}</p>
              <ol className={styles.list} aria-label="Entries">
                {content.month.entries.map((entry) => {
                  const current = entry.id === content.open;
                  return (
                    <li key={entry.id}>
                      <button type="button" className={styles.row} aria-label={entry.label} aria-current={current ? 'page' : undefined} data-current={current || undefined} onClick={() => onOpen(entry.id)}>
                        <span className={styles.number} aria-hidden="true">
                          {entry.day}
                        </span>
                        <span className={styles.entryWords}>
                          {entry.time}
                          {entry.first ? ` ${entry.first}` : ''}
                        </span>
                      </button>
                    </li>
                  );
                })}
              </ol>
            </>
          )}
        </>
      ) : content.kind === 'book' ? (
        <>
          <div className={styles.head}>
            <button type="button" className={styles.headButton} onClick={() => onOpen(content.place.book.id)} aria-label={`Open the notebook ${content.place.title}`}>
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
            <p className={styles.empty}>No pages yet.</p>
          ) : (
            <ol className={styles.list} aria-label="Pages">
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
    </>
  );
}

/** Which of the aside's two the person last looked at, kept to this device: the index, or the version history. */
type AsideTab = 'index' | 'history';
const TAB_KEY = 'glyph-aside-tab';

export interface AsidePanelProps extends Omit<AsideProps, 'content'> {
  /** The open note's book or run of chapters, or null where it has neither (aside.ts). */
  content: AsideContent | null;
  /** The open note, for its version history: on a desktop, where the aside has room for it. Null elsewhere. */
  history: { noteId: string; title: string } | null;
}

/**
 * The aside with all it can hold (Matt: "make a sidebar that can be expanded on desktop to see the version history"):
 * a book's index or a run of chapters, and the open note's version history (AsideHistory.tsx). With both there are two
 * tabs, the last one chosen kept; with one, that one alone. App.tsx draws none of it when there is neither.
 */
export function AsidePanel({ content, history, onOpen, onOpenTitle, onClose, popup }: AsidePanelProps) {
  const [tab, setTab] = useState<AsideTab>(() => (readStoredText(TAB_KEY) === 'history' ? 'history' : 'index'));
  const choose = (next: AsideTab) => {
    setTab(next);
    writeStoredText(TAB_KEY, next);
  };
  const showing: AsideTab = content && history ? tab : content ? 'index' : 'history';
  return (
    <div className={styles.aside} data-kind={showing === 'history' ? 'history' : content?.kind} data-popup={popup || undefined}>
      {content && history ? (
        <div className={styles.tabs} role="tablist" aria-label="What the side panel shows">
          {(
            [
              ['index', content.kind === 'chapters' ? 'Chapters' : content.place.journal ? 'Entries' : 'Index'],
              ['history', 'History'],
            ] as const
          ).map(([id, label]) => (
            <button key={id} type="button" role="tab" className={styles.tab} aria-selected={showing === id} data-on={showing === id || undefined} onClick={() => choose(id)}>
              {label}
            </button>
          ))}
        </div>
      ) : null}
      {showing === 'index' && content ? (
        <AsideIndex content={content} onOpen={onOpen} onOpenTitle={onOpenTitle} onClose={onClose} />
      ) : history ? (
        <AsideHistory noteId={history.noteId} title={history.title} onClose={onClose} />
      ) : null}
    </div>
  );
}

/**
 * The aside as the notes drawer's card (notes/FloatingCard.tsx), at the right: the same rounded, blurred card hung
 * from the icon that opened it, the page live beside it, closed by a tap outside, Escape, the phone's back gesture,
 * the X, or opening a page. The icon itself is left to close it, as the drawer leaves its own.
 */
export function AsideCard({ onClose, onOpen, onOpenTitle, ...rest }: AsidePanelProps & { onClose: () => void }) {
  return (
    <FloatingCard side="end" label="Side panel" toggle="[data-aside-toggle]" onClose={onClose}>
      <AsidePanel
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
