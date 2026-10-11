import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { rerender, show } from '../../test/render.tsx';
import type { CaptureLanding } from '../capture/landing.ts';
import { pendingTag, setPendingTag } from '../core/location.ts';
import { useLanding } from './useLanding.ts';

/** The landing's toast as the note's screen asks for it, with its toast and dismiss watched. */
function Probe({ noteId, landing, view = null, toast, dismiss }: { noteId: string; landing?: CaptureLanding & { key: number }; view?: EditorView | null; toast: (options: { action?: { onPress: () => void } }) => void; dismiss: () => void }) {
  useLanding(noteId, landing, view, { toast, dismiss });
  return null;
}

let view: EditorView | null = null;
beforeEach(() => localStorage.clear());
afterEach(() => {
  view?.destroy();
  view = null;
});

describe('the toast of a note a recording wrote into', () => {
  it('goes when the note is left, so its Undo never takes out words no longer on screen', () => {
    const toast = vi.fn();
    const dismiss = vi.fn();
    const landing = { noteId: 'house', title: 'House TODOs', blocks: ['- [ ] Call Sam'], others: [], made: [], key: 1 };
    show(<Probe noteId="house" landing={landing} toast={toast} dismiss={dismiss} />);
    expect(toast).toHaveBeenCalledWith(expect.objectContaining({ message: 'Added to House TODOs', action: expect.objectContaining({ label: 'Undo' }) }));
    expect(dismiss).not.toHaveBeenCalled();
    rerender(<Probe noteId="work" toast={toast} dismiss={dismiss} />);
    expect(dismiss).toHaveBeenCalledTimes(1);
  });

  it('on Undo drops a tag waiting for the words it takes out, and takes the tag with them from a note left with nothing else', async () => {
    let undo: (() => void) | undefined;
    const toast = vi.fn((options: { action?: { onPress: () => void } }) => {
      undo ??= options.action?.onPress;
    });
    view = new EditorView({ state: EditorState.create({ doc: '---\nlocation: 51.5074,-0.1278\n---\n# Said\n\n- [ ] Call Sam' }) });
    setPendingTag('n1', { lat: 51.5074, lon: -0.1278, place: null, rough: false });
    const landing = { noteId: 'n1', title: 'Said', blocks: ['# Said', '- [ ] Call Sam'], others: [], made: [], key: 1 };
    show(<Probe noteId="n1" landing={landing} view={view} toast={toast} dismiss={() => undefined} />);
    await act(async () => {
      undo!();
      await Promise.resolve();
    });
    expect(view.state.doc.toString()).toBe('');
    expect(pendingTag('n1')).toBeNull();
  });

  it('on Undo leaves a tag whose note still has words', async () => {
    let undo: (() => void) | undefined;
    const toast = vi.fn((options: { action?: { onPress: () => void } }) => {
      undo ??= options.action?.onPress;
    });
    view = new EditorView({ state: EditorState.create({ doc: '---\nlocation: 51.5074,-0.1278\n---\n# House\n\n- [ ] Fix the gutter\n- [ ] Call Sam' }) });
    const landing = { noteId: 'n1', title: 'House', blocks: ['- [ ] Call Sam'], others: [], made: [], key: 1 };
    show(<Probe noteId="n1" landing={landing} view={view} toast={toast} dismiss={() => undefined} />);
    await act(async () => {
      undo!();
      await Promise.resolve();
    });
    expect(view.state.doc.toString()).toBe('---\nlocation: 51.5074,-0.1278\n---\n# House\n\n- [ ] Fix the gutter');
  });
});
