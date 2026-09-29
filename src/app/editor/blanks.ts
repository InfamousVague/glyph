import { ensureSyntaxTree, syntaxTree } from '@codemirror/language';
import { Facet, StateEffect, StateField, type EditorState, type Extension, type Range } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { BookOpenText, Calculator, CalendarDays, Globe, Hourglass, LoaderCircle, MessageCircleQuestionMark, PenLine, Wifi, WifiOff, type LucideIcon } from '@glacier/icons';
import { blankMatches, type Blank, fillsIn } from '../core/blanks.ts';
import { externalStore } from '../core/externalStore.ts';
import { frontMatterOffset } from '../core/frontMatter.ts';
import type { FactIcon } from '../core/fillFacts.ts';
import { mathsIn } from '../core/maths.ts';
import { fillable, laneOf, type Lane, type Lookups } from '../ai/fills/lane.ts';
import { blankKey, fillOutcome, fillStatus, subscribeFills, type FillOutcome, type FillStatus, type FillTarget } from '../ai/fills/queue.ts';
import { runFor } from '../ai/runs.ts';
import { iconElement } from './iconDom.ts';
import { selectedLines } from './lines.ts';
import { inQuietText } from './syntax.ts';
import { formattedView } from './viewMode.ts';

/**
 * Blanks, drawn: a question in curly brackets as the square Matt asked for (docs/DESIGN.md §145, 3).
 *
 * The parser makes no node for `{?…}` (editor/language.ts takes only symmetric delimiter runs), so this reads the lines
 * on screen with the pattern (core/blanks.ts) and draws what the parser calls words: never in code, maths, HTML, a
 * comment, a link's address or front matter. The square is a dashed hairline of the words' own ink, in both inks,
 * round the question, with an icon at its end that says what will happen before anything is pressed: a calculator, a
 * calendar or a globe where the app works it out (core/fillFacts.ts, its answer after the square like a sum's), a
 * question in a speech bubble where the model will answer, a signal where the phone will look it up (ai/fills/web.ts),
 * and a crossed-out signal where it can't be known. In the Markdown view the braces stay in the marks' dim ink; in the
 * Formatted view they go, but on the lines being written.
 *
 * A tap on the square places the caret, as on any words: filling is always a separate press, so a tap meant for the
 * caret never wakes the model. The press is the Fill pill at the end of the line (the suggestion pill's look and
 * touch handling, editor/suggestions.ts), Fill the blanks in the More sheet, or the palette. On the line being typed
 * the icon, the words after the square and the pill wait until the hands have stopped for 700 ms with the caret
 * outside the braces, so nothing jumps with each letter; a worked-out answer shows at once, as a sum's does.
 *
 * A press is handed to the fills' queue (ai/fills/queue.ts), which knows each blank by its question and its order
 * among blanks with that question, and by its range here, mapped through every edit (`blanksField`), while the note is
 * open.
 */

// ---- what the editor knows -----------------------------------------------------------------------------------

/** What the screen gives the squares: whose note, whether the model can run here, and what a press does. */
export interface BlankHooks {
  noteId(): string;
  /** The model can run here (ai/available.ts): the Fill pill is drawn. A browser, iOS and a read-only page have none. */
  canFill(): boolean;
  /** The chosen model's horizon (core/ai.ts `learntUntil`). */
  learntUntil(): number;
  /** Whether live blanks may be looked up here (ai/fills/queue.ts `lookupsHere`). */
  lookups(): Lookups;
  /** A press: the queue takes these. */
  fill(targets: FillTarget[]): void;
  /** A sentence to say, for a press that runs nothing. */
  say(message: string): void;
  /** The clock, for tests. */
  now?(): Date;
  zone?(): string;
}

/** The hooks, read by the widgets and the panel. Absent where a note is only read. */
export const blankHooks = Facet.define<BlankHooks | null, BlankHooks | null>({ combine: (values) => values.find(Boolean) ?? null });

/** A card's small, still note (notes/peek.ts): the square with no icon. */
const stillSquares = Facet.define<boolean, boolean>({ combine: (values) => values.some(Boolean) });

