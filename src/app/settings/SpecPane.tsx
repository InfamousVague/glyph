import { ExternalLink } from '@glacier/icons';
import { openLink } from '../core/linkPreview.ts';
import { PaneSection, SettingRow } from './kit/settingsKit.tsx';
import { BASE_SPECS, SPEC, type SpecEntry } from './specification.ts';
import styles from './SpecPane.module.css';

/**
 * The specification, a page of Settings behind About's Help card (GLY-4; docs/DESIGN.md §164): the base Markdown every
 * note is, by link, then every extension and AI fill as a definition, how it is written, the rule, how any other app
 * shows it, and where one pattern is the rule, the pattern itself. The words are settings/specification.ts, held to
 * the code by its test.
 */
export function SpecPane() {
  return (
    <>
      <PaneSection title="The base" description="Every note is standard Markdown first. What follows only adds to it.">
        {BASE_SPECS.map((spec) => (
          <SettingRow key={spec.name} icon={<ExternalLink size={20} />} label={spec.name} hint={spec.about} onPress={() => openLink(spec.url)} />
        ))}
      </PaneSection>
      {SPEC.map((section) => (
        <section key={section.id} className={styles.section} aria-labelledby={`spec-${section.id}`}>
          <h2 id={`spec-${section.id}`} className={styles.title}>
            {section.title}
          </h2>
          <p className={styles.intro}>{section.intro}</p>
          <div className={styles.entries}>
            {section.entries.map((entry) => (
              <Entry key={entry.name} entry={entry} />
            ))}
          </div>
        </section>
      ))}
    </>
  );
}

function Entry({ entry }: { entry: SpecEntry }) {
  return (
    <article className={styles.entry}>
      <h3 className={styles.name} data-findable>
        {entry.name}
      </h3>
      <pre className={styles.written}>
        <code>{entry.written}</code>
      </pre>
      <p className={styles.rule}>{entry.rule}</p>
      <p className={styles.elsewhere}>
        <span className={styles.label}>Elsewhere</span> {entry.elsewhere}
      </p>
      {entry.pattern ? (
        <details className={styles.pattern}>
          <summary className={styles.label}>The pattern</summary>
          <pre className={styles.written}>
            <code>{entry.pattern}</code>
          </pre>
        </details>
      ) : null}
    </article>
  );
}
