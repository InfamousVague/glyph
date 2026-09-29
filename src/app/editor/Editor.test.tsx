import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { EditorView } from '@codemirror/view';
import { rerender, show, unmount } from '../../test/render.tsx';
import { Editor } from './Editor.tsx';
import { WISP_EDGE_FOOT_CLEAR } from '../art/wispEdge.ts';

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

  it('draws the view it is given, swapped in place, and says which for the page’s styles', () => {
    const { view, element } = mount({ value: '**milk** and eggs', display: 'formatted' });
    const dom = view().dom;
    // Formatted hides the marks that only say how the words look (editor/viewMode.ts); the mixed page keeps them.
    expect(view().contentDOM.textContent).toBe('milk and eggs');
    expect(document.querySelector('[data-view]')?.getAttribute('data-view')).toBe('formatted');
    rerender(element({ value: '**milk** and eggs', display: 'mixed' }));
    expect(view().dom).toBe(dom);
    expect(view().contentDOM.textContent).toBe('**milk** and eggs');
    expect(document.querySelector('[data-view]')?.getAttribute('data-view')).toBe('mixed');
  });

  it('has a + beside the line only where one is asked for, and never on a note drawn small', () => {
    const hooks = { allowed: () => true, onOpen: vi.fn(), onClose: vi.fn(), onKey: () => false };
    mount();
    expect(document.querySelectorAll('.cm-plus')).toHaveLength(0);
    unmount();
    mount({ plus: hooks });
    expect(document.querySelectorAll('.cm-plus')).toHaveLength(1);
    unmount();
    mount({ plus: hooks, peek: true, readOnly: true });
    expect(document.querySelectorAll('.cm-plus')).toHaveLength(0);
  });

  it('draws a place’s map card only where it is asked to, and folds the line to its name everywhere', () => {
    const value = 'Lunch\n[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';
    mount({ value, readOnly: true });
    expect(document.querySelectorAll('.cm-placeCard')).toHaveLength(0);
    expect(document.querySelectorAll('.cm-line')[1]?.textContent).toBe('Cais do Sodré, Lisbon');
    unmount();
    mount({ value, readOnly: true, places: 'ask' });
    expect(document.querySelectorAll('.cm-placeCard')).toHaveLength(1);
  });
});

describe('the caret kept out of the foot smoke', () => {
  const bottomMargin = (view: EditorView) =>
    view.state
      .facet(EditorView.scrollMargins)
      .map((margins) => margins(view)?.bottom ?? 0)
      .reduce((most, each) => Math.max(most, each), 0);

  it('asks to be scrolled that far clear of the bottom as it is typed, and follows a change', () => {
    const { view, element } = mount({ footClear: WISP_EDGE_FOOT_CLEAR });
    expect(WISP_EDGE_FOOT_CLEAR).toBe(24 + 11 + 2 * 29);
    expect(bottomMargin(view())).toBe(WISP_EDGE_FOOT_CLEAR);
    rerender(element({ footClear: 0 }));
    expect(bottomMargin(view())).toBe(0);
    unmount();
  });

  it('asks for nothing where no page smokes under it', () => {
    const { view } = mount();
    expect(bottomMargin(view())).toBe(0);
    unmount();
  });

  it('holds the clearance to a third of the room on a short page, so the line is not lifted under the header', () => {
    const { view } = mount({ footClear: WISP_EDGE_FOOT_CLEAR });
    // The page that scrolls around the note: 210px tall, 80 of them under the header, as a phone on its side with
    // the keyboard up.
    const page = document.createElement('div');
    page.dataset.scrolls = '';
    page.style.paddingTop = '80px';
    let tall = 210;
    Object.defineProperty(page, 'clientHeight', { get: () => tall });
    view().dom.replaceWith(page);
    page.append(view().dom);
    expect(bottomMargin(view())).toBeCloseTo(130 / 3);
    // A tall page gives the whole clearance.
    tall = 900;
    expect(bottomMargin(view())).toBe(WISP_EDGE_FOOT_CLEAR);
    unmount();
  });
});