/** Redraw: the queue moved, the pause ended, a minute turned. */
export const blanksRedraw = StateEffect.define<null>();

/** Counts every redraw, so a drawn table knows to draw its cells again (editor/tables.ts). */
export const blankStamp = StateField.define<number>({
  create: () => 0,
  update: (stamp, tr) => (tr.effects.some((e) => e.is(blanksRedraw)) ? stamp + 1 : stamp),
});

/** Blanks a press took, tracked by their identity while the note is open. */
export const trackBlanks = StateEffect.define<readonly { key: string; from: number; to: number }[]>();

/** Each tracked blank's range, mapped through every edit, as the landing is (editor/aiChanges.ts). */
export const blanksField = StateField.define<ReadonlyMap<string, { from: number; to: number }>>({
  create: () => new Map(),
  update(ranges, tr) {
    let next = ranges;
    if (tr.docChanged && ranges.size) {
      const moved = new Map<string, { from: number; to: number }>();
      for (const [key, range] of ranges) {
        const from = tr.changes.mapPos(range.from, 1);
        const to = tr.changes.mapPos(range.to, -1);
        if (to > from) moved.set(key, { from, to });
      }
      next = moved;
    }
    for (const effect of tr.effects) {
      if (!effect.is(trackBlanks)) continue;
      const added = new Map(next);
      for (const { key, from, to } of effect.value) added.set(key, { from, to });
      next = added;
    }
    return next;
  },
});

/**
 * Whether a blank starting at `from` sits in words the editor draws: not front matter (the parser makes no node for
 * it, editor/extended.ts draws it by its own rule), code, a comment, an address or maths.
 */
function inWords(state: EditorState, from: number): boolean {
  if (from < frontMatterOffset(state.doc.sliceString(0, Math.min(state.doc.length, 4000)))) return false;
  if (inQuietText(state, from)) return false;
  const line = state.doc.lineAt(from);
  return !mathsIn(line.text, line.from).some((m) => from >= m.from && from < m.to);
}

/**
 * The blanks the editor draws, offers and fills: every match of the pattern outside the parser's quiet places. For
 * the whole note (Fill the blanks, its count in the More sheet, the palette) the whole tree is asked for first, on the
 * press or when the sheet opens, never per keystroke.
 */
export function editorBlanks(state: EditorState, whole = true): Blank[] {
  if (whole) ensureSyntaxTree(state, state.doc.length, 200);
  const text = state.doc.toString();
  if (!text.includes('{?')) return [];
  return blankMatches(text).filter((blank) => inWords(state, blank.from));
}

/** A blank's identity among `all`: its question and its order among blanks with that question. */
export function keyOf(all: readonly Blank[], blank: Blank): string {
  return blankKey(blank.question, all.filter((b) => b.question === blank.question && b.from < blank.from).length);
}

/** The options a lane is worked out with, from the hooks. */
function laneOptions(hooks: BlankHooks | null) {
  return { clock: { now: hooks?.now?.() ?? new Date(), zone: hooks?.zone?.() }, learntUntil: hooks?.learntUntil() ?? 2024, lookups: hooks?.lookups() ?? ('off' as Lookups) };
}

/** A blank's lane in this state. */
export function laneAt(state: EditorState, blank: Blank): Lane {
  return laneOf(blank, state.doc.toString(), laneOptions(state.facet(blankHooks)));
}

/**
 * A press of these blanks: the title blank with too little under it says so and runs nothing, the rest are tracked
 * from here and handed to the queue. Answers how many went.
 */
