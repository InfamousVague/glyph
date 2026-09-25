import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { button, show } from '../../test/render.tsx';
import { goBack } from '../core/back.ts';
import { ContextMenu } from './ContextMenu.tsx';

/**
 * The note's own press-and-hold menu, over a real editor: what opens it and what does not, the words it offers, what
 * Paste says when nothing can be pasted, the Style page, and what closes it. The editor here carries none of the
 * note's extensions; the menu reads and writes it through its state alone.
 */

let view: EditorView;
let host: HTMLDivElement;

function editor(doc: string, selection: { anchor: number; head?: number } = { anchor: 0 }): EditorView {
  host = document.createElement('div');
  document.body.appendChild(host);
  view = new EditorView({ state: EditorState.create({ doc, selection }), parent: host });
  return view;
}

/** Waits for the next animation frame, by which the menu has opened on a press it heard before it. */
const frame = () => act(async () => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));

/** A right click or a press and hold, heard as the phone and the desktop both say it. */
async function hold(target: Element = view.contentDOM): Promise<MouseEvent> {
  const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 20, clientY: 20 });
  act(() => {
    target.dispatchEvent(event);
  });
  await frame();
  return event;
}

const menu = () => document.querySelector<HTMLElement>('[role="menu"]');
const words = () => [...(menu()?.querySelectorAll('button') ?? [])].map((b) => b.textContent);

/** Presses a row and lets what it does - a clipboard, a picture - finish. */
async function choose(label: string): Promise<void> {
  await act(async () => button(label, menu()!).click());
}

/** The browser's clipboard, as this test says it is: `undefined` for a browser with none. */
function browserClipboard(clipboard: Partial<Clipboard> | undefined): void {
  Object.defineProperty(navigator, 'clipboard', { configurable: true, value: clipboard });
}

beforeEach(() => {
  browserClipboard(undefined);
  delete window.GlyphHost;
});

afterEach(() => {
  view?.destroy();
  host?.remove();
  vi.useRealTimers();
});

describe('what opens the menu', () => {
  it('opens on a press in the note, and keeps the phone’s own menu away', async () => {
    editor('some words', { anchor: 0, head: 4 });
    show(<ContextMenu view={view} />);
    const event = await hold();
    expect(event.defaultPrevented).toBe(true);
    expect(menu()?.getAttribute('aria-label')).toBe('Note actions');
    expect(words()).toEqual(expect.arrayContaining(['Cut', 'Copy', 'Select all', 'Style']));
  });

  it('does not open over a drawn board or diagram, which have menus of their own', async () => {
    editor('```board\n```');
    show(<ContextMenu view={view} />);
    const board = document.createElement('div');
    board.className = 'cm-board';
    view.dom.appendChild(board);
    const event = await hold(board);
    expect(event.defaultPrevented).toBe(true);
    expect(menu()).toBeNull();
  });

  it('opens after a held press on empty paper, putting the caret where the finger is', () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    editor('words\n\nmore');
    show(<ContextMenu view={view} />);
    // jsdom lays nothing out, so where the finger is in the note is said for it: the empty second line.
    vi.spyOn(view, 'posAtCoords').mockReturnValue(6);
    act(() => {
      view.contentDOM.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerType: 'touch', isPrimary: true, clientX: 5, clientY: 30 }));
    });
    act(() => vi.advanceTimersByTime(479));
    expect(menu()).toBeNull();
    act(() => vi.advanceTimersByTime(1));
    expect(menu()).not.toBeNull();
    expect(view.state.selection.main.head).toBe(6);
  });

  it('leaves a held press on a word to the phone, and one that moves to the scroll', () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    editor('words\n\nmore');
    show(<ContextMenu view={view} />);
    const at = vi.spyOn(view, 'posAtCoords').mockReturnValue(2);
    act(() => {
      view.contentDOM.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerType: 'touch', isPrimary: true, clientX: 5, clientY: 5 }));
    });
    act(() => vi.advanceTimersByTime(1000));
    expect(menu()).toBeNull();
    at.mockReturnValue(6);
    act(() => {
      view.contentDOM.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerType: 'touch', isPrimary: true, clientX: 5, clientY: 30 }));
      view.contentDOM.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, pointerType: 'touch', isPrimary: true, clientX: 5, clientY: 50 }));
    });
    act(() => vi.advanceTimersByTime(1000));
    expect(menu()).toBeNull();
  });
});

