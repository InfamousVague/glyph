import { act } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { button, show } from '../../test/render.tsx';
import { ContextMenu } from './ContextMenu.tsx';
import { tapField, type FieldPage } from './fieldMenu.ts';
import { iconsSettled } from './iconDom.ts';
import { taskFields } from './taskFields.ts';

/**
 * A to-do's fields on the press-and-hold menu (editor/FieldItems.tsx, through editor/ContextMenu.tsx): Due date,
 * Priority and Assign among a list item's actions and nowhere else, a chip's tap opening its own page at the chip,
 * and each page's presses written into the line. Thursday 1 October 2026.
 */

let view: EditorView;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'], now: new Date(2026, 9, 1, 12) });
});

afterEach(async () => {
  view?.destroy();
  vi.useRealTimers();
  await iconsSettled();
});

function editor(doc: string, anchor = 0, extensions = [taskFields()]): EditorView {
  view = new EditorView({ state: EditorState.create({ doc, selection: { anchor }, extensions }), parent: document.body });
  return view;
}

const menu = () => document.querySelector<HTMLElement>('[role="menu"]');
const words = () => [...(menu()?.querySelectorAll('button') ?? [])].map((b) => b.textContent);
const line = (n: number) => view.state.doc.line(n).text;
const frame = () => act(async () => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));

/** A right click on the note: the line's own actions, over the caret. */
async function hold(): Promise<void> {
  act(() => {
    view.contentDOM.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 20, clientY: 20 }));
  });
  await frame();
}

function tap(page: FieldPage, n: number): void {
  act(() => tapField(view, { page, line: n, x: 40, y: 60 }));
}

async function choose(label: string): Promise<void> {
  await act(async () => button(label, menu()!).click());
}

describe('among a line’s actions', () => {
  it('offers Due date, Priority and Assign on a list item', async () => {
    editor('- [ ] Fix the login loop', 3);
    show(<ContextMenu view={view} />);
    await hold();
    expect(words()).toEqual(expect.arrayContaining(['Due date', 'Priority', 'Assign']));
  });

  it('offers none of them on a line of words', async () => {
    editor('Just a sentence.', 3);
    show(<ContextMenu view={view} />);
    await hold();
    expect(words()).not.toContain('Due date');
  });

  it('turns the band over to a field’s page and back', async () => {
    editor('- [ ] Fix the login loop', 3);
    show(<ContextMenu view={view} />);
    await hold();
    await choose('Due date');
    expect(menu()?.getAttribute('aria-label')).toBe('Fields');
    expect(words()).toEqual(['Back', 'Today', 'Tomorrow', 'Next week', 'Pick a date']);
    await choose('Back');
    expect(menu()?.getAttribute('aria-label')).toBe('Note actions');
  });

  it('writes the day pressed where Obsidian Tasks reads it, and closes', async () => {
    editor('- [ ] Fix the login loop ^login-loop', 3);
    show(<ContextMenu view={view} />);
    await hold();
    await choose('Due date');
    await choose('Next week');
    expect(line(1)).toBe('- [ ] Fix the login loop 📅 2026-10-05 ^login-loop');
    expect(menu()).toBeNull();
  });

  it('assigns the people the note names, one press each, and someone new by their at sign', async () => {
    editor('- [ ] Fix the login loop\n- [ ] Ask @sam\n- [ ] Tell @matt', 3);
    show(<ContextMenu view={view} />);
    await hold();
    await choose('Assign');
    expect(words()).toEqual(['Back', 'sam', 'matt', 'Someone new']);
    await choose('Assign sam');
    expect(line(1)).toBe('- [ ] Fix the login loop @sam');
    // It stays open for a second, with the first lit.
    expect(button('Take sam off', menu()!).getAttribute('aria-checked')).toBe('true');
    await choose('Someone new');
    expect(line(1)).toBe('- [ ] Fix the login loop @sam @');
    expect(view.state.selection.main.head).toBe(line(1).length);
    expect(menu()).toBeNull();
  });
});

describe('from a chip', () => {
  it('opens a due day’s page at the chip, its day lit, with Remove', async () => {
    editor('Top\n- [ ] Fix it 📅 2026-10-02');
    show(<ContextMenu view={view} />);
    tap({ kind: 'date', key: 'due' }, 2);
    expect(words()).toEqual(['Today', 'Tomorrow', 'Next week', 'Pick a date', 'Remove']);
    expect(button('Due tomorrow', menu()!).getAttribute('aria-checked')).toBe('true');
    expect(menu()?.style.left).not.toBe('');
    await choose('Remove the due date');
    expect(line(2)).toBe('- [ ] Fix it');
  });

  it('offers the five priorities and None, the one it has lit', async () => {
    editor('- [ ] Fix it ⏫ 📅 2026-10-02');
    show(<ContextMenu view={view} />);
    tap({ kind: 'priority' }, 1);
    expect(words()).toEqual(['Highest', 'High', 'Medium', 'Low', 'Lowest', 'None']);
    expect(button('High priority', menu()!).getAttribute('aria-checked')).toBe('true');
    await choose('Lowest priority');
    expect(line(1)).toBe('- [ ] Fix it ⏬ 📅 2026-10-02');
    tap({ kind: 'priority' }, 1);
    await choose('No priority');
    expect(line(1)).toBe('- [ ] Fix it 📅 2026-10-02');
  });

  it('takes a person off', async () => {
    editor('- [ ] Fix it @sam @matt');
    show(<ContextMenu view={view} />);
    tap({ kind: 'person', name: 'sam' }, 1);
    expect(words()).toEqual(['Remove']);
    await choose('Take sam off');
    expect(line(1)).toBe('- [ ] Fix it @matt');
  });

  it('opens Pick a date on the phone’s own picker, and writes the day chosen', async () => {
    const shown = vi.fn();
    Object.defineProperty(HTMLInputElement.prototype, 'showPicker', { configurable: true, value: shown });
    editor('- [ ] Fix it');
    show(<ContextMenu view={view} />);
    tap({ kind: 'date', key: 'start' }, 1);
    await choose('Pick a date');
    expect(shown).toHaveBeenCalled();
    expect(menu()).toBeNull();
    const input = document.querySelector<HTMLInputElement>('input.glyph-pickDay')!;
    input.value = '2026-10-12';
    act(() => {
      input.dispatchEvent(new Event('change'));
    });
    expect(line(1)).toBe('- [ ] Fix it 🛫 2026-10-12');
    delete (HTMLInputElement.prototype as { showPicker?: unknown }).showPicker;
  });

  it('opens from a chip drawn in the note', async () => {
    editor('Top\n- [ ] Fix it ⏫');
    show(<ContextMenu view={view} />);
    const chip = view.contentDOM.querySelector<HTMLElement>('.cm-field')!;
    act(() => {
      chip.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    });
    expect(words()).toContain('Highest');
  });
});