export function pressBlanks(view: EditorView, blanks: readonly Blank[], all: readonly Blank[] = editorBlanks(view.state)): number {
  const hooks = view.state.facet(blankHooks);
  if (!hooks) return 0;
  const targets: FillTarget[] = [];
  const tracked: { key: string; from: number; to: number }[] = [];
  let tooShort = false;
  for (const blank of blanks) {
    const lane = laneAt(view.state, blank);
    if (!fillable(lane)) continue;
    if (lane.lane === 'model' && lane.info.tooShort) {
      tooShort = true;
      continue;
    }
    const key = keyOf(all, blank);
    const order = Number(key.split('\u0000')[1]);
    targets.push({ key, question: blank.question, order });
    tracked.push({ key, from: blank.from, to: blank.to });
  }
  if (tooShort && !targets.length) hooks.say('Write a few lines first. The title is made from them.');
  if (!targets.length) return 0;
  view.dispatch({ effects: trackBlanks.of(tracked) });
  hooks.fill(targets);
  return targets.length;
}

/** Every blank in the note a press of Fill would take, for Fill the blanks and its count. */
export function fillableBlanks(state: EditorState): Blank[] {
  const hooks = state.facet(blankHooks);
  const text = state.doc.toString();
  const options = laneOptions(hooks);
  return editorBlanks(state).filter((blank) => fillable(laneOf(blank, text, options)));
}

/** Fill the blanks: every blank the model or a lookup can answer, top to bottom. Answers how many went. */
export function fillAll(view: EditorView): number {
  const all = editorBlanks(view.state);
  return pressBlanks(view, fillableBlanks(view.state), all);
}

// ---- how each blank is drawn -----------------------------------------------------------------------------------

const FACT_ICONS: Record<FactIcon, LucideIcon> = { calculator: Calculator, calendar: CalendarDays, globe: Globe };

/** The icon a blank wears: what will happen, or, once pressed, the run's phase. */
function iconFor(lane: Lane, status: FillStatus | null, noteId: string | null): { Icon: LucideIcon; spin: boolean } {
  if (status?.phase === 'filling') {
    const phase = (noteId && runFor(noteId)?.phase) || 'queued';
    if (phase === 'loading') return { Icon: LoaderCircle, spin: true };
    if (phase === 'prefill') return { Icon: BookOpenText, spin: false };
    if (phase === 'generating') return { Icon: PenLine, spin: false };
    return { Icon: Hourglass, spin: false };
  }
  if (status?.phase === 'waiting') return { Icon: Hourglass, spin: false };
  if (status?.phase === 'looking') return { Icon: Wifi, spin: false };
  if (status?.phase === 'paused') return { Icon: WifiOff, spin: false };
  if (lane.lane === 'worked') return { Icon: FACT_ICONS[lane.worked.icon], spin: false };
  if (lane.lane === 'cannot') return { Icon: FACT_ICONS[lane.cannot.icon], spin: false };
  if (lane.lane === 'live') return { Icon: lane.can === 'look' ? Wifi : WifiOff, spin: false };
  return { Icon: MessageCircleQuestionMark, spin: false };
}

/** The quiet words after a blank, if any: a refusal, a pause, what came of a press. */
export function wordsAfter(lane: Lane, status: FillStatus | null, outcome: FillOutcome | null): string | null {
  if (status?.phase === 'paused') return status.why === 'offline' ? 'Waiting for a connection' : 'Paused';
  if (status?.phase === 'looking') return 'Looking it up';
  if (status) return null;
  if (outcome) return { unknown: 'Not known', none: 'No answer came', 'didnt-fit': 'Didn’t fit', nothing: 'Not found online' }[outcome.why];
  if (lane.lane === 'cannot') return 'Can’t work out';
  if (lane.lane === 'live' && lane.can === 'local-only') return 'Paused';
  if (lane.lane === 'live' && lane.can !== 'look') return 'Can’t know offline';
  return null;
}

/** A blank's name for a screen reader: its outcome, then what it asks. */
function label(lane: Lane, blank: Blank, text: string): string {
  const asked = blank.question || text.slice(text.lastIndexOf('\n', blank.from - 1) + 1, blank.from).trim() || '';
  if (lane.lane === 'worked') return `Worked out: ${asked}`;
  if (lane.lane === 'cannot') return `Can't work out: ${asked}`;
  if (lane.lane === 'live' && lane.can !== 'look') return `Can't know offline: ${asked}`;
  if (lane.lane === 'live') return `Looked up online: ${asked}`;
  return blank.question ? `A blank for the AI: ${blank.question}` : 'A blank for the AI';
}

