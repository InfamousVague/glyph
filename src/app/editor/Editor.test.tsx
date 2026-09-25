import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { EditorView } from '@codemirror/view';
import { rerender, show, unmount } from '../../test/render.tsx';
import { Editor } from './Editor.tsx';

/**
 * The one CodeMirror host: the view is made once and React never touches what is inside it. So `value` loads a new
 * document only when it differs from what the view holds - which is how the echo of its own `onChange` is ignored -
 * and the props that may change are swapped in place, the view and its selection kept.
 */

function mount(props: Partial<Parameters<typeof Editor>[0]> = {}) {
  let view: EditorView | null = null;
  const onView = vi.fn((made: EditorView | null) => {
    view = made ?? view;
  });
  const element = (over: Partial<Parameters<typeof Editor>[0]> = {}) => <Editor value="first words" onChange={() => {}} dark={false} assist onView={onView} {...props} {...over} />;
  show(element());
  return { view: () => view!, onView, element };
}

describe('the editor', () => {
  it('hands its view up once it is made, and null as it goes', () => {
    const { onView, view } = mount();
    expect(onView).toHaveBeenCalledTimes(1);
    expect(view().state.doc.toString()).toBe('first words');
    unmount();
    expect(onView).toHaveBeenLastCalledWith(null);
  });

  it('says every change, and takes the echo of its own change back as nothing', () => {
    const onChange = vi.fn();
    const { view, element } = mount({ onChange });
    act(() => view().dispatch({ changes: { from: 11, insert: ' and more' }, selection: { anchor: 20 } }));
    expect(onChange).toHaveBeenLastCalledWith('first words and more');
    // The parent passes back what it was told: the document the view already holds, so nothing is dispatched.
    const dispatch = vi.spyOn(view(), 'dispatch');
    rerender(element({ onChange, value: 'first words and more' }));
    expect(dispatch).not.toHaveBeenCalled();
    expect(view().state.selection.main.head).toBe(20);
  });

  it('loads a different document when handed one, keeping the caret inside it', () => {
    const { view, element } = mount();
    act(() => view().dispatch({ selection: { anchor: 11 } }));
    rerender(element({ value: 'short' }));
    expect(view().state.doc.toString()).toBe('short');
    expect(view().state.selection.main.head).toBe(5);
  });

  it('stops being typed into when read-only, without making a new view', () => {
    const { view, element } = mount();
    const dom = view().dom;
    expect(view().contentDOM.getAttribute('contenteditable')).toBe('true');
    rerender(element({ readOnly: true }));
    expect(view().dom).toBe(dom);
    expect(view().contentDOM.getAttribute('contenteditable')).toBe('false');
    expect(view().state.readOnly).toBe(true);
  });

  it('turns the input aids on and off in place', () => {
    const { view, element } = mount();
    expect(view().contentDOM.getAttribute('autocapitalize')).toBe('sentences');
    rerender(element({ assist: false }));
    expect(view().contentDOM.getAttribute('autocapitalize')).toBe('off');
    expect(view().contentDOM.getAttribute('spellcheck')).toBe('false');
  });

  it('says which view it draws, for the page’s styles', () => {
    const { element } = mount({ display: 'formatted' });
    expect(document.querySelector('[data-view]')?.getAttribute('data-view')).toBe('formatted');
    rerender(element({ display: 'mixed' }));
    expect(document.querySelector('[data-view]')?.getAttribute('data-view')).toBe('mixed');
  });
});
