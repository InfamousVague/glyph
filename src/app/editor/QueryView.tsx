import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Check, ChevronLeft, ChevronRight, Pencil, TriangleAlert } from '@glacier/icons';
import { inMonth, monthAfter, monthName, monthWeeks, openingMonth, type CalendarDay } from '../core/query/calendar.ts';
import type { QueryProblem } from '../core/query/read.ts';
import { KIND_WORDS, type Cell, type Group, type QueryResult, type Row } from '../core/query/run.ts';
import { chipLook, dayLabel, daySaid, type ChipLook } from './fieldChips.ts';
import { tagsIn } from '../core/tags.ts';
import { drawDiagram, type Drawing } from './mermaid.ts';
import styles from './QueryView.module.css';

/**
 * A query's answer, drawn (editor/queries.ts, docs/QUERIES.md, docs/DESIGN.md §159): a table, a list, a board, a
 * month, a gantt or a count, with a quiet head that says what it lists and how many, and a pencil that opens its lines.
 * Everything here is drawing; what is listed, in what order and in which groups is core/query/run.ts's.
 *
 * A cell is drawn as what it holds: a due day by when it is ("Tomorrow", red once it has passed), a priority as Jira's
 * chevrons, a person with their initial in a ring, a status with its category's dot - the same looks a field has on
 * its line (editor/fieldChips.ts) and a ticket has in a list (notes/TicketMark.tsx), so a thing reads the same
 * wherever it is shown. The name of a record is the button that opens it; a to-do's box ticks it.
 */

interface QueryViewProps {
  /** The fence's lines, shown with the problem where they cannot be read. */
  lines: string;
  problem: QueryProblem | null;
  /** Null where the lines cannot be read, or there is no library to read. */
  result: QueryResult | null;
  editable: boolean;
  /** The open note, whose to-dos are ticked and reached in place. */
  thisNote: string | null;
  onEdit: () => void;
  onOpen: (row: Row) => void;
  onTick: (row: Row) => void;
}

/** What a row and a cell need from the query's drawing to act and to name days. */
interface Acts {
  today: string;
  editable: boolean;
  onOpen: (row: Row) => void;
  onTick: (row: Row) => void;
}

export function QueryView({ lines, problem, result, editable, onEdit, onOpen, onTick }: QueryViewProps) {
  if (problem || !result) {
    return (
      <section className={styles.query} aria-label="Query">
        <Head title="Query" count={null} editable={editable} onEdit={onEdit} />
        <pre className={styles.lines}>{lines}</pre>
        {problem ? (
          <p className={styles.problem} role="note">
            <TriangleAlert size="1em" strokeWidth={2.2} aria-hidden="true" className={styles.problemMark} />
            <span>
              Line {problem.line}, column {problem.column}: {problem.message}
            </span>
          </p>
        ) : null}
      </section>
    );
  }
  const acts: Acts = { today: result.today, editable, onOpen, onTick };
  const words = KIND_WORDS[result.kind];
  const count = result.shown < result.matched ? `${result.shown} of ${result.matched}` : String(result.matched);
  const rows = result.groups.flatMap((group) => group.rows);
  const empty = result.matched === 0 && result.show !== 'count';
  return (
    <section className={styles.query} aria-label={`Query: ${words}`} data-show={result.show}>
      <Head title={words} count={count} editable={editable} onEdit={onEdit} />
      {result.warnings.map((warning) => (
        <p key={warning} className={styles.warning}>
          {warning}
        </p>
      ))}
      {empty && !(result.show === 'board' && result.groups.length > 1) ? (
        <p className={styles.empty}>Nothing matches this query yet.</p>
      ) : result.show === 'table' ? (
        <TableView result={result} acts={acts} />
      ) : result.show === 'board' ? (
        <BoardView result={result} acts={acts} />
      ) : result.show === 'calendar' ? (
        <CalendarView rows={rows} acts={acts} />
      ) : result.show === 'gantt' ? (
        <GanttView result={result} />
      ) : result.show === 'count' ? (
        <CountView result={result} />
      ) : (
        <ListView result={result} acts={acts} />
      )}
      {result.totals.length && result.show !== 'table' && result.show !== 'count' ? <Totals totals={result.totals} /> : null}
    </section>
  );
}