class IconWidget extends WidgetType {
  constructor(
    readonly Icon: LucideIcon,
    readonly spin: boolean,
  ) {
    super();
  }
  eq(other: IconWidget): boolean {
    return other.Icon === this.Icon && other.spin === this.spin;
  }
  toDOM(): HTMLElement {
    const span = document.createElement('span');
    span.className = 'cm-blankIcon';
    span.setAttribute('aria-hidden', 'true');
    if (this.spin) span.dataset.spin = '';
    span.appendChild(iconElement(this.Icon));
    return span;
  }
  ignoreEvent(): boolean {
    return false;
  }
}

/** What follows a blank: a worked-out answer drawn as a sum's, or quiet words; either opens the panel on a tap. */
class AfterWidget extends WidgetType {
  constructor(
    readonly text: string,
    readonly answer: boolean,
    readonly at: number,
  ) {
    super();
  }
  eq(other: AfterWidget): boolean {
    return other.text === this.text && other.answer === this.answer && other.at === this.at;
  }
  toDOM(view: EditorView): HTMLElement {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = this.answer ? 'cm-sumAnswer cm-blankAnswer' : 'cm-blankWords';
    button.textContent = this.text;
    if (this.answer) button.setAttribute('aria-label', `equals ${this.text}`);
    keepFromEditor(button, () => openPanelAt(view, this.at));
    return button;
  }
  ignoreEvent(): boolean {
    return true;
  }
}

/** The Fill pill at the end of a line: its blanks, and how busy they are. */
class PillWidget extends WidgetType {
  constructor(
    readonly label: string,
    readonly busy: boolean,
    readonly froms: readonly number[],
    readonly aria: string,
  ) {
    super();
  }
  eq(other: PillWidget): boolean {
    return other.label === this.label && other.busy === this.busy && other.froms.join() === this.froms.join();
  }
  toDOM(view: EditorView): HTMLElement {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'cm-suggest cm-fillPill';
    button.textContent = this.label;
    button.setAttribute('aria-label', this.aria);
    if (this.busy) {
      button.dataset.busy = '';
      button.disabled = true;
    }
    keepFromEditor(button, () => {
      if (this.busy) return;
      const all = editorBlanks(view.state);
      pressBlanks(
        view,
        all.filter((b) => this.froms.includes(b.from)),
        all,
      );
    });
    return button;
  }
  ignoreEvent(): boolean {
    return true;
  }
}

/**
 * A press on a word or a pill, kept from the editor as the suggestion pill keeps its own (editor/suggestions.ts): a
 * pointer or mouse press has its default taken away, so the caret does not move and the widget is not rebuilt under
 * the tap; a touch is only kept from the editor, since a touch whose default is taken never becomes a click.
 */
function keepFromEditor(button: HTMLElement, press: () => void): void {
  for (const kind of ['pointerdown', 'mousedown'] as const) {
    button.addEventListener(kind, (event) => {
      event.preventDefault();
      event.stopPropagation();
    });
  }
  button.addEventListener('touchstart', (event) => event.stopPropagation());
  button.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopPropagation();
    press();
  });
}

/** Opens the fill panel for what sits at `at` (editor/fillPanel.ts), through the facet it registers. */
function openPanelAt(view: EditorView, at: number): void {
  view.state.facet(panelOpener)?.(view, at);
}

/** The panel's opener, given by editor/fillPanel.ts, so the two modules do not import each other. */
export const panelOpener = Facet.define<(view: EditorView, at: number) => void, ((view: EditorView, at: number) => void) | null>({ combine: (values) => values[0] ?? null });

/** The square round a blank, named for a screen reader by its outcome, and breathing while it fills. */
const boxFor = (name: string, busy: boolean) => Decoration.mark({ class: 'cm-blank', attributes: { role: 'group', 'aria-label': name, ...(busy ? { 'data-busy': '' } : {}) }, inclusiveStart: true, inclusiveEnd: true });
const brace = Decoration.mark({ class: 'cm-blankMark' });
const question = Decoration.mark({ class: 'cm-blankQuestion' });
const hidden = Decoration.replace({});

