import { useMemo, useRef } from 'react';
import { markGroups, type MarkRow } from './marks.ts';
import { Drawn } from './MarksTable.tsx';
import styles from './CheatSheet.module.css';

/**
 * The cheat sheet: every formatting character, and nothing else (Matt: "redo the UI for the cheatsheet dont include
 * anything but formatting characters and condense the UI and bring in more organization and structure").
 *
 * It began as the guide's table with the spoken rules under it, which made it a second tutorial rather than something
 * to glance at. What is left is the marks: a line of chips to jump between the groups, then a group at a time, each
 * row the mark, what to type and how it comes out, three to a line where the phone is wide enough. The rows are
 * `guide/marks.ts` still, so a plugin switched off is not promised here and a new mark arrives by itself.
 *
 * The voice cues live where they are taught, one row above this in Settings > Help: the tutorial says them out loud
 * and ticks them off, which a table cannot do.
 */
export function CheatSheet() {
  const groups = useMemo(() => markGroups(), []);
  const sheet = useRef<HTMLDivElement>(null);

  /** The chips are a way down a long page: the group's heading goes to the top of whatever is scrolling. */
  const jump = (title: string) => {
    sheet.current?.querySelector(`[data-group="${CSS.escape(title)}"]`)?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  return (
    <div ref={sheet} className={styles.sheet}>
      <nav className={styles.chips} aria-label="The groups of marks">
        {groups.map((group) => (
          <button key={group.title} type="button" className={styles.chip} onClick={() => jump(group.title)}>
            {group.title}
          </button>
        ))}
      </nav>

      {groups.map((group) => (
        <section key={group.title} className={styles.group} data-group={group.title}>
          <h2 className={styles.title}>{group.title}</h2>
          <div className={styles.rows}>
            {group.rows.map((row) => (
              <Row key={row.name} row={row} />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

/** One mark: what it is, what to type, and the same line as the note draws it. */
function Row({ row }: { row: MarkRow }) {
  return (
    <div className={styles.row}>
      <code className={styles.symbol}>{row.symbol}</code>
      <div className={styles.words}>
        <p className={styles.name}>{row.name}</p>
        <pre className={styles.typed}>{row.typed}</pre>
        <div className={styles.shown}>
          <Drawn row={row} />
        </div>
      </div>
    </div>
  );
}
