import { describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { canvasNoteBody } from '../canvas/jsonCanvas.ts';
import { canvasFrames, framesIn, refreshCanvasFrames } from './canvasFrames.ts';

describe('embeds in a note', () => {
  it('finds a line that is only ![[Title]], the title being what is before any #', () => {
    expect(framesIn('# Trip\n\n![[Cabin, laid out]]\n\nwords')).toEqual([{ line: 3, title: 'Cabin, laid out' }]);
    expect(framesIn('  ![[Map#^card]]  ')).toEqual([{ line: 1, title: 'Map' }]);
    expect(framesIn('![[One]]\n![[Two]]').map((f) => f.title)).toEqual(['One', 'Two']);
  });

  it('leaves a link without the !, an embed inside a sentence, and an empty one alone', () => {
    expect(framesIn('[[Map]]')).toEqual([]);
    expect(framesIn('see ![[Map]] here')).toEqual([]);
    expect(framesIn('![[ ]]')).toEqual([]);
    expect(framesIn('![[#^card]]')).toEqual([]);
  });
});

describe('the frame', () => {
  const canvas = canvasNoteBody('Map', { nodes: [{ id: 'a', type: 'text', text: 'A card', x: 0, y: 0, width: 120, height: 60 }], edges: [] });
  const bodies: Record<string, string> = { Map: canvas, Words: '# Words\n\nJust words.' };

  function make(doc: string) {
    const open = vi.fn();
    const parent = document.createElement('div');
    document.body.appendChild(parent);
    let dark = false;
    const view = new EditorView({
      state: EditorState.create({
        doc,
        extensions: [canvasFrames({ body: (title) => bodies[title] ?? null, known: (title) => title in bodies, open, dark: () => dark })],
      }),
      parent,
    });
    return { view, open, parent, paint: (next: boolean) => (dark = next) };
  }

  it('draws a canvas named on its own line as a frame with its name and an Open, and leaves a note of words as the link', () => {
    const { view, open, parent } = make('![[Map]]\n\n![[Words]]\n\n![[Nowhere]]');
    const frames = parent.querySelectorAll('.cm-canvasFrame');
    expect(frames.length).toBe(1);
    expect(frames[0]?.getAttribute('aria-label')).toBe('Canvas: Map');
    expect(frames[0]?.querySelector('.cm-canvasFrameName')?.textContent).toBe('Map');
    frames[0]?.querySelector<HTMLButtonElement>('.cm-canvasFrameOpen')?.click();
    expect(open).toHaveBeenCalledWith('Map');
    // The line itself is gone from the page; the two that name no canvas stay as typed.
    expect(parent.textContent).not.toContain('![[Map]]');
    expect(parent.textContent).toContain('![[Words]]');
    expect(parent.textContent).toContain('![[Nowhere]]');
    view.destroy();
    parent.remove();
  });

  it('is drawn again, not kept, when the app is painted the other way', () => {
    const { view, parent, paint } = make('![[Map]]');
    const before = parent.querySelector('.cm-canvasFrame');
    view.dispatch({ effects: refreshCanvasFrames.of(null) });
    // Nothing changed: the same frame stays.
    expect(parent.querySelector('.cm-canvasFrame')).toBe(before);
    paint(true);
    view.dispatch({ effects: refreshCanvasFrames.of(null) });
    expect(parent.querySelector('.cm-canvasFrame')).not.toBe(before);
    view.destroy();
    parent.remove();
  });
});
