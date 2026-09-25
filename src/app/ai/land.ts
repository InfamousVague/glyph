import { ChangeSet } from '@codemirror/state';
import type { EditorView } from '@codemirror/view';
import { fireFelt } from '../core/haptics.ts';
import { addAiChanges, aiEdit, landingField, setLanding, touchedIn, type AiChange, type Landing } from '../editor/aiChanges.ts';
import { wisp } from '../editor/wispArrivals.ts';
import { matchLine, wordDiff } from './landing.ts';

/**
 * The lander: a run's lines into the note, one as each finishes, as tracked
 * changes (editor/aiChanges.ts).
 *
 * It works from the landing state the editor keeps - where the next line
 * goes, where the old words end - so the person can type while it runs and
 * the bookmark moves with their words. Each line is placed by the reading
 * rules in ai/landing.ts: kept where the old line is the same, rewritten
 * word by word where it is nearly the same, added where it is new; the old
 * lines a match passed over are struck. Lines the person wrote while the run
 * was on are theirs: never struck, never rewritten, and a line of the
 * model's that would have replaced one is dropped and counted, so the strip
 * can say so.
 *
 * When the run is done, whatever old words are left below the landed ones
 * are struck, and the finished text (tidied once at the end, its links put
 * back) is read over the landed lines the same way, so a bullet the tidy-up
 * straightened or a link that came back late lands as one more small
 * change rather than a rewrite of everything.
 */

interface OldLine {
  text: string;
  from: number;
  /** The end of the words, before the newline. */
  to: number;
  /** Whether a newline follows. Only the note's last line has none. */
  newline: boolean;
}

let count = 0;
const changeId = () => `c-${Date.now().toString(36)}-${(count += 1)}`;

export interface LanderOptions {
  /** The lines arrive from smoke (editor/wispArrivals.ts), when the person has the wisp on. */
  wisp: boolean;
  /** A tick under the thumb as each line lands. */
  haptic: boolean;
}

/** Where a run's lines were up to, kept across the note being closed and opened again while it runs, with the note as it was before any landed. */
const progress = new Map<string, { landed: number; start: number; cursor: number; oldEnd: number; before: string }>();

export class Lander {
  private landed = 0;
  /** Lines of the model's that were dropped because the person had written over their place. */
  dropped = 0;
  /** The note before the run's first line landed, for the log's Undo. */
  readonly before: string;

  constructor(
    private readonly view: EditorView,
    private readonly runId: string,
    private readonly options: LanderOptions,
    before: string,
  ) {
    // The note was closed and opened again mid-run: carry on where the lines were up to, with the note as it was
    // before the first landed. A landing already set is a fresh start, whatever an earlier lander for this run left.
    const kept = progress.get(runId);
    if (kept && !view.state.field(landingField)) {
      this.landed = kept.landed;
      this.before = kept.before;
      view.dispatch({ effects: setLanding.of({ start: kept.start, cursor: kept.cursor, oldEnd: kept.oldEnd }) });
    } else {
      progress.delete(runId);
      this.before = before;
    }
  }

  private landing(): Landing | null {
    return this.view.state.field(landingField);
  }

  /** Lands the lines the run has finished so far, past the ones already landed. */
  land(lines: readonly string[]): void {
    for (let i = this.landed; i < lines.length; i += 1) this.landOne(lines[i]!);
    this.landed = lines.length;
    this.remember();
  }

  private remember(): void {
    const landing = this.landing();
    if (landing) progress.set(this.runId, { landed: this.landed, start: landing.start, cursor: landing.cursor, oldEnd: landing.oldEnd, before: this.before });
  }

