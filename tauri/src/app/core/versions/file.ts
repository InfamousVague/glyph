import { applySteps, countSteps, diffLines, linesOf, type Step } from './diff.ts';

/**
 * A note's versions file (Matt: "create a special file like a versions files that efficiently tracks changes in a way
 * that can be shared via a file it doesn't need to be super human readable but it should be at least a bit (like a
 * yarn lock)"): `<Title>.versions`, beside the note's `.md`, holding every version kept of it.
 *
 *     # Ghost.md versions 1
 *     # note gho-7f3a
 *
 *     v1 2026-10-04T15:20:01.000Z matt 3f9a21c0
 *       +# Launch plan
 *       +- book the venue
 *     v2 2026-10-04T16:02:44.000Z matt 8c0d4e11 "Before the review"
 *       =1
 *       -- book the venue
 *       +- book the venue (done)
 *
 * A version is its head line - its number, when, who, the hash of the note's whole text then, and a name if it was
 * given one - and under it, indented, the change from the version before: `=N` keeps N lines, `-` takes a line out and
 * `+` puts one in, each line as it was. So the file grows by what changed, not by the note each time, and a person can
 * still read what each version did. A version marked `full` holds the whole note rather than a change: one in every
 * `FULL_EVERY`, so a file that lost its oldest versions to `MOST_VERSIONS` still starts somewhere, and a damaged
 * version costs only the ones up to the next full one.
 *
 * Reading a file rebuilds each version and checks it against its hash; a version that does not come out as written is
 * dropped, never shown as something it was not. Two devices' files are merged version by version (`mergeFiles`), by
 * when each was kept, who kept it and its hash, so a timeline kept on two devices is one timeline after a sync.
 */

export const FORMAT = 1;
const MAGIC = '# Ghost.md versions';
/** A whole note rather than a change, every this many versions. */
export const FULL_EVERY = 50;
/** The most versions a file keeps: the oldest go first. */
export const MOST_VERSIONS = 1000;

export interface Version {
  /** Its place in the file, from 1. */
  n: number;
  /** When it was kept, in ms. */
  at: number;
  /** Who kept it: their handle, or `me` without an account. */
  by: string;
  /** The hash of the note's text then (`hashText`). */
  hash: string;
  /** The name it was given, if any. */
  label?: string;
  /** The note's whole text then, rebuilt. */
  text: string;
  /** How many lines it put in and took out against the version before. */
  added: number;
  removed: number;
}

export interface VersionsFile {
  noteId: string;
  versions: Version[];
  /** Versions in the file that did not come out as their hash says, and were left out. */
  damaged: number;
}

