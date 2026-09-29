import { afterEach, describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { MARKS } from '../plugins/marks/index.tsx';
import { inLocale } from '../../test/locale.ts';
import { parseWhole } from '../../test/syntaxTree.ts';
import { MODEL_LIMITS } from '../core/ai.ts';
import { forgetFills } from '../ai/fills/queue.ts';
import { blanks, type BlankHooks } from './blanks.ts';
import { fillPanel, openFillPanel } from './fillPanel.ts';
import { glyphMarkdown } from './language.ts';

const views: EditorView[] = [];
afterEach(() => {
  views.splice(0).forEach((v) => v.destroy());
  forgetFills();
});

function hooks(overrides: Partial<BlankHooks> = {}): BlankHooks & { pressed: unknown[][] } {
  const pressed: unknown[][] = [];
  return {
    pressed,
    noteId: () => 'n1',
    canFill: () => true,
    learntUntil: () => 2024,
    lookups: () => 'on',
    fill: (targets) => void pressed.push(targets),
    say: () => undefined,
    now: () => new Date(Date.UTC(2026, 8, 28, 13, 5)),
    zone: () => 'Europe/London',
    ...overrides,
  };
}

function editor(doc: string, given: BlankHooks | null = hooks(), readOnly = false): EditorView {
  const view = new EditorView({
    state: EditorState.create({ doc, extensions: [glyphMarkdown(MARKS, []), blanks(given), fillPanel(), EditorState.readOnly.of(readOnly), EditorView.editable.of(!readOnly)] }),
    parent: document.body,
  });
  views.push(view);
  return parseWhole(view);
}

/** The panel's words, its title first, and its actions, opened on what sits at `at`. */
function panel(view: EditorView, at: number): { words: string[]; actions: string[] } {
  inLocale('en-GB', () => openFillPanel(view, at));
  const shown = view.dom.querySelector('.cm-fillPanel');
  return {
    words: [...(shown?.querySelectorAll('p') ?? [])].map((p) => p.textContent ?? ''),
    actions: [...(shown?.querySelectorAll('button') ?? [])].map((b) => b.textContent ?? ''),
  };
}
const press = (view: EditorView, label: string) => ([...view.dom.querySelectorAll('.cm-fillPanel button')].find((b) => b.textContent === label) as HTMLButtonElement).click();

const TOKYO = 'Flights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)';

describe('the panel on a filled answer', () => {
  it('says whose it is, from memory, when and what was asked, and the one sentence about every model', () => {
    const view = editor(TOKYO);
    expect(panel(view, TOKYO.indexOf('midweek'))).toEqual({
      words: ['Qwen3.5 4B, from memory', 'Asked on 28 September 2026: what day / time?', MODEL_LIMITS, 'General advice, not today’s fares.'],
      actions: ['Keep as mine', 'Ask again', 'Put the question back'],
    });
  });

  it('says from this note, and from the web with its source', () => {
    const note = 'Who brings the charger? ??Sam??(Qwen3.5 4B from this note, 2026-09-28)';
    expect(panel(editor(note), note.indexOf('Sam'))?.words.slice(0, 1)).toEqual(['Qwen3.5 4B, from this note']);
    const web = 'Weather in Lisbon tomorrow: ??Rain??(Qwen3.5 4B from Open-Meteo, 2026-09-28. Asked: weather)';
    expect(panel(editor(web), web.indexOf('Rain')).words[2]).toBe('The phone asked Open-Meteo, and the model wrote this from what came back. It can still be wrong.');
  });

  it('keeps an answer as the person’s own, or puts the question back', () => {
    const view = editor(TOKYO);
    panel(view, TOKYO.indexOf('midweek'));
    press(view, 'Keep as mine');
    expect(view.state.doc.toString()).toBe('Flights are cheapest to Tokyo on midweek');
    const again = editor(TOKYO);
    panel(again, TOKYO.indexOf('midweek'));
    press(again, 'Put the question back');
    expect(again.state.doc.toString()).toBe('Flights are cheapest to Tokyo on {?what day / time?}');
  });

  it('puts three items back as one blank, and leaves a second fill of the same question alone', () => {
    const item = (words: string, n: number) => `- ??${words}??(Qwen3.5 4B from memory, 2026-09-28. Asked: more. ${n} of 3)`;
    const note = ['## Packing', '- Passport', item('Rail pass', 1), item('Shoes', 2), item('Cash', 3), item('Umbrella', 1), item('Hat', 2), item('Map', 3)].join('\n');
    const view = editor(note);
    panel(view, note.indexOf('Shoes'));
    press(view, 'Put the question back');
    expect(view.state.doc.toString()).toBe(['## Packing', '- Passport', '- {?more}', item('Umbrella', 1), item('Hat', 2), item('Map', 3)].join('\n'));
  });

  it('asks again for the whole answer, told what it is not', () => {
    const given = hooks();
    const note = 'The 2022 World Cup was won by ??France??(Qwen3.5 4B from memory, 2026-09-28)';
    const view = editor(note, given);
    panel(view, note.indexOf('France'));
    press(view, 'Ask again');
    expect(given.pressed).toEqual([[{ key: `again\u0000${note.indexOf('??')}`, question: '', order: 0, again: { mark: note.slice(note.indexOf('??')), words: 'France' } }]]);
  });

  it('has no actions where the note is only read', () => {
    expect(panel(editor(TOKYO, null, true), TOKYO.indexOf('midweek')).actions).toEqual([]);
  });
});

describe('the panel on a blank', () => {
  it('shows a worked-out answer’s working, and writes it in', () => {
    const note = '- Cabin $200\n- Ferry $45\n\nTotal: {?}';
    const view = editor(note);
    expect(panel(view, note.indexOf('{?'))).toEqual({ words: ['Worked out by the app', '$200 + $45 = $245.', 'The model was not asked.'], actions: ['Write it in'] });
    press(view, 'Write it in');
    expect(view.state.doc.toString()).toBe('- Cabin $200\n- Ferry $45\n\nTotal: $245');
  });

  it('says why the app can’t, and asks the model anyway', () => {
    const given = hooks();
    const note = 'Days until Easter: {?}';
    const view = editor(note, given);
    expect(panel(view, note.indexOf('{?'))).toEqual({ words: ['The app can’t work this out', 'Easter moves each year, and the app does not know when it falls.'], actions: ['Ask the model anyway'] });
    press(view, 'Ask the model anyway');
    expect(given.pressed).toEqual([[{ key: '\u00000', question: '', order: 0, anyway: true }]]);
  });

  it('says a live blank no source answers can’t be known offline', () => {
    const note = 'A return flight costs {?price today}';
    const view = editor(note);
    expect(panel(view, note.indexOf('{?'))).toEqual({
      words: ['The model can’t know this', 'Prices change, and the model has no internet.', 'No public source the phone can ask answers this.'],
      actions: ['Ask the model anyway'],
    });
  });

  it('offers no Ask anyway where the model can never run', () => {
    const note = 'Days until Easter: {?}';
    expect(panel(editor(note, hooks({ canFill: () => false })), note.indexOf('{?')).actions).toEqual([]);
  });
});