describe('Paste', () => {
  it('is offered only where something can read the clipboard', async () => {
    editor('words');
    show(<ContextMenu view={view} />);
    await hold();
    expect(words()).not.toContain('Paste');
  });

  it('puts in the words the activity read, over the selection', async () => {
    window.GlyphHost = { readClipboard: () => JSON.stringify({ text: 'oat milk' }) } as unknown as typeof window.GlyphHost;
    editor('buy milk', { anchor: 4, head: 8 });
    show(<ContextMenu view={view} />);
    await hold();
    await choose('Paste');
    expect(view.state.doc.toString()).toBe('buy oat milk');
    expect(menu()).toBeNull();
  });

  it('hands a picture the activity copied out to the screen, by its path', async () => {
    window.GlyphHost = { readClipboard: () => JSON.stringify({ path: '/cache/shot.png' }) } as unknown as typeof window.GlyphHost;
    const onPasteImage = vi.fn(async () => undefined);
    editor('words');
    show(<ContextMenu view={view} onPasteImage={onPasteImage} />);
    await hold();
    await choose('Paste');
    expect(onPasteImage).toHaveBeenCalledWith('/cache/shot.png');
  });

  it('says what the activity said when it could not read', async () => {
    window.GlyphHost = { readClipboard: () => JSON.stringify({ error: 'The clipboard is locked.' }) } as unknown as typeof window.GlyphHost;
    const say = vi.fn();
    editor('words');
    show(<ContextMenu view={view} say={say} />);
    await hold();
    await choose('Paste');
    expect(say).toHaveBeenCalledWith('The clipboard is locked.');
  });

  it('does not call a clipboard it could not read empty', async () => {
    window.GlyphHost = { readClipboard: () => '{}' } as unknown as typeof window.GlyphHost;
    const say = vi.fn();
    editor('words');
    show(<ContextMenu view={view} say={say} />);
    await hold();
    await choose('Paste');
    expect(say).toHaveBeenCalledWith('Nothing came back from the clipboard. Copy it again, or tap into the note and paste from your keyboard.');
  });

  it('calls it empty when the browser read it and found nothing', async () => {
    browserClipboard({ readText: async () => '' });
    const say = vi.fn();
    editor('words');
    show(<ContextMenu view={view} say={say} />);
    await hold();
    await choose('Paste');
    expect(say).toHaveBeenCalledWith('Nothing on the clipboard to paste. Copy the words again, then hold here.');
  });

  it('says it could not reach the clipboard when the browser refuses', async () => {
    browserClipboard({ readText: () => Promise.reject(new Error('NotAllowedError')) });
    const say = vi.fn();
    editor('words');
    show(<ContextMenu view={view} say={say} />);
    await hold();
    await choose('Paste');
    expect(say).toHaveBeenCalledWith('Ghost.md couldn’t reach the clipboard here. Tap into the note and paste from your keyboard instead.');
    expect(view.state.doc.toString()).toBe('words');
  });
});

