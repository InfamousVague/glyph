import { Prec, type Extension } from '@codemirror/state';
import { EditorView, ViewPlugin } from '@codemirror/view';
import { Calculator, CalendarDays, Check, FileText, Globe, Lightbulb, MessageCircleQuestionMark, RotateCw, TextCursorInput, Undo2, Wifi, WifiOff, type LucideIcon } from '@glacier/icons';
import { MODEL_LIMITS, modelName } from '../core/ai.ts';
import { blankMatches, type Blank, fillsIn, type Filled } from '../core/blanks.ts';
import type { FactIcon } from '../core/fillFacts.ts';
import { liveWords } from '../core/fillLive.ts';
import { laneOf, type Lane } from '../ai/fills/lane.ts';
import { fillOutcome, fillStatus, type FillOutcome, type FillStatus } from '../ai/fills/queue.ts';
import { NO_SOURCE, sourceName } from '../ai/fills/web.ts';
import { blankHooks, editorBlanks, keyOf, panelOpener, trackBlanks } from './blanks.ts';
import { iconElement } from './iconDom.ts';
import { isMacApp } from '../core/platform.ts';

/** The device, as the panel's words name it: the phone, or this Mac in the Mac app. */
const device = () => (isMacApp ? 'this Mac' : 'the phone');
const Device = () => (isMacApp ? 'This Mac' : 'The phone');

/**
 * The panel a tap on an answer opens (docs/DESIGN.md §145, 7): where it came from, in words, and what can be done with
 * it. A filled answer says whose it is and from where (memory, this note, or the web and which source), when it was
 * asked and what, and the one sentence the app says about every model everywhere (core/ai.ts `MODEL_LIMITS`), with
 * Keep as mine, Ask again and Put the question back. A worked-out answer shows its working and Write it in. A refusal
 * says why in the app's words, with Ask the model anyway where the model can run, since a word list can be wrong.
 *
 * Placed and closed as a mark's note is (editor/textPanel.ts): under the words, inside the editor's width, gone on a
 * tap elsewhere, a change or a scroll. Its tap on a filled answer runs before the mark notes' (`Prec.high`), which
 * leave a fill's bracket to this panel (editor/markNotes.ts). On a page that is only read, the words and no actions.
 */

const PANEL = 'cm-fillPanel';

interface Action {
  Icon: LucideIcon;
  label: string;
  run: () => void;
}

interface PanelContent {
  Icon: LucideIcon;
  title: string;
  lines: string[];
  actions: Action[];
}

const FACT_ICONS: Record<FactIcon, LucideIcon> = { calculator: Calculator, calendar: CalendarDays, globe: Globe };

/** "28 September 2026" in the person's own form, from a fill's ISO date. */
function askedOn(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(y!, (m ?? 1) - 1, d ?? 1, 12));
}

/** A caveat under a model's answer: the refusal's sentence when the app would have refused it, else advice on prices. */
function caveat(lane: Lane | null, sentence: string): string | null {
  if (lane?.lane === 'cannot') return lane.cannot.words;
  if (lane?.lane === 'live') return lane.live.words;
  if (/\b(price|prices|cost|costs|cheap|cheapest|fare|fares|pay|budget|deal)\b/i.test(sentence)) {
    return /\b(flight|flights|fly|train|trains|bus|hotel|hotels|fare|fares|ticket|tickets|trip)\b/i.test(sentence) ? 'General advice, not today’s fares.' : 'General advice, not today’s prices.';
  }
  return null;
}

/** The note with a filled answer written back as its blank, and that blank: what it was asked as. */
function asBlank(text: string, span: { from: number; to: number }, question: string): { text: string; blank: Blank } {
  const written = `{?${question}}`;
  return { text: `${text.slice(0, span.from)}${written}${text.slice(span.to)}`, blank: { from: span.from, to: span.from + written.length, question } };
}