interface Drawn {
  decorations: DecorationSet;
  /** Whether a worked-out answer that changes each minute is on screen: the minute timer runs only then. */
  minutely: boolean;
}

/** The squares on screen, their icons, the words after them and the pills. */
function draw(view: EditorView, idle: boolean): Drawn {
  const { state } = view;
  const text = state.doc.toString();
  if (!text.includes('{?')) return { decorations: Decoration.none, minutely: false };
  const hooks = state.facet(blankHooks);
  const noteId = hooks?.noteId() ?? null;
  const formatted = state.facet(formattedView);
  const still = state.facet(stillSquares);
  const caretLines = view.hasFocus ? selectedLines(state) : new Set<number>();
  const editable = state.facet(EditorView.editable);
  const all = blankMatches(text).filter((blank) => inWords(state, blank.from));
  const options = laneOptions(hooks);
  const marks: Range<Decoration>[] = [];
  const pills = new Map<number, { froms: number[]; busy: 'filling' | 'waiting' | null; questions: string[] }>();
  let minutely = false;
  const head = state.selection.main.head;
  for (const { from, to } of view.visibleRanges) {
    for (const blank of all) {
      if (blank.to < from || blank.from > to) continue;
      const line = state.doc.lineAt(blank.from);
      const lane = laneOf(blank, text, options);
      const key = keyOf(all, blank);
      const status = noteId ? fillStatus(noteId, key) : null;
      const outcome = noteId ? fillOutcome(noteId, key) : null;
      const typing = caretLines.has(line.number) && !idle;
      const caretInside = view.hasFocus && head > blank.from + 1 && head < blank.to;
      const busy = status?.phase === 'filling' || status?.phase === 'looking';
      marks.push(boxFor(label(lane, blank, text), busy).range(blank.from, blank.to));
      const showBraces = !formatted || caretLines.has(line.number);
      if (showBraces) {
        marks.push(brace.range(blank.from, blank.from + 2));
        marks.push(brace.range(blank.to - 1, blank.to));
      } else {
        marks.push(hidden.range(blank.from, blank.from + 2));
        marks.push(hidden.range(blank.to - 1, blank.to));
      }
      if (blank.to - 1 > blank.from + 2) marks.push(question.range(blank.from + 2, blank.to - 1));
      if (!caretInside && !typing && !still) {
        const { Icon, spin } = iconFor(lane, status, noteId);
        marks.push(Decoration.widget({ widget: new IconWidget(Icon, spin), side: -1 }).range(blank.to - 1));
      }
      if (lane.lane === 'worked' && !status) {
        marks.push(Decoration.widget({ widget: new AfterWidget(lane.worked.answer, true, blank.from), side: 1 }).range(blank.to));
        if (lane.worked.changes === 'minute') minutely = true;
      } else if (!typing) {
        const words = wordsAfter(lane, status, outcome);
        if (words) marks.push(Decoration.widget({ widget: new AfterWidget(words, false, blank.from), side: 1 }).range(blank.to));
      }
      // The pill: blanks the model or a lookup will answer, where the model can run.
      if (editable && hooks?.canFill() && (fillable(lane) || status) && !typing) {
        const pill = pills.get(line.number) ?? { froms: [], busy: null, questions: [] };
        if (status?.phase === 'filling' || status?.phase === 'looking') pill.busy = 'filling';
        else if (status?.phase === 'waiting' && pill.busy !== 'filling') pill.busy = 'waiting';
        else if (!status && fillable(lane)) {
          pill.froms.push(blank.from);
          pill.questions.push(blank.question);
        }
        pills.set(line.number, pill);
      }
    }
  }
  for (const [number, pill] of pills) {
    const line = state.doc.line(number);
    if (pill.busy) {
      marks.push(Decoration.widget({ widget: new PillWidget(pill.busy === 'filling' ? 'Filling' : 'Waiting', true, [], pill.busy === 'filling' ? 'Filling' : 'Waiting'), side: 2 }).range(line.to));
    } else if (pill.froms.length) {
      const n = pill.froms.length;
      const aria = n === 1 ? (pill.questions[0] ? `Fill the blank: ${pill.questions[0]}` : 'Fill the blank') : `Fill ${n} blanks`;
      marks.push(Decoration.widget({ widget: new PillWidget(n === 1 ? 'Fill' : `Fill ${n}`, false, pill.froms, aria), side: 2 }).range(line.to));
    }
  }
  return { decorations: Decoration.set(marks, true), minutely };
}

