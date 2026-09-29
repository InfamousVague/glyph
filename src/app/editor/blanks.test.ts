import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorSelection, EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { MARKS } from '../plugins/marks/index.tsx';
import { parseWhole } from '../../test/syntaxTree.ts';
import { forgetFills } from '../ai/fills/queue.ts';
import { blanks, blanksField, editorBlanks, fillAll, fillableBlanks, PAUSE_MS, type BlankHooks } from './blanks.ts';
import { glyphMarkdown } from './language.ts';
import { noteView } from './viewMode.ts';

const views: EditorView[] = [];
afterEach(() => {
  views.splice(0).forEach((v) => v.destroy());
  forgetFills();
  vi.useRealTimers();
});

/** Hooks as the note screen gives them, on Monday 28 September 2026 in London. */
function hooks(overrides: Partial<BlankHooks> = {}): BlankHooks & { pressed: unknown[][]; said: string[] } {
  const pressed: unknown[][] = [];
  const said: string[] = [];
  return {
    pressed,
    said,
    noteId: () => 'n1',
    canFill: () => true,
    learntUntil: () => 2024,
    lookups: () => 'on',
    fill: (targets) => void pressed.push(targets),
    say: (message) => void said.push(message),
    now: () => new Date(Date.UTC(2026, 8, 28, 13, 5)),
    zone: () => 'Europe/London',
    ...overrides,
  };
}

function editor(doc: string, given: BlankHooks | null = hooks(), options: { formatted?: boolean; anchor?: number } = {}): EditorView {
  const view = new EditorView({
    state: EditorState.create({
      doc,
      selection: options.anchor !== undefined ? EditorSelection.cursor(options.anchor) : undefined,
      extensions: [glyphMarkdown(MARKS, []), blanks(given), noteView(options.formatted ? 'formatted' : 'mixed')],
    }),
    parent: document.body,
  });
  views.push(view);
  return parseWhole(view);
}

const html = (view: EditorView) => view.contentDOM.innerHTML;
const squares = (view: EditorView) => [...view.contentDOM.querySelectorAll('.cm-blank')];
const labels = (view: EditorView) => squares(view).map((s) => s.getAttribute('aria-label'));
const pills = (view: EditorView) => [...view.contentDOM.querySelectorAll('.cm-fillPill')].map((p) => p.textContent);
const after = (view: EditorView) => [...view.contentDOM.querySelectorAll('.cm-blankWords, .cm-blankAnswer')].map((w) => w.textContent);

describe('the square', () => {
  it('draws a blank in a dashed box, its braces dim in the Markdown view', () => {
    const view = editor('Flights are cheapest on {?what day / time?}');
    expect(squares(view)).toHaveLength(1);
    expect(view.contentDOM.querySelectorAll('.cm-blankMark')).toHaveLength(2);
    expect(view.contentDOM.querySelector('.cm-blankQuestion')?.textContent).toBe('what day / time?');
    expect(labels(view)).toEqual(['A blank for the AI: what day / time?']);
  });

  it('keeps a short square on one line, and lets a long question wrap', () => {
    const view = editor('Weather in Lisbon tomorrow: {?weather}\n\nA plan: {?a friendlier way to say: fix the boiler now, and the date}');
    const [short, long] = [...view.contentDOM.querySelectorAll<HTMLElement>('.cm-blank[role="group"]')];
    expect(short!.hasAttribute('data-short')).toBe(true);
    expect(long!.hasAttribute('data-short')).toBe(false);
  });

  it('hides the braces in the Formatted view, but on the line being written', () => {
    const view = editor('Flights are cheapest on {?which day}\n\nAnother line', hooks(), { formatted: true, anchor: 40 });
    expect(html(view)).not.toContain('{?');
    view.focus();
    view.dispatch({ selection: { anchor: 5 } });
    expect(view.contentDOM.querySelectorAll('.cm-blankMark').length).toBe(view.hasFocus ? 2 : 0);
  });

  it('draws nothing in code, maths, a comment, a link’s address or front matter', () => {
    const view = editor('---\ntitle: {?x}\n---\nA `{?code}` and $x {?m}$ and <!-- {?c} --> and [w](https://a.b/{?u})\n\n```\n{?fenced}\n```');
    expect(squares(view)).toHaveLength(0);
    expect(editorBlanks(view.state)).toHaveLength(0);
  });
});

