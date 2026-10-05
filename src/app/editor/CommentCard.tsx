import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from 'react';
import { ArrowUp, CircleCheck, MessageSquare, RotateCcw, Trash2 } from '@glacier/icons';
import { ago, nameOf, type CardPeople } from './commentWords.ts';
import { SheetGroup, SheetRow } from '../plugins/kit.tsx';
import styles from './CommentCard.module.css';

export type { CardPeople } from './commentWords.ts';

/**
 * A comment thread drawn as a card (docs/SHARED.md, S8): who said what and when, in their colour, the replies under
 * it, a field to reply in, Resolve or Reopen, and Delete thread; a new comment's field; and the note's threads as a
 * list. The note's thread card is these inside the app's sheet (editor/CommentSheet.tsx), and the ```comments fence is
 * drawn as the list (editor/comments.ts).
 *
 * They take a thread as data and say what was pressed, and nothing here reads a note: a canvas's threads (S9, a
 * `comments` array in its JSON) are drawn by the same card, from the same shape.
 */

/** One comment, as the card draws it. */
export interface CardComment {
  by: string;
  /** ISO 8601. */
  at: string;
  words: string;
}

/** A thread, as the card draws it: core/comments/format.ts `Thread` is one, and so is a canvas's. */
export interface CardThread {
  id: string;
  head: CardComment;
  replies: readonly CardComment[];
  resolved: { by: string; at: string } | null;
}


/** A person's initial in their colour: the member rows' mark (notes/OrganizationScreen.tsx `.avatar`). */
function Initial({ by, people }: { by: string; people: CardPeople }) {
  const name = nameOf(by, people);
  return (
    <span className={styles.initial} data-hue={people.colour(by)} aria-hidden="true">
      {(name === 'You' && by !== 'me' ? by : name).slice(0, 1).toUpperCase()}
    </span>
  );
}

function OneComment({ comment, people, now, reply }: { comment: CardComment; people: CardPeople; now: number; reply?: boolean }) {
  return (
    <li className={styles.comment} data-reply={reply || undefined}>
      <Initial by={comment.by} people={people} />
      <div className={styles.body}>
        <p className={styles.byline}>
          <span className={styles.who}>{nameOf(comment.by, people)}</span>
          <time className={styles.when} dateTime={comment.at}>
            {ago(comment.at, now)}
          </time>
        </p>
        <p className={styles.words}>{comment.words}</p>
      </div>
    </li>
  );
}

/**
 * A field for words, a send at its end, quiet until there are words: the More sheet's Ask field's shape
 * (editor/NoteSettings.tsx), taking several lines. Enter sends; Shift+Enter is a new line, as in any chat.
 */
export function CommentField({ label, placeholder, send, onSend, autoFocus }: { label: string; placeholder: string; send: string; onSend: (words: string) => void; autoFocus?: boolean }) {
  const [words, setWords] = useState('');
  const field = useRef<HTMLTextAreaElement>(null);
  useEffect(() => {
    if (autoFocus) field.current?.focus();
  }, [autoFocus]);
  const submit = (event?: FormEvent) => {
    event?.preventDefault();
    if (!words.trim()) return;
    onSend(words.trim());
    setWords('');
  };
  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      submit();
    }
  };
  return (
    <form className={styles.field} onSubmit={submit} aria-label={label}>
      <textarea
        ref={field}
        className={styles.input}
        value={words}
        rows={Math.min(5, Math.max(1, words.split('\n').length))}
        onChange={(event) => setWords(event.target.value)}
        onKeyDown={onKeyDown}
        placeholder={placeholder}
        aria-label={label}
        enterKeyHint="send"
      />
      <button type="submit" className={styles.send} disabled={!words.trim()} aria-label={send}>
        <ArrowUp size={18} strokeWidth={2.2} aria-hidden="true" />
      </button>
    </form>
  );
}

const ResolveIcon = () => <CircleCheck size={18} strokeWidth={2.2} />;
const ReopenIcon = () => <RotateCcw size={18} strokeWidth={2.2} />;
const DeleteIcon = () => <Trash2 size={18} strokeWidth={2.2} />;

interface CommentThreadProps {
  thread: CardThread;
  people: CardPeople;
  /** The words the thread is about, as the note has them; null for one anchored after a line. */
  quote?: string | null;
  onReply: (words: string) => void;
  onResolve: () => void;
  onReopen: () => void;
  onDelete: () => void;
  now?: number;
}