/**
 * How many blanks the open note has for a press of Fill, for the palette's Fill the blanks (commands/palette.ts):
 * counted a moment after the typing stops, never per keystroke.
 */
export const openNoteBlanks = externalStore<{ noteId: string; count: number } | null>(null);

/** How long the hands rest on the caret's line before its icon, words and pill come back. */
export const PAUSE_MS = 700;

const plugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    private idle = true;
    private pause = 0;
    private minute = 0;
    private readonly unsubscribe: () => void;

    private counting = 0;

    constructor(readonly view: EditorView) {
      const drawn = draw(view, this.idle);
      this.decorations = drawn.decorations;
      this.tick(drawn.minutely);
      this.unsubscribe = subscribeFills(() => queueMicrotask(() => this.redraw()));
      this.count();
    }

    /** The open note's count of blanks for Fill, told half a second after the typing stops. */
    private count(): void {
      const hooks = this.view.state.facet(blankHooks);
      if (!hooks || !this.view.state.facet(EditorView.editable)) return;
      window.clearTimeout(this.counting);
      this.counting = window.setTimeout(() => {
        if (!this.view.dom.isConnected) return;
        const text = this.view.state.doc.toString();
        const count = text.includes('{?') ? blankMatches(text).filter((b) => inWords(this.view.state, b.from) && fillable(laneOf(b, text, laneOptions(hooks)))).length : 0;
        const was = openNoteBlanks.get();
        if (!was || was.noteId !== hooks.noteId() || was.count !== count) openNoteBlanks.set({ noteId: hooks.noteId(), count });
      }, 500);
    }

    private redraw(): void {
      if (this.view.dom.isConnected) this.view.dispatch({ effects: blanksRedraw.of(null) });
    }

    /** The minute timer, running only while a time-now answer is on screen. */
    private tick(minutely: boolean): void {
      window.clearTimeout(this.minute);
      if (!minutely) return;
      this.minute = window.setTimeout(() => this.redraw(), 60_000 - (Date.now() % 60_000) + 50);
    }

    update(update: ViewUpdate): void {
      if (update.docChanged && update.transactions.some((tr) => tr.isUserEvent('input') || tr.isUserEvent('delete'))) {
        this.idle = false;
        window.clearTimeout(this.pause);
        this.pause = window.setTimeout(() => {
          this.idle = true;
          this.redraw();
        }, PAUSE_MS);
      }
      if (update.docChanged) this.count();
      const asked = update.transactions.some((tr) => tr.effects.some((e) => e.is(blanksRedraw)));
      if (update.docChanged || update.selectionSet || update.viewportChanged || update.focusChanged || asked || syntaxTree(update.startState) !== syntaxTree(update.state)) {
        const drawn = draw(update.view, this.idle);
        this.decorations = drawn.decorations;
        this.tick(drawn.minutely);
      }
    }

    destroy(): void {
      window.clearTimeout(this.pause);
      window.clearTimeout(this.minute);
      window.clearTimeout(this.counting);
      this.unsubscribe();
      const hooks = this.view.state.facet(blankHooks);
      if (hooks && openNoteBlanks.get()?.noteId === hooks.noteId()) openNoteBlanks.set(null);
    }
  },
  { decorations: (value) => value.decorations },
);