describe('the icon and what follows', () => {
  it('says what will happen: the model, the app’s working, a lookup, or nothing to be known', () => {
    const view = editor(['Flights are cheapest on {?which day}', 'Days until Christmas: {?}', 'Weather in Lisbon today: {?weather}', 'Days until Easter: {?}', 'A return flight costs {?price today}'].join('\n\n'));
    expect(labels(view)).toEqual([
      'A blank for the AI: which day',
      'Worked out: Days until Christmas:',
      'Looked up online when pressed: weather',
      "Can't work out: Days until Easter:",
      'No source to ask: price today',
    ]);
    expect(after(view)).toEqual(['88 days', 'Can’t work out', 'No source to ask']);
    expect(view.contentDOM.querySelectorAll('.cm-blankIcon svg')).toHaveLength(5);
  });

  it('keeps a live blank paused under Local only, and refused with Look up blanks online off', () => {
    expect(after(editor('Weather in Lisbon today: {?weather}', hooks({ lookups: () => 'local-only' })))).toEqual(['Paused']);
    expect(after(editor('Weather in Lisbon today: {?weather}', hooks({ lookups: () => 'off' })))).toEqual(['Can’t know offline']);
  });

  it('redraws a worked-out answer as a number changes', () => {
    const view = editor('- Cabin $200\n- Ferry $45\n- Food $80\n\nTotal so far: {?total}');
    expect(after(view)).toEqual(['$325']);
    view.dispatch({ changes: { from: view.state.doc.toString().indexOf('$80') + 1, to: view.state.doc.toString().indexOf('$80') + 3, insert: '95' } });
    expect(after(view)).toEqual(['$340']);
  });

  it('draws no icon while the caret is inside the braces', () => {
    const view = editor('Cheapest on {?which day}', hooks(), { anchor: 16 });
    view.focus();
    view.dispatch({ selection: { anchor: 16 } });
    if (view.hasFocus) expect(view.contentDOM.querySelectorAll('.cm-blankIcon')).toHaveLength(0);
  });
});

describe('the Fill pill', () => {
  it('counts the line’s blanks for the model and leaves out the rest', () => {
    const view = editor('Cheapest on {?which day} and {?which airport}\n\nDays until Christmas: {?}\n\nThe capital is {?}.');
    expect(pills(view)).toEqual(['Fill 2', 'Fill']);
  });

  it('is not drawn where the model can never run', () => {
    expect(pills(editor('Cheapest on {?which day}', hooks({ canFill: () => false })))).toEqual([]);
    expect(pills(editor('Cheapest on {?which day}', null))).toEqual([]);
  });

  it('presses its line’s blanks, tracked from then on', () => {
    const given = hooks();
    const view = editor('Cheapest on {?which day}\n\nThe capital is {?}.', given);
    (view.contentDOM.querySelector('.cm-fillPill') as HTMLButtonElement).click();
    expect(given.pressed).toEqual([[{ key: 'which day\u00000', question: 'which day', order: 0 }]]);
    expect(view.state.field(blanksField).get('which day\u00000')).toEqual({ from: 12, to: 24 });
    view.dispatch({ changes: { from: 0, insert: 'Oh. ' } });
    expect(view.state.field(blanksField).get('which day\u00000')).toEqual({ from: 16, to: 28 });
  });

  it('waits on the line being typed until the hands have stopped', () => {
    vi.useFakeTimers();
    const view = editor('Cheapest on ', hooks(), { anchor: 12 });
    view.focus();
    view.dispatch({ changes: { from: 12, insert: '{?which day}' }, selection: { anchor: 24 }, userEvent: 'input.type' });
    if (view.hasFocus) expect(pills(view)).toEqual([]);
    vi.advanceTimersByTime(PAUSE_MS + 10);
    expect(pills(view)).toEqual(['Fill']);
  });
});

describe('Fill the blanks', () => {
  it('takes every blank the model or a lookup can answer, top to bottom', () => {
    const given = hooks();
    const view = editor('Cheapest on {?which day}\n\nDays until Christmas: {?}\n\nWeather in Lisbon today: {?weather}\n\nThe capital is {?}.', given);
    expect(fillableBlanks(view.state).map((b) => b.question)).toEqual(['which day', 'weather', '']);
    expect(fillAll(view)).toBe(3);
    expect((given.pressed[0] as { question: string }[]).map((t) => t.question)).toEqual(['which day', 'weather', '']);
  });

  it('says why a title has nothing to be named from, and runs nothing', () => {
    const given = hooks();
    const view = editor('# {?}\n\nToo few words.', given);
    expect(fillAll(view)).toBe(0);
    expect(given.said).toEqual(['Write a few lines first. The title is made from them.']);
  });
});
