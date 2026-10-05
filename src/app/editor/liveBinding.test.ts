import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it } from 'vitest';
import { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate } from 'y-protocols/awareness';
import * as Y from 'yjs';
import { bindLive, unbindLive } from './liveBinding.ts';
import { localUndo, undoSlot } from './undoSlot.ts';

let view: EditorView | null = null;

afterEach(() => {
  view?.destroy();
  view = null;
});

/** A note's editor as Editor.tsx builds it, undo in its slot; and the live document another device writes into. */
function open(words: string, live: string) {
  view = new EditorView({ state: EditorState.create({ doc: words, extensions: [undoSlot.of(localUndo())] }), parent: document.body });
  const text = new Y.Doc().getText('note');
  text.insert(0, live);
  return { on: view, text, session: { text } };
}
/** Words from another device, arriving as the session applies them: under an origin of its own, never this editor's. */
const arrive = (text: Y.Text, words: string) => text.doc!.transact(() => text.insert(0, words), 'relay');
const type = (on: EditorView, words: string) => on.dispatch({ changes: { from: on.state.doc.length, insert: words }, userEvent: 'input.type' });
/** Cmd-Z or Ctrl-Z, whichever this platform's undo is. */
const undoKey = (on: EditorView) => on.contentDOM.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', ctrlKey: true, metaKey: /Mac/.test(navigator.platform), bubbles: true, cancelable: true }));

describe('a note bound to its live document', () => {
  it('is brought to the live words first, then follows them both ways', () => {
    const { on, text, session } = open('An older copy', 'Typed on the phone');
    bindLive(on, session);
    expect(on.state.doc.toString()).toBe('Typed on the phone');
    type(on, '!');
    expect(text.toString()).toBe('Typed on the phone!');
    arrive(text, 'Mac: ');
    expect(on.state.doc.toString()).toBe('Mac: Typed on the phone!');
  });

  it('draws a member’s caret and selection in their colour with their handle on it, given an awareness', () => {
    const { on, text } = open('Hello world', 'Hello world');
    const awareness = new Awareness(text.doc!);
    awareness.setLocalStateField('user', { name: 'matt', hue: 'rose', color: 'red', colorLight: 'pink' });
    bindLive(on, { text, awareness });
    // sam's device, on the same document: a selection over "world", as y-codemirror puts it in their state (the
    // relative positions themselves, which cross as their JSON, nulls and all).
    const theirs = new Y.Doc();
    Y.applyUpdate(theirs, Y.encodeStateAsUpdate(text.doc!));
    const sam = new Awareness(theirs);
    const words = theirs.getText('note');
    sam.setLocalState({
      user: { name: 'sam', hue: 'sea', color: 'blue', colorLight: 'lightblue' },
      cursor: { anchor: Y.createRelativePositionFromTypeIndex(words, 6), head: Y.createRelativePositionFromTypeIndex(words, 11) },
    });
    applyAwarenessUpdate(awareness, encodeAwarenessUpdate(sam, [sam.clientID]), 'relay');
    const caret = on.dom.querySelector<HTMLElement>('.cm-ySelectionCaret');
    expect(caret?.getAttribute('style')).toContain('blue');
    expect(caret?.querySelector('.cm-ySelectionInfo')?.textContent).toBe('sam');
    expect(on.dom.querySelector<HTMLElement>('.cm-ySelection')?.getAttribute('style')).toContain('lightblue');
    // This editor's own selection goes into the awareness for the others, as relative positions.
    on.focus();
    on.dispatch({ selection: { anchor: 2 } });
    const mine = awareness.getLocalState()?.cursor as { anchor: unknown } | undefined;
    expect(mine?.anchor).toBeDefined();
    sam.destroy();
    awareness.destroy();
  });

  it('undoes only this person’s typing while live, and with its own history again once unbound', () => {
    const { on, text, session } = open('Buy', 'Buy');
    bindLive(on, session);
    type(on, ' milk');
    arrive(text, 'Sam: ');
    undoKey(on);
    // The other device's words stay; only what was typed here is taken back.
    expect(on.state.doc.toString()).toBe('Sam: Buy');

    unbindLive(on);
    type(on, ' eggs');
    expect(text.toString()).toBe('Sam: Buy');
    undoKey(on);
    expect(on.state.doc.toString()).toBe('Sam: Buy');
  });
});