/** How long Delete thread waits for its second press, as leaving an organization does. */
const ARMED_MS = 4000;

/** A thread's card: its comments, a reply field, Resolve or Reopen, and Delete thread, which asks a second press. */
export function CommentThread({ thread, people, quote = null, onReply, onResolve, onReopen, onDelete, now = Date.now() }: CommentThreadProps) {
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    if (!armed) return undefined;
    const timer = window.setTimeout(() => setArmed(false), ARMED_MS);
    return () => window.clearTimeout(timer);
  }, [armed]);
  return (
    <div className={styles.thread} data-resolved={thread.resolved ? '' : undefined}>
      {quote ? (
        <blockquote className={styles.quote} data-hue={people.colour(thread.head.by)}>
          {quote}
        </blockquote>
      ) : null}
      <ol className={styles.comments}>
        <OneComment comment={thread.head} people={people} now={now} />
        {thread.replies.map((reply, i) => (
          <OneComment key={`${reply.at}:${i}`} comment={reply} people={people} now={now} reply />
        ))}
      </ol>
      {thread.resolved ? (
        <p className={styles.resolved}>
          Resolved by {nameOf(thread.resolved.by, people)}, {ago(thread.resolved.at, now).toLowerCase()}.
        </p>
      ) : null}
      <CommentField label="Reply" placeholder={thread.resolved ? 'Reply, and it stays resolved' : 'Reply'} send="Send reply" onSend={onReply} />
      <SheetGroup>
        {thread.resolved ? <SheetRow icon={ReopenIcon} label="Reopen" hint="Its wash comes back on the words." onPress={onReopen} /> : <SheetRow icon={ResolveIcon} label="Resolve" hint="The thread stays, without its wash." onPress={onResolve} />}
        <SheetRow
          icon={DeleteIcon}
          label={armed ? 'Delete it? Press again' : 'Delete thread'}
          hint={armed ? 'Its comments and its mark in the note go.' : undefined}
          danger
          onPress={() => {
            if (!armed) {
              setArmed(true);
              return;
            }
            setArmed(false);
            onDelete();
          }}
        />
      </SheetGroup>
    </div>
  );
}

/** A new comment's card: the words it is about, and a field to write it in, focused. */
export function NewComment({ quote, onSave }: { quote: string | null; onSave: (words: string) => void }) {
  return (
    <div className={styles.thread}>
      {quote ? <blockquote className={styles.quote}>{quote}</blockquote> : null}
      <CommentField label="Comment" placeholder="Write a comment" send="Add comment" onSend={onSave} autoFocus />
    </div>
  );
}

/** The first line of some words, cut to `max` characters. */
function firstLine(words: string, max = 90): string {
  const line = words.split('\n')[0] ?? '';
  return line.length > max ? `${line.slice(0, max - 1).trimEnd()}…` : line;
}

interface CommentListProps {
  threads: readonly CardThread[];
  people: CardPeople;
  onOpen: (id: string) => void;
  now?: number;
}

/** The threads as a list, open ones first: who started each, its first words, its replies, and whether it is resolved. */
export function CommentList({ threads, people, onOpen, now = Date.now() }: CommentListProps) {
  const ordered = [...threads.filter((thread) => !thread.resolved), ...threads.filter((thread) => thread.resolved)];
  return (
    <ul className={styles.list}>
      {ordered.map((thread) => {
        const replies = thread.replies.length;
        return (
          <li key={thread.id}>
            <button type="button" className={styles.item} data-resolved={thread.resolved ? '' : undefined} onClick={() => onOpen(thread.id)}>
              <Initial by={thread.head.by} people={people} />
              <span className={styles.body}>
                <span className={styles.byline}>
                  <span className={styles.who}>{nameOf(thread.head.by, people)}</span>
                  <time className={styles.when} dateTime={thread.head.at}>
                    {ago(thread.head.at, now)}
                  </time>
                </span>
                <span className={styles.words}>{firstLine(thread.head.words)}</span>
                {replies || thread.resolved ? (
                  <span className={styles.meta}>
                    {replies ? (
                      <span className={styles.replies}>
                        <MessageSquare size={12} strokeWidth={2.2} aria-hidden="true" /> {replies === 1 ? '1 reply' : `${replies} replies`}
                      </span>
                    ) : null}
                    {thread.resolved ? <span>Resolved</span> : null}
                  </span>
                ) : null}
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}
