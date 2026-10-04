/**
 * The change from one version of a note to the next, line by line, as git takes it: Myers' shortest edit script
 * (E. W. Myers, "An O(ND) Difference Algorithm and Its Variations", 1986). A version in a versions file is this
 * change written out (core/versions/file.ts), so a file holds each version's new lines and not the whole note again.
 *
 * The shared lines at the top and the foot are taken off before the search, which is where nearly every edit of a
 * note leaves most of it; the search then runs over what is left.
 */

/** One step of a change: keep `n` lines, take one out, or put one in. */
export type Step = { keep: number } | { del: string } | { add: string };

/** A note's text as lines, split so that joining them with `\n` gives the text back exactly. */
export const linesOf = (text: string): string[] => text.split('\n');

/** The steps that turn `before` into `after`. Runs of kept lines are one step. */
export function diffLines(before: readonly string[], after: readonly string[]): Step[] {
  let top = 0;
  while (top < before.length && top < after.length && before[top] === after[top]) top += 1;
  let foot = 0;
  while (foot < before.length - top && foot < after.length - top && before[before.length - 1 - foot] === after[after.length - 1 - foot]) foot += 1;
  const a = before.slice(top, before.length - foot);
  const b = after.slice(top, after.length - foot);

  const steps: Step[] = [];
  const keep = (n: number) => {
    if (n <= 0) return;
    const last = steps[steps.length - 1];
    if (last && 'keep' in last) last.keep += n;
    else steps.push({ keep: n });
  };
  keep(top);
  for (const step of middle(a, b)) {
    if ('keep' in step) keep(step.keep);
    else steps.push(step);
  }
  keep(foot);
  return steps;
}

/** The shortest edit script from `a` to `b`, by Myers' greedy search over diagonals, then traced back. */
function middle(a: readonly string[], b: readonly string[]): Step[] {
  const n = a.length;
  const m = b.length;
  if (n === 0) return b.map((line) => ({ add: line }));
  if (m === 0) return a.map((line) => ({ del: line }));
  const max = n + m;
  const offset = max;
  const v = new Int32Array(2 * max + 2);
  const trace: Int32Array[] = [];
  let found = -1;
  for (let d = 0; d <= max && found < 0; d += 1) {
    trace.push(v.slice());
    for (let k = -d; k <= d; k += 2) {
      let x = k === -d || (k !== d && v[offset + k - 1]! < v[offset + k + 1]!) ? v[offset + k + 1]! : v[offset + k - 1]! + 1;
      let y = x - k;
      while (x < n && y < m && a[x] === b[y]) {
        x += 1;
        y += 1;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) {
        found = d;
        break;
      }
    }
  }
  // Back from the end along the path the search took, collecting its moves in reverse.
  const reversed: Step[] = [];
  let x = n;
  let y = m;
  for (let d = found; d > 0; d -= 1) {
    const was = trace[d]!;
    const k = x - y;
    const down = k === -d || (k !== d && was[offset + k - 1]! < was[offset + k + 1]!);
    const prevK = down ? k + 1 : k - 1;
    const prevX = was[offset + prevK]!;
    const prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      reversed.push({ keep: 1 });
      x -= 1;
      y -= 1;
    }
    if (down) reversed.push({ add: b[prevY]! });
    else reversed.push({ del: a[prevX]! });
    x = prevX;
    y = prevY;
  }
  while (x > 0 && y > 0) {
    reversed.push({ keep: 1 });
    x -= 1;
    y -= 1;
  }
  const steps: Step[] = [];
  for (let at = reversed.length - 1; at >= 0; at -= 1) {
    const step = reversed[at]!;
    const last = steps[steps.length - 1];
    if ('keep' in step && last && 'keep' in last) last.keep += step.keep;
    else steps.push('keep' in step ? { keep: step.keep } : step);
  }
  return steps;
}

/** `before` with `steps` applied; null where the steps do not fit it (a file changed by hand, or a broken one). */
export function applySteps(before: readonly string[], steps: readonly Step[]): string[] | null {
  const out: string[] = [];
  let at = 0;
  for (const step of steps) {
    if ('keep' in step) {
      if (at + step.keep > before.length) return null;
      for (let i = 0; i < step.keep; i += 1) out.push(before[at + i]!);
      at += step.keep;
    } else if ('del' in step) {
      if (before[at] !== step.del) return null;
      at += 1;
    } else out.push(step.add);
  }
  // What is left of the version before is kept: a change written without its last keep still reads.
  for (; at < before.length; at += 1) out.push(before[at]!);
  return out;
}

/** How many lines a change puts in and takes out, for a version's "+3 −1". */
export function countSteps(steps: readonly Step[]): { added: number; removed: number } {
  let added = 0;
  let removed = 0;
  for (const step of steps) {
    if ('add' in step) added += 1;
    else if ('del' in step) removed += 1;
  }
  return { added, removed };
}

/** A version's lines; none at all before the first version, rather than one empty line. */
export const linesFrom = (text: string | null): string[] => (text === null ? [] : linesOf(text));

/**
 * The first line a version put in or took out, against the version before it - or against nothing, for a note's
 * first - for the version's line on a timeline (editor/VersionHistory.tsx, notes/OrganizationLog.tsx). Null when it
 * changed no line that says anything: a name given, or blank lines alone.
 */
export function firstChange(before: string | null, after: string): { kind: 'add' | 'del'; text: string } | null {
  for (const step of diffLines(linesFrom(before), linesOf(after))) {
    if ('add' in step && step.add.trim()) return { kind: 'add', text: step.add.trim() };
    if ('del' in step && step.del.trim()) return { kind: 'del', text: step.del.trim() };
  }
  return null;
}
