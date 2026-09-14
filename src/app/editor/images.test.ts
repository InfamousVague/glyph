import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { inlineImages, insertImage, insertImageAt, reserveImageSpot } from './images.ts';

// jsdom has no layout: CodeMirror's scrolling asks ranges for rectangles it cannot give.
Range.prototype.getClientRects = () => ({ length: 0, item: () => null, [Symbol.iterator]: [][Symbol.iterator] }) as unknown as DOMRectList;
Range.prototype.getBoundingClientRect = () => new DOMRect();

function view(doc: string, caret: number): EditorView {
  const state = EditorState.create({ doc, selection: { anchor: caret }, extensions: [inlineImages()] });
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
