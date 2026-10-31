import type { ReactNode } from 'react';
import { readBoard } from '../../src/app/core/boards/fence.ts';
import { itemsIn } from '../../src/app/core/boards/items.ts';
import { readComments, type Thread } from '../../src/app/core/comments/format.ts';
import { readQuery } from '../../src/app/core/query/read.ts';
import { libraryOf, type Library as QueryLibrary } from '../../src/app/core/query/records.ts';
import { KIND_WORDS, runQuery, type Cell, type QueryResult, type Row } from '../../src/app/core/query/run.ts';
import { formOf, type FormField } from '../../src/read/form.ts';
import { relativeHref } from './links.ts';
import type { Library, Page } from './library.ts';
import styles from './site.module.css';

/**
 * The fences a note holds that are not code, drawn for a site that cannot run them (docs/MARKDOWN_FIRST.md §7, the
 * "Publisher" column; §8 "static fallbacks per fence"):
 *
 * - ```query: run at build time over every page of the site with the app's own engine (core/query, the one the web
 *   app's editor ran), and drawn as the table, list, board, count or calendar it asks for, each row a link to its note.
 *   "Today" is the day of the build. A query that cannot be read says what is wrong with it, as the editor does.
 * - ```form: a read-only description of its fields. A form takes answers only through a Ghost.md share link and the
 *   service (docs/FORMS.md), and the page says so.
 * - ```rules and ```comments: hidden behind a toggle (`<details>`, no script), the comments read as threads.
 * - ```board: its lanes as headings, each card's words looked up by its anchor in the note.
 * - ```gantt is the reader's own readable list (read/gantt.ts), ```mermaid stays its code: the site carries no scripts
 *   from anywhere but itself, and mermaid.js is not worth the weight of every page.
 *
 * A `[Label](ghost:…)` button is already a plain span on the reader page (Rendered.tsx `safeHref`): inert here too.
 */

export interface FenceContext {
  page: Page;
  library: Library;
  queries: QueryLibrary;
  today: string;
  /** The page a query's record is in, by its id, which is its file. */
  pageById: Map<string, Page>;
}

/**
 * A page's words as the query engine reads a note: its text, and for a ticket in the merged one-block shape, where the
 * key is `issue:` and `id:` is the library's, the key written as `id:` so the engine (which reads the shape on disk
 * today, core/properties.ts `ticketIdOf`) finds it.
 */
function queryText(page: Page): string {
  if (page.front.blocks !== 1 || !page.front.page.issue) return page.text;
  return page.text.replace(/^id[ \t]*:.*$/m, `id: ${page.front.page.issue}`);
}

/** The query engine's library, built once per site: every page as a note, its id its file. */
export function queryLibraryOf(library: Library): { queries: QueryLibrary; pageById: Map<string, Page> } {
  const pageById = new Map(library.pages.map((page) => [page.file, page] as const));
  const queries = libraryOf(library.pages.map((page) => ({ id: page.file, body: queryText(page), createdAt: page.createdAt, updatedAt: page.updatedAt })));
  return { queries, pageById };
}

function cellText(cell: Cell): string {
  switch (cell.kind) {
    case 'empty':
      return '';
    case 'text':
    case 'number':
    case 'status':
      return cell.text;
    case 'day':
      return cell.day;
    case 'priority':
      return cell.name;
    case 'people':
      return cell.names.map((name) => `@${name}`).join(' ');
    case 'list':
      return cell.items.map((item) => (cell.tags ? `#${item}` : item)).join(', ');
    case 'bool':
      return cell.on ? 'Done' : 'Not done';
  }
}

function rowLink(row: Row, ctx: FenceContext, children: ReactNode): ReactNode {
  const page = ctx.pageById.get(row.noteId);
  if (!page || page === ctx.page) return <span>{children}</span>;
  return <a href={relativeHref(ctx.page.href, page.href)}>{children}</a>;
}

