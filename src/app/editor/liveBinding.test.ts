import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it } from 'vitest';
import * as Y from 'yjs';
import type { LiveSession } from '../core/live/session.ts';
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
  return { on: view, text, session: { text } as unknown as LiveSession };
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