/** FNV-1a over the text's UTF-16 units, as eight hex digits: enough to tell a version rebuilt wrong from one rebuilt right. */
export function hashText(text: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

/** Who may keep a version, as a word with no spaces in it. */
const who = (by: string) => by.replace(/\s+/g, '-') || 'me';

// --- reading ---------------------------------------------------------------------------

const HEAD = /^v(\d+) (\S+) (\S+) ([0-9a-f]{8})( full)?(?: (".*"))?$/;

/** A versions file read and every version in it rebuilt; null where the text is not a versions file at all. */
export function readFile(file: string): VersionsFile | null {
  const lines = file.split('\n');
  if (!lines[0]?.startsWith(MAGIC)) return null;
  let noteId = '';
  const versions: Version[] = [];
  let damaged = 0;
  let previous: string[] | null = [];
  let head: { at: number; by: string; hash: string; label?: string; full: boolean } | null = null;
  let steps: Step[] = [];

  const close = () => {
    if (!head) return;
    const base = head.full ? [] : previous;
    const rebuilt = base ? applySteps(base, steps) : null;
    const text = rebuilt?.join('\n');
    if (rebuilt && text !== undefined && hashText(text) === head.hash) {
      const changed = head.full && versions.length ? countSteps(diffLines(previous ?? [], rebuilt)) : countSteps(steps);
      versions.push({ n: versions.length + 1, at: head.at, by: head.by, hash: head.hash, ...(head.label ? { label: head.label } : {}), text, ...changed });
      previous = rebuilt;
    } else {
      damaged += 1;
      // The versions after it are changes to one that is not there: none is read until the next full one.
      previous = null;
    }
    head = null;
    steps = [];
  };

  for (const line of lines.slice(1)) {
    if (line.startsWith('# note ')) {
      noteId = line.slice('# note '.length).trim();
      continue;
    }
    if (line.startsWith('#') || (line === '' && !head)) continue;
    const match = HEAD.exec(line);
    if (match) {
      close();
      const at = Date.parse(match[2]!);
      let label: string | undefined;
      try {
        label = match[6] ? (JSON.parse(match[6]) as string) : undefined;
      } catch {
        label = undefined;
      }
      head = { at: Number.isFinite(at) ? at : 0, by: match[3]!, hash: match[4]!, ...(label ? { label } : {}), full: Boolean(match[5]) };
      continue;
    }
    if (!head) continue;
    if (line.startsWith('  =')) steps.push({ keep: Number(line.slice(3)) || 0 });
    else if (line.startsWith('  -')) steps.push({ del: line.slice(3) });
    else if (line.startsWith('  +')) steps.push({ add: line.slice(3) });
    // A line between versions that is none of these (an empty one, a stray edit): the version is checked by its hash.
  }
  close();
  return { noteId, versions, damaged };
}

// --- writing ---------------------------------------------------------------------------

function stepLines(steps: readonly Step[]): string[] {
  return steps.map((step) => ('keep' in step ? `  =${step.keep}` : 'del' in step ? `  -${step.del}` : `  +${step.add}`));
}

/** The whole file for `versions`, numbered afresh, each written as its change from the one before. */
export function writeFile(noteId: string, versions: readonly Pick<Version, 'at' | 'by' | 'label' | 'text'>[]): string {
  const kept = versions.slice(-MOST_VERSIONS);
  const out = [`${MAGIC} ${FORMAT}`, `# note ${noteId}`, `# A version is the change from the one before it: "=N" keeps N lines, "-" takes a line out, "+" puts one in.`, ''];
  let previous: string[] = [];
  kept.forEach((version, at) => {
    const lines = linesOf(version.text);
    // The first a file holds is always whole, and one in every FULL_EVERY after it.
    const full = at === 0 || at % FULL_EVERY === 0;
    const label = version.label ? ` ${JSON.stringify(version.label)}` : '';
    out.push(`v${at + 1} ${new Date(version.at).toISOString()} ${who(version.by)} ${hashText(version.text)}${full ? ' full' : ''}${label}`);
    out.push(...stepLines(full ? lines.map((add) => ({ add })) : diffLines(previous, lines)));
    previous = lines;
  });
  return `${out.join('\n')}\n`;
}

/**
 * The file with a version of `text` kept at the end, or null where there is nothing to keep: the last version already
 * holds this text, and it is not being given a name. A file that is not a versions file is started again.
 */
export function withVersion(file: string | null, noteId: string, text: string, { at, by, label }: { at: number; by: string; label?: string }): string | null {
  const read = file ? readFile(file) : null;
  const versions = read?.versions ?? [];
  const last = versions[versions.length - 1];
  const name = label?.trim();
  if (last && last.text === text) {
    if (!name || last.label === name) return null;
    // The same words, named now: the name goes on the version that has them, rather than a version of no change.
    return writeFile(noteId, [...versions.slice(0, -1), { ...last, label: name }]);
  }
  return writeFile(noteId, [...versions, { at, by, text, ...(name ? { label: name } : {}) }]);
}

/** A version's key across devices: when it was kept, who kept it and what it held. */
const keyOf = (version: Pick<Version, 'at' | 'by' | 'hash'>) => `${version.at}|${version.by}|${version.hash}`;

/**
 * Two files of one note's versions as one, as a sync meets them (core/sync/notes.ts): every version in either, once,
 * in the order they were kept, and a name given on either side kept. Null where neither is a versions file.
 */
export function mergeFiles(mine: string | null, theirs: string | null, noteId: string): string | null {
  const a = mine ? readFile(mine) : null;
  const b = theirs ? readFile(theirs) : null;
  if (!a && !b) return null;
  const all = new Map<string, Version>();
  for (const version of [...(a?.versions ?? []), ...(b?.versions ?? [])]) {
    const key = keyOf(version);
    const was = all.get(key);
    if (!was || (!was.label && version.label)) all.set(key, version);
  }
  const ordered = [...all.values()].sort((x, y) => x.at - y.at || x.by.localeCompare(y.by) || x.hash.localeCompare(y.hash));
  return writeFile(a?.noteId || b?.noteId || noteId, ordered);
}
