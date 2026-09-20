import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, StickyNote, Trash2 } from '@glacier/icons';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import type { Note } from '../core/store.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { when } from '../notes/when.ts';
import { memoText } from './memo.ts';
import styles from './MemosScreen.module.css';

/**
 * The memos, on a wall (docs/MEMOS.md). Matt chose "a Memos screen: a wall of small cards": a field at the top to
 * write one, then every memo as a small card, newest first, tap to change it where it is.
 *
 * A memo is written here, not in the editor: it is a few words, and the editor is a page. The field keeps on Enter
 * (a new line is Shift+Enter) or on Keep, since a phone's keyboard has no Enter to speak of; a card tapped becomes
 * the same field over its own words, with Done and a bin. A memo is text as it was typed, drawn as it was typed:
 * what a memo says is short enough that its marks are its words.
 */

export interface MemosScreenProps {
  memos: Note[];
  onBack: () => void;
  /** A memo written in the field: made, and the wall reads again. */
  onAdd: (text: string) => Promise<void>;
  /** A memo changed on its card. */
  onChange: (memo: Note, text: string) => Promise<void>;
  /** A memo binned: the same undoable delete a note gets. */
  onRemove: (memo: Note) => void;
  /** Asked for from a +: the field is focused as the screen opens. A new number focuses it again. */
  compose?: number;
}

export function MemosScreen({ memos, onBack, onAdd, onChange, onRemove, compose = 0 }: MemosScreenProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
  const field = useRef<HTMLTextAreaElement>(null);
  const [draft, setDraft] = useState('');
  const [editing, setEditing] = useState<{ id: string; text: string } | null>(null);
  useWispEdge(scroller, 'memos', topBar, { foot: true });
  useBack(true, onBack);

  useEffect(() => {
    if (compose) field.current?.focus();
  }, [compose]);

  const keep = async () => {
    const text = draft.trim();
    if (!text) return;
    setDraft('');
    await onAdd(text);
    fireNativeHaptic('success');
    field.current?.focus();
  };

  const done = async () => {
    if (!editing) return;
    const memo = memos.find((m) => m.id === editing.id);
    const text = editing.text.trim();
    setEditing(null);
    if (!memo) return;
    if (!text) onRemove(memo);
    else if (text !== memoText(memo.body)) await onChange(memo, text);
  };

  /** Enter keeps; Shift+Enter is a new line, as in every chat field. */
  const onKey = (event: React.KeyboardEvent<HTMLTextAreaElement>, run: () => void) => {
    if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      run();
    }
  };

  return (
    <div className={styles.screen}>
      <header ref={topBar} className={`app-headerPane ${styles.topBar}`}>
        <button type="button" className={`app-word ${styles.back}`} onClick={onBack}>
          <ArrowLeft size={18} aria-hidden="true" /> Home
        </button>
        <h1 className={styles.heading}>
          <StickyNote size={16} aria-hidden="true" /> Memos
          {memos.length ? <span className={styles.count}>{memos.length}</span> : null}
        </h1>
      </header>
      <div ref={scroller} className={styles.scroll}>
        <div className={styles.page}>
          <div className={styles.composer}>
            <textarea
              ref={field}
              className={styles.field}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => onKey(e, () => void keep())}
              placeholder="A memo: a few words, kept."
              rows={2}
              aria-label="A new memo"
            />
            <button type="button" className={`app-pill ${styles.keep}`} onClick={() => void keep()} disabled={!draft.trim()}>
              Keep
            </button>
          </div>

          {memos.length ? (
            <ul className={styles.wall} aria-label="Your memos">
              {memos.map((memo, i) => {
                const mine = editing?.id === memo.id;
                return (
                  <li key={memo.id} className={styles.cardItem} style={{ '--i': Math.min(i, 8) } as React.CSSProperties}>
                    {mine ? (
                      <div className={`${styles.card} ${styles.cardEditing}`}>
                        <textarea
                          className={styles.field}
                          value={editing.text}
                          onChange={(e) => setEditing({ id: memo.id, text: e.target.value })}
                          onKeyDown={(e) => onKey(e, () => void done())}
                          rows={3}
                          aria-label="This memo"
                          autoFocus
                        />
                        <div className={styles.cardTools}>
                          <button type="button" className={`app-word ${styles.bin}`} onClick={() => onRemove(memo)} aria-label="Delete this memo">
                            <Trash2 size={16} aria-hidden="true" />
                          </button>
                          <button type="button" className={`app-pill ${styles.keep}`} onClick={() => void done()}>
                            Done
                          </button>
                        </div>
                      </div>
                    ) : (
                      <button type="button" className={styles.card} onClick={() => setEditing({ id: memo.id, text: memoText(memo.body) })}>
                        <span className={styles.cardText}>{memoText(memo.body)}</span>
                        <span className={styles.cardWhen}>{when(memo.updatedAt)}</span>
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
          ) : (
            <p className={styles.empty}>Nothing kept yet. A memo is a thought too small for a note.</p>
          )}
        </div>
      </div>
    </div>
  );
}