/** The items of one fill round the tapped one: adjacent lines whose brackets differ only in their place. */
function itemsOfFill(text: string, fill: ReturnType<typeof fillsIn>[number]): ReturnType<typeof fillsIn> {
  const place = fill.filled.place;
  if (!place) return [fill];
  const same = (other: Filled) => other.model === fill.filled.model && other.date === fill.filled.date && other.question === fill.filled.question && other.place?.of === place.of && other.source.kind === fill.filled.source.kind;
  const fills = fillsIn(text);
  const at = fills.indexOf(fills.find((f) => f.from === fill.from)!);
  let first = at;
  while (first > 0 && same(fills[first - 1]!.filled) && fills[first - 1]!.filled.place!.n === fills[first]!.filled.place!.n - 1) first -= 1;
  let last = at;
  while (last + 1 < fills.length && same(fills[last + 1]!.filled) && fills[last + 1]!.filled.place!.n === fills[last]!.filled.place!.n + 1) last += 1;
  return fills.slice(first, last + 1);
}

/** The panel for a filled answer. */
function fillContent(view: EditorView, fill: ReturnType<typeof fillsIn>[number]): PanelContent {
  const text = view.state.doc.toString();
  const hooks = view.state.facet(blankHooks);
  const editable = view.state.facet(EditorView.editable) && !view.state.readOnly;
  const { filled } = fill;
  const question = filled.question ?? '';
  const group = itemsOfFill(text, fill);
  const span = { from: group[0]!.from, to: group[group.length - 1]!.to };
  const asked = asBlank(text, span, question);
  const lane = hooks ? laneOf(asked.blank, asked.text, { clock: { now: hooks.now?.() ?? new Date() }, learntUntil: hooks.learntUntil(), lookups: hooks.lookups() }) : null;
  const sentence = asked.text.slice(asked.text.lastIndexOf('\n', asked.blank.from - 1) + 1, asked.text.indexOf('\n', asked.blank.to) === -1 ? undefined : asked.text.indexOf('\n', asked.blank.to));
  const askedLine = question ? `Asked on ${askedOn(filled.date)}: ${question}` : `Asked on ${askedOn(filled.date)}.`;
  const lines: string[] = [askedLine];
  let Icon: LucideIcon = Lightbulb;
  let title = `${filled.model}, from memory`;
  if (filled.source.kind === 'note') {
    Icon = FileText;
    title = `${filled.model}, from this note`;
    lines.push('Its words are in one line of this note, beside what was asked. The model chose them, so check it reads right.');
  } else if (filled.source.kind === 'web') {
    Icon = Wifi;
    title = `${filled.model}, from ${filled.source.name}`;
    lines.push(filled.model === 'Ghost.md' ? `${Device()} asked ${filled.source.name}, and the app wrote this from what came back.` : `${Device()} asked ${filled.source.name}, and the model wrote this from what came back. It can still be wrong.`);
  } else {
    lines.push(MODEL_LIMITS);
    const warning = caveat(lane, sentence);
    if (warning) lines.push(warning);
  }
  const actions: Action[] = [];
  if (editable) {
    actions.push({
      Icon: Check,
      label: 'Keep as mine',
      run: () => view.dispatch({ changes: { from: fill.from, to: fill.to, insert: fill.words }, userEvent: 'input.fill' }),
    });
    if (hooks?.canFill()) {
      actions.push({
        Icon: RotateCw,
        label: 'Ask again',
        run: () => {
          const mark = text.slice(span.from, span.to);
          const words = group.map((g) => g.words).join(', ');
          const key = `again\u0000${span.from}`;
          view.dispatch({ effects: trackBlanks.of([{ key, from: span.from, to: span.to }]) });
          hooks.fill([{ key, question, order: 0, again: { mark, words } }]);
        },
      });
    }
    actions.push({
      Icon: Undo2,
      label: 'Put the question back',
      run: () => view.dispatch({ changes: { from: span.from, to: span.to, insert: `{?${question}}` }, userEvent: 'input.fill' }),
    });
  }
  return { Icon, title, lines, actions };
}

