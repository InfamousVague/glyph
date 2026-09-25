import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { IMAGE_READY } from '../core/images.ts';
import { inlineImages, insertImage, insertImageAt, reserveImageSpot } from './images.ts';

/** Keeping a picture is the store's (core/images.ts); here it answers a name, or refuses, as the test says. */
const kept = vi.hoisted(() => ({ names: [] as string[], refuse: null as string | null, asked: 0 }));
vi.mock('../core/images.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/images.ts')>()),
  saveImageFile: async () => {
    kept.asked += 1;
    if (kept.refuse) throw new Error(kept.refuse);
    const name = kept.names.shift();
    if (!name) throw new Error('no name left to give');
    return name;
  },
}));

function view(doc: string, caret: number, onError?: (message: string) => void): EditorView {
  const state = EditorState.create({ doc, selection: { anchor: caret }, extensions: [inlineImages(onError)] });
  return new EditorView({ state, parent: document.createElement('div') });
}

describe('putting a picture into a note', () => {
  it('goes under the line the caret is on, never splitting it', () => {
    const v = view('Book the cabin by Friday', 8);
    insertImage(v, 'a.jpg');
    expect(v.state.doc.toString()).toBe('Book the cabin by Friday\n![](image/a.jpg)\n');
  });

  it('takes an empty line', () => {
    const v = view('Trip\n\nMore', 5);
    insertImage(v, 'a.jpg');
    expect(v.state.doc.toString()).toBe('Trip\n![](image/a.jpg)\n\nMore');
  });

  it('lands where the caret was when the paste happened, whatever changed since', () => {
    const doc = '![](image/first.jpg)\n\no';
    const v = view(doc, doc.length);
    const spot = reserveImageSpot(v);
    // The caret jumps into the first line, and a word is typed above, while the picture is saved.
    v.dispatch({ selection: { anchor: 12 } });
    v.dispatch({ changes: { from: 0, insert: 'Title\n' } });
    insertImageAt(v, spot, 'second.jpg');
    expect(v.state.doc.toString()).toBe('Title\n![](image/first.jpg)\n\no\n![](image/second.jpg)\n');
  });
});

describe('a picture shown in the note', () => {
  it('is drawn under its line, the markdown left as it is, and drawn again when the picture arrives', () => {
    const v = view('Cabin\n![the porch](image/porch.jpg)\nafter', 0);
    const figure = () => v.contentDOM.querySelector('figure');
    expect(figure()?.querySelector('img')?.alt).toBe('the porch');
    expect(v.contentDOM.textContent).toContain('![the porch](image/porch.jpg)');
    const before = figure();
    window.dispatchEvent(new Event(IMAGE_READY));
    expect(figure()).not.toBe(before);
    v.destroy();
  });
});

describe('pasting a picture', () => {
  afterEach(() => {
    kept.names = [];
    kept.refuse = null;
    kept.asked = 0;
  });

  /** A paste carrying `files`, as the clipboard hands them over, or as items, the way some keyboards do. */
  function paste(target: EditorView, files: File[], asItems = false): Event {
    const event = new Event('paste', { bubbles: true, cancelable: true });
    // The words of the paste, which the editor's own handling reads when this one leaves the paste to it: none.
    const getData = () => '';
    const clipboardData = asItems
      ? { files: [], items: files.map((file) => ({ kind: 'file', type: file.type, getAsFile: () => file })), getData }
      : { files, items: [], getData };
    Object.defineProperty(event, 'clipboardData', { value: clipboardData });
    target.contentDOM.dispatchEvent(event);
    return event;
  }
  const picture = (name: string) => new File(['…'], name, { type: 'image/jpeg' });

  it('keeps each picture and puts them in at the caret, one after another, and nothing else from the paste', async () => {
    kept.names = ['one.jpg', 'two.jpg'];
    const v = view('Trip notes', 4);
    const event = paste(v, [picture('a.jpg'), picture('b.jpg')]);
    expect(event.defaultPrevented).toBe(true);
    await vi.waitFor(() => expect(v.state.doc.toString()).toBe('Trip notes\n![](image/one.jpg)\n![](image/two.jpg)\n'));
    v.destroy();
  });

  it('takes a picture a keyboard hands over as an item rather than a file', async () => {
    kept.names = ['kb.jpg'];
    const v = view('', 0);
    paste(v, [picture('a.jpg')], true);
    await vi.waitFor(() => expect(v.state.doc.toString()).toBe('![](image/kb.jpg)\n'));
    v.destroy();
  });

  it('leaves a paste with no picture to the editor, and says why a picture could not be kept', async () => {
    const said: string[] = [];
    const v = view('Trip', 4, (message) => said.push(message));
    paste(v, [new File(['hi'], 'note.txt', { type: 'text/plain' })]);
    expect(kept.asked).toBe(0);
    kept.refuse = 'The disk is full.';
    paste(v, [picture('a.jpg')]);
    await vi.waitFor(() => expect(said).toEqual(['The disk is full.']));
    expect(v.state.doc.toString()).toBe('Trip');
    v.destroy();
  });
});