const theme = EditorView.baseTheme({
  // The suggestion pill's hairline, dashed, round the whole blank: no hue, right on black paper and white.
  '.cm-blank': {
    border: '1px dashed color-mix(in oklch, currentColor 45%, transparent)',
    borderRadius: '0.2em',
    padding: '0 0.25em',
    boxDecorationBreak: 'clone',
    WebkitBoxDecorationBreak: 'clone',
  },
  '.cm-blank[data-busy]': {
    animation: 'cm-blank-breathe 1.6s ease-in-out infinite alternate',
  },
  '@keyframes cm-blank-breathe': {
    from: { opacity: '0.45' },
    to: { opacity: '0.8' },
  },
  '.cm-blankMark': { color: 'var(--app-ink-4, currentColor)' },
  '.cm-blankQuestion': { color: 'var(--app-ink-3, currentColor)' },
  '.cm-blankIcon': {
    display: 'inline-block',
    inlineSize: '0.9em',
    blockSize: '0.9em',
    marginInline: '0.2em 0.05em',
    verticalAlign: '-0.08em',
    color: 'var(--app-ink-3, currentColor)',
    minInlineSize: '0.9em',
  },
  '.cm-blankIcon svg': { inlineSize: '0.9em', blockSize: '0.9em', display: 'block' },
  '.cm-blankIcon[data-spin] svg': { animation: 'cm-blank-spin 1.2s linear infinite' },
  '@keyframes cm-blank-spin': { to: { transform: 'rotate(360deg)' } },
  '.cm-blankAnswer': {
    appearance: 'none',
    border: 'none',
    background: 'transparent',
    padding: '0',
    font: 'inherit',
    cursor: 'pointer',
  },
  '.cm-blankWords': {
    appearance: 'none',
    border: 'none',
    background: 'transparent',
    padding: '0',
    marginInlineStart: '0.6em',
    font: 'inherit',
    fontSize: '0.68em',
    color: 'var(--app-ink-4, currentColor)',
    verticalAlign: '0.15em',
    whiteSpace: 'nowrap',
    cursor: 'pointer',
    WebkitTapHighlightColor: 'transparent',
  },
  // A filled answer in a drawn table: its words with the Unsure mark's dotted line, a tap opening its panel.
  '.cm-fillWords': {
    appearance: 'none',
    border: 'none',
    background: 'transparent',
    padding: '0',
    font: 'inherit',
    color: 'inherit',
    textAlign: 'inherit',
    textDecoration: 'underline dotted',
    textDecorationColor: 'var(--glacier-text-subtle, currentColor)',
    textUnderlineOffset: '0.22em',
    textDecorationThickness: '0.09em',
    cursor: 'pointer',
  },
  '.cm-glyphTableWrap .cm-fillPill': { display: 'inline-block', marginBlockStart: '0.3em' },
  '@media (prefers-reduced-motion: reduce)': {
    '.cm-blank[data-busy]': { animation: 'none', opacity: '0.6' },
    '.cm-blankIcon[data-spin] svg': { animation: 'none' },
  },
});

// ---- in a drawn table ------------------------------------------------------------------------------------------

/**
 * A drawn table's cell (editor/tables.ts), with its blanks and its fills: a blank as its square with its icon and the
 * words after it, a filled answer as its words with the dotted line and the bracket hidden, a tap on either opening
 * the panel. `raw` is the cell's text as written and `at` where it starts in the note. Answers whether it drew
 * anything of its own; the table draws the cell's words as it always did otherwise.
 */