/** The panel for a blank: worked out, refused, paused, or what came of a press. */
function blankContent(view: EditorView, blank: Blank): PanelContent | null {
  const { state } = view;
  const hooks = state.facet(blankHooks);
  const text = state.doc.toString();
  const editable = state.facet(EditorView.editable) && !state.readOnly;
  const lane = laneOf(blank, text, { clock: { now: hooks?.now?.() ?? new Date(), zone: hooks?.zone?.() }, learntUntil: hooks?.learntUntil() ?? 2024, lookups: hooks?.lookups() ?? 'off' });
  const all = editorBlanks(state, false);
  const key = keyOf(all, blank);
  const noteId = hooks?.noteId() ?? null;
  const status: FillStatus | null = noteId ? fillStatus(noteId, key) : null;
  const outcome: FillOutcome | null = noteId ? fillOutcome(noteId, key) : null;
  const order = Number(key.split('\u0000')[1]);
  const anyway: Action | null =
    editable && hooks?.canFill()
      ? {
          Icon: MessageCircleQuestionMark,
          label: 'Ask the model anyway',
          run: () => {
            view.dispatch({ effects: trackBlanks.of([{ key, from: blank.from, to: blank.to }]) });
            hooks.fill([{ key, question: blank.question, order, anyway: true }]);
          },
        }
      : null;
  if (status?.phase === 'paused') {
    const source = lane.lane === 'live' ? sourceName(lane.plan) : null;
    return status.why === 'offline'
      ? { Icon: WifiOff, title: 'Waiting for a connection', lines: [`${Device()} will ask ${source ?? 'the source'} once it is online, and the answer is written from what comes back.`], actions: [] }
      : { Icon: WifiOff, title: 'Paused', lines: [`Local only is on, so ${device()} doesn’t look this up. It goes on when Local only is off.`], actions: [] };
  }
  if (outcome) {
    const name = modelName(outcome.model);
    const says = {
      unknown: `${name} said it did not know.`,
      none: 'No answer came. Try the question in other words.',
      'didnt-fit': 'The answer did not fit the blank, so nothing was written.',
      nothing: outcome.words ?? 'Nothing came back for this.',
    }[outcome.why];
    return { Icon: outcome.why === 'nothing' ? WifiOff : MessageCircleQuestionMark, title: says, lines: [], actions: outcome.why === 'nothing' && anyway ? [anyway] : [] };
  }
  if (lane.lane === 'worked') {
    const { worked } = lane;
    return {
      Icon: FACT_ICONS[worked.icon],
      title: 'Worked out by the app',
      lines: [worked.working, 'The model was not asked.'],
      actions: editable
        ? [
            {
              Icon: TextCursorInput,
              label: 'Write it in',
              run: () => view.dispatch({ changes: { from: blank.from, to: blank.to, insert: worked.answer }, userEvent: 'input.fill' }),
            },
          ]
        : [],
    };
  }
  if (lane.lane === 'cannot') return { Icon: FACT_ICONS[lane.cannot.icon], title: 'The app can’t work this out', lines: [lane.cannot.words], actions: anyway ? [anyway] : [] };
  if (lane.lane === 'live') {
    const source = sourceName(lane.plan);
    const why =
      lane.can === 'none'
        ? lane.plan.kind === 'none'
          ? lane.plan.why
          : NO_SOURCE
        : lane.can === 'local-only'
          ? `Local only is on, so this waits. ${Device()} would ask ${source} for it.`
          : lane.can === 'off'
            ? `Look up blanks online is off in Settings, so ${device()} doesn’t ask the web.`
            : `On Fill, ${device()} asks ${source}, and the answer is written from what comes back. Only the question goes.`;
    return { Icon: lane.can === 'look' ? Wifi : WifiOff, title: lane.can === 'look' ? 'Looked up online' : 'The model can’t know this', lines: [liveWords(lane.live.kind), why], actions: lane.can === 'look' ? [] : anyway ? [anyway] : [] };
  }
  return null;
}

/** Shows `content` under the words at `at`, in place of any panel showing. */
function show(view: EditorView, at: number, content: PanelContent): void {
  close(view);
  // Where the words are drawn; at the editor's own corner where they are not laid out (off screen, or a test's page).
  const frame = view.dom.getBoundingClientRect();
  const coords = view.coordsAtPos(at) ?? { left: frame.left, bottom: frame.top };
  const panel = document.createElement('div');
  panel.className = PANEL;
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-label', content.title);
  const head = document.createElement('p');
  head.className = 'cm-fillPanelHead';
  const icon = document.createElement('span');
  icon.className = 'cm-fillPanelIcon';
  icon.appendChild(iconElement(content.Icon));
  head.append(icon, document.createTextNode(content.title));
  panel.appendChild(head);
  for (const line of content.lines) {
    const p = document.createElement('p');
    p.textContent = line;
    panel.appendChild(p);
  }
  if (content.actions.length) {
    const row = document.createElement('div');
    row.className = 'cm-fillPanelActions';
    for (const action of content.actions) {
      const button = document.createElement('button');
      button.type = 'button';
      const glyph = document.createElement('span');
      glyph.className = 'cm-fillPanelIcon';
      glyph.appendChild(iconElement(action.Icon));
      button.append(glyph, document.createTextNode(action.label));
      // The editor keeps the focus and the keyboard: a press here never takes them.
      button.addEventListener('mousedown', (event) => event.preventDefault());
      button.addEventListener('click', (event) => {
        event.preventDefault();
        close(view);
        action.run();
      });
      row.appendChild(button);
    }
    panel.appendChild(row);
  }
  panel.style.left = '0px';
  panel.style.top = `${coords.bottom - frame.top + 6}px`;
  view.dom.appendChild(panel);
  const width = panel.getBoundingClientRect().width;
  panel.style.left = `${Math.max(8, Math.min(coords.left - frame.left, frame.width - width - 8))}px`;
}

