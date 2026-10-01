import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { parseWhole } from '../../test/syntaxTree.ts';
import { FIELD_TAP, type FieldTap } from './fieldMenu.ts';
import { iconsSettled } from './iconDom.ts';
import { glyphMarkdown } from './language.ts';
import { taskFields } from './taskFields.ts';

/**
 * A to-do's fields drawn in a note (editor/taskFields.ts): a chip for each off the caret's line and the characters on
 * it, nothing in code or a blank's question, every chip quiet on a ticked item, and a tap on a chip with a menu told
 * to the menu (editor/ContextMenu.tsx listens) while the caret stays where it was. Thursday 1 October 2026.
 */

let view: EditorView | null = null;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'], now: new Date(2026, 9, 1, 12) });
});

afterEach(async () => {
  view?.destroy();
  view = null;
  vi.useRealTimers();
  vi.restoreAllMocks();
  await iconsSettled();
});

function open(doc: string, { anchor = 0, editable = true } = {}): EditorView {
  view = parseWhole(
    new EditorView({
      state: EditorState.create({ doc, selection: { anchor }, extensions: [glyphMarkdown(), taskFields(), EditorState.readOnly.of(!editable), EditorView.editable.of(editable)] }),
      parent: document.body,
    }),
  );
  return view;
}

const chips = (on: EditorView) => [...on.contentDOM.querySelectorAll<HTMLElement>('.cm-field')];
const labels = (on: EditorView) => chips(on).map((chip) => chip.getAttribute('aria-label'));
/** What line `n` reads as on the page: its words, and each chip's own words. */
const shown = (on: EditorView, n: number) => on.contentDOM.querySelectorAll('.cm-line')[n - 1]?.textContent ?? '';

describe('the chips', () => {
  it('draws each field on a to-do as its chip, in the line’s order', () => {
    const on = open('# Sprint\n- [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03');
    expect(labels(on)).toEqual(['Assigned to sam', 'High priority', expect.stringMatching(/^Due Saturday,? (?:3 October|October 3)$/)]);
    expect(chips(on).map((chip) => chip.dataset.tone)).toEqual(['plain', 'high', 'plain']);
    // The tag is a tag's, and the characters of the fields are not on the page while their chips are.
    expect(shown(on, 2)).not.toContain('📅');
    expect(shown(on, 2)).toContain('#bug');
  });

  it('colours a due day red once it has passed, amber on the day, and quiet once the box is ticked', () => {
    const on = open('x\n- [ ] Late 📅 2026-09-29\n- [ ] Now 📅 2026-10-01\n- [x] Done late 📅 2026-09-29 ⏫');
    expect(chips(on).map((chip) => chip.dataset.tone)).toEqual(['overdue', 'today', 'done', 'done']);
    expect(chips(on)[1]?.textContent).toBe('Today');
  });

  it('shows the line as written while the caret is on it, and the chips again once it leaves', () => {
    const on = open('Top\n- [ ] Fix it @sam 📅 2026-10-02');
    vi.spyOn(on, 'hasFocus', 'get').mockReturnValue(true);
    on.dispatch({ selection: { anchor: on.state.doc.length } });
    expect(chips(on)).toHaveLength(0);
    expect(shown(on, 2)).toBe('- [ ] Fix it @sam 📅 2026-10-02');
    on.dispatch({ selection: { anchor: 0 } });
    expect(chips(on)).toHaveLength(2);
  });

  it('draws the caret’s line too while the note is not being written', () => {
    const on = open('- [ ] Fix it 📅 2026-10-02', { anchor: 3 });
    expect(chips(on)).toHaveLength(1);
  });

  it('draws nothing in code, front matter or a blank’s question', () => {
    const on = open('---\nowner: @sam\n---\nSay `@sam ⏫` and {?who is @sam?}\n\n```\n- [ ] 📅 2026-10-02\n```');
    expect(labels(on)).toEqual([]);
  });

  it('draws a person anywhere in the words, as a tag is drawn', () => {
    const on = open('Ask @sam about it.');
    expect(labels(on)).toEqual(['Assigned to sam']);
  });
});

describe('a tap on a chip', () => {
  function tapped(on: EditorView): FieldTap[] {
    const heard: FieldTap[] = [];
    on.dom.addEventListener(FIELD_TAP, (event) => heard.push((event as CustomEvent<FieldTap>).detail));
    return heard;
  }

  it('tells the menu which field and which line, and keeps the caret where it was', () => {
    const on = open('Top\n- [ ] Fix it @sam ⏫ 📅 2026-10-02');
    const heard = tapped(on);
    const [person, priority, due] = chips(on);
    const down = new MouseEvent('mousedown', { bubbles: true, cancelable: true });
    due!.dispatchEvent(down);
    expect(down.defaultPrevented).toBe(true);
    for (const chip of [due!, priority!, person!]) chip.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    expect(heard.map((tap) => [tap.page, tap.line])).toEqual([
      [{ kind: 'date', key: 'due' }, 2],
      [{ kind: 'priority' }, 2],
      [{ kind: 'person', name: 'sam' }, 2],
    ]);
    expect(on.state.selection.main.head).toBe(0);
    expect(due!.getAttribute('role')).toBe('button');
  });

  it('is the editor’s on a chip with no menu, and on a page that cannot be edited', () => {
    const on = open('- [ ] Water the plants 🔁 every week [effort:: 3]');
    const heard = tapped(on);
    for (const chip of chips(on)) {
      expect(chip.getAttribute('role')).toBeNull();
      chip.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    }
    expect(heard).toEqual([]);
    view?.destroy();

    const reading = open('- [ ] Fix it 📅 2026-10-02', { editable: false });
    const none = tapped(reading);
    chips(reading)[0]!.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    expect(none).toEqual([]);
    expect(chips(reading)[0]?.getAttribute('role')).toBeNull();
  });
});
