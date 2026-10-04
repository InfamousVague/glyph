import { useState } from 'react';
import { ArrowLeft, History, RotateCcw, Share2 } from '@glacier/icons';
import { useToast } from '@glacier/react';
import { agoText } from '../core/markDetails.ts';
import { diffLines, firstChange, linesFrom, linesOf } from '../core/versions/diff.ts';
import type { Version } from '../core/versions/file.ts';
import { keepVersion, setKeepsVersions, useVersions, versionsByDefault } from '../core/versions/record.ts';
import { shareVersionsFile } from '../core/versions/share.ts';
import { SheetField, SheetGroup, SheetHeading, SheetNote, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { authorName, clock, dayOf } from './versionWords.ts';
import styles from './VersionHistory.module.css';

/**
 * A note's version history, a page of its More sheet (editor/NoteSettings.tsx; core/versions/record.ts), drawn as a
 * timeline (Matt: "include a way to view changes on a timeline in app along with the author of the changes"): every
 * version kept, newest first, on a line down the page under the day it was kept, each with who made it, when, how much
 * it changed and the first line it changed. A version opened shows what it changed against the one before, then what
 * going back to it would change against the note now, and Restore. Above the timeline a version is saved by hand with
 * a name; under it the versions file is shared and the history switched off. Restoring keeps a new version with that
 * version's words, as `git revert` does.
 *
 * The timeline's pieces - the author's ring and what a version changed here, its words in versionWords.ts - are
 * shared with an organization's audit log (notes/OrganizationLog.tsx), which draws every note's versions on the same
 * line.
 */

/** How many lines either side of a change are shown, the rest folded into "12 lines the same". */
const CONTEXT = 2;

interface VersionHistoryProps {
  noteId: string;
  title: string;
  /** The note's words now, for what restoring a version would change. */
  current: () => string;
  /** Puts a version's words into the note, through the editor, as one change to undo. */
  onRestore: (text: string, version: Version) => void;
  onBack: () => void;
}

/** Who made a version, as a round mark with their first letter: the same person, the same mark, down the timeline. */
export function Author({ by }: { by: string }) {
  return (
    <span className={styles.author} aria-hidden="true">
      {(by === 'me' ? 'Y' : (by[0] ?? '?')).toUpperCase()}
    </span>
  );
}

/** The timeline: the versions newest first, under the day each was kept. */
function Timeline({ versions, onOpen }: { versions: readonly Version[]; onOpen: (version: Version) => void }) {
  const newest = [...versions].reverse();
  const days: { day: string; versions: Version[] }[] = [];
  for (const version of newest) {
    const day = dayOf(version.at);
    const last = days[days.length - 1];
    if (last && last.day === day) last.versions.push(version);
    else days.push({ day, versions: [version] });
  }
  return (
    <div className={styles.timeline}>
      {days.map(({ day, versions: those }) => (
        <section key={day} className={styles.day} aria-label={day}>
          <h3 className={styles.dayName}>{day}</h3>
          <ol className={styles.entries}>
            {those.map((version) => {
              const before = versions[version.n - 2]?.text ?? null;
              const peek = firstChange(before, version.text);
              return (
                <li key={`${version.n}-${version.hash}`} className={styles.entry}>
                  <button type="button" className={styles.entryButton} onClick={() => onOpen(version)} aria-label={`Version ${version.n}${version.label ? `, ${version.label}` : ''}, by ${authorName(version.by)}, ${agoText(version.at)}`}>
                    <Author by={version.by} />
                    <span className={styles.entryBody}>
                      <span className={styles.entryHead}>
                        <span className={styles.who}>{authorName(version.by)}</span>
                        <span className={styles.when}>{clock(version.at)}</span>
                        {version.label ? <span className={styles.label}>{version.label}</span> : null}
                      </span>
                      <span className={styles.entryWhat}>
                        <span className={styles.counts}>{version.n === 1 ? 'First version' : version.added || version.removed ? `+${version.added} −${version.removed}` : 'Named'}</span>
                        {peek ? (
                          <span className={styles.peek} data-kind={peek.kind}>
                            {peek.kind === 'add' ? '+ ' : '− '}
                            {peek.text}
                          </span>
                        ) : null}
                      </span>
                    </span>
                    <span className={styles.number}>v{version.n}</span>
                  </button>
                </li>
              );
            })}
          </ol>
        </section>
      ))}
    </div>
  );
}

/** The lines that go from `from` to `to`, and the lines that come, with a little of what stays around them. */
export function Change({ from, to, label, same = 'The note says exactly this now.' }: { from: string | null; to: string; label: string; same?: string }) {
  const before = linesFrom(from);
  const steps = diffLines(before, linesOf(to));
  const rows: { kind: 'same' | 'del' | 'add' | 'fold'; text: string; key: string }[] = [];
  let at = 0;
  steps.forEach((step, index) => {
    if ('keep' in step) {
      const lines = before.slice(at, at + step.keep);
      at += step.keep;
      const first = index === 0;
      const last = index === steps.length - 1;
      const head = first ? 0 : CONTEXT;
      const tail = last ? 0 : CONTEXT;
      if (lines.length <= head + tail + 1) lines.forEach((text, i) => rows.push({ kind: 'same', text, key: `${index}-${i}` }));
      else {
        lines.slice(0, head).forEach((text, i) => rows.push({ kind: 'same', text, key: `${index}-h${i}` }));
        const folded = lines.length - head - tail;
        rows.push({ kind: 'fold', text: folded === 1 ? '1 line the same' : `${folded} lines the same`, key: `${index}-fold` });
        lines.slice(lines.length - tail).forEach((text, i) => rows.push({ kind: 'same', text, key: `${index}-t${i}` }));
      }
    } else if ('del' in step) {
      at += 1;
      rows.push({ kind: 'del', text: step.del, key: `${index}-del` });
    } else rows.push({ kind: 'add', text: step.add, key: `${index}-add` });
  });
  if (!rows.some((row) => row.kind === 'add' || row.kind === 'del')) return <SheetNote>{same}</SheetNote>;
  return (
    <ol className={styles.change} aria-label={label}>
      {rows.map((row) => (
        <li key={row.key} className={styles.line} data-kind={row.kind} aria-label={row.kind === 'add' ? `Comes back: ${row.text}` : row.kind === 'del' ? `Goes: ${row.text}` : undefined}>
          <span className={styles.mark} aria-hidden="true">
            {row.kind === 'add' ? '+' : row.kind === 'del' ? '−' : ''}
          </span>
          <span className={styles.words}>{row.kind === 'fold' ? row.text : row.text || ' '}</span>
        </li>
      ))}
    </ol>
  );
}

export function VersionHistory({ noteId, title, current, onRestore, onBack }: VersionHistoryProps) {
  const read = useVersions(noteId);
  const [opened, setOpened] = useState<Version | null>(null);
  const [name, setName] = useState('');
  const { toast } = useToast();
  const versions = read?.versions ?? [];

  if (opened) {
    const before = versions[opened.n - 2]?.text ?? null;
    return (
      <>
        <button type="button" className={styles.back} onClick={() => setOpened(null)}>
          <ArrowLeft /> The timeline
        </button>
        <SheetTitle>
          Version {opened.n}
          {opened.label ? ` · ${opened.label}` : ''}
        </SheetTitle>
        <div className={styles.byline}>
          <Author by={opened.by} />
          <span>
            <span className={styles.who}>{authorName(opened.by)}</span>
            {` · ${new Date(opened.at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}`}
          </span>
        </div>
        <SheetHeading>{opened.n === 1 ? 'The note as it began' : 'What this version changed'}</SheetHeading>
        {opened.n === 1 && !opened.text.trim() ? (
          <SheetNote>It began empty.</SheetNote>
        ) : (
          <Change from={before} to={opened.text} label="What this version changed" same="The same words as the version before, named." />
        )}
        <SheetHeading>Restoring it changes the note like this</SheetHeading>
        <Change from={current()} to={opened.text} label="What restoring changes" />
        <SheetGroup>
          <SheetRow
            icon={RotateCcw}
            label={`Restore version ${opened.n}`}
            hint="The note goes back to these words. Now is kept as a version first, so this can be undone too."
            onPress={() => {
              onRestore(opened.text, opened);
              setOpened(null);
            }}
            disabled={opened.text === current()}
          />
        </SheetGroup>
      </>
    );
  }

  const saveNow = async () => {
    const kept = await keepVersion(noteId, current(), { label: name.trim() || undefined });
    setName('');
    toast({ message: kept ? 'Version saved.' : 'Nothing has changed since the last version.' });
  };

  return (
    <>
      <button type="button" className={styles.back} onClick={onBack}>
        <ArrowLeft /> {title || 'This note'}
      </button>
      <SheetTitle>Version history</SheetTitle>
      <SheetNote>
        {versionsByDefault(noteId)
          ? 'Kept for every note in an organization. A version is saved after a pause in the writing, when you leave the note, and whenever you save one here.'
          : 'A version is saved after a pause in the writing, when you leave the note, and whenever you save one here.'}
      </SheetNote>

      <SheetGroup>
        <SheetField label="Name" value={name} onChange={(e) => setName(e.target.value)} placeholder="What this version is, if anything" autoComplete="off" />
        <SheetRow icon={History} label="Save a version now" onPress={() => void saveNow()} />
      </SheetGroup>

      <SheetHeading>{read === null ? 'Reading the versions…' : versions.length === 1 ? '1 version' : `${versions.length} versions`}</SheetHeading>
      {versions.length ? (
        <Timeline versions={versions} onOpen={setOpened} />
      ) : read ? (
        <SheetNote>None yet. The first is saved as you write.</SheetNote>
      ) : null}
      {read?.damaged ? <SheetNote>{read.damaged === 1 ? 'One version in the file couldn’t be read, and is left out.' : `${read.damaged} versions in the file couldn’t be read, and are left out.`}</SheetNote> : null}

      <SheetGroup>
        <SheetRow
          icon={Share2}
          label="Share the versions file"
          hint={`${(title.trim() || 'Untitled').replace(/[\\/:*?"<>|]+/g, ' ').trim()}.versions, beside the note. Every version, each as what changed.`}
          onPress={() =>
            void shareVersionsFile(noteId, title)
              .then((said) => said && toast({ message: said }))
              .catch((failure: unknown) => toast({ message: failure instanceof Error ? failure.message : 'The file couldn’t be shared.' }))
          }
          disabled={!versions.length}
        />
        <SheetRow
          label="Stop keeping history"
          hint="The versions kept so far stay, and carry on if you switch it on again."
          onPress={() => {
            setKeepsVersions(noteId, false);
            onBack();
          }}
        />
      </SheetGroup>
    </>
  );
}