/** The quiet head: what the query lists, how many, and the pencil that shows its lines. */
function Head({ title, count, editable, onEdit }: { title: string; count: string | null; editable: boolean; onEdit: () => void }) {
  return (
    <header className={styles.head}>
      <span className={styles.title}>{title}</span>
      {count !== null ? <span className={styles.count}>{count}</span> : null}
      {editable ? (
        <button type="button" className={styles.edit} onClick={onEdit} aria-label="Edit the query" title="Edit the query">
          <Pencil size="1em" strokeWidth={2.2} aria-hidden="true" />
        </button>
      ) : null}
    </header>
  );
}

/** A group's heading, for a list or a table grouped by a field: its value, how many, and its totals. */
function GroupHead({ group }: { group: Group }) {
  return (
    <div className={styles.groupHead}>
      {group.cell?.kind === 'status' ? <StatusCell cell={group.cell} /> : <span className={styles.groupLabel}>{group.label}</span>}
      <span className={styles.count}>{group.rows.length}</span>
      {group.totals.map((total) => (
        <span key={total.field} className={styles.groupTotal}>
          {total.label} {total.text}
        </span>
      ))}
    </div>
  );
}

function Totals({ totals }: { totals: QueryResult['totals'] }) {
  return (
    <p className={styles.totals}>
      {totals.map((total) => (
        <span key={total.field}>
          {total.label} <strong>{total.text}</strong>
        </span>
      ))}
    </p>
  );
}

// ---- a record's own pieces -------------------------------------------------------------------------

/** A to-do's box, ticked where it is written; nothing for a note or a ticket. */
function Box({ row, acts }: { row: Row; acts: Acts }) {
  if (row.kind !== 'task' || row.done === null) return null;
  return (
    <button
      type="button"
      role="checkbox"
      aria-checked={row.done}
      aria-label={row.done ? `Clear ${row.name}` : `Tick ${row.name}`}
      className={styles.box}
      data-done={row.done ? '' : undefined}
      disabled={!acts.editable}
      onClick={() => acts.onTick(row)}
    >
      {row.done ? <Check size="0.8em" strokeWidth={3} aria-hidden="true" /> : null}
    </button>
  );
}

/** A record's name, the button that opens it: a ticket's key before it, its tags as tags, a finished one struck through. */
function Name({ row, acts }: { row: Row; acts: Acts }) {
  return (
    <button type="button" className={styles.name} data-done={row.category === 'done' || row.done ? '' : undefined} onClick={() => acts.onOpen(row)}>
      {row.id ? <span className={styles.key}>{row.id}</span> : null}
      <span className={styles.nameWords}>{withTags(row.name || 'Untitled')}</span>
    </button>
  );
}

/** Words with their tags drawn as the editor draws a tag (editor/tags.ts), so `Milk #dairy` reads as it does on its line. */
function withTags(words: string): ReactNode {
  const tags = tagsIn(words);
  if (!tags.length) return words;
  const parts: ReactNode[] = [];
  let at = 0;
  for (const tag of tags) {
    if (tag.from > at) parts.push(words.slice(at, tag.from));
    parts.push(
      <span key={tag.from} className="cm-tag">
        {words.slice(tag.from, tag.to)}
      </span>,
    );
    at = tag.to;
  }
  if (at < words.length) parts.push(words.slice(at));
  return parts;
}

/** A field's chip, as its line draws it (editor/fieldChips.ts), drawn by React. */
function Chip({ look, words = true }: { look: ChipLook; words?: boolean }) {
  const Icon = look.icon;
  const text = words ? look.text : '';
  return (
    <span className="cm-field" data-tone={look.tone} data-mark={text ? undefined : ''} data-person={look.initial ? '' : undefined} title={look.label} aria-label={look.label} role="img">
      {Icon ? <Icon strokeWidth={look.menu === 'priority' ? 2.6 : 2.2} aria-hidden="true" /> : null}
      {look.initial ? (
        <span className="cm-fieldInitial" aria-hidden="true">
          {look.initial}
        </span>
      ) : null}
      {text ? (
        <span className="cm-fieldWords" aria-hidden="true">
          {text}
        </span>
      ) : null}
    </span>
  );
}

function StatusCell({ cell }: { cell: Extract<Cell, { kind: 'status' }> }) {
  return (
    <span className={styles.status} data-category={cell.category}>
      <span className={styles.dot} aria-hidden="true" />
      {cell.text}
    </span>
  );
}

