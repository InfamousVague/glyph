import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { show, unmount } from '../../test/render.tsx';
import { inlineImages } from './images.ts';
import { useNotePictures, type NotePictures } from './useNotePictures.ts';

/**
 * Pictures put into the open note, at the caret as it was when the picker opened, and the one line on the note that
 * says when a picture did not come in - said once, and gone after a few seconds.
 */

const picked = vi.hoisted(() => ({ pick: vi.fn<() => Promise<string | null>>(), adopt: vi.fn<(path: string) => Promise<string | null>>() }));

vi.mock('../core/images.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/images.ts')>()),
  pickImage: () => picked.pick(),
  adoptImagePath: (path: string) => picked.adopt(path),
}));

let view: EditorView;
let pictures: NotePictures;

function Pictures() {
  pictures = useNotePictures(view);
  return <p data-problem="">{pictures.problem}</p>;
}

const problem = () => document.querySelector('[data-problem]')?.textContent;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  view = new EditorView({ state: EditorState.create({ doc: 'first\nsecond', selection: { anchor: 5 }, extensions: [inlineImages(() => undefined)] }), parent: document.body });
  show(<Pictures />);
});

afterEach(() => {
  unmount();
  view.destroy();
  vi.useRealTimers();
});

describe('pictures in the note', () => {
  it('puts the chosen picture where the caret was when the picker opened, though it moved since', async () => {
    let choose: (name: string) => void = () => undefined;
    picked.pick.mockImplementation(() => new Promise((resolve) => (choose = resolve)));
    let adding: Promise<void> = Promise.resolve();
    act(() => {
      adding = pictures.addPhoto();
    });
    // The picker leaves the app; the caret is somewhere else when it comes back.
    act(() => view.dispatch({ selection: { anchor: view.state.doc.length } }));
    await act(async () => {
      choose('pic.jpg');
      await adding;
    });
    expect(view.state.doc.toString()).toContain('first\n![](image/pic.jpg)');
  });

  it('puts in a picture the activity copied out of the clipboard', async () => {
    picked.adopt.mockResolvedValue('clip.png');
    await act(() => pictures.pasteImage('/cache/clip.png'));
    expect(picked.adopt).toHaveBeenCalledWith('/cache/clip.png');
    expect(view.state.doc.toString()).toContain('![](image/clip.png)');
  });

  it('says why a picture did not come in, once, and then gets out of the way', async () => {
    picked.pick.mockRejectedValue(new Error('That picture could not be read.'));
    await act(() => pictures.addPhoto());
    expect(problem()).toBe('That picture could not be read.');
    expect(view.state.doc.toString()).toBe('first\nsecond');
    act(() => vi.advanceTimersByTime(5999));
    expect(problem()).toBe('That picture could not be read.');
    act(() => vi.advanceTimersByTime(1));
    expect(problem()).toBe('');
  });

  it('puts nothing in when nothing was chosen', async () => {
    picked.pick.mockResolvedValue(null);
    await act(() => pictures.addPhoto());
    expect(view.state.doc.toString()).toBe('first\nsecond');
    expect(problem()).toBe('');
  });

  it('carries a plugin’s sentence on the same line', () => {
    act(() => pictures.say('Sent to Notion.'));
    expect(problem()).toBe('Sent to Notion.');
  });
});
