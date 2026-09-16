import { useMemo } from 'react';
import { markGroups, type MarkRow } from './marks.ts';
import styles from './MarksTable.module.css';

/**
 * The guide's table of marks: every way a note can be formatted, what to type,
 * how it comes out, and how to say it while recording (Matt: "create a guide
 * page, it should show every formatting mode we have in a table and show you
 * an example of how it works").
 *
 * A row is the mark, the line to type with its marks visible, and the same
 * line drawn as the note draws it, so the two sit side by side and the mark
 * itself is read off the example. The rows come from guide/marks.ts, which
 * reads the switched-on plugins, so Glyph's own marks are listed with the
 * app's and a plugin switched off is never promised.
 *
 * On a phone it is two columns, "you type" and "it reads"; the marks stay
 * visible in both, since that is what the editor does.
 */
export function MarksTable() {
  const groups = useMemo(() => markGroups(), []);
  return (
    <div className={styles.table}>
      {groups.map((group) => (
        <section key={group.title} className={styles.group}>
          <h2 className={styles.groupTitle}>{group.title}</h2>
          <p className={styles.groupLead}>{group.lead}</p>
          <div className={styles.rows} role="table" aria-label={`${group.title}: what to type, and how it reads`}>
            <div className={styles.head} role="row">
              <span role="columnheader">You type</span>
              <span role="columnheader">It reads</span>
            </div>
            {group.rows.map((row) => (
              <div key={row.name} className={styles.row} role="row">
                <div className={styles.typed} role="cell">
                  <code className={styles.symbol}>{row.symbol}</code>
                  <pre className={styles.code}>{row.typed}</pre>
                </div>
                <div className={styles.shown} role="cell">
                  <span className={styles.name}>{row.name}</span>
                  <Shown row={row} />
                  {row.say ? <span className={styles.say}>{row.say}</span> : null}
                </div>
              </div>
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

/** The example as the note draws it: one line, in the mark's own look. */
function Shown({ row }: { row: MarkRow }) {
  switch (row.looks) {
    case 'h1':
      return <span className={`${styles.example} ${styles.h1}`}>{row.words}</span>;
    case 'h2':
      return <span className={`${styles.example} ${styles.h2}`}>{row.words}</span>;
    case 'h3':
      return <span className={`${styles.example} ${styles.h3}`}>{row.words}</span>;
    case 'bold':
      return <strong className={styles.example}>{row.words}</strong>;
    case 'italic':
      return <em className={styles.example}>{row.words}</em>;
    case 'both':
      return (
        <strong className={styles.example}>
          <em>{row.words}</em>
        </strong>
      );
    case 'struck':
      return <s className={styles.example}>{row.words}</s>;
    case 'code':
      return <code className={`${styles.example} ${styles.mono}`}>{row.words}</code>;
    case 'link':
      return <span className={`${styles.example} ${styles.link}`}>{row.words}</span>;
    case 'quote':
      return <span className={`${styles.example} ${styles.quote}`}>{row.words}</span>;
    case 'bullet':
      return (
        <span className={styles.example}>
          <span className={styles.marker}>-</span> {row.words}
        </span>
      );
    case 'number':
      return (
        <span className={styles.example}>
          <span className={styles.marker}>1.</span> {row.words}
        </span>
      );
    case 'todo':
    case 'done':
      return (
        <span className={styles.example}>
          <span className={styles.box}>{row.looks === 'done' ? '×' : ''}</span>
          <span className={row.looks === 'done' ? styles.doneWords : undefined}>{row.words}</span>
        </span>
      );
    // A note on a mark: the words as the doubt draws them, the ring that stands for the brackets, and the panel a tap
    // on either of them opens (editor/markNotes.ts).
    case 'note':
      return (
        <span className={styles.example}>
          <span className={styles.noted}>{row.words}</span>
          <span className={styles.ring} aria-hidden="true">
            i
          </span>
          <span className={styles.panel}>{row.note}</span>
        </span>
      );
    case 'rule':
      return <span className={`${styles.example} ${styles.rule}`} aria-label="a line across the page" />;
    case 'table':
      return (
        <table className={`${styles.example} ${styles.grid}`}>
          <tbody>
            <tr>
              <th>What</th>
              <th>Packed</th>
            </tr>
            <tr>
              <td>Tent</td>
              <td>Yes</td>
            </tr>
          </tbody>
        </table>
      );
    case 'picture':
      return (
        <span className={styles.example}>
          <span className={styles.frame} aria-hidden="true" />
          <span className={styles.caption}>{row.words}</span>
        </span>
      );
    case 'fence':
      return <pre className={`${styles.example} ${styles.block}`}>{row.words}</pre>;
    case 'wisp':
      // Smoke, as the editor draws a spoiler: unreadable until the caret is in it.
      return <span className={`${styles.example} ${styles.smoke}`}>{row.words}</span>;
    default:
      // A plugin's own look, from the CSS it declares (plugins/types.ts `FormatLook`).
      return (
        <span className={styles.example}>
          <span style={cssToStyle(row.css)}>{row.words}</span>
        </span>
      );
  }
}

/** A plugin's look, as its own CSS text, turned into the style this page can hand React. */
function cssToStyle(css: string | undefined): Record<string, string> {
  const style: Record<string, string> = {};
  for (const part of (css ?? '').split(';')) {
    const at = part.indexOf(':');
    if (at < 0) continue;
    const name = part.slice(0, at).trim();
    const value = part.slice(at + 1).trim();
    if (!name || !value) continue;
    style[name.startsWith('--') ? name : name.replace(/-([a-z])/g, (_, letter: string) => letter.toUpperCase())] = value;
  }
  return style;
}