  /** The old lines still ahead of the cursor, with where each sits. */
  private oldLines(landing: Landing): OldLine[] {
    const { doc } = this.view.state;
    const out: OldLine[] = [];
    let at = landing.cursor;
    const end = Math.max(landing.cursor, landing.oldEnd);
    while (at < end) {
      const line = doc.lineAt(at);
      const to = Math.min(line.to, end);
      const newline = to < doc.length && doc.sliceString(to, to + 1) === '\n' && to < end;
      out.push({ text: doc.sliceString(at, to), from: at, to, newline });
      at = newline ? to + 1 : to;
      if (!newline) break;
    }
    return out;
  }

  private dispatch(spec: { changes?: { from: number; to?: number; insert?: string }[]; records?: AiChange[]; cursor: number; oldEnd: number; start?: number }, removed: boolean): void {
    const landing = this.landing();
    // The effect's positions are in the note as it will read after the edit; the start it keeps has to be moved too.
    const moved = spec.changes?.length ? ChangeSet.of(spec.changes, this.view.state.doc.length) : null;
    const start = spec.start ?? (landing ? (moved ? moved.mapPos(landing.start, -1) : landing.start) : spec.cursor);
    this.view.dispatch({
      changes: spec.changes ?? [],
      effects: [...(spec.records?.length ? [addAiChanges.of(spec.records)] : []), setLanding.of({ start, cursor: spec.cursor, oldEnd: Math.max(spec.cursor, spec.oldEnd) })],
      annotations: [aiEdit.of('land'), ...(this.options.wisp && spec.changes?.length ? [wisp.of({ kind: removed ? 'rewrite' : 'heard' })] : [])],
      userEvent: 'ai.land',
    });
    if (this.options.haptic && spec.changes?.length) fireFelt('light');
  }

  /**
   * The old lines up to `until` go: struck in runs, except the ones the
   * person wrote, which are passed over. Answers the cursor after them and
   * how much the note shrank.
   */
  private strike(landing: Landing, old: readonly OldLine[], until: number): { cursor: number; shrank: number } {
    let cursor = landing.cursor;
    let shrank = 0;
    let run: OldLine[] = [];
    const flush = () => {
      if (!run.length) return;
      const first = run[0]!;
      const last = run[run.length - 1]!;
      const from = first.from - shrank;
      const to = (last.newline ? last.to + 1 : last.to) - shrank;
      const removed = run.map((l) => l.text).join('\n');
      // Blank lines go without a mark: there is nothing to draw struck through, and nothing worth a Revert.
      const records = removed.trim() ? [{ id: changeId(), runId: this.runId, from, to: from, removed, block: true }] : [];
      this.dispatch({ changes: [{ from, to, insert: '' }], records, cursor: from, oldEnd: landing.oldEnd - shrank - (to - from) }, true);
      shrank += to - from;
      cursor = from;
      run = [];
    };
    for (let i = 0; i < until; i += 1) {
      const line = old[i]!;
      if (touchedIn(landing, line.from, line.to)) {
        flush();
        cursor = (line.newline ? line.to + 1 : line.to) - shrank;
      } else run.push(line);
    }
    flush();
    return { cursor, shrank };
  }

  private landOne(line: string): void {
    const landing = this.landing();
    if (!landing) return;
    const old = this.oldLines(landing);
    const match = matchLine(
      old.map((o) => o.text),
      line,
    );
    if (match.kind === 'insert') {
      // The next old line is one the person wrote while the model worked: a line of the model's that matches nothing
      // ahead is most likely its version of that line, and theirs stands.
      if (old[0] && touchedIn(landing, old[0].from, old[0].to)) {
        this.dropped += 1;
        return;
      }
      this.insert(landing, line);
      return;
    }
    const target = old[match.at]!;
    const { cursor, shrank } = this.strike(landing, old, match.at);
    const after = this.landing() ?? { ...landing, cursor, oldEnd: landing.oldEnd - shrank };
    const from = target.from - shrank;
    const to = target.to - shrank;
    if (match.kind === 'keep' || touchedIn(after, from, to)) {
      if (match.kind !== 'keep') this.dropped += 1;
      this.pass(after, from, to, target.newline);
      return;
    }
    this.replace(after, line, from, to, target.newline, target.text);
  }