function queryRows(result: QueryResult, rows: readonly Row[], ctx: FenceContext): ReactNode {
  if (result.show === 'table') {
    return (
      <table>
        <thead>
          <tr>
            {result.columns.map((column) => (
              <th key={column.field}>{column.label}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.key} data-overdue={row.overdue ? '' : undefined}>
              {row.cells.map((cell, i) => (
                <td key={i} data-kind={cell.kind}>
                  {i === result.opens ? rowLink(row, ctx, cellText(cell) || row.name) : cellText(cell)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    );
  }
  return (
    <ul className={styles.queryList}>
      {rows.map((row) => (
        <li key={row.key} data-done={row.done ? '' : undefined}>
          {row.done !== null ? <input type="checkbox" checked={row.done} disabled readOnly aria-label={row.done ? 'Done' : 'To do'} /> : null}
          {rowLink(row, ctx, row.id ? `${row.id} ${row.name}` : row.name)}
          {row.cells
            .map((cell, i) => (i === result.opens ? '' : cellText(cell)))
            .filter(Boolean)
            .map((text, i) => (
              <span key={i} className={styles.queryMeta}>
                {text}
              </span>
            ))}
        </li>
      ))}
    </ul>
  );
}

/** A ```query fence: its result, drawn once. */
export function queryFence(code: string, ctx: FenceContext): ReactNode {
  const reading = readQuery(code);
  if (!reading.query) {
    return (
      <div className={styles.fenceBox} data-fence="query">
        <p className={styles.fenceNote}>This query can’t be read: {reading.problem.message}</p>
        <pre>
          <code>{code}</code>
        </pre>
      </div>
    );
  }
  const result = runQuery(reading.query, ctx.queries, ctx.today);
  const shown = result.groups.reduce((n, group) => n + group.rows.length, 0);
  return (
    <div className={styles.fenceBox} data-fence="query" data-show={result.show}>
      <p className={styles.fenceNote}>
        {KIND_WORDS[result.kind]}: {result.matched === shown ? result.matched : `${shown} of ${result.matched}`} · run on {result.today}
      </p>
      {result.warnings.map((warning, i) => (
        <p key={i} className={styles.fenceNote}>
          {warning}
        </p>
      ))}
      {result.show === 'count' ? (
        <p className={styles.queryCount}>{result.matched}</p>
      ) : result.show === 'gantt' && result.gantt ? (
        <pre data-lang="mermaid">
          <code>{result.gantt.code}</code>
        </pre>
      ) : result.group || result.show === 'board' || result.show === 'calendar' ? (
        <div className={result.show === 'board' ? styles.queryBoard : undefined}>
          {result.groups.map((group) => (
            <section key={group.key}>
              <h4>{group.label || (result.show === 'calendar' ? 'No day' : '')}</h4>
              {queryRows(result, group.rows, ctx)}
            </section>
          ))}
        </div>
      ) : (
        queryRows(result, result.groups.flatMap((group) => group.rows), ctx)
      )}
      {result.totals.length ? <p className={styles.fenceNote}>{result.totals.map((total) => `${total.label}: ${total.text}`).join(' · ')}</p> : null}
    </div>
  );
}

function fieldKind(field: FormField): string {
  switch (field.kind) {
    case 'short':
      return 'a line';
    case 'long':
      return 'a paragraph';
    case 'choice':
      return `one of ${field.options.join(', ')}`;
    case 'email':
      return 'an email address';
    case 'file':
      return 'a file';
  }
}

/** A ```form fence: its fields, read and not filled. */
export function formFence(code: string): ReactNode {
  const def = formOf(`\`\`\`form\n${code}\n\`\`\``);
  return (
    <div className={styles.fenceBox} data-fence="form">
      <p className={styles.fenceNote}>A form. It takes answers through a Ghost.md share link, not on this site.</p>
      {def?.fields.length ? (
        <ul className={styles.formFields}>
          {def.fields.map((field) => (
            <li key={field.label}>
              <strong>{field.label}</strong> — {fieldKind(field)}
              {field.required ? ', required' : ''}
            </li>
          ))}
        </ul>
      ) : null}
      {def?.button ? <p className={styles.fenceNote}>Button: {def.button}</p> : null}
    </div>
  );
}

function thread(t: Thread): ReactNode {
  return (
    <li key={t.id} data-resolved={t.resolved ? '' : undefined}>
      <p>
        <strong>{t.head.by}</strong> <time dateTime={t.head.at}>{t.head.at.replace('T', ' ').replace(/Z$/, ' UTC')}</time>
      </p>
      <p>{t.head.words}</p>
      {t.replies.length ? (
        <ul>
          {t.replies.map((reply, i) => (
            <li key={i}>
              <p>
                <strong>{reply.by}</strong> <time dateTime={reply.at}>{reply.at.replace('T', ' ').replace(/Z$/, ' UTC')}</time>
              </p>
              <p>{reply.words}</p>
            </li>
          ))}
        </ul>
      ) : null}
      {t.resolved ? <p className={styles.fenceNote}>Resolved by {t.resolved.by}</p> : null}
    </li>
  );
}

/** A ```comments fence: its threads, behind a toggle. */
export function commentsFence(code: string): ReactNode {
  const read = readComments(`\`\`\`comments\n${code}\n\`\`\``);
  const open = read.threads.filter((t) => !t.resolved).length;
  return (
    <details className={styles.fenceDetails} data-fence="comments">
      <summary>
        {read.threads.length} {read.threads.length === 1 ? 'comment' : 'comments'}
        {open !== read.threads.length ? ` (${open} open)` : ''}
      </summary>
      <ul className={styles.threads}>{read.threads.map(thread)}</ul>
    </details>
  );
}

/** A ```rules fence: its sentences, behind a toggle. */
export function rulesFence(code: string): ReactNode {
  const lines = code.split('\n').filter((line) => line.trim() !== '');
  return (
    <details className={styles.fenceDetails} data-fence="rules">
      <summary>
        {lines.length} {lines.length === 1 ? 'rule' : 'rules'}
      </summary>
      <ul>
        {lines.map((line, i) => (
          <li key={i}>{line.trim()}</li>
        ))}
      </ul>
    </details>
  );
}

/** A ```board fence: its lanes as headings over their cards' words. */
export function boardFence(code: string, page: Page): ReactNode {
  const items = new Map(itemsIn(page.text).map((item) => [item.id, item] as const));
  const columns = readBoard(code, new Set(items.keys()));
  return (
    <div className={`${styles.fenceBox} ${styles.board}`} data-fence="board">
      {columns.map((column) => (
        <section key={column.name}>
          <h4>{column.name}</h4>
          <ul>
            {column.cards.map((id) => {
              const item = items.get(id);
              return (
                <li key={id} data-done={item?.done ? '' : undefined}>
                  {item?.text ?? id}
                </li>
              );
            })}
          </ul>
        </section>
      ))}
    </div>
  );
}

/** The fences this site draws itself; undefined leaves one to the reader (Rendered.tsx `SiteDraw.fence`). */
export function fenceFor(ctx: FenceContext): (info: string, code: string) => ReactNode | undefined {
  return (info, code) => {
    const word = info.trim().split(/\s+/)[0]?.toLowerCase() ?? '';
    switch (word) {
      case 'query':
        return queryFence(code, ctx);
      case 'form':
        return formFence(code);
      case 'comments':
        return commentsFence(code);
      case 'rules':
        return rulesFence(code);
      case 'board':
        return boardFence(code, ctx.page);
      default:
        return undefined;
    }
  };
}
