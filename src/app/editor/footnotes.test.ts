import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { glyphMarkdown } from './language.ts';
import { footnotes, footnotesIn, noteAtPos } from './footnotes.ts';

const doc = [
  'The deposit is four hundred[^sam], not four fifty[^bank].',
  '',
  '[^sam]: Sam said so on the phone.',
  '[^bank]: The bank statement disagrees.',
].join('\n');

function drawn(text: string) {
  const view = new EditorView({ state: EditorState.create({ doc: text, extensions: [glyphMarkdown([], []), footnotes()] }), parent: document.body });
  const html = view.contentDOM.innerHTML;
  const state = view.state;
  view.destroy();
  return { html, state };
}

describe('the footnotes a note defines', () => {
  it('reads each one by name, with what it says', () => {
    expect(footnotesIn(doc)).toEqual([
      { name: 'sam', text: 'Sam said so on the phone.', line: 3 },
      { name: 'bank', text: 'The bank statement disagrees.', line: 4 },
    ]);
  });

  it('takes the first of a name written twice, and nothing from a note with none', () => {
    expect(footnotesIn('[^a]: one\n[^a]: two')).toHaveLength(1);
    expect(footnotesIn('just words')).toEqual([]);
  });
});

describe('how they are drawn', () => {
  it('raises a marker that has a definition, and sets the definition quietly', () => {
    const { html } = drawn(doc);
    expect(html).toContain('cm-footMark');
    expect(html).toContain('cm-footDefinition');
  });

  it('leaves a marker with nothing to point at as plain words', () => {
    expect(drawn('a claim[^nowhere] here').html).not.toContain('cm-footMark');
  });

  it('never marks the definition’s own name as a reference', () => {
    const { html } = drawn('[^sam]: Sam said so.');
    expect(html).not.toContain('cm-footMark');
  });
});

describe('the panel a tap on a marker opens', () => {
  let view: EditorView | null = null;

  afterEach(() => {
    view?.destroy();
    view = null;
    vi.restoreAllMocks();
  });

  /**
   * The note in an editor 300 px wide, a tap landing at `pos`. jsdom lays nothing out, so where the tap lands and
   * where the words are drawn are said here: the marker at 250 px across, and the panel 120 px wide once drawn.
   */
  function tapAt(pos: number): EditorView {
    view ??= new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown([], []), footnotes()] }), parent: document.body });
    const on = view;
    vi.spyOn(on, 'posAtCoords').mockReturnValue(pos);
    vi.spyOn(on, 'coordsAtPos').mockReturnValue({ left: 250, right: 260, top: 40, bottom: 60 });
    vi.spyOn(on.dom, 'getBoundingClientRect').mockReturnValue(new DOMRect(0, 20, 300, 400));
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue(new DOMRect(0, 0, 120, 30));
    on.contentDOM.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: 250, clientY: 50 }));
    return on;
  }
  const panel = (on: EditorView) => on.dom.querySelector<HTMLElement>('.cm-footPanel');

  it('says what the footnote says, under the marker and held inside the note’s width', () => {
    const on = tapAt(doc.indexOf('[^sam]') + 2);
    expect(panel(on)?.textContent).toBe('Sam said so on the phone.');
    expect(panel(on)?.getAttribute('role')).toBe('dialog');
    expect(panel(on)?.getAttribute('aria-label')).toBe('Footnote sam');
    // Under the words, and pulled in from the right edge: 300 wide, less the panel's 120, less a margin of 8.
    expect(panel(on)?.style.top).toBe('46px');
    expect(panel(on)?.style.left).toBe('172px');
  });

  it('is one at a time, and closes on a tap elsewhere, a change to the note, or a scroll', () => {
    tapAt(doc.indexOf('[^sam]') + 2);
    const on = tapAt(doc.indexOf('[^bank]') + 2);
    expect(on.dom.querySelectorAll('.cm-footPanel')).toHaveLength(1);
    expect(panel(on)?.textContent).toBe('The bank statement disagrees.');

    tapAt(3);
    expect(panel(on)).toBeNull();

    tapAt(doc.indexOf('[^sam]') + 2);
    on.dispatch({ changes: { from: 0, insert: 'Now: ' } });
    expect(panel(on)).toBeNull();

    tapAt(doc.indexOf('[^sam]') + 7);
    expect(panel(on)).not.toBeNull();
    on.scrollDOM.dispatchEvent(new Event('scroll'));
    expect(panel(on)).toBeNull();
  });
});

describe('what a tap on a marker finds', () => {
  it('answers the footnote under that position, and nothing elsewhere', () => {
    const { state } = drawn(doc);
    const notes = footnotesIn(doc);
    const at = doc.indexOf('[^sam]') + 2;
    expect(noteAtPos(state, notes, at)?.text).toBe('Sam said so on the phone.');
    expect(noteAtPos(state, notes, 3)).toBeNull();
    // The definition line is not a reference to itself.
    expect(noteAtPos(state, notes, doc.indexOf('[^sam]: ') + 2)).toBeNull();
  });
});