function close(view: EditorView): void {
  view.dom.querySelector(`.${PANEL}`)?.remove();
}

/** The panel for whatever sits at `at`: a blank's words after it, or a filled answer. */
export function openFillPanel(view: EditorView, at: number): boolean {
  const text = view.state.doc.toString();
  const fill = fillsIn(text).find((f) => at >= f.from && at <= f.to);
  if (fill) {
    show(view, fill.from + 2, fillContent(view, fill));
    return true;
  }
  const blank = blankMatches(text).find((b) => at >= b.from && at <= b.to);
  if (!blank) return false;
  const content = blankContent(view, blank);
  if (!content) return false;
  show(view, blank.from, content);
  return true;
}

const tapped = ViewPlugin.fromClass(
  class {
    update(update: { docChanged: boolean; view: EditorView }) {
      if (update.docChanged) close(update.view);
    }
  },
  {
    eventHandlers: {
      mousedown(event, view) {
        const target = event.target as HTMLElement | null;
        if (target?.closest(`.${PANEL}`)) return false;
        const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
        const text = view.state.doc.toString();
        const fill = pos === null ? null : fillsIn(text).find((f) => pos >= f.from + 2 && pos <= f.to);
        if (!fill) {
          close(view);
          return false;
        }
        // The caret still goes where the finger went, so the words can be edited straight after, as a mark's note does.
        show(view, fill.from + 2, fillContent(view, fill));
        return false;
      },
    },
  },
);

/** The panel, its look, and its tap on a filled answer. */
export function fillPanel(): Extension {
  return [
    Prec.high(tapped),
    panelOpener.of((view, at) => void openFillPanel(view, at)),
    EditorView.domEventHandlers({ scroll: (_event, view) => void close(view) }),
    EditorView.baseTheme({
      [`.${PANEL}`]: {
        position: 'absolute',
        zIndex: '30',
        maxInlineSize: 'min(22rem, 86vw)',
        padding: '0.55em 0.75em 0.6em',
        borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
        background: 'var(--app-paper-2, var(--glacier-surface))',
        border: '1px solid var(--app-rule, var(--glacier-border-subtle))',
        boxShadow: '0 6px 20px rgb(0 0 0 / 0.18)',
        font: 'inherit',
        fontSize: '0.84em',
        lineHeight: '1.4',
        color: 'var(--app-ink-2, currentColor)',
      },
      [`.${PANEL} p`]: { margin: '0 0 0.35em' },
      '.cm-fillPanelHead': { display: 'flex', alignItems: 'center', gap: '0.4em', color: 'var(--app-ink, currentColor)', fontWeight: '600' },
      '.cm-fillPanelIcon': { display: 'inline-flex', inlineSize: '1em', blockSize: '1em', flex: 'none' },
      '.cm-fillPanelIcon svg': { inlineSize: '1em', blockSize: '1em' },
      '.cm-fillPanelActions': { display: 'flex', flexWrap: 'wrap', gap: '0.2em 0.9em', marginBlockStart: '0.45em' },
      '.cm-fillPanelActions button': {
        appearance: 'none',
        border: 'none',
        background: 'transparent',
        padding: '0.3em 0',
        font: 'inherit',
        color: 'var(--app-ink, currentColor)',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '0.35em',
        cursor: 'pointer',
        WebkitTapHighlightColor: 'transparent',
      },
    }),
  ];
}
