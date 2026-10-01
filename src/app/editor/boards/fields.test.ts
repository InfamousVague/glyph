import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { drawnBoards } from '../boards.ts';
import { FIELD_TAP, type FieldTap } from '../fieldMenu.ts';
import { iconsSettled } from '../iconDom.ts';
import { glyphMarkdown } from '../language.ts';

/**
 * A card's fields (editor/boards/fields.ts): the item's words without them, and its due day, priority and people as
 * chips of the card's own in its footer, quiet once the card is ticked, a tap on one opening its page of the
 * press-and-hold menu for the item's line. Thursday 1 October 2026.
 */

const doc = [
  '```board',
  'To do: login, notes',
  'Done: demo',
  '```',
  '',
  '- [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03 🔁 every week ^login',
  '- [ ] Write the notes ^notes',
  '- [x] Book the demo room @matt 📅 2026-09-28 ^demo',
].join('\n');

let view: EditorView | null = null;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'], now: new Date(2026, 9, 1, 12) });
});

afterEach(async () => {
  view?.destroy();
  view = null;
  vi.useRealTimers();
  await iconsSettled();
});

function open(text: string, readOnly = false): EditorView {
  view = new EditorView({ state: EditorState.create({ doc: text, extensions: [glyphMarkdown(), drawnBoards(), EditorState.readOnly.of(readOnly)] }), parent: document.body });
  return view;
}

const card = (on: EditorView, id: string) => on.dom.querySelector<HTMLElement>(`.cm-boardCard[data-card="${id}"]`)!;
const chips = (element: HTMLElement) => [...element.querySelectorAll<HTMLElement>('.cm-boardFields .cm-field')];

describe('a card’s fields', () => {
  it('says the item’s words without them, and shows its due day, priority and people as chips', () => {
    const on = open(doc);
    const login = card(on, 'login');
    expect(login.querySelector('.cm-boardWords')?.textContent).toBe('Fix the login loop #bug');
    expect(chips(login).map((chip) => chip.getAttribute('aria-label'))).toEqual(['Assigned to sam', 'High priority', expect.stringMatching(/^Due Saturday/)]);
    // A recurrence is the line's to show, not the card's.
    expect(login.textContent).not.toContain('every week');
  });

  it('has no row of chips for an item with no fields', () => {
    expect(card(open(doc), 'notes').querySelector('.cm-boardFields')).toBeNull();
  });

  it('quiets the chips of a ticked card', () => {
    expect(chips(card(open(doc), 'demo')).map((chip) => chip.dataset.tone)).toEqual(['done', 'done']);
  });

  it('opens the press-and-hold menu on a chip’s page for the item’s line', () => {
    const on = open(doc);
    const heard: FieldTap[] = [];
    on.dom.addEventListener(FIELD_TAP, (event) => heard.push((event as CustomEvent<FieldTap>).detail));
    const due = chips(card(on, 'login'))[2]!;
    due.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    expect(heard.map((tap) => [tap.page, tap.line])).toEqual([[{ kind: 'date', key: 'due' }, 6]]);
  });

  it('draws them but opens nothing on a page that cannot be edited', () => {
    const on = open(doc, true);
    const heard: FieldTap[] = [];
    on.dom.addEventListener(FIELD_TAP, (event) => heard.push((event as CustomEvent<FieldTap>).detail));
    const due = chips(card(on, 'login'))[2]!;
    due.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    expect(heard).toEqual([]);
  });
});