/**
 * A cell, drawn as what it holds. `quiet` is a row that is finished with, whose days are not late; `brief` is a list's
 * or a card's line of them, where a priority is its mark alone and an empty cell is nothing at all.
 */
function CellView({ cell, field, today, quiet, brief }: { cell: Cell; field: string; today: string; quiet: boolean; brief: boolean }): ReactNode {
  switch (cell.kind) {
    case 'empty':
      return brief ? null : <span className={styles.none} aria-label="None">–</span>;
    case 'text':
      // A ticket's key in the mono face it is written in, as everywhere a key is shown.
      return <span className={field === 'id' ? styles.keyCell : styles.text}>{cell.text}</span>;
    case 'number':
      return <span className={styles.number}>{cell.text}</span>;
    case 'day': {
      const tone = quiet ? null : cell.tone;
      return (
        <time dateTime={cell.day} className={styles.day} data-tone={tone ?? undefined} title={daySaid(cell.day, today)}>
          {dayLabel(cell.day, today)}
        </time>
      );
    }
    case 'priority': {
      const look = chipLook({ kind: 'priority', from: 0, to: 0, key: 'priority', value: cell.name }, { today, done: quiet });
      return look ? (
        <span className={styles.priority}>
          <Chip look={look} />
          {brief ? null : <span>{look.label.replace(/ priority$/, '')}</span>}
        </span>
      ) : null;
    }
    case 'status':
      return <StatusCell cell={cell} />;
    case 'people':
      return (
        <span className={styles.people}>
          {cell.names.map((name) => {
            const look = chipLook({ kind: 'person', from: 0, to: 0, key: 'assignee', value: name }, { today, done: quiet });
            return look ? <Chip key={name} look={look} /> : null;
          })}
        </span>
      );
    case 'list':
      return (
        <span className={styles.list}>
          {cell.items.map((item) =>
            cell.tags ? (
              <span key={item} className="cm-tag">
                #{item}
              </span>
            ) : (
              <span key={item} className={styles.item}>
                {item}
              </span>
            ),
          )}
        </span>
      );
    case 'bool':
      return cell.on ? <Check size="1em" strokeWidth={2.6} aria-label="Yes" className={styles.yes} /> : brief ? null : <span className={styles.none}>No</span>;
  }
}

/** The cells a list's row or a card shows beside its name: every column but the name, nothing where they are empty. */
function Meta({ row, result, acts }: { row: Row; result: QueryResult; acts: Acts }) {
  const quiet = row.category === 'done' || row.done === true;
  const shown = result.columns
    .map((column, index) => ({ column, cell: row.cells[index]! }))
    // The name is the row's own; a ticket's key is before it already; the note a to-do is in says itself below; and
    // the field it is grouped by is its group's heading, which a card under it need not say again.
    .filter(({ column, cell }, index) => index !== result.opens && column.field !== 'id' && column.field !== 'note' && column.field !== result.group && cell.kind !== 'empty');
  const note = result.kind === 'tasks' && result.columns.some((column) => column.field === 'note') ? row.cells[result.columns.findIndex((column) => column.field === 'note')] : null;
  if (!shown.length && !note) return null;
  return (
    <span className={styles.meta}>
      {shown.map(({ column, cell }) => (
        <span key={column.field} className={styles.metaCell} data-field={column.field}>
          <CellView cell={cell} field={column.field} today={acts.today} quiet={quiet} brief />
        </span>
      ))}
      {note?.kind === 'text' ? <span className={styles.inNote}>{note.text}</span> : null}
    </span>
  );
}

// ---- the ways a query is shown ---------------------------------------------------------------------

