import card from '../ai/ConfirmCard.module.css';
import type { Note } from '../core/store.ts';
import type { CardChoice, LiveCard } from './liveRoute.ts';
import { withoutLead } from '../core/itemSyntax.ts';
import { partialCommand } from './chip.ts';
import { linesAbove } from './listAppend.ts';
import { tableQuestion } from './table.ts';
import type { TableDraft } from './takeHost.ts';
import styles from './CaptureScreen.module.css';

/**
 * The recorder's cards, where the chip would be: the table being asked for a piece at a time, a table as it will land,
 * and items arriving in another note's list. Drawn by CaptureScreen.tsx from what the take tells it; they hold no
 * state of their own.
 *
 * The table card is the confirm card's shape, drawn with that card's own stylesheet (ai/ConfirmCard.module.css), so
 * the questions and the yes that follows them read as one card; the question and the table are the only parts of its
 * own (CaptureScreen.module.css).
 */

/** A table as it stands: the labels, then each row, padded to them. */
export function TablePreview({ columns, rows }: { columns: readonly string[]; rows: readonly (readonly string[])[] }) {
  return (
    <div className={styles.tableWrap}>
      <table className={styles.table}>
        <thead>
          <tr>
            {columns.map((label, i) => (
              <th key={i}>{label}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, r) => (
            <tr key={r}>
              {columns.map((_, i) => (
                <td key={i}>{row[i] ?? ''}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * "And what will the column labels be?": the table being said, one question
 * at a time. Matt wanted the recorder to guide a table rather than expect it in
 * one breath, so the card asks for the labels, then the first row, then the
 * next or "done", showing the table as it grows and the words being heard
 * for the piece it asked for.
 */
export function TableCard({ draft, heard, onDone, onCancel }: { draft: TableDraft<Note>; heard: string; onDone: () => void; onCancel: () => void }) {
  const { question, hint } = tableQuestion(draft);
  const words = heard ? partialCommand(heard) : '';
  return (
    <section className={card.confirm} aria-live="polite" aria-label={`Table for ${draft.title}`}>
      <p className={card.heading}>Table for {draft.title}</p>
      <p className={styles.tableQuestion}>{question}</p>
      {draft.columns.length ? <TablePreview columns={draft.columns} rows={draft.rows} /> : null}
      {words ? <p className={card.detail}>“{words}”</p> : <p className={card.hint}>{hint}</p>}
      <div className={card.actions}>
        <button type="button" className="app-word" onClick={onCancel}>
          Cancel
        </button>
        {draft.columns.length ? (
          <button type="button" className="app-pill" onClick={onDone}>
            That’s all
          </button>
        ) : null}
      </div>
    </section>
  );
}

/**
 * Items landing in another note's list: the note's name, the list's last lines
 * as they were, and the new lines arriving under them with a tick each. `onUndo`, for words the live reader sent
 * there, takes them out again (Not this note).
 */
export function ListLanding({ title, body, added, onUndo }: { title: string; body: string; added: string[]; onUndo?: () => void }) {
  return (
    <div className={styles.landing} aria-label={`Added to ${title}`}>
      {onUndo ? (
        <button type="button" className={`app-word ${styles.landingUndo}`} onClick={onUndo}>
          Not this note
        </button>
      ) : null}
      <p className={styles.contextTitle}>{title}</p>
      {linesAbove(body, added).map((line, i) => (
        <p key={`b${i}`} className={styles.contextLine}>
          {withoutLead(line).replace(/^#{1,6}\s+/, '')}
        </p>
      ))}
      {added.map((line, i) => (
        <p key={`a${i}`} className={styles.landed} style={{ animationDelay: `${120 + i * 140}ms` }}>
          <span className={styles.landedTick} aria-hidden="true" />
          {withoutLead(line)}
        </p>
      ))}
    </div>
  );
}

/**
 * "Add to which note?": the live reader was not sure which note a name meant, or found none but came near one
 * (capture/liveRoute.ts). The card shows the words as they would land and a button for each note it could be, a new
 * note by the name as heard, and Keep here. It blocks nothing: the recording carries on, what is said meanwhile goes
 * to the page, and after 8 s, or at Done, the words stay here. A title, "the first one" or "keep it here" said answers
 * it as a tap does.
 */
export function NoteChoiceCard({ card: shown, onChoose }: { card: LiveCard<Note>; onChoose: (choice: CardChoice) => void }) {
  return (
    <section className={card.confirm} aria-live="polite" aria-label={shown.heading}>
      <p className={card.heading}>{shown.heading}</p>
      {shown.payload ? <p className={card.line}>{withoutLead(shown.payload)}</p> : null}
      <div className={styles.choices}>
        {shown.candidates.map((candidate) => (
          <button key={candidate.id} type="button" className="app-pill" onClick={() => onChoose({ kind: 'note', id: candidate.id })}>
            {candidate.title}
          </button>
        ))}
        {shown.newTitle ? (
          <button type="button" className="app-word" onClick={() => onChoose({ kind: 'new' })}>
            New note “{shown.newTitle}”
          </button>
        ) : null}
      </div>
      <div className={card.actions}>
        <button type="button" className="app-word" onClick={() => onChoose({ kind: 'keep' })}>
          {shown.form === 'declined' ? 'Leave it' : 'Keep here'}
        </button>
      </div>
    </section>
  );
}