describe('the actions', () => {
  it('cuts the selection onto the clipboard', async () => {
    const writeText = vi.fn(async () => undefined);
    browserClipboard({ writeText });
    editor('buy oat milk', { anchor: 4, head: 8 });
    show(<ContextMenu view={view} />);
    await hold();
    await choose('Cut');
    expect(writeText).toHaveBeenCalledWith('oat ');
    expect(view.state.doc.toString()).toBe('buy milk');
  });

  it('opens find with the selected words', async () => {
    const onFind = vi.fn();
    editor('buy oat milk', { anchor: 4, head: 7 });
    show(<ContextMenu view={view} onFind={onFind} />);
    await hold();
    await choose('Find');
    expect(onFind).toHaveBeenCalledWith('oat');
  });

  it('makes a board of the list the press is in, and says so', async () => {
    const say = vi.fn();
    editor('- [ ] milk\n- [x] eggs', { anchor: 2 });
    show(<ContextMenu view={view} say={say} />);
    await hold();
    await choose('Board from list');
    expect(view.state.doc.toString()).toContain('```board');
    expect(say).toHaveBeenCalledWith('2 items are now a board, 1 in Done.');
  });

  it('adds an item to its list’s board, and copies the board whole', async () => {
    const say = vi.fn();
    const writeText = vi.fn(async () => undefined);
    browserClipboard({ writeText });
    editor('- [ ] milk\n- [ ] eggs', { anchor: 2 });
    show(<ContextMenu view={view} say={say} />);
    await hold();
    await choose('Board from list');
    act(() => view.dispatch({ changes: { from: view.state.doc.length, insert: '\n- [ ] bread' }, selection: { anchor: view.state.doc.length + 4 } }));
    await hold();
    await choose('Add to board');
    expect(say).toHaveBeenLastCalledWith('Added to To do.');
    act(() => view.dispatch({ selection: { anchor: 0 } }));
    await hold();
    await choose('Copy board');
    expect(writeText).toHaveBeenCalledWith(expect.stringContaining('```board'));
  });

  it('adds the line it was offered for, wherever the caret has gone while the menu was open', async () => {
    const say = vi.fn();
    editor('# List\n\n- [ ] milk\n- [ ] eggs', { anchor: 10 });
    show(<ContextMenu view={view} say={say} />);
    await hold();
    await choose('Board from list');
    act(() => view.dispatch({ changes: { from: view.state.doc.length, insert: '\n- [ ] bread' }, selection: { anchor: view.state.doc.length + 4 } }));
    const bread = view.state.doc.lines;
    await hold();
    // A keyboard on a desktop keeps the editor's focus while the menu is up, so the caret can move under it.
    act(() => view.dispatch({ selection: { anchor: 0 } }));
    await choose('Add to board');
    expect(say).toHaveBeenLastCalledWith('Added to To do.');
    expect(view.state.doc.line(bread).text).toMatch(/^- \[ \] bread \^\S+$/);
  });

  it('sends the line’s words, without the item’s marks, where a plugin takes them', async () => {
    const run = vi.fn();
    editor('- [ ] Buy milk ^milk', { anchor: 3 });
    show(<ContextMenu view={view} send={{ label: 'Notion', run }} />);
    await hold();
    await choose('Notion');
    expect(run).toHaveBeenCalledWith('Buy milk');
  });
});

describe('the Style page', () => {
  it('keeps a pressed style on the page, lit, and goes back', async () => {
    editor('buy milk', { anchor: 4, head: 8 });
    show(<ContextMenu view={view} />);
    await hold();
    await choose('Style');
    expect(menu()?.getAttribute('aria-label')).toBe('Styles');
    await choose('Bold');
    expect(view.state.doc.toString()).toBe('buy **milk**');
    expect(button('Bold').getAttribute('aria-checked')).toBe('true');
    await choose("Back to the note's actions");
    expect(menu()?.getAttribute('aria-label')).toBe('Note actions');
  });

  it('closes the menu for an insert, which leaves nothing to keep lit', async () => {
    editor('words', { anchor: 5 });
    show(<ContextMenu view={view} />);
    await hold();
    await choose('Style');
    await choose('Rule');
    expect(menu()).toBeNull();
    expect(view.state.doc.toString()).toContain('---');
  });
});

describe('what closes the menu', () => {
  it('a touch anywhere else, but not on the menu', async () => {
    editor('words');
    show(<ContextMenu view={view} />);
    await hold();
    act(() => {
      menu()!.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    });
    expect(menu()).not.toBeNull();
    act(() => {
      document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    });
    expect(menu()).toBeNull();
  });

  it('a scroll of the note, but not of the menu’s own band', async () => {
    editor('words');
    show(<ContextMenu view={view} />);
    await hold();
    act(() => {
      menu()!.firstElementChild!.dispatchEvent(new Event('scroll'));
    });
    expect(menu()).not.toBeNull();
    act(() => {
      view.scrollDOM.dispatchEvent(new Event('scroll'));
    });
    expect(menu()).toBeNull();
  });

  it('the back gesture', async () => {
    editor('words');
    show(<ContextMenu view={view} />);
    await hold();
    act(() => {
      goBack();
    });
    expect(menu()).toBeNull();
  });
});