  /** The cursor moves past a line that stays as it is, a newline put after it if the note ends there. */
  private pass(landing: Landing, from: number, to: number, newline: boolean): void {
    if (newline) {
      this.dispatch({ cursor: to + 1, oldEnd: landing.oldEnd }, false);
      return;
    }
    this.dispatch({ changes: [{ from: to, insert: '\n' }], cursor: to + 1, oldEnd: Math.max(landing.oldEnd, to) + 1 }, false);
  }

  /** A line the model added, on a line of its own at the cursor. */
  private insert(landing: Landing, line: string): void {
    const { doc } = this.view.state;
    let at = landing.cursor;
    let oldEnd = landing.oldEnd;
    const changes: { from: number; insert: string }[] = [];
    // The cursor is always at the start of a line, unless the note's last line has no newline yet. A newline put in
    // for that is the note's, not the run's: the run's words start after it.
    let start: number | undefined;
    if (at > 0 && doc.sliceString(at - 1, at) !== '\n') {
      changes.push({ from: at, insert: '\n' });
      at += 1;
      oldEnd += 1;
      if (landing.start === landing.cursor) start = at;
    }
    changes.push({ from: landing.cursor, insert: line + '\n' });
    const from = at;
    const to = at + line.length;
    this.dispatch({ changes, records: [{ id: changeId(), runId: this.runId, from, to, removed: '', block: true }], cursor: to + 1, oldEnd: oldEnd + line.length + 1, start }, false);
  }

  /** An old line rewritten: the new words in, and only the words that differ marked. */
  private replace(landing: Landing, line: string, from: number, to: number, newline: boolean, oldText: string): void {
    const records: AiChange[] = [];
    let pos = from;
    let gone = '';
    for (const segment of wordDiff(oldText, line)) {
      if (segment.kind === 'removed') {
        gone += segment.text;
        continue;
      }
      if (segment.kind === 'added') {
        records.push({ id: changeId(), runId: this.runId, from: pos, to: pos + segment.text.length, removed: gone, block: false });
        gone = '';
      } else if (gone) {
        records.push({ id: changeId(), runId: this.runId, from: pos, to: pos, removed: gone, block: false });
        gone = '';
      }
      pos += segment.text.length;
    }
    if (gone) records.push({ id: changeId(), runId: this.runId, from: pos, to: pos, removed: gone, block: false });
    const changes = [{ from, to, insert: line }, ...(newline ? [] : [{ from: to, insert: '\n' }])];
    const grew = line.length - (to - from);
    this.dispatch({ changes, records, cursor: from + line.length + 1, oldEnd: Math.max(landing.oldEnd, to) + grew + (newline ? 0 : 1) }, records.some((r) => r.removed !== ''));
  }

  /**
   * The run is done: the old words left below the landed lines go, and the
   * finished text is read over the landed lines, so what the tidy-up changed
   * lands too. Then the bookmark is put away.
   */
  finish(finalLines: readonly string[]): void {
    const landing = this.landing();
    if (!landing) return;
    const old = this.oldLines(landing);
    this.strike(landing, old, old.length);
    const after = this.landing();
    if (after) {
      // Read the finished text over what landed: the landed lines are the old ones now.
      this.dispatch({ cursor: after.start, oldEnd: after.cursor, start: after.start }, false);
      this.landed = 0;
      for (const line of finalLines) this.landOne(line);
      const last = this.landing();
      if (last) this.strike(last, this.oldLines(last), this.oldLines(last).length);
    }
    this.view.dispatch({ effects: setLanding.of(null), annotations: aiEdit.of('land') });
    progress.delete(this.runId);
  }

  /** The run stopped or failed: what landed stays, nothing more is struck. */
  abandon(): void {
    this.view.dispatch({ effects: setLanding.of(null), annotations: aiEdit.of('land') });
    progress.delete(this.runId);
  }
}
