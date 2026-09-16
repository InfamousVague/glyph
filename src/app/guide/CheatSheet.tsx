import { useMemo } from 'react';
import { MarksTable } from './MarksTable.tsx';
import { saidGroups } from './cheatSheet.ts';
import styles from './CheatSheet.module.css';

/**
 * Every formatting rule Glyph has, in one page to look things up in (Matt: "i want the glossary / lexicon / cheat
 * sheet added for all formatting rules in the help section of the more menu").
 *
 * Two halves, because a note is written two ways. **What you type** is the table of marks that the guide already had
 * (guide/MarksTable.tsx): the mark, a line using it, and the same line drawn as the note draws it. **What you say**
 * is every spoken rule (guide/cheatSheet.ts), each with words that work, in the order the tutorial teaches them.
 *
 * Both halves are read from what the app actually does - the plugin registry and the tutorial's own lessons - so a
 * mark from a switched-off plugin is not promised here, and a rule cannot say one thing on this page and another in
 * the recorder.
 */
export function CheatSheet() {
  const groups = useMemo(() => saidGroups(), []);
  return (
    <div className={styles.sheet}>
      <p className={styles.lead}>Every way to format a note: the marks you type, and the words you say while recording.</p>

      <section className={styles.part}>
        <h2 className={styles.partTitle}>What you type</h2>
        <p className={styles.lead}>
          Any of Glyph’s own marks can carry a note: write it in brackets straight after, like ??the deposit??(Sam said 400), and tapping the words shows it.
        </p>
        <MarksTable />
      </section>

      <section className={styles.part}>
        <h2 className={styles.partTitle}>What you say</h2>
        {groups.map((group) => (
          <section key={group.chapter} className={styles.group}>
            <h3 className={styles.groupTitle}>{group.chapter}</h3>
            {group.rules.map((rule) => (
              <div key={`${group.chapter}-${rule.title}`} className={`${styles.rule} ${rule.spoken ? '' : styles.tip}`}>
                <p className={styles.name}>{rule.title}</p>
                <p className={styles.teach}>{rule.teach}</p>
                {rule.say.length ? (
                  <div className={styles.say}>
                    {rule.say.map((phrase, index) => (
                      <p key={`${phrase}-${index}`} className={styles.phrase}>
                        “{phrase}”
                      </p>
                    ))}
                  </div>
                ) : null}
              </div>
            ))}
          </section>
        ))}
      </section>
    </div>
  );
}