export function drawCell(view: EditorView, cell: HTMLElement, raw: string, at: number, plain: (text: string) => string): boolean {
  if (!raw.includes('{?') && !raw.includes('??(')) return false;
  const { state } = view;
  const hooks = state.facet(blankHooks);
  const text = state.doc.toString();
  const all = blankMatches(text).filter((blank) => inWords(state, blank.from));
  const options = laneOptions(hooks);
  const noteId = hooks?.noteId() ?? null;
  const pieces: { from: number; to: number; node: () => Node[] }[] = [];
  for (const blank of blankMatches(raw, at)) {
    const lane = laneOf(blank, text, options);
    const key = keyOf(all, blank);
    const status = noteId ? fillStatus(noteId, key) : null;
    const outcome = noteId ? fillOutcome(noteId, key) : null;
    pieces.push({
      from: blank.from,
      to: blank.to,
      node: () => {
        const square = document.createElement('span');
        square.className = 'cm-blank';
        square.setAttribute('role', 'group');
        square.setAttribute('aria-label', label(lane, blank, text));
        if (status?.phase === 'filling' || status?.phase === 'looking') square.dataset.busy = '';
        if (blank.question) {
          const words = document.createElement('span');
          words.className = 'cm-blankQuestion';
          words.textContent = blank.question;
          square.appendChild(words);
        }
        const { Icon, spin } = iconFor(lane, status, noteId);
        square.appendChild(new IconWidget(Icon, spin).toDOM());
        const out: Node[] = [square];
        const after = lane.lane === 'worked' && !status ? lane.worked.answer : wordsAfter(lane, status, outcome);
        if (after) out.push(new AfterWidget(after, lane.lane === 'worked' && !status, blank.from).toDOM(view));
        return out;
      },
    });
  }
  for (const fill of fillsIn(raw, at)) {
    pieces.push({
      from: fill.from,
      to: fill.to,
      node: () => {
        const words = document.createElement('button');
        words.type = 'button';
        words.className = 'cm-fillWords';
        words.textContent = fill.words;
        keepFromEditor(words, () => openPanelAt(view, fill.from + 2));
        return [words];
      },
    });
  }
  pieces.sort((a, b) => a.from - b.from);
  cell.textContent = '';
  let cursor = at;
  for (const piece of pieces) {
    if (piece.from < cursor) continue;
    if (piece.from > cursor) cell.append(plain(raw.slice(cursor - at, piece.from - at)));
    cell.append(...piece.node());
    cursor = piece.to;
  }
  if (cursor < at + raw.length) cell.append(plain(raw.slice(cursor - at)));
  return true;
}

/** The Fill pill after a drawn table with blanks for the model: Fill 3, or Filling while they go. Null where none. */
export function tablePill(view: EditorView, from: number, to: number): HTMLElement | null {
  const { state } = view;
  const hooks = state.facet(blankHooks);
  if (!hooks?.canFill() || !state.facet(EditorView.editable)) return null;
  const text = state.doc.toString();
  const all = blankMatches(text).filter((blank) => inWords(state, blank.from));
  const mine = all.filter((b) => b.from >= from && b.to <= to);
  if (!mine.length) return null;
  const options = laneOptions(hooks);
  const noteId = hooks.noteId();
  let busy: 'filling' | 'waiting' | null = null;
  const froms: number[] = [];
  for (const blank of mine) {
    const status = fillStatus(noteId, keyOf(all, blank));
    if (status?.phase === 'filling' || status?.phase === 'looking') busy = 'filling';
    else if (status?.phase === 'waiting' && busy !== 'filling') busy = 'waiting';
    else if (!status && fillable(laneOf(blank, text, options))) froms.push(blank.from);
  }
  if (busy) return new PillWidget(busy === 'filling' ? 'Filling' : 'Waiting', true, [], busy === 'filling' ? 'Filling' : 'Waiting').toDOM(view);
  if (!froms.length) return null;
  return new PillWidget(froms.length === 1 ? 'Fill' : `Fill ${froms.length}`, false, froms, froms.length === 1 ? 'Fill the blank' : `Fill ${froms.length} blanks`).toDOM(view);
}

/** The squares, the tracked ranges and their look, with `hooks` where a note is the person's to fill. */
export function blanks(hooks: BlankHooks | null, { still = false }: { still?: boolean } = {}): Extension {
  return [blankHooks.of(hooks), stillSquares.of(still), blanksField, blankStamp, plugin, theme];
}

/** A class and a sample for the brisk setup's line, so a change of look reaches it (docs/DESIGN.md §146). */
export const BLANK_CLASS = 'cm-blank';
