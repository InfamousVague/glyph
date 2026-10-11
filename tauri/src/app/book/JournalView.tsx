import { useMemo, useState } from 'react';
import { useBack } from '../core/back.ts';
import { ChevronRight, Plus, X } from '@glacier/icons';
import { noteTitle } from '../core/noteTitle.ts';
import { isDarkNow, usePreferences } from '../core/preferences.ts';
import type { Note } from '../core/store.ts';
import { bookWords, withoutChapter } from './book.ts';
import { BookWords } from './BookView.tsx';
import { templateOf, templateSentence } from './journal.ts';
import { entryStarts, startLine } from './entryStarts.ts';
import { monthsOf, pagesOf } from './journalMonths.ts';
import styles from './JournalView.module.css';

/**
 * A journal, drawn where its words would be (editor/NoteScreen.tsx; docs/DESIGN.md §142): one action, New entry, then
 * the journal's own words, then its entries by the month each was written in, newest first. A notebook's index is
 * its order (book/BookView.tsx); a journal's is time's, so there are no grips, no moves and no Add a page here, and
 * the Markdown behind the view switch keeps the lines in the order they were made.
 *
 * The three newest months are open, and each older one is a row that opens it in place: a year is about ninety rows
 * and nine month rows, not three hundred and sixty-five. A row is what a person scans for - the day, the time, where
 * it was written, and how it starts, faded at the edge rather than cut with an ellipsis - and opens the entry in the
 * journal's tab. A page planned before a notebook was kept as a journal is listed at the end under Not written yet,
 * with the index's cross to take it out; an entry's line with no note is not drawn (book/journalMonths.ts).
 *
 * Speak an entry is in the note's More sheet on a journal (editor/NoteSettings.tsx), so the view has one button.
 *
 * New entry asks what the entry starts with (Matt: "I would like to see [the templates] when clicking new page on a
 * journal while the journal is open"): the journal's own template first, marked as its usual, then the other presets
 * and an empty page, each with a line of how it starts, filled for this minute. A tap makes the entry from that one;
 * the journal's usual template is changed only on its More sheet (book/TemplatePicker.tsx).
 */

interface JournalViewProps {
  body: string;
  /** The note by that title, for an entry's date, place and words: undefined where there is none. */
  noteOf: (title: string) => Note | undefined;
  /** Whether a note by that title exists, for a link in the journal's own words. */
  known: (title: string) => boolean;
  /** Opens the note by that title in this tab (App.tsx `openTitleWithin`). */
  open: (title: string) => void;
  onChange: (body: string) => void;
  /** New entry (App.tsx `newEntry`), from the template chosen for it; absent, no button. */
  onNewEntry?: (template: string) => void;
  dark?: boolean;
}

/** Months drawn open before the older ones fold to a row each. */
const OPEN_MONTHS = 3;