function ListView({ result, acts }: { result: QueryResult; acts: Acts }) {
  return (
    <div className={styles.groups}>
      {result.groups.map((group) => (
        <div key={group.key || 'all'} className={styles.group}>
          {result.group ? <GroupHead group={group} /> : null}
          <ul className={styles.rows}>
            {group.rows.map((row) => (
              <li key={row.key} className={styles.row} data-kind={row.kind}>
                <Box row={row} acts={acts} />
                <span className={styles.rowBody}>
                  <Name row={row} acts={acts} />
                  <Meta row={row} result={result} acts={acts} />
                </span>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

function TableView({ result, acts }: { result: QueryResult; acts: Acts }) {
  const totals = new Map(result.totals.map((total) => [total.field, total.text]));
  // A total for a field that is not a column is said under the table instead.
  const outside = result.totals.filter((total) => !result.columns.some((column) => column.field === total.field));
  return (
    <>
      {result.groups.map((group) => (
        <div key={group.key || 'all'} className={styles.group}>
          {result.group ? <GroupHead group={group} /> : null}
          <div className={styles.tableScroll}>
            <table className={styles.table}>
              <thead>
                <tr>
                  {result.columns.map((column) => (
                    <th key={column.field} scope="col" data-field={column.field}>
                      {column.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {group.rows.map((row) => {
                  const quiet = row.category === 'done' || row.done === true;
                  return (
                    <tr key={row.key} data-done={quiet ? '' : undefined}>
                      {result.columns.map((column, index) =>
                        index === result.opens ? (
                          <th key={column.field} scope="row" className={styles.nameCell}>
                            <span className={styles.nameCellInner}>
                              <Box row={row} acts={acts} />
                              <Name row={{ ...row, id: column.field === 'title' && result.columns.some((each) => each.field === 'id') ? null : row.id }} acts={acts} />
                            </span>
                          </th>
                        ) : (
                          <td key={column.field} data-field={column.field}>
                            <CellView cell={row.cells[index]!} field={column.field} today={acts.today} quiet={quiet} brief={false} />
                          </td>
                        ),
                      )}
                    </tr>
                  );
                })}
              </tbody>
              {!result.group && result.columns.some((column) => totals.has(column.field)) ? (
                <tfoot>
                  <tr>
                    {result.columns.map((column, index) => (
                      <td key={column.field} data-field={column.field}>
                        {totals.has(column.field) ? <strong className={styles.number}>{totals.get(column.field)}</strong> : index === 0 ? 'Total' : null}
                      </td>
                    ))}
                  </tr>
                </tfoot>
              ) : null}
            </table>
          </div>
        </div>
      ))}
      {outside.length || (result.group && result.totals.length) ? <Totals totals={result.group ? result.totals : outside} /> : null}
    </>
  );
}

function BoardView({ result, acts }: { result: QueryResult; acts: Acts }) {
  return (
    <div className={styles.board} role="list" aria-label="Board">
      {result.groups.map((group) => (
        <section key={group.key || 'none'} className={styles.lane} role="listitem" aria-label={`${group.label}, ${group.rows.length}`}>
          <GroupHead group={group} />
          <ul className={styles.cards}>
            {group.rows.map((row) => (
              <li key={row.key} className={styles.card} data-done={row.category === 'done' || row.done ? '' : undefined}>
                <span className={styles.cardTop}>
                  <Box row={row} acts={acts} />
                  <Name row={row} acts={acts} />
                </span>
                <Meta row={row} result={result} acts={acts} />
              </li>
            ))}
            {group.rows.length ? null : <li className={styles.laneEmpty}>Nothing here</li>}
          </ul>
        </section>
      ))}
    </div>
  );
}

const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

function CalendarView({ rows, acts }: { rows: Row[]; acts: Acts }) {
  const opening = useMemo(() => openingMonth(rows, acts.today), [rows, acts.today]);
  const [month, setMonth] = useState(opening);
  const [picked, setPicked] = useState<string | null>(null);
  const weeks = monthWeeks(month, rows, acts.today);
  const days = weeks.flat();
  // The day whose records are listed under the month: the one picked, a day of the weeks either side included, else
  // today in today's month, else the first day with anything on it.
  const shownDay = days.find((day) => day.day === picked) ?? days.find((day) => day.today && day.inMonth && day.rows.length) ?? days.find((day) => day.inMonth && day.rows.length) ?? null;
  const undated = rows.filter((row) => row.day === null).length;
  const turn = (by: number) => {
    setMonth((now) => monthAfter(now, by));
    setPicked(null);
  };
  return (
    <div className={styles.calendar}>
      <div className={styles.monthBar}>
        <button type="button" className={styles.turn} onClick={() => turn(-1)} aria-label="The month before">
          <ChevronLeft size="1em" strokeWidth={2.4} aria-hidden="true" />
        </button>
        <span className={styles.monthName} aria-live="polite">
          {monthName(month)}
          <span className={styles.count}>{inMonth(rows, month)}</span>
        </span>
        <button type="button" className={styles.turn} onClick={() => turn(1)} aria-label="The month after">
          <ChevronRight size="1em" strokeWidth={2.4} aria-hidden="true" />
        </button>
      </div>
      <div className={styles.month} role="grid" aria-label={monthName(month)}>
        <div className={styles.week} role="row">
          {WEEKDAYS.map((day) => (
            <span key={day} className={styles.weekday} role="columnheader" aria-label={day}>
              {day.charAt(0)}
            </span>
          ))}
        </div>
        {weeks.map((week) => (
          <div key={week[0]!.day} className={styles.week} role="row">
            {week.map((day) => (
              <DayCell key={day.day} day={day} picked={shownDay?.day === day.day} today={acts.today} onPick={() => setPicked(day.day)} />
            ))}
          </div>
        ))}
      </div>
      {shownDay ? (
        <div className={styles.dayList}>
          <p className={styles.dayListHead}>{daySaid(shownDay.day, acts.today)}</p>
          {shownDay.rows.length ? (
            <ul className={styles.rows}>
              {shownDay.rows.map((row) => (
                <li key={row.key} className={styles.row}>
                  <Box row={row} acts={acts} />
                  <span className={styles.rowBody}>
                    <Name row={row} acts={acts} />
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className={styles.empty}>Nothing on this day.</p>
          )}
        </div>
      ) : null}
      {undated ? <p className={styles.warning}>{undated === 1 ? 'One has no day, and is not on the calendar.' : `${undated} have no day, and are not on the calendar.`}</p> : null}
    </div>
  );
}

function DayCell({ day, picked, today, onPick }: { day: CalendarDay; picked: boolean; today: string; onPick: () => void }) {
  const late = day.rows.some((row) => row.overdue);
  const label = `${daySaid(day.day, today)}${day.rows.length ? `, ${day.rows.length} ${day.rows.length === 1 ? 'thing' : 'things'}` : ''}`;
  return (
    <button
      type="button"
      role="gridcell"
      className={styles.dayCell}
      data-out={day.inMonth ? undefined : ''}
      data-today={day.today ? '' : undefined}
      data-picked={picked ? '' : undefined}
      aria-selected={picked}
      aria-label={label}
      onClick={onPick}
    >
      <span className={styles.date}>{day.date}</span>
      {day.rows.length ? (
        <span className={styles.dots} data-late={late ? '' : undefined} aria-hidden="true">
          {day.rows.length > 3 ? day.rows.length : day.rows.map((row) => <span key={row.key} className={styles.pip} />)}
        </span>
      ) : null}
    </button>
  );
}

function GanttView({ result }: { result: QueryResult }) {
  const code = result.gantt?.code ?? '';
  const [drawing, setDrawing] = useState<Drawing | null>(null);
  useEffect(() => {
    let live = true;
    setDrawing(null);
    if (code) void drawDiagram(code).then((made) => live && setDrawing(made));
    return () => {
      live = false;
    };
  }, [code]);
  const unplaced = result.shown - (result.gantt?.placed ?? 0);
  if (!code) return <p className={styles.empty}>Nothing here has a start or a due day to put on a timeline.</p>;
  return (
    <>
      {drawing && 'svg' in drawing ? (
        // Mermaid's own drawing, made with its strict security level (editor/mermaid.ts): no HTML from a record's words.
        <div className={`cm-mermaid ${styles.gantt}`} data-drawn="" role="img" aria-label="Timeline" dangerouslySetInnerHTML={{ __html: drawing.svg }} />
      ) : (
        <pre className={styles.lines}>{code}</pre>
      )}
      {drawing && 'failed' in drawing ? <p className={styles.warning}>This timeline could not be drawn here.</p> : null}
      {unplaced > 0 ? <p className={styles.warning}>{unplaced === 1 ? 'One has no start or due day, and is not on the timeline.' : `${unplaced} have no start or due day, and are not on the timeline.`}</p> : null}
    </>
  );
}

function CountView({ result }: { result: QueryResult }) {
  const word = KIND_WORDS[result.kind].toLowerCase();
  const one = { notes: 'note', tickets: 'ticket', tasks: 'to-do' }[result.kind];
  return (
    <p className={styles.countView}>
      <span className={styles.bigNumber}>{result.matched}</span>
      <span className={styles.countWords}>{result.matched === 1 ? one : word}</span>
      {result.totals.map((total) => (
        <span key={total.field} className={styles.countWords}>
          · {total.label} <strong>{total.text}</strong>
        </span>
      ))}
    </p>
  );
}
