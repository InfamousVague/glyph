import { useEffect, useMemo, useRef, useState, type ComponentType, type CSSProperties, type KeyboardEvent, type PointerEvent as ReactPointerEvent, type ReactNode, type RefObject } from 'react';
import { createPortal } from 'react-dom';
import { CalendarDays, ChartGantt, Check, ChevronLeft, ChevronRight, List as ListIcon, Pencil, Sigma, SlidersHorizontal, SquareKanban, Table as TableIcon, TriangleAlert, type IconProps } from '@glacier/icons';
import { inMonth, monthAfter, monthName, monthWeeks, openingMonth, type CalendarDay } from '../core/query/calendar.ts';
import { withShow } from '../core/query/fence.ts';
import { SHOWS, type QueryProblem, type ShowAs } from '../core/query/read.ts';
import { QueryBuilder } from './QueryBuilder.tsx';
import { KIND_WORDS, type Cell, type Column, type Group, type QueryResult, type Row } from '../core/query/run.ts';
import { chipLook, dayLabel, daySaid, type ChipLook } from './fieldChips.ts';
import { tagsIn } from '../core/tags.ts';
import { drawDiagram, type Drawing } from './mermaid.ts';
import { wispFoot, wispFootFade } from '../art/wispFoot.ts';
import { BOARD_HEIGHT, clampHeight } from '../core/boards.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { FieldPicker, StatusIcon } from './FieldPicker.tsx';
import { pickOf, picksField, statusLook, type FieldPick } from './fieldPicks.ts';
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
 *
 * **A value is a button** where the note can be edited (docs/DESIGN.md §169; Matt: "I'd like to be able to click things
 * like done labels in order to change the status … use modals with iconography and color"): a status, a priority, a
 * person and a due, start or scheduled day, in a table's cell, a list's line or a board's card, opens a sheet of its
 * choices (editor/FieldPicker.tsx), each in its mark and colour, and the one picked is written where the record is
 * (`onSet`), as a card dragged to another lane is. A to-do's status is its box: To do or Done.
 */

interface QueryViewProps {
  /** The fence's lines, shown with the problem where they cannot be read. */
  lines: string;
  problem: QueryProblem | null;
  /** Null where the lines cannot be read, or there is no library to read. */
  result: QueryResult | null;
  editable: boolean;
  /** A board's lanes' height from the fence (`height=18`), in their own ems; null for the board's own. */
  height?: number | null;
  /** Writes a board's height into the fence, or takes it out with null. */
  onHeight?: (height: number | null) => void;
  /** Writes the whole fence body back, one clause changed: the view switcher and the builder. Absent where the lines cannot be edited. */
  onBody?: (body: string) => void;
  /** The open note, whose to-dos are ticked and reached in place. */
  thisNote: string | null;
  onEdit: () => void;
  onOpen: (row: Row) => void;
  onTick: (row: Row) => void;
  /** A card dragged to another lane of a board: its grouped field set to the lane's value, or cleared with null. */
  onMove: (row: Row, value: string | null) => void;
  /** One field of a record set to a value picked in a sheet, or taken off with null. Absent, nothing is picked. */
  onSet?: (row: Row, field: string, value: string | null) => void;
  /** The people the library names, the most named first: who a person's sheet offers. Read when it opens. */
  people?: () => readonly string[];
}

/** What a row and a cell need from the query's drawing to act and to name days. */
interface Acts {
  today: string;
  editable: boolean;
  onOpen: (row: Row) => void;
  onTick: (row: Row) => void;
  onMove: (row: Row, value: string | null) => void;
  /** Whether a record's field opens a sheet to pick it from; and opening it. */
  pickable: (row: Row, field: string) => boolean;
  pick: (row: Row, column: Column, cell: Cell) => void;
}

/** A sheet open on one record's field. */
interface Picking {
  row: Row;
  field: string;
  label: string;
  pick: FieldPick;
}

export function QueryView({ lines, problem, result, editable, height = null, onHeight, onBody, onEdit, onOpen, onTick, onMove, onSet, people }: QueryViewProps) {
  const [building, setBuilding] = useState(false);
  const [picking, setPicking] = useState<Picking | null>(null);
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
  const canPick = editable && !!onSet;
  const acts: Acts = {
    today: result.today,
    editable,
    onOpen,
    onTick,
    onMove,
    pickable: (row, field) => canPick && picksField(row, field),
    pick: (row, column, cell) => {
      const pick = pickOf(row, column.field, cell, result.today, people ?? (() => []));
      if (!pick) return;
      fireNativeHaptic('selection');
      setPicking({ row, field: column.field, label: column.label, pick });
    },
  };
  const words = KIND_WORDS[result.kind];
  const count = result.shown < result.matched ? `${result.shown} of ${result.matched}` : String(result.matched);
  const rows = result.groups.flatMap((group) => group.rows);
  const empty = result.matched === 0 && result.show !== 'count';
  return (
    <section className={styles.query} aria-label={`Query: ${words}`} data-show={result.show}>
      <Head
        title={words}
        count={count}
        editable={editable}
        onEdit={onEdit}
        show={result.show}
        onShow={onBody ? (way) => onBody(withShow(lines, way)) : undefined}
        onBuild={onBody ? () => setBuilding(true) : undefined}
      />
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
        <BoardView result={result} acts={acts} height={height} onHeight={onHeight} />
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
      {building && onBody
        ? createPortal(
            <QueryBuilder
              body={lines}
              onBody={onBody}
              onLines={() => {
                setBuilding(false);
                onEdit();
              }}
              onClose={() => setBuilding(false)}
            />,
            document.body,
          )
        : null}
      {picking && onSet
        ? createPortal(
            <FieldPicker
              pick={picking.pick}
              label={picking.label}
              record={picking.row.id ? `${picking.row.id} · ${picking.row.name}` : picking.row.name}
              onClose={() => setPicking(null)}
              onPick={(value) => {
                const { row, field, pick } = picking;
                fireNativeHaptic('selection');
                // A to-do's status is its box: ticked or cleared, only where that is a change.
                if (pick.kind === 'box') {
                  if ((value === 'done') !== pick.done) onTick(row);
                  return;
                }
                onSet(row, field, value);
              }}
            />,
            document.body,
          )
        : null}
    </section>
  );
}

/** The ways a query can be shown, for the switcher: each with its mark and a word, in the order docs/QUERIES.md teaches. */
const VIEWS: Readonly<Record<ShowAs, { icon: ComponentType<IconProps>; label: string }>> = {
  table: { icon: TableIcon, label: 'Table' },
  list: { icon: ListIcon, label: 'List' },
  board: { icon: SquareKanban, label: 'Board' },
  calendar: { icon: CalendarDays, label: 'Calendar' },
  gantt: { icon: ChartGantt, label: 'Timeline' },
  count: { icon: Sigma, label: 'Count' },
};

/**
 * The quiet head: what the query lists, how many, a switcher for how it is drawn, and the pencil that shows its lines.
 * The switcher writes only the `show:` line (editor/queries.ts `onShow`), so a list becomes a board or a table with
 * its `from:` and `where:` kept, the way a database's view tabs do; it is there only where the lines can be edited.
 */
function Head({
  title,
  count,
  editable,
  onEdit,
  show,
  onShow,
  onBuild,
}: {
  title: string;
  count: string | null;
  editable: boolean;
  onEdit: () => void;
  show?: ShowAs;
  onShow?: (show: ShowAs) => void;
  onBuild?: () => void;
}) {
  return (
    <header className={styles.head}>
      <span className={styles.title}>{title}</span>
      {count !== null ? <span className={styles.count}>{count}</span> : null}
      {editable && show && onShow ? (
        <div className={styles.views} role="group" aria-label="How to show the query">
          {SHOWS.map((way) => {
            const Icon = VIEWS[way].icon;
            const here = way === show;
            return (
              <button
                key={way}
                type="button"
                className={styles.view}
                data-here={here ? '' : undefined}
                aria-pressed={here}
                aria-label={`Show as a ${VIEWS[way].label.toLowerCase()}`}
                title={VIEWS[way].label}
                onClick={() => {
                  if (!here) {
                    fireNativeHaptic('selection');
                    onShow(way);
                  }
                }}
              >
                <Icon size="1em" strokeWidth={2.2} aria-hidden="true" />
              </button>
            );
          })}
        </div>
      ) : null}
      {editable && onBuild ? (
        <button type="button" className={styles.edit} onClick={onBuild} aria-label="Build the query" title="Build the query">
          <SlidersHorizontal size="1em" strokeWidth={2.2} aria-hidden="true" />
        </button>
      ) : null}
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

/**
 * A record's name, the button that opens it: its tags as tags, a finished one struck through, a ticket's key before it
 * unless `hideKey` (a list's row and a board's card draw the key on its own line above the title instead, so the title
 * takes the full width rather than being pushed right of the key, Matt: "having it to the right makes a bunch of space
 * on the left that's unused").
 */
function Name({ row, acts, hideKey }: { row: Row; acts: Acts; hideKey?: boolean }) {
  return (
    <button type="button" className={styles.name} data-done={row.category === 'done' || row.done ? '' : undefined} onClick={() => acts.onOpen(row)}>
      {!hideKey && row.id ? <span className={styles.key}>{row.id}</span> : null}
      <span className={styles.nameWords}>{withTags(row.name || 'Untitled')}</span>
    </button>
  );
}

/** A ticket's key on a line of its own, above the title on a list's row and a board's card. */
function KeyLine({ id }: { id: string | null }) {
  return id ? <span className={styles.cardKey}>{id}</span> : null;
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

/** A status as a pill in its category's colour, with its mark (editor/FieldPicker.tsx `statusLook`). */
function StatusCell({ cell, workflow }: { cell: Extract<Cell, { kind: 'status' }>; workflow?: readonly string[] }) {
  return (
    <span className={styles.status} data-category={cell.category} data-look={statusLook(cell.text, workflow)}>
      <StatusIcon look={statusLook(cell.text, workflow)} size="0.95em" />
      {cell.text}
    </span>
  );
}

/**
 * A value that opens its sheet where it can be picked (`Acts.pick`), drawn as itself inside a quiet button; drawn as
 * itself alone where it cannot. Its press is its own: it never starts a board's card being carried (`startDrag`).
 */
function Picked({ row, column, cell, acts, children }: { row: Row; column: Column; cell: Cell; acts: Acts; children: ReactNode }) {
  if (!acts.pickable(row, column.field)) return <>{children}</>;
  const said = cell.kind === 'empty' ? 'none' : cell.kind === 'status' ? cell.text : cell.kind === 'priority' ? cell.name : cell.kind === 'people' ? cell.names.join(', ') : cell.kind === 'day' ? cell.day : '';
  return (
    <button
      type="button"
      className={styles.picked}
      data-empty={cell.kind === 'empty' ? '' : undefined}
      aria-haspopup="dialog"
      aria-label={`${column.label}: ${said}. Change it`}
      title={`Change ${column.label.toLowerCase()}`}
      onPointerDown={(event) => event.stopPropagation()}
      onClick={(event) => {
        event.stopPropagation();
        acts.pick(row, column, cell);
      }}
    >
      {children}
    </button>
  );
}

/**
 * A cell, drawn as what it holds. `quiet` is a row that is finished with, whose days are not late; `brief` is a list's
 * or a card's line of them, where a priority is its mark alone and an empty cell is nothing at all.
 */
function CellView({ cell, field, today, quiet, brief, workflow }: { cell: Cell; field: string; today: string; quiet: boolean; brief: boolean; workflow?: readonly string[] }): ReactNode {
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
      return <StatusCell cell={cell} workflow={workflow} />;
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
          <Picked row={row} column={column} cell={cell} acts={acts}>
            <CellView cell={cell} field={column.field} today={acts.today} quiet={quiet} brief workflow={row.workflow} />
          </Picked>
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
                  <KeyLine id={row.id} />
                  <Name row={row} acts={acts} hideKey />
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
                            <Picked row={row} column={column} cell={row.cells[index]!} acts={acts}>
                              <CellView cell={row.cells[index]!} field={column.field} today={acts.today} quiet={quiet} brief={false} workflow={row.workflow} />
                            </Picked>
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

/**
 * The value a lane writes to the grouped field when a card is dropped in it: a status' own text, or null to clear the
 * field in the "No …" lane. Only a status or a plain text field is written from what the lane shows; a day, a priority
 * or a person is drawn, not the value it is stored as, so a board grouped by one is not one cards can be dragged across
 * (`boardMovable`).
 */
function laneValue(group: Group): string | null {
  if (!group.key) return null;
  if (group.cell?.kind === 'status' || group.cell?.kind === 'text') return group.cell.text;
  return null;
}

/** Whether a board's cards can be dragged between its lanes: it is grouped, editable, and every lane can be written. */
function boardMovable(result: QueryResult, editable: boolean): boolean {
  return editable && !!result.group && result.groups.every((group) => !group.key || group.cell?.kind === 'status' || group.cell?.kind === 'text');
}

/** The group key of the lane under the pointer, or null where it is over no lane. '' is the "No …" lane, still a key. */
function laneKeyAt(x: number, y: number): string | null {
  const el = typeof document.elementFromPoint === 'function' ? document.elementFromPoint(x, y) : null;
  const lane = el?.closest<HTMLElement>('[data-lane-key]');
  return lane ? (lane.dataset.laneKey ?? null) : null;
}

/** How far a finger may wander before a press is a scroll, not the start of a drag, and how long a touch holds to lift a card. */
const DRAG_SLOP = 8;
const HOLD_MS = 320;

/**
 * A query drawn as a board, at a height of its own, as a ```board is (editor/boards/divider.ts): the lanes are as tall
 * as the fence's `height=`, or a screenful left to themselves, and each scrolls inside it with the wisp at its foot.
 * Left to the tallest lane, a query of every done ticket ran the board down the page a card at a time (Matt: "The
 * swimlanes are maximum height on the query instead of acting like board view with the split view handle").
 *
 * A card is dragged between lanes where the board can be written (`boardMovable`; Matt: "be able to click and drag
 * items between lanes"): a long press on a touch lifts it so a scroll of the lane is not mistaken for a pick-up, a
 * small move does on a mouse, and dropping it on another lane sets the grouped field to that lane's value (the queue
 * takes it, editor/queries.ts `onMove`). A ghost follows the pointer while it moves, and the lane under it is lit.
 */
function BoardView({ result, acts, height, onHeight }: { result: QueryResult; acts: Acts; height: number | null; onHeight?: (height: number | null) => void }) {
  // The height the line under the board is being dragged to, drawn while the finger moves and written when it lifts.
  const [dragged, setDragged] = useState<number | null>(null);
  const shown = dragged ?? height;
  const boardRef = useRef<HTMLDivElement>(null);

  const movable = boardMovable(result, acts.editable);
  const laneValues = useMemo(() => new Map(result.groups.map((group) => [group.key, laneValue(group)])), [result.groups]);
  // The card being carried, the lane it is over, and the ghost's place; cleared when it is dropped or let go.
  const [carrying, setCarrying] = useState<{ key: string; from: string } | null>(null);
  const [over, setOver] = useState<string | null>(null);
  const [ghost, setGhost] = useState<{ x: number; y: number; label: string } | null>(null);
  const teardown = useRef<(() => void) | null>(null);
  useEffect(() => () => teardown.current?.(), []);

  const startDrag = (event: ReactPointerEvent<HTMLLIElement>, row: Row, from: string) => {
    if (!movable) return;
    if (event.button !== 0 && event.pointerType === 'mouse') return;
    const startX = event.clientX;
    const startY = event.clientY;
    let active = false;
    let hold: number | null = null;
    const lift = () => {
      active = true;
      hold = null;
      fireNativeHaptic('selection');
      setCarrying({ key: row.key, from });
      setGhost({ x: startX, y: startY, label: row.name });
    };
    const move = (moving: PointerEvent) => {
      const dx = moving.clientX - startX;
      const dy = moving.clientY - startY;
      if (!active) {
        if (moving.pointerType === 'mouse') {
          if (Math.hypot(dx, dy) > DRAG_SLOP) lift();
          else return;
        } else {
          // A touch that wanders before the hold is a scroll of the lane, not a pick-up.
          if (Math.hypot(dx, dy) > DRAG_SLOP) stop(false);
          return;
        }
      }
      moving.preventDefault();
      setGhost({ x: moving.clientX, y: moving.clientY, label: row.name });
      const key = laneKeyAt(moving.clientX, moving.clientY);
      setOver(key !== null && key !== from ? key : null);
    };
    const up = (ending: PointerEvent) => {
      const landed = active ? laneKeyAt(ending.clientX, ending.clientY) : null;
      stop(true);
      if (landed !== null && landed !== from) acts.onMove(row, laneValues.get(landed) ?? null);
    };
    const stop = (dropped: boolean) => {
      if (hold) window.clearTimeout(hold);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
      teardown.current = null;
      setCarrying(null);
      setOver(null);
      setGhost(null);
      void dropped;
    };
    const cancel = () => stop(false);
    window.addEventListener('pointermove', move, { passive: false });
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    teardown.current = () => stop(false);
    if (event.pointerType !== 'mouse') hold = window.setTimeout(lift, HOLD_MS);
  };

  return (
    <>
      <div
        ref={boardRef}
        className={styles.board}
        role="list"
        aria-label="Board"
        data-sized={shown !== null ? '' : undefined}
        data-dragging={carrying ? '' : undefined}
        style={shown !== null ? ({ '--query-lane-height': `${shown}em` } as CSSProperties) : undefined}
      >
        {result.groups.map((group) => (
          <section
            key={group.key || 'none'}
            className={styles.lane}
            role="listitem"
            aria-label={`${group.label}, ${group.rows.length}`}
            data-lane-key={movable ? group.key : undefined}
            data-over={movable && over === group.key && carrying?.from !== group.key ? '' : undefined}
          >
            <GroupHead group={group} />
            <LaneCards still={dragged !== null}>
              {group.rows.map((row) => (
                <li
                  key={row.key}
                  className={styles.card}
                  data-done={row.category === 'done' || row.done ? '' : undefined}
                  data-movable={movable ? '' : undefined}
                  data-carrying={carrying?.key === row.key ? '' : undefined}
                  onPointerDown={movable ? (event) => startDrag(event, row, group.key) : undefined}
                >
                  <KeyLine id={row.id} />
                  <span className={styles.cardTop}>
                    <Box row={row} acts={acts} />
                    <Name row={row} acts={acts} hideKey />
                  </span>
                  <Meta row={row} result={result} acts={acts} />
                </li>
              ))}
              {group.rows.length ? null : <li className={styles.laneEmpty}>Nothing here</li>}
            </LaneCards>
          </section>
        ))}
      </div>
      {ghost
        ? createPortal(
            <div className={styles.dragGhost} style={{ left: `${ghost.x}px`, top: `${ghost.y}px` }} aria-hidden="true">
              {ghost.label}
            </div>,
            document.body,
          )
        : null}
      {acts.editable && onHeight ? <HeightSplit boardRef={boardRef} height={height} onDrag={setDragged} onHeight={onHeight} /> : null}
    </>
  );
}

/**
 * A lane's cards, scrolling inside the board's height: with more below than it shows, its foot fades and goes to the
 * app's wisp, as a ```board's lane does (editor/boards/height.ts `laneFoot`). While the board's height is dragged the
 * plain fade does, since a filter for every pixel of the drag would be made and thrown away.
 */
function LaneCards({ still, children }: { still: boolean; children: ReactNode }) {
  const ref = useRef<HTMLUListElement>(null);
  useEffect(() => {
    const stack = ref.current;
    if (!stack) return;
    const foot = () => {
      const more = stack.scrollHeight - stack.clientHeight - stack.scrollTop > 4;
      stack.toggleAttribute('data-more', more);
      const smoke = more && !still ? wispFoot(stack.offsetHeight, stack.offsetWidth) : null;
      if (smoke) {
        stack.style.filter = smoke;
        stack.style.setProperty('--query-lane-fade', `${wispFootFade(stack.offsetHeight)}px`);
      } else {
        stack.style.removeProperty('filter');
        stack.style.removeProperty('--query-lane-fade');
      }
    };
    foot();
    stack.addEventListener('scroll', foot, { passive: true });
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(foot);
    observer?.observe(stack);
    return () => {
      stack.removeEventListener('scroll', foot);
      observer?.disconnect();
    };
  }, [still, children]);
  return (
    <ul ref={ref} className={styles.cards}>
      {children}
    </ul>
  );
}

/**
 * The line under a query's board, which sets how tall its lanes are: the ```board's divider (editor/boards/divider.ts,
 * Glacier's split-pane divider), dragged, stepped with the arrow keys, sent to either end with Home and End, and put
 * back with a double tap. The height is the lanes' own ems, written into the fence when the finger lifts.
 */
function HeightSplit({
  boardRef,
  height,
  onDrag,
  onHeight,
}: {
  boardRef: RefObject<HTMLDivElement | null>;
  height: number | null;
  onDrag: (height: number | null) => void;
  onHeight: (height: number | null) => void;
}) {
  const [dragging, setDragging] = useState(false);
  /** How tall the lanes are drawn now, in their ems. */
  const drawn = (): { ems: number; em: number } => {
    const lane = boardRef.current?.querySelector<HTMLElement>(`.${styles.lane}`);
    const em = lane ? parseFloat(window.getComputedStyle(lane).fontSize) || 16 : 16;
    if (height !== null) return { ems: height, em };
    const px = lane?.getBoundingClientRect().height ?? 0;
    return { ems: px > 0 ? px / em : BOARD_HEIGHT.min, em };
  };
  const press = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.button !== 0 && event.pointerType === 'mouse') return;
    event.preventDefault();
    event.stopPropagation();
    const { ems: from, em } = drawn();
    const startY = event.clientY;
    const id = event.pointerId;
    let now = from;
    let edge: 'min' | 'max' | null = null;
    setDragging(true);
    const move = (moving: PointerEvent) => {
      if (moving.pointerId !== id) return;
      moving.preventDefault();
      const wanted = from + (moving.clientY - startY) / em;
      now = clampHeight(wanted);
      onDrag(now);
      // A buzz at either end, as Glacier's divider gives, so the finger knows it can go no further.
      const at = wanted <= BOARD_HEIGHT.min ? 'min' : wanted >= BOARD_HEIGHT.max ? 'max' : null;
      if (at !== edge) {
        edge = at;
        if (at) fireNativeHaptic('medium');
      }
    };
    const still = (touching: TouchEvent) => {
      if (touching.cancelable) touching.preventDefault();
    };
    const done = (write: boolean) => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
      window.removeEventListener('touchmove', still);
      setDragging(false);
      onDrag(null);
      if (write && Math.abs(now - from) >= 0.5) onHeight(now);
    };
    const up = (lifting: PointerEvent) => {
      if (lifting.pointerId === id) done(true);
    };
    const cancel = (cancelling: PointerEvent) => {
      if (cancelling.pointerId === id) done(false);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    window.addEventListener('touchmove', still, { passive: false });
  };
  const key = (event: KeyboardEvent<HTMLDivElement>) => {
    const now = drawn().ems;
    const next =
      event.key === 'ArrowUp' ? now - 1 : event.key === 'ArrowDown' ? now + 1 : event.key === 'Home' ? BOARD_HEIGHT.min : event.key === 'End' ? BOARD_HEIGHT.max : null;
    if (next === null) return;
    event.preventDefault();
    onHeight(clampHeight(next));
  };
  return (
    <div
      className={styles.split}
      role="separator"
      aria-orientation="horizontal"
      aria-label="Board height"
      aria-valuemin={BOARD_HEIGHT.min}
      aria-valuemax={BOARD_HEIGHT.max}
      aria-valuenow={height ?? undefined}
      tabIndex={0}
      title="Drag to resize the board"
      data-dragging={dragging ? '' : undefined}
      onPointerDown={press}
      onDoubleClick={(event) => {
        event.preventDefault();
        onHeight(null);
      }}
      onKeyDown={key}
    >
      <span className={styles.grip} aria-hidden="true" />
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
