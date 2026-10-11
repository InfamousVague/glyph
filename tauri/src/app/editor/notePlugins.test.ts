import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { history, undo } from '@codemirror/commands';
import { noteEditing } from './notePlugins.ts';

/**
 * The note as plugins change it: through the editor, one line at a time and one undo each, reading the editor's words
 * when there is one and the screen's live body when there is not.
 */

let view: EditorView | null = null;

afterEach(() => {
  view?.destroy();
  view = null;
});

describe('the note, as plugins change it', () => {
  it('rewrites the first line it is asked for, and only that one, as one undo', () => {
    view = new EditorView({ state: EditorState.create({ doc: '- [ ] milk\n- [ ] eggs\n- [ ] milk', extensions: [history()] }), parent: document.body });
    const editing = noteEditing('n1', view, () => 'unused', () => undefined);
    const seen: number[] = [];
    const found = editing.replaceLine(
      (text, line) => {
        seen.push(line);
        return text.includes('milk');
      },
      (text) => `${text} [notion](https://notion.so/1)`,
    );
    expect(found).toBe(true);
    expect(seen).toEqual([1]);
    expect(view.state.doc.toString()).toBe('- [ ] milk [notion](https://notion.so/1)\n- [ ] eggs\n- [ ] milk');
    undo(view);
    expect(view.state.doc.toString()).toBe('- [ ] milk\n- [ ] eggs\n- [ ] milk');
  });

  it('answers false when no line is the one, and writes nothing', () => {
    view = new EditorView({ state: EditorState.create({ doc: '- [ ] eggs' }), parent: document.body });
    const editing = noteEditing('n1', view, () => 'unused', () => undefined);
    expect(editing.replaceLine(() => false, () => 'x')).toBe(false);
    expect(view.state.doc.toString()).toBe('- [ ] eggs');
  });

  it('reads the live body when no editor is drawn, and can change nothing then', () => {
    const say = vi.fn();
    const editing = noteEditing('n1', null, () => '{"nodes":[]}', say);
    expect(editing.body()).toBe('{"nodes":[]}');
    expect(editing.replaceLine(() => true, () => 'x')).toBe(false);
    editing.say('Sent.');
    expect(say).toHaveBeenCalledWith('Sent.');
    expect(editing.noteId).toBe('n1');
  });
});
