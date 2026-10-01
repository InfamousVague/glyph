import { history, undo } from '@codemirror/commands';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { dayChoices, lineFields, peopleIn, pickDay, setLineField, setLinePerson, startPerson, takesFields } from './fieldMenu.ts';

/**
 * What the press-and-hold menu does with a to-do's fields (editor/fieldMenu.ts): the days it offers, the people it
 * knows, each edit as one change of one line that one undo takes back, and the phone's own date picker.
 */

let view: EditorView | null = null;

function open(doc: string, readOnly = false): EditorView {
  view = new EditorView({ state: EditorState.create({ doc, extensions: [history(), EditorState.readOnly.of(readOnly)] }), parent: document.body });
  return view;
}

afterEach(() => {
  view?.destroy();
  view = null;
  document.querySelectorAll('input.glyph-pickDay').forEach((input) => input.remove());
});

describe('what the menu offers', () => {
  it('offers today, tomorrow and next week’s Monday', () => {
    expect(dayChoices('2026-10-01')).toEqual([
      { id: 'today', label: 'Today', day: '2026-10-01' },
      { id: 'tomorrow', label: 'Tomorrow', day: '2026-10-02' },
      { id: 'next-week', label: 'Next week', day: '2026-10-05' },
    ]);
    expect(dayChoices('2026-10-04').at(-1)?.day).toBe('2026-10-05');
  });

  it('offers fields on a list item, and on nothing else', () => {
    expect(takesFields('- [ ] Fix it')).toBe(true);
    expect(takesFields('2. Step')).toBe(true);
    expect(takesFields('- Bullet')).toBe(true);
    expect(takesFields('Just words')).toBe(false);
    expect(takesFields('# Heading')).toBe(false);
  });

  it('knows the people a note names, each once, and none in code', () => {
    expect(peopleIn('- [ ] One @sam\n- [ ] Two @Sam @matt\nSee `@jo` and @@@kim@@\n- [ ] Three @sam-ortiz')).toEqual(['sam', 'matt', 'sam-ortiz']);
  });
});

describe('the edits', () => {
  it('sets, changes and takes off a field as one edit each', () => {
    const on = open('Top\n- [ ] Fix the login loop ^login-loop');
    expect(setLineField(on, 2, 'due', '2026-10-03')).toBe(true);
    expect(on.state.doc.line(2).text).toBe('- [ ] Fix the login loop 📅 2026-10-03 ^login-loop');
    expect(setLineField(on, 2, 'priority', 'high')).toBe(true);
    expect(on.state.doc.line(2).text).toBe('- [ ] Fix the login loop ⏫ 📅 2026-10-03 ^login-loop');
    expect(lineFields(on, 2)).toMatchObject({ due: '2026-10-03', priority: 'high' });
    undo(on);
    expect(on.state.doc.line(2).text).toBe('- [ ] Fix the login loop 📅 2026-10-03 ^login-loop');
    expect(setLineField(on, 2, 'due', null)).toBe(true);
    expect(on.state.doc.line(2).text).toBe('- [ ] Fix the login loop ^login-loop');
  });

  it('changes only what differs, so the caret elsewhere on the line stays put', () => {
    const on = open('- [ ] Fix it 📅 2026-10-03');
    on.dispatch({ selection: { anchor: 8 } });
    setLineField(on, 1, 'due', '2026-10-09');
    expect(on.state.doc.toString()).toBe('- [ ] Fix it 📅 2026-10-09');
    expect(on.state.selection.main.head).toBe(8);
  });

  it('puts people on and takes them off', () => {
    const on = open('- [ ] Fix it ⏫');
    setLinePerson(on, 1, 'Sam', true);
    expect(on.state.doc.toString()).toBe('- [ ] Fix it @Sam ⏫');
    expect(setLinePerson(on, 1, 'sam', true)).toBe(false);
    setLinePerson(on, 1, 'sam', false);
    expect(on.state.doc.toString()).toBe('- [ ] Fix it ⏫');
  });

  it('leaves the at sign where a new person goes, with the caret after it', () => {
    const on = open('- [ ] Fix it #bug ⏫ 📅 2026-10-03');
    expect(startPerson(on, 1)).toBe(true);
    expect(on.state.doc.toString()).toBe('- [ ] Fix it #bug @ ⏫ 📅 2026-10-03');
    expect(on.state.selection.main.head).toBe('- [ ] Fix it #bug @'.length);
  });

  it('writes nothing on a page that cannot be edited, or a line that is not there', () => {
    const on = open('- [ ] Fix it', true);
    expect(setLineField(on, 1, 'due', '2026-10-03')).toBe(false);
    expect(startPerson(on, 1)).toBe(false);
    view?.destroy();
    const other = open('- [ ] Fix it');
    expect(setLineField(other, 4, 'due', '2026-10-03')).toBe(false);
    expect(setLineField(other, 1, 'due', 'Friday')).toBe(false);
    expect(lineFields(other, 9)).toBeNull();
  });
});

describe('a day picked', () => {
  it('opens the phone’s own picker on its day, and hands back the day chosen', () => {
    const shown = vi.fn();
    Object.defineProperty(HTMLInputElement.prototype, 'showPicker', { configurable: true, value: shown });
    const picked = vi.fn();
    pickDay({ x: 10, y: 20 }, '2026-10-03', picked);
    const input = document.querySelector<HTMLInputElement>('input.glyph-pickDay')!;
    expect(input.type).toBe('date');
    expect(input.value).toBe('2026-10-03');
    expect(shown).toHaveBeenCalledTimes(1);
    input.value = '2026-10-09';
    input.dispatchEvent(new Event('change'));
    expect(picked).toHaveBeenCalledWith('2026-10-09');
    expect(document.querySelector('input.glyph-pickDay')).toBeNull();
    delete (HTMLInputElement.prototype as { showPicker?: unknown }).showPicker;
  });

  it('keeps one picker at a time, and hands back nothing for a cleared field', () => {
    const picked = vi.fn();
    pickDay({ x: 0, y: 0 }, null, picked);
    pickDay({ x: 0, y: 0 }, null, picked);
    const inputs = document.querySelectorAll<HTMLInputElement>('input.glyph-pickDay');
    expect(inputs).toHaveLength(1);
    inputs[0]!.value = '';
    inputs[0]!.dispatchEvent(new Event('change'));
    expect(picked).not.toHaveBeenCalled();
  });
});