export function JournalView({ body, noteOf, known, open, onChange, onNewEntry, dark: darkGiven }: JournalViewProps) {
  const themeDark = isDarkNow(usePreferences().theme);
  const dark = darkGiven ?? themeDark;
  const words = useMemo(() => bookWords(body), [body]);
  const template = useMemo(() => templateOf(body), [body]);
  const name = useMemo(() => noteTitle(body), [body]);
  // Read every render, and the months worked out again only when a page's note changed: `noteOf` is new each time App
  // draws, and a year of entries is a year of rows to sort.
  const pages = pagesOf(body, noteOf);
  const changed = pages.map((page) => (page.note ? `${page.note.id}:${page.note.updatedAt}` : '')).join('|');
  // eslint-disable-next-line react-hooks/exhaustive-deps -- `changed` says when the pages' notes did
  const { months, unwritten } = useMemo(() => monthsOf(pages, template, name), [body, template, name, changed]);
  /** The older months opened by a tap. */
  const [unfolded, setUnfolded] = useState<ReadonlySet<string>>(() => new Set());
  /** New entry pressed: the templates to start it from are showing. */
  const [choosing, setChoosing] = useState(false);

  return (
    <div className={styles.journal} data-entries={months.reduce((sum, month) => sum + month.entries.length, 0)}>
      {onNewEntry ? (
        <div className={styles.adds}>
          <button type="button" className={styles.action} aria-expanded={choosing} onClick={() => setChoosing((was) => !was)}>
            <Plus size={16} aria-hidden="true" /> New entry
          </button>
        </div>
      ) : null}
      {onNewEntry && choosing ? (
        <TemplateChoice
          usual={template}
          journal={name}
          onPick={(text) => {
            setChoosing(false);
            onNewEntry(text);
          }}
          onCancel={() => setChoosing(false)}
        />
      ) : null}
      {words.before ? <BookWords words={words.before} known={known} open={open} dark={dark} /> : null}
      {months.length === 0 && unwritten.length === 0 ? (
        <div className={styles.empty}>
          <p>No entries yet.</p>
          <p className={styles.quiet}>{templateSentence(template)}</p>
        </div>
      ) : null}
      {months.map((month, n) =>
        n < OPEN_MONTHS || unfolded.has(month.key) ? (
          <section key={month.key} className={styles.month} aria-label={month.label}>
            <h2 className={styles.monthName}>{month.label}</h2>
            <ol className={styles.entries}>
              {month.entries.map((entry) => (
                <li key={entry.id}>
                  <button type="button" className={styles.entry} aria-label={entry.label} onClick={() => open(entry.title)}>
                    <span className={styles.day} aria-hidden="true">
                      <span className={styles.date}>{entry.day}</span>
                      <span className={styles.weekday}>{entry.weekday}</span>
                    </span>
                    <span className={styles.meta} aria-hidden="true">
                      {entry.time}
                      {entry.place ? ` · ${entry.place}` : ''}
                    </span>
                    <span className={styles.first} aria-hidden="true">
                      {entry.first}
                    </span>
                  </button>
                </li>
              ))}
            </ol>
          </section>
        ) : (
          <button key={month.key} type="button" className={styles.folded} onClick={() => setUnfolded((was) => new Set([...was, month.key]))}>
            <span>
              {month.label} · {month.entries.length}
            </span>
            <ChevronRight size={16} aria-hidden="true" />
          </button>
        ),
      )}
      {unwritten.length ? (
        <section className={styles.month} aria-label="Not written yet">
          <h2 className={styles.monthName}>Not written yet</h2>
          <ol className={styles.entries}>
            {unwritten.map((title) => (
              <li key={title} className={styles.planned}>
                <button type="button" className={styles.plannedTitle} aria-label={`${title}, not written yet`} onClick={() => open(title)}>
                  {title}
                </button>
                <button type="button" className={styles.tool} aria-label={`Take ${title} out of the journal`} onClick={() => onChange(withoutChapter(body, title))}>
                  <X size={16} aria-hidden="true" />
                </button>
              </li>
            ))}
          </ol>
        </section>
      ) : null}
      {words.after ? <BookWords words={words.after} known={known} open={open} dark={dark} /> : null}
    </div>
  );
}

/** The templates a new entry can start from, under New entry (JournalView). */
function TemplateChoice({ usual, journal, onPick, onCancel }: { usual: string; journal: string; onPick: (text: string) => void; onCancel: () => void }) {
  // The back gesture folds the choice before it leaves the journal, as the find bar and the palette take it first.
  useBack(true, onCancel);
  const starts = useMemo(() => entryStarts(usual), [usual]);
  const now = new Date();
  return (
    <section className={styles.choose} aria-label="Start the entry with">
      <p className={styles.chooseTitle}>Start the entry with</p>
      <ul className={styles.starts}>
        {starts.map((start) => (
          <li key={start.id}>
            <button type="button" className={styles.start} onClick={() => onPick(start.text)}>
              <span className={styles.startName}>
                {start.name}
                {start.id === 'usual' ? <span className={styles.usual}>Usual</span> : null}
              </span>
              <span className={styles.startLine}>{startLine(start.text, journal, now)}</span>
            </button>
          </li>
        ))}
      </ul>
      <button type="button" className={`app-word ${styles.cancel}`} onClick={onCancel}>
        Cancel
      </button>
    </section>
  );
}
